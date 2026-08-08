import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../application/platform_migration_dry_run.dart';

/// Read-only [PlatformMigrationSource] over the legacy SQLite tables. Reads raw
/// rows (not record models) so the dry-run mapper can flag any unmapped column.
///
/// `import_mappings` is read alongside `import_jobs` because a mapping row is
/// not an entity of its own — it folds into its job's `mapping` object — and an
/// orphaned mapping row must stay visible to the mapper rather than being
/// filtered out here.
class SqlitePlatformAuditJobsMigrationSource
    implements PlatformMigrationSource {
  const SqlitePlatformAuditJobsMigrationSource(this._database);

  final Database _database;

  @override
  Future<PlatformMigrationSourceSnapshot> read() async {
    final tasks = await _database.query('tasks', orderBy: 'id ASC');
    final notifications = await _database.query(
      'notifications',
      orderBy: 'id ASC',
    );
    final importJobs = await _database.query('import_jobs', orderBy: 'id ASC');
    final importMappings = await _database.query(
      'import_mappings',
      orderBy: 'id ASC',
    );
    return PlatformMigrationSourceSnapshot(
      tasks: tasks.map(Map<String, Object?>.from).toList(growable: false),
      notifications: notifications
          .map(Map<String, Object?>.from)
          .toList(growable: false),
      importJobs: importJobs
          .map(Map<String, Object?>.from)
          .toList(growable: false),
      importMappings: importMappings
          .map(Map<String, Object?>.from)
          .toList(growable: false),
    );
  }
}
