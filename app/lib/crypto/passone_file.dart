import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'kdf.dart';
import 'models.dart';
import 'vault_crypto.dart';

/// Wrong password, corrupted data or unsupported format.
class PassoneDecryptException implements Exception {
  @override
  String toString() => 'Cannot decrypt the PassOne file.';
}

/// Encrypted PassOne export format (`.passone`).
///
/// A self-describing JSON envelope holding the KDF parameters and the
/// AES-256-GCM ciphertext of the vault JSON:
///
///   {format, version, kdf, salt_b64, nonce_b64, data_b64}
class PassoneFile {
  static const String format = 'passone';
  static const int version = 1;

  /// Encrypts [vault] with [password] and returns the `.passone` envelope.
  static Future<String> encrypt(VaultData vault, String password) async {
    final salt = VaultCrypto.randomBytes(16);
    final kdf = const KdfParams.argon2id();
    final key = await Kdf().derive(password, salt, kdf);
    final (blob, nonce) = await VaultCrypto.encrypt(
        key, VaultCrypto.encodeJson(vault.toJson()));
    return jsonEncode({
      'format': format,
      'version': version,
      'kdf': kdf.toJson(),
      'salt_b64': VaultCrypto.bytesToB64(salt),
      'nonce_b64': VaultCrypto.bytesToB64(nonce),
      'data_b64': VaultCrypto.bytesToB64(blob),
    });
  }

  /// Decrypts a [content] envelope with [password].
  ///
  /// Throws [PassoneDecryptException] on wrong password, corrupted data or
  /// unsupported format/version.
  static Future<VaultData> decrypt(String content, String password) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      throw PassoneDecryptException();
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != format) {
      throw PassoneDecryptException();
    }
    if (decoded['version'] != version) {
      throw PassoneDecryptException();
    }
    try {
      final salt = VaultCrypto.b64ToBytes(decoded['salt_b64'] as String);
      final nonce = VaultCrypto.b64ToBytes(decoded['nonce_b64'] as String);
      final blob = VaultCrypto.b64ToBytes(decoded['data_b64'] as String);
      final kdf = KdfParams.fromJson(decoded['kdf'] as Map<String, dynamic>);
      final key = await Kdf().derive(password, salt, kdf);
      final clear = await VaultCrypto.decrypt(key, blob, nonce);
      return VaultData.fromJson(VaultCrypto.decodeJson(clear));
    } on SecretBoxAuthenticationError {
      throw PassoneDecryptException();
    } on FormatException {
      throw PassoneDecryptException();
    }
  }
}
