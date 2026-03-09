import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/note.dart';
import 'search_repo.dart';

class NotesRepository {
  const NotesRepository(this._db, {SearchRepo? searchRepo}) : _searchRepo = searchRepo;

  final Database _db;
  final SearchRepo? _searchRepo;

  Future<List<NoteRecord>> listNotes({
    required String entityType,
    required String entityId,
  }) async {
    final rows = await _db.query(
      'notes',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[entityType, entityId],
      orderBy: 'created_at DESC',
    );
    return rows.map(NoteRecord.fromMap).toList();
  }

  Future<NoteRecord> addNote({
    required String entityType,
    required String entityId,
    required String text,
    String? createdBy,
  }) async {
    final note = NoteRecord(
      id: const Uuid().v4(),
      entityType: entityType,
      entityId: entityId,
      text: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      createdBy: createdBy,
    );
    await _db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildNoteRecord(note));
    }
    return note;
  }

  Future<void> deleteNote(String id) async {
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.deleteIndexEntryByEntity(entityType: 'note', entityId: id);
    }
    await _db.delete('notes', where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
