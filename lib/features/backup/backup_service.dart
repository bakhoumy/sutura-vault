import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:sutura_vault/core/crypto/crypto_engine.dart';
import 'package:sutura_vault/core/database/database_helper.dart';
import 'package:sutura_vault/core/security/panic_wipe_service.dart';
import 'package:sutura_vault/core/security/security_guard.dart';
import 'package:sutura_vault/core/security/security_service.dart';

/// Service de sauvegarde directe `.db` et de restauration en bac à sable (Section 4).
class BackupService {
  BackupService._();

  /// Section 4.1 : Consolide WAL et copie physiquement la base chiffrée AES-256
  /// vers `Download/sutura_backup_[timestamp].db`.
  static Future<File> exportEncryptedBackup() async {
    await DatabaseHelper.instance.checkpoint();

    final isDecoy = DatabaseHelper.instance.isDecoySession;
    final sourcePath =
        await DatabaseHelper.instance.getDatabasePath(isDecoy: isDecoy);
    final sourceFile = File(sourcePath);

    if (!await sourceFile.exists()) {
      throw StateError('Base chiffrée introuvable sur le stockage local.');
    }

    final now = DateTime.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final fileName = 'sutura_backup_$stamp.db';

    final downloadDir = Directory('/storage/emulated/0/Download');
    final targetDir = await downloadDir.exists()
        ? downloadDir
        : await getApplicationDocumentsDirectory();

    final targetPath = p.join(targetDir.path, fileName);
    return sourceFile.copy(targetPath);
  }

  /// Partage natif 1-clic (USB OTG, PC, Bluetooth, SD) sous SecurityGuard.
  static Future<void> shareBackupFile(File backupFile) async {
    await SecurityGuard.instance.runProtected<void>(() async {
      await Share.shareXFiles(
        <XFile>[XFile(backupFile.path)],
        text: 'Sauvegarde chiffrée AES-256 Sutura Vault (.db)',
      );
    });
  }

  /// Section 4.2 : Protocole de Restauration Sécurisée en Bac à Sable.
  ///
  /// 1. Copie l'archive `.db` dans un espace temporaire (zéro risque sur la base active).
  /// 2. Ouvre et valide le déchiffrement SQLCipher (`SELECT count(*) FROM sqlite_master`).
  /// 3. Si [currentDevicePin] diffère de [archivePin], harmonise la clé via `PRAGMA rekey`.
  /// 4. Ferme la base active, purge `-wal`/`-shm`, remplace atomiquement.
  static Future<void> restoreFromBackup({
    required File backupFile,
    required String archivePin,
    String? currentDevicePin,
  }) async {
    if (!await backupFile.exists()) {
      throw ArgumentError('Le fichier de sauvegarde sélectionné n\'existe plus.');
    }
    if (!SecurityService.isValidPinFormat(archivePin)) {
      throw ArgumentError('Le Master PIN de l\'archive doit faire 6 chiffres.');
    }

    final archiveKey = CryptoEngine.deriveDatabaseKey(archivePin);
    String? targetDeviceKey;

    if (currentDevicePin != null && currentDevicePin.isNotEmpty) {
      if (!SecurityService.isValidPinFormat(currentDevicePin)) {
        throw ArgumentError(
          'Le Master PIN actuel du téléphone doit faire 6 chiffres.',
        );
      }
      final verification =
          await SecurityService.instance.verifyPin(currentDevicePin);
      if (verification.status != PinAuthStatus.masterSuccess) {
        throw StateError('Le Master PIN actuel du téléphone est incorrect.');
      }
      targetDeviceKey = verification.derivedKey;
    }

    // 1. Copie isolée en bac à sable
    final tempDir = await getTemporaryDirectory();
    final sandboxPath = p.join(
      tempDir.path,
      'sutura_sandbox_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    final sandboxFile = await backupFile.copy(sandboxPath);

    Database? sandboxDb;
    try {
      // 2. Test effectif en bac à sable
      sandboxDb = await openDatabase(
        sandboxPath,
        password: archiveKey,
        readOnly: false,
      );

      final integrity = await sandboxDb.rawQuery(
        'SELECT count(*) FROM sqlite_master',
      );
      final tableCount = Sqflite.firstIntValue(integrity) ?? 0;
      if (tableCount <= 0) {
        throw StateError('Archive SQLite vide ou incompatible.');
      }

      // Vérifie que le schéma Sutura Vault existe bien dans l'archive
      final tables = await sandboxDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='vault_items'",
      );
      if (tables.isEmpty) {
        throw StateError(
          'Ce fichier .db ne semble pas être un coffre Sutura Vault valide.',
        );
      }

      // 3. Harmonisation transparente de clé si PIN archive != PIN actuel
      if (targetDeviceKey != null &&
          targetDeviceKey != archiveKey &&
          CryptoEngine.isValidDerivedKey(targetDeviceKey)) {
        await sandboxDb.rawQuery("PRAGMA rekey = '$targetDeviceKey'");
      }

      try {
        await sandboxDb.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}

      await sandboxDb.close();
      sandboxDb = null;

      // 4. Remplacement atomique de la base active
      final isDecoy = DatabaseHelper.instance.isDecoySession;
      await DatabaseHelper.instance.lock();

      final activePath =
          await DatabaseHelper.instance.getDatabasePath(isDecoy: isDecoy);

      for (final suffix in const <String>['-wal', '-shm', '-journal']) {
        final residue = File('$activePath$suffix');
        if (await residue.exists()) {
          await residue.delete();
        }
      }

      await sandboxFile.copy(activePath);
    } catch (e) {
      if (sandboxDb != null && sandboxDb.isOpen) {
        await sandboxDb.close();
      }
      if (e is StateError || e is ArgumentError) rethrow;
      throw StateError(
        'Échec du déchiffrement en bac à sable : vérifiez le Master PIN de l\'archive.',
      );
    } finally {
      // Nettoyage sécurisé du bac à sable
      await PanicWipeService.shredFile(sandboxFile);
      for (final suffix in const <String>['-wal', '-shm', '-journal']) {
        await PanicWipeService.shredFile(File('$sandboxPath$suffix'));
      }
    }
  }
}