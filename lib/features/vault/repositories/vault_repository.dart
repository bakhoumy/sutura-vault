import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:sutura_vault/core/database/database_helper.dart';
import 'package:sutura_vault/features/vault/models/vault_models.dart';

/// Repository unifié des 4 compartiments SQLCipher.
class VaultRepository {
  VaultRepository._internal();
  static final VaultRepository instance = VaultRepository._internal();

  Database get _db => DatabaseHelper.instance.database;

  // ---------------------------------------------------------------------------
  // Compartiment 1 : Identifiants & Clés IT
  // ---------------------------------------------------------------------------

  Future<List<VaultItem>> getAllItems() async {
    final rows = await _db.query(
      'vault_items',
      orderBy: 'updated_at DESC',
    );
    return rows.map(VaultItem.fromDbMap).toList();
  }

  Future<void> upsertItem(VaultItem item) async {
    await _db.insert(
      'vault_items',
      item.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteItem(String id) async {
    await _db.delete('vault_items', where: 'id = ?', whereArgs: <Object>[id]);
  }

  // ---------------------------------------------------------------------------
  // Compartiment 2 : Porte-Documents
  // ---------------------------------------------------------------------------

  Future<List<VaultDocument>> getAllDocuments() async {
    final rows = await _db.query(
      'vault_documents',
      orderBy: 'created_at DESC',
    );
    return rows.map(VaultDocument.fromDbMap).toList();
  }

  Future<void> insertDocument(VaultDocument doc) async {
    await _db.insert(
      'vault_documents',
      doc.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteDocument(String id) async {
    await _db.delete(
      'vault_documents',
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  // ---------------------------------------------------------------------------
  // Compartiment 3 : Notes Noires
  // ---------------------------------------------------------------------------

  Future<List<BlackTextNote>> getAllNotes() async {
    final rows = await _db.query(
      'black_text_notes',
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return rows.map(BlackTextNote.fromDbMap).toList();
  }

  Future<void> upsertNote(BlackTextNote note) async {
    await _db.insert(
      'black_text_notes',
      note.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> toggleNotePin(String id, {required bool isPinned}) async {
    await _db.update(
      'black_text_notes',
      <String, Object?>{
        'is_pinned': isPinned ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  Future<void> deleteNote(String id) async {
    await _db.delete(
      'black_text_notes',
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  // ---------------------------------------------------------------------------
  // Compartiment 4 : Mémos Vocaux Noirs
  // ---------------------------------------------------------------------------

  /// Purge automatiquement les mémos éphémères (> 24h) avant de retourner la liste.
  Future<List<BlackAudioMemo>> getAllAudioMemos() async {
    final cutoffMs = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    await _db.delete(
      'black_audio_memos',
      where: 'auto_delete_mode = ? AND created_at <= ?',
      whereArgs: <Object>[AudioAutoDeleteMode.ephemeral24h.code, cutoffMs],
    );

    final rows = await _db.query(
      'black_audio_memos',
      orderBy: 'created_at DESC',
    );
    return rows.map(BlackAudioMemo.fromDbMap).toList();
  }

  Future<void> insertAudioMemo(BlackAudioMemo memo) async {
    await _db.insert(
      'black_audio_memos',
      memo.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> incrementAudioListenCount(String id) async {
    await _db.rawUpdate(
      'UPDATE black_audio_memos SET listen_count = listen_count + 1 WHERE id = ?',
      <Object>[id],
    );
  }

  Future<void> deleteAudioMemo(String id) async {
    await _db.delete(
      'black_audio_memos',
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  // ---------------------------------------------------------------------------
  // Audit Temps Réel (Section 4.3)
  // ---------------------------------------------------------------------------

  Future<VaultCounts> getVaultCounts() async {
    final items =
        Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM vault_items')) ?? 0;
    final docs =
        Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM vault_documents')) ?? 0;
    final notes =
        Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM black_text_notes')) ?? 0;
    final audio =
        Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM black_audio_memos')) ?? 0;

    return VaultCounts(
      items: items,
      documents: docs,
      notes: notes,
      audioMemos: audio,
    );
  }
}