import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../crypto/kdf.dart';
import '../crypto/models.dart';
import '../crypto/vault_crypto.dart';
import 'biometrics.dart';
import 'settings.dart';

enum AuthStatus { unauthenticated, locked, unlocked }

/// Eccezione quando l'account è pending (serve il setup).
class NeedsSetupException implements Exception {
  const NeedsSetupException();

  @override
  String toString() => 'The account is awaiting setup.';
}

/// Eccezione per password/recovery key errata.
class WrongPasswordException implements Exception {
  const WrongPasswordException();

  @override
  String toString() => 'Invalid password or recovery key.';
}

class SessionState {
  final AuthStatus status;
  final UserInfo? user;
  final String? token;
  final AppSettings settings;
  final CachedVault? cache;
  final Uint8List? vaultKey;
  final VaultData? vault;

  const SessionState({
    this.status = AuthStatus.unauthenticated,
    this.user,
    this.token,
    this.settings = const AppSettings(),
    this.cache,
    this.vaultKey,
    this.vault,
  });

  SessionState copyWith({
    AuthStatus? status,
    UserInfo? user,
    String? token,
    AppSettings? settings,
    CachedVault? cache,
    Uint8List? vaultKey,
    VaultData? vault,
  }) {
    return SessionState(
      status: status ?? this.status,
      user: user ?? this.user,
      token: token ?? this.token,
      settings: settings ?? this.settings,
      cache: cache ?? this.cache,
      vaultKey: vaultKey ?? this.vaultKey,
      vault: vault ?? this.vault,
    );
  }
}

class SessionController extends StateNotifier<SessionState> {
  final SettingsRepository _repo;
  final BiometricService _biometrics;
  final Kdf _kdf = Kdf();
  PassOneClient? _client;
  Timer? _lockTimer;

  SessionController(this._repo, {BiometricService? biometrics})
      : _biometrics = biometrics ?? BiometricService(),
        super(const SessionState()) {
    _init();
  }

  PassOneClient get client {
    final c = _client;
    if (c == null) {
      throw ApiException(0, 'no_server',
          'Configure the server address in the settings.');
    }
    return c;
  }

  Future<void> _init() async {
    final settings = await _repo.load();
    final cache = await _repo.loadCache();
    if (settings.serverUrl.isNotEmpty) {
      _client = PassOneClient(baseUrl: settings.serverUrl);
    }
    state = SessionState(
      settings: settings,
      cache: cache,
      status: cache != null ? AuthStatus.locked : AuthStatus.unauthenticated,
      user: cache != null
          ? UserInfo(
              id: cache.userId,
              username: cache.username,
              status: 'active',
              vaultRevision: cache.revision,
              recoveryEnabled: cache.wrappedRecovery != null,
              kdfAlgorithm: cache.kdf['algorithm'] as String? ?? '',
            )
          : null,
    );
  }

  /// Imposta/aggiorna l'URL del server e il client HTTP.
  Future<void> setServerUrl(String url) async {
    final base = url.trim().replaceAll(RegExp(r'/+$'), '');
    final settings = state.settings.copyWithServerUrl(base);
    await _repo.save(settings);
    _client = PassOneClient(baseUrl: base);
    state = state.copyWith(settings: settings);
  }

  Future<void> setLockTimeout(LockTimeout timeout) async {
    final settings = state.settings.copyWithLockTimeout(timeout);
    await _repo.save(settings);
    state = state.copyWith(settings: settings);
    if (state.status == AuthStatus.unlocked) {
      _scheduleLock();
    }
  }

  Future<void> setLastUsername(String username) async {
    final settings = state.settings.copyWithLastUsername(username);
    await _repo.save(settings);
    state = state.copyWith(settings: settings);
  }

  /// Imposta la lingua forzata ('it'/'en') o torna alla lingua di sistema (null).
  Future<void> setLanguageCode(String? code) async {
    final settings = state.settings.copyWithLanguageCode(code);
    await _repo.save(settings);
    state = state.copyWith(settings: settings);
  }

  /// Prelogin: salt + parametri KDF per derivare la chiave prima di autenticarsi.
  Future<({String status, Uint8List salt, KdfParams kdf})> prelogin(
      String username) async {
    final res = await client.prelogin(username);
    final kdf = KdfParams.fromJson(res.kdf);
    return (status: res.status, salt: res.salt, kdf: kdf);
  }

  Future<Uint8List> _deriveKek(String password, Uint8List salt, KdfParams kdf) =>
      _kdf.derive(password, salt, kdf);

  /// Login: deriva la chiave, si autentica, scarica e decripta il vault.
  Future<void> login({
    required String username,
    required String password,
    String? serverUrl,
  }) async {
    if (serverUrl != null) {
      await setServerUrl(serverUrl);
    }
    final pre = await prelogin(username);
    if (pre.status == 'pending') {
      throw NeedsSetupException();
    }
    if (pre.status == 'unknown') {
      throw const WrongPasswordException();
    }
    final kek = await _deriveKek(password, pre.salt, pre.kdf);
    final authHashB64 = VaultCrypto.bytesToB64(await sha256Bytes(kek));
    final session = await client.login(
      username: username,
      authHashB64: authHashB64,
      deviceName: _deviceName(),
    );
    await _loadVaultAfterLogin(session, kek, password, pre.salt, pre.kdf);
    await setLastUsername(username);
  }

  /// Registrazione diretta o con invite token (primo accesso).
  /// Restituisce la recovery key (da mostrare UNA volta) oppure null.
  Future<String?> register({
    required String username,
    required String password,
    String? inviteToken,
    bool wantRecovery = false,
    String? serverUrl,
  }) async {
    if (serverUrl != null) {
      await setServerUrl(serverUrl);
    }
    final salt = VaultCrypto.randomBytes(16);
    final kdf = KdfParams.argon2id();
    final kek = await _deriveKek(password, salt, kdf);
    final authHashB64 = VaultCrypto.bytesToB64(await sha256Bytes(kek));
    final vaultKey = VaultCrypto.generateVaultKey();

    String? recoveryKey;
    String? recoveryHashB64;
    Uint8List? wrappedRecov;
    if (wantRecovery) {
      recoveryKey = VaultCrypto.bytesToB64(VaultCrypto.randomBytes(32));
      wrappedRecov = await VaultCrypto.wrapKey(
          VaultCrypto.b64ToBytes(recoveryKey), vaultKey);
      recoveryHashB64 =
          VaultCrypto.bytesToB64(await sha256Bytes(VaultCrypto.b64ToBytes(recoveryKey)));
    }

    final wrapped = await VaultCrypto.wrapKey(kek, vaultKey);
    final vaultData = VaultData();
    final (blob, nonce) = await VaultCrypto.encrypt(
        vaultKey, VaultCrypto.encodeJson(vaultData.toJson()));

    final session = await client.setup(
      username: username,
      inviteToken: inviteToken,
      authHashB64: authHashB64,
      saltB64: VaultCrypto.bytesToB64(salt),
      kdf: kdf.toJson(),
      wrappedKeyB64: VaultCrypto.bytesToB64(wrapped),
      wrappedRecoveryB64:
          wrappedRecov == null ? null : VaultCrypto.bytesToB64(wrappedRecov),
      recoveryHashB64: recoveryHashB64,
      blobB64: VaultCrypto.bytesToB64(blob),
      nonceB64: VaultCrypto.bytesToB64(nonce),
      deviceName: _deviceName(),
    );

    final cache = _buildCache(session, salt, kdf, authHashB64, wrapped,
        wrappedRecov, blob, nonce);
    await _repo.saveCache(cache);
    await setLastUsername(username);
    state = state.copyWith(
      status: AuthStatus.unlocked,
      user: session.user,
      token: session.token,
      cache: cache,
      vaultKey: vaultKey,
      vault: vaultData,
    );
    _scheduleLock();
    return recoveryKey;
  }

  Future<void> _loadVaultAfterLogin(Session session, Uint8List kek,
      String password, Uint8List preSalt, KdfParams preKdf) async {
    final remote = await client.vaultGet(session.token);
    final vaultKey = await VaultCrypto.unwrapKey(kek, remote.wrappedKey);
    final vaultData = VaultData.fromJson(
        VaultCrypto.decodeJson(await VaultCrypto.decrypt(
            vaultKey, remote.blob, remote.nonce)));
    final authHashB64 = VaultCrypto.bytesToB64(await sha256Bytes(kek));
    final cache = CachedVault(
      token: session.token,
      userId: session.user.id,
      username: session.user.username,
      salt: remote.salt,
      kdf: remote.kdf,
      authHash: VaultCrypto.b64ToBytes(authHashB64),
      wrappedKey: remote.wrappedKey,
      wrappedRecovery: remote.wrappedRecoveryKey,
      blob: remote.blob,
      nonce: remote.nonce,
      revision: remote.revision,
    );
    await _repo.saveCache(cache);
    state = state.copyWith(
      status: AuthStatus.unlocked,
      user: session.user,
      token: session.token,
      cache: cache,
      vaultKey: vaultKey,
      vault: vaultData,
    );
    _scheduleLock();
  }

  /// Unlock offline: deriva la chiave localmente e decripta la cache.
  Future<void> unlock(String password) async {
    final cache = state.cache;
    if (cache == null) {
      throw StateError('nessuna cache del vault');
    }
    final kdf = KdfParams.fromJson(cache.kdf);
    final kek = await _deriveKek(password, cache.salt, kdf);
    final authHash = await sha256Bytes(kek);
    if (!_bytesEqual(authHash, cache.authHash)) {
      throw WrongPasswordException();
    }
    final vaultKey = await VaultCrypto.unwrapKey(kek, cache.wrappedKey);
    final vaultData = VaultData.fromJson(
        VaultCrypto.decodeJson(
            await VaultCrypto.decrypt(vaultKey, cache.blob, cache.nonce)));
    state = state.copyWith(
      status: AuthStatus.unlocked,
      token: cache.token,
      user: state.user ??
          UserInfo(
              id: cache.userId,
              username: cache.username,
              status: 'active',
              vaultRevision: cache.revision,
              recoveryEnabled: cache.wrappedRecovery != null,
              kdfAlgorithm: cache.kdf['algorithm'] as String? ?? ''),
      vaultKey: vaultKey,
      vault: vaultData,
    );
    _scheduleLock();
  }

  /// Abilita l'accesso biometrico: genera una bioKey, la salva nel Keystore
  /// (gated da biometria) e avvolge la vaultKey corrente. Richiede lo stato
  /// sbloccato: la vaultKey è in memoria.
  Future<void> enableBiometrics() async {
    final cache = state.cache;
    final vaultKey = state.vaultKey;
    if (cache == null || vaultKey == null) {
      throw StateError('vault non sbloccato');
    }
    if (!await _biometrics.isAvailable()) {
      throw StateError('biometria non disponibile su questo dispositivo');
    }
    final bioKey = VaultCrypto.randomBytes(32);
    final bioWrapped = await VaultCrypto.wrapKey(bioKey, vaultKey);
    await _biometrics.storeBioKey(bioKey);
    final updated = _cacheWithBio(cache, bioWrapped);
    state = state.copyWith(
      cache: updated,
      settings: state.settings.copyWithBiometricsEnabled(true),
    );
    await _repo.saveCache(updated);
    await _repo.save(state.settings);
  }

  /// Disabilita l'accesso biometrico e rimuove la bioKey dal Keystore.
  Future<void> disableBiometrics() async {
    await _biometrics.deleteBioKey();
    final cache = state.cache;
    final updated = cache == null ? null : _cacheWithBio(cache, null);
    state = state.copyWith(
      cache: updated,
      settings: state.settings.copyWithBiometricsEnabled(false),
    );
    if (updated != null) await _repo.saveCache(updated);
    await _repo.save(state.settings);
  }

  /// Sblocca con la biometria: legge la bioKey dal Keystore (prompt) e srotola
  /// la vaultKey salvata. Non richiede la master password.
  Future<BiometricReadResult> unlockWithBiometrics() async {
    final cache = state.cache;
    final bioWrapped = cache?.bioWrappedKey;
    if (cache == null || bioWrapped == null) {
      return BiometricReadResult.unavailable;
    }
    final read = await _biometrics.readBioKey();
    if (read.result != BiometricReadResult.success || read.bioKey == null) {
      return read.result;
    }
    try {
      final vaultKey = await VaultCrypto.unwrapKey(read.bioKey!, bioWrapped);
      final vaultData = VaultData.fromJson(VaultCrypto.decodeJson(
          await VaultCrypto.decrypt(vaultKey, cache.blob, cache.nonce)));
      state = state.copyWith(
        status: AuthStatus.unlocked,
        token: cache.token,
        user: state.user ??
            UserInfo(
                id: cache.userId,
                username: cache.username,
                status: 'active',
                vaultRevision: cache.revision,
                recoveryEnabled: cache.wrappedRecovery != null,
                kdfAlgorithm: cache.kdf['algorithm'] as String? ?? ''),
        vaultKey: vaultKey,
        vault: vaultData,
      );
      _scheduleLock();
      return BiometricReadResult.success;
    } catch (_) {
      return BiometricReadResult.unavailable;
    }
  }

  CachedVault _cacheWithBio(CachedVault cache, Uint8List? bioWrapped) =>
      CachedVault(
        token: cache.token,
        userId: cache.userId,
        username: cache.username,
        salt: cache.salt,
        kdf: cache.kdf,
        authHash: cache.authHash,
        wrappedKey: cache.wrappedKey,
        wrappedRecovery: cache.wrappedRecovery,
        blob: cache.blob,
        nonce: cache.nonce,
        revision: cache.revision,
        bioWrappedKey: bioWrapped,
      );

  /// Blocca il vault: azzera le chiavi dalla memoria.
  void lock() {
    _lockTimer?.cancel();
    _lockTimer = null;
    // Stato costruito esplicitamente: copyWith non può azzerare vaultKey/vault
    // (usa `??`), quindi qui le chiavi vengono davvero rimosse dalla memoria.
    state = SessionState(
      status: AuthStatus.locked,
      user: state.user,
      token: state.token,
      settings: state.settings,
      cache: state.cache,
    );
  }

  void _scheduleLock() {
    _lockTimer?.cancel();
    final minutes = state.settings.lockTimeout.minutes;
    if (minutes < 0) return;
    _lockTimer = Timer(Duration(minutes: minutes), lock);
  }

  /// Riavvia il timer di lock (da chiamare su attività utente).
  void touch() {
    if (state.status == AuthStatus.unlocked) {
      _scheduleLock();
    }
  }

  /// Aggiorna le voci in memoria e sincronizza col server (LWW).
  Future<void> saveVault(VaultData vault) async {
    final cache = state.cache;
    final vaultKey = state.vaultKey;
    final token = state.token;
    if (cache == null || vaultKey == null || token == null) {
      throw StateError('vault non sbloccato');
    }
    state = state.copyWith(vault: vault);
    var current = vault;
    var revision = cache.revision;
    var remote = false;
    for (var attempt = 0; attempt < 3; attempt++) {
      final (blob, nonce) = await VaultCrypto.encrypt(
          vaultKey, VaultCrypto.encodeJson(current.toJson()));
      try {
        final newRev = await client.vaultPut(
          token,
          baseRevision: revision,
          blobB64: VaultCrypto.bytesToB64(blob),
          nonceB64: VaultCrypto.bytesToB64(nonce),
        );
        await _updateCache(
            blob: blob, nonce: nonce, revision: newRev, remote: remote);
        return;
      } on ApiException catch (e) {
        if (!e.isConflict) rethrow;
        final latest = await client.vaultGet(token);
        final remoteVault = VaultData.fromJson(VaultCrypto.decodeJson(
            await VaultCrypto.decrypt(vaultKey, latest.blob, latest.nonce)));
        current = _mergeVaults(current, remoteVault);
        revision = latest.revision;
        remote = true;
      }
    }
    throw ApiException(0, 'sync_failed', 'Sincronizzazione non riuscita.');
  }

  /// Scarica il vault dal server e fa merge (LWW) con quello locale.
  Future<void> refreshFromServer() async {
    final cache = state.cache;
    final vaultKey = state.vaultKey;
    final token = state.token;
    if (cache == null || vaultKey == null || token == null) return;
    final latest = await client.vaultGet(token);
    if (latest.revision <= cache.revision) return;
    final remoteVault = VaultData.fromJson(VaultCrypto.decodeJson(
        await VaultCrypto.decrypt(vaultKey, latest.blob, latest.nonce)));
    final merged = _mergeVaults(state.vault ?? VaultData(), remoteVault);
    state = state.copyWith(vault: merged);
    await _updateCache(
        blob: latest.blob,
        nonce: latest.nonce,
        revision: latest.revision,
        remote: true);
  }

  Future<void> _updateCache({
    required Uint8List blob,
    required Uint8List nonce,
    required int revision,
    required bool remote,
  }) async {
    final cache = state.cache!;
    final updated = CachedVault(
      token: cache.token,
      userId: cache.userId,
      username: cache.username,
      salt: cache.salt,
      kdf: cache.kdf,
      authHash: cache.authHash,
      wrappedKey: cache.wrappedKey,
      wrappedRecovery: cache.wrappedRecovery,
      blob: blob,
      nonce: nonce,
      revision: revision,
      bioWrappedKey: cache.bioWrappedKey,
    );
    state = state.copyWith(cache: updated);
    await _repo.saveCache(updated);
  }

  Future<void> logout() async {
    final token = state.token;
    if (token != null) {
      try {
        await client.logout(token);
      } catch (_) {}
    }
    await _biometrics.deleteBioKey();
    _lockTimer?.cancel();
    await _repo.clearCache();
    final settings = state.settings.copyWithBiometricsEnabled(false);
    await _repo.save(settings);
    state = SessionState(settings: settings);
  }

  Future<void> logoutAll() async {
    final token = state.token;
    if (token != null) {
      try {
        await client.logoutAll(token);
      } catch (_) {}
    }
    await _biometrics.deleteBioKey();
    await _repo.clearCache();
    final settings = state.settings.copyWithBiometricsEnabled(false);
    await _repo.save(settings);
    state = SessionState(settings: settings);
  }

  /// Cambio della master password. [generateRecovery] crea/ruota la recovery key,
  /// [disableRecovery] la rimuove. Restituisce la nuova recovery key se generata.
  Future<String?> changePassword({
    required String oldPassword,
    required String newPassword,
    bool generateRecovery = false,
    bool disableRecovery = false,
  }) async {
    final cache = state.cache;
    final vaultKey = state.vaultKey;
    final token = state.token;
    if (cache == null || vaultKey == null || token == null) {
      throw StateError('vault non sbloccato');
    }
    final oldKdf = KdfParams.fromJson(cache.kdf);
    final oldKek = await _deriveKek(oldPassword, cache.salt, oldKdf);
    final oldAuthHash = await sha256Bytes(oldKek);
    if (!_bytesEqual(oldAuthHash, cache.authHash)) {
      throw WrongPasswordException();
    }

    final newSalt = VaultCrypto.randomBytes(16);
    final newKdf = KdfParams.argon2id();
    final newKek = await _deriveKek(newPassword, newSalt, newKdf);
    final newAuthHashB64 =
        VaultCrypto.bytesToB64(await sha256Bytes(newKek));
    final newWrapped = await VaultCrypto.wrapKey(newKek, vaultKey);

    var wrappedRecov = cache.wrappedRecovery;
    String? newRecoveryKey;
    String? recoveryHashB64;
    if (disableRecovery) {
      wrappedRecov = null;
    } else if (generateRecovery) {
      newRecoveryKey = VaultCrypto.bytesToB64(VaultCrypto.randomBytes(32));
      wrappedRecov = await VaultCrypto.wrapKey(
          VaultCrypto.b64ToBytes(newRecoveryKey), vaultKey);
      recoveryHashB64 =
          VaultCrypto.bytesToB64(await sha256Bytes(VaultCrypto.b64ToBytes(newRecoveryKey)));
    }

    await client.changePassword(
      token,
      oldAuthHashB64: VaultCrypto.bytesToB64(oldAuthHash),
      newAuthMaterial: {
        'auth_hash_b64': newAuthHashB64,
        'salt_b64': VaultCrypto.bytesToB64(newSalt),
        'kdf': newKdf.toJson(),
        'vault_key_wrapped_b64': VaultCrypto.bytesToB64(newWrapped),
        'vault_key_wrapped_recov_b64':
            ?(wrappedRecov == null ? null : VaultCrypto.bytesToB64(wrappedRecov)),
        'recovery_hash_b64': ?recoveryHashB64,
      },
    );

    final updated = CachedVault(
      token: cache.token,
      userId: cache.userId,
      username: cache.username,
      salt: newSalt,
      kdf: newKdf.toJson(),
      authHash: VaultCrypto.b64ToBytes(newAuthHashB64),
      wrappedKey: newWrapped,
      wrappedRecovery: wrappedRecov,
      blob: cache.blob,
      nonce: cache.nonce,
      revision: cache.revision,
      bioWrappedKey: cache.bioWrappedKey,
    );
    await _repo.saveCache(updated);
    state = state.copyWith(cache: updated);
    return newRecoveryKey;
  }

  /// Recovery: usa la recovery key per rientrare e reimpostare la password.
  /// Restituisce la nuova recovery key se richiesta.
  Future<String?> recover({
    required String username,
    required String recoveryKey,
    required String newPassword,
    bool wantNewRecovery = false,
    String? serverUrl,
  }) async {
    if (serverUrl != null) {
      await setServerUrl(serverUrl);
    }
    final recKeyBytes = VaultCrypto.b64ToBytes(recoveryKey);
    final recoveryHashB64 =
        VaultCrypto.bytesToB64(await sha256Bytes(recKeyBytes));
    final payload = await client.recoverPayload(
        username: username, recoveryHashB64: recoveryHashB64);

    final vaultKey =
        await VaultCrypto.unwrapKey(recKeyBytes, payload.wrappedRecoveryKey!);

    final newSalt = VaultCrypto.randomBytes(16);
    final newKdf = KdfParams.argon2id();
    final newKek = await _deriveKek(newPassword, newSalt, newKdf);
    final newAuthHashB64 =
        VaultCrypto.bytesToB64(await sha256Bytes(newKek));
    final newWrapped = await VaultCrypto.wrapKey(newKek, vaultKey);

    String? newRecoveryKey;
    String? newRecoveryHashB64;
    Uint8List? newWrappedRecov;
    if (wantNewRecovery) {
      newRecoveryKey = VaultCrypto.bytesToB64(VaultCrypto.randomBytes(32));
      newWrappedRecov = await VaultCrypto.wrapKey(
          VaultCrypto.b64ToBytes(newRecoveryKey), vaultKey);
      newRecoveryHashB64 =
          VaultCrypto.bytesToB64(await sha256Bytes(VaultCrypto.b64ToBytes(newRecoveryKey)));
    }

    final session = await client.recover(
      username: username,
      recoveryHashB64: recoveryHashB64,
      newAuthMaterial: {
        'auth_hash_b64': newAuthHashB64,
        'salt_b64': VaultCrypto.bytesToB64(newSalt),
        'kdf': newKdf.toJson(),
        'vault_key_wrapped_b64': VaultCrypto.bytesToB64(newWrapped),
        'vault_key_wrapped_recov_b64':
            ?(newWrappedRecov == null ? null : VaultCrypto.bytesToB64(newWrappedRecov)),
        'recovery_hash_b64': ?newRecoveryHashB64,
      },
      deviceName: _deviceName(),
    );

    final vaultData = VaultData.fromJson(VaultCrypto.decodeJson(
        await VaultCrypto.decrypt(vaultKey, payload.blob, payload.nonce)));
    final cache = CachedVault(
      token: session.token,
      userId: session.user.id,
      username: session.user.username,
      salt: newSalt,
      kdf: newKdf.toJson(),
      authHash: VaultCrypto.b64ToBytes(newAuthHashB64),
      wrappedKey: newWrapped,
      wrappedRecovery: newWrappedRecov,
      blob: payload.blob,
      nonce: payload.nonce,
      revision: payload.revision,
    );
    await _repo.saveCache(cache);
    await setLastUsername(username);
    state = state.copyWith(
      status: AuthStatus.unlocked,
      user: session.user,
      token: session.token,
      cache: cache,
      vaultKey: vaultKey,
      vault: vaultData,
    );
    _scheduleLock();
    return newRecoveryKey;
  }

  CachedVault _buildCache(Session session, Uint8List salt, KdfParams kdf,
      String authHashB64, Uint8List wrapped, Uint8List? wrappedRecov,
      Uint8List blob, Uint8List nonce) {
    return CachedVault(
      token: session.token,
      userId: session.user.id,
      username: session.user.username,
      salt: salt,
      kdf: kdf.toJson(),
      authHash: VaultCrypto.b64ToBytes(authHashB64),
      wrappedKey: wrapped,
      wrappedRecovery: wrappedRecov,
      blob: blob,
      nonce: nonce,
      revision: session.user.vaultRevision,
    );
  }

  /// Merge LWW per entry: unione per id, vince la updatedAt più recente.
  VaultData _mergeVaults(VaultData local, VaultData remote) {
    final byId = <String, VaultEntry>{};
    for (final e in local.entries) {
      byId[e.id] = e;
    }
    for (final e in remote.entries) {
      final existing = byId[e.id];
      if (existing == null || e.updatedAt.isAfter(existing.updatedAt)) {
        byId[e.id] = e;
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return VaultData(entries: merged);
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  String _deviceName() {
    // V1: nome generico; su Linux/Windows si potrebbe leggere il hostname.
    return 'PassOne';
  }
}
