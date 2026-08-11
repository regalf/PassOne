import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Decodes a Base32 string (RFC 4648, without padding) into bytes.
Uint8List base32Decode(String input) {
  final s = input
      .toUpperCase()
      .replaceAll(RegExp(r'[\s=]'), '');
  final out = BytesBuilder();
  var buffer = 0;
  var bits = 0;
  for (var i = 0; i < s.length; i++) {
    final c = _alphabet.indexOf(s[i]);
    if (c < 0) {
      throw FormatException('Carattere Base32 non valido: ${s[i]}');
    }
    buffer = (buffer << 5) | c;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.addByte((buffer >> bits) & 0xff);
    }
  }
  return out.toBytes();
}

/// Encodes bytes into Base32 without padding.
String base32Encode(Uint8List bytes) {
  final buf = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      buf.write(_alphabet[(buffer >> bits) & 0x1f]);
    }
  }
  if (bits > 0) {
    buf.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
  }
  return buf.toString();
}

/// Generates the 6-digit TOTP code (RFC 6238, HMAC-SHA1, 30s period).
Future<String> generateTotp(String secretBase32, {DateTime? time}) async {
  final secret = base32Decode(secretBase32);
  final counter = ((time ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000) ~/ 30;
  final msg = ByteData(8)..setUint64(0, counter);
  final mac = await Hmac.sha1().calculateMac(
      msg.buffer.asUint8List(), secretKey: SecretKey(secret));
  final h = mac.bytes;
  final offset = h[h.length - 1] & 0x0f;
  final bin = ((h[offset] & 0x7f) << 24) |
      ((h[offset + 1] & 0xff) << 16) |
      ((h[offset + 2] & 0xff) << 8) |
      (h[offset + 3] & 0xff);
  return (bin % 1000000).toString().padLeft(6, '0');
}

/// Seconds remaining until the current code changes.
int totpSecondsLeft(DateTime time) => 30 - (time.millisecondsSinceEpoch ~/ 1000) % 30;

/// Data extracted from an otpauth:// URI (or from a bare Base32 key).
class TotpUriData {
  final String secret;
  final String? issuer;
  final String? account;

  const TotpUriData({required this.secret, this.issuer, this.account});

  String get label {
    if (issuer != null && account != null && account!.isNotEmpty) {
      return '$issuer: $account';
    }
    return issuer ?? account ?? '';
  }
}

/// Parses a QR: accepts an `otpauth://totp/...` URI (issuer/account/secret)
/// or a bare Base32 key. Returns null if not valid.
TotpUriData? parseTotp(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('otpauth://')) {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host != 'totp') return null;
    final label = Uri.decodeComponent(
        (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '').replaceFirst(RegExp(r'^/'), ''));
    String? issuer;
    String? account;
    final colon = label.indexOf(':');
    if (colon >= 0) {
      issuer = label.substring(0, colon);
      account = label.substring(colon + 1);
    } else {
      account = label;
    }
    final secret = (uri.queryParameters['secret'] ?? '').toUpperCase();
    if (secret.isEmpty) return null;
    try {
      base32Decode(secret);
    } on FormatException {
      return null;
    }
    final queryIssuer = uri.queryParameters['issuer'];
    return TotpUriData(
      secret: secret,
      issuer: queryIssuer ?? issuer,
      account: account,
    );
  }
  final secret = text.toUpperCase().replaceAll(RegExp(r'[\s=]'), '');
  try {
    base32Decode(secret);
  } on FormatException {
    return null;
  }
  return TotpUriData(secret: secret);
}

/// Validates a Base32 key returning it normalized, or null if invalid.
String? normalizeTotpSecret(String input) {
  final t = parseTotp(input);
  if (t == null) return null;
  try {
    base32Decode(t.secret);
  } on FormatException {
    return null;
  }
  return t.secret;
}

/// Verifies a 6-digit TOTP code for [secretBase32]. ±1 window tolerance:
/// if the user types while the code changes, the code from the previous/next
/// window is still accepted.
Future<bool> verifyTotp(String secretBase32, String code,
    {DateTime? time}) async {
  final normalized = code.trim();
  if (normalized.length != 6 || int.tryParse(normalized) == null) return false;
  final now = time ?? DateTime.now();
  for (final i in [-1, 0, 1]) {
    final expected = await generateTotp(secretBase32,
        time: now.add(Duration(seconds: i * 30)));
    if (expected == normalized) return true;
  }
  return false;
}
