import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../application/party_migration_dry_run.dart';

/// Read-only [PartyMigrationSource] over the legacy SQLite tables. Reads raw
/// rows (not record models) so the dry-run mapper can flag any unmapped column.
class SqliteContactsPartiesMigrationSource implements PartyMigrationSource {
  const SqliteContactsPartiesMigrationSource(this._database);

  final Database _database;

  @override
  Future<PartyMigrationSourceSnapshot> read() async {
    final tenants = await _database.query('tenants', orderBy: 'id ASC');
    final contractors = await _database.query('contractors', orderBy: 'id ASC');
    final contacts = await _database.query('contacts', orderBy: 'id ASC');
    return PartyMigrationSourceSnapshot(
      tenants: tenants.map(Map<String, Object?>.from).toList(growable: false),
      contractors: contractors
          .map(Map<String, Object?>.from)
          .toList(growable: false),
      contacts: contacts.map(Map<String, Object?>.from).toList(growable: false),
    );
  }
}
