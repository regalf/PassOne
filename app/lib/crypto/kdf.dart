import 'dart:convert';
import 'dart:typed_data';

import 'package:argon2_ffi_base/argon2_ffi_base.dart';
import 'package:cryptography/cryptography.dart' as cg;

/// Algoritmi KDF supportati.
enum KdfAlgorithm { argon2id, pbkdf2Sha256 }

/// Parametri KDF. Per argon2id: [m] è la memoria in KiB, [t] le iterazioni,
/// [p] il parallelismo. Per pbkdf2-sha256: [t] è il numero di iterazioni.
class KdfParams {
  final KdfAlgorithm algorithm;
  final int m;
  final int t;
  final int p;

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
    return KdfParams(
      algorithm: alg,
      m: (params['m'] as num?)?.toInt() ?? 65536,
      t: (params['t'] as num?)?.toInt() ?? 3,
      p: (params['p'] as num?)?.toInt() ?? 4,
    );
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

/// Derivazione della chiave. Usa argon2id quando disponibile, con fallback
/// automatico su pbkdf2-sha256 se la libreria nativa non si carica.
class Kdf {
  Argon2? _argon2;
  bool _argon2Failed = false;

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
    if (!_argon2Failed) {
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
        _argon2Failed = true;
      }
    }
    // Fallback deterministico: PBKDF2 con parametri derivati dai costi argon2.
    return _derivePbkdf2(password, salt,
        KdfParams.pbkdf2(iterations: (params.t * 1000).clamp(100000, 600000)),
        length);
  }

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
