import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:passone_app/crypto/kdf.dart';
import 'package:passone_app/crypto/models.dart';
import 'package:passone_app/crypto/vault_crypto.dart';
import 'package:passone_app/state/biometrics.dart';
import 'package:passone_app/state/session.dart';
import 'package:passone_app/state/settings.dart';

/// In-memory fake biometric service (same as unlock_restores_token_test).
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
  final tmpDir = Directory.systemTemp.createTempSync('passone_cache_test');

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

  Future<CachedVault> buildCache({int savedAt = 0}) async {
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
      savedAt: savedAt,
    );
  }

  test('an expired cache is wiped and the user is sent to login', () async {
    final repo = SettingsRepository();
    await repo.save(const AppSettings(
        cacheExpiry: CacheExpiry.twelveHours,
        lockTimeout: LockTimeout.one,
        biometricsEnabled: true));
    await repo.saveCache(await buildCache(
        savedAt: DateTime.now().millisecondsSinceEpoch - 60 * 24 * 3600000));

    final c = SessionController(repo, biometrics: _FakeBiometrics());
    // The initial state is already unauthenticated, so wait for _init() to
    // run (it wipes the cache and sets the notice) instead of the status.
    await waitFor(() => c.state.cacheExpiredNotice);

    expect(c.state.status, AuthStatus.unauthenticated);
    expect(c.state.cache, isNull);
    expect((await repo.loadCache()), isNull,
        reason: 'the expired cache file must be removed');
    // The wipe must not reset the persisted settings to the defaults.
    final settings = await repo.load();
    expect(settings.cacheExpiry, CacheExpiry.twelveHours);
    expect(settings.lockTimeout, LockTimeout.one);
    // The bioKey is gone, so biometrics must be off in the UI state too.
    expect(c.state.settings.biometricsEnabled, isFalse,
        reason: 'the fingerprint toggle must be off after the wipe');
    expect(settings.biometricsEnabled, isFalse);
  });

  test('a fresh cache keeps the locked status', () async {
    final repo = SettingsRepository();
    await repo.saveCache(
        await buildCache(savedAt: DateTime.now().millisecondsSinceEpoch));

    final c = SessionController(repo, biometrics: _FakeBiometrics());
    await waitFor(() => c.state.status == AuthStatus.locked);

    expect(c.state.cacheExpiredNotice, isFalse);
    expect(c.state.cache, isNotNull);
  });

  test('cache expiry "never" never wipes an old cache', () async {
    final repo = SettingsRepository();
    await repo.save(
        const AppSettings(cacheExpiry: CacheExpiry.never));
    await repo.saveCache(await buildCache(
        savedAt: DateTime.now().millisecondsSinceEpoch - 60 * 24 * 3600000));

    final c = SessionController(repo, biometrics: _FakeBiometrics());
    await waitFor(() => c.state.status == AuthStatus.locked);

    expect(c.state.cacheExpiredNotice, isFalse);
    expect(c.state.cache, isNotNull);
  });

  test('a legacy cache without savedAt is never wiped', () async {
    final repo = SettingsRepository();
    await repo.saveCache(await buildCache());

    final c = SessionController(repo, biometrics: _FakeBiometrics());
    await waitFor(() => c.state.status == AuthStatus.locked);

    expect(c.state.cacheExpiredNotice, isFalse);
    expect(c.state.cache, isNotNull);
    expect(c.state.cache!.savedAt, 0);
  });

  test('savedAt survives a cache save/load roundtrip', () async {
    final repo = SettingsRepository();
    final ts = DateTime.now().millisecondsSinceEpoch - 1000;
    await repo.saveCache(await buildCache(savedAt: ts));
    final loaded = await repo.loadCache();
    expect(loaded!.savedAt, ts);
  });
}
