import 'package:flutter_test/flutter_test.dart';
import 'package:sutura_vault/core/crypto/crypto_engine.dart';

void main() {
  group('CryptoEngine — Dérivation & Isolation', () {
    test('dérivation déterministe et portable (64 hex chars)', () {
      final k1 = CryptoEngine.deriveDatabaseKey('482910');
      final k2 = CryptoEngine.deriveDatabaseKey('482910');

      expect(k1, equals(k2));
      expect(CryptoEngine.isValidDerivedKey(k1), isTrue);
    });

    test('séparation de domaine entre clé DB et empreinte Keystore', () {
      final dbKey = CryptoEngine.deriveDatabaseKey('482910');
      final authHash = CryptoEngine.hashPinForStorage('482910');

      expect(dbKey, isNot(equals(authHash)));
    });

    test('comparaison à temps constant exacte', () {
      final h1 = CryptoEngine.hashPinForStorage('123456');
      final h2 = CryptoEngine.hashPinForStorage('123456');
      final h3 = CryptoEngine.hashPinForStorage('654321');

      expect(CryptoEngine.constantTimeEquals(h1, h2), isTrue);
      expect(CryptoEngine.constantTimeEquals(h1, h3), isFalse);
    });
  });
}