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
import 'package:passone_app/state/conflicts.dart';
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

class _ConflictController extends SessionController {
  final _FakeServer server;

  _ConflictController(super.repo, {super.biometrics, required this.server})
      : super();

  @override
  PassOneClient get client =>
      PassOneClient(baseUrl: 'http://fake', httpClient: server.client());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmpDir = Directory.systemTemp.createTempSync('passone_conflict_test');

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

  Future<_ConflictController> makeUnlocked() async {
    final repo = SettingsRepository();
    await repo.saveCache(await buildCache());
    final server = _FakeServer();
    final c = _ConflictController(repo, biometrics: _FakeBiometrics(),
        server: server);
    await waitFor(() => c.state.status == AuthStatus.locked);
    await c.unlock('master-password');
    server.vaultKey = c.state.vaultKey!;
    expect(c.state.status, AuthStatus.unlocked);
    return c;
  }

  group('entryFingerprint', () {
    test('ignores id and timestamps, keeps the content', () {
      final a =
          VaultEntry.create(name: 'GitHub', username: 'alice', password: 'pw');
      final b = VaultEntry(
        id: 'different-id',
        name: 'GitHub',
        url: '',
        username: 'alice',
        password: 'pw',
        notes: '',
        createdAt: a.createdAt.subtract(const Duration(days: 30)),
        updatedAt: a.updatedAt.subtract(const Duration(days: 30)),
      );
      expect(entryFingerprint(a), entryFingerprint(b));
      expect(entryFingerprint(a),
          isNot(entryFingerprint(a.copyWith(password: 'other'))));
    });
  });

  group('findConflicts', () {
    test('detects the same id edited differently on both sides', () {
      final base =
          VaultEntry.create(name: 'GitHub', username: 'alice', password: 'pw');
      final local = VaultData(entries: [base.copyWith(password: 'local-pw')]);
      final remote = VaultData(entries: [base.copyWith(password: 'remote-pw')]);
      final conflicts = findConflicts(local, remote);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, ConflictKind.editedEdited);
      expect(conflicts.single.id, base.id);
      expect(conflicts.single.local.password, 'local-pw');
      expect(conflicts.single.remote.password, 'remote-pw');
    });

    test('does not report identical entries', () {
      final a =
          VaultEntry.create(name: 'GitHub', username: 'alice', password: 'pw');
      expect(findConflicts(VaultData(entries: [a]), VaultData(entries: [a])),
          isEmpty);
    });

    test('detects duplicates with different ids and identical content', () {
      final dup1 =
          VaultEntry.create(name: 'Netflix', username: 'bob', password: 'x');
      final dup2 =
          VaultEntry.create(name: 'Netflix', username: 'bob', password: 'x');
      expect(dup1.id, isNot(dup2.id));
      final conflicts = findConflicts(
          VaultData(entries: [dup1]), VaultData(entries: [dup2]));
      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, ConflictKind.duplicate);
      expect(conflicts.single.local.id, dup1.id);
      expect(conflicts.single.remote.id, dup2.id);
    });
  });

  group('resolveConflicts', () {
    test('editedEdited keeps the chosen side and drops the other', () {
      final base =
          VaultEntry.create(name: 'GitHub', username: 'alice', password: 'pw');
      final local = base.copyWith(password: 'local-pw');
      final remote = base.copyWith(password: 'remote-pw');
      final conflicts = findConflicts(
          VaultData(entries: [local]), VaultData(entries: [remote]));
      final merged = VaultData(entries: [local]);

      final pickRemote = resolveConflicts(merged, conflicts, [
        ConflictResolution(conflicts.single.id, ConflictChoice.remote),
      ]);
      expect(pickRemote.entries.single.password, 'remote-pw');

      final pickLocal = resolveConflicts(merged, conflicts, [
        ConflictResolution(conflicts.single.id, ConflictChoice.local),
      ]);
      expect(pickLocal.entries.single.password, 'local-pw');
    });

    test('duplicate drops the other copy or keeps both', () {
      final dup1 =
          VaultEntry.create(name: 'Netflix', username: 'bob', password: 'x');
      final dup2 =
          VaultEntry.create(name: 'Netflix', username: 'bob', password: 'x');
      final conflicts = findConflicts(
          VaultData(entries: [dup1]), VaultData(entries: [dup2]));
      final merged = VaultData(entries: [dup1, dup2]);

      final both = resolveConflicts(merged, conflicts, [
        ConflictResolution(conflicts.single.id, ConflictChoice.both),
      ]);
      expect(both.entries, hasLength(2));

      final keepLocal = resolveConflicts(merged, conflicts, [
        ConflictResolution(conflicts.single.id, ConflictChoice.local),
      ]);
      expect(keepLocal.entries.map((e) => e.id).toList(), [dup1.id]);

      final keepRemote = resolveConflicts(merged, conflicts, [
        ConflictResolution(conflicts.single.id, ConflictChoice.remote),
      ]);
      expect(keepRemote.entries.map((e) => e.id).toList(), [dup2.id]);
    });
  });

  group('controller integration', () {
    test('syncAll pulls a newer remote vault without pending changes', () async {
      final c = await makeUnlocked();
      final base = c.state.vault!.entries.single;
      expect(c.state.cache!.revision, 3);

      // The server moved on: another device pushed a new entry (rev 4).
      c.server.revision = 4;
      c.server.remote = VaultData(entries: [
        base.copyWith(name: 'ServerItem'),
        VaultEntry.create(name: 'GitHub', username: 'alice', password: 'pw'),
      ]);

      final ok = await c.syncAll();

      expect(ok, isTrue);
      expect(c.state.cache!.revision, 4);
      expect(c.state.vault!.entries.map((e) => e.name),
          contains('ServerItem'));
    });

    test('syncAll without remote changes leaves the vault untouched', () async {
      final c = await makeUnlocked();
      final before = c.state.vault!.entries.single.id;
      c.server.revision = 3;
      c.server.remote = c.state.vault!;
      final ok = await c.syncAll();
      expect(ok, isTrue);
      expect(c.state.vault!.entries.single.id, before);
    });

    test('syncAll applies a remote deletion (no union resurrection)',
        () async {
      final c = await makeUnlocked();
      final base = c.state.vault!.entries.single;
      final stale = VaultEntry.create(
          name: 'Old', username: 'old', password: 'pw');

      // The local vault in RAM is stale: it still has an entry that another
      // device deleted on the server.
      c.state = c.state.copyWith(
          vault: VaultData(entries: [base, stale]));

      // Server moved to rev 4 and no longer has 'Old'.
      c.server.revision = 4;
      c.server.remote = VaultData(entries: [base]);

      final ok = await c.syncAll();

      expect(ok, isTrue);
      expect(c.state.vault!.entries.map((e) => e.name), contains('GitHub'));
      expect(c.state.vault!.entries.map((e) => e.name), isNot(contains('Old')));
      expect(c.state.cache!.revision, 4);
    });

    test('a 409 merge with a same-id edit produces a conflict', () async {
      final c = await makeUnlocked();
      final base = c.state.vault!.entries.single;

      c.server.online = false;
      await c.saveVault(
          VaultData(entries: [base.copyWith(password: 'local-pw')]));

      c.server.online = true;
      c.server.revision = 4;
      c.server.conflictNext = 1;
      c.server.remote =
          VaultData(entries: [base.copyWith(password: 'remote-pw')]);

      final ok = await c.syncPendingChanges();

      expect(ok, isTrue);
      final conflicts = c.state.conflicts;
      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, ConflictKind.editedEdited);
      expect(conflicts.single.local.password, 'local-pw');
      expect(conflicts.single.remote.password, 'remote-pw');
    });

    test('applyConflictResolutions keeps the chosen side and clears conflicts',
        () async {
      final c = await makeUnlocked();
      final base = c.state.vault!.entries.single;
      c.server.online = false;
      await c.saveVault(
          VaultData(entries: [base.copyWith(password: 'local-pw')]));
      c.server.online = true;
      c.server.revision = 4;
      c.server.conflictNext = 1;
      c.server.remote =
          VaultData(entries: [base.copyWith(password: 'remote-pw')]);
      final ok = await c.syncPendingChanges();
      expect(ok, isTrue);
      expect(c.state.conflicts, hasLength(1));

      await c.applyConflictResolutions([
        ConflictResolution(c.state.conflicts.single.id, ConflictChoice.remote),
      ]);

      expect(c.state.conflicts, isEmpty);
      expect(c.state.vault!.entries.single.password, 'remote-pw');
      expect(c.state.pendingSync, isFalse);
      expect(c.state.cache!.revision, greaterThan(4),
          reason: 'the resolved vault must be pushed');
    });
  });
}
