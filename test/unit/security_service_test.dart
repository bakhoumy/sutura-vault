import 'package:flutter_test/flutter_test.dart';
import 'package:sutura_vault/core/security/security_service.dart';

class _InMemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> deleteAll() async => _data.clear();

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

void main() {
  group('SecurityService — Bouclier (SEC-03, SEC-05, SEC-06, SEC-07)', () {
    late _InMemorySecureStore store;
    late DateTime fakeNow;
    late SecurityService service;

    setUp(() {
      store = _InMemorySecureStore();
      fakeNow = DateTime(2025, 1, 1, 12, 0, 0);
      service = SecurityService(store: store, clock: () => fakeNow);
    });

    test('SEC-05 : interdit mathématiquement Master PIN == Decoy PIN', () async {
      await service.initializeMasterPin('147258');

      await expectLater(
        service.setDecoyPin('147258'),
        throwsA(isA<PinCollisionException>()),
      );

      // Un Decoy PIN distinct fonctionne et ouvre la session decoy
      await service.setDecoyPin('963852');

      final masterRes = await service.verifyPin('147258');
      expect(masterRes.status, equals(PinAuthStatus.masterSuccess));

      final decoyRes = await service.verifyPin('963852');
      expect(decoyRes.status, equals(PinAuthStatus.decoySuccess));
      expect(decoyRes.derivedKey, isNot(equals(masterRes.derivedKey)));
    });

    test('SEC-07 : lockout 30s après 3 échecs, 2min après 5 échecs et réarmement auto', () async {
      await service.initializeMasterPin('112233');

      final r1 = await service.verifyPin('000001');
      expect(r1.status, equals(PinAuthStatus.invalidPin));

      final r2 = await service.verifyPin('000002');
      expect(r2.status, equals(PinAuthStatus.invalidPin));

      // 3e échec -> blocage 30s
      final r3 = await service.verifyPin('000003');
      expect(r3.status, equals(PinAuthStatus.lockedOut));
      expect(r3.remainingLockoutSeconds, equals(30));

      // Même le bon PIN est bloqué pendant le lockout
      final duringLock = await service.verifyPin('112233');
      expect(duringLock.status, equals(PinAuthStatus.lockedOut));

      // Avance de 31 secondes -> réarmement automatique garanti
      fakeNow = fakeNow.add(const Duration(seconds: 31));
      expect(await service.getRemainingLockoutSeconds(), equals(0));

      // 4e échec (encore autorisé, puis 5e -> blocage 2 minutes = 120s)
      final r4 = await service.verifyPin('000004');
      expect(r4.status, equals(PinAuthStatus.invalidPin));

      final r5 = await service.verifyPin('000005');
      expect(r5.status, equals(PinAuthStatus.lockedOut));
      expect(r5.remainingLockoutSeconds, equals(120));

      // Après 121s -> débloqué, bon PIN réinitialise le compteur
      fakeNow = fakeNow.add(const Duration(seconds: 121));
      final ok = await service.verifyPin('112233');
      expect(ok.status, equals(PinAuthStatus.masterSuccess));
      expect(await service.getFailedAttempts(), equals(0));
    });

    test('SEC-06 : Mode Zone Hostile purge la clé biométrique du Keystore', () async {
      final masterKey = await service.initializeMasterPin('482910');

      await service.setBiometricsAllowed(
        allowed: true,
        masterDerivedKey: masterKey,
      );
      expect(await service.isBiometricsUserAllowed(), isTrue);

      // Activation du Mode Zone Hostile -> biométrie coupée et clé effacée
      await service.setBiometricsAllowed(allowed: false);
      expect(await service.isBiometricsUserAllowed(), isFalse);
      expect(await store.read('sutura_bio_master_key'), isNull);
    });
  });
}