import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/portfolio.dart';

class PropertyProfileRepository {
  const PropertyProfileRepository(this._db);

  final Database _db;

  Future<PropertyProfileRecord?> getProfile(String propertyId) async {
    final rows = await _db.query(
      'property_profiles',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PropertyProfileRecord.fromMap(rows.first);
  }

  Future<void> upsertProfile(PropertyProfileRecord profile) async {
    await _db.insert(
      'property_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PropertyKpiSnapshotRecord>> listSnapshots({
    String? propertyId,
    String? portfolioId,
    String? periodFrom,
    String? periodTo,
  }) async {
    if (portfolioId != null) {
      final rows = await _db.rawQuery(
        '''
        SELECT s.*
        FROM property_kpi_snapshots s
        INNER JOIN portfolio_properties pp ON pp.property_id = s.property_id
        WHERE pp.portfolio_id = ?
          ${periodFrom != null ? 'AND s.period_date >= ?' : ''}
          ${periodTo != null ? 'AND s.period_date <= ?' : ''}
        ORDER BY s.period_date DESC
      ''',
        <Object?>[
          portfolioId,
          if (periodFrom != null) periodFrom,
          if (periodTo != null) periodTo,
        ],
      );
      return rows.map(PropertyKpiSnapshotRecord.fromMap).toList();
    }

    final conditions = <String>[];
    final args = <Object?>[];
    if (propertyId != null) {
      conditions.add('property_id = ?');
      args.add(propertyId);
    }
    if (periodFrom != null) {
      conditions.add('period_date >= ?');
      args.add(periodFrom);
    }
    if (periodTo != null) {
      conditions.add('period_date <= ?');
      args.add(periodTo);
    }
    final rows = await _db.query(
      'property_kpi_snapshots',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'period_date DESC',
    );
    return rows.map(PropertyKpiSnapshotRecord.fromMap).toList();
  }

  Future<PropertyKpiSnapshotRecord> upsertSnapshot({
    required String propertyId,
    String? scenarioId,
    required String periodDate,
    double? noi,
    double? occupancy,
    double? capex,
    double? valuation,
    required String source,
  }) async {
    final record = PropertyKpiSnapshotRecord(
      id: const Uuid().v4(),
      propertyId: propertyId,
      scenarioId: scenarioId,
      periodDate: periodDate,
      noi: noi,
      occupancy: occupancy,
      capex: capex,
      valuation: valuation,
      source: source,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insert(
      'property_kpi_snapshots',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return record;
  }
}
