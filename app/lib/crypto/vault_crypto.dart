import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Operazioni AEAD e di envelope sul vault.
class VaultCrypto {
  static const int _nonceLength = 12;
  static const int _tagLength = 16;

  static final AesGcm _aesGcm = AesGcm.with256bits();

  static Uint8List randomBytes(int length) {
    final rng = Random.secure();
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }

  static Uint8List generateVaultKey() => randomBytes(32);

  /// Cripta [data] con AES-256-GCM restituendo (blob, nonce).
  /// Il blob contiene solo ciphertext+tag: il nonce è restituito a parte.
  static Future<(Uint8List, Uint8List)> encrypt(
      Uint8List key, Uint8List data) async {
    final nonce = randomBytes(_nonceLength);
    final box = await _aesGcm.encrypt(
      data,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    return (Uint8List.fromList(box.concatenation(nonce: false)), nonce);
  }

  /// Decripta [blob] (ciphertext+tag) con [nonce].
  static Future<Uint8List> decrypt(
      Uint8List key, Uint8List blob, Uint8List nonce) async {
    final box = SecretBox(
      blob.sublist(0, blob.length - _tagLength),
      nonce: nonce,
      mac: Mac(blob.sublist(blob.length - _tagLength)),
    );
    final clear = await _aesGcm.decrypt(box, secretKey: SecretKey(key));
    return Uint8List.fromList(clear);
  }

  /// Avvolge una chiave (es. vault_key) con una chiave di wrapping (KEK o recovery).
  /// Formato: [nonce(12) || ciphertext+tag].
  static Future<Uint8List> wrapKey(Uint8List wrappingKey, Uint8List key) async {
    final (blob, nonce) = await encrypt(wrappingKey, key);
    final out = Uint8List(_nonceLength + blob.length);
    out.setRange(0, _nonceLength, nonce);
    out.setRange(_nonceLength, out.length, blob);
    return out;
  }

  /// Srotola una chiave avvolta con [wrapKey].
  static Future<Uint8List> unwrapKey(
      Uint8List wrappingKey, Uint8List wrapped) async {
    if (wrapped.length < _nonceLength + _tagLength) {
      throw const FormatException('chiave avvolta non valida');
    }
    final nonce = wrapped.sublist(0, _nonceLength);
    final blob = wrapped.sublist(_nonceLength);
    return decrypt(wrappingKey, blob, nonce);
  }

  /// JSON → bytes UTF-8.
  static Uint8List encodeJson(Map<String, dynamic> json) =>
      Uint8List.fromList(utf8.encode(jsonEncode(json)));

  static Map<String, dynamic> decodeJson(Uint8List bytes) =>
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

  static String bytesToB64(List<int> bytes) =>
      base64.encode(bytes);

  static Uint8List b64ToBytes(String b64) =>
      Uint8List.fromList(base64.decode(b64));
}
