import 'package:flutter/services.dart';

import '../crypto/models.dart';
import '../crypto/vault_crypto.dart';

/// Bridge to the native Android autofill service via the platform channel.
///
/// The service runs outside the Flutter isolate, so it cannot read the
/// decrypted vault. Instead:
///  - while the vault is unlocked the app sends the *encrypted* credential
///    snapshot plus a fresh per-unlock session key;
///  - on lock the session key is wiped, so the service can no longer decrypt
///    the snapshot and stops offering autofill;
///  - credentials saved from other apps (onSaveRequest) are held on the native
///    side and pulled back here to be imported into the vault.
class AutofillBridge {
  static const MethodChannel _channel = MethodChannel('passone/autofill');

  Future<void> setSessionKey(Uint8List key) async {
    await _channel.invokeMethod<void>(
      'setSessionKey',
      {'key': VaultCrypto.bytesToB64(key)},
    );
  }

  Future<void> clearSessionKey() async {
    await _channel.invokeMethod<void>('clearSessionKey');
  }

  /// Sends the snapshot encrypted with the session key (nonce || ciphertext+tag).
  Future<void> syncSnapshot(Uint8List encryptedBlob) async {
    await _channel.invokeMethod<void>(
      'syncSnapshot',
      {'blob': VaultCrypto.bytesToB64(encryptedBlob)},
    );
  }

  /// Credentials saved by the system autofill framework while the vault was
  /// locked/unlocked, still encrypted on the native side.
  Future<List<PendingSave>> pullPendingSaves() async {
    final list = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
      'pullPendingSaves',
    );
    if (list == null) return const [];
    return list
        .map((m) => PendingSave.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> confirmPendingSaves() async {
    await _channel.invokeMethod<void>('confirmPendingSaves');
  }

  Future<bool> isAutofillEnabled() async {
    return await _channel.invokeMethod<bool>('isEnabled') ?? false;
  }

  Future<void> openSystemSettings() async {
    await _channel.invokeMethod<void>('openSettings');
  }

  /// Builds the credential snapshot (only entries with username+password) and
  /// encrypts it with [key] into nonce(12) || AES-GCM ciphertext+tag.
  static Future<Uint8List> encryptSnapshot(
      Uint8List key, VaultData vault) async {
    final entries = vault.entries
        .where((e) => e.username.isNotEmpty && e.password.isNotEmpty)
        .map((e) => {
              'id': e.id,
              'name': e.name,
              'username': e.username,
              'password': e.password,
              'url': e.url,
            })
        .toList();
    final payload = VaultCrypto.encodeJson({'v': 1, 'entries': entries});
    final (blob, nonce) = await VaultCrypto.encrypt(key, payload);
    final out = Uint8List(nonce.length + blob.length);
    out.setRange(0, nonce.length, nonce);
    out.setRange(nonce.length, out.length, blob);
    return out;
  }
}

/// A credential captured by the system autofill service, waiting to be
/// imported into the vault.
class PendingSave {
  final String id;
  final String name;
  final String username;
  final String password;
  final String url;
  final String notes;
  final int createdAt;
  final int updatedAt;

  const PendingSave({
    required this.id,
    required this.name,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PendingSave.fromMap(Map<String, dynamic> m) => PendingSave(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        username: m['username'] as String? ?? '',
        password: m['password'] as String? ?? '',
        url: m['url'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
        createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (m['updatedAt'] as num?)?.toInt() ?? 0,
      );

  VaultEntry toEntry() => VaultEntry.create(
        name: name.isEmpty ? url : name,
        url: url,
        username: username,
        password: password,
        notes: notes,
      );
}
