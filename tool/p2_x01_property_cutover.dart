/// P2-X01-AP4: builds the local property cutover artifacts from the legacy
/// SQLite core.
///
/// This is the read side of the cutover and it never writes to the source: the
/// database is opened `readOnly`, so a mutation would fail rather than silently
/// change legacy data. It produces two files:
///
/// * `report.json` — the shareable dry-run evidence. Counts, checksums,
///   identifiers and issue codes only, never a source value.
/// * `import.sql` — the idempotent apply script, generated only when the report
///   is `production_import_ready`. It carries real data and stays local.
///
/// The rows travel as a single JSON document consumed by `jsonb_to_recordset`
/// rather than as concatenated literals, so no value is ever escaped into SQL
/// by hand.
///
/// Usage:
///
/// ```
/// dart run tool/p2_x01_property_cutover.dart \
///   --database <path to app_data.db> \
///   --source-workspace-id ws_default \
///   --target-workspace-id <uuid> \
///   --target-workspace-key neximmo \
///   --actor-id <uuid> \
///   --output <directory>
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:neximmo_app/features/portfolio_property/application/reference_migration_dry_run.dart';
import 'package:neximmo_app/features/portfolio_property/data/sqlite_reference_migration_source_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/data/sqlite_to_postgres_reference_dry_run_mapper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The target columns, in the order the generated statement uses them. Kept
/// explicit so a schema drift surfaces as a Postgres error on apply instead of
/// a silently skipped column.
const Map<String, String> _propertyColumnTypes = <String, String>{
  'id': 'uuid',
  'workspace_id': 'uuid',
  'name': 'text',
  'address_line1': 'text',
  'address_line2': 'text',
  'zip': 'text',
  'city': 'text',
  'country': 'text',
  'property_type': 'text',
  'units': 'integer',
  'sqft': 'numeric',
  'year_built': 'smallint',
  'notes': 'text',
  'status': 'public.property_status',
  'created_at': 'timestamptz',
  'updated_at': 'timestamptz',
  'created_by': 'uuid',
  'updated_by': 'uuid',
  'version': 'bigint',
  'deleted_at': 'timestamptz',
  'land_area': 'numeric',
  'residential_area': 'numeric',
  'commercial_area': 'numeric',
  'parking_spots': 'integer',
  'owner_company': 'text',
  'purchase_date': 'timestamptz',
  'purchase_price': 'numeric',
  'notary': 'text',
  'seller': 'text',
  'land_registry_details': 'text',
  'parcel': 'text',
  'energy_certificate': 'text',
  'insurance_details': 'text',
  'tax_assignment': 'text',
};

/// `id`, `workspace_id`, `created_at` and `created_by` are refused by the
/// P1-004 `properties_protected_columns` trigger on update, so a re-run must
/// not try to write them. `deleted_by` is owned by the DEBT-012 trigger.
const Set<String> _protectedOnUpdate = <String>{
  'id',
  'workspace_id',
  'created_at',
  'created_by',
};

/// Dart discards whatever `main` returns — the process exits 0 regardless — so
/// the exit code has to be assigned, not returned. `verify_p2_x01_property_
/// cutover.ps1` has been reading `$LASTEXITCODE` all along; until this was
/// fixed it was reading a constant, and only the later
/// `production_import_ready` check kept the gate closed.
///
/// `exitCode` rather than `exit()`: `exit()` terminates immediately and would
/// skip the `finally` that closes the legacy database, and it would truncate
/// the stdout line the wrapper parses as JSON.
Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/p2_x01_property_cutover.dart '
      '--database <path> --source-workspace-id <id> '
      '--target-workspace-id <uuid> --target-workspace-key <key> '
      '--actor-id <uuid> --output <dir>',
    );
    return 64;
  }

  // `--database` is a filesystem path and has to be resolved as one *before* it
  // reaches sqflite, which resolves a relative database path against its own
  // default database directory rather than the working directory. Leaving it
  // relative made the two disagree: existsSync() below resolved it against the
  // working directory and passed, then openDatabase looked somewhere else and
  // failed on a path nobody had supplied.
  // generate_cutover_fixture.dart already writes through File(...).absolute for
  // exactly this reason; the reading side was never aligned with it.
  final requestedDatabasePath = options['database']!;
  final databasePath = p.normalize(p.absolute(requestedDatabasePath));
  final source = File(databasePath);
  if (!source.existsSync()) {
    stderr.writeln(
      'Source database not found.\n'
      '  requested: $requestedDatabasePath\n'
      '  resolved:  $databasePath',
    );
    return 66;
  }

  sqfliteFfiInit();
  // readOnly is the guarantee that this tool cannot mutate the legacy core.
  final database = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );

  final ReferenceMigrationPlan plan;
  try {
    final snapshot = await SqliteReferenceMigrationSourceAdapter(
      database,
    ).read();
    plan = const SqliteToPostgresReferenceDryRunMapper().mapToPlan(
      snapshot: snapshot,
      request: ReferenceMigrationDryRunRequest(
        sourceWorkspaceId: options['source-workspace-id']!,
        targetWorkspaceId: options['target-workspace-id']!,
        targetWorkspaceKey: options['target-workspace-key']!,
        migrationActorId: options['actor-id']!,
        confirmGlobalPropertyWorkspaceBinding: true,
        inferArchivedAtFromUpdatedAt: true,
      ),
    );
  } finally {
    await database.close();
  }

  final outputDirectory = Directory(options['output']!);
  outputDirectory.createSync(recursive: true);
  final reportFile = File('${outputDirectory.path}/report.json');
  reportFile.writeAsStringSync(plan.report.toCanonicalJson());

  final report = plan.report;
  final propertySummary = report.summaries.firstWhere(
    (summary) => summary.entity == ReferenceMigrationEntity.property,
  );
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'status': report.status.name,
      'production_import_ready': report.productionImportReady,
      'manifest_checksum': report.manifestChecksum,
      'source_rows': propertySummary.sourceRows,
      'mapped_rows': propertySummary.mappedRows,
      'rejected_rows': propertySummary.rejectedRows,
      'counts_reconcile': propertySummary.countsReconcile,
      'checksums_reconcile': propertySummary.checksumsReconcile,
      'report': reportFile.path,
    }),
  );

  if (!report.productionImportReady) {
    stderr.writeln(
      'Dry run is not import ready; no apply script written. '
      'Errors: '
      '${report.issues.where((issue) => issue.severity == ReferenceMigrationIssueSeverity.error).map((issue) => issue.toCanonicalMap()).toList()}',
    );
    return 65;
  }

  final importFile = File('${outputDirectory.path}/import.sql');
  importFile.writeAsStringSync(
    _buildImportSql(
      propertyTargets: plan.propertyTargets,
      targetWorkspaceId: options['target-workspace-id']!,
    ),
  );
  stdout.writeln(jsonEncode(<String, Object?>{'import': importFile.path}));
  return 0;
}

String _buildImportSql({
  required List<Map<String, Object?>> propertyTargets,
  required String targetWorkspaceId,
}) {
  final rows =
      propertyTargets.map((target) {
        return <String, Object?>{
          for (final column in _propertyColumnTypes.keys)
            column: target[column],
        };
      }).toList();
  final payload = jsonEncode(rows);
  if (payload.contains(r'$cutover$')) {
    throw StateError('Source data collides with the SQL dollar quote tag.');
  }

  final columns = _propertyColumnTypes.keys.join(', ');
  final recordDefinition = _propertyColumnTypes.entries
      .map((entry) => '${entry.key} ${entry.value}')
      .join(', ');
  final updateAssignments = _propertyColumnTypes.keys
      .where((column) => !_protectedOnUpdate.contains(column))
      .map((column) => '$column = excluded.$column')
      .join(',\n      ');

  return '''
-- P2-X01-AP4 property cutover. Generated from the deterministic dry-run; do
-- not edit by hand. Re-running is safe: rows are keyed by the UUIDv5 target id
-- derived from the legacy id, so a second run updates instead of duplicating.
begin;

insert into public.properties ($columns)
select $columns
  from jsonb_to_recordset(\$cutover\$$payload\$cutover\$::jsonb)
    as source($recordDefinition)
on conflict (id) do update set
      $updateAssignments;

-- Fail closed if the applied set does not match the planned set exactly.
do \$guard\$
declare
  v_expected integer := ${rows.length};
  v_actual integer;
begin
  select count(*) into v_actual
    from public.properties
   where workspace_id = '$targetWorkspaceId'::uuid;
  if v_actual <> v_expected then
    raise exception
      'P2-X01-AP4 cutover mismatch: expected % properties, found %',
      v_expected, v_actual;
  end if;
end
\$guard\$;

commit;
''';
}

Map<String, String>? _parseArgs(List<String> args) {
  const required = <String>[
    'database',
    'source-workspace-id',
    'target-workspace-id',
    'target-workspace-key',
    'actor-id',
    'output',
  ];
  final parsed = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (!argument.startsWith('--') || index + 1 >= args.length) {
      return null;
    }
    parsed[argument.substring(2)] = args[++index];
  }
  for (final key in required) {
    if ((parsed[key] ?? '').isEmpty) {
      return null;
    }
  }
  return parsed;
}
