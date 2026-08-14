import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/client.dart';
import '../crypto/kdf.dart';
import '../crypto/models.dart';
import '../crypto/vault_crypto.dart';
import 'autofill.dart';
import 'biometrics.dart';
import 'conflicts.dart';
import 'settings.dart';

enum AuthStatus { unauthenticated, locked, unlocked }

/// Reachability of the configured server, shown as a cloud indicator next to
/// the username on the unlock screen.
enum ServerStatus { checking, online, offline }

/// Exception when the account is pending (setup is required).
class NeedsSetupException implements Exception {
  const NeedsSetupException();

  @override
  String toString() => 'The account is awaiting setup.';
}

/// Exception for wrong password/recovery key.
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
  final int lastAutofillImports;
  /// Passkey registration requested by the system Credential Manager while the
  /// vault was locked (or not): parsed request from the native stash, shown to
  /// the user as a confirmation dialog once the vault is unlocked.
  final Map<String, dynamic>? pendingPasskeyCreate;
  /// Passkey assertion requested by the system while the vault was locked:
  /// the app shows a picker of the matching passkeys after the unlock.
  final Map<String, dynamic>? pendingPasskeyGet;

  /// Result of the last server reachability check (cloud indicator).
  final ServerStatus serverStatus;

  /// True when the local cache expired and was wiped at startup: the login
  /// screen shows a notice explaining what happened.
  final bool cacheExpiredNotice;

  /// Pending sync conflicts between the local vault and the server (empty when
  /// none): surfaced as a banner + dedicated resolution screen.
  final List<VaultConflict> conflicts;

  const SessionState({
    this.status = AuthStatus.unauthenticated,
    this.user,
    this.token,
    this.settings = const AppSettings(),
    this.cache,
    this.vaultKey,
    this.vault,
    this.lastAutofillImports = 0,
    this.pendingPasskeyCreate,
    this.pendingPasskeyGet,
    this.serverStatus = ServerStatus.checking,
    this.cacheExpiredNotice = false,
    this.conflicts = const [],
  });

  SessionState copyWith({
    AuthStatus? status,
    UserInfo? user,
    String? token,
    AppSettings? settings,
    CachedVault? cache,
    Uint8List? vaultKey,
    VaultData? vault,
    int? lastAutofillImports,
    Map<String, dynamic>? pendingPasskeyCreate,
    Map<String, dynamic>? pendingPasskeyGet,
    ServerStatus? serverStatus,
    bool? cacheExpiredNotice,
    List<VaultConflict>? conflicts,
  }) {
    return SessionState(
      status: status ?? this.status,
      user: user ?? this.user,
      token: token ?? this.token,
      settings: settings ?? this.settings,
      cache: cache ?? this.cache,
      vaultKey: vaultKey ?? this.vaultKey,
      vault: vault ?? this.vault,
      lastAutofillImports: lastAutofillImports ?? this.lastAutofillImports,
      pendingPasskeyCreate:
          pendingPasskeyCreate ?? this.pendingPasskeyCreate,
      pendingPasskeyGet: pendingPasskeyGet ?? this.pendingPasskeyGet,
      serverStatus: serverStatus ?? this.serverStatus,
      cacheExpiredNotice: cacheExpiredNotice ?? this.cacheExpiredNotice,
      conflicts: conflicts ?? this.conflicts,
    );
  }

  /// True when the local vault holds edits that could not be pushed to the
  /// server yet (offline): they are kept in the cache and pushed on reconnect.
  bool get pendingSync => cache?.pendingSync ?? false;

  /// Epoch milliseconds of the last successful server sync (0 = never).
  int get lastSyncedAt => cache?.lastSyncedAt ?? 0;
}

class SessionController extends StateNotifier<SessionState> {
  final SettingsRepository _repo;
  final BiometricService _biometrics;
  final Kdf _kdf = Kdf();
  PassOneClient? _client;
  Timer? _lockTimer;
  // Monotonic idle counter: Timer pauses while the app is backgrounded, so
  // the idle time is measured with a stopwatch and the remaining time is
  // re-scheduled when the app returns to the foreground.
  final Stopwatch _idle = Stopwatch()..start();
  // True when the last lock came from the explicit Lock button: the unlock
  // screen must then skip the automatic biometric prompt (otherwise the
  // fingerprint read right after the tap unlocks the vault immediately).
  bool _manualLock = false;
  // Native autofill bridge and the per-unlock snapshot key (held in memory).
  final AutofillBridge _autofill = AutofillBridge();
  Uint8List? _autofillKey;

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
    var settings = await _repo.load();
    final cache = await _repo.loadCache();
    if (settings.serverUrl.isNotEmpty) {
      _client = PassOneClient(baseUrl: settings.serverUrl);
    }
    var activeCache = cache;
    var expired = false;
    if (cache != null &&
        settings.cacheExpiry != CacheExpiry.never &&
        cache.savedAt > 0) {
      final ttlMs = settings.cacheExpiry.hours * 3600000;
      final ageMs = DateTime.now().millisecondsSinceEpoch - cache.savedAt;
      if (ageMs > ttlMs) {
        expired = true;
        activeCache = null;
        // The bioKey is deleted by the wipe, so biometrics must be turned off
        // both on disk and in the state that is built below.
        settings = settings.copyWithBiometricsEnabled(false);
        await _wipeLocalState(settings);
      }
    }
    state = SessionState(
      settings: settings,
      cache: activeCache,
      cacheExpiredNotice: expired,
      status: activeCache != null
          ? AuthStatus.locked
          : AuthStatus.unauthenticated,
      user: activeCache != null
          ? UserInfo(
              id: activeCache.userId,
              username: activeCache.username,
              status: 'active',
              vaultRevision: activeCache.revision,
              recoveryEnabled: activeCache.wrappedRecovery != null,
              kdfAlgorithm:
                  activeCache.kdf['algorithm'] as String? ?? '',
            )
          : null,
    );
    unawaited(refreshServerStatus());
  }

  /// Removes everything that would let the app reopen the vault without a
  /// fresh login: cache file, biometric key and the autofill session key.
  ///
  /// [settings] is the current settings to persist (biometrics disabled): it
  /// must be passed explicitly from [_init], where the state is not built yet
  /// and still holds the defaults.
  Future<void> _wipeLocalState([AppSettings? settings]) async {
    if (_autofillSupported) {
      _autofillKey = null;
      unawaited(_autofill.clearSessionKey());
    }
    await _biometrics.deleteBioKey();
    await _repo.clearCache();
    final s = (settings ?? state.settings).copyWithBiometricsEnabled(false);
    await _repo.save(s);
  }

  /// Checks whether the configured server is reachable and updates the cloud
  /// indicator. Never throws: failures are surfaced as [ServerStatus.offline].
  /// When the vault is unlocked and has pending local edits, their push is
  /// retried on a successful health check.
  Future<void> refreshServerStatus() async {
    final url = state.settings.serverUrl;
    if (url.isEmpty) {
      state = state.copyWith(serverStatus: ServerStatus.offline);
      return;
    }
    var online = false;
    try {
      await (_client ?? PassOneClient(baseUrl: url)).healthCheck();
      online = true;
    } catch (_) {}
    if (!mounted) return;
    state = state.copyWith(serverStatus: online
        ? ServerStatus.online
        : ServerStatus.offline);
    if (online && state.pendingSync && state.status == AuthStatus.unlocked) {
      unawaited(_syncPendingSilently());
    }
  }

  /// Best-effort push of pending edits after a reconnect; swallows errors so
  /// the caller (resume/health check) never observes a failure.
  Future<void> _syncPendingSilently() async {
    try {
      await syncPendingChanges();
    } catch (_) {}
  }

  /// Persists whether the unlock screen should keep showing the offline warning.
  Future<void> setHideOfflineWarning(bool v) async {
    final settings = state.settings.copyWithHideOfflineWarning(v);
    await _repo.save(settings);
    state = state.copyWith(settings: settings);
  }

  /// Changes how long the local cache stays usable without a server sync.
  Future<void> setCacheExpiry(CacheExpiry expiry) async {
    final settings = state.settings.copyWithCacheExpiry(expiry);
    await _repo.save(settings);
    state = state.copyWith(settings: settings);
  }

  /// Clears the "cache expired" notice after the login screen showed it.
  void clearCacheExpiredNotice() {
    if (state.cacheExpiredNotice) {
      state = state.copyWith(cacheExpiredNotice: false);
    }
  }

  /// Verifies the master password against the cached vault without changing
  /// the session (used as a gate for sensitive settings). Throws
  /// [WrongPasswordException] on mismatch.
  Future<void> verifyMasterPassword(String password) async {
    final cache = state.cache;
    if (cache == null) {
      throw StateError('vault non sbloccato');
    }
    final kdf = KdfParams.fromJson(cache.kdf);
    final kek = await _deriveKek(password, cache.salt, kdf);
    try {
      await VaultCrypto.unwrapKey(kek, cache.wrappedKey);
    } catch (_) {
      throw WrongPasswordException();
    }
  }

  /// Prompts for biometrics (fingerprint/face) and returns the result, used
  /// as a gate for sensitive settings when biometrics are enabled.
  Future<BiometricReadResult> authenticateWithBiometrics() =>
      _biometrics.authenticate();

  /// Sets/updates the server URL and the HTTP client.
  Future<void> setServerUrl(String url) async {
    final base = url.trim().replaceAll(RegExp(r'/+$'), '');
    final settings = state.settings.copyWithServerUrl(base);
    await _repo.save(settings);
    _client = PassOneClient(baseUrl: base);
    state = state.copyWith(settings: settings);
  }

  /// Checks that the server responds on GET /health. Overridable in tests.
  Future<void> checkServerReachability(String url) =>
      PassOneClient(baseUrl: url).healthCheck();

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

  /// Sets the forced language ('it'/'en') or returns to the system language (null).
  Future<void> setLanguageCode(String? code) async {
    final settings = state.settings.copyWithLanguageCode(code);
    await _repo.save(settings);
    state = state.copyWith(settings: settings);
  }

  /// Prelogin: salt + KDF parameters to derive the key before authenticating.
  Future<({String status, Uint8List salt, KdfParams kdf})> prelogin(
      String username) async {
    final res = await client.prelogin(username);
    final kdf = KdfParams.fromJson(res.kdf);
    return (status: res.status, salt: res.salt, kdf: kdf);
  }

  Future<Uint8List> _deriveKek(String password, Uint8List salt, KdfParams kdf) =>
      _kdf.derive(password, salt, kdf);

  /// Login: derives the key, authenticates, downloads and decrypts the vault.
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

  /// Direct registration or with an invite token (first access).
  /// Returns the recovery key (to show ONCE) or null.
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

    final cache = await _buildCache(
        session, vaultKey, salt, kdf, wrapped, wrappedRecov, blob, nonce);
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
    final cache = await CachedVault.withToken(
      vaultKey: vaultKey,
      token: session.token,
      userId: session.user.id,
      username: session.user.username,
      salt: remote.salt,
      kdf: remote.kdf,
      wrappedKey: remote.wrappedKey,
      wrappedRecovery: remote.wrappedRecoveryKey,
      blob: remote.blob,
      nonce: remote.nonce,
      revision: remote.revision,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
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
    unawaited(_setupAutofill(vaultKey, vaultData));
  }

  /// Offline unlock: derives the key locally and decrypts the cache.
  Future<void> unlock(String password) async {
    final cache = state.cache;
    if (cache == null) {
      throw StateError('nessuna cache del vault');
    }
    final kdf = KdfParams.fromJson(cache.kdf);
    final kek = await _deriveKek(password, cache.salt, kdf);
    // The wrapped key authenticates the derived KEK: unwrap fails if the
    // password is wrong. There is no authHash in the cache, so a stolen cache
    // does not leak the password verifier used to authenticate to the server.
    Uint8List vaultKey;
    try {
      vaultKey = await VaultCrypto.unwrapKey(kek, cache.wrappedKey);
    } catch (_) {
      throw WrongPasswordException();
    }
    final vaultData = VaultData.fromJson(
        VaultCrypto.decodeJson(
            await VaultCrypto.decrypt(vaultKey, cache.blob, cache.nonce)));
    final token = await cache.decryptToken(vaultKey);
    state = state.copyWith(
      status: AuthStatus.unlocked,
      token: token,
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
    unawaited(_setupAutofill(vaultKey, vaultData));
    // Legacy cache holding a plaintext token: re-encrypt and persist it now.
    if (cache.tokenNonce.isEmpty && token != null) {
      final migrated = await cache.reencryptToken(vaultKey, token);
      await _repo.saveCache(migrated);
      state = state.copyWith(cache: migrated);
    }
    _repairBioKey();
  }

  /// If biometrics are enabled but the bioKey is missing or unreadable (e.g.
  /// legacy data written with the old biometric cipher), re-store a fresh
  /// bioKey and re-wrap the vaultKey. Runs after a successful password unlock,
  /// where the vaultKey is available. Failures are ignored: the user can still
  /// unlock with the password.
  Future<void> _repairBioKey() async {
    if (!state.settings.biometricsEnabled) return;
    try {
      if (!await _biometrics.hasBioKey()) {
        await enableBiometrics(confirm: false);
      }
    } catch (_) {}
  }

  /// Enables biometric access: generates a bioKey, stores it in the Keystore
  /// (gated by biometrics) and wraps the current vaultKey. Requires the
  /// unlocked state: the vaultKey is in memory.
  ///
  /// When [confirm] is true (default, settings toggle) a fingerprint prompt is
  /// shown first: the bioKey is only created after a successful match.
  Future<void> enableBiometrics({bool confirm = true}) async {
    final cache = state.cache;
    final vaultKey = state.vaultKey;
    if (cache == null || vaultKey == null) {
      throw StateError('vault non sbloccato');
    }
    if (!await _biometrics.isAvailable()) {
      throw StateError('biometria non disponibile su questo dispositivo');
    }
    if (confirm) {
      final auth = await _biometrics.authenticate();
      if (auth == BiometricReadResult.canceled) {
        throw const BiometricCanceledException();
      }
      if (auth != BiometricReadResult.success) {
        throw StateError('biometria non disponibile su questo dispositivo');
      }
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

  /// Disables biometric access and removes the bioKey from the Keystore.
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

  /// Unlocks with biometrics: reads the bioKey from the Keystore (prompt) and unwraps
  /// the saved vaultKey. Does not require the master password.
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
      final token = await cache.decryptToken(vaultKey);
      state = state.copyWith(
        status: AuthStatus.unlocked,
        token: token,
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
      unawaited(_setupAutofill(vaultKey, vaultData));
      if (cache.tokenNonce.isEmpty && token != null) {
        final migrated = await cache.reencryptToken(vaultKey, token);
        await _repo.saveCache(migrated);
        state = state.copyWith(cache: migrated);
      }
      return BiometricReadResult.success;
    } catch (_) {
      return BiometricReadResult.unavailable;
    }
  }

  CachedVault _cacheWithBio(CachedVault cache, Uint8List? bioWrapped) =>
      CachedVault(
        encryptedToken: cache.encryptedToken,
        tokenNonce: cache.tokenNonce,
        userId: cache.userId,
        username: cache.username,
        salt: cache.salt,
        kdf: cache.kdf,
        wrappedKey: cache.wrappedKey,
        wrappedRecovery: cache.wrappedRecovery,
        blob: cache.blob,
        nonce: cache.nonce,
        revision: cache.revision,
        bioWrappedKey: bioWrapped,
        savedAt: cache.savedAt,
        pendingSync: cache.pendingSync,
        lastSyncedAt: cache.lastSyncedAt,
      );

  /// Locks the vault: wipes the keys from memory. [manual] is true when the
  /// user pressed the Lock button (the unlock screen skips the automatic
  /// biometric prompt in that case).
  void lock({bool manual = false}) {
    _manualLock = manual;
    _lockTimer?.cancel();
    _lockTimer = null;
    // A pending passkey create/get request is aborted: the native activity
    // must not keep the caller waiting while the vault is locked.
    if (state.pendingPasskeyCreate != null || state.pendingPasskeyGet != null) {
      unawaited(_autofill.passkeyCreateCancel());
      unawaited(_autofill.passkeyGetCancel());
    }
    // The autofill session key is wiped: the native service can no longer
    // decrypt the snapshot and stops offering autofill until the next unlock.
    if (_autofillSupported) {
      _autofillKey = null;
      unawaited(_autofill.clearSessionKey());
    }
    // State built explicitly: copyWith cannot wipe vaultKey/vault/token
    // (it uses `??`), so here the secrets are really removed from memory.
    // The session token is NOT kept: it is restored from the encrypted cache
    // only on the next unlock. Logout from the locked screen therefore only
    // cleans up locally (the server session expires via its TTL or when the
    // password is changed).
    state = SessionState(
      status: AuthStatus.locked,
      user: state.user,
      settings: state.settings,
      cache: state.cache,
    );
  }

  /// Reads and clears the manual-lock flag for the current lock screen.
  bool consumeManualLock() {
    final manual = _manualLock;
    _manualLock = false;
    return manual;
  }

  void _scheduleLock() {
    _lockTimer?.cancel();
    final minutes = state.settings.lockTimeout.minutes;
    if (minutes < 0) return;
    _idle
      ..reset()
      ..start();
    _lockTimer = Timer(Duration(minutes: minutes), lock);
  }

  /// Restarts the lock timer (call it on user activity).
  void touch() {
    if (state.status == AuthStatus.unlocked) {
      _scheduleLock();
    }
  }

  /// Called when the app returns to the foreground: if the idle time exceeded
  /// the lock timeout the vault locks immediately, otherwise the remaining
  /// time is re-scheduled from the monotonic stopwatch (a plain Timer pauses
  /// while the isolate is suspended, so it would fire too late).
  void checkResumed() {
    if (state.status != AuthStatus.unlocked) return;
    // A Credential Manager passkey request may have (re)launched the activity
    // while the app was backgrounded with the vault already unlocked.
    unawaited(_checkPasskeyLaunch());
    // The app may have been backgrounded during an outage: re-check the server
    // and flush pending edits if it is reachable again.
    unawaited(refreshServerStatus());
    final minutes = state.settings.lockTimeout.minutes;
    if (minutes < 0) return;
    final remaining = Duration(minutes: minutes) - _idle.elapsed;
    if (remaining <= Duration.zero) {
      lock();
      return;
    }
    _lockTimer?.cancel();
    _lockTimer = Timer(remaining, lock);
  }

  /// Updates the entries in memory and syncs with the server (LWW).
  ///
  /// When the server is unreachable the edit is kept locally (optimistic state
  /// + encrypted cache) with [SessionState.pendingSync] set, and is pushed on
  /// the next connection ([syncPendingChanges]).
  Future<void> saveVault(VaultData vault) async {
    final cache = state.cache;
    final vaultKey = state.vaultKey;
    final token = state.token;
    if (cache == null || vaultKey == null || token == null) {
      throw StateError('vault non sbloccato');
    }
    state = state.copyWith(vault: vault);
    await _pushVault(vault);
  }

  /// Pushes any local edit that could not reach the server while offline.
  /// Returns true when the vault is now in sync, false when the server is
  /// still unreachable (the changes stay pending). Throws on real server
  /// errors (e.g. auth failures), which the caller decides how to surface.
  Future<bool> syncPendingChanges() async {
    final cache = state.cache;
    final vault = state.vault;
    if (cache == null || state.vaultKey == null || state.token == null ||
        vault == null) {
      return false;
    }
    if (!cache.pendingSync) return true;
    return _pushVault(vault);
  }

  /// Applies the user's conflict decisions to the merged vault, pushes the
  /// result to the server and clears the pending conflicts.
  Future<void> applyConflictResolutions(
      List<ConflictResolution> resolutions) async {
    final conflicts = state.conflicts;
    final vault = state.vault;
    if (conflicts.isEmpty || vault == null) return;
    final resolved = resolveConflicts(vault, conflicts, resolutions);
    state = state.copyWith(vault: resolved);
    await saveVault(resolved);
    state = state.copyWith(conflicts: const []);
  }

  /// Manual "sync now": pulls the latest server vault (LWW merge) and, when
  /// there are pending local edits, pushes them too. Returns true when the app
  /// is now in sync, false when the server is unreachable or when conflicts
  /// still need to be resolved first.
  Future<bool> syncAll() async {
    if (state.conflicts.isNotEmpty) return false;
    try {
      await refreshFromServer();
    } catch (_) {
      return false;
    }
    if (state.pendingSync) {
      return syncPendingChanges();
    }
    return true;
  }

  /// Uploads [vault] to the server with optimistic-concurrency retries. On a
  /// 409 the remote vault is fetched, merged (LWW) and retried; on network
  /// failures the local edit is persisted as pending ([pendingSync]) and the
  /// method returns false without throwing.
  Future<bool> _pushVault(VaultData vault) async {
    final vaultKey = state.vaultKey!;
    final token = state.token!;
    var current = vault;
    var revision = state.cache!.revision;
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
        if (state.serverStatus == ServerStatus.offline) {
          state = state.copyWith(serverStatus: ServerStatus.online);
        }
        unawaited(_syncAutofillSnapshot(current));
        return true;
      } on ApiException catch (e) {
        if (_isNetworkError(e)) {
          await _persistPending(blob, nonce, revision, current);
          return false;
        }
        if (!e.isConflict) rethrow;
        try {
          final latest = await client.vaultGet(token);
          final remoteVault = VaultData.fromJson(VaultCrypto.decodeJson(
              await VaultCrypto.decrypt(
                  vaultKey, latest.blob, latest.nonce)));
          // The local vault before the merge: conflicts are detected against
          // this version so the user can still pick either side.
          final localBeforeMerge = current;
          current = _mergeVaults(current, remoteVault);
          // The merged vault is the actual local truth: show it and push it.
          state = state.copyWith(vault: current);
          final found = findConflicts(localBeforeMerge, remoteVault);
          if (found.isNotEmpty) {
            state = state.copyWith(conflicts: found);
          }
          revision = latest.revision;
          remote = true;
        } catch (e2) {
          if (_isNetworkError(e2)) {
            await _persistPending(blob, nonce, revision, current);
            return false;
          }
          rethrow;
        }
      } catch (e) {
        // Raw transport errors not normalized by the client (timeouts,
        // sockets): treat them as offline too.
        if (_isNetworkError(e)) {
          await _persistPending(blob, nonce, revision, current);
          return false;
        }
        rethrow;
      }
    }
    throw ApiException(0, 'sync_failed', 'Sincronizzazione non riuscita.');
  }

  /// True for connectivity failures: normalized [ApiException]s (status 0,
  /// code 'network') and raw transport errors.
  bool _isNetworkError(Object e) {
    if (e is ApiException) return e.isNetworkError;
    return e is http.ClientException ||
        e is TimeoutException ||
        e is SocketException;
  }

  /// Keeps the local edit: persists the encrypted [blob] with the current
  /// [revision] and marks the cache as [CachedVault.pendingSync] so it is
  /// pushed on the next connection (and survives an app restart).
  Future<void> _persistPending(
      Uint8List blob, Uint8List nonce, int revision, VaultData vault) async {
    await _updateCache(
        blob: blob,
        nonce: nonce,
        revision: revision,
        remote: false,
        pending: true);
    if (state.vault != null && !identical(state.vault, vault)) {
      state = state.copyWith(vault: vault);
    }
    state = state.copyWith(serverStatus: ServerStatus.offline);
  }

  /// Downloads the vault from the server and merges (LWW) it with the local one.
  Future<void> refreshFromServer() async {
    final cache = state.cache;
    final vaultKey = state.vaultKey;
    final token = state.token;
    if (cache == null || vaultKey == null || token == null) return;
    final latest = await client.vaultGet(token);
    if (latest.revision <= cache.revision) return;
    final remoteVault = VaultData.fromJson(VaultCrypto.decodeJson(
        await VaultCrypto.decrypt(vaultKey, latest.blob, latest.nonce)));
    // The server is authoritative when there are no unsynced local edits:
    // replace the vault entirely instead of a union merge, so deletions made
    // on other devices actually disappear here too (a pure LWW union has no
    // tombstones and would resurrect them in memory).
    final merged = state.pendingSync
        ? _mergeVaults(state.vault ?? VaultData(), remoteVault)
        : remoteVault;
    state = state.copyWith(vault: merged);
    await _updateCache(
        blob: latest.blob,
        nonce: latest.nonce,
        revision: latest.revision,
        remote: true);
    unawaited(_syncAutofillSnapshot(merged));
  }

  Future<void> _updateCache({
    required Uint8List blob,
    required Uint8List nonce,
    required int revision,
    required bool remote,
    bool pending = false,
  }) async {
    final cache = state.cache!;
    final updated = CachedVault(
      encryptedToken: cache.encryptedToken,
      tokenNonce: cache.tokenNonce,
      userId: cache.userId,
      username: cache.username,
      salt: cache.salt,
      kdf: cache.kdf,
      wrappedKey: cache.wrappedKey,
      wrappedRecovery: cache.wrappedRecovery,
      blob: blob,
      nonce: nonce,
      revision: revision,
      bioWrappedKey: cache.bioWrappedKey,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      pendingSync: pending,
      lastSyncedAt: pending ? cache.lastSyncedAt : DateTime.now().millisecondsSinceEpoch,
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
    await _wipeLocalState();
    state = SessionState();
  }

  Future<void> logoutAll() async {
    final token = state.token;
    if (token != null) {
      try {
        await client.logoutAll(token);
      } catch (_) {}
    }
    await _wipeLocalState();
    state = SessionState();
  }

  /// Master password change. [generateRecovery] creates/rotates the recovery key,
  /// [disableRecovery] removes it. Returns the new recovery key if generated.
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
    // Unwrap fails if the old password is wrong (no authHash in the cache).
    try {
      await VaultCrypto.unwrapKey(oldKek, cache.wrappedKey);
    } catch (_) {
      throw WrongPasswordException();
    }
    // The server still verifies the old password through the auth hash.
    final oldAuthHash = await sha256Bytes(oldKek);

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
      encryptedToken: cache.encryptedToken,
      tokenNonce: cache.tokenNonce,
      userId: cache.userId,
      username: cache.username,
      salt: newSalt,
      kdf: newKdf.toJson(),
      wrappedKey: newWrapped,
      wrappedRecovery: wrappedRecov,
      blob: cache.blob,
      nonce: cache.nonce,
      revision: cache.revision,
      bioWrappedKey: cache.bioWrappedKey,
      savedAt: cache.savedAt,
      pendingSync: cache.pendingSync,
      lastSyncedAt: cache.lastSyncedAt,
    );
    await _repo.saveCache(updated);
    state = state.copyWith(cache: updated);
    return newRecoveryKey;
  }

  /// Recovery: uses the recovery key to get back in and reset the password.
  /// Returns the new recovery key if requested.
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
    final cache = await CachedVault.withToken(
      vaultKey: vaultKey,
      token: session.token,
      userId: session.user.id,
      username: session.user.username,
      salt: newSalt,
      kdf: newKdf.toJson(),
      wrappedKey: newWrapped,
      wrappedRecovery: newWrappedRecov,
      blob: payload.blob,
      nonce: payload.nonce,
      revision: payload.revision,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
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

  Future<CachedVault> _buildCache(Session session, Uint8List vaultKey,
      Uint8List salt, KdfParams kdf, Uint8List wrapped,
      Uint8List? wrappedRecov, Uint8List blob, Uint8List nonce) {
    return CachedVault.withToken(
      vaultKey: vaultKey,
      token: session.token,
      userId: session.user.id,
      username: session.user.username,
      salt: salt,
      kdf: kdf.toJson(),
      wrappedKey: wrapped,
      wrappedRecovery: wrappedRecov,
      blob: blob,
      nonce: nonce,
      revision: session.user.vaultRevision,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// LWW merge per entry: union by id, the most recent updatedAt wins.
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

    final foldersById = <String, VaultFolder>{};
    for (final f in local.folders) {
      foldersById[f.id] = f;
    }
    for (final f in remote.folders) {
      final existing = foldersById[f.id];
      if (existing == null || f.updatedAt.isAfter(existing.updatedAt)) {
        foldersById[f.id] = f;
      }
    }
    final mergedFolders = foldersById.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return VaultData(entries: merged, folders: mergedFolders);
  }

  /// Adds a folder, persists and syncs the vault.
  Future<VaultFolder> addFolder(String name) {
    final folder = VaultFolder.create(name: name);
    return _mutateVault((vault) => VaultData(
          entries: vault.entries,
          folders: [...vault.folders, folder],
        )).then((_) => folder);
  }

  /// Renames a folder, persists and syncs the vault.
  Future<void> renameFolder(String folderId, String name) {
    return _mutateVault((vault) => VaultData(
          entries: vault.entries,
          folders: vault.folders
              .map((f) => f.id == folderId ? f.copyWith(name: name) : f)
              .toList(),
        ));
  }

  /// Deletes a folder and removes it from every entry, persists and syncs.
  Future<void> deleteFolder(String folderId) {
    return _mutateVault((vault) => VaultData(
          entries: vault.entries
              .map((e) => e.folderId == folderId
                  ? e.copyWith(folderId: () => null)
                  : e)
              .toList(),
          folders: vault.folders.where((f) => f.id != folderId).toList(),
        ));
  }

  /// Moves an entry into/out of a folder, persists and syncs.
  Future<void> moveEntryToFolder(String entryId, String? folderId) {
    return _mutateVault((vault) => VaultData(
          folders: vault.folders,
          entries: vault.entries
              .map((e) => e.id == entryId
                  ? e.copyWith(folderId: () => folderId)
                  : e)
              .toList(),
        ));
  }

  Future<void> _mutateVault(VaultData Function(VaultData) mutate) async {
    final current = state.vault;
    if (current == null) {
      throw StateError('vault non sbloccato');
    }
    await saveVault(mutate(current));
  }

  // ---- system autofill ------------------------------------------------

  /// True when running on Android (the only platform with the native service).
  bool get _autofillSupported => Platform.isAndroid;

  /// Sets up the native autofill service after an unlock: generates a fresh
  /// per-unlock snapshot key, sends it with the encrypted snapshot, and imports
  /// any credentials the system captured while the vault was locked.
  Future<void> _setupAutofill(Uint8List vaultKey, VaultData vault) async {
    if (!_autofillSupported) return;
    try {
      _autofillKey = VaultCrypto.randomBytes(32);
      final blob = await AutofillBridge.encryptSnapshot(_autofillKey!, vault);
      await _autofill.setSessionKey(_autofillKey!);
      await _autofill.syncSnapshot(blob);
    } catch (_) {
      // Channel unavailable (e.g. tests or non-Android host): nothing to do.
      _autofillKey = null;
      return;
    }
    // The user may have locked the vault while this setup was in flight: a
    // session key must never survive a lock.
    if (state.status != AuthStatus.unlocked) {
      await _autofill.clearSessionKey();
      _autofillKey = null;
      return;
    }
    // If this unlock was triggered by the autofill "vault locked" prompt (or by
    // a Credential Manager passkey request), drive the native activity from the
    // app: plain unlocks finish the activity, passkey requests get stashed into
    // the state so the UI can confirm/pick and return the credential.
    unawaited(_checkPasskeyLaunch());
    // Import credentials the system captured while the vault was locked. Runs
    // best-effort so a failure (e.g. server unreachable) never wipes the session.
    unawaited(_importPendingSaves());
  }

  /// Re-encrypts the snapshot with the current session key after a vault change.
  Future<void> _syncAutofillSnapshot(VaultData vault) async {
    final key = _autofillKey;
    if (!_autofillSupported || key == null) return;
    try {
      final blob = await AutofillBridge.encryptSnapshot(key, vault);
      await _autofill.syncSnapshot(blob);
    } catch (_) {}
  }

  /// Imports credentials captured by the system autofill framework. Existing
  /// entries (same url host + username) get the password updated; everything
  /// else is added as a new entry. The result is synced once and the native
  /// pending list is cleared. Best-effort: a failure (e.g. server unreachable)
  /// must never wipe the autofill session just established.
  Future<void> _importPendingSaves() async {
    try {
      final pending = await _autofill.pullPendingSaves();
      if (pending.isEmpty) return;
      final current = state.vault;
      if (current == null) return;
      var vault = current;
      var imported = 0;
      for (final p in pending) {
        final host = _urlHost(p.url);
        final existing = vault.entries.where((e) =>
            e.username == p.username &&
            (host == null || _urlHost(e.url) == host) &&
            (p.password.isNotEmpty));
        if (existing.isNotEmpty) {
          final first = existing.first;
          vault = vault.copyWith(
            entries: vault.entries
                .map((e) => e.id == first.id
                    ? e.copyWith(password: p.password)
                    : e)
                .toList(),
          );
        } else {
          vault = vault.copyWith(entries: [...vault.entries, p.toEntry()]);
        }
        imported++;
      }
      if (imported > 0) {
        await saveVault(vault);
        state = state.copyWith(lastAutofillImports: imported);
      }
      await _autofill.confirmPendingSaves();
    } catch (_) {
      // Never wipe the session because of a failed import.
    }
  }

  /// Detects how the current activity was launched and, for passkey create/get
  /// requests, moves the request stashed natively into the app state so the UI
  /// can drive the flow. Runs after every unlock and on resume.
  Future<void> _checkPasskeyLaunch() async {
    if (!_autofillSupported) return;
    try {
      final launch = await _autofill.getPasskeyLaunch();
      debugPrint('PassOnePasskey: checkPasskeyLaunch -> $launch');
      if (launch == 'create' && state.pendingPasskeyCreate == null) {
        final req = await _autofill.takePendingPasskeyCreate();
        debugPrint('PassOnePasskey: pending create=${req != null}');
        if (req != null) {
          state = state.copyWith(pendingPasskeyCreate: req);
        }
      } else if (launch == 'get' && state.pendingPasskeyGet == null) {
        final req = await _autofill.takePendingPasskeyGet();
        debugPrint('PassOnePasskey: pending get=${req != null}');
        if (req != null) {
          state = state.copyWith(pendingPasskeyGet: req);
        }
      } else if (launch == 'unlock') {
        // Plain autofill "vault locked" prompt: return to the host app.
        await _autofill.notifyUnlockFinished();
      }
    } catch (_) {
      // Channel unavailable (tests / non-Android host).
    }
  }

  /// Confirms a passkey registration requested by the system Credential
  /// Manager: generates the key pair natively, persists the passkey in the
  /// vault (and syncs it) and returns the registration response to the caller.
  Future<void> confirmPasskeyCreate() async {
    final req = state.pendingPasskeyCreate;
    if (req == null) return;
    state = state.copyWith(pendingPasskeyCreate: null);
    try {
      debugPrint('PassOnePasskey: confirmPasskeyCreate start');
      final outcome = await _autofill.passkeyCreateGenerate(
        requestJson: req['requestJson'] as String,
        username: (req['userName'] as String?) ?? '',
        userHandle: (req['userHandle'] as String?) ?? '',
      );
      final rpId =
          (outcome['rpId'] as String?) ?? ((req['rpId'] as String?) ?? '');
      final rpName = (req['rpName'] as String?)?.trim();
      final userName = (req['userName'] as String?)?.trim() ?? '';
      final userHandle = (req['userHandle'] as String?)?.trim() ?? '';
      final entry = VaultEntry.create(
        name: (rpName == null || rpName.isEmpty) ? rpId : rpName,
        url: 'https://$rpId',
        username: userName,
        passkeyCredentialId: outcome['credentialId'] as String?,
        passkeyPrivateKey: outcome['privateKeyPkcs8'] as String?,
        passkeyPublicKey: outcome['publicKeySpki'] as String?,
        passkeyRpId: rpId,
        passkeyUserHandle: userHandle.isEmpty ? null : userHandle,
        passkeyCounter: 0,
      );
      final vault = state.vault ?? VaultData();
      debugPrint('PassOnePasskey: saving passkey entry to vault (${vault.entries.length} entries)');
      await saveVault(VaultData(
        entries: [...vault.entries, entry],
        folders: vault.folders,
      ));
      debugPrint('PassOnePasskey: saveVault ok, sending createDone');
      await _autofill.passkeyCreateDone(outcome['responseJson'] as String);
    } catch (e) {
      debugPrint('PassOnePasskey: confirmPasskeyCreate FAILED: $e');
      // Nothing was persisted: cancel the native registration.
      await _autofill.passkeyCreateCancel();
      rethrow;
    }
  }

  /// Cancels a pending passkey registration.
  Future<void> cancelPasskeyCreate() async {
    state = state.copyWith(pendingPasskeyCreate: null);
    try {
      await _autofill.passkeyCreateCancel();
    } catch (_) {}
  }

  /// The vault passkeys matching the pending get request: same rpId and, when
  /// present in the request, in `allowCredentials`.
  List<VaultEntry> passkeyGetCandidates() {
    final req = state.pendingPasskeyGet;
    final vault = state.vault;
    if (req == null || vault == null) return const [];
    final rpId = (req['rpId'] as String?) ?? '';
    final allow = _allowCredentialIds((req['requestJson'] as String?) ?? '');
    final matches = vault.entries.where((e) {
      if (!e.isPasskey) return false;
      if (rpId.isNotEmpty && e.passkeyRpId != rpId) return false;
      if (allow.isNotEmpty && !allow.contains(e.passkeyCredentialId)) {
        return false;
      }
      return true;
    }).toList();
    debugPrint(
        'PassOnePasskey: passkeyGetCandidates rpId=$rpId allow=${allow.length} matches=${matches.length} (vaultPasskeys=${vault.entries.where((e) => e.isPasskey).length})');
    return matches;
  }

  Set<String> _allowCredentialIds(String requestJson) {
    try {
      final obj = jsonDecode(requestJson) as Map<String, dynamic>;
      final allow = obj['allowCredentials'];
      if (allow is List) {
        return allow
            .whereType<Map>()
            .map((m) => m['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
      }
    } catch (_) {}
    return const {};
  }

  /// Completes a passkey assertion requested while the vault was locked:
  /// signs with the selected passkey natively and returns the assertion to
  /// the system Credential Manager.
  Future<void> confirmPasskeyGet(VaultEntry entry) async {
    final req = state.pendingPasskeyGet;
    if (req == null) return;
    state = state.copyWith(pendingPasskeyGet: null);
    try {
      await _autofill.passkeyGetDone(
        requestJson: req['requestJson'] as String,
        clientDataHash: req['clientDataHash'] as String,
        credentialId: entry.passkeyCredentialId!,
        privateKeyPkcs8: entry.passkeyPrivateKey!,
        rpId: entry.passkeyRpId ?? ((req['rpId'] as String?) ?? ''),
        userHandle: entry.passkeyUserHandle,
        publicKey: entry.passkeyPublicKey,
      );
    } catch (e) {
      await _autofill.passkeyGetCancel();
      rethrow;
    }
  }

  /// Cancels a pending passkey assertion.
  Future<void> cancelPasskeyGet() async {
    state = state.copyWith(pendingPasskeyGet: null);
    try {
      await _autofill.passkeyGetCancel();
    } catch (_) {}
  }

  /// Resets the "N passwords imported" notice shown on the vault screen.
  void clearAutofillImportNotice() {
    if (state.lastAutofillImports != 0) {
      state = state.copyWith(lastAutofillImports: 0);
    }
  }

  /// Whether PassOne is the active system autofill service (Android only).
  Future<bool> isAutofillEnabled() async {
    if (!_autofillSupported) return false;
    try {
      return await _autofill.isAutofillEnabled();
    } catch (_) {
      return false;
    }
  }

  /// Opens the system screen to enable PassOne as autofill service.
  Future<void> openAutofillSettings() async {
    if (!_autofillSupported) return;
    try {
      await _autofill.openSystemSettings();
    } catch (_) {}
  }

  /// Whether every fill must be confirmed with biometrics/PIN (Android only).
  Future<bool> isAutofillRequireAuth() async {
    if (!_autofillSupported) return false;
    try {
      return await _autofill.isRequireAuthEnabled();
    } catch (_) {
      return false;
    }
  }

  /// Persists the "always ask before filling" preference natively.
  Future<void> setAutofillRequireAuth(bool enabled) async {
    if (!_autofillSupported) return;
    try {
      await _autofill.setRequireAuth(enabled);
    } catch (_) {}
  }

  static String? _urlHost(String url) {
    final cleaned =
        url.trim().replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    final host = cleaned.split('/').first.split(':').first.toLowerCase();
    if (host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  String _deviceName() {
    // V1: generic name; on Linux/Windows the hostname could be read.
    return 'PassOne';
  }
}
