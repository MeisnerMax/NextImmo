import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/operations.dart';
import '../../core/operations/rent_roll_engine.dart';

class RentRollRepo {
  const RentRollRepo(this._db, this._engine);

  final Database _db;
  final RentRollEngine _engine;

  Future<List<UnitRecord>> listUnitsByAsset(String assetPropertyId) async {
    final rows = await _db.query(
      'units',
      where: 'asset_property_id = ?',
      whereArgs: <Object?>[assetPropertyId],
      orderBy: 'unit_code COLLATE NOCASE',
    );
    return rows.map(UnitRecord.fromMap).toList();
  }

  Future<UnitRecord> createUnit({
    required String assetPropertyId,
    required String unitCode,
    String? unitType,
    double? targetRentMonthly,
    double? beds,
    double? baths,
    double? sqft,
    String? floor,
    String status = 'vacant',
    double? marketRentMonthly,
    String? offlineReason,
    int? vacancySince,
    String? vacancyReason,
    String? marketingStatus,
    String? renovationStatus,
    int? expectedReadyDate,
    String? nextAction,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = UnitRecord(
      id: const Uuid().v4(),
      assetPropertyId: assetPropertyId,
      unitCode: unitCode,
      unitType: unitType,
      beds: beds,
      baths: baths,
      sqft: sqft,
      floor: floor,
      status: status,
      targetRentMonthly: targetRentMonthly,
      marketRentMonthly: marketRentMonthly,
      offlineReason: offlineReason,
      vacancySince: vacancySince,
      vacancyReason: vacancyReason,
      marketingStatus: marketingStatus,
      renovationStatus: renovationStatus,
      expectedReadyDate: expectedReadyDate,
      nextAction: nextAction,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert(
      'units',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return record;
  }

  Future<void> updateUnit(UnitRecord unit) async {
    await _db.update(
      'units',
      unit.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[unit.id],
    );
  }

  Future<void> deleteUnit(String id) async {
    await _db.delete('units', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<RentRollSnapshotBundle> generateSnapshot({
    required String assetPropertyId,
    required String periodKey,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final units = await listUnitsByAsset(assetPropertyId);

    final leaseRows = await _db.query(
      'leases',
      where: 'asset_property_id = ?',
      whereArgs: <Object?>[assetPropertyId],
    );
    final leases = leaseRows.map(LeaseRecord.fromMap).toList();

    final leaseIds = leases.map((lease) => lease.id).toList(growable: false);
    final schedules = <LeaseRentScheduleRecord>[];
    if (leaseIds.isNotEmpty) {
      final placeholders = List<String>.filled(leaseIds.length, '?').join(',');
      final rows = await _db.rawQuery(
        'SELECT * FROM lease_rent_schedule WHERE period_key = ? AND lease_id IN ($placeholders)',
        <Object?>[periodKey, ...leaseIds],
      );
      schedules.addAll(rows.map(LeaseRentScheduleRecord.fromMap));
    }

    final tenantRows = await _db.query('tenants');
    final tenantsById = <String, TenantRecord>{
      for (final row in tenantRows)
        (row['id']! as String): TenantRecord.fromMap(row),
    };

    final computed = _engine.compute(
      periodKey: periodKey,
      units: units,
      leases: leases,
      schedule: schedules,
      tenantsById: tenantsById,
    );

    final snapshot = RentRollSnapshotRecord(
      id: const Uuid().v4(),
      assetPropertyId: assetPropertyId,
      periodKey: periodKey,
      snapshotAt: now,
      occupancyRate: computed.occupancyRate,
      gprMonthly: computed.gprMonthly,
      vacancyLossMonthly: computed.vacancyLossMonthly,
      egiMonthly: computed.egiMonthly,
      inPlaceRentMonthly: computed.inPlaceRentMonthly,
      marketRentMonthly: computed.marketRentMonthly,
      notes: null,
    );

    final lineRecords = computed.lines
        .map(
          (line) => RentRollLineRecord(
            id: const Uuid().v4(),
            snapshotId: snapshot.id,
            unitId: line.unit.id,
            leaseId: line.lease?.id,
            tenantName: line.tenantName,
            status: line.status,
            inPlaceRentMonthly: line.inPlaceRentMonthly,
            marketRentMonthly: line.marketRentMonthly,
            leaseEndDate: line.leaseEndDate,
            createdAt: now,
          ),
        )
        .toList(growable: false);

    await _db.transaction((txn) async {
      final existing = await txn.query(
        'rent_roll_snapshots',
        columns: const <String>['id'],
        where: 'asset_property_id = ? AND period_key = ?',
        whereArgs: <Object?>[assetPropertyId, periodKey],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final existingId = existing.first['id']! as String;
        await txn.delete(
          'rent_roll_lines',
          where: 'snapshot_id = ?',
          whereArgs: <Object?>[existingId],
        );
        await txn.delete(
          'rent_roll_snapshots',
          where: 'id = ?',
          whereArgs: <Object?>[existingId],
        );
      }

      await txn.insert(
        'rent_roll_snapshots',
        snapshot.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      for (final line in lineRecords) {
        await txn.insert(
          'rent_roll_lines',
          line.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });

    return RentRollSnapshotBundle(snapshot: snapshot, lines: lineRecords);
  }

  Future<List<RentRollSnapshotRecord>> listSnapshots(
    String assetPropertyId,
  ) async {
    final rows = await _db.query(
      'rent_roll_snapshots',
      where: 'asset_property_id = ?',
      whereArgs: <Object?>[assetPropertyId],
      orderBy: 'period_key DESC',
    );
    return rows.map(RentRollSnapshotRecord.fromMap).toList();
  }

  Future<RentRollSnapshotBundle?> getSnapshot(String snapshotId) async {
    final rows = await _db.query(
      'rent_roll_snapshots',
      where: 'id = ?',
      whereArgs: <Object?>[snapshotId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final snapshot = RentRollSnapshotRecord.fromMap(rows.first);
    final linesRows = await _db.query(
      'rent_roll_lines',
      where: 'snapshot_id = ?',
      whereArgs: <Object?>[snapshotId],
      orderBy: 'status ASC, unit_id ASC',
    );
    final lines = linesRows.map(RentRollLineRecord.fromMap).toList();
    return RentRollSnapshotBundle(snapshot: snapshot, lines: lines);
  }

  Future<void> deleteSnapshot(String snapshotId) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'rent_roll_lines',
        where: 'snapshot_id = ?',
        whereArgs: <Object?>[snapshotId],
      );
      await txn.delete(
        'rent_roll_snapshots',
        where: 'id = ?',
        whereArgs: <Object?>[snapshotId],
      );
    });
  }
}
