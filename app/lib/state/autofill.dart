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

  /// When true, every autofill requires a biometric/PIN confirmation, even if
  /// the vault is already unlocked.
  Future<void> setRequireAuth(bool enabled) async {
    await _channel.invokeMethod<void>('setRequireAuth', {'enabled': enabled});
  }

  Future<bool> isRequireAuthEnabled() async {
    return await _channel.invokeMethod<bool>('getRequireAuth') ?? false;
  }

  /// Tells the native side that the vault was just unlocked from the autofill
  /// "vault locked" prompt, so the unlock activity can finish and return to the
  /// host app. No-op when the activity was not launched for autofill unlock.
  Future<void> notifyUnlockFinished() async {
    try {
      await _channel.invokeMethod<void>('autofillUnlockFinished');
    } catch (_) {}
  }

  /// How this activity instance was launched: "create" (passkey registration),
  /// "get" (passkey assertion after a locked vault), "unlock" (plain autofill
  /// unlock) or "none".
  Future<String> getPasskeyLaunch() async {
    try {
      return await _channel.invokeMethod<String>('getPasskeyLaunch') ?? 'none';
    } catch (_) {
      return 'none';
    }
  }

  /// The stashed create request (from the Credential Manager), or null.
  Future<Map<String, dynamic>?> takePendingPasskeyCreate() async {
    final m = await _channel.invokeMapMethod<dynamic, dynamic>(
      'takePendingPasskeyCreate',
    );
    if (m == null) return null;
    return Map<String, dynamic>.from(m);
  }

  /// The stashed get request (request JSON + client data hash + rpId), or null.
  Future<Map<String, dynamic>?> takePendingPasskeyGet() async {
    final m = await _channel.invokeMapMethod<dynamic, dynamic>(
      'takePendingPasskeyGet',
    );
    if (m == null) return null;
    return Map<String, dynamic>.from(m);
  }

  /// Asks the native side to generate a new key pair and build the WebAuthn
  /// registration response for the given create request.
  Future<Map<String, dynamic>> passkeyCreateGenerate({
    required String requestJson,
    required String username,
    required String userHandle,
  }) async {
    final m = await _channel.invokeMapMethod<dynamic, dynamic>(
      'passkeyCreateGenerate',
      {
        'requestJson': requestJson,
        'username': username,
        'userHandle': userHandle,
      },
    );
    return Map<String, dynamic>.from(m!);
  }

  /// Tells the native side the passkey was persisted: the launch activity
  /// finishes with the registration response, returning to the host app.
  Future<void> passkeyCreateDone(String responseJson) async {
    await _channel.invokeMethod<void>(
      'passkeyCreateDone',
      {'responseJson': responseJson},
    );
  }

  Future<void> passkeyCreateCancel() async {
    await _channel.invokeMethod<void>('passkeyCreateCancel');
  }

  /// Completes a passkey assertion initiated while the vault was locked. The
  /// native side signs with [privateKeyPkcs8] and returns the result to the
  /// Credential Manager framework.
  Future<void> passkeyGetDone({
    required String requestJson,
    required String clientDataHash,
    required String credentialId,
    required String privateKeyPkcs8,
    required String rpId,
    required String? userHandle,
    required String? publicKey,
  }) async {
    await _channel.invokeMethod<void>('passkeyGetDone', {
      'requestJson': requestJson,
      'clientDataHash': clientDataHash,
      'credentialId': credentialId,
      'privateKey': privateKeyPkcs8,
      'rpId': rpId,
      'userHandle': userHandle,
      'publicKey': publicKey,
    });
  }

  Future<void> passkeyGetCancel() async {
    await _channel.invokeMethod<void>('passkeyGetCancel');
  }

  Future<void> openSystemSettings() async {
    await _channel.invokeMethod<void>('openSettings');
  }

  /// Builds the credential snapshot and encrypts it with [key] into
  /// nonce(12) || AES-GCM ciphertext+tag.
  ///
  /// v2 adds a `passkeys` array (one object per WebAuthn passkey) on top of
  /// the v1 `entries` (username+password) array, so the native services can
  /// offer passkeys from the Credential Manager provider.
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
    final passkeys = vault.entries
        .where((e) => e.isPasskey)
        .map((e) => {
              'id': e.id,
              'name': e.name,
              'username': e.username,
              'url': e.url,
              'credentialId': e.passkeyCredentialId,
              'privateKey': e.passkeyPrivateKey,
              'publicKey': e.passkeyPublicKey,
              'rpId': e.passkeyRpId,
              'userHandle': e.passkeyUserHandle,
              'counter': e.passkeyCounter,
            })
        .toList();
    final payload = VaultCrypto.encodeJson({
      'v': 2,
      'entries': entries,
      'passkeys': passkeys,
    });
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
