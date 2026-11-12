import 'package:flutter_test/flutter_test.dart';
import 'package:passone_app/api/client.dart';

/// An address entered without a scheme ("192.168.1.8:8321") used to be
/// passed straight to the client: Uri.parse then read "192.168.1.8" as an
/// invalid scheme and every request failed with
/// "FormatException: Scheme not starting with alphabetic character".
void main() {
  group('normalizeBaseUrl', () {
    test('adds the https scheme when it is missing', () {
      expect(PassOneClient.normalizeBaseUrl('192.168.1.8:8321'),
          'https://192.168.1.8:8321');
      expect(PassOneClient.normalizeBaseUrl('passone.example.com'),
          'https://passone.example.com');
      expect(PassOneClient.normalizeBaseUrl('  example.com  '),
          'https://example.com');
    });

    test('keeps an explicit scheme', () {
      expect(PassOneClient.normalizeBaseUrl('http://192.168.1.8:8321'),
          'http://192.168.1.8:8321');
      expect(PassOneClient.normalizeBaseUrl('https://example.com'),
          'https://example.com');
    });

    test('removes the trailing slashes', () {
      expect(PassOneClient.normalizeBaseUrl('https://example.com/'),
          'https://example.com');
      expect(PassOneClient.normalizeBaseUrl('https://example.com///'),
          'https://example.com');
    });
  });

  group('isCleartext', () {
    test('detects a plain HTTP address', () {
      expect(PassOneClient.isCleartext('http://192.168.1.8:8321'), isTrue);
      expect(PassOneClient.isCleartext('HTTP://192.168.1.8:8321'), isTrue);
      expect(PassOneClient.isCleartext('https://example.com'), isFalse);
    });
  });

  group('invalid server address', () {
    test('an address without a scheme is rejected with a clear error', () {
      final client = PassOneClient(baseUrl: '192.168.1.8:8321');
      expect(
        () => client.prelogin('alice'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code',
            ApiException.codeInvalidServerUrl)),
      );
    });

    test('an empty address is rejected', () {
      final client = PassOneClient(baseUrl: '');
      expect(
        () => client.healthCheck(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code',
            ApiException.codeInvalidServerUrl)),
      );
    });
  });
}
