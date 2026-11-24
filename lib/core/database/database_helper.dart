import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:sutura_vault/core/crypto/crypto_engine.dart';

/// Gestionnaire exclusif de la base chiffrée SQLCipher (AES-256-CBC).
///
/// Gère l'isolation physique stricte entre la vraie base (`sutura_master.db`)
/// et la base de déni plausible (`sutura_decoy.db`).
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String masterDbName = 'sutura_master.db';
  static const String decoyDbName = 'sutura_decoy.db';
  static const int _dbVersion = 1;

  Database? _database;
  bool _isDecoySession = false;

  bool get isOpen => _database != null && _database!.isOpen;
  bool get isDecoySession => _isDecoySession;

  Database get database {
    final db = _database;
    if (db == null || !db.isOpen) {
      throw StateError('Le coffre est verrouillé. Authentification requise.');
    }
    return db;
  }

  /// Retourne le chemin absolu du fichier `.db` actif (ou cible).
  Future<String> getDatabasePath({required bool isDecoy}) async {
    final dir = await getApplicationDocumentsDirectory();
    final filename = isDecoy ? decoyDbName : masterDbName;
    return p.join(dir.path, filename);
  }

  /// Ouvre la base chiffrée (Master ou Decoy) avec la clé dérivée du PIN.
  Future<Database> openVault({
    required String derivedKey,
    required bool isDecoy,
  }) async {
    if (!CryptoEngine.isValidDerivedKey(derivedKey)) {
      throw ArgumentError('Format de clé cryptographique invalide.');
    }

    await lock();

    final dbPath = await getDatabasePath(isDecoy: isDecoy);
    final db = await openDatabase(
      dbPath,
      version: _dbVersion,
      password: derivedKey,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    );

    // Validation effective immédiate du déchiffrement SQLCipher
    await db.rawQuery('SELECT count(*) FROM sqlite_master');

    _database = db;
    _isDecoySession = isDecoy;
    return db;
  }

  /// Règle d'ingénierie #3 : PRAGMAs via rawQuery protégés par try/catch.
  Future<void> _onConfigure(Database db) async {
    const pragmas = <String>[
      'PRAGMA temp_store = MEMORY',
      'PRAGMA synchronous = NORMAL',
      'PRAGMA cache_size = -4000',
    ];
    for (final pragma in pragmas) {
      try {
        await db.rawQuery(pragma);
      } catch (_) {
        // Certains périphériques Android limitent certains PRAGMAs : toléré.
      }
    }
  }

  /// Schéma relationnel minimaliste — 4 Tables Cœur (Section 5.3).
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE vault_items (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        title TEXT NOT NULL,
        encrypted_payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE vault_documents (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        doc_type TEXT NOT NULL,
        encrypted_image TEXT NOT NULL,
        notes TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE black_text_notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        category TEXT NOT NULL,
        tags TEXT,
        is_pinned INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE black_audio_memos (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        encrypted_audio TEXT NOT NULL,
        auto_delete_mode INTEGER DEFAULT 0,
        listen_count INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  /// Ferme proprement la connexion active et verrouille le coffre.
  Future<void> lock() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  /// SEC-11 : Rotation de clé isolée évitant tout blocage SQLITE_LOCKED.
  Future<void> rekeyVault({
    required String oldDerivedKey,
    required String newDerivedKey,
    required bool isDecoy,
  }) async {
    if (!CryptoEngine.isValidDerivedKey(oldDerivedKey) ||
        !CryptoEngine.isValidDerivedKey(newDerivedKey)) {
      throw ArgumentError('Clé de rotation invalide.');
    }

    // 1. Fermer toute connexion active avant PRAGMA rekey
    await lock();

    final dbPath = await getDatabasePath(isDecoy: isDecoy);
    final file = File(dbPath);
    if (!await file.exists()) {
      return;
    }

    // 2. Ouverture exclusive, rechiffrement, checkpoint et fermeture
    final db = await openDatabase(
      dbPath,
      password: oldDerivedKey,
      onConfigure: _onConfigure,
    );
    try {
      await db.rawQuery("PRAGMA rekey = '$newDerivedKey'");
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}
    } finally {
      await db.close();
    }

    // 3. Réouverture propre avec la nouvelle clé
    await openVault(derivedKey: newDerivedKey, isDecoy: isDecoy);
  }

  /// Consolide les journaux WAL avant export physique `.db` (Section 4.1).
  Future<void> checkpoint() async {
    if (!isOpen) return;
    try {
      await _database!.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}
  }

  /// Taille physique du fichier `.db` actif en octets (Centre d'Audit).
  Future<int> getActiveDatabaseSizeBytes() async {
    final dbPath = await getDatabasePath(isDecoy: _isDecoySession);
    final file = File(dbPath);
    if (!await file.exists()) return 0;
    return file.length();
  }
}