import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Decodifica una stringa Base32 (RFC 4648, senza padding) in byte.
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

/// Codifica byte in Base32 senza padding.
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

/// Genera il codice TOTP a 6 cifre (RFC 6238, HMAC-SHA1, periodo 30s).
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

/// Secondi mancanti al cambio del codice corrente.
int totpSecondsLeft(DateTime time) => 30 - (time.millisecondsSinceEpoch ~/ 1000) % 30;

/// Dati estratti da un URI otpauth:// (o da una chiave Base32 nuda).
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

/// Interpreta un QR: accetta l'URI `otpauth://totp/...` (issuer/account/secret)
/// oppure una chiave Base32 nuda. Restituisce null se non valido.
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

/// Valida una chiave Base32 restituendola normalizzata, o null se invalida.
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

/// Verifica un codice TOTP a 6 cifre per [secretBase32]. Tolleranza di ±1
/// finestra: se l'utente digita mentre il codice cambia, il codice della
/// finestra precedente/successiva viene comunque accettato.
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
