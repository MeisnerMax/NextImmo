import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../application/platform_migration_dry_run.dart';
import '../domain/platform_entity_type.dart';

/// Read-only, deterministic dry-run mapper (P2-D04 increment 4 step 7): legacy
/// `tasks` / `notifications` / `import_jobs` (+ `import_mappings`) rows project
/// onto the canonical P2-D04 tables with UUIDv5 target ids and SHA-256
/// reconciliation. It never mutates the source, performs no I/O and never reads
/// a clock — two runs over the same snapshot produce byte-identical canonical
/// JSON. A real import is only authorized once the produced report reconciles.
///
/// The derived `search_index` is deliberately not an entity here: DOM-010 makes
/// it a projection, rebuilt by reindexing the owning domains after they migrate.
class SqliteToPostgresPlatformAuditJobsDryRunMapper {
  const SqliteToPostgresPlatformAuditJobsDryRunMapper();

  PlatformMigrationDryRunReport map({
    required PlatformMigrationSourceSnapshot snapshot,
    required PlatformMigrationDryRunRequest request,
    PlatformMigrationAbortSignal abortSignal =
        const NeverAbortPlatformMigration(),
  }) {
    final issues = <PlatformMigrationIssue>[];
    final mappings = <PlatformMigrationMapping>[];
    final requestValid = _validateRequest(request, issues);
    var aborted = abortSignal.isAborted;

    final taskRows = _sortedRows(snapshot.tasks);
    final notificationRows = _sortedRows(snapshot.notifications);
    final importJobRows = _sortedRows(snapshot.importJobs);
    // Mapping rows collapse into their job's `mapping` object before any job is
    // mapped, so an orphan is visible as an importJob-attributed error rather
    // than silently dropped.
    final fold = _foldImportMappings(
      importJobRows,
      _sortedRows(snapshot.importMappings),
    );

    final specs = <_EntitySpec>[
      _EntitySpec(PlatformMigrationEntity.task, taskRows),
      _EntitySpec(PlatformMigrationEntity.notification, notificationRows),
      _EntitySpec(
        PlatformMigrationEntity.importJob,
        importJobRows,
        extraIssues: fold.issues,
      ),
    ];

    final summaries = <PlatformMigrationEntitySummary>[];
    for (final spec in specs) {
      final result = _processEntity(
        entity: spec.entity,
        rows: spec.rows,
        extraIssues: spec.extraIssues,
        bindingValid: requestValid,
        alreadyAborted: aborted,
        abortSignal: abortSignal,
        request: request,
        importMappings: fold.byJobId,
      );
      aborted = aborted || result.aborted;
      issues.addAll(result.issues);
      mappings.addAll(result.mappings);
      summaries.add(result.summary);
    }

    if (aborted) {
      issues.add(
        const PlatformMigrationIssue(
          code: 'run.aborted',
          severity: PlatformMigrationIssueSeverity.warning,
        ),
      );
    }

    mappings.sort(_compareMappings);
    issues.sort(_compareIssues);

    final hasErrors = issues.any(
      (issue) => issue.severity == PlatformMigrationIssueSeverity.error,
    );
    final status = aborted
        ? PlatformMigrationStatus.aborted
        : hasErrors ||
              summaries.any(
                (summary) =>
                    !summary.countsReconcile || !summary.checksumsReconcile,
              )
        ? PlatformMigrationStatus.invalid
        : PlatformMigrationStatus.ready;

    final unsigned = PlatformMigrationDryRunReport(
      status: status,
      request: request,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: '',
    );
    return unsigned.withManifestChecksum(
      platformMigrationChecksum(
        unsigned.toCanonicalMap(includeManifestChecksum: false),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // import_mappings fold
  // ---------------------------------------------------------------------------

  _ImportMappingFold _foldImportMappings(
    List<Map<String, Object?>> jobRows,
    List<Map<String, Object?>> mappingRows,
  ) {
    const entity = PlatformMigrationEntity.importJob;
    final issues = <PlatformMigrationIssue>[];
    final byJobId = <String, Map<String, Object?>>{};
    final knownJobIds = <String>{
      for (final row in jobRows)
        if (row['id'] case final String id when id.isNotEmpty) id,
    };

    for (final row in mappingRows) {
      final rowId = row['id'];
      final sourceId = rowId is String && rowId.isNotEmpty ? rowId : null;
      if (sourceId == null) {
        issues.add(_fieldError('source.invalid_id', entity, null, 'id'));
        continue;
      }
      _flagUnmappedColumns(row, entity, sourceId, issues, _importMappingColumns);

      final jobId = row['import_job_id'];
      if (jobId is! String || !knownJobIds.contains(jobId)) {
        // A mapping without a job is a fact with nowhere to land: it cannot be
        // folded, and inventing a job for it would fabricate an import.
        issues.add(
          _fieldError(
            'import_job.orphan_mapping',
            entity,
            sourceId,
            'import_job_id',
          ),
        );
        continue;
      }

      final targetTable = row['target_table'];
      if (targetTable is! String || targetTable.trim().isEmpty) {
        issues.add(
          _fieldError(
            'import_job.mapping_target_table_missing',
            entity,
            sourceId,
            'target_table',
          ),
        );
        continue;
      }
      final key = targetTable.trim();

      final rawJson = row['mapping_json'];
      Object? decoded;
      if (rawJson is! String) {
        issues.add(
          _fieldError(
            'source.invalid_text',
            entity,
            sourceId,
            'mapping_json',
          ),
        );
        continue;
      }
      try {
        decoded = jsonDecode(rawJson);
      } on FormatException {
        // Keep the raw text rather than dropping the mapping: the operator can
        // still see exactly what the legacy row held.
        decoded = rawJson;
        issues.add(
          _fieldWarning(
            'mapping.import_mapping_json_unparsed',
            entity,
            sourceId,
            'mapping_json',
          ),
        );
      }

      final folded = byJobId.putIfAbsent(jobId, () => <String, Object?>{});
      if (folded.containsKey(key)) {
        issues.add(
          _fieldWarning(
            'mapping.import_mapping_target_collapsed',
            entity,
            sourceId,
            'target_table',
          ),
        );
      }
      folded[key] = decoded;
    }

    return _ImportMappingFold(byJobId: byJobId, issues: issues);
  }

  // ---------------------------------------------------------------------------
  // per-entity processing
  // ---------------------------------------------------------------------------

  _EntityResult _processEntity({
    required PlatformMigrationEntity entity,
    required List<Map<String, Object?>> rows,
    required List<PlatformMigrationIssue> extraIssues,
    required bool bindingValid,
    required bool alreadyAborted,
    required PlatformMigrationAbortSignal abortSignal,
    required PlatformMigrationDryRunRequest request,
    required Map<String, Map<String, Object?>> importMappings,
  }) {
    final issues = <PlatformMigrationIssue>[];
    final mappings = <PlatformMigrationMapping>[];
    final targets = <Map<String, Object?>>[];
    final sourceProjections = <Map<String, Object?>>[];
    final targetProjections = <Map<String, Object?>>[];
    var processed = 0;
    var mapped = 0;
    var rejected = 0;
    var aborted = alreadyAborted;

    if (!aborted) {
      for (final row in rows) {
        if (abortSignal.isAborted) {
          aborted = true;
          break;
        }
        processed++;
        if (!bindingValid) {
          rejected++;
          continue;
        }
        final result = _mapRow(entity, row, request, importMappings);
        issues.addAll(result.issues);
        if (result.hasErrors || result.target == null) {
          rejected++;
          continue;
        }
        mapped++;
        targets.add(result.target!);
        sourceProjections.add(result.sourceProjection!);
        targetProjections.add(result.targetProjection!);
        mappings.add(
          PlatformMigrationMapping(
            entity: entity,
            sourceId: result.sourceId!,
            targetId: result.targetId!,
            sourceChecksum: platformMigrationChecksum(row),
            targetChecksum: platformMigrationChecksum(result.target),
          ),
        );
      }
    }

    if (!aborted) {
      issues.addAll(extraIssues);
    }

    return _EntityResult(
      aborted: aborted,
      issues: issues,
      mappings: mappings,
      summary: _summary(
        entity: entity,
        sourceRowsData: rows,
        processedRows: processed,
        mappedRows: mapped,
        rejectedRows: rejected,
        targets: targets,
        sourceProjections: sourceProjections,
        targetProjections: targetProjections,
        entityIssues: issues,
        aborted: aborted,
      ),
    );
  }

  _MappedRow _mapRow(
    PlatformMigrationEntity entity,
    Map<String, Object?> row,
    PlatformMigrationDryRunRequest request,
    Map<String, Map<String, Object?>> importMappings,
  ) {
    switch (entity) {
      case PlatformMigrationEntity.task:
        return _mapTask(row, request);
      case PlatformMigrationEntity.notification:
        return _mapNotification(row, request);
      case PlatformMigrationEntity.importJob:
        return _mapImportJob(row, request, importMappings);
    }
  }

  // ---------------------------------------------------------------------------
  // tasks
  // ---------------------------------------------------------------------------

  _MappedRow _mapTask(
    Map<String, Object?> row,
    PlatformMigrationDryRunRequest request,
  ) {
    const entity = PlatformMigrationEntity.task;
    final issues = <PlatformMigrationIssue>[];
    final sourceId = _validatedSourceId(row, entity, issues);
    _flagUnmappedColumns(row, entity, sourceId, issues, _taskColumns);

    final title = _requiredText(
      row,
      key: 'title',
      maxLength: 300,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final description = _optionalUntrimmedText(
      row,
      key: 'description',
      maxLength: 10000,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final category = _optionalText(
      row,
      key: 'category',
      maxLength: 100,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );

    // The target column is a uuid referencing a workspace member; the legacy
    // column is free text. Anything that is not already a uuid cannot be
    // carried without inventing an identity, so it degrades to unassigned.
    String? assignedTo;
    final rawAssignee = row['assigned_to'];
    if (rawAssignee != null) {
      final candidate = rawAssignee is String ? rawAssignee.trim() : '';
      if (candidate.isNotEmpty && Uuid.isValidUUID(fromString: candidate)) {
        assignedTo = candidate;
      } else {
        issues.add(
          _fieldWarning(
            'mapping.task_assignee_dropped',
            entity,
            sourceId,
            'assigned_to',
          ),
        );
      }
    }

    // The headline rename of this work item: legacy `todo` is canonical `open`.
    String? status;
    final rawStatus = row['status'];
    switch (rawStatus) {
      case 'todo':
        status = 'open';
        issues.add(
          _fieldWarning(
            'mapping.task_status_todo_renamed',
            entity,
            sourceId,
            'status',
          ),
        );
      case 'in_progress':
        status = 'in_progress';
      case 'done':
        status = 'done';
      default:
        issues.add(
          _fieldError('source.unknown_task_status', entity, sourceId, 'status'),
        );
    }

    // The priority vocabulary is identical on both sides.
    String? priority;
    final rawPriority = row['priority'];
    if (rawPriority is String && _taskPriorities.contains(rawPriority)) {
      priority = rawPriority;
    } else {
      issues.add(
        _fieldError(
          'source.unknown_task_priority',
          entity,
          sourceId,
          'priority',
        ),
      );
    }

    final (linkType, linkId) = _entityLink(row, entity, sourceId, issues);
    final dueAt = _optionalTimestamp(
      row,
      key: 'due_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final createdAt = _requiredTimestamp(
      row,
      key: 'created_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final updatedAt = _requiredTimestamp(
      row,
      key: 'updated_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );

    // No target column exists for the legacy cost estimate.
    if (row['estimated_cost'] != null) {
      issues.add(
        _fieldWarning(
          'mapping.task_estimated_cost_dropped',
          entity,
          sourceId,
          'estimated_cost',
        ),
      );
    }
    // The legacy actor is nullable free text; both target actor columns are
    // NOT NULL uuids, so the migration actor owns every migrated row.
    if (row['created_by'] != null) {
      issues.add(
        _fieldWarning('mapping.actor_replaced', entity, sourceId, 'created_by'),
      );
    }

    if (_hasErrors(issues) ||
        sourceId == null ||
        title == null ||
        status == null ||
        priority == null ||
        createdAt == null ||
        updatedAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }

    final targetId = _targetId(request, entity, sourceId);
    issues.add(
      _fieldWarning('mapping.id_derived_uuid_v5', entity, sourceId, 'id'),
    );

    final target = <String, Object?>{
      'id': targetId,
      'workspace_id': request.targetWorkspaceId,
      'entity_type': linkType,
      'entity_id': linkId,
      'title': title,
      'description': description,
      'category': category,
      'assigned_to': assignedTo,
      'priority': priority,
      'status': status,
      'due_at': dueAt,
      // `task_generated_instances` is a separate legacy table, out of scope for
      // this increment: nothing migrated here is a recurring generation.
      'generated_key': null,
      // Nothing in the legacy store is archived — `done` is not `archived`.
      'archived_at': null,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'created_by': request.migrationActorId,
      'updated_by': request.migrationActorId,
      'version': 1,
    };

    return _MappedRow(
      sourceId: sourceId,
      targetId: targetId,
      target: target,
      sourceProjection: <String, Object?>{
        'source_id': sourceId,
        'title': title,
        'description': description,
        'category': category,
        'status': status,
        'priority': priority,
        'assigned_to': assignedTo,
        'entity_type': linkType,
        'entity_id': linkId,
        'due_at': dueAt,
      },
      targetProjection: <String, Object?>{
        'source_id': sourceId,
        'title': target['title'],
        'description': target['description'],
        'category': target['category'],
        'status': target['status'],
        'priority': target['priority'],
        'assigned_to': target['assigned_to'],
        'entity_type': target['entity_type'],
        'entity_id': target['entity_id'],
        'due_at': target['due_at'],
      },
      issues: issues,
    );
  }

  // ---------------------------------------------------------------------------
  // notifications
  // ---------------------------------------------------------------------------

  _MappedRow _mapNotification(
    Map<String, Object?> row,
    PlatformMigrationDryRunRequest request,
  ) {
    const entity = PlatformMigrationEntity.notification;
    final issues = <PlatformMigrationIssue>[];
    final sourceId = _validatedSourceId(row, entity, issues);
    _flagUnmappedColumns(row, entity, sourceId, issues, _notificationColumns);

    String? kind;
    final rawKind = row['kind'];
    if (rawKind is! String || rawKind.trim().isEmpty) {
      issues.add(
        _fieldError('source.required_value_missing', entity, sourceId, 'kind'),
      );
    } else {
      final normalized = rawKind.trim().toLowerCase();
      if (normalized != rawKind) {
        issues.add(
          _fieldWarning(
            'mapping.notification_kind_normalized',
            entity,
            sourceId,
            'kind',
          ),
        );
      }
      if (!_normalizedKey.hasMatch(normalized) ||
          normalized.length < 2 ||
          normalized.length > 100) {
        issues.add(
          _fieldError(
            'source.invalid_notification_kind',
            entity,
            sourceId,
            'kind',
          ),
        );
      } else {
        kind = normalized;
      }
    }

    // The legacy message is one free-text blob; the target splits it into a
    // bounded title and an optional body. The split is lossless: the body keeps
    // the whole message, the title is its first 300 characters.
    String? title;
    String? body;
    final rawMessage = row['message'];
    if (rawMessage is! String || rawMessage.trim().isEmpty) {
      issues.add(
        _fieldError(
          'source.required_value_missing',
          entity,
          sourceId,
          'message',
        ),
      );
    } else {
      final normalized = rawMessage.trim();
      if (normalized != rawMessage) {
        issues.add(
          _fieldWarning('mapping.text_trimmed', entity, sourceId, 'message'),
        );
      }
      if (normalized.length > _notificationBodyMaxLength) {
        issues.add(
          _fieldError(
            'source.notification_message_too_long',
            entity,
            sourceId,
            'message',
          ),
        );
      } else if (normalized.length > _notificationTitleMaxLength) {
        title = normalized.substring(0, _notificationTitleMaxLength);
        body = normalized;
        issues.add(
          _fieldWarning(
            'mapping.notification_message_split',
            entity,
            sourceId,
            'message',
          ),
        );
      } else {
        title = normalized;
      }
    }

    final (linkType, linkId) = _entityLink(row, entity, sourceId, issues);
    final readAt = _optionalTimestamp(
      row,
      key: 'read_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final createdAt = _requiredTimestamp(
      row,
      key: 'created_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );

    // No target column exists for a notification due date, and smuggling it
    // into the body would corrupt the message.
    if (row['due_at'] != null) {
      issues.add(
        _fieldWarning(
          'mapping.notification_due_at_dropped',
          entity,
          sourceId,
          'due_at',
        ),
      );
    }

    if (_hasErrors(issues) ||
        sourceId == null ||
        kind == null ||
        title == null ||
        createdAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }

    final targetId = _targetId(request, entity, sourceId);
    issues.add(
      _fieldWarning('mapping.id_derived_uuid_v5', entity, sourceId, 'id'),
    );
    // The legacy table has no recipient at all: the local app is single-user.
    // The recipient is therefore supplied by whoever runs the migration and
    // recorded as synthesized on every single mapped row.
    issues.add(
      _fieldWarning(
        'mapping.notification_recipient_synthesized',
        entity,
        sourceId,
        'recipient_user_id',
      ),
    );
    // The legacy table has no `updated_at`; the target column is NOT NULL.
    issues.add(
      _fieldWarning(
        'mapping.notification_updated_at_from_created_at',
        entity,
        sourceId,
        'updated_at',
      ),
    );

    final target = <String, Object?>{
      'id': targetId,
      'workspace_id': request.targetWorkspaceId,
      'recipient_user_id': request.notificationRecipientUserId,
      'kind': kind,
      'title': title,
      'body': body,
      'entity_type': linkType,
      'entity_id': linkId,
      'read_at': readAt,
      'created_at': createdAt,
      'updated_at': createdAt,
      'created_by': request.migrationActorId,
      'updated_by': request.migrationActorId,
      'version': 1,
    };

    return _MappedRow(
      sourceId: sourceId,
      targetId: targetId,
      target: target,
      sourceProjection: <String, Object?>{
        'source_id': sourceId,
        'kind': kind,
        'title': title,
        'body': body,
        'entity_type': linkType,
        'entity_id': linkId,
        'read_at': readAt,
        'recipient_user_id': request.notificationRecipientUserId,
      },
      targetProjection: <String, Object?>{
        'source_id': sourceId,
        'kind': target['kind'],
        'title': target['title'],
        'body': target['body'],
        'entity_type': target['entity_type'],
        'entity_id': target['entity_id'],
        'read_at': target['read_at'],
        'recipient_user_id': target['recipient_user_id'],
      },
      issues: issues,
    );
  }

  // ---------------------------------------------------------------------------
  // import jobs
  // ---------------------------------------------------------------------------

  _MappedRow _mapImportJob(
    Map<String, Object?> row,
    PlatformMigrationDryRunRequest request,
    Map<String, Map<String, Object?>> importMappings,
  ) {
    const entity = PlatformMigrationEntity.importJob;
    final issues = <PlatformMigrationIssue>[];
    final sourceId = _validatedSourceId(row, entity, issues);
    _flagUnmappedColumns(row, entity, sourceId, issues, _importJobColumns);

    String? sourceKind;
    final rawKind = row['kind'];
    if (rawKind is! String || rawKind.trim().isEmpty) {
      issues.add(
        _fieldError('source.required_value_missing', entity, sourceId, 'kind'),
      );
    } else {
      final normalized = rawKind.trim().toLowerCase();
      if (normalized != rawKind) {
        issues.add(
          _fieldWarning(
            'mapping.import_job_source_kind_normalized',
            entity,
            sourceId,
            'kind',
          ),
        );
      }
      if (!_normalizedKey.hasMatch(normalized) ||
          normalized.length < 2 ||
          normalized.length > 100) {
        issues.add(
          _fieldError(
            'source.invalid_import_source_kind',
            entity,
            sourceId,
            'kind',
          ),
        );
      } else {
        sourceKind = normalized;
      }
    }

    final targetScope = _requiredText(
      row,
      key: 'target_scope',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );

    // `error` is the only failure evidence the legacy store carries.
    String? errorMessage;
    final rawError = row['error'];
    if (rawError != null) {
      if (rawError is! String) {
        issues.add(
          _fieldError('source.invalid_text', entity, sourceId, 'error'),
        );
      } else if (rawError.trim().isEmpty) {
        issues.add(
          _fieldWarning('mapping.empty_text_to_null', entity, sourceId, 'error'),
        );
      } else {
        errorMessage = rawError;
      }
    }

    var status = _legacyImportJobStatuses[row['status']];
    if (status == null) {
      issues.add(
        _fieldError(
          'source.unknown_import_job_status',
          entity,
          sourceId,
          'status',
        ),
      );
    } else if (errorMessage != null && status != 'failed') {
      // A recorded error is a failure whatever the legacy status column says.
      issues.add(
        _fieldWarning(
          'mapping.import_job_status_from_error',
          entity,
          sourceId,
          'status',
        ),
      );
      status = 'failed';
    }

    // AGG-020 is a schema invariant: nothing may sit in `ready`/`running`/
    // `completed` without BOTH a dry-run manifest and a reconciliation. The
    // legacy table has neither column and never had, so the evidence cannot be
    // produced — and fabricating it would defeat the invariant it encodes.
    // Such a row is refused, not downgraded and not decorated with a fake
    // manifest.
    //
    // The refusal is a WARNING, not an ERROR, and the distinction is load
    // bearing. An error in this report means "the source is wrong, fix it and
    // re-run". This can never be fixed: no edit to the legacy database can
    // produce evidence for an import that ran years before the evidence
    // requirement existed. Recording it as an error would leave
    // `productionImportReady` permanently false and would block the task and
    // notification migrations — which have nothing to do with it — on a
    // condition nobody can clear. The row is still rejected (it returns without
    // a target), so the counts reconcile and the report states exactly how much
    // operational history is being left behind.
    if (status != null && _importJobCommitEvidenceStatuses.contains(status)) {
      issues.add(
        _fieldWarning(
          'import_job.history_not_migratable',
          entity,
          sourceId,
          'dry_run',
        ),
      );
      return _MappedRow(sourceId: sourceId, issues: issues);
    }
    if (status == 'failed' && errorMessage == null) {
      issues.add(
        _fieldError(
          'import_job.failure_report_unavailable',
          entity,
          sourceId,
          'error_report',
        ),
      );
    }

    var finishedAt = _optionalTimestamp(
      row,
      key: 'finished_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final terminal =
        status != null && _importJobTerminalStatuses.contains(status);
    if (terminal && finishedAt == null) {
      // A terminal row must carry a finish stamp and the mapper never invents
      // a timestamp.
      issues.add(
        _fieldError(
          'import_job.finish_stamp_unavailable',
          entity,
          sourceId,
          'finished_at',
        ),
      );
    }
    if (!terminal && finishedAt != null) {
      issues.add(
        _fieldWarning(
          'mapping.import_job_finished_at_dropped',
          entity,
          sourceId,
          'finished_at',
        ),
      );
      finishedAt = null;
    }

    final createdAt = _requiredTimestamp(
      row,
      key: 'created_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );

    if (_hasErrors(issues) ||
        sourceId == null ||
        sourceKind == null ||
        targetScope == null ||
        status == null ||
        createdAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }

    final targetId = _targetId(request, entity, sourceId);
    issues.add(
      _fieldWarning('mapping.id_derived_uuid_v5', entity, sourceId, 'id'),
    );
    // The legacy table has no `updated_at`; the target column is NOT NULL.
    issues.add(
      _fieldWarning(
        'mapping.import_job_updated_at_from_created_at',
        entity,
        sourceId,
        'updated_at',
      ),
    );

    final mapping = Map<String, Object?>.from(
      importMappings[sourceId] ?? const <String, Object?>{},
    );
    final errorReport = errorMessage == null
        ? null
        : <String, Object?>{'message': errorMessage};

    final target = <String, Object?>{
      'id': targetId,
      'workspace_id': request.targetWorkspaceId,
      'source_kind': sourceKind,
      'target_scope': targetScope,
      'status': status,
      'mapping': mapping,
      'dry_run': null,
      'reconciliation': null,
      'error_report': errorReport,
      'started_at': null,
      'finished_at': finishedAt,
      'created_at': createdAt,
      'updated_at': createdAt,
      'created_by': request.migrationActorId,
      'updated_by': request.migrationActorId,
      'version': 1,
    };

    return _MappedRow(
      sourceId: sourceId,
      targetId: targetId,
      target: target,
      sourceProjection: <String, Object?>{
        'source_id': sourceId,
        'source_kind': sourceKind,
        'target_scope': targetScope,
        'status': status,
        'mapping': mapping,
        'error_report': errorReport,
        'finished_at': finishedAt,
      },
      targetProjection: <String, Object?>{
        'source_id': sourceId,
        'source_kind': target['source_kind'],
        'target_scope': target['target_scope'],
        'status': target['status'],
        'mapping': target['mapping'],
        'error_report': target['error_report'],
        'finished_at': target['finished_at'],
      },
      issues: issues,
    );
  }

  // ---------------------------------------------------------------------------
  // summaries and validation
  // ---------------------------------------------------------------------------

  PlatformMigrationEntitySummary _summary({
    required PlatformMigrationEntity entity,
    required List<Map<String, Object?>> sourceRowsData,
    required int processedRows,
    required int mappedRows,
    required int rejectedRows,
    required List<Map<String, Object?>> targets,
    required List<Map<String, Object?>> sourceProjections,
    required List<Map<String, Object?>> targetProjections,
    required List<PlatformMigrationIssue> entityIssues,
    required bool aborted,
  }) {
    final sourceRows = sourceRowsData.length;
    final errorCount = entityIssues
        .where(
          (issue) => issue.severity == PlatformMigrationIssueSeverity.error,
        )
        .length;
    final warningCount = entityIssues
        .where(
          (issue) => issue.severity == PlatformMigrationIssueSeverity.warning,
        )
        .length;
    if (aborted) {
      return PlatformMigrationEntitySummary(
        entity: entity,
        sourceRows: sourceRows,
        processedRows: processedRows,
        mappedRows: mappedRows,
        rejectedRows: rejectedRows,
        errorCount: errorCount,
        warningCount: warningCount,
        sourceChecksum: null,
        candidateChecksum: null,
        reconciliationChecksum: null,
        checksumsReconcile: false,
      );
    }
    final sourceReconciliation = platformMigrationChecksum(
      _sortProjectionRows(sourceProjections),
    );
    final targetReconciliation = platformMigrationChecksum(
      _sortProjectionRows(targetProjections),
    );
    return PlatformMigrationEntitySummary(
      entity: entity,
      sourceRows: sourceRows,
      processedRows: processedRows,
      mappedRows: mappedRows,
      rejectedRows: rejectedRows,
      errorCount: errorCount,
      warningCount: warningCount,
      sourceChecksum: platformMigrationChecksum(sourceRowsData),
      candidateChecksum: platformMigrationChecksum(_sortProjectionRows(targets)),
      reconciliationChecksum: sourceReconciliation,
      checksumsReconcile: sourceReconciliation == targetReconciliation,
    );
  }

  bool _validateRequest(
    PlatformMigrationDryRunRequest request,
    List<PlatformMigrationIssue> issues,
  ) {
    var valid = true;
    if (request.sourceWorkspaceId.isEmpty ||
        request.sourceWorkspaceId.trim() != request.sourceWorkspaceId) {
      issues.add(
        const PlatformMigrationIssue(
          code: 'request.invalid_source_workspace_id',
          severity: PlatformMigrationIssueSeverity.error,
        ),
      );
      valid = false;
    }
    for (final entry in <MapEntry<String, String>>[
      MapEntry('request.invalid_target_workspace_id', request.targetWorkspaceId),
      MapEntry('request.invalid_migration_actor_id', request.migrationActorId),
      MapEntry(
        'request.invalid_notification_recipient_user_id',
        request.notificationRecipientUserId,
      ),
    ]) {
      if (!Uuid.isValidUUID(fromString: entry.value)) {
        issues.add(
          PlatformMigrationIssue(
            code: entry.key,
            severity: PlatformMigrationIssueSeverity.error,
          ),
        );
        valid = false;
      }
    }
    if (!_normalizedKey.hasMatch(request.targetWorkspaceKey)) {
      issues.add(
        const PlatformMigrationIssue(
          code: 'request.invalid_target_workspace_key',
          severity: PlatformMigrationIssueSeverity.error,
        ),
      );
      valid = false;
    }
    return valid;
  }

  // ---------------------------------------------------------------------------
  // field helpers
  // ---------------------------------------------------------------------------

  String _targetId(
    PlatformMigrationDryRunRequest request,
    PlatformMigrationEntity entity,
    String sourceId,
  ) {
    return const Uuid().v5(
      request.targetWorkspaceId,
      'neximmo/p2-d04/${_targetIdNamespaces[entity]}/$sourceId',
    );
  }

  /// The legacy link halves are mapped through the controlled registry. Both
  /// halves move together — the server enforces
  /// `(entity_type is null) = (entity_id is null)` — so anything that cannot be
  /// carried in full degrades to no link at all rather than half a reference.
  (String?, String?) _entityLink(
    Map<String, Object?> row,
    PlatformMigrationEntity entity,
    String? sourceId,
    List<PlatformMigrationIssue> issues,
  ) {
    final rawType = row['entity_type'];
    final linkType = PlatformEntityType.fromWire(
      rawType is String ? rawType.trim() : null,
    );
    if (linkType == null) {
      issues.add(
        _fieldWarning(
          'mapping.entity_link_type_not_mapped',
          entity,
          sourceId,
          'entity_type',
        ),
      );
      return (null, null);
    }
    final rawId = row['entity_id'];
    if (rawId is! String || rawId.trim().isEmpty) {
      issues.add(
        _fieldWarning(
          'mapping.entity_link_id_missing',
          entity,
          sourceId,
          'entity_id',
        ),
      );
      return (null, null);
    }
    final id = rawId.trim();
    if (!Uuid.isValidUUID(fromString: id)) {
      // The target column is a uuid. Deriving one would adopt another domain's
      // migration namespace and invent a dangling reference.
      issues.add(
        _fieldWarning(
          'mapping.entity_link_id_not_uuid',
          entity,
          sourceId,
          'entity_id',
        ),
      );
      return (null, null);
    }
    return (linkType.wireName, id);
  }

  String? _validatedSourceId(
    Map<String, Object?> row,
    PlatformMigrationEntity entity,
    List<PlatformMigrationIssue> issues,
  ) {
    final value = row['id'];
    if (value is! String || value.isEmpty || value.trim() != value) {
      issues.add(_fieldError('source.invalid_id', entity, null, 'id'));
      return null;
    }
    return value;
  }

  String? _requiredText(
    Map<String, Object?> row, {
    required String key,
    required int maxLength,
    required PlatformMigrationEntity entity,
    required String? sourceId,
    required List<PlatformMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      issues.add(
        _fieldError('source.required_value_missing', entity, sourceId, key),
      );
      return null;
    }
    final normalized = value.trim();
    if (normalized.length > maxLength) {
      issues.add(_fieldError('source.text_too_long', entity, sourceId, key));
      return null;
    }
    if (normalized != value) {
      issues.add(_fieldWarning('mapping.text_trimmed', entity, sourceId, key));
    }
    return normalized;
  }

  String? _optionalText(
    Map<String, Object?> row, {
    required String key,
    required int maxLength,
    required PlatformMigrationEntity entity,
    required String? sourceId,
    required List<PlatformMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      issues.add(_fieldError('source.invalid_text', entity, sourceId, key));
      return null;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      issues.add(
        _fieldWarning('mapping.empty_text_to_null', entity, sourceId, key),
      );
      return null;
    }
    if (normalized.length > maxLength) {
      issues.add(_fieldError('source.text_too_long', entity, sourceId, key));
      return null;
    }
    if (normalized != value) {
      issues.add(_fieldWarning('mapping.text_trimmed', entity, sourceId, key));
    }
    return normalized;
  }

  String? _optionalUntrimmedText(
    Map<String, Object?> row, {
    required String key,
    required int maxLength,
    required PlatformMigrationEntity entity,
    required String? sourceId,
    required List<PlatformMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      issues.add(_fieldError('source.invalid_text', entity, sourceId, key));
      return null;
    }
    if (value.length > maxLength) {
      issues.add(_fieldError('source.text_too_long', entity, sourceId, key));
      return null;
    }
    return value;
  }

  /// Legacy timestamps are epoch milliseconds; the candidate rows carry
  /// ISO-8601 UTC strings. No clock is read.
  String? _requiredTimestamp(
    Map<String, Object?> row, {
    required String key,
    required PlatformMigrationEntity entity,
    required String? sourceId,
    required List<PlatformMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      issues.add(
        _fieldError('source.required_value_missing', entity, sourceId, key),
      );
      return null;
    }
    return _epochMillisToIso(
      value,
      key: key,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
  }

  String? _optionalTimestamp(
    Map<String, Object?> row, {
    required String key,
    required PlatformMigrationEntity entity,
    required String? sourceId,
    required List<PlatformMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    return _epochMillisToIso(
      value,
      key: key,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
  }

  String? _epochMillisToIso(
    Object? value, {
    required String key,
    required PlatformMigrationEntity entity,
    required String? sourceId,
    required List<PlatformMigrationIssue> issues,
  }) {
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      issues.add(
        _fieldError('source.invalid_epoch_millis', entity, sourceId, key),
      );
      return null;
    }
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
        isUtc: true,
      ).toIso8601String();
    } on RangeError {
      issues.add(
        _fieldError('source.invalid_epoch_millis', entity, sourceId, key),
      );
      return null;
    }
  }

  /// The source reads raw rows precisely so a legacy column nobody mapped
  /// becomes visible here instead of disappearing quietly.
  void _flagUnmappedColumns(
    Map<String, Object?> row,
    PlatformMigrationEntity entity,
    String? sourceId,
    List<PlatformMigrationIssue> issues,
    Set<String> knownColumns,
  ) {
    final unknown = row.keys.where((key) => !knownColumns.contains(key)).toList()
      ..sort();
    for (final column in unknown) {
      if (row[column] == null) {
        continue;
      }
      issues.add(
        _fieldWarning('source.unmapped_column', entity, sourceId, column),
      );
    }
  }

  static PlatformMigrationIssue _fieldError(
    String code,
    PlatformMigrationEntity entity,
    String? sourceId,
    String field,
  ) => PlatformMigrationIssue(
    code: code,
    severity: PlatformMigrationIssueSeverity.error,
    entity: entity,
    sourceId: sourceId,
    field: field,
  );

  static PlatformMigrationIssue _fieldWarning(
    String code,
    PlatformMigrationEntity entity,
    String? sourceId,
    String field,
  ) => PlatformMigrationIssue(
    code: code,
    severity: PlatformMigrationIssueSeverity.warning,
    entity: entity,
    sourceId: sourceId,
    field: field,
  );

  bool _hasErrors(List<PlatformMigrationIssue> issues) => issues.any(
    (issue) => issue.severity == PlatformMigrationIssueSeverity.error,
  );
}

class _EntitySpec {
  const _EntitySpec(
    this.entity,
    this.rows, {
    this.extraIssues = const <PlatformMigrationIssue>[],
  });

  final PlatformMigrationEntity entity;
  final List<Map<String, Object?>> rows;
  final List<PlatformMigrationIssue> extraIssues;
}

class _ImportMappingFold {
  const _ImportMappingFold({required this.byJobId, required this.issues});

  final Map<String, Map<String, Object?>> byJobId;
  final List<PlatformMigrationIssue> issues;
}

class _MappedRow {
  const _MappedRow({
    required this.sourceId,
    required this.issues,
    this.targetId,
    this.target,
    this.sourceProjection,
    this.targetProjection,
  });

  final String? sourceId;
  final String? targetId;
  final Map<String, Object?>? target;
  final Map<String, Object?>? sourceProjection;
  final Map<String, Object?>? targetProjection;
  final List<PlatformMigrationIssue> issues;

  bool get hasErrors => issues.any(
    (issue) => issue.severity == PlatformMigrationIssueSeverity.error,
  );
}

class _EntityResult {
  const _EntityResult({
    required this.aborted,
    required this.issues,
    required this.mappings,
    required this.summary,
  });

  final bool aborted;
  final List<PlatformMigrationIssue> issues;
  final List<PlatformMigrationMapping> mappings;
  final PlatformMigrationEntitySummary summary;
}

List<Map<String, Object?>> _sortedRows(List<Map<String, Object?>> rows) {
  final sorted = rows.map(Map<String, Object?>.from).toList(growable: false)
    ..sort((left, right) => _rowId(left).compareTo(_rowId(right)));
  return sorted;
}

List<Map<String, Object?>> _sortProjectionRows(List<Map<String, Object?>> rows) {
  final sorted = rows.map(Map<String, Object?>.from).toList(growable: false)
    ..sort((left, right) {
      final leftId = (left['source_id'] ?? left['id'] ?? '').toString();
      final rightId = (right['source_id'] ?? right['id'] ?? '').toString();
      return leftId.compareTo(rightId);
    });
  return sorted;
}

String _rowId(Map<String, Object?> row) => row['id']?.toString() ?? '';

int _compareMappings(
  PlatformMigrationMapping left,
  PlatformMigrationMapping right,
) {
  final entity = left.entity.name.compareTo(right.entity.name);
  return entity != 0 ? entity : left.sourceId.compareTo(right.sourceId);
}

int _compareIssues(
  PlatformMigrationIssue left,
  PlatformMigrationIssue right,
) {
  final leftKey = <String>[
    left.entity?.name ?? '',
    left.sourceId ?? '',
    left.field ?? '',
    left.code,
    left.severity.name,
  ].join(' ');
  final rightKey = <String>[
    right.entity?.name ?? '',
    right.sourceId ?? '',
    right.field ?? '',
    right.code,
    right.severity.name,
  ].join(' ');
  return leftKey.compareTo(rightKey);
}

const int _notificationTitleMaxLength = 300;
const int _notificationBodyMaxLength = 4000;

const Set<String> _taskPriorities = <String>{'low', 'normal', 'high'};

/// The literal status strings the legacy `ImportsRepository` writes, mapped
/// onto `public.import_job_status`. Anything else is unknown, not guessed.
const Map<Object?, String> _legacyImportJobStatuses = <Object?, String>{
  'pending': 'draft',
  'running': 'running',
  'succeeded': 'completed',
  'failed': 'failed',
};

const Set<String> _importJobCommitEvidenceStatuses = <String>{
  'ready',
  'running',
  'completed',
};
// `running`/`completed` also require a start stamp the legacy table never
// recorded, but they are already refused as unmigratable history above, so no
// separate started-status set is needed: `failed` is the only terminal status a
// legacy row can actually reach here.
const Set<String> _importJobTerminalStatuses = <String>{'completed', 'failed'};

const Map<PlatformMigrationEntity, String> _targetIdNamespaces =
    <PlatformMigrationEntity, String>{
      PlatformMigrationEntity.task: 'task',
      PlatformMigrationEntity.notification: 'notification',
      PlatformMigrationEntity.importJob: 'import_job',
    };

const Set<String> _taskColumns = <String>{
  'id',
  'entity_type',
  'entity_id',
  'title',
  'description',
  'category',
  'assigned_to',
  'estimated_cost',
  'status',
  'priority',
  'due_at',
  'created_at',
  'updated_at',
  'created_by',
};

const Set<String> _notificationColumns = <String>{
  'id',
  'entity_type',
  'entity_id',
  'kind',
  'message',
  'due_at',
  'read_at',
  'created_at',
};

const Set<String> _importJobColumns = <String>{
  'id',
  'kind',
  'status',
  'target_scope',
  'created_at',
  'finished_at',
  'error',
};

const Set<String> _importMappingColumns = <String>{
  'id',
  'import_job_id',
  'target_table',
  'mapping_json',
  'created_at',
};

final RegExp _normalizedKey = RegExp(r'^[a-z0-9]+([._-][a-z0-9]+)*$');
