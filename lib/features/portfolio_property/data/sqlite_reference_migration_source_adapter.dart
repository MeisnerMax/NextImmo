import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../application/reference_migration_dry_run.dart';

class SqliteReferenceMigrationSourceAdapter
    implements ReferenceMigrationSource {
  const SqliteReferenceMigrationSourceAdapter(this._database);

  final Database _database;

  @override
  Future<ReferenceMigrationSourceSnapshot> read() async {
    final workspaces = await _database.query('workspaces', orderBy: 'id ASC');
    final properties = await _database.query('properties', orderBy: 'id ASC');
    return ReferenceMigrationSourceSnapshot(
      workspaces: workspaces
          .map(Map<String, Object?>.from)
          .toList(growable: false),
      properties: properties
          .map(Map<String, Object?>.from)
          .toList(growable: false),
    );
  }
}
