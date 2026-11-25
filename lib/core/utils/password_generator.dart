import 'dart:math';

enum PasswordStrength {
  weak, // Faible (< 50 bits)
  medium, // Moyen (50..79 bits)
  armored, // Blindé (>= 80 bits)
}

/// Générateur cryptographique de secrets basé sur [Random.secure] (Section 3.1).
class PasswordGenerator {
  PasswordGenerator._();

  static const String _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String _digits = '0123456789';
  static const String _symbols = r'!@#$%^&*()-_=+[]{}|;:,.<>?';

  static String generate({
    int length = 20,
    bool includeUppercase = true,
    bool includeLowercase = true,
    bool includeDigits = true,
    bool includeSymbols = true,
  }) {
    if (length < 4 || length > 128) {
      throw ArgumentError('La longueur doit être comprise entre 4 et 128.');
    }

    final pools = <String>[
      if (includeUppercase) _uppercase,
      if (includeLowercase) _lowercase,
      if (includeDigits) _digits,
      if (includeSymbols) _symbols,
    ];

    if (pools.isEmpty) {
      throw ArgumentError('Au moins un jeu de caractères doit être activé.');
    }

    final random = Random.secure();
    final chars = <String>[];

    // Garantit au moins 1 caractère de chaque famille sélectionnée
    for (final pool in pools) {
      chars.add(pool[random.nextInt(pool.length)]);
    }

    final combined = pools.join();
    while (chars.length < length) {
      chars.add(combined[random.nextInt(combined.length)]);
    }

    // Mélange Fisher-Yates cryptographique (supprime tout biais positionnel)
    for (var i = chars.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }

    return chars.join();
  }

  /// Calcule l'entropie estimée en bits : length * log2(taille_alphabet).
  static double calculateEntropyBits(String password) {
    if (password.isEmpty) return 0;

    var poolSize = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) poolSize += 26;
    if (RegExp(r'[A-Z]').hasMatch(password)) poolSize += 26;
    if (RegExp(r'[0-9]').hasMatch(password)) poolSize += 10;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) poolSize += 32;

    if (poolSize == 0) return 0;
    return password.length * (log(poolSize) / ln2);
  }

  static PasswordStrength evaluateStrength(String password) {
    final bits = calculateEntropyBits(password);
    if (bits >= 80) return PasswordStrength.armored;
    if (bits >= 50) return PasswordStrength.medium;
    return PasswordStrength.weak;
  }

  static String strengthLabel(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.weak:
        return 'Faible';
      case PasswordStrength.medium:
        return 'Moyen';
      case PasswordStrength.armored:
        return 'Blindé';
    }
  }
}