import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Moteur cryptographique souverain de SUTURA VAULT.
///
/// Règle d'ingénierie #2 :
/// Utilise un sel applicatif constant [_kSovereignAppSalt] garantissant la
/// portabilité des sauvegardes `.db` inter-appareils. SQLCipher ajoute
/// nativement un sel matériel aléatoire de 16 octets dans l'en-tête du fichier
/// `.db` et exécute 256 000 itérations PBKDF2-HMAC-SHA512 (SEC-02).
class CryptoEngine {
  CryptoEngine._();

  static const String _kSovereignAppSalt =
      'SUTURA_VAULT_SOVEREIGN_SALT_V1_YB_SOLUTIONS_2025';

  static final RegExp _hex64Pattern = RegExp(r'^[0-9a-f]{64}$');

  /// Dérive la clé hexadécimale (64 caractères) transmise à SQLCipher.
  static String deriveDatabaseKey(String pin) {
    final bytes = utf8.encode('DB_KEY::$_kSovereignAppSalt::$pin');
    return sha256.convert(bytes).toString();
  }

  /// Dérive une empreinte distincte (domain-separated) stockée dans le
  /// Keystore/Keychain matériel pour vérifier le Master PIN ou le Decoy PIN.
  static String hashPinForStorage(String pin) {
    final bytes = utf8.encode('PIN_AUTH::$_kSovereignAppSalt::$pin');
    return sha256.convert(bytes).toString();
  }

  /// Vérifie strictement qu'une clé dérivée est au format hexadécimal 256 bits
  /// (empêche toute injection SQL lors d'un PRAGMA rekey).
  static bool isValidDerivedKey(String key) => _hex64Pattern.hasMatch(key);

  /// Comparaison à temps constant contre les attaques temporelles.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}