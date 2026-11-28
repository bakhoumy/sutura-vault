import 'package:flutter_test/flutter_test.dart';
import 'package:sutura_vault/core/crypto/crypto_engine.dart';
import 'package:sutura_vault/core/security/pin_recovery_service.dart';
import 'package:sutura_vault/core/security/security_service.dart';

class _MemStore implements SecureKeyValueStore {
  final Map<String, String> _map = <String, String>{};
  @override
  Future<void> delete(String key) async => _map.remove(key);
  @override
  Future<void> deleteAll() async => _map.clear();
  @override
  Future<String?> read(String key) async => _map[key];
  @override
  Future<void> write(String key, String value) async => _map[key] = value;
}

void main() {
  group('PinRecoveryService — Enveloppe PBKDF2-HMAC-SHA256 + Encrypt-then-MAC',
      () {
    late _MemStore store;
    late SecurityService security;
    late PinRecoveryService recovery;
    String? rekeyedOld;
    String? rekeyedNew;

    setUp(() {
      store = _MemStore();
      security = SecurityService(store: store);
      rekeyedOld = null;
      rekeyedNew = null;
      recovery = PinRecoveryService(
        store: store,
        securityService: security,
        pbkdf2Iterations: 1000, // Rapide en test unitaire
        rekeyDatabase: ({
          required String oldDerivedKey,
          required String newDerivedKey,
        }) async {
          rekeyedOld = oldDerivedKey;
          rekeyedNew = newDerivedKey;
        },
      );
    });

    test('scelle, vérifie (insensible casse/espaces) et réinitialise le PIN via rekey',
        () async {
      final oldKey = await security.initializeMasterPin('147258');

      await recovery.configureRecovery(
        masterDerivedKey: oldKey,
        items: const <SecurityQuestionAnswer>[
          SecurityQuestionAnswer(
            question: 'Dans quelle ville êtes-vous né(e) ?',
            answer: 'Dakar',
          ),
          SecurityQuestionAnswer(
            question: 'Quel est le nom de votre école primaire ?',
            answer: 'Ecole Liberté',
          ),
          SecurityQuestionAnswer(
            question: 'Quel plat traditionnel préférez-vous par-dessus tout ?',
            answer: 'Thiéboudienne',
          ),
        ],
      );

      expect(await recovery.isRecoveryConfigured(), isTrue);

      // Mauvaise réponse -> refus MAC + incrément anti-force brute SEC-07
      final wrong = await recovery.verifyAnswersAndUnwrapKey(
        const <String>['Dakar', 'Mauvaise', 'Thiéboudienne'],
      );
      expect(wrong, isNull);
      expect(await security.getFailedAttempts(), equals(1));

      // Bonnes réponses avec casse/espaces différents -> déballage exact
      const validAnswers = <String>[
        '  dakar ',
        'ecole   liberté',
        'THIÉBOUDIENNE',
      ];
      final unwrapped = await recovery.verifyAnswersAndUnwrapKey(validAnswers);
      expect(unwrapped, equals(oldKey));

      // Reset vers un nouveau Master PIN + PRAGMA rekey + ré-enveloppage
      final newKey = await recovery.resetMasterPinWithRecoveredKey(
        recoveredOldKey: unwrapped!,
        verifiedAnswers: validAnswers,
        newPin: '852963',
      );

      expect(rekeyedOld, equals(oldKey));
      expect(rekeyedNew, equals(newKey));
      expect(newKey, equals(CryptoEngine.deriveDatabaseKey('852963')));

      // Le nouveau PIN fonctionne immédiatement
      final auth = await security.verifyPin('852963');
      expect(auth.status, equals(PinAuthStatus.masterSuccess));

      // Les 3 mêmes réponses déballent désormais la NOUVELLE clé !
      final unwrappedAgain =
          await recovery.verifyAnswersAndUnwrapKey(validAnswers);
      expect(unwrappedAgain, equals(newKey));
    });

    test('interdit la collision avec le Decoy PIN lors d\'une récupération',
        () async {
      final oldKey = await security.initializeMasterPin('111222');
      await security.setDecoyPin('999888');

      await recovery.configureRecovery(
        masterDerivedKey: oldKey,
        items: const <SecurityQuestionAnswer>[
          SecurityQuestionAnswer(question: 'Q1', answer: 'Rep1'),
          SecurityQuestionAnswer(question: 'Q2', answer: 'Rep2'),
          SecurityQuestionAnswer(question: 'Q3', answer: 'Rep3'),
        ],
      );

      final unwrapped = await recovery.verifyAnswersAndUnwrapKey(
        const <String>['rep1', 'rep2', 'rep3'],
      );

      await expectLater(
        recovery.resetMasterPinWithRecoveredKey(
          recoveredOldKey: unwrapped!,
          verifiedAnswers: const <String>['rep1', 'rep2', 'rep3'],
          newPin: '999888',
        ),
        throwsA(isA<PinCollisionException>()),
      );
    });
  });
}