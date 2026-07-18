import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/reference_migration_dry_run.dart';
import 'package:neximmo_app/features/portfolio_property/data/sqlite_to_postgres_reference_dry_run_mapper.dart';

void main() {
  const mapper = SqliteToPostgresReferenceDryRunMapper();
  const request = ReferenceMigrationDryRunRequest(
    sourceWorkspaceId: 'ws_default',
    targetWorkspaceId: '17000000-0000-5000-8000-000000000001',
    targetWorkspaceKey: 'legacy-default',
    migrationActorId: 'a7000000-0000-5000-8000-000000000001',
    confirmGlobalPropertyWorkspaceBinding: true,
    inferArchivedAtFromUpdatedAt: true,
  );

  test('maps the reference scope with reconciled deterministic checksums', () {
    final report = mapper.map(snapshot: _validSnapshot(), request: request);

    expect(
      report.status,
      ReferenceMigrationStatus.ready,
      reason:
          report.issues
              .where(
                (issue) =>
                    issue.severity == ReferenceMigrationIssueSeverity.error,
              )
              .map((issue) => issue.toCanonicalMap())
              .toList()
              .toString(),
    );
    expect(report.productionImportReady, isTrue);
    expect(report.manifestChecksum, hasLength(64));
    expect(report.mappings, hasLength(3));
    expect(
      report.summaries.map(
        (summary) => <Object>[
          summary.entity,
          summary.sourceRows,
          summary.mappedRows,
          summary.rejectedRows,
          summary.countsReconcile,
          summary.checksumsReconcile,
        ],
      ),
      <List<Object>>[
        <Object>[ReferenceMigrationEntity.workspace, 1, 1, 0, true, true],
        <Object>[ReferenceMigrationEntity.property, 2, 2, 0, true, true],
      ],
    );
    expect(
      report.mappings
          .where(
            (mapping) => mapping.entity == ReferenceMigrationEntity.property,
          )
          .map((mapping) => mapping.targetId),
      everyElement(matches(_uuidPattern)),
    );
    expect(
      report.issues.where(
        (issue) => issue.severity == ReferenceMigrationIssueSeverity.error,
      ),
      isEmpty,
    );
    final serialized = report.toCanonicalJson();
    for (final sensitive in <String>[
      'Default Workspace',
      'workspace/docs',
      'Musterstrasse',
      'Berlin',
      'Sensitive note',
    ]) {
      expect(serialized, isNot(contains(sensitive)));
    }
  });

  test('is byte-identical across source order and repeated runs', () {
    final snapshot = _validSnapshot();
    final reversed = ReferenceMigrationSourceSnapshot(
      workspaces: snapshot.workspaces.reversed.toList(),
      properties: snapshot.properties.reversed.toList(),
    );

    final first = mapper.map(snapshot: snapshot, request: request);
    final retry = mapper.map(snapshot: snapshot, request: request);
    final reordered = mapper.map(snapshot: reversed, request: request);

    expect(retry.toCanonicalJson(), first.toCanonicalJson());
    expect(reordered.toCanonicalJson(), first.toCanonicalJson());
    expect(reordered.manifestChecksum, first.manifestChecksum);

    final changedProperties =
        snapshot.properties.map(Map<String, Object?>.from).toList();
    changedProperties.first['city'] = 'Hamburg';
    final changed = mapper.map(
      snapshot: ReferenceMigrationSourceSnapshot(
        workspaces: snapshot.workspaces,
        properties: changedProperties,
      ),
      request: request,
    );
    expect(changed.manifestChecksum, isNot(first.manifestChecksum));
  });

  test('rejects invalid fields and never exposes their values', () {
    final invalidProperty = _property(id: 'invalid-property', archived: 2)
      ..addAll(<String, Object?>{
        'name': '   ',
        'country': 'not valid',
        'units': -1,
        'year_built': 2200,
        'owner_company': 'Secret Owner GmbH',
      });

    final report = mapper.map(
      snapshot: ReferenceMigrationSourceSnapshot(
        workspaces: <Map<String, Object?>>[_workspace()],
        properties: <Map<String, Object?>>[invalidProperty],
      ),
      request: request,
    );

    expect(report.status, ReferenceMigrationStatus.invalid);
    expect(report.productionImportReady, isFalse);
    final propertySummary = report.summaries.singleWhere(
      (summary) => summary.entity == ReferenceMigrationEntity.property,
    );
    expect(propertySummary.sourceRows, 1);
    expect(propertySummary.mappedRows, 0);
    expect(propertySummary.rejectedRows, 1);
    expect(propertySummary.countsReconcile, isTrue);
    expect(
      report.issues.map((issue) => issue.code),
      containsAll(<String>[
        'mapping.unmapped_field',
        'source.required_value_missing',
        'source.invalid_normalized_key',
        'source.integer_out_of_range',
        'source.invalid_archive_flag',
      ]),
    );
    expect(report.toCanonicalJson(), isNot(contains('Secret Owner GmbH')));
  });

  test('multiple legacy workspaces fail closed for global properties', () {
    final report = mapper.map(
      snapshot: ReferenceMigrationSourceSnapshot(
        workspaces: <Map<String, Object?>>[
          _workspace(),
          _workspace(id: 'ws_other'),
        ],
        properties: <Map<String, Object?>>[_property(id: 'property-1')],
      ),
      request: request,
    );

    expect(report.status, ReferenceMigrationStatus.invalid);
    expect(report.mappings, isEmpty);
    expect(
      report.issues.map((issue) => issue.code),
      contains('ownership.workspace_ambiguous'),
    );
    expect(
      report.summaries.every((summary) => summary.countsReconcile),
      isTrue,
    );
  });

  test('archive timestamp inference must be explicitly accepted', () {
    const strictRequest = ReferenceMigrationDryRunRequest(
      sourceWorkspaceId: 'ws_default',
      targetWorkspaceId: '17000000-0000-5000-8000-000000000001',
      targetWorkspaceKey: 'legacy-default',
      migrationActorId: 'a7000000-0000-5000-8000-000000000001',
      confirmGlobalPropertyWorkspaceBinding: true,
      inferArchivedAtFromUpdatedAt: false,
    );
    final report = mapper.map(
      snapshot: ReferenceMigrationSourceSnapshot(
        workspaces: <Map<String, Object?>>[_workspace()],
        properties: <Map<String, Object?>>[
          _property(id: 'archived', archived: 1),
        ],
      ),
      request: strictRequest,
    );

    expect(report.status, ReferenceMigrationStatus.invalid);
    expect(
      report.issues.map((issue) => issue.code),
      contains('mapping.archive_timestamp_missing'),
    );
  });

  test('controlled abort emits no complete dataset checksums', () {
    final report = mapper.map(
      snapshot: _validSnapshot(),
      request: request,
      abortSignal: _AbortAfterChecks(3),
    );

    expect(report.status, ReferenceMigrationStatus.aborted);
    expect(report.productionImportReady, isFalse);
    final propertySummary = report.summaries.singleWhere(
      (summary) => summary.entity == ReferenceMigrationEntity.property,
    );
    expect(propertySummary.processedRows, 1);
    expect(propertySummary.sourceRows, 2);
    expect(propertySummary.sourceChecksum, isNull);
    expect(propertySummary.candidateChecksum, isNull);
    expect(propertySummary.reconciliationChecksum, isNull);
    expect(report.issues.map((issue) => issue.code), contains('run.aborted'));
  });
}

ReferenceMigrationSourceSnapshot _validSnapshot() {
  return ReferenceMigrationSourceSnapshot(
    workspaces: <Map<String, Object?>>[_workspace()],
    properties: <Map<String, Object?>>[
      _property(id: 'property-active'),
      _property(id: 'property-archived', archived: 1),
    ],
  );
}

Map<String, Object?> _workspace({String id = 'ws_default'}) {
  return <String, Object?>{
    'id': id,
    'name': 'Default Workspace',
    'docs_root_path': 'workspace/docs',
    'created_at': 1000,
  };
}

Map<String, Object?> _property({required String id, int archived = 0}) {
  return <String, Object?>{
    'id': id,
    'name': 'Musterobjekt',
    'address_line1': 'Musterstrasse 1',
    'address_line2': null,
    'zip': '10115',
    'city': 'Berlin',
    'country': 'DE',
    'property_type': 'mixed_use',
    'units': 4,
    'sqft': 420.5,
    'year_built': 1998,
    'notes': 'Sensitive note',
    'created_at': 2000,
    'updated_at': 3000,
    'archived': archived,
  };
}

class _AbortAfterChecks implements ReferenceMigrationAbortSignal {
  _AbortAfterChecks(this.allowedChecks);

  final int allowedChecks;
  int _checks = 0;

  @override
  bool get isAborted => _checks++ >= allowedChecks;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
