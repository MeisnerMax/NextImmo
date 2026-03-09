import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/documents.dart';

class DocumentTypesRepo {
  const DocumentTypesRepo(this._db);

  final Database _db;

  Future<List<DocumentTypeRecord>> list({String? entityType}) async {
    final rows = await _db.query(
      'document_types',
      where: entityType == null ? null : 'entity_type = ?',
      whereArgs: entityType == null ? null : <Object?>[entityType],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(DocumentTypeRecord.fromMap).toList(growable: false);
  }

  Future<DocumentTypeRecord> create({
    required String name,
    required String entityType,
    List<String> requiredFields = const <String>[],
  }) async {
    final record = DocumentTypeRecord(
      id: const Uuid().v4(),
      name: name.trim(),
      entityType: entityType.trim(),
      requiredFields: requiredFields,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insert(
      'document_types',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return record;
  }

  Future<void> update(DocumentTypeRecord record) async {
    await _db.update(
      'document_types',
      record.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[record.id],
    );
  }

  Future<void> delete(String id) async {
    await _db.delete(
      'document_types',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
