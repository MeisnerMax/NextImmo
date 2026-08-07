/// P2-X01-AP4: builds the domain cutover artifacts (parties, party roles, and
/// the stages that follow) from the legacy SQLite core.
///
/// Same guarantees as the property cutover: the source is opened `readOnly`,
/// the report carries no source values, and the apply script is generated only
/// when the plan is import ready. Rows travel as JSON through
/// `jsonb_to_recordset`, so no value is escaped into SQL by hand.
///
/// Usage:
///
/// ```
/// dart run tool/p2_x01_domain_cutover.dart \
///   --database <path to app_data.db> \
///   --target-workspace-id <uuid> \
///   --actor-id <uuid> \
///   --output <directory>
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:neximmo_app/features/legacy_cutover/application/legacy_cutover.dart';
import 'package:neximmo_app/features/legacy_cutover/data/legacy_cutover_planner.dart';
import 'package:neximmo_app/features/legacy_cutover/data/sqlite_legacy_cutover_source_adapter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Target table shape per entity, in apply order. Columns are explicit so a
/// schema drift fails loudly on apply rather than skipping a column silently.
class _TableSpec {
  const _TableSpec({
    required this.table,
    required this.columns,
    required this.protectedOnUpdate,
  });

  final String table;
  final Map<String, String> columns;

  /// Columns refused by the `reject_protected_column_update` triggers, which a
  /// re-run must therefore not attempt to write.
  final Set<String> protectedOnUpdate;
}

const Map<LegacyCutoverEntity, _TableSpec> _specs =
    <LegacyCutoverEntity, _TableSpec>{
      LegacyCutoverEntity.party: _TableSpec(
        table: 'public.parties',
        columns: <String, String>{
          'id': 'uuid',
          'workspace_id': 'uuid',
          'party_type': 'public.party_type',
          'display_name': 'text',
          'legal_name': 'text',
          'email': 'text',
          'phone': 'text',
          'notes': 'text',
          'merged_into_party_id': 'uuid',
          'created_at': 'timestamptz',
          'updated_at': 'timestamptz',
          'created_by': 'uuid',
          'updated_by': 'uuid',
          'version': 'bigint',
          'deleted_at': 'timestamptz',
        },
        protectedOnUpdate: <String>{
          'id',
          'workspace_id',
          'created_at',
          'created_by',
        },
      ),
      // Units come before roles only by map order; they depend on properties,
      // which the property cutover applied earlier.
      LegacyCutoverEntity.unit: _TableSpec(
        table: 'public.units',
        columns: <String, String>{
          'id': 'uuid',
          'workspace_id': 'uuid',
          'property_id': 'uuid',
          'unit_code': 'text',
          'unit_type': 'text',
          'status': 'public.unit_status',
          'floor': 'text',
          'area_sqm': 'numeric',
          'rooms': 'numeric',
          'bathrooms': 'numeric',
          'target_rent_monthly': 'numeric',
          'market_rent_monthly': 'numeric',
          'currency_code': 'text',
          'vacancy_since': 'date',
          'vacancy_reason': 'text',
          'offline_reason': 'text',
          'marketing_status': 'text',
          'renovation_status': 'text',
          'expected_ready_date': 'date',
          'next_action': 'text',
          'notes': 'text',
          'created_at': 'timestamptz',
          'updated_at': 'timestamptz',
          'created_by': 'uuid',
          'updated_by': 'uuid',
          'version': 'bigint',
        },
        protectedOnUpdate: <String>{
          'id',
          'workspace_id',
          'created_at',
          'created_by',
        },
      ),
      // Leases share the units' transaction so the deferred AGG-004 occupancy
      // invariant is satisfied at COMMIT.
      LegacyCutoverEntity.lease: _TableSpec(
        table: 'public.leases',
        columns: <String, String>{
          'id': 'uuid',
          'workspace_id': 'uuid',
          'property_id': 'uuid',
          'unit_id': 'uuid',
          'tenant_party_id': 'uuid',
          'lease_name': 'text',
          'status': 'public.lease_status',
          'start_date': 'date',
          'end_date': 'date',
          'move_in_date': 'date',
          'move_out_date': 'date',
          'signed_date': 'date',
          'notice_date': 'date',
          'renewal_option_date': 'date',
          'break_option_date': 'date',
          'base_rent_monthly': 'numeric',
          'ancillary_charges_monthly': 'numeric',
          'parking_other_charges_monthly': 'numeric',
          'currency_code': 'text',
          'security_deposit': 'numeric',
          'deposit_status': 'text',
          'payment_day_of_month': 'integer',
          'billing_frequency': 'text',
          'rent_free_period_months': 'integer',
          'ended_at': 'timestamptz',
          'cancelled_at': 'timestamptz',
          'notes': 'text',
          'created_at': 'timestamptz',
          'updated_at': 'timestamptz',
          'created_by': 'uuid',
          'updated_by': 'uuid',
          'version': 'bigint',
        },
        protectedOnUpdate: <String>{
          'id',
          'workspace_id',
          'created_at',
          'created_by',
        },
      ),
      // The method configuration columns are omitted on purpose: they are NOT
      // NULL with server-side defaults, so a migrated case starts from the
      // contract's own defaults instead of values invented by the cutover.
      LegacyCutoverEntity.valuationCase: _TableSpec(
        table: 'public.valuation_cases',
        columns: <String, String>{
          'id': 'uuid',
          'workspace_id': 'uuid',
          'property_id': 'uuid',
          'scenario_id': 'uuid',
          'title': 'text',
          'kind': 'public.valuation_case_kind',
          'status': 'public.valuation_case_status',
          'approved_at': 'timestamptz',
          'approved_by': 'uuid',
          'archived_at': 'timestamptz',
          'created_at': 'timestamptz',
          'updated_at': 'timestamptz',
          'created_by': 'uuid',
          'updated_by': 'uuid',
          'version': 'bigint',
        },
        protectedOnUpdate: <String>{
          'id',
          'workspace_id',
          'created_at',
          'created_by',
        },
      ),
      LegacyCutoverEntity.partyRole: _TableSpec(
        table: 'public.party_roles',
        columns: <String, String>{
          'id': 'uuid',
          'workspace_id': 'uuid',
          'party_id': 'uuid',
          'role_type': 'public.party_role_type',
          'valid_from': 'timestamptz',
          'valid_until': 'timestamptz',
          'created_at': 'timestamptz',
          'updated_at': 'timestamptz',
          'created_by': 'uuid',
          'updated_by': 'uuid',
          'version': 'bigint',
        },
        protectedOnUpdate: <String>{
          'id',
          'workspace_id',
          'created_at',
          'created_by',
        },
      ),
    };

Future<int> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/p2_x01_domain_cutover.dart --database <path> '
      '--target-workspace-id <uuid> --actor-id <uuid> --output <dir>',
    );
    return 64;
  }

  final source = File(options['database']!);
  if (!source.existsSync()) {
    stderr.writeln('Source database not found: ${source.path}');
    return 66;
  }

  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(
    source.path,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );

  final LegacyCutoverPlan plan;
  try {
    final snapshot = await SqliteLegacyCutoverSourceAdapter(database).read();
    plan = const LegacyCutoverPlanner().plan(
      snapshot: snapshot,
      request: LegacyCutoverRequest(
        targetWorkspaceId: options['target-workspace-id']!,
        actorId: options['actor-id']!,
      ),
    );
  } finally {
    await database.close();
  }

  final outputDirectory = Directory(options['output']!)
    ..createSync(recursive: true);
  File(
    '${outputDirectory.path}/report.json',
  ).writeAsStringSync(plan.report.toCanonicalJson());

  final report = plan.report;
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'status': report.status.name,
      'import_ready': report.importReady,
      'manifest_checksum': report.manifestChecksum,
      'summaries': <String, Object?>{
        for (final summary in report.summaries)
          summary.entity.name: <String, Object?>{
            'source_rows': summary.sourceRows,
            'mapped_rows': summary.mappedRows,
            'rejected_rows': summary.rejectedRows,
            'counts_reconcile': summary.countsReconcile,
          },
      },
    }),
  );

  if (!report.importReady) {
    stderr.writeln(
      'Domain cutover is not import ready; no apply script written. Errors: '
      '${report.issues.where((issue) => issue.isError).map((issue) => issue.toCanonicalMap()).toList()}',
    );
    return 65;
  }

  File(
    '${outputDirectory.path}/import.sql',
  ).writeAsStringSync(_buildImportSql(plan));
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'import': '${outputDirectory.path}/import.sql',
    }),
  );
  return 0;
}

String _buildImportSql(LegacyCutoverPlan plan) {
  final buffer =
      StringBuffer()
        ..writeln(
          '-- P2-X01-AP4 domain cutover. Generated from the deterministic '
          'plan; do not edit by hand.',
        )
        ..writeln(
          '-- Re-running is safe: every target id is a UUIDv5 derived from the '
          'legacy id, so a second run updates instead of duplicating.',
        )
        ..writeln('begin;')
        ..writeln();

  // Apply order follows the spec order, which is dependency order: a party
  // exists before the role that references it.
  for (final entry in _specs.entries) {
    final rows = plan.targets[entry.key] ?? const <Map<String, Object?>>[];
    if (rows.isEmpty) {
      continue;
    }
    final spec = entry.value;
    final payload = jsonEncode(
      rows
          .map(
            (row) => <String, Object?>{
              for (final column in spec.columns.keys) column: row[column],
            },
          )
          .toList(),
    );
    if (payload.contains(r'$cutover$')) {
      throw StateError('Source data collides with the SQL dollar quote tag.');
    }
    final columns = spec.columns.keys.join(', ');
    final definition = spec.columns.entries
        .map((column) => '${column.key} ${column.value}')
        .join(', ');
    final updates = spec.columns.keys
        .where((column) => !spec.protectedOnUpdate.contains(column))
        .map((column) => '$column = excluded.$column')
        .join(',\n      ');

    buffer
      ..writeln('insert into ${spec.table} ($columns)')
      ..writeln('select $columns')
      ..writeln('  from jsonb_to_recordset(\$cutover\$$payload\$cutover\$::jsonb)')
      ..writeln('    as source($definition)')
      ..writeln('on conflict (id) do update set')
      ..writeln('      $updates;')
      ..writeln();
  }

  // Fail closed if the applied set does not match the planned set exactly.
  for (final entry in _specs.entries) {
    final rows = plan.targets[entry.key] ?? const <Map<String, Object?>>[];
    if (rows.isEmpty) {
      continue;
    }
    final workspaceId = rows.first['workspace_id'];
    buffer
      ..writeln('do \$guard\$')
      ..writeln('declare')
      ..writeln('  v_actual integer;')
      ..writeln('begin')
      ..writeln('  select count(*) into v_actual from ${entry.value.table}')
      ..writeln("   where workspace_id = '$workspaceId'::uuid;")
      ..writeln('  if v_actual <> ${rows.length} then')
      ..writeln(
        "    raise exception 'P2-X01-AP4 ${entry.key.name} mismatch: "
        "expected ${rows.length}, found %', v_actual;",
      )
      ..writeln('  end if;')
      ..writeln('end')
      ..writeln('\$guard\$;')
      ..writeln();
  }

  buffer.writeln('commit;');
  return buffer.toString();
}

Map<String, String>? _parseArgs(List<String> args) {
  const required = <String>[
    'database',
    'target-workspace-id',
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
