import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:passone_app/api/client.dart';
import 'package:passone_app/crypto/kdf.dart';
import 'package:passone_app/crypto/models.dart';
import 'package:passone_app/crypto/vault_crypto.dart';
import 'package:passone_app/state/biometrics.dart';
import 'package:passone_app/state/session.dart';
import 'package:passone_app/state/settings.dart';

/// In-memory fake biometric service.
class _FakeBiometrics extends BiometricService {
  Uint8List? stored;

  _FakeBiometrics()
      : super(auth: LocalAuthentication(), storage: const FlutterSecureStorage());

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<BiometricReadResult> authenticate() async =>
      BiometricReadResult.success;

  @override
  Future<void> storeBioKey(Uint8List bioKey) async {
    stored = bioKey;
  }

  @override
  Future<({BiometricReadResult result, Uint8List? bioKey})>
      readBioKey() async {
    return stored == null
        ? (result: BiometricReadResult.unavailable, bioKey: null)
        : (result: BiometricReadResult.success, bioKey: stored);
  }

  @override
  Future<void> deleteBioKey() async {
    stored = null;
  }

  @override
  Future<bool> hasBioKey() async => stored != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmpDir = Directory.systemTemp.createTempSync('passone_test');

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
    );
  }

  Future<void> waitFor(bool Function() cond) async {
    for (var i = 0; i < 200; i++) {
      if (cond()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('timed out waiting for the condition');
  }

  test('unlock after cold start restores the token for saving', () async {
    final repo = SettingsRepository();
    await repo.saveCache(await buildCache());

    final c = SessionController(repo);
    await waitFor(() => c.state.status == AuthStatus.locked);

    expect(c.state.token, isNull, reason: 'cold start: token not in memory');

    await c.unlock('master-password');
    await waitFor(() => c.state.status == AuthStatus.unlocked);

    expect(c.state.token, 'session-token',
        reason: 'unlock must restore the token from the cache');
    expect(c.state.vaultKey, isNotNull);
    expect(c.state.vault, isNotNull);
    expect(c.state.vault!.entries.length, 1);

    // With the token restored, saveVault's guard is passed and the request
    // reaches the network (ApiException without a server) instead of StateError.
    await expectLater(
      c.saveVault(c.state.vault!),
      throwsA(isA<ApiException>()),
    );

    c.lock();
    expect(c.state.token, isNull,
        reason: 'lock must wipe the session token from memory');
    await c.unlock('master-password');
    await waitFor(() => c.state.status == AuthStatus.unlocked);
    expect(c.state.token, 'session-token',
        reason: 'the token is restored from the encrypted cache on unlock');
    c.lock();
  });

  test('the token is stored encrypted, never in plaintext', () async {
    final repo = SettingsRepository();
    await repo.saveCache(await buildCache());

    final file = File('${tmpDir.path}${Platform.pathSeparator}vault.cache.json');
    expect(file.existsSync(), isTrue);
    final raw = await file.readAsString();
    expect(raw, isNot(contains('session-token')),
        reason: 'the session token must not appear in plaintext in the file');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    expect(data['encryptedToken'], isA<String>());
    expect(data['encryptedToken'], isNotEmpty);
    expect(data.containsKey('token'), isFalse,
        reason: 'the legacy plaintext token field must not be written');

    final c = SessionController(repo);
    await waitFor(() => c.state.status == AuthStatus.locked);
    await c.unlock('master-password');
    await waitFor(() => c.state.status == AuthStatus.unlocked);
    expect(c.state.token, 'session-token');
    c.lock();
  });

  test('biometrics: enable, lock, unlock with fingerprint, disable',
      () async {
    final repo = SettingsRepository();
    await repo.saveCache(await buildCache());
    final bio = _FakeBiometrics();
    final c = SessionController(repo, biometrics: bio);
    await waitFor(() => c.state.status == AuthStatus.locked);

    await c.unlock('master-password');
    await waitFor(() => c.state.status == AuthStatus.unlocked);

    await c.enableBiometrics();
    expect(c.state.settings.biometricsEnabled, isTrue);
    expect(c.state.cache!.bioWrappedKey, isNotNull);
    expect(bio.stored, isNotNull);

    c.lock();
    expect(c.state.status, AuthStatus.locked);
    expect(c.state.vaultKey, isNull);

    final result = await c.unlockWithBiometrics();
    expect(result, BiometricReadResult.success);
    expect(c.state.status, AuthStatus.unlocked);
    expect(c.state.token, 'session-token',
        reason: 'the biometric unlock must restore the token');
    expect(c.state.vaultKey, isNotNull);
    expect(c.state.vault!.entries.single.name, 'GitHub');

    await c.disableBiometrics();
    expect(c.state.settings.biometricsEnabled, isFalse);
    expect(c.state.cache!.bioWrappedKey, isNull);
    expect(bio.stored, isNull);

    c.lock();
  });
}
