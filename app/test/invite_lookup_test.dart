import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:passone_app/api/client.dart';

/// The invite flow: the user types the invite token, the server resolves it
/// to the account and the app shows which account is being configured.
void main() {
  group('inviteLookup', () {
    test('an invalid token is reported as bad_invite', () async {
      final client = PassOneClient(
        baseUrl: 'http://127.0.0.1:1',
        httpClient: _FakeClient(
          status: 401,
          body: '{"error":"invalid invite token","code":"bad_invite"}',
        ),
      );
      await expectLater(
        client.inviteLookup('not-a-token'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'bad_invite')),
      );
    });

    test('a valid token returns the user name of the account', () async {
      final client = PassOneClient(
        baseUrl: 'http://127.0.0.1:1',
        httpClient: _FakeClient(
          status: 200,
          body: '{"username":"alice"}',
        ),
      );
      expect(await client.inviteLookup('a-token'), 'alice');
    });
  });
}

/// Minimal HTTP client: returns a canned response.
class _FakeClient extends http.BaseClient {
  final int status;
  final String body;

  _FakeClient({required this.status, required this.body});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}
