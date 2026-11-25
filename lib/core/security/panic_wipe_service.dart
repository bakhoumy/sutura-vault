import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:sutura_vault/core/database/database_helper.dart';
import 'package:sutura_vault/core/security/security_guard.dart';
import 'package:sutura_vault/core/security/security_service.dart';
import 'package:sutura_vault/core/utils/clipboard_vault.dart';

/// Protocole d'auto-destruction anti-forensique « Panic Wipe » (SEC-12).
class PanicWipeService {
  PanicWipeService._();

  static const String confirmationPhrase = 'DETRUIRE LE COFFRE';

  /// Vérifie strictement la phrase d'armement avant toute destruction.
  static bool isPhraseValid(String input) =>
      input.trim() == confirmationPhrase;

  /// Écrase physiquement un fichier par des octets aléatoires cryptographiques
  /// avant de le supprimer du système de fichiers.
  static Future<void> shredFile(File file) async {
    if (!await file.exists()) return;

    try {
      final length = await file.length();
      if (length > 0) {
        final random = Random.secure();
        final raf = await file.open(mode: FileMode.writeOnly);
        try {
          const chunkSize = 64 * 1024; // 64 Ko
          var remaining = length;
          while (remaining > 0) {
            final toWrite = remaining < chunkSize ? remaining : chunkSize;
            final buffer = Uint8List(toWrite);
            for (var i = 0; i < toWrite; i++) {
              buffer[i] = random.nextInt(256);
            }
            await raf.writeFrom(buffer);
            remaining -= toWrite;
          }
          await raf.flush();
        } finally {
          await raf.close();
        }
      }
    } catch (_) {
      // On poursuit impérativement vers la suppression physique même en cas d'I/O partiel.
    }

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Exécute le Panic Wipe intégral (Master + Decoy + WAL/SHM + Cache + Keystore).
  static Future<void> executePanicWipe({required String phrase}) async {
    if (!isPhraseValid(phrase)) {
      throw ArgumentError(
        'Phrase de confirmation invalide. Saisir exactement : $confirmationPhrase',
      );
    }

    // 1. Fermer immédiatement toute connexion SQLCipher active & purger le presse-papiers
    await DatabaseHelper.instance.lock();
    await ClipboardVault.instance.purgeNow();
    SecurityGuard.instance.reset();

    // 2. Écraser & détruire Master DB, Decoy DB et tous les journaux SQLite
    final masterPath =
        await DatabaseHelper.instance.getDatabasePath(isDecoy: false);
    final decoyPath =
        await DatabaseHelper.instance.getDatabasePath(isDecoy: true);

    final targets = <String>[
      masterPath,
      '$masterPath-wal',
      '$masterPath-shm',
      '$masterPath-journal',
      decoyPath,
      '$decoyPath-wal',
      '$decoyPath-shm',
      '$decoyPath-journal',
    ];

    for (final path in targets) {
      await shredFile(File(path));
    }

    // 3. Nettoyer les fichiers temporaires applicatifs (audio/sandbox)
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(followLinks: false)) {
          if (entity is File) {
            await shredFile(entity);
          }
        }
      }
    } catch (_) {}

    // 4. Purge totale du Keystore matériel / Keychain
    await SecurityService.instance.wipeAllSecureKeys();
  }
}