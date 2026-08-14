import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:passone_app/api/client.dart';
import 'package:passone_app/crypto/kdf.dart';
import 'package:passone_app/crypto/models.dart';
import 'package:passone_app/crypto/vault_crypto.dart';
import 'package:passone_app/state/biometrics.dart';
import 'package:passone_app/state/session.dart';
import 'package:passone_app/state/settings.dart';

class _FakeBiometrics extends BiometricService {
  _FakeBiometrics()
      : super(auth: LocalAuthentication(), storage: const FlutterSecureStorage());

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<BiometricReadResult> authenticate() async =>
      BiometricReadResult.success;
}

/// Scriptable fake of the PassOne HTTP server.
class _FakeServer {
  bool online = true;
  int conflictNext = 0;
  int revision = 3;
  late Uint8List vaultKey;
  Uint8List salt = VaultCrypto.randomBytes(16);
  Uint8List wrappedKey = VaultCrypto.randomBytes(32);
  VaultData remote = VaultData();

  http.Client client() => MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'PUT' && path.endsWith('/api/v1/vault')) {
          if (!online) throw http.ClientException('connection refused');
          if (conflictNext > 0) {
            conflictNext--;
            return http.Response(
                jsonEncode({
                  'error': 'revision conflict',
                  'code': 'revision_conflict',
                  'current_revision': revision + 1,
                }),
                409,
                request: req);
          }
          revision += 1;
          return http.Response(jsonEncode({'vault_revision': revision}), 200,
              request: req);
        }
        if (req.method == 'GET' && path.endsWith('/api/v1/vault')) {
          if (!online) throw http.ClientException('connection refused');
          final (blob, nonce) = await VaultCrypto.encrypt(
              vaultKey, VaultCrypto.encodeJson(remote.toJson()));
          return http.Response(
              jsonEncode({
                'vault_blob_b64': VaultCrypto.bytesToB64(blob),
                'vault_nonce_b64': VaultCrypto.bytesToB64(nonce),
                'vault_key_wrapped_b64': VaultCrypto.bytesToB64(wrappedKey),
                'vault_key_wrapped_recov_b64': null,
                'recovery_enabled': false,
                'salt_b64': VaultCrypto.bytesToB64(salt),
                'kdf': KdfParams.pbkdf2(iterations: 1000).toJson(),
                'vault_revision': revision,
              }),
              200,
              request: req);
        }
        return http.Response('{"error":"not found","code":"not_found"}', 404);
      });
}

class _PendingController extends SessionController {
  final _FakeServer server;

  _PendingController(super.repo, {super.biometrics, required this.server})
      : super();

  @override
  PassOneClient get client =>
      PassOneClient(baseUrl: 'http://fake', httpClient: server.client());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmpDir = Directory.systemTemp.createTempSync('passone_pending_test');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return tmpDir.path;
        }
        return null;
      },
    );
  });

  tearDownAll(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  Future<void> waitFor(bool Function() cond) async {
    for (var i = 0; i < 200; i++) {
      if (cond()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('timed out waiting for the condition');
  }

  Future<CachedVault> buildCache() async {
    final password = 'master-password';
    final salt = VaultCrypto.randomBytes(16);
    final kdf = KdfParams.pbkdf2(iterations: 1000);
    final kek = await Kdf().derive(password, salt, kdf);
    final vaultKey = VaultCrypto.generateVaultKey();
    final wrappedKey = await VaultCrypto.wrapKey(kek, vaultKey);
    final vault = VaultData(entries: [
      VaultEntry.create(name: 'GitHub', username: 'alice', password: 'pw'),
    ]);
    final (blob, nonce) = await VaultCrypto.encrypt(
        vaultKey, VaultCrypto.encodeJson(vault.toJson()));
    return CachedVault.withToken(
      vaultKey: vaultKey,
      token: 'session-token',
      userId: 7,
      username: 'alice',
      salt: salt,
      kdf: kdf.toJson(),
      wrappedKey: wrappedKey,
      wrappedRecovery: null,
      blob: blob,
      nonce: nonce,
      revision: 3,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<_PendingController> makeUnlocked() async {
    final repo = SettingsRepository();
    await repo.saveCache(await buildCache());
    final server = _FakeServer();
    final c = _PendingController(repo, biometrics: _FakeBiometrics(),
        server: server);
    await waitFor(() => c.state.status == AuthStatus.locked);
    await c.unlock('master-password');
    server.vaultKey = c.state.vaultKey!;
    expect(c.state.status, AuthStatus.unlocked);
    return c;
  }

  VaultData edit(VaultData local) => VaultData(
        entries: [
          ...local.entries,
          VaultEntry.create(
              name: 'LocalItem', username: 'local', password: 'pw'),
        ],
        folders: local.folders,
      );

  test('an offline save keeps the edit locally and marks pendingSync',
      () async {
    final c = await makeUnlocked();
    final repo = SettingsRepository();
    final before = c.state.vault!;
    final edited = edit(before);

    c.server.online = false;
    await c.saveVault(edited);

    expect(c.state.pendingSync, isTrue, reason: 'must be flagged pending');
    expect(c.state.serverStatus, ServerStatus.offline);
    expect(c.state.vault!.entries.length, before.entries.length + 1,
        reason: 'the edit must be kept locally');
    expect(c.state.cache!.revision, 3, reason: 'the server never advanced');
    // Survives an app restart: the encrypted cache carries the flag + blob.
    final reloaded = await repo.loadCache();
    expect(reloaded, isNotNull);
    expect(reloaded!.pendingSync, isTrue);
    expect(reloaded.lastSyncedAt, c.state.lastSyncedAt);
  });

  test('pending edits are pushed to the server on reconnect', () async {
    final c = await makeUnlocked();
    c.server.online = false;
    await c.saveVault(edit(c.state.vault!));
    expect(c.state.pendingSync, isTrue);

    c.server.online = true;
    final ok = await c.syncPendingChanges();

    expect(ok, isTrue);
    expect(c.state.pendingSync, isFalse);
    expect(c.state.lastSyncedAt, greaterThan(0));
    expect(c.state.cache!.revision, 4);
    expect(c.state.serverStatus, ServerStatus.online);
    expect(c.state.vault!.entries.any((e) => e.name == 'LocalItem'), isTrue);
  });

  test('a conflict during reconnect merges remote edits (LWW)', () async {
    final c = await makeUnlocked();
    c.server.online = false;
    await c.saveVault(edit(c.state.vault!));

    // While offline another device pushed a change: the server moved to
    // revision 4 and the local base is stale.
    c.server.online = true;
    c.server.revision = 4;
    c.server.conflictNext = 1;
    c.server.remote = VaultData(entries: [
      VaultEntry.create(
          name: 'ServerItem', username: 'server', password: 'pw'),
    ]);

    final ok = await c.syncPendingChanges();

    expect(ok, isTrue);
    expect(c.state.pendingSync, isFalse);
    expect(c.state.cache!.revision, 5);
    final names = c.state.vault!.entries.map((e) => e.name).toList();
    expect(names, contains('LocalItem'));
    expect(names, contains('ServerItem'));
  });

  test('a 401 during save is rethrown, not treated as offline', () async {
    final repo = SettingsRepository();
    await repo.saveCache(await buildCache());
    final server = _FakeServer();
    // Never return success: 401 on every PUT.
    final c = _UnreachableController(
        repo, biometrics: _FakeBiometrics(), server: server);
    await waitFor(() => c.state.status == AuthStatus.locked);
    await c.unlock('master-password');
    server.vaultKey = c.state.vaultKey!;

    server.online = true;
    final edited = edit(c.state.vault!);
    await expectLater(c.saveVault(edited), throwsA(isA<ApiException>()));
    expect(c.state.pendingSync, isFalse);
  });
}

class _UnreachableController extends _PendingController {
  _UnreachableController(super.repo, {super.biometrics, required super.server})
      : super();

  @override
  PassOneClient get client => PassOneClient(
      baseUrl: 'http://fake',
      httpClient: _UnauthorizedClient());
}

class _UnauthorizedClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'error': 'unauthorized',
          'code': 'unauthorized',
        }))),
        401,
        request: request);
  }
}
