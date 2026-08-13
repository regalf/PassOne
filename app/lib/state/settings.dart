import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/vault_crypto.dart';

/// Lock timeout. [minutes] is -1 for "always".
enum LockTimeout {
  one(1),
  two(2),
  five(5),
  ten(10),
  always(-1);

  const LockTimeout(this.minutes);
  final int minutes;

  String get label => minutes < 0 ? 'Sempre (sconsigliato)' : '$minutes minuti';

  static LockTimeout fromMinutes(int m) {
    for (final t in LockTimeout.values) {
      if (t.minutes == m) return t;
    }
    return LockTimeout.one;
  }
}

/// App settings persisted in shared_preferences.
class AppSettings {
  final String serverUrl;
  final String? lastUsername;
  final LockTimeout lockTimeout;
  final bool biometricsEnabled;

  /// Forced language code: null = follows the system language,
  /// 'it' or 'en' for an explicit choice.
  final String? languageCode;

  const AppSettings({
    this.serverUrl = '',
    this.lastUsername,
    this.lockTimeout = LockTimeout.five,
    this.biometricsEnabled = false,
    this.languageCode,
  });

  AppSettings copyWithServerUrl(String url) => AppSettings(
      serverUrl: url,
      lastUsername: lastUsername,
      lockTimeout: lockTimeout,
      biometricsEnabled: biometricsEnabled,
      languageCode: languageCode);
  AppSettings copyWithLockTimeout(LockTimeout t) => AppSettings(
      serverUrl: serverUrl,
      lastUsername: lastUsername,
      lockTimeout: t,
      biometricsEnabled: biometricsEnabled,
      languageCode: languageCode);
  AppSettings copyWithLastUsername(String u) => AppSettings(
      serverUrl: serverUrl,
      lastUsername: u,
      lockTimeout: lockTimeout,
      biometricsEnabled: biometricsEnabled,
      languageCode: languageCode);
  AppSettings copyWithBiometricsEnabled(bool v) => AppSettings(
      serverUrl: serverUrl,
      lastUsername: lastUsername,
      lockTimeout: lockTimeout,
      biometricsEnabled: v,
      languageCode: languageCode);
  AppSettings copyWithLanguageCode(String? code) => AppSettings(
      serverUrl: serverUrl,
      lastUsername: lastUsername,
      lockTimeout: lockTimeout,
      biometricsEnabled: biometricsEnabled,
      languageCode: code);
}

/// Encrypted vault cache + materials for offline unlock.
///
/// The session token is never stored in plaintext: it is kept encrypted with
/// the vault key (AES-256-GCM), so the on-disk file only holds ciphertext.
/// [tokenNonce] is empty for caches written before this change (legacy
/// plaintext token): [decryptToken] falls back to reading it directly.
class CachedVault {
  final Uint8List encryptedToken;
  final Uint8List tokenNonce;
  final int userId;
  final String username;
  final Uint8List salt;
  final Map<String, dynamic> kdf;
  final Uint8List wrappedKey;
  final Uint8List? wrappedRecovery;
  final Uint8List blob;
  final Uint8List nonce;
  final int revision;
  final Uint8List? bioWrappedKey;

  CachedVault({
    required this.encryptedToken,
    required this.tokenNonce,
    required this.userId,
    required this.username,
    required this.salt,
    required this.kdf,
    required this.wrappedKey,
    required this.wrappedRecovery,
    required this.blob,
    required this.nonce,
    required this.revision,
    this.bioWrappedKey,
  });

  /// Builds a cache encrypting [token] with [vaultKey].
  static Future<CachedVault> withToken({
    required Uint8List vaultKey,
    required String token,
    required int userId,
    required String username,
    required Uint8List salt,
    required Map<String, dynamic> kdf,
    required Uint8List wrappedKey,
    required Uint8List? wrappedRecovery,
    required Uint8List blob,
    required Uint8List nonce,
    required int revision,
    Uint8List? bioWrappedKey,
  }) async {
    final (encryptedToken, tokenNonce) =
        await VaultCrypto.encrypt(vaultKey, utf8.encode(token));
    return CachedVault(
      encryptedToken: encryptedToken,
      tokenNonce: tokenNonce,
      userId: userId,
      username: username,
      salt: salt,
      kdf: kdf,
      wrappedKey: wrappedKey,
      wrappedRecovery: wrappedRecovery,
      blob: blob,
      nonce: nonce,
      revision: revision,
      bioWrappedKey: bioWrappedKey,
    );
  }

  /// Decrypts and returns the session token with [vaultKey], or null if the
  /// decryption fails. Legacy caches (empty [tokenNonce]) return the token as-is.
  Future<String?> decryptToken(Uint8List vaultKey) async {
    try {
      final clear = tokenNonce.isEmpty
          ? encryptedToken
          : await VaultCrypto.decrypt(vaultKey, encryptedToken, tokenNonce);
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  /// Returns a copy with [token] re-encrypted (used to migrate legacy caches
  /// that still hold a plaintext token after the first unlock).
  Future<CachedVault> reencryptToken(
          Uint8List vaultKey, String token) async =>
      withToken(
        vaultKey: vaultKey,
        token: token,
        userId: userId,
        username: username,
        salt: salt,
        kdf: kdf,
        wrappedKey: wrappedKey,
        wrappedRecovery: wrappedRecovery,
        blob: blob,
        nonce: nonce,
        revision: revision,
        bioWrappedKey: bioWrappedKey,
      );

  Map<String, dynamic> toJson() => {
        'encryptedToken': base64.encode(encryptedToken),
        'tokenNonce': base64.encode(tokenNonce),
        'userId': userId,
        'username': username,
        'salt': base64.encode(salt),
        'kdf': kdf,
        'wrappedKey': base64.encode(wrappedKey),
        'wrappedRecovery': wrappedRecovery == null ? null : base64.encode(wrappedRecovery!),
        'blob': base64.encode(blob),
        'nonce': base64.encode(nonce),
        'revision': revision,
        'bioWrappedKey':
            bioWrappedKey == null ? null : base64.encode(bioWrappedKey!),
      };

  factory CachedVault.fromJson(Map<String, dynamic> j) {
    final legacyToken = j['token'] as String?;
    return CachedVault(
      encryptedToken: j['encryptedToken'] == null
          ? Uint8List.fromList(utf8.encode(legacyToken ?? ''))
          : base64.decode(j['encryptedToken'] as String),
      tokenNonce: j['tokenNonce'] == null
          ? Uint8List(0)
          : base64.decode(j['tokenNonce'] as String),
      userId: (j['userId'] as num).toInt(),
      username: j['username'] as String,
      salt: base64.decode(j['salt'] as String),
      kdf: (j['kdf'] as Map).cast<String, dynamic>(),
      wrappedKey: base64.decode(j['wrappedKey'] as String),
      wrappedRecovery: j['wrappedRecovery'] == null
          ? null
          : base64.decode(j['wrappedRecovery'] as String),
      blob: base64.decode(j['blob'] as String),
      nonce: base64.decode(j['nonce'] as String),
      revision: (j['revision'] as num).toInt(),
      bioWrappedKey: j['bioWrappedKey'] == null
          ? null
          : base64.decode(j['bioWrappedKey'] as String),
    );
  }
}

/// Persistence of settings and vault cache.
class SettingsRepository {
  static const _kServerUrl = 'serverUrl';
  static const _kLastUsername = 'lastUsername';
  static const _kLockTimeout = 'lockTimeoutMinutes';
  static const _kBiometrics = 'biometricsEnabled';
  static const _kLanguage = 'languageCode';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      serverUrl: prefs.getString(_kServerUrl) ?? '',
      lastUsername: prefs.getString(_kLastUsername),
      lockTimeout:
          LockTimeout.fromMinutes(prefs.getInt(_kLockTimeout) ?? 5),
      biometricsEnabled: prefs.getBool(_kBiometrics) ?? false,
      languageCode: prefs.getString(_kLanguage),
    );
  }

  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerUrl, s.serverUrl);
    if (s.lastUsername != null) {
      await prefs.setString(_kLastUsername, s.lastUsername!);
    }
    await prefs.setInt(_kLockTimeout, s.lockTimeout.minutes);
    await prefs.setBool(_kBiometrics, s.biometricsEnabled);
    if (s.languageCode != null) {
      await prefs.setString(_kLanguage, s.languageCode!);
    } else {
      await prefs.remove(_kLanguage);
    }
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}vault.cache.json');
  }

  Future<CachedVault?> loadCache() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return CachedVault.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCache(CachedVault cache) async {
    final f = await _cacheFile();
    // Atomic write: temp file + rename so a crash/power loss cannot leave a
    // partially written cache behind.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(cache.toJson()), flush: true);
    await tmp.rename(f.path);
    await _restrictCachePermissions(f);
  }

  /// Restricts the cache file to the owner (0600) on desktop platforms.
  /// On Android/iOS the app directory is already sandboxed by the OS.
  Future<void> _restrictCachePermissions(File f) async {
    if (Platform.isAndroid || Platform.isIOS) return;
    try {
      final res = await Process.run('chmod', ['600', f.path]);
      if (res.exitCode != 0) {
        developer.log(
          'could not restrict cache permissions',
          name: 'passone.settings',
          error: res.stderr,
        );
      }
    } catch (e) {
      // Best effort: chmod may be unavailable; the home dir is usually
      // already private (0700) on desktop Linux.
      developer.log(
        'could not restrict cache permissions',
        name: 'passone.settings',
        error: e,
      );
    }
  }

  Future<void> clearCache() async {
    final f = await _cacheFile();
    if (await f.exists()) {
      await f.delete();
    }
  }
}

/// SHA-256 (used for authHash and recovery hash).
Future<Uint8List> sha256Bytes(List<int> data) async {
  final hash = await Sha256().hash(data);
  return Uint8List.fromList(hash.bytes);
}
