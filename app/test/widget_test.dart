import 'package:flutter_test/flutter_test.dart';

import 'package:passone_app/util/password_generator.dart';

void main() {
  test('PasswordGenerator respects length and character sets', () {
    const gen = PasswordGenerator(length: 24);
    for (var i = 0; i < 50; i++) {
      final p = gen.generate();
      expect(p.length, 24);
      expect(RegExp(r'[a-z]').hasMatch(p), isTrue);
      expect(RegExp(r'[A-Z]').hasMatch(p), isTrue);
      expect(RegExp(r'[0-9]').hasMatch(p), isTrue);
      expect(RegExp(r'[!@#\$%^&*()\-_=+\[\]{};:,.<>?/]').hasMatch(p), isTrue);
    }
  });

  test('PasswordGenerator without symbols does not use them', () {
    const gen = PasswordGenerator(length: 12, useSymbols: false);
    final p = gen.generate();
    expect(RegExp(r'[!@#\$%^&*()\-_=+\[\]{};:,.<>?/]').hasMatch(p), isFalse);
  });

  test('PasswordGenerator throws if no character set is active', () {
    const gen = PasswordGenerator(
        length: 8, useLower: false, useUpper: false, useDigits: false, useSymbols: false);
    expect(() => gen.generate(), throwsArgumentError);
  });

  test('Entropy grows with the length', () {
    const short = PasswordGenerator(length: 8);
    const long = PasswordGenerator(length: 20);
    expect(long.entropy, greaterThan(short.entropy));
  });
}
