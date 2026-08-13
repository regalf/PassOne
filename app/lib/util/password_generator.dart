import 'dart:math';

/// Random password generator.
class PasswordGenerator {
  static const String _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const String _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _digits = '0123456789';
  static const String _symbols = '!@#\$%^&*()-_=+[]{};:,.<>?/';

  final int length;
  final bool useLower;
  final bool useUpper;
  final bool useDigits;
  final bool useSymbols;

  const PasswordGenerator({
    this.length = 20,
    this.useLower = true,
    this.useUpper = true,
    this.useDigits = true,
    this.useSymbols = true,
  });

  String generate() {
    final rng = Random.secure();
    final pools = <String>[
      if (useLower) _lower,
      if (useUpper) _upper,
      if (useDigits) _digits,
      if (useSymbols) _symbols,
    ];
    if (pools.isEmpty) {
      throw ArgumentError('Almeno un set di caratteri deve essere attivo');
    }
    final all = pools.join();
    final buf = StringBuffer();
    // Guarantees at least one character from each active pool.
    for (final pool in pools) {
      buf.write(pool[rng.nextInt(pool.length)]);
    }
    while (buf.length < length) {
      buf.write(all[rng.nextInt(all.length)]);
    }
    final chars = buf.toString().split('')..shuffle(rng);
    return chars.join();
  }

  /// Entropy estimate in bits.
  double get entropy {
    final poolSize =
        (useLower ? _lower.length : 0) +
        (useUpper ? _upper.length : 0) +
        (useDigits ? _digits.length : 0) +
        (useSymbols ? _symbols.length : 0);
    return length * (log(poolSize) / ln2);
  }
}
