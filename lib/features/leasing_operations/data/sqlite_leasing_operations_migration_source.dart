import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../application/leasing_migration_dry_run.dart';

/// Read-only [LeasingMigrationSource] over the legacy SQLite tables. Reads raw
/// rows (not record models) so the dry-run mapper can flag any unmapped column.
///
/// `rent_roll_snapshots` is counted rather than read: the mapper does not
/// migrate them (their shape cannot become an AGG-007 snapshot) and a count is
/// exactly what it needs to report how many are being left behind.
class SqliteLeasingOperationsMigrationSource implements LeasingMigrationSource {
  const SqliteLeasingOperationsMigrationSource(this._database);

  final Database _database;

  @override
  Future<LeasingMigrationSourceSnapshot> read() async {
    final units = await _database.query('units', orderBy: 'id ASC');
    final leases = await _database.query('leases', orderBy: 'id ASC');
    final snapshots = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM rent_roll_snapshots',
    );
    return LeasingMigrationSourceSnapshot(
      units: units.map(Map<String, Object?>.from).toList(growable: false),
      leases: leases.map(Map<String, Object?>.from).toList(growable: false),
      rentRollSnapshotCount:
          (snapshots.first['count'] as num?)?.toInt() ?? 0,
    );
  }
}
