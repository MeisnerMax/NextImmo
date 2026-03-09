import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/documents.dart';

class RequiredDocumentsRepo {
  const RequiredDocumentsRepo(this._db);

  final Database _db;

  Future<List<RequiredDocumentRecord>> list({
    String? entityType,
    String? propertyType,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (entityType != null && entityType.trim().isNotEmpty) {
      where.add('entity_type = ?');
      args.add(entityType.trim());
    }
    if (propertyType != null && propertyType.trim().isNotEmpty) {
      where.add('(property_type = ? OR property_type IS NULL)');
      args.add(propertyType.trim());
    }
    final rows = await _db.query(
      'required_documents',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'entity_type ASC, property_type ASC, created_at DESC',
    );
    return rows.map(RequiredDocumentRecord.fromMap).toList(growable: false);
  }

  Future<RequiredDocumentRecord> upsert({
    String? id,
    required String entityType,
    String? propertyType,
    required String typeId,
    required bool requiredFlag,
    String? expiresFieldKey,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = RequiredDocumentRecord(
      id: id ?? const Uuid().v4(),
      entityType: entityType.trim(),
      propertyType:
          propertyType?.trim().isEmpty ?? true ? null : propertyType!.trim(),
      typeId: typeId,
      required: requiredFlag,
      expiresFieldKey:
          expiresFieldKey?.trim().isEmpty ?? true
              ? null
              : expiresFieldKey!.trim(),
      createdAt: now,
    );
    await _db.insert(
      'required_documents',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return record;
  }

  Future<void> delete(String id) async {
    await _db.delete(
      'required_documents',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
