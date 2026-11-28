import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sutura_vault/core/crypto/crypto_engine.dart';
import 'package:sutura_vault/core/database/database_helper.dart';
import 'package:sutura_vault/core/security/security_service.dart';

typedef RekeyDatabaseFn = Future<void> Function({
  required String oldDerivedKey,
  required String newDerivedKey,
});

/// Paire Question / Réponse de récupération (style Windows local).
class SecurityQuestionAnswer {
  const SecurityQuestionAnswer({
    required this.question,
    required this.answer,
  });

  final String question;
  final String answer;
}

/// Service de récupération hors-ligne du Master PIN par 3 questions/réponses.
///
/// Aucune réponse ni clé en clair n'est jamais persistée : la clé SQLCipher
/// Master est enveloppée (Encrypt-then-MAC) par une KEK dérivée via
/// PBKDF2-HMAC-SHA256 (50 000 itérations + sel aléatoire matériel 16 octets).
class PinRecoveryService {
  PinRecoveryService({
    SecureKeyValueStore? store,
    SecurityService? securityService,
    RekeyDatabaseFn? rekeyDatabase,
    int pbkdf2Iterations = _defaultIterations,
  })  : _store = store ?? HardwareKeyValueStore(),
        _securityService = securityService ?? SecurityService.instance,
        _rekeyDatabase = rekeyDatabase ?? _defaultRekey,
        _pbkdf2Iterations = pbkdf2Iterations;

  static final PinRecoveryService instance = PinRecoveryService();

  static const String _kRecoveryBundle = 'sutura_pin_recovery_bundle_v1';
  static const int _defaultIterations = 50000;

  /// Questions prédéfinies (style récupération compte local Windows).
  static const List<String> predefinedQuestions = <String>[
    'Quel était le nom de votre premier animal de compagnie ?',
    'Dans quelle ville êtes-vous né(e) ?',
    'Quel était votre surnom durant votre enfance ?',
    'Quel est le nom de votre école primaire ?',
    'Quel est le prénom de votre meilleur(e) ami(e) d\'enfance ?',
    'Quel est le modèle de votre premier téléphone ou véhicule ?',
    'Quel est le nom de la rue où vous avez grandi ?',
    'Quel plat traditionnel préférez-vous par-dessus tout ?',
  ];

  final SecureKeyValueStore _store;
  final SecurityService _securityService;
  final RekeyDatabaseFn _rekeyDatabase;
  final int _pbkdf2Iterations;

  static Future<void> _defaultRekey({
    required String oldDerivedKey,
    required String newDerivedKey,
  }) {
    return DatabaseHelper.instance.rekeyVault(
      oldDerivedKey: oldDerivedKey,
      newDerivedKey: newDerivedKey,
      isDecoy: false,
    );
  }

  /// Indique si les 3 questions de récupération sont configurées.
  Future<bool> isRecoveryConfigured() async {
    final raw = await _store.read(_kRecoveryBundle);
    return raw != null && raw.isNotEmpty;
  }

  /// Retourne les 3 questions enregistrées (sans jamais exposer les réponses).
  Future<List<String>?> getConfiguredQuestions() async {
    final raw = await _store.read(_kRecoveryBundle);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final qList = decoded['questions'];
      if (qList is! List || qList.length != 3) return null;
      return qList.map((Object? e) => e.toString()).toList();
    } catch (_) {
      return null;
    }
  }

  /// Configure ou remplace les 3 questions/réponses en scellant la clé Master.
  Future<void> configureRecovery({
    required String masterDerivedKey,
    required List<SecurityQuestionAnswer> items,
  }) async {
    if (!CryptoEngine.isValidDerivedKey(masterDerivedKey)) {
      throw ArgumentError('Clé Master invalide.');
    }
    _validateItems(items);

    final questions = items.map((e) => e.question.trim()).toList();
    final answers = items.map((e) => e.answer).toList();

    final bundleJson = _sealBundle(
      masterDerivedKey: masterDerivedKey,
      questions: questions,
      answers: answers,
    );
    await _store.write(_kRecoveryBundle, bundleJson);
  }

  /// Supprime totalement l'enveloppe de récupération du Keystore.
  Future<void> clearRecovery() => _store.delete(_kRecoveryBundle);

  /// Vérifie les 3 réponses (soumis au lockout anti-force brute SEC-07).
  /// Retourne la clé SQLCipher Master déballée si les 3 réponses sont exactes,
  /// sinon `null`.
  Future<String?> verifyAnswersAndUnwrapKey(List<String> answers) async {
    if (await _securityService.getRemainingLockoutSeconds() > 0) {
      throw StateError('Verrouillage anti-force brute actif. Patientez.');
    }

    if (answers.length != 3) {
      await _securityService.registerFailedRecoveryAttempt();
      return null;
    }

    final raw = await _store.read(_kRecoveryBundle);
    if (raw == null || raw.isEmpty) return null;

    final recoveredKey = _tryUnsealBundle(raw, answers);
    if (recoveredKey == null) {
      await _securityService.registerFailedRecoveryAttempt();
      return null;
    }

    return recoveredKey;
  }

  /// Réinitialise le Master PIN à partir de la clé récupérée :
  /// 1. Vérifie l'anti-collision Decoy PIN,
  /// 2. Exécute `PRAGMA rekey` isolé sur `sutura_master.db`,
  /// 3. Met à jour le Keystore & ré-enveloppe la nouvelle clé sous les 3 réponses.
  Future<String> resetMasterPinWithRecoveredKey({
    required String recoveredOldKey,
    required List<String> verifiedAnswers,
    required String newPin,
  }) async {
    if (!SecurityService.isValidPinFormat(newPin)) {
      throw ArgumentError(
        'Le nouveau Master PIN doit contenir exactement 6 chiffres.',
      );
    }

    final questions = await getConfiguredQuestions();
    if (questions == null || questions.length != 3) {
      throw StateError('Configuration de récupération introuvable.');
    }

    final newKey = CryptoEngine.deriveDatabaseKey(newPin);

    // Vérifie anti-collision Decoy AVANT de toucher à la base SQLCipher
    await _securityService.commitRecoveredMasterPin(
      newPin: newPin,
      newDerivedKey: newKey,
    );

    try {
      await _rekeyDatabase(
        oldDerivedKey: recoveredOldKey,
        newDerivedKey: newKey,
      );
    } catch (e) {
      rethrow;
    }

    // Ré-enveloppe la nouvelle clé Master avec un nouveau sel aléatoire
    final updatedBundle = _sealBundle(
      masterDerivedKey: newKey,
      questions: questions,
      answers: verifiedAnswers,
    );
    await _store.write(_kRecoveryBundle, updatedBundle);

    return newKey;
  }

  // ---------------------------------------------------------------------------
  // Primitives Cryptographiques (PBKDF2-HMAC-SHA256 + Encrypt-then-MAC)
  // ---------------------------------------------------------------------------

  void _validateItems(List<SecurityQuestionAnswer> items) {
    if (items.length != 3) {
      throw ArgumentError('Exactement 3 questions de sécurité sont requises.');
    }
    final uniqueQuestions = items.map((e) => e.question.trim()).toSet();
    if (uniqueQuestions.length != 3) {
      throw ArgumentError('Les 3 questions doivent être distinctes.');
    }
    for (final item in items) {
      if (_normalizeAnswer(item.answer).length < 2) {
        throw ArgumentError(
          'Chaque réponse doit contenir au moins 2 caractères.',
        );
      }
    }
  }

  static String _normalizeAnswer(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _sealBundle({
    required String masterDerivedKey,
    required List<String> questions,
    required List<String> answers,
  }) {
    final rng = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );

    final secretMaterial = _canonicalSecret(questions, answers);
    final kek = _pbkdf2HmacSha256(
      password: utf8.encode(secretMaterial),
      salt: salt,
      iterations: _pbkdf2Iterations,
    );

    final encKey = Hmac(sha256, kek)
        .convert(utf8.encode('SUTURA_RECOVERY_ENC_V1'))
        .bytes;
    final macKey = Hmac(sha256, kek)
        .convert(utf8.encode('SUTURA_RECOVERY_MAC_V1'))
        .bytes;

    final plainKeyBytes = _hexToBytes(masterDerivedKey); // 32 octets
    final keystream = Hmac(sha256, encKey).convert(salt).bytes; // 32 octets

    final cipherBytes = Uint8List(plainKeyBytes.length);
    for (var i = 0; i < plainKeyBytes.length; i++) {
      cipherBytes[i] = plainKeyBytes[i] ^ keystream[i];
    }

    final macInput = <int>[
      ...salt,
      ...utf8.encode(questions.join('|')),
      ...cipherBytes,
    ];
    final macBytes = Hmac(sha256, macKey).convert(macInput).bytes;

    return jsonEncode(<String, Object>{
      'v': 1,
      'iter': _pbkdf2Iterations,
      'questions': questions,
      'salt': base64Encode(salt),
      'cipher': base64Encode(cipherBytes),
      'mac': base64Encode(macBytes),
    });
  }

  String? _tryUnsealBundle(String rawJson, List<String> answers) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return null;

      final qRaw = decoded['questions'];
      if (qRaw is! List || qRaw.length != 3) return null;
      final questions = qRaw.map((Object? e) => e.toString()).toList();

      final iterations = (decoded['iter'] as int?) ?? _defaultIterations;
      final salt = base64Decode(decoded['salt'] as String);
      final cipherBytes = base64Decode(decoded['cipher'] as String);
      final storedMacHex = _bytesToHex(base64Decode(decoded['mac'] as String));

      final secretMaterial = _canonicalSecret(questions, answers);
      final kek = _pbkdf2HmacSha256(
        password: utf8.encode(secretMaterial),
        salt: salt,
        iterations: iterations,
      );

      final encKey = Hmac(sha256, kek)
          .convert(utf8.encode('SUTURA_RECOVERY_ENC_V1'))
          .bytes;
      final macKey = Hmac(sha256, kek)
          .convert(utf8.encode('SUTURA_RECOVERY_MAC_V1'))
          .bytes;

      final macInput = <int>[
        ...salt,
        ...utf8.encode(questions.join('|')),
        ...cipherBytes,
      ];
      final computedMacHex =
          _bytesToHex(Hmac(sha256, macKey).convert(macInput).bytes);

      // Vérification Encrypt-then-MAC à temps constant avant tout déchiffrement
      if (!CryptoEngine.constantTimeEquals(storedMacHex, computedMacHex)) {
        return null;
      }

      final keystream = Hmac(sha256, encKey).convert(salt).bytes;
      final plainBytes = Uint8List(cipherBytes.length);
      for (var i = 0; i < cipherBytes.length; i++) {
        plainBytes[i] = cipherBytes[i] ^ keystream[i];
      }

      final recoveredKey = _bytesToHex(plainBytes);
      return CryptoEngine.isValidDerivedKey(recoveredKey) ? recoveredKey : null;
    } catch (_) {
      return null;
    }
  }

  static String _canonicalSecret(List<String> questions, List<String> answers) {
    final parts = <String>[];
    for (var i = 0; i < 3; i++) {
      parts.add('${questions[i].trim()}::${_normalizeAnswer(answers[i])}');
    }
    return parts.join('||');
  }

  /// PBKDF2-HMAC-SHA256 (1 bloc = 32 octets = 256 bits).
  static Uint8List _pbkdf2HmacSha256({
    required List<int> password,
    required List<int> salt,
    required int iterations,
  }) {
    final hmac = Hmac(sha256, password);
    final initial = <int>[...salt, 0, 0, 0, 1];
    var u = hmac.convert(initial).bytes;
    final out = Uint8List.fromList(u);

    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}