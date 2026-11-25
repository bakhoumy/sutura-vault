import 'package:flutter_test/flutter_test.dart';
import 'package:sutura_vault/core/utils/password_generator.dart';

void main() {
  group('PasswordGenerator — Entropie & Random.secure', () {
    test('génère un secret blindé respectant tous les critères', () {
      final pwd = PasswordGenerator.generate(
        length: 24,
        includeUppercase: true,
        includeLowercase: true,
        includeDigits: true,
        includeSymbols: true,
      );

      expect(pwd.length, equals(24));
      expect(RegExp(r'[A-Z]').hasMatch(pwd), isTrue);
      expect(RegExp(r'[a-z]').hasMatch(pwd), isTrue);
      expect(RegExp(r'[0-9]').hasMatch(pwd), isTrue);
      expect(RegExp(r'[^a-zA-Z0-9]').hasMatch(pwd), isTrue);
      expect(
        PasswordGenerator.evaluateStrength(pwd),
        equals(PasswordStrength.armored),
      );
    });

    test('détecte un mot de passe faible', () {
      expect(
        PasswordGenerator.evaluateStrength('123456'),
        equals(PasswordStrength.weak),
      );
    });

    test('génère des valeurs distinctes à chaque appel', () {
      final a = PasswordGenerator.generate(length: 20);
      final b = PasswordGenerator.generate(length: 20);
      expect(a, isNot(equals(b)));
    });
  });
}