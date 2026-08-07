import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_migration_dry_run.dart';
import 'package:neximmo_app/features/platform_audit_jobs/data/sqlite_to_postgres_platform_audit_jobs_dry_run_mapper.dart';
import 'package:uuid/uuid.dart';

const _mapper = SqliteToPostgresPlatformAuditJobsDryRunMapper();

const _workspaceId = 'a1a1a1a1-1111-4111-8111-111111111111';
const _actorId = 'b2b2b2b2-2222-4222-9222-222222222222';
const _recipientId = 'c3c3c3c3-3333-4333-a333-333333333333';
const _propertyId = 'd4d4d4d4-4444-4444-8444-444444444444';
const _leaseId = 'e5e5e5e5-5555-4555-9555-555555555555';

PlatformMigrationDryRunRequest _request() {
  return const PlatformMigrationDryRunRequest(
    sourceWorkspaceId: 'legacy',
    targetWorkspaceId: _workspaceId,
    targetWorkspaceKey: 'target-workspace',
    migrationActorId: _actorId,
    notificationRecipientUserId: _recipientId,
  );
}

String _iso(int epochMillis) =>
    DateTime.fromMillisecondsSinceEpoch(epochMillis, isUtc: true)
        .toIso8601String();

String _targetId(String namespace, String sourceId) =>
    const Uuid().v5(_workspaceId, 'neximmo/p2-d04/$namespace/$sourceId');

Map<String, Object?> _task({
  String id = 'task-1',
  Object? status = 'todo',
  Object? priority = 'normal',
  Object? entityType = 'property',
  Object? entityId = _propertyId,
  Object? title = 'Repair the roof',
  Object? estimatedCost,
  Object? createdBy,
}) => <String, Object?>{
  'id': id,
  'entity_type': entityType,
  'entity_id': entityId,
  'title': title,
  'description': null,
  'category': null,
  'assigned_to': null,
  'estimated_cost': estimatedCost,
  'status': status,
  'priority': priority,
  'due_at': null,
  'created_at': 1000,
  'updated_at': 2000,
  'created_by': createdBy,
};

Map<String, Object?> _expectedTaskTarget({
  String id = 'task-1',
  String status = 'open',
  String priority = 'normal',
  Object? entityType = 'property',
  Object? entityId = _propertyId,
  String title = 'Repair the roof',
}) => <String, Object?>{
  'id': _targetId('task', id),
  'workspace_id': _workspaceId,
  'entity_type': entityType,
  'entity_id': entityId,
  'title': title,
  'description': null,
  'category': null,
  'assigned_to': null,
  'priority': priority,
  'status': status,
  'due_at': null,
  'generated_key': null,
  'archived_at': null,
  'created_at': _iso(1000),
  'updated_at': _iso(2000),
  'created_by': _actorId,
  'updated_by': _actorId,
  'version': 1,
};

Map<String, Object?> _notification({
  String id = 'note-1',
  Object? kind = 'lease.expiring',
  Object? message = 'Lease 12 expires soon',
  Object? dueAt,
  Object? readAt,
  Object? entityType = 'lease',
  Object? entityId = _leaseId,
}) => <String, Object?>{
  'id': id,
  'entity_type': entityType,
  'entity_id': entityId,
  'kind': kind,
  'message': message,
  'due_at': dueAt,
  'read_at': readAt,
  'created_at': 1000,
};

Map<String, Object?> _expectedNotificationTarget({
  String id = 'note-1',
  String kind = 'lease.expiring',
  String title = 'Lease 12 expires soon',
  Object? body,
  Object? entityType = 'lease',
  Object? entityId = _leaseId,
  Object? readAt,
}) => <String, Object?>{
  'id': _targetId('notification', id),
  'workspace_id': _workspaceId,
  'recipient_user_id': _recipientId,
  'kind': kind,
  'title': title,
  'body': body,
  'entity_type': entityType,
  'entity_id': entityId,
  'read_at': readAt,
  'created_at': _iso(1000),
  'updated_at': _iso(1000),
  'created_by': _actorId,
  'updated_by': _actorId,
  'version': 1,
};

Map<String, Object?> _importJob({
  String id = 'job-1',
  Object? kind = 'csv',
  Object? status = 'pending',
  Object? targetScope = 'properties',
  Object? finishedAt,
  Object? error,
}) => <String, Object?>{
  'id': id,
  'kind': kind,
  'status': status,
  'target_scope': targetScope,
  'created_at': 1000,
  'finished_at': finishedAt,
  'error': error,
};

Map<String, Object?> _expectedImportJobTarget({
  String id = 'job-1',
  String sourceKind = 'csv',
  String targetScope = 'properties',
  String status = 'draft',
  Map<String, Object?> mapping = const <String, Object?>{},
  Object? errorReport,
  Object? finishedAt,
}) => <String, Object?>{
  'id': _targetId('import_job', id),
  'workspace_id': _workspaceId,
  'source_kind': sourceKind,
  'target_scope': targetScope,
  'status': status,
  'mapping': mapping,
  'dry_run': null,
  'reconciliation': null,
  'error_report': errorReport,
  'started_at': null,
  'finished_at': finishedAt,
  'created_at': _iso(1000),
  'updated_at': _iso(1000),
  'created_by': _actorId,
  'updated_by': _actorId,
  'version': 1,
};

Map<String, Object?> _importMapping({
  String id = 'map-1',
  String importJobId = 'job-1',
  String targetTable = 'properties',
  Object? mappingJson = '{"name":"Name"}',
}) => <String, Object?>{
  'id': id,
  'import_job_id': importJobId,
  'target_table': targetTable,
  'mapping_json': mappingJson,
  'created_at': 1000,
};

PlatformMigrationSourceSnapshot _snapshot({
  List<Map<String, Object?>>? tasks,
  List<Map<String, Object?>>? notifications,
  List<Map<String, Object?>>? importJobs,
  List<Map<String, Object?>>? importMappings,
}) {
  return PlatformMigrationSourceSnapshot(
    tasks: tasks ?? <Map<String, Object?>>[_task()],
    notifications: notifications ?? <Map<String, Object?>>[_notification()],
    importJobs: importJobs ?? <Map<String, Object?>>[_importJob()],
    importMappings: importMappings ?? <Map<String, Object?>>[],
  );
}

class _AlwaysAbort implements PlatformMigrationAbortSignal {
  const _AlwaysAbort();
  @override
  bool get isAborted => true;
}

PlatformMigrationEntitySummary _summaryOf(
  PlatformMigrationDryRunReport report,
  PlatformMigrationEntity entity,
) => report.summaries.firstWhere((summary) => summary.entity == entity);

PlatformMigrationMapping _mappingOf(
  PlatformMigrationDryRunReport report,
  PlatformMigrationEntity entity,
  String sourceId,
) => report.mappings.firstWhere(
  (mapping) => mapping.entity == entity && mapping.sourceId == sourceId,
);

Iterable<PlatformMigrationIssue> _issues(
  PlatformMigrationDryRunReport report,
  String code,
) => report.issues.where((issue) => issue.code == code);

bool _hasIssue(PlatformMigrationDryRunReport report, String code) =>
    _issues(report, code).isNotEmpty;

void main() {
  group('SqliteToPostgresPlatformAuditJobsDryRunMapper', () {
    test('maps a clean snapshot to a reconciled, import-ready report', () {
      final report = _mapper.map(snapshot: _snapshot(), request: _request());

      expect(report.status, PlatformMigrationStatus.ready);
      expect(report.productionImportReady, isTrue);
      expect(report.manifestChecksum, isNotEmpty);
      expect(report.summaries.length, 3);
      for (final summary in report.summaries) {
        expect(summary.countsReconcile, isTrue, reason: summary.entity.name);
        expect(summary.checksumsReconcile, isTrue, reason: summary.entity.name);
        expect(summary.sourceRows, 1, reason: summary.entity.name);
        expect(summary.mappedRows, 1, reason: summary.entity.name);
        expect(summary.rejectedRows, 0, reason: summary.entity.name);
        expect(summary.errorCount, 0, reason: summary.entity.name);
      }
      // Target ids are deterministic UUIDv5 values.
      expect(
        _mappingOf(report, PlatformMigrationEntity.task, 'task-1').targetId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('is deterministic across two runs over the same snapshot', () {
      final first = _mapper.map(snapshot: _snapshot(), request: _request());
      final second = _mapper.map(snapshot: _snapshot(), request: _request());

      expect(first.manifestChecksum, second.manifestChecksum);
      expect(first.toCanonicalJson(), second.toCanonicalJson());
    });

    test('does not mutate the source snapshot', () {
      final snapshot = _snapshot();
      final before = <String, Object?>{...snapshot.tasks.first};

      _mapper.map(snapshot: snapshot, request: _request());

      expect(snapshot.tasks.first, before);
      expect(snapshot.tasks.length, 1);
    });

    // -------------------------------------------------------------------------
    // tasks
    // -------------------------------------------------------------------------

    test('renames the legacy task status `todo` to the canonical `open`', () {
      final report = _mapper.map(snapshot: _snapshot(), request: _request());

      final renames = _issues(report, 'mapping.task_status_todo_renamed');
      expect(renames.length, 1);
      expect(renames.first.entity, PlatformMigrationEntity.task);
      expect(renames.first.sourceId, 'task-1');
      expect(renames.first.field, 'status');
      expect(renames.first.severity, PlatformMigrationIssueSeverity.warning);

      // The emitted candidate row carries `open`, not `todo`.
      expect(
        _mappingOf(report, PlatformMigrationEntity.task, 'task-1')
            .targetChecksum,
        platformMigrationChecksum(_expectedTaskTarget()),
      );
      expect(report.status, PlatformMigrationStatus.ready);
    });

    test('passes `in_progress` and `done` through without a rename', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          tasks: <Map<String, Object?>>[
            _task(id: 'task-a', status: 'in_progress'),
            _task(id: 'task-b', status: 'done'),
          ],
        ),
        request: _request(),
      );

      expect(_hasIssue(report, 'mapping.task_status_todo_renamed'), isFalse);
      expect(
        _mappingOf(report, PlatformMigrationEntity.task, 'task-a')
            .targetChecksum,
        platformMigrationChecksum(
          _expectedTaskTarget(id: 'task-a', status: 'in_progress'),
        ),
      );
      // `done` is not `archived`: archived_at stays null.
      expect(
        _mappingOf(report, PlatformMigrationEntity.task, 'task-b')
            .targetChecksum,
        platformMigrationChecksum(
          _expectedTaskTarget(id: 'task-b', status: 'done'),
        ),
      );
      expect(report.status, PlatformMigrationStatus.ready);
    });

    test('rejects a task with an unknown status', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          tasks: <Map<String, Object?>>[_task(status: 'archived')],
        ),
        request: _request(),
      );

      expect(_hasIssue(report, 'source.unknown_task_status'), isTrue);
      final summary = _summaryOf(report, PlatformMigrationEntity.task);
      expect(summary.rejectedRows, 1);
      expect(summary.mappedRows, 0);
      expect(summary.countsReconcile, isTrue);
      expect(report.status, PlatformMigrationStatus.invalid);
      expect(report.productionImportReady, isFalse);
    });

    test('rejects a task with an unknown priority', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          tasks: <Map<String, Object?>>[_task(priority: 'urgent')],
        ),
        request: _request(),
      );

      expect(_hasIssue(report, 'source.unknown_task_priority'), isTrue);
      expect(_summaryOf(report, PlatformMigrationEntity.task).rejectedRows, 1);
      expect(report.status, PlatformMigrationStatus.invalid);
    });

    test('rejects a task whose title cannot satisfy the 1..300 bound', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          tasks: <Map<String, Object?>>[
            _task(id: 'task-blank', title: '   '),
            _task(id: 'task-long', title: 'x' * 301),
          ],
        ),
        request: _request(),
      );

      expect(_hasIssue(report, 'source.required_value_missing'), isTrue);
      expect(_hasIssue(report, 'source.text_too_long'), isTrue);
      expect(_summaryOf(report, PlatformMigrationEntity.task).rejectedRows, 2);
    });

    test('drops the entity link when the legacy entity id is null', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          tasks: <Map<String, Object?>>[_task(entityId: null)],
        ),
        request: _request(),
      );

      final dropped = _issues(report, 'mapping.entity_link_id_missing');
      expect(dropped.length, 1);
      expect(dropped.first.field, 'entity_id');
      expect(dropped.first.severity, PlatformMigrationIssueSeverity.warning);
      // Both halves go null together, as the server constraint demands.
      expect(
        _mappingOf(report, PlatformMigrationEntity.task, 'task-1')
            .targetChecksum,
        platformMigrationChecksum(
          _expectedTaskTarget(entityType: null, entityId: null),
        ),
      );
      expect(report.status, PlatformMigrationStatus.ready);
    });

    test('drops the entity link when the type is outside the registry', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          tasks: <Map<String, Object?>>[_task(entityType: 'legacy_widget')],
        ),
        request: _request(),
      );

      final dropped = _issues(report, 'mapping.entity_link_type_not_mapped');
      expect(dropped.length, 1);
      expect(dropped.first.field, 'entity_type');
      expect(
        _mappingOf(report, PlatformMigrationEntity.task, 'task-1')
            .targetChecksum,
        platformMigrationChecksum(
          _expectedTaskTarget(entityType: null, entityId: null),
        ),
      );
      expect(report.status, PlatformMigrationStatus.ready);
    });

    test('flags a dropped estimated_cost, which has no target column', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          tasks: <Map<String, Object?>>[_task(estimatedCost: 1250.5)],
        ),
        request: _request(),
      );

      final dropped = _issues(report, 'mapping.task_estimated_cost_dropped');
      expect(dropped.length, 1);
      expect(dropped.first.field, 'estimated_cost');
      expect(dropped.first.severity, PlatformMigrationIssueSeverity.warning);
      expect(report.status, PlatformMigrationStatus.ready);
      // The value is gone from the candidate row, not smuggled elsewhere.
      expect(
        _mappingOf(report, PlatformMigrationEntity.task, 'task-1')
            .targetChecksum,
        platformMigrationChecksum(_expectedTaskTarget()),
      );
    });

    test('replaces a non-null legacy created_by with the migration actor', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          tasks: <Map<String, Object?>>[_task(createdBy: 'max@example.test')],
        ),
        request: _request(),
      );

      final replaced = _issues(report, 'mapping.actor_replaced');
      expect(replaced.length, 1);
      expect(replaced.first.field, 'created_by');
      expect(
        _mappingOf(report, PlatformMigrationEntity.task, 'task-1')
            .targetChecksum,
        platformMigrationChecksum(_expectedTaskTarget()),
      );
    });

    // -------------------------------------------------------------------------
    // notifications
    // -------------------------------------------------------------------------

    test('synthesizes the notification recipient on every mapped row', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          notifications: <Map<String, Object?>>[
            _notification(id: 'note-1'),
            _notification(id: 'note-2'),
          ],
        ),
        request: _request(),
      );

      final synthesized = _issues(
        report,
        'mapping.notification_recipient_synthesized',
      ).toList();
      expect(synthesized.length, 2);
      expect(
        synthesized.map((issue) => issue.sourceId).toList(),
        <String>['note-1', 'note-2'],
      );
      for (final issue in synthesized) {
        expect(issue.field, 'recipient_user_id');
        expect(issue.severity, PlatformMigrationIssueSeverity.warning);
      }
      expect(
        _mappingOf(report, PlatformMigrationEntity.notification, 'note-1')
            .targetChecksum,
        platformMigrationChecksum(_expectedNotificationTarget()),
      );
      expect(report.status, PlatformMigrationStatus.ready);
    });

    test('keeps a message of at most 300 characters as the title alone', () {
      final message = 'x' * 300;
      final report = _mapper.map(
        snapshot: _snapshot(
          notifications: <Map<String, Object?>>[_notification(message: message)],
        ),
        request: _request(),
      );

      expect(_hasIssue(report, 'mapping.notification_message_split'), isFalse);
      expect(
        _mappingOf(report, PlatformMigrationEntity.notification, 'note-1')
            .targetChecksum,
        platformMigrationChecksum(
          _expectedNotificationTarget(title: message),
        ),
      );
    });

    test('splits a longer message losslessly into title and body', () {
      final message = 'x' * 350;
      final report = _mapper.map(
        snapshot: _snapshot(
          notifications: <Map<String, Object?>>[_notification(message: message)],
        ),
        request: _request(),
      );

      final split = _issues(report, 'mapping.notification_message_split');
      expect(split.length, 1);
      expect(split.first.field, 'message');
      expect(
        _mappingOf(report, PlatformMigrationEntity.notification, 'note-1')
            .targetChecksum,
        platformMigrationChecksum(
          _expectedNotificationTarget(title: 'x' * 300, body: message),
        ),
      );
      expect(report.status, PlatformMigrationStatus.ready);
    });

    test('rejects a message longer than the target body limit', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          notifications: <Map<String, Object?>>[
            _notification(message: 'x' * 4001),
          ],
        ),
        request: _request(),
      );

      expect(
        _hasIssue(report, 'source.notification_message_too_long'),
        isTrue,
      );
      final summary = _summaryOf(report, PlatformMigrationEntity.notification);
      expect(summary.rejectedRows, 1);
      expect(summary.mappedRows, 0);
      expect(report.status, PlatformMigrationStatus.invalid);
    });

    test('normalizes a notification kind and warns about the change', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          notifications: <Map<String, Object?>>[
            _notification(kind: ' Lease.Expiring '),
          ],
        ),
        request: _request(),
      );

      final normalized = _issues(report, 'mapping.notification_kind_normalized');
      expect(normalized.length, 1);
      expect(normalized.first.field, 'kind');
      expect(
        _mappingOf(report, PlatformMigrationEntity.notification, 'note-1')
            .targetChecksum,
        platformMigrationChecksum(_expectedNotificationTarget()),
      );
      expect(report.status, PlatformMigrationStatus.ready);
    });

    test('rejects a kind that normalization cannot rescue', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          notifications: <Map<String, Object?>>[
            _notification(kind: 'lease expiring!'),
          ],
        ),
        request: _request(),
      );

      expect(_hasIssue(report, 'source.invalid_notification_kind'), isTrue);
      expect(
        _summaryOf(report, PlatformMigrationEntity.notification).rejectedRows,
        1,
      );
      expect(report.status, PlatformMigrationStatus.invalid);
    });

    test('flags a dropped notification due date without smuggling it', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          notifications: <Map<String, Object?>>[_notification(dueAt: 9000)],
        ),
        request: _request(),
      );

      final dropped = _issues(report, 'mapping.notification_due_at_dropped');
      expect(dropped.length, 1);
      expect(dropped.first.field, 'due_at');
      // The candidate row is byte-identical to one that never had a due date.
      expect(
        _mappingOf(report, PlatformMigrationEntity.notification, 'note-1')
            .targetChecksum,
        platformMigrationChecksum(_expectedNotificationTarget()),
      );
      expect(report.status, PlatformMigrationStatus.ready);
    });

    test('maps read_at straight through', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          notifications: <Map<String, Object?>>[_notification(readAt: 4000)],
        ),
        request: _request(),
      );

      expect(
        _mappingOf(report, PlatformMigrationEntity.notification, 'note-1')
            .targetChecksum,
        platformMigrationChecksum(
          _expectedNotificationTarget(readAt: _iso(4000)),
        ),
      );
    });

    // -------------------------------------------------------------------------
    // import jobs
    // -------------------------------------------------------------------------

    test('folds import_mappings rows into the job mapping object', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          importMappings: <Map<String, Object?>>[
            _importMapping(),
            _importMapping(
              id: 'map-2',
              targetTable: 'units',
              mappingJson: '{"unit_code":"Code"}',
            ),
          ],
        ),
        request: _request(),
      );

      expect(
        _mappingOf(report, PlatformMigrationEntity.importJob, 'job-1')
            .targetChecksum,
        platformMigrationChecksum(
          _expectedImportJobTarget(
            mapping: <String, Object?>{
              'properties': <String, Object?>{'name': 'Name'},
              'units': <String, Object?>{'unit_code': 'Code'},
            },
          ),
        ),
      );
      expect(report.status, PlatformMigrationStatus.ready);
      expect(report.productionImportReady, isTrue);
    });

    test('keeps unparsable mapping json as raw text with a warning', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          importMappings: <Map<String, Object?>>[
            _importMapping(mappingJson: 'not json at all'),
          ],
        ),
        request: _request(),
      );

      final unparsed = _issues(report, 'mapping.import_mapping_json_unparsed');
      expect(unparsed.length, 1);
      expect(unparsed.first.entity, PlatformMigrationEntity.importJob);
      expect(unparsed.first.sourceId, 'map-1');
      expect(unparsed.first.severity, PlatformMigrationIssueSeverity.warning);
      expect(
        _mappingOf(report, PlatformMigrationEntity.importJob, 'job-1')
            .targetChecksum,
        platformMigrationChecksum(
          _expectedImportJobTarget(
            mapping: <String, Object?>{'properties': 'not json at all'},
          ),
        ),
      );
      expect(report.status, PlatformMigrationStatus.ready);
    });

    test('reports an orphan import mapping row as an importJob error', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          importMappings: <Map<String, Object?>>[
            _importMapping(id: 'map-orphan', importJobId: 'job-missing'),
          ],
        ),
        request: _request(),
      );

      final orphans = _issues(report, 'import_job.orphan_mapping');
      expect(orphans.length, 1);
      expect(orphans.first.entity, PlatformMigrationEntity.importJob);
      expect(orphans.first.sourceId, 'map-orphan');
      expect(orphans.first.severity, PlatformMigrationIssueSeverity.error);

      final summary = _summaryOf(report, PlatformMigrationEntity.importJob);
      // The orphan counts against the entity but is not itself a mapping and
      // does not disturb the row counts.
      expect(summary.errorCount, 1);
      expect(summary.sourceRows, 1);
      expect(summary.mappedRows, 1);
      expect(summary.rejectedRows, 0);
      expect(summary.countsReconcile, isTrue);
      expect(
        report.mappings.any((mapping) => mapping.sourceId == 'map-orphan'),
        isFalse,
      );
      expect(report.status, PlatformMigrationStatus.invalid);
      expect(report.productionImportReady, isFalse);
    });

    test('maps the legacy pending status to draft', () {
      final report = _mapper.map(snapshot: _snapshot(), request: _request());

      expect(
        _mappingOf(report, PlatformMigrationEntity.importJob, 'job-1')
            .targetChecksum,
        platformMigrationChecksum(_expectedImportJobTarget()),
      );
    });

    test(
      'refuses to fabricate AGG-020 commit evidence for succeeded/running jobs',
      () {
        final report = _mapper.map(
          snapshot: _snapshot(
            importJobs: <Map<String, Object?>>[
              _importJob(id: 'job-run', status: 'running'),
              _importJob(
                id: 'job-ok',
                status: 'succeeded',
                finishedAt: 5000,
              ),
            ],
          ),
          request: _request(),
        );

        final refusals = _issues(
          report,
          'import_job.history_not_migratable',
        ).toList();
        expect(refusals.length, 2);
        for (final issue in refusals) {
          // A warning, not an error: no edit to the legacy database can produce
          // evidence for an import that ran before the evidence requirement
          // existed, so this is a permanent exclusion rather than a defect to
          // fix and re-run.
          expect(issue.severity, PlatformMigrationIssueSeverity.warning);
          expect(issue.entity, PlatformMigrationEntity.importJob);
          expect(issue.field, 'dry_run');
        }

        final summary = _summaryOf(report, PlatformMigrationEntity.importJob);
        expect(summary.mappedRows, 0);
        expect(summary.rejectedRows, 2);
        expect(summary.countsReconcile, isTrue);
        expect(report.mappings.any((m) => m.sourceId.startsWith('job-')), isFalse);
        // The point of the downgrade: unmigratable operational history must not
        // hold the task and notification migrations hostage.
        expect(report.status, PlatformMigrationStatus.ready);
        expect(report.productionImportReady, isTrue);
      },
    );

    test('maps a failed legacy job onto failed with its error report', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          importJobs: <Map<String, Object?>>[
            _importJob(status: 'failed', error: 'boom', finishedAt: 5000),
          ],
        ),
        request: _request(),
      );

      expect(
        _mappingOf(report, PlatformMigrationEntity.importJob, 'job-1')
            .targetChecksum,
        platformMigrationChecksum(
          _expectedImportJobTarget(
            status: 'failed',
            errorReport: <String, Object?>{'message': 'boom'},
            finishedAt: _iso(5000),
          ),
        ),
      );
      expect(report.status, PlatformMigrationStatus.ready);
      expect(report.productionImportReady, isTrue);
    });

    test('rejects a terminal job without a finish stamp', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          importJobs: <Map<String, Object?>>[
            _importJob(status: 'failed', error: 'boom'),
          ],
        ),
        request: _request(),
      );

      expect(_hasIssue(report, 'import_job.finish_stamp_unavailable'), isTrue);
      expect(
        _summaryOf(report, PlatformMigrationEntity.importJob).rejectedRows,
        1,
      );
      expect(report.status, PlatformMigrationStatus.invalid);
    });

    test('rejects a failed job that carries no error to report', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          importJobs: <Map<String, Object?>>[
            _importJob(status: 'failed', finishedAt: 5000),
          ],
        ),
        request: _request(),
      );

      expect(
        _hasIssue(report, 'import_job.failure_report_unavailable'),
        isTrue,
      );
      expect(
        _summaryOf(report, PlatformMigrationEntity.importJob).rejectedRows,
        1,
      );
    });

    test('treats a recorded error as the failure, whatever the status says', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          importJobs: <Map<String, Object?>>[
            _importJob(status: 'pending', error: 'boom', finishedAt: 5000),
          ],
        ),
        request: _request(),
      );

      expect(_hasIssue(report, 'mapping.import_job_status_from_error'), isTrue);
      expect(
        _mappingOf(report, PlatformMigrationEntity.importJob, 'job-1')
            .targetChecksum,
        platformMigrationChecksum(
          _expectedImportJobTarget(
            status: 'failed',
            errorReport: <String, Object?>{'message': 'boom'},
            finishedAt: _iso(5000),
          ),
        ),
      );
    });

    test('drops a finish stamp a non-terminal target status cannot carry', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          importJobs: <Map<String, Object?>>[_importJob(finishedAt: 5000)],
        ),
        request: _request(),
      );

      expect(
        _hasIssue(report, 'mapping.import_job_finished_at_dropped'),
        isTrue,
      );
      expect(
        _mappingOf(report, PlatformMigrationEntity.importJob, 'job-1')
            .targetChecksum,
        platformMigrationChecksum(_expectedImportJobTarget()),
      );
      expect(report.status, PlatformMigrationStatus.ready);
    });

    test('rejects an unknown legacy import job status', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          importJobs: <Map<String, Object?>>[_importJob(status: 'queued')],
        ),
        request: _request(),
      );

      expect(_hasIssue(report, 'source.unknown_import_job_status'), isTrue);
      final summary = _summaryOf(report, PlatformMigrationEntity.importJob);
      expect(summary.rejectedRows, 1);
      expect(summary.mappedRows, 0);
      expect(summary.countsReconcile, isTrue);
      expect(report.status, PlatformMigrationStatus.invalid);
    });

    test('normalizes the import source kind and warns about the change', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          importJobs: <Map<String, Object?>>[_importJob(kind: ' CSV ')],
        ),
        request: _request(),
      );

      expect(
        _hasIssue(report, 'mapping.import_job_source_kind_normalized'),
        isTrue,
      );
      expect(
        _mappingOf(report, PlatformMigrationEntity.importJob, 'job-1')
            .targetChecksum,
        platformMigrationChecksum(_expectedImportJobTarget()),
      );
      expect(report.status, PlatformMigrationStatus.ready);
    });

    test('rejects a source kind normalization cannot rescue', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          importJobs: <Map<String, Object?>>[_importJob(kind: 'c s v!')],
        ),
        request: _request(),
      );

      expect(_hasIssue(report, 'source.invalid_import_source_kind'), isTrue);
      expect(
        _summaryOf(report, PlatformMigrationEntity.importJob).rejectedRows,
        1,
      );
    });

    // -------------------------------------------------------------------------
    // run-level behaviour
    // -------------------------------------------------------------------------

    test('keeps counts and checksums reconciled around a rejected row', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          tasks: <Map<String, Object?>>[
            _task(id: 'task-ok'),
            _task(id: 'task-bad', status: 'archived'),
          ],
        ),
        request: _request(),
      );

      final summary = _summaryOf(report, PlatformMigrationEntity.task);
      expect(summary.sourceRows, 2);
      expect(summary.processedRows, 2);
      expect(summary.mappedRows, 1);
      expect(summary.rejectedRows, 1);
      expect(summary.countsReconcile, isTrue);
      expect(summary.checksumsReconcile, isTrue);
      expect(summary.errorCount, 1);
      expect(summary.sourceChecksum, isNotNull);
      expect(summary.candidateChecksum, isNotNull);
      expect(report.status, PlatformMigrationStatus.invalid);
      expect(report.productionImportReady, isFalse);
      // Even an invalid report is byte-stable.
      final second = _mapper.map(
        snapshot: _snapshot(
          tasks: <Map<String, Object?>>[
            _task(id: 'task-ok'),
            _task(id: 'task-bad', status: 'archived'),
          ],
        ),
        request: _request(),
      );
      expect(report.toCanonicalJson(), second.toCanonicalJson());
    });

    test('reports an aborted run without checksums', () {
      final report = _mapper.map(
        snapshot: _snapshot(),
        request: _request(),
        abortSignal: const _AlwaysAbort(),
      );

      expect(report.status, PlatformMigrationStatus.aborted);
      expect(_hasIssue(report, 'run.aborted'), isTrue);
      expect(report.mappings, isEmpty);
      expect(report.productionImportReady, isFalse);
      for (final summary in report.summaries) {
        expect(summary.processedRows, 0);
        expect(summary.checksumsReconcile, isFalse);
        expect(summary.sourceChecksum, isNull);
      }
    });

    test('rejects an invalid request without dereferencing rows', () {
      final report = _mapper.map(
        snapshot: _snapshot(),
        request: const PlatformMigrationDryRunRequest(
          sourceWorkspaceId: 'legacy',
          targetWorkspaceId: 'not-a-uuid',
          targetWorkspaceKey: 'target-workspace',
          migrationActorId: _actorId,
          notificationRecipientUserId: _recipientId,
        ),
      );

      expect(
        _hasIssue(report, 'request.invalid_target_workspace_id'),
        isTrue,
      );
      expect(report.status, PlatformMigrationStatus.invalid);
      for (final summary in report.summaries) {
        expect(summary.mappedRows, 0);
        expect(summary.rejectedRows, summary.sourceRows);
      }
    });

    test('rejects a request without a notification recipient uuid', () {
      final report = _mapper.map(
        snapshot: _snapshot(),
        request: const PlatformMigrationDryRunRequest(
          sourceWorkspaceId: 'legacy',
          targetWorkspaceId: _workspaceId,
          targetWorkspaceKey: 'target-workspace',
          migrationActorId: _actorId,
          notificationRecipientUserId: 'nobody',
        ),
      );

      expect(
        _hasIssue(report, 'request.invalid_notification_recipient_user_id'),
        isTrue,
      );
      expect(report.status, PlatformMigrationStatus.invalid);
    });
  });
}
