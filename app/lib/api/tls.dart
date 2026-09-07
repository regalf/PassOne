import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// SHA-256 of the certificate's SPKI (SubjectPublicKeyInfo), formatted as a
/// lowercase hex string. The server computes the same fingerprint over
/// `x509.MarshalPKIXPublicKey(cert.PublicKey)`, i.e. over the SPKI DER that
/// sits inside the X.509 certificate: the fingerprint therefore matches
/// byte-for-byte when computed on this device.
///
/// Synchronous: it runs inside the TLS `badCertificateCallback`, which cannot
/// await. Returns null when the certificate cannot be parsed.
String? spkiFingerprintHex(X509Certificate cert) {
  try {
    final spki = extractSpkiFromCert(cert.der);
    return bytesToHex(sha256.convert(spki).bytes);
  } catch (_) {
    return null;
  }
}

String bytesToHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// Extracts the SubjectPublicKeyInfo DER from an X.509 certificate DER:
/// the first element of the outer SEQUENCE is the TBSCertificate, whose
/// 7th element is the SubjectPublicKeyInfo.
Uint8List extractSpkiFromCert(Uint8List derCert) {
  var offset = 0;
  offset = _expectTag(derCert, offset, 0x30); // Certificate (SEQUENCE)
  final (_, oc) = _readLength(derCert, offset);
  offset += oc;
  offset = _expectTag(derCert, offset, 0x30); // TBSCertificate (SEQUENCE)
  final (_, tc) = _readLength(derCert, offset);
  offset += tc;
  for (var i = 0; i < 6; i++) {
    offset = _seekNextElement(derCert, offset);
  }
  final spkiStart = offset;
  offset = _expectTag(derCert, offset, 0x30); // SubjectPublicKeyInfo
  final (len, lc) = _readLength(derCert, offset);
  offset += lc + len;
  return derCert.sublist(spkiStart, offset);
}

int _expectTag(Uint8List data, int offset, int tag) {
  if (offset >= data.length || data[offset] != tag) {
    throw const FormatException('DER: unexpected tag');
  }
  return offset + 1;
}

(int, int) _readLength(Uint8List data, int offset) {
  final first = data[offset];
  if (first < 0x80) return (first, 1);
  final numBytes = first & 0x7f;
  var length = 0;
  for (var i = 0; i < numBytes; i++) {
    length = (length << 8) | data[offset + 1 + i];
  }
  return (length, 1 + numBytes);
}

int _seekNextElement(Uint8List data, int offset) {
  offset++; // tag byte (X.509 uses single-byte tags)
  final (contentLen, lenBytes) = _readLength(data, offset);
  offset += lenBytes;
  return offset + contentLen;
}

/// Normalizes a manually typed pairing code into its canonical form: 64
/// lowercase hex characters (the SPKI fingerprint). Accepts extra separators
/// (colons, spaces), the `0x` prefix and the `sha256:` prefix. Returns null
/// when the input is not a plausible pairing code.
String? normalizePairingCode(String input) {
  var s = input.trim();
  if (s.toLowerCase().startsWith('0x')) s = s.substring(2);
  if (s.toLowerCase().startsWith('sha256:')) s = s.substring('sha256:'.length);
  final hex = s.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
  if (hex.length != 64) return null;
  final ok = hex.codeUnits.every((c) =>
      (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66));
  return ok ? hex : null;
}

/// Extracts the pairing code from a scanned text: either a raw fingerprint or
/// a PassOne pairing URI (`passone://pair/<fp>`, `passone://pair?fp=...`).
/// Returns null when the content does not carry a valid fingerprint.
String? pairingCodeFromQrText(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri != null && uri.scheme == 'passone') {
    return pairingCodeFromUri(uri);
  }
  return normalizePairingCode(input);
}

String? pairingCodeFromUri(Uri uri) {
  final parts = <String>[
    if (uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments,
  ];
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].toLowerCase() == 'pair' && i + 1 < parts.length) {
      final code = normalizePairingCode(parts[i + 1]);
      if (code != null) return code;
    }
  }
  // Opaque form `passone:pair:<fp>`: the whole path is a single segment.
  final path = uri.path;
  if (path.toLowerCase().startsWith('pair:')) {
    final code = normalizePairingCode(path.substring('pair:'.length));
    if (code != null) return code;
  }
  final fp = uri.queryParameters['fp'];
  return fp == null ? null : normalizePairingCode(fp);
}

/// Group a hex fingerprint in blocks like the server/CLI might display it
/// (used only for cosmetic, non-authoritative display).
String groupHex(String hex, [int blockLen = 8]) {
  final upper = hex.toUpperCase();
  final sb = StringBuffer();
  for (var i = 0; i < upper.length; i++) {
    if (i > 0 && i % blockLen == 0) sb.write(' ');
    sb.write(upper[i]);
  }
  return sb.toString();
}