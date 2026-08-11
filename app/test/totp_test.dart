import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:passone_app/crypto/models.dart';
import 'package:passone_app/crypto/totp.dart';

void main() {
  group('base32', () {
    test('decode/encode roundtrip RFC 4648', () {
      const ascii = '12345678901234567890';
      final bytes = Uint8List.fromList(ascii.codeUnits);
      final encoded = base32Encode(bytes);
      expect(encoded, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(String.fromCharCodes(base32Decode(encoded)), ascii);
    });

    test('decode tolerates lowercase, spaces and padding', () {
      final decoded = base32Decode('gezd gnbv gy3t qojq gezd gnbv gy3t qojq');
      expect(String.fromCharCodes(decoded), '12345678901234567890');
    });

    test('decode rejects invalid characters', () {
      expect(() => base32Decode('ABC!'), throwsFormatException);
    });
  });

  group('generateTotp (RFC 6238, SHA-1, 6 digits, 30s step)', () {
    const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

    // RFC 6238 vectors are indexed by the counter T = floor(sec/30).
    DateTime at(int counter) =>
        DateTime.fromMillisecondsSinceEpoch(counter * 30 * 1000);

    test('RFC 6238 vectors (last 6 digits)', () async {
      expect(await generateTotp(secret, time: at(1)), '287082');
      expect(await generateTotp(secret, time: at(37037036)), '081804');
      expect(await generateTotp(secret, time: at(37037037)), '050471');
      expect(await generateTotp(secret, time: at(41152263)), '005924');
      expect(await generateTotp(secret, time: at(66666666)), '279037');
      expect(await generateTotp(secret, time: at(666666666)), '353130');
    });

    test('6-digit code with leading zeros', () async {
      final code = await generateTotp(secret, time: at(41152263));
      expect(code, hasLength(6));
      expect(code.startsWith('00'), isTrue);
    });

    test('changes between two consecutive windows', () async {
      final a = await generateTotp(secret, time: at(60));
      final b = await generateTotp(secret, time: at(61));
      expect(a, isNot(b));
    });
  });

  group('totpSecondsLeft', () {
    test('seconds until rotation', () {
      final t = DateTime.fromMillisecondsSinceEpoch(45 * 1000);
      expect(totpSecondsLeft(t), 15);
      expect(totpSecondsLeft(DateTime.fromMillisecondsSinceEpoch(0)), 30);
      expect(totpSecondsLeft(DateTime.fromMillisecondsSinceEpoch(29 * 1000)), 1);
      expect(totpSecondsLeft(DateTime.fromMillisecondsSinceEpoch(30 * 1000)), 30);
    });
  });

  group('parseTotp', () {
    test('full otpauth URI (issuer in query and label)', () {
      final d = parseTotp(
          'otpauth://totp/GitHub:alice%40example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=GitHub');
      expect(d, isNotNull);
      expect(d!.secret, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(d.issuer, 'GitHub');
      expect(d.account, 'alice@example.com');
      expect(d.label, 'GitHub: alice@example.com');
    });

    test('URI with unpadded lowercase secret', () {
      final d = parseTotp('otpauth://totp/Service?secret=gezdgnbvgy3tqojqgezdgnbvgy3tqojq');
      expect(d, isNotNull);
      expect(d!.secret, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(d.issuer, isNull);
    });

    test('bare Base32 key', () {
      final d = parseTotp('JBSWY3DPEHPK3PXP');
      expect(d, isNotNull);
      expect(d!.secret, 'JBSWY3DPEHPK3PXP');
      expect(d.label, '');
    });

    test('rejects invalid input', () {
      expect(parseTotp(''), isNull);
      expect(parseTotp('  '), isNull);
      expect(parseTotp('non-base32-!'), isNull);
      expect(parseTotp('otpauth://hotp/Test?secret=GEZDGNBV'), isNull);
      expect(parseTotp('otpauth://totp/Test?secret='), isNull);
      expect(parseTotp('otpauth://totp/Test?secret=ABC!'), isNull);
      expect(parseTotp('http://not-otp'), isNull);
    });
  });

  group('verifyTotp', () {
    const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
    DateTime at(int counter) =>
        DateTime.fromMillisecondsSinceEpoch(counter * 30 * 1000);

    test('accepts the code of the current window', () async {
      final code = await generateTotp(secret, time: at(5));
      expect(await verifyTotp(secret, code, time: at(5)), isTrue);
    });

    test('also accepts the previous window code (tolerance)', () async {
      final prev = await generateTotp(secret, time: at(5));
      expect(await verifyTotp(secret, prev, time: at(6)), isTrue);
    });

    test('rejects a wrong code', () async {
      final wrong = await generateTotp(secret, time: at(5));
      final mutated = (int.parse(wrong) + 1) % 1000000;
      expect(await verifyTotp(secret, mutated.toString().padLeft(6, '0'), time: at(5)), isFalse);
    });

    test('rejects malformed input', () async {
      expect(await verifyTotp(secret, '12345', time: at(5)), isFalse);
      expect(await verifyTotp(secret, '1234567', time: at(5)), isFalse);
      expect(await verifyTotp(secret, 'abcdef', time: at(5)), isFalse);
      expect(await verifyTotp(secret, '', time: at(5)), isFalse);
    });

    test('tolerates spaces around the code', () async {
      final code = await generateTotp(secret, time: at(5));
      expect(await verifyTotp(secret, '  $code ', time: at(5)), isTrue);
    });
  });

  group('normalizeTotpSecret', () {
    test('normalizes a bare key', () {
      expect(normalizeTotpSecret('gezd gnbv gy3t'), 'GEZDGNBVGY3T');
    });

    test('null on invalid input', () {
      expect(normalizeTotpSecret('!!!'), isNull);
    });
  });

  group('VaultEntry.totpSecret', () {
    test('isTotp true only with a seed', () {
      final e = VaultEntry.create(name: 'x', totpSecret: 'SECRET');
      expect(e.isTotp, isTrue);
      final p = VaultEntry.create(name: 'y');
      expect(p.isTotp, isFalse);
    });

    test('copyWith clears the seed with () => null', () {
      final e = VaultEntry.create(name: 'x', totpSecret: 'SECRET');
      final cleared = e.copyWith(totpSecret: () => null);
      expect(cleared.totpSecret, isNull);
      expect(cleared.isTotp, isFalse);
    });

    test('copyWith keeps the seed by default', () {
      final e = VaultEntry.create(name: 'x', totpSecret: 'SECRET');
      expect(e.copyWith(name: 'renamed').totpSecret, 'SECRET');
    });

    test('JSON roundtrip', () {
      final e = VaultEntry.create(name: 'x', totpSecret: 'SECRET');
      final parsed = VaultEntry.fromJson(e.toJson());
      expect(parsed.totpSecret, 'SECRET');
      expect(parsed.isTotp, isTrue);
      final p = VaultEntry.create(name: 'y');
      expect(VaultEntry.fromJson(p.toJson()).totpSecret, isNull);
    });
  });
}
