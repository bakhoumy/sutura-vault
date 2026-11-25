import 'package:flutter_test/flutter_test.dart';
import 'package:sutura_vault/features/vault/models/vault_models.dart';

void main() {
  group('VaultModels — Sérialisation SQLCipher & Auto-destruction', () {
    test('VaultItem round-trip JSON sans double-chiffrement (Règle #1)', () {
      const original = VaultItem(
        id: 'item-1',
        category: 'Serveurs/SSH/Dev',
        title: 'Prod Bastion',
        login: 'root',
        password: 's3cr3t!Password',
        secondaryPin: '4829',
        url: 'ssh://10.0.0.1',
        notes: 'Accès d\'urgence',
        updatedAt: 1700000000000,
      );

      final restored = VaultItem.fromDbMap(original.toDbMap());
      expect(restored.title, equals(original.title));
      expect(restored.login, equals(original.login));
      expect(restored.password, equals(original.password));
      expect(restored.secondaryPin, equals(original.secondaryPin));
      expect(restored.url, equals(original.url));
      expect(restored.notes, equals(original.notes));
    });

    test('BlackAudioMemo détecte exactement l\'expiration 24h', () {
      final expiredAt = DateTime.now()
          .subtract(const Duration(hours: 25))
          .millisecondsSinceEpoch;
      final freshAt = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;

      final expiredMemo = BlackAudioMemo(
        id: 'a1',
        title: 'Ancien',
        durationSeconds: 10,
        audioBase64: 'AAAA',
        autoDeleteMode: AudioAutoDeleteMode.ephemeral24h,
        listenCount: 0,
        createdAt: expiredAt,
      );
      final freshMemo = BlackAudioMemo(
        id: 'a2',
        title: 'Récent',
        durationSeconds: 10,
        audioBase64: 'AAAA',
        autoDeleteMode: AudioAutoDeleteMode.ephemeral24h,
        listenCount: 0,
        createdAt: freshAt,
      );

      expect(expiredMemo.isExpired24h, isTrue);
      expect(freshMemo.isExpired24h, isFalse);
    });
  });
}