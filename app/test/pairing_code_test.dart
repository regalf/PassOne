import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:passone_app/api/tls.dart';

const _fp = '03a906ee615ecc67ae60d033bac9e55700c90b1e5f6b9c65ae51cd04f10085d0';

void main() {
  group('normalizePairingCode', () {
    test('accepts a raw fingerprint', () {
      expect(normalizePairingCode(_fp), _fp);
    });

    test('accepts uppercase and normalizes to lowercase', () {
      expect(normalizePairingCode(_fp.toUpperCase()), _fp);
    });

    test('strips separators (spaces, colons)', () {
      final spaced = '03:a9:06:ee:61:5e:cc:67:ae:60:d0:33:ba:c9:e5:57:00:c9:0b:'
          '1e:5f:6b:9c:65:ae:51:cd:04:f1:00:85:d0';
      expect(normalizePairingCode(spaced), _fp);
    });

    test('accepts the 0x prefix', () {
      expect(normalizePairingCode('0x$_fp'), _fp);
    });

    test('accepts the sha256: prefix', () {
      expect(normalizePairingCode('sha256:$_fp'), _fp);
    });

    test('rejects too short/too long input', () {
      expect(normalizePairingCode(_fp.substring(0, 32)), isNull);
      expect(normalizePairingCode('${_fp}ff'), isNull);
    });

    test('rejects non-hex characters', () {
      var broken = _fp.substring(0, 63);
      expect(normalizePairingCode('${broken}g'), isNull);
      expect(normalizePairingCode('abc'), isNull);
      expect(normalizePairingCode(''), isNull);
    });
  });

  group('pairingCodeFromQrText', () {
    test('extracts a bare fingerprint', () {
      expect(pairingCodeFromQrText(_fp), _fp);
    });

    test('parses passone://pair/<fp>', () {
      final raw = 'passone://pair/$_fp';
      expect(pairingCodeFromQrText(raw), _fp);
    });

    test('parses passone://pair?fp=...', () {
      final raw = 'passone://pair?fp=$_fp';
      expect(pairingCodeFromQrText(raw), _fp);
    });

    test('parses passone:pair:<fp>', () {
      final raw = 'passone:pair:$_fp';
      expect(pairingCodeFromQrText(raw), _fp);
    });

    test('rejects unrelated QR content', () {
      expect(pairingCodeFromQrText('otpauth://totp/Test?secret=ABC'), isNull);
      expect(pairingCodeFromQrText('hello world'), isNull);
    });
  });

  group('bytesToHex', () {
    test('formats bytes as lowercase hex', () {
      expect(bytesToHex([0xab, 0x01, 0xff]), 'ab01ff');
      expect(bytesToHex([]), '');
    });
  });

  group('extractSpkiFromCert', () {
    test('SPKI SHA-256 matches the key-level fingerprint (fixture cert.der)',
        () async {
      final f = File('test/fixtures/pairing_cert.der');
      final der = Uint8List.fromList(f.readAsBytesSync());
      final spki = extractSpkiFromCert(der);
      final fp = bytesToHex(sha256.convert(spki).bytes);
      // The expected fingerprint was computed from the same EC P-256 key used
      // to generate the certificate, via:
      //   openssl pkey -in key.pem -pubout | openssl dgst -sha256
      expect(fp,
          'ac9f98813161582fef06d4cf5e3e142c2e4ac263b7d6ba89999291a24845a09b');
    });
  });
}