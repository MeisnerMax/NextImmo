/// Generates a deterministic legacy fixture database for the P2-X01-AP4
/// cutover verification.
///
/// Why a generator instead of a checked-in binary: the fixture must use the
/// *real* legacy schema, which lives in `DbMigrations`. Building it through
/// `AppDatabase` means the fixture follows every future schema migration
/// automatically, and a schema change that would break the cutover surfaces
/// here rather than in production. A committed `.db` blob would also be
/// unreviewable.
///
/// The fixture is the migration's own Asset-Overview seed (which `onCreate`
/// provisions automatically) plus the `FX-*` rows added here. The seed is
/// generated from a workbook and therefore deterministic, and the added rows
/// cover the cases the seed does not: an archived property with a real
/// tombstone, the full set of asset attributes, an organization-shaped party,
/// and an occupied unit with the lease that AGG-004 requires.
///
/// Everything is fixed — ids, timestamps, values — so the cutover manifest
/// checksum is reproducible across machines and runs. No real customer data is
/// involved, which is what makes this safe to run in CI.
///
/// Usage:
///
/// ```
/// dart run tool/generate_cutover_fixture.dart --output <path to fixture.db>
/// ```
library;

import 'dart:io';

// `DbMigrations` directly, not `AppDatabase`: the latter pulls in
// `path_provider` and therefore Flutter, which `dart run` cannot load. The
// schema is identical — this is the same onCreate the app uses.
import 'package:neximmo_app/data/sqlite/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fixed epoch millis so every generated row is byte-identical between runs.
const _createdAt = 1700000000000;
const _updatedAt = 1700000100000;
const _deletedAt = 1700000200000;

Future<int> main(List<String> args) async {
  final output = _parseOutput(args);
  if (output == null) {
    stderr.writeln(
      'Usage: dart run tool/generate_cutover_fixture.dart --output <path>',
    );
    return 64;
  }

  // Absolute on purpose: sqflite resolves a *relative* database path against
  // its own default database directory, not the working directory, so
  // `--output build/fixture.db` would silently land somewhere else than the
  // path reported here — and the caller would then not find it.
  final file = File(output).absolute;
  if (file.existsSync()) {
    file.deleteSync();
  }
  file.parent.createSync(recursive: true);

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Schema comes from the real migrations, not from a hand-written DDL copy.
  final database = await databaseFactoryFfi.openDatabase(
    file.path,
    options: OpenDatabaseOptions(
      version: DbMigrations.currentVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: DbMigrations.onCreate,
      onUpgrade: DbMigrations.onUpgrade,
    ),
  );

  await database.transaction((txn) async {
    // onCreate already provisions the default workspace, so this normalises it
    // to fixed values rather than inserting a second one.
    await txn.insert(
      'workspaces',
      <String, Object?>{
        'id': 'ws_default',
        'name': 'Fixture Workspace',
        'docs_root_path': 'workspace/docs',
        'created_at': _createdAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Two properties: one active and fully populated with the asset attributes
    // the AP4 migration added, one archived with a real tombstone. Together
    // they cover the mapper's two hardest paths.
    await txn.insert('properties', <String, Object?>{
      'id': 'FX-0001',
      'name': 'Fixture Wohnhaus',
      'address_line1': 'Fixturestrasse 1',
      'address_line2': null,
      'zip': '10115',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'multifamily',
      'units': 2,
      'sqft': 240.0,
      'year_built': 1998,
      'notes': 'Fixture note',
      'created_at': _createdAt,
      'updated_at': _updatedAt,
      'archived': 0,
      'land_area': 500.0,
      'residential_area': 200.0,
      'commercial_area': 40.0,
      'parking_spots': 3,
      'owner_company': 'Fixture Invest GmbH',
      'purchase_date': _createdAt,
      'purchase_price': 750000.0,
      'notary': 'Notariat Fixture',
      'seller': 'Fixture Verkaeufer',
      'land_registry_details': 'Blatt 1',
      'parcel': 'Flur 1, Flurstueck 1',
      'energy_certificate': 'B, 80 kWh',
      'insurance_details': 'Police 1',
      'tax_assignment': 'Finanzamt Fixture',
    });
    await txn.insert('properties', <String, Object?>{
      'id': 'FX-0002',
      'name': 'Fixture Archiviert',
      'address_line1': 'Fixturestrasse 2',
      'zip': '10117',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'office',
      'units': 0,
      'created_at': _createdAt,
      'updated_at': _updatedAt,
      'archived': 1,
      'deleted_at': _deletedAt,
      'deleted_by': 'user_owner',
    });

    // One person and one organization, so the derived party type is exercised
    // in both directions.
    await txn.insert('tenants', <String, Object?>{
      'id': 'FX-T-0001',
      'display_name': 'Erika Beispiel',
      'legal_name': 'Erika Beispiel',
      'email': 'erika@example.com',
      'phone': '030123456',
      'status': 'active',
      'created_at': _createdAt,
      'updated_at': _updatedAt,
    });
    await txn.insert('tenants', <String, Object?>{
      'id': 'FX-T-0002',
      'display_name': 'Fixture Invest GmbH',
      'legal_name': 'Fixture Invest GmbH',
      'status': 'active',
      'created_at': _createdAt,
      'updated_at': _updatedAt,
    });

    // One occupied unit (needs its lease to satisfy AGG-004) and one vacant.
    await txn.insert('units', <String, Object?>{
      'id': 'FX-U-0001',
      'asset_property_id': 'FX-0001',
      'unit_code': 'WE-01',
      'sqft': 78.0,
      'status': 'occupied',
      'market_rent_monthly': 850.0,
      'created_at': _createdAt,
      'updated_at': _updatedAt,
    });
    await txn.insert('units', <String, Object?>{
      'id': 'FX-U-0002',
      'asset_property_id': 'FX-0001',
      'unit_code': 'WE-02',
      'sqft': 62.0,
      'status': 'vacant',
      'market_rent_monthly': 700.0,
      'created_at': _createdAt,
      'updated_at': _updatedAt,
    });

    await txn.insert('leases', <String, Object?>{
      'id': 'FX-L-0001',
      'asset_property_id': 'FX-0001',
      'unit_id': 'FX-U-0001',
      'tenant_id': 'FX-T-0001',
      'lease_name': 'Mietvertrag WE-01',
      'start_date': _createdAt,
      'status': 'active',
      'base_rent_monthly': 850.0,
      'currency_code': 'EUR',
      'security_deposit': 2550.0,
      'payment_day_of_month': 3,
      'billing_frequency': 'monthly',
      'deposit_status': 'open',
      'created_at': _createdAt,
      'updated_at': _updatedAt,
    });

    await txn.insert('scenarios', <String, Object?>{
      'id': 'FX-S-0001',
      'property_id': 'FX-0001',
      'name': 'Bestandsszenario',
      'strategy_type': 'hold',
      'is_base': 0,
      'workflow_status': 'draft',
      'created_at': _createdAt,
      'updated_at': _updatedAt,
    });
  });

  final counts = <String, int>{};
  for (final table in <String>[
    'workspaces',
    'properties',
    'tenants',
    'units',
    'leases',
    'scenarios',
  ]) {
    counts[table] =
        (await database.rawQuery('select count(*) c from $table')).first['c']!
            as int;
  }
  await database.close();

  stdout.writeln('Fixture written to ${file.path}');
  counts.forEach((table, count) => stdout.writeln('  $table: $count'));
  return 0;
}

String? _parseOutput(List<String> args) {
  for (var index = 0; index + 1 < args.length; index++) {
    if (args[index] == '--output') {
      return args[index + 1];
    }
  }
  return null;
}
