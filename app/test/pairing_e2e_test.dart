import 'package:flutter_test/flutter_test.dart';
import 'package:passone_app/api/client.dart';

// Live pairing check against a self-signed PassOne server started for the e2e
// run:
//   passone serve --config <dir>/config.yaml   (tls_mode: selfsigned)
// The expected fingerprint is the one the server printed at startup /
// printed by `passone tls fingerprint`.
void main() {
  const baseUrl = 'https://127.0.0.1:18331';
  const serverFingerprint =
      'aba5d851ff77fcaaf56b055e3ece82498de96b07660f642b38e4f8a474bc804d';

  setUpAll(() async {
    // Same idea as the other e2e tests: skip when the pairing server is not
    // running on the expected port. An unpinned probe legitimately fails with
    // pairing_required (self-signed): that still proves the server answers.
    try {
      final c = PassOneClient(baseUrl: baseUrl);
      await c.healthCheck();
    } on ApiException catch (e) {
      if (e.code == ApiException.codePairingRequired) return;
      markTestSkipped('pairing integration server not reachable on $baseUrl');
    } catch (_) {
      markTestSkipped('pairing integration server not reachable on $baseUrl');
    }
  });

  test('unpinned connection reports pairing_required with the server fingerprint',
      () async {
    final client = PassOneClient(baseUrl: baseUrl);
    try {
      await client.healthCheck();
      fail('unpinned self-signed connection must be refused');
    } on ApiException catch (e) {
      expect(e.code, ApiException.codePairingRequired);
      expect(e.isNetworkError, isFalse,
          reason: 'pairing must not be treated as a plain network error');
    }
    // The fingerprint extracted from the presented certificate must match the
    // one the Go server prints (validates the DER/SPKI extraction cross-lang).
    expect(client.lastCertFingerprint, serverFingerprint);
  });

  test('prelogin without pin also surfaces pairing_required', () async {
    final client = PassOneClient(baseUrl: baseUrl);
    try {
      await client.prelogin('no_such_user');
      fail('unpinned self-signed connection must be refused');
    } on ApiException catch (e) {
      expect(e.code, ApiException.codePairingRequired);
    }
  });

  test('matching pin trusts the server', () async {
    final client = PassOneClient(
      baseUrl: baseUrl,
      serverPin: serverFingerprint,
    );
    final data = await client.prelogin('no_such_user');
    // The handshake succeeded, so the server answered with the normal payload.
    expect(data.status, isA<String>());
  });

  test('mismatched pin reports cert_changed', () async {
    final wrong =
        'ddddddddffffffffddddddddffffffffddddddddffffffffddddddddffffffff';
    final client = PassOneClient(baseUrl: baseUrl, serverPin: wrong);
    try {
      await client.healthCheck();
      fail('a wrong pin must be refused');
    } on ApiException catch (e) {
      expect(e.code, ApiException.codeCertChanged);
    }
    expect(client.lastCertFingerprint, serverFingerprint);
  });

  test('plain text HTTP URL never uses TLS pinning', () async {
    final client = PassOneClient(baseUrl: 'http://127.0.0.1:18331');
    // No TLS callback involved; reaching the service is not tested here, only
    // that no cert state leak happens on construction.
    expect(client.lastCertFailure, isNull);
  });
}