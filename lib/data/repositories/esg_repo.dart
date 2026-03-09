import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/models/esg.dart';

class EsgRepository {
  const EsgRepository(this._db);

  final Database _db;

  Future<EsgProfileRecord?> getProfile(String propertyId) async {
    final rows = await _db.query(
      'esg_profiles',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return EsgProfileRecord.fromMap(rows.first);
  }

  Future<List<EsgProfileRecord>> listProfiles({int? epcExpiringBefore}) async {
    final rows = await _db.query(
      'esg_profiles',
      where:
          epcExpiringBefore == null
              ? null
              : 'epc_valid_until IS NOT NULL AND epc_valid_until <= ?',
      whereArgs:
          epcExpiringBefore == null ? null : <Object?>[epcExpiringBefore],
      orderBy: 'updated_at DESC',
    );
    return rows.map(EsgProfileRecord.fromMap).toList();
  }

  Future<void> upsertProfile(EsgProfileRecord profile) async {
    await _db.insert(
      'esg_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
