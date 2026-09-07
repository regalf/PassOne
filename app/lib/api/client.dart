import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'tls.dart';

/// API exception with a semantic code.
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;

  ApiException(this.status, this.code, this.message);

  /// The server uses a self-signed (or otherwise untrusted) TLS certificate
  /// and this device has no pairing pin for it yet: the user must scan/enter
  /// the pairing code shown by the server.
  static const codePairingRequired = 'pairing_required';

  /// A pairing pin exists but the certificate presented by the server no
  /// longer matches it (e.g. after `passone tls rotate`): re-pairing is
  /// required, treating the change as a possible key compromise.
  static const codeCertChanged = 'cert_changed';

  bool get isConflict => status == 409;

  /// True for connectivity failures normalized by [_send] (status 0, code
  /// 'network'). Excludes 'no_server' (no server configured) and the TLS
  /// pairing/pin codes, which need their own handling.
  bool get isNetworkError => status == 0 && code == 'network';

  @override
  String toString() => message;
}

/// Public data of a user returned by the server.
class UserInfo {
  final int id;
  final String username;
  final String status;
  final int vaultRevision;
  final bool recoveryEnabled;
  final String kdfAlgorithm;

  UserInfo({
    required this.id,
    required this.username,
    required this.status,
    required this.vaultRevision,
    required this.recoveryEnabled,
    required this.kdfAlgorithm,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
        id: (json['id'] as num).toInt(),
        username: json['username'] as String,
        status: json['status'] as String? ?? '',
        vaultRevision: (json['vault_revision'] as num).toInt(),
        recoveryEnabled: json['recovery_enabled'] as bool? ?? false,
        kdfAlgorithm: json['kdf_algorithm'] as String? ?? '',
      );
}

class Session {
  final String token;
  final DateTime expiresAt;
  final UserInfo user;

  Session({required this.token, required this.expiresAt, required this.user});

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        token: json['token'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        user: UserInfo.fromJson(json['user'] as Map<String, dynamic>),
      );
}

/// Response of POST /auth/prelogin: salt + KDF parameters to derive the key.
class PreloginResult {
  final String status;
  final Uint8List salt;
  final Map<String, dynamic> kdf;

  PreloginResult({
    required this.status,
    required this.salt,
    required this.kdf,
  });

  factory PreloginResult.fromJson(Map<String, dynamic> json) => PreloginResult(
        status: json['status'] as String? ?? 'unknown',
        salt: Uint8List.fromList(base64.decode(json['salt_b64'] as String)),
        kdf: json['kdf'] as Map<String, dynamic>,
      );
}

/// Response of GET /vault.
class VaultRemote {
  final Uint8List blob;
  final Uint8List nonce;
  final Uint8List wrappedKey;
  final Uint8List? wrappedRecoveryKey;
  final bool recoveryEnabled;
  final Uint8List salt;
  final Map<String, dynamic> kdf;
  final int revision;

  VaultRemote({
    required this.blob,
    required this.nonce,
    required this.wrappedKey,
    required this.wrappedRecoveryKey,
    required this.recoveryEnabled,
    required this.salt,
    required this.kdf,
    required this.revision,
  });

  factory VaultRemote.fromJson(Map<String, dynamic> json) {
    Uint8List? maybeB64(String key) {
      final v = json[key] as String?;
      if (v == null || v.isEmpty) return null;
      return Uint8List.fromList(base64.decode(v));
    }

    return VaultRemote(
      blob: base64.decode(json['vault_blob_b64'] as String),
      nonce: base64.decode(json['vault_nonce_b64'] as String),
      wrappedKey: base64.decode(json['vault_key_wrapped_b64'] as String),
      wrappedRecoveryKey: maybeB64('vault_key_wrapped_recov_b64'),
      recoveryEnabled: json['recovery_enabled'] as bool? ?? false,
      salt: base64.decode(json['salt_b64'] as String),
      kdf: json['kdf'] as Map<String, dynamic>,
      revision: (json['vault_revision'] as num).toInt(),
    );
  }
}

/// REST client for the PassOne server.
class PassOneClient {
  final String baseUrl;

  /// SPKI fingerprint (64 lowercase hex chars) the server certificate must
  /// match, or null when the connection is not pinned (plain HTTP, or HTTPS
  /// with a public CA). Once set, any other certificate is rejected.
  final String? serverPin;
  http.Client _http;
  final Duration timeout;

  /// TLS dialog state filled by the certificate callback on handshake
  /// failures, consumed by [_send] to surface [ApiException.codePairingRequired]
  /// / [ApiException.codeCertChanged]. Cleared after each error mapping.
  String? lastCertFailure;
  String? lastCertFingerprint;

  PassOneClient({
    required this.baseUrl,
    this.serverPin,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client() {
    if (httpClient == null && baseUrl.startsWith('https://')) {
      final io = HttpClient();
      io.badCertificateCallback = (cert, host, port) => _verify(cert);
      _http = IOClient(io);
    }
  }

  /// Enforces the SPKI pin when the certificate fails normal chain
  /// verification. A matching pin passes; otherwise the failure is recorded so
  /// [_send] can route it to the pairing/change flows.
  bool _verify(X509Certificate cert) {
    final fp = spkiFingerprintHex(cert);
    lastCertFingerprint = fp;
    final pin = serverPin?.trim().toLowerCase();
    if (fp != null && pin != null && pin.length == 64 && fp == pin) {
      return true;
    }
    lastCertFailure = fp == null
        ? null
        : (pin == null || pin.isEmpty
            ? ApiException.codePairingRequired
            : ApiException.codeCertChanged);
    return false;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  dynamic _decode(http.Response res, Uri uri) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    String code = '';
    String message = 'HTTP error ${res.statusCode}';
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      code = body['code'] as String? ?? '';
      message = body['error'] as String? ?? message;
    } catch (_) {}
    throw ApiException(res.statusCode, code, message);
  }

  /// Maps the outcome of a request. A TLS handshake refusal recorded by the
  /// certificate callback is surfaced as a dedicated semantic error
  /// ([ApiException.codePairingRequired]/[ApiException.codeCertChanged]) so
  /// the UI can drive the pairing flow instead of showing "unreachable".
  Future<dynamic> _send(
      Future<http.Response> Function() request, String? token) async {
    try {
      final res = await request().timeout(timeout);
      return _decode(res, res.request!.url);
    } on ApiException {
      rethrow;
    } catch (e) {
      final failure = lastCertFailure;
      lastCertFailure = null;
      if (failure == ApiException.codePairingRequired) {
        throw ApiException(0, ApiException.codePairingRequired,
            'The server requires pairing before the login can continue.');
      }
      if (failure == ApiException.codeCertChanged) {
        throw ApiException(0, ApiException.codeCertChanged,
            'The server certificate no longer matches the one this device trusts.');
      }
      throw ApiException(0, 'network', 'Unable to reach the server: $e');
    }
  }

  Future<PreloginResult> prelogin(String username) async {
    final data = await _send(
      () => _http.post(
        _uri('/auth/prelogin'),
        headers: _headers(null),
        body: jsonEncode({'username': username}),
      ),
      null,
    );
    return PreloginResult.fromJson(data as Map<String, dynamic>);
  }

  Future<Session> setup({
    required String username,
    String? inviteToken,
    required String authHashB64,
    required String saltB64,
    required Map<String, dynamic> kdf,
    required String wrappedKeyB64,
    String? wrappedRecoveryB64,
    String? recoveryHashB64,
    required String blobB64,
    required String nonceB64,
    String? deviceName,
  }) async {
    final data = await _send(
      () => _http.post(
        _uri('/auth/setup'),
        headers: _headers(null),
        body: jsonEncode({
          'username': username,
          'invite_token': ?inviteToken,
          'auth_hash_b64': authHashB64,
          'salt_b64': saltB64,
          'kdf': kdf,
          'vault_key_wrapped_b64': wrappedKeyB64,
          'vault_key_wrapped_recov_b64': ?wrappedRecoveryB64,
          'recovery_hash_b64': ?recoveryHashB64,
          'vault_blob_b64': blobB64,
          'vault_nonce_b64': nonceB64,
          'device_name': deviceName ?? '',
        }),
      ),
      null,
    );
    return Session.fromJson(data as Map<String, dynamic>);
  }

  Future<Session> login({
    required String username,
    required String authHashB64,
    String? deviceName,
  }) async {
    final data = await _send(
      () => _http.post(
        _uri('/auth/login'),
        headers: _headers(null),
        body: jsonEncode({
          'username': username,
          'auth_hash_b64': authHashB64,
          'device_name': deviceName ?? '',
        }),
      ),
      null,
    );
    return Session.fromJson(data as Map<String, dynamic>);
  }

  Future<void> logout(String token) async {
    await _send(
        () => _http.post(_uri('/auth/logout'), headers: _headers(token)), token);
  }

  Future<void> logoutAll(String token) async {
    await _send(
        () => _http.post(_uri('/auth/logout-all'), headers: _headers(token)),
        token);
  }

  Future<void> changePassword(
    String token, {
    required String oldAuthHashB64,
    required Map<String, dynamic> newAuthMaterial,
  }) async {
    await _send(
      () => _http.post(
        _uri('/auth/change-password'),
        headers: _headers(token),
        body: jsonEncode({
          'old_auth_hash_b64': oldAuthHashB64,
          'new': newAuthMaterial,
        }),
      ),
      token,
    );
  }

  Future<Session> recover({
    required String username,
    required String recoveryHashB64,
    required Map<String, dynamic> newAuthMaterial,
    String? deviceName,
  }) async {
    final data = await _send(
      () => _http.post(
        _uri('/auth/recover'),
        headers: _headers(null),
        body: jsonEncode({
          'username': username,
          'recovery_hash_b64': recoveryHashB64,
          'new': newAuthMaterial,
          'device_name': deviceName ?? '',
        }),
      ),
      null,
    );
    return Session.fromJson(data as Map<String, dynamic>);
  }

  /// Downloads the encrypted vault after proving possession of the recovery key.
  Future<VaultRemote> recoverPayload({
    required String username,
    required String recoveryHashB64,
  }) async {
    final res = await _http
        .post(
          _uri('/auth/recover-payload'),
          headers: _headers(null),
          body: jsonEncode({
            'username': username,
            'recovery_hash_b64': recoveryHashB64,
          }),
        )
        .timeout(timeout);
    final data = _decode(res, _uri('/auth/recover-payload')) as Map<String, dynamic>;
    return VaultRemote.fromJson(data);
  }

  Future<VaultRemote> vaultGet(String token) async {
    final res = await _http.get(
      _uri('/vault'),
      headers: _headers(token),
    ).timeout(timeout);
    final data = _decode(res, _uri('/vault')) as Map<String, dynamic>;
    return VaultRemote.fromJson(data);
  }

  Future<int> vaultPut(
    String token, {
    required int baseRevision,
    required String blobB64,
    required String nonceB64,
    String? wrappedKeyB64,
    String? wrappedRecoveryB64,
  }) async {
    final data = await _send(
      () => _http.put(
        _uri('/vault'),
        headers: _headers(token),
        body: jsonEncode({
          'base_revision': baseRevision,
          'vault_blob_b64': blobB64,
          'vault_nonce_b64': nonceB64,
          'vault_key_wrapped_b64': ?wrappedKeyB64,
          'vault_key_wrapped_recov_b64': ?wrappedRecoveryB64,
        }),
      ),
      token,
    );
    return (data as Map<String, dynamic>)['vault_revision'] as int;
  }

  Future<void> healthCheck() async {
    // Goes through [_send] so a TLS handshake refusal is surfaced with the
    // pairing/pin-change codes, not as an opaque network error.
    final data = await _send(
        () => _http.get(Uri.parse('$baseUrl/health')), null);
    final status = (data as Map<String, dynamic>?)?['status'];
    if (status != 'ok') {
      throw ApiException(0, 'unreachable',
          'The server is not responding as expected');
    }
  }
}
