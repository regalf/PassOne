import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'kdf.dart';
import 'models.dart';
import 'vault_crypto.dart';

/// Wrong password, corrupted data or unsupported format.
class PassoneDecryptException implements Exception {
  @override
  String toString() => 'Cannot decrypt the PassOne file.';
}

/// The envelope is malformed or requests KDF parameters that are not
/// supported (out of range, unknown algorithm).
class PassoneFormatException implements Exception {
  PassoneFormatException(this.message);

  final String message;

  @override
  String toString() => message;
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
  ///
  /// Argon2id is used when the native library is available, otherwise
  /// PBKDF2-HMAC-SHA256. Unlike the server-side case, this fallback is safe:
  /// the envelope is self-describing and carries the KDF parameters actually
  /// used, so the file can always be decrypted again.
  static Future<String> encrypt(VaultData vault, String password) async {
    final salt = VaultCrypto.randomBytes(16);
    KdfParams kdf = const KdfParams.argon2id();
    Uint8List key;
    try {
      key = await Kdf().derive(password, salt, kdf);
    } on KdfUnavailableException {
      kdf = const KdfParams.pbkdf2(iterations: 600000);
      key = await Kdf().derive(password, salt, kdf);
    }
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

  /// Returns true when [content] looks like a PassOne envelope (regardless of
  /// the file name), so callers can decide to ask for the password.
  static bool isPassoneEnvelope(String content) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      return false;
    }
    return decoded is Map<String, dynamic> && decoded['format'] == format;
  }

  /// Decrypts a [content] envelope with [password].
  ///
  /// Throws [PassoneDecryptException] on wrong password, corrupted data or
  /// unsupported version, [PassoneFormatException] on a malformed envelope
  /// and [KdfUnavailableException] when the requested KDF is not available
  /// on this device.
  static Future<VaultData> decrypt(String content, String password) async {
    if (!isPassoneEnvelope(content)) {
      throw PassoneDecryptException();
    }
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    if (decoded['version'] != version) {
      throw PassoneDecryptException();
    }
    final KdfParams kdf;
    try {
      kdf = KdfParams.fromJson(decoded['kdf'] as Map<String, dynamic>);
    } on InvalidKdfParamsException catch (e) {
      throw PassoneFormatException(e.message);
    } on FormatException catch (e) {
      throw PassoneFormatException(e.message);
    }
    try {
      final salt = VaultCrypto.b64ToBytes(decoded['salt_b64'] as String);
      final nonce = VaultCrypto.b64ToBytes(decoded['nonce_b64'] as String);
      final blob = VaultCrypto.b64ToBytes(decoded['data_b64'] as String);
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
