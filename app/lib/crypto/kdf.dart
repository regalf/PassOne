import 'dart:convert';
import 'dart:typed_data';

import 'package:argon2_ffi_base/argon2_ffi_base.dart';
import 'package:cryptography/cryptography.dart' as cg;

/// Supported KDF algorithms.
enum KdfAlgorithm { argon2id, pbkdf2Sha256 }

/// Thrown when the requested KDF cannot be used on this device.
///
/// It is never replaced by a weaker algorithm: a different KDF produces a
/// different key, so the failure would surface as a wrong password on a
/// correct one (or, worse, as a corrupted vault).
class KdfUnavailableException implements Exception {
  const KdfUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when the server or an imported file sends KDF parameters that are
/// outside the allowed range.
class InvalidKdfParamsException implements Exception {
  const InvalidKdfParamsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// KDF parameters. For argon2id: [m] is the memory in KiB, [t] the iterations,
/// [p] the parallelism. For pbkdf2-sha256: [t] is the number of iterations.
class KdfParams {
  final KdfAlgorithm algorithm;
  final int m;
  final int t;
  final int p;

  /// Sanity limits, mirroring the server-side ones (`max_kdf_memory_mb` and
  /// `max_kdf_iterations` in config.yaml). They protect the client from a
  /// hostile server or a crafted `.passone` file asking for an absurd amount
  /// of memory (which would simply OOM the device).
  static const int maxMemoryKiB = 2048 * 1024; // 2 GiB
  static const int maxIterations = 10000000;
  static const int maxParallelism = 16;

  /// Minimum sane values (Argon2 requires at least 8 KiB per lane).
  static const int minMemoryKiB = 8;
  static const int minIterations = 1;
  static const int minParallelism = 1;

  const KdfParams.argon2id({this.m = 65536, this.t = 3, this.p = 4})
      : algorithm = KdfAlgorithm.argon2id;

  const KdfParams.pbkdf2({required int iterations})
      : algorithm = KdfAlgorithm.pbkdf2Sha256,
        m = 0,
        t = iterations,
        p = 1;

  static const Map<String, KdfAlgorithm> _algos = {
    'argon2id': KdfAlgorithm.argon2id,
    'pbkdf2-sha256': KdfAlgorithm.pbkdf2Sha256,
  };

  factory KdfParams.fromJson(Map<String, dynamic> json) {
    final alg = _algos[json['algorithm']];
    if (alg == null) {
      throw FormatException('algoritmo KDF sconosciuto: ${json['algorithm']}');
    }
    final params = (json['params'] as Map?) ?? const {};
    final kdf = KdfParams(
      algorithm: alg,
      m: (params['m'] as num?)?.toInt() ?? 65536,
      t: (params['t'] as num?)?.toInt() ?? 3,
      p: (params['p'] as num?)?.toInt() ?? 4,
    );
    kdf.validate();
    return kdf;
  }

  /// Throws an [InvalidKdfParamsException] if the parameters are outside the
  /// allowed range. Called on every parameter set that comes from outside the
  /// app (server response, `.passone` envelope).
  void validate() {
    if (t < minIterations || t > maxIterations) {
      throw InvalidKdfParamsException(
          'parametro KDF non valido: iterazioni fuori range ($t)');
    }
    switch (algorithm) {
      case KdfAlgorithm.argon2id:
        if (m < minMemoryKiB || m > maxMemoryKiB) {
          throw InvalidKdfParamsException(
              'parametro KDF non valido: memoria fuori range ($m KiB)');
        }
        if (p < minParallelism || p > maxParallelism) {
          throw InvalidKdfParamsException(
              'parametro KDF non valido: parallelismo fuori range ($p)');
        }
      case KdfAlgorithm.pbkdf2Sha256:
        break;
    }
  }

  const KdfParams({
    required this.algorithm,
    required this.m,
    required this.t,
    required this.p,
  });

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm == KdfAlgorithm.argon2id ? 'argon2id' : 'pbkdf2-sha256',
        'params': switch (algorithm) {
          KdfAlgorithm.argon2id => {'m': m, 't': t, 'p': p},
          KdfAlgorithm.pbkdf2Sha256 => {'t': t},
        },
      };

  @override
  String toString() => toJson().toString();
}

/// Key derivation. Uses argon2id; if the native library is not available the
/// derivation fails with a [KdfUnavailableException] instead of silently
/// switching to a weaker algorithm.
class Kdf {
  Argon2? _argon2;
  Object? _argon2Error;

  /// True when argon2id can be used on this device.
  bool get argon2Available => _argon2Error == null;

  Future<Uint8List> derive(String password, Uint8List salt, KdfParams params,
      {int length = 32}) async {
    switch (params.algorithm) {
      case KdfAlgorithm.argon2id:
        return _deriveArgon2id(password, salt, params, length);
      case KdfAlgorithm.pbkdf2Sha256:
        return _derivePbkdf2(password, salt, params, length);
    }
  }

  Future<Uint8List> _deriveArgon2id(
      String password, Uint8List salt, KdfParams params, int length) async {
    // A previous failure is remembered: the native library will not load on
    // the second attempt either.
    final previous = _argon2Error;
    if (previous != null) {
      throw KdfUnavailableException(_argon2Message(previous));
    }
    try {
      final argon2 = _argon2 ??= Argon2FfiFlutter();
      final hash = await argon2.argon2Async(Argon2Arguments(
        Uint8List.fromList(utf8.encode(password)),
        salt,
        params.m,
        params.t,
        length,
        params.p,
        2, // ARGON2_ID
        0x13, // ARGON2_VERSION_13
      ));
      return hash;
    } catch (e) {
      _argon2Error = e;
      throw KdfUnavailableException(_argon2Message(e));
    }
  }

  String _argon2Message(Object error) =>
      'Argon2id non è disponibile su questo dispositivo ($error). '
      'La derivazione della chiave non può essere eseguita con il KDF richiesto '
      'dal server.';

  Future<Uint8List> _derivePbkdf2(
      String password, Uint8List salt, KdfParams params, int length) async {
    final pbkdf2 = cg.Pbkdf2(
      macAlgorithm: cg.Hmac.sha256(),
      iterations: params.t,
      bits: length * 8,
    );
    final secretKey = await pbkdf2.deriveKey(
      secretKey: cg.SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }
}
