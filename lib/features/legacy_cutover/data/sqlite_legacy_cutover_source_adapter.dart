/// Read-only source adapter for the P2-X01-AP4 domain cutover.
///
/// Reads the legacy tables verbatim and in a stable order. It performs no
/// projection and no filtering: any narrowing belongs in the mapper, where it
/// is visible as a named issue.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../application/legacy_cutover.dart';

class SqliteLegacyCutoverSourceAdapter implements LegacyCutoverSource {
  const SqliteLegacyCutoverSourceAdapter(this._database);

  final Database _database;

  @override
  Future<LegacyCutoverSnapshot> read() async {
    return LegacyCutoverSnapshot(
      tenants: await _read('tenants'),
      units: await _read('units'),
      leases: await _read('leases'),
      scenarios: await _read('scenarios'),
    );
  }

  Future<List<Map<String, Object?>>> _read(String table) async {
    final rows = await _database.query(table, orderBy: 'id ASC');
    return rows.map(Map<String, Object?>.from).toList(growable: false);
  }
}
