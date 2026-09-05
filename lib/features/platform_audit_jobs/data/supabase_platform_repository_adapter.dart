import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/audit_read_port.dart';
import '../application/platform_repository.dart';
import '../domain/audit_event_dto.dart';
import '../domain/import_job_dto.dart';
import '../domain/notification_dto.dart';
import '../domain/platform_entity_type.dart';
import '../domain/search_entry_dto.dart';
import '../domain/task_dto.dart';

/// The single seam between the platform ports and the Supabase SDK. Reads go
/// through PostgREST (RLS-authorized), every mutation goes through an RPC —
/// there is no direct-DML path, and the server grants none.
abstract interface class PlatformSupabaseGateway {
  String? get currentUserId;

  Future<List<Map<String, dynamic>>> listTasks({
    required String workspaceId,
    required List<String>? statuses,
    required String? entityType,
    required String? entityId,
    required String? assignedTo,
    required bool unassignedOnly,
    required String? propertyId,
    required DateTime? dueFrom,
    required DateTime? dueUntil,
    required bool withoutDue,
    required String? titleQuery,
    required bool includeArchived,
    required bool sortByDue,
    required PlatformKeysetCursor? after,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> getTask({
    required String workspaceId,
    required String taskId,
  });

  Future<List<Map<String, dynamic>>> listNotifications({
    required String workspaceId,
    required String? recipientUserId,
    required bool unreadOnly,
    required PlatformKeysetCursor? after,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> listImportJobs({
    required String workspaceId,
    required String? status,
    required String? targetScope,
    required PlatformKeysetCursor? after,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> getImportJob({
    required String workspaceId,
    required String importJobId,
  });

  Future<List<Map<String, dynamic>>> listSearchEntries({
    required String workspaceId,
    required String? entityType,
    required List<({String type, String id})>? entities,
    required PlatformKeysetCursor? after,
    required int limit,
  });

  Future<Object?> callRpc(String function, Map<String, Object?> parameters);
}

class SupabasePlatformGateway implements PlatformSupabaseGateway {
  SupabasePlatformGateway(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> listTasks({
    required String workspaceId,
    required List<String>? statuses,
    required String? entityType,
    required String? entityId,
    required String? assignedTo,
    required bool unassignedOnly,
    required String? propertyId,
    required DateTime? dueFrom,
    required DateTime? dueUntil,
    required bool withoutDue,
    required String? titleQuery,
    required bool includeArchived,
    required bool sortByDue,
    required PlatformKeysetCursor? after,
    required int limit,
  }) async {
    var query = _client.from('tasks').select().eq('workspace_id', workspaceId);
    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter('status', statuses);
    }
    if (entityType != null && entityId != null) {
      query = query.eq('entity_type', entityType).eq('entity_id', entityId);
    }
    if (assignedTo != null) {
      query = query.eq('assigned_to', assignedTo);
    }
    if (unassignedOnly) {
      query = query.isFilter('assigned_to', null);
    }
    if (propertyId != null) {
      query = query.eq('property_id', propertyId);
    }
    // Half-open, matching count_tasks: from inclusive, until exclusive.
    if (dueFrom != null) {
      query = query.gte('due_at', dueFrom.toUtc().toIso8601String());
    }
    if (dueUntil != null) {
      query = query.lt('due_at', dueUntil.toUtc().toIso8601String());
    }
    if (withoutDue) {
      query = query.isFilter('due_at', null);
    }
    if (titleQuery != null) {
      query = query.ilike('title', '%${escapeLikePattern(titleQuery)}%');
    }
    if (!includeArchived) {
      query = query.neq('status', 'archived');
    }
    if (sortByDue) {
      // The due-ordered read serves only dated tasks — the keyset pair cannot
      // express null, and the no-date bucket is the withoutDue filter.
      query = query.not('due_at', 'is', null);
      if (after != null) {
        query = query.or(_keysetFilterAscending('due_at', after));
      }
      final rows = await query
          .order('due_at', ascending: true)
          .order('id', ascending: true)
          .limit(limit);
      return rows.map(Map<String, dynamic>.from).toList(growable: false);
    }
    if (after != null) {
      query = query.or(_keysetFilter('created_at', after));
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getTask({
    required String workspaceId,
    required String taskId,
  }) async {
    final rows = await _client
        .from('tasks')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('id', taskId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listNotifications({
    required String workspaceId,
    required String? recipientUserId,
    required bool unreadOnly,
    required PlatformKeysetCursor? after,
    required int limit,
  }) async {
    var query = _client
        .from('notifications')
        .select()
        .eq('workspace_id', workspaceId);
    if (recipientUserId != null) {
      query = query.eq('recipient_user_id', recipientUserId);
    }
    if (unreadOnly) {
      query = query.isFilter('read_at', null);
    }
    if (after != null) {
      query = query.or(_keysetFilter('created_at', after));
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listImportJobs({
    required String workspaceId,
    required String? status,
    required String? targetScope,
    required PlatformKeysetCursor? after,
    required int limit,
  }) async {
    var query = _client
        .from('import_jobs')
        .select()
        .eq('workspace_id', workspaceId);
    if (status != null) {
      query = query.eq('status', status);
    }
    if (targetScope != null) {
      query = query.eq('target_scope', targetScope);
    }
    if (after != null) {
      query = query.or(_keysetFilter('created_at', after));
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getImportJob({
    required String workspaceId,
    required String importJobId,
  }) async {
    final rows = await _client
        .from('import_jobs')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('id', importJobId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listSearchEntries({
    required String workspaceId,
    required String? entityType,
    required List<({String type, String id})>? entities,
    required PlatformKeysetCursor? after,
    required int limit,
  }) async {
    var query = _client
        .from('search_index')
        .select()
        .eq('workspace_id', workspaceId);
    if (entityType != null) {
      query = query.eq('entity_type', entityType);
    }
    if (entities != null && entities.isNotEmpty) {
      // Registry wire names and uuids only — no or-syntax metacharacters.
      query = query.or(
        entities
            .map(
              (entity) =>
                  'and(entity_type.eq.${entity.type},entity_id.eq.${entity.id})',
            )
            .join(','),
      );
    }
    if (after != null) {
      query = query.or(_keysetFilter('updated_at', after));
    }
    final rows = await query
        .order('updated_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) {
    return _client.rpc(function, params: parameters);
  }

  /// Descending composite keyset: strictly older, or same instant with a
  /// smaller id. The tie-break is what makes the page boundary exact when many
  /// rows share a timestamp — which they do, because `now()` is transaction-
  /// bound and one fan-out writes every row at the same instant.
  static String _keysetFilter(String column, PlatformKeysetCursor cursor) {
    final stamp = cursor.timestamp.toUtc().toIso8601String();
    return '$column.lt.$stamp,and($column.eq.$stamp,id.lt.${cursor.id})';
  }

  /// The ascending twin, for the due-ordered read: strictly later, or the
  /// same instant with a larger id.
  static String _keysetFilterAscending(
    String column,
    PlatformKeysetCursor cursor,
  ) {
    final stamp = cursor.timestamp.toUtc().toIso8601String();
    return '$column.gt.$stamp,and($column.eq.$stamp,id.gt.${cursor.id})';
  }

  /// A title query is a literal substring: `%`, `_` and `\` in the input must
  /// match themselves, not act as ilike wildcards — the same escaping
  /// `count_tasks` applies server-side, so list and count agree.
  /// Public for the contract test; production code reaches it only through
  /// [listTasks].
  static String escapeLikePattern(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}

AuditEventDto _parseAuditEvent(Map<String, dynamic> row) {
  return AuditEventDto(
    id: _requiredString(row, 'id'),
    occurredAt: DateTime.parse(_requiredString(row, 'occurred_at')),
    action: _requiredString(row, 'action'),
    entityType: _requiredString(row, 'entity_type'),
    entityId: row['entity_id'] as String?,
    parentEntityType: row['parent_entity_type'] as String?,
    parentEntityId: row['parent_entity_id'] as String?,
    // An unknown actor type degrades to `system`, never to `user`: attributing
    // a change to a person the server did not name would be worse than
    // attributing it to the platform.
    actorType: switch (row['actor_type']) {
      'user' => AuditActorType.user,
      'service' => AuditActorType.service,
      _ => AuditActorType.system,
    },
    actorUserId: row['actor_user_id'] as String?,
    actorIdentifier: row['actor_identifier'] as String?,
    roleKey: row['role_key'] as String?,
    source: _requiredString(row, 'source'),
    correlationId: _requiredString(row, 'correlation_id'),
    mutationId: row['mutation_id'] as String?,
    reason: row['reason'] as String?,
    changedFields: <String>[
      if (row['changed_fields'] is List)
        for (final field in row['changed_fields'] as List)
          if (field is String) field,
    ],
  );
}

AuditEventCursor? _parseAuditCursor(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final cursor = _asMap(raw);
  final occurredAt = cursor['occurred_at'];
  final id = cursor['id'];
  if (occurredAt is! String || id is! String) {
    return null;
  }
  return AuditEventCursor(occurredAt: DateTime.parse(occurredAt), id: id);
}

/// Supabase-backed implementation of the four data-plane DOM-010 ports.
class SupabasePlatformRepositoryAdapter
    implements
        TaskRepository,
        NotificationPort,
        JobRepository,
        SearchIndexPort,
        AuditReadPort {
  SupabasePlatformRepositoryAdapter({required SupabaseClient client})
    : _gateway = SupabasePlatformGateway(client);

  SupabasePlatformRepositoryAdapter.withGateway(PlatformSupabaseGateway gateway)
    : _gateway = gateway;

  final PlatformSupabaseGateway _gateway;

  // ---------------------------------------------------------------------------
  // TaskRepository
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<TaskDto>>> searchTasks(
    TaskListQuery query,
  ) async {
    try {
      final sortByDue = query.sort == TaskListSort.dueAsc;
      final rows = await _gateway.listTasks(
        workspaceId: query.workspaceId,
        statuses: query.statuses
            ?.map((status) => status.wireName)
            .toList(growable: false),
        entityType: query.entity?.type.wireName,
        entityId: query.entity?.id,
        assignedTo: query.assignedTo,
        unassignedOnly: query.unassignedOnly,
        propertyId: query.propertyId,
        dueFrom: query.dueFrom,
        dueUntil: query.dueUntil,
        withoutDue: query.withoutDue,
        titleQuery: query.titleQuery,
        includeArchived: query.includeArchived,
        sortByDue: sortByDue,
        after: PlatformKeysetCursor.decode(query.page.cursor),
        limit: query.page.limit + 1,
      );
      return PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(
        _page<TaskDto>(
          rows: rows,
          limit: query.page.limit,
          workspaceId: query.workspaceId,
          parse: _parseTask,
          cursorOf:
              (task) => PlatformKeysetCursor(
                // The cursor column must match the active sort; a due-ordered
                // read never serves a task without a due date.
                timestamp: sortByDue ? task.dueAt! : task.createdAt,
                id: task.id,
              ),
          workspaceOf: (task) => task.workspaceId,
        ),
      );
    } catch (error) {
      return _readFailure<PlatformPageResult<TaskDto>>(
        error,
        'Supabase tasks could not be loaded.',
      );
    }
  }

  @override
  Future<PlatformRepositoryResult<int>> countTasks(TaskCountQuery query) async {
    try {
      final response = await _gateway.callRpc('count_tasks', <String, Object?>{
        'p_workspace_id': query.workspaceId,
        'p_statuses': query.statuses
            ?.map((status) => status.wireName)
            .toList(growable: false),
        'p_assigned_to': query.assignedTo,
        'p_unassigned_only': query.unassignedOnly,
        'p_entity_type': query.entity?.type.wireName,
        'p_entity_id': query.entity?.id,
        'p_property_id': query.propertyId,
        'p_due_from': _formatTimestamp(query.dueFrom),
        'p_due_until': _formatTimestamp(query.dueUntil),
        'p_without_due': query.withoutDue,
        'p_include_archived': query.includeArchived,
        'p_title_query': query.titleQuery,
      });
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return PlatformRepositorySuccess<int>(
          _requiredInt(_asMap(payload['entity']), 'count'),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<int>(_asMap(payload['error']), null);
    } catch (error) {
      return _readFailure<int>(
        error,
        'Supabase task count could not be loaded.',
      );
    }
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> getTaskById({
    required String workspaceId,
    required String taskId,
  }) async {
    try {
      final rows = await _gateway.getTask(
        workspaceId: workspaceId,
        taskId: taskId,
      );
      if (rows.isEmpty) {
        return const PlatformRepositoryFailure<TaskDto>(
          kind: PlatformRepositoryFailureKind.notFound,
          message: 'Task not found.',
        );
      }
      final task = _parseTask(rows.first);
      _requireWorkspace(task.workspaceId, workspaceId);
      return PlatformRepositorySuccess<TaskDto>(task);
    } catch (error) {
      return _readFailure<TaskDto>(error, 'Supabase task could not be loaded.');
    }
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> createTask(
    CreateTaskCommand command,
  ) {
    final draft = command.draft;
    return _executeCommand<TaskDto>(
      context: command.context,
      function: 'create_task',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_title': draft.title,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_entity_type': draft.entity?.type.wireName,
        'p_entity_id': draft.entity?.id,
        'p_description': draft.description,
        'p_category': draft.category,
        'p_assigned_to': draft.assignedTo,
        'p_priority': draft.priority.wireName,
        'p_due_at': _formatTimestamp(draft.dueAt),
        'p_generated_key': draft.generatedKey,
        'p_reason': command.context.reason,
      },
      parseEntity:
          (entity) => _parseScopedTask(entity, command.context.workspaceId),
    );
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> updateTask(
    UpdateTaskCommand command,
  ) {
    final changes = command.changes;
    return _executeCommand<TaskDto>(
      context: command.context,
      function: 'update_task',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_task_id': command.taskId,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_changes': <String, Object?>{
          if (changes.title != null) 'title': changes.title,
          if (changes.description.isPresent)
            'description': changes.description.value,
          if (changes.category.isPresent) 'category': changes.category.value,
          if (changes.assignedTo.isPresent)
            'assigned_to': changes.assignedTo.value,
          if (changes.priority != null) 'priority': changes.priority!.wireName,
          if (changes.dueAt.isPresent)
            'due_at': _formatTimestamp(changes.dueAt.value),
        },
        'p_reason': command.context.reason,
      },
      parseEntity:
          (entity) => _parseScopedTask(entity, command.context.workspaceId),
      parseConflictEntity:
          (entity) => (
            currentTask: _parseScopedTask(entity, command.context.workspaceId),
            currentImportJob: null,
          ),
    );
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> transitionTaskStatus(
    TransitionTaskStatusCommand command,
  ) {
    return _executeCommand<TaskDto>(
      context: command.context,
      function: 'transition_task_status',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_task_id': command.taskId,
        'p_expected_version': command.expectedVersion,
        'p_to_status': command.targetStatus.wireName,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity:
          (entity) => _parseScopedTask(entity, command.context.workspaceId),
      parseConflictEntity:
          (entity) => (
            currentTask: _parseScopedTask(entity, command.context.workspaceId),
            currentImportJob: null,
          ),
    );
  }

  // ---------------------------------------------------------------------------
  // NotificationPort
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<NotificationDto>>>
  notificationFeed(NotificationFeedQuery query) async {
    try {
      final rows = await _gateway.listNotifications(
        workspaceId: query.workspaceId,
        recipientUserId: query.recipientUserId,
        unreadOnly: query.unreadOnly,
        after: PlatformKeysetCursor.decode(query.page.cursor),
        limit: query.page.limit + 1,
      );
      return PlatformRepositorySuccess<PlatformPageResult<NotificationDto>>(
        _page<NotificationDto>(
          rows: rows,
          limit: query.page.limit,
          workspaceId: query.workspaceId,
          parse: _parseNotification,
          cursorOf:
              (notification) => PlatformKeysetCursor(
                timestamp: notification.createdAt,
                id: notification.id,
              ),
          workspaceOf: (notification) => notification.workspaceId,
        ),
      );
    } catch (error) {
      return _readFailure<PlatformPageResult<NotificationDto>>(
        error,
        'Supabase notifications could not be loaded.',
      );
    }
  }

  @override
  Future<PlatformRepositoryResult<NotificationFanOutReceipt>>
  fanOutNotification(CreateNotificationCommand command) {
    final draft = command.draft;
    return _executeCommand<NotificationFanOutReceipt>(
      context: command.context,
      function: 'create_notification',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_recipient_user_ids': draft.recipientUserIds,
        'p_kind': draft.kind,
        'p_title': draft.title,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_body': draft.body,
        'p_entity_type': draft.entity?.type.wireName,
        'p_entity_id': draft.entity?.id,
        'p_reason': command.context.reason,
      },
      parseEntity: _parseFanOutReceipt,
    );
  }

  @override
  Future<PlatformRepositoryResult<NotificationDto>> markNotificationRead(
    MarkNotificationReadCommand command,
  ) {
    return _executeCommand<NotificationDto>(
      context: command.context,
      function: 'mark_notification_read',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_notification_id': command.notificationId,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
      },
      parseEntity: (entity) {
        final notification = _parseNotification(entity);
        _requireWorkspace(
          notification.workspaceId,
          command.context.workspaceId,
        );
        return notification;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // JobRepository
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<ImportJobDto>>>
  searchImportJobs(ImportJobListQuery query) async {
    try {
      final rows = await _gateway.listImportJobs(
        workspaceId: query.workspaceId,
        status: query.status?.wireName,
        targetScope: query.targetScope,
        after: PlatformKeysetCursor.decode(query.page.cursor),
        limit: query.page.limit + 1,
      );
      return PlatformRepositorySuccess<PlatformPageResult<ImportJobDto>>(
        _page<ImportJobDto>(
          rows: rows,
          limit: query.page.limit,
          workspaceId: query.workspaceId,
          parse: _parseImportJob,
          cursorOf:
              (job) =>
                  PlatformKeysetCursor(timestamp: job.createdAt, id: job.id),
          workspaceOf: (job) => job.workspaceId,
        ),
      );
    } catch (error) {
      return _readFailure<PlatformPageResult<ImportJobDto>>(
        error,
        'Supabase import jobs could not be loaded.',
      );
    }
  }

  @override
  Future<PlatformRepositoryResult<ImportJobDto>> getImportJobById({
    required String workspaceId,
    required String importJobId,
  }) async {
    try {
      final rows = await _gateway.getImportJob(
        workspaceId: workspaceId,
        importJobId: importJobId,
      );
      if (rows.isEmpty) {
        return const PlatformRepositoryFailure<ImportJobDto>(
          kind: PlatformRepositoryFailureKind.notFound,
          message: 'Import job not found.',
        );
      }
      final job = _parseImportJob(rows.first);
      _requireWorkspace(job.workspaceId, workspaceId);
      return PlatformRepositorySuccess<ImportJobDto>(job);
    } catch (error) {
      return _readFailure<ImportJobDto>(
        error,
        'Supabase import job could not be loaded.',
      );
    }
  }

  @override
  Future<PlatformRepositoryResult<ImportJobDto>> createImportJob(
    CreateImportJobCommand command,
  ) {
    return _executeCommand<ImportJobDto>(
      context: command.context,
      function: 'create_import_job',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_source_kind': command.draft.sourceKind,
        'p_target_scope': command.draft.targetScope,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_mapping': command.draft.mapping,
        'p_reason': command.context.reason,
      },
      parseEntity:
          (entity) =>
              _parseScopedImportJob(entity, command.context.workspaceId),
    );
  }

  @override
  Future<PlatformRepositoryResult<ImportJobDto>> updateImportJob(
    UpdateImportJobCommand command,
  ) {
    final changes = command.changes;
    return _executeCommand<ImportJobDto>(
      context: command.context,
      function: 'update_import_job',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_import_job_id': command.importJobId,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_changes': <String, Object?>{
          if (changes.sourceKind != null) 'source_kind': changes.sourceKind,
          if (changes.targetScope != null) 'target_scope': changes.targetScope,
          if (changes.mapping != null) 'mapping': changes.mapping,
        },
        'p_reason': command.context.reason,
      },
      parseEntity:
          (entity) =>
              _parseScopedImportJob(entity, command.context.workspaceId),
      parseConflictEntity:
          (entity) => (
            currentTask: null,
            currentImportJob: _parseScopedImportJob(
              entity,
              command.context.workspaceId,
            ),
          ),
    );
  }

  @override
  Future<PlatformRepositoryResult<ImportJobDto>> transitionImportJobStatus(
    TransitionImportJobStatusCommand command,
  ) {
    final evidence = command.evidence;
    return _executeCommand<ImportJobDto>(
      context: command.context,
      function: 'transition_import_job_status',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_import_job_id': command.importJobId,
        'p_expected_version': command.expectedVersion,
        'p_to_status': command.targetStatus.wireName,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_dry_run': evidence.dryRun,
        'p_reconciliation': evidence.reconciliation,
        'p_error_report': evidence.errorReport,
        'p_reason': command.context.reason,
      },
      parseEntity:
          (entity) =>
              _parseScopedImportJob(entity, command.context.workspaceId),
      parseConflictEntity:
          (entity) => (
            currentTask: null,
            currentImportJob: _parseScopedImportJob(
              entity,
              command.context.workspaceId,
            ),
          ),
    );
  }

  // ---------------------------------------------------------------------------
  // SearchIndexPort
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<SearchEntryDto>>>
  searchIndex(SearchIndexQuery query) async {
    try {
      final rows = await _gateway.listSearchEntries(
        workspaceId: query.workspaceId,
        entityType: query.entityType?.wireName,
        entities: query.entities
            ?.map((entity) => (type: entity.type.wireName, id: entity.id))
            .toList(growable: false),
        after: PlatformKeysetCursor.decode(query.page.cursor),
        limit: query.page.limit + 1,
      );
      return PlatformRepositorySuccess<PlatformPageResult<SearchEntryDto>>(
        _page<SearchEntryDto>(
          rows: rows,
          limit: query.page.limit,
          workspaceId: query.workspaceId,
          parse: _parseSearchEntry,
          cursorOf:
              (entry) => PlatformKeysetCursor(
                timestamp: entry.updatedAt,
                id: entry.id,
              ),
          workspaceOf: (entry) => entry.workspaceId,
        ),
      );
    } catch (error) {
      return _readFailure<PlatformPageResult<SearchEntryDto>>(
        error,
        'Supabase search index could not be loaded.',
      );
    }
  }

  @override
  Future<PlatformRepositoryResult<SearchEntryDto>> reindexSearchEntry(
    ReindexSearchEntryCommand command,
  ) {
    return _executeUnenvelopedCommand<SearchEntryDto>(
      context: command.context,
      function: 'reindex_search_entry',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_entity_type': command.entity.type.wireName,
        'p_entity_id': command.entity.id,
        'p_title': command.content.title,
        'p_subtitle': command.content.subtitle,
        'p_body': command.content.body,
      },
      parseEntity: (entity) {
        final parsed = _parseSearchEntry(entity);
        _requireWorkspace(parsed.workspaceId, command.context.workspaceId);
        return parsed;
      },
    );
  }

  @override
  Future<PlatformRepositoryResult<SearchEntryRemoval>> removeSearchEntry(
    RemoveSearchEntryCommand command,
  ) {
    return _executeUnenvelopedCommand<SearchEntryRemoval>(
      context: command.context,
      function: 'remove_search_entry',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_entity_type': command.entity.type.wireName,
        'p_entity_id': command.entity.id,
      },
      parseEntity: (entity) {
        final removal = _parseSearchRemoval(entity);
        _requireWorkspace(removal.workspaceId, command.context.workspaceId);
        return removal;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Shared command execution
  // ---------------------------------------------------------------------------

  Future<PlatformRepositoryResult<T>> _executeCommand<T>({
    required PlatformCommandContext context,
    required String function,
    required Map<String, Object?> parameters,
    required T Function(Map<String, dynamic> entity) parseEntity,
    _ConflictEntity Function(Map<String, dynamic> entity)? parseConflictEntity,
  }) async {
    // Short-circuit before any network call: a command whose declared actor is
    // not the authenticated user is a client bug, and sending it would write an
    // audit row attributing the mutation to the wrong person.
    if (_gateway.currentUserId != context.actorId) {
      return PlatformRepositoryFailure<T>(
        kind: PlatformRepositoryFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }
    return _dispatch<T>(
      function: function,
      parameters: parameters,
      parseEntity: parseEntity,
      parseConflictEntity: parseConflictEntity,
    );
  }

  /// The search-index write path. Same actor guard, but no envelope: there is
  /// no `mutationId` to replay and no version to conflict on, so a
  /// `version_conflict` from this path would be a contract violation and is
  /// treated as one (no conflict parser is supplied).
  Future<PlatformRepositoryResult<T>> _executeUnenvelopedCommand<T>({
    required SearchIndexCommandContext context,
    required String function,
    required Map<String, Object?> parameters,
    required T Function(Map<String, dynamic> entity) parseEntity,
  }) async {
    if (_gateway.currentUserId != context.actorId) {
      return PlatformRepositoryFailure<T>(
        kind: PlatformRepositoryFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }
    return _dispatch<T>(
      function: function,
      parameters: parameters,
      parseEntity: parseEntity,
      parseConflictEntity: null,
    );
  }

  /// AUDIT-01. The projection is the server's: this reads what the RPC chose
  /// to publish and adds nothing. In particular there is no branch here that
  /// could reach for `old_values` or `new_values` — the payload does not carry
  /// them, which is the point.
  @override
  Future<PlatformRepositoryResult<AuditEventPage>> propertyAuditEvents(
    PropertyAuditQuery query,
  ) async {
    try {
      final response = await _gateway
          .callRpc('property_audit_events', <String, Object?>{
            'p_workspace_id': query.workspaceId,
            'p_property_id': query.propertyId,
            'p_after_occurred_at':
                query.cursor?.occurredAt.toUtc().toIso8601String(),
            'p_after_id': query.cursor?.id,
            'p_limit': query.limit,
          });
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        final raw = payload['events'];
        return PlatformRepositorySuccess<AuditEventPage>(
          AuditEventPage(
            events: <AuditEventDto>[
              if (raw is List)
                for (final item in raw)
                  if (item is Map) _parseAuditEvent(_asMap(item)),
            ],
            nextCursor: _parseAuditCursor(payload['next_cursor']),
          ),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<AuditEventPage>(_asMap(payload['error']), null);
    } catch (_) {
      return const PlatformRepositoryFailure<AuditEventPage>(
        kind: PlatformRepositoryFailureKind.infrastructureFailure,
        message: 'The audit trail could not be loaded.',
      );
    }
  }

  Future<PlatformRepositoryResult<T>> _dispatch<T>({
    required String function,
    required Map<String, Object?> parameters,
    required T Function(Map<String, dynamic> entity) parseEntity,
    required _ConflictEntity Function(Map<String, dynamic> entity)?
    parseConflictEntity,
  }) async {
    try {
      final response = await _gateway.callRpc(function, parameters);
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return PlatformRepositorySuccess<T>(
          parseEntity(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<T>(_asMap(payload['error']), parseConflictEntity);
    } catch (_) {
      return PlatformRepositoryFailure<T>(
        kind: PlatformRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase platform command failed.',
      );
    }
  }

  PlatformRepositoryFailure<T> _mapRpcFailure<T>(
    Map<String, dynamic> error,
    _ConflictEntity Function(Map<String, dynamic> entity)? parseConflictEntity,
  ) {
    final code = _requiredString(error, 'code');
    // The server's own message is passed through: these are our controlled
    // strings, not arbitrary infrastructure text. Anything thrown from outside
    // that contract lands in the catch above as an infrastructure failure.
    final message =
        error['message'] is String
            ? error['message'] as String
            : 'Platform command failed.';
    switch (code) {
      case 'not_found':
        return PlatformRepositoryFailure<T>(
          kind: PlatformRepositoryFailureKind.notFound,
          message: message,
        );
      case 'forbidden':
        return PlatformRepositoryFailure<T>(
          kind: PlatformRepositoryFailureKind.forbidden,
          message: message,
        );
      case 'validation_failed':
        return PlatformRepositoryFailure<T>(
          kind: PlatformRepositoryFailureKind.validationFailed,
          message: message,
          validationFields: _validationFields(error),
        );
      case 'mutation_conflict':
        return PlatformRepositoryFailure<T>(
          kind: PlatformRepositoryFailureKind.mutationConflict,
          message: message,
        );
      case 'in_progress':
        return PlatformRepositoryFailure<T>(
          kind: PlatformRepositoryFailureKind.mutationInProgress,
          message: message,
        );
      case 'version_conflict':
        if (parseConflictEntity == null) {
          throw const FormatException('Unexpected version conflict.');
        }
        final conflictEntity = parseConflictEntity(
          _asMap(error['current_entity']),
        );
        return PlatformRepositoryFailure<T>(
          kind: PlatformRepositoryFailureKind.versionConflict,
          message: message,
          versionConflict: PlatformVersionConflict(
            expectedVersion: _requiredInt(error, 'expected_version'),
            actualVersion: _requiredInt(error, 'actual_version'),
            currentTask: conflictEntity.currentTask,
            currentImportJob: conflictEntity.currentImportJob,
          ),
        );
      case 'infrastructure_failure':
      default:
        return PlatformRepositoryFailure<T>(
          kind: PlatformRepositoryFailureKind.infrastructureFailure,
          message: 'Supabase platform command failed.',
        );
    }
  }

  TaskDto _parseScopedTask(Map<String, dynamic> entity, String workspaceId) {
    final task = _parseTask(entity);
    _requireWorkspace(task.workspaceId, workspaceId);
    return task;
  }

  ImportJobDto _parseScopedImportJob(
    Map<String, dynamic> entity,
    String workspaceId,
  ) {
    final job = _parseImportJob(entity);
    _requireWorkspace(job.workspaceId, workspaceId);
    return job;
  }
}

typedef _ConflictEntity =
    ({TaskDto? currentTask, ImportJobDto? currentImportJob});

/// Read-path failure classification (A15). An authorization refusal must
/// surface as `forbidden`, not be flattened into an infrastructure failure —
/// the UI is neither allowed to claim "Kein Zugriff" it cannot know nor to
/// hide one it was told. `42501` is Postgres `insufficient_privilege`; `403`
/// is PostgREST's HTTP form of the same answer. An RLS policy that merely
/// filters rows never lands here (it returns an empty result, not an error).
PlatformRepositoryFailure<T> _readFailure<T>(Object error, String message) {
  if (error is PostgrestException &&
      (error.code == '42501' || error.code == '403')) {
    return PlatformRepositoryFailure<T>(
      kind: PlatformRepositoryFailureKind.forbidden,
      message: error.message,
    );
  }
  return PlatformRepositoryFailure<T>(
    kind: PlatformRepositoryFailureKind.infrastructureFailure,
    message: message,
  );
}

/// `validation_failed` names its rejected input as `field` (one key) or
/// `fields` (several, e.g. unknown update keys). Anything else in there is a
/// contract violation and is dropped rather than crashing the error path.
List<String> _validationFields(Map<String, dynamic> error) {
  final single = error['field'];
  final many = error['fields'];
  return List<String>.unmodifiable(<String>[
    if (single is String && single.isNotEmpty) single,
    if (many is List)
      ...many.whereType<String>().where((field) => field.isNotEmpty),
  ]);
}

/// Fail closed on a workspace mismatch: a row the server returned for another
/// workspace means the scope guard was bypassed somewhere, and continuing would
/// surface foreign data as if it were the caller's.
void _requireWorkspace(String actual, String expected) {
  if (actual != expected) {
    throw const FormatException('Platform row workspace mismatch.');
  }
}

PlatformPageResult<T> _page<T>({
  required List<Map<String, dynamic>> rows,
  required int limit,
  required String workspaceId,
  required T Function(Map<String, dynamic> row) parse,
  required PlatformKeysetCursor Function(T item) cursorOf,
  required String Function(T item) workspaceOf,
}) {
  final hasNextPage = rows.length > limit;
  final pageRows = hasNextPage ? rows.take(limit) : rows;
  final items = pageRows.map(parse).toList(growable: false);
  if (items.any((item) => workspaceOf(item) != workspaceId)) {
    throw const FormatException('Platform row workspace mismatch.');
  }
  return PlatformPageResult<T>(
    items: items,
    nextCursor:
        hasNextPage && items.isNotEmpty ? cursorOf(items.last).encode() : null,
  );
}

// -----------------------------------------------------------------------------
// Row parsing
// -----------------------------------------------------------------------------

TaskDto _parseTask(Map<String, dynamic> row) {
  return TaskDto(
    id: _requiredString(row, 'id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    title: _requiredString(row, 'title'),
    priority: _requiredEnum(
      TaskPriority.fromWire(row['priority'] as String?),
      'priority',
    ),
    status: _requiredEnum(
      TaskStatus.fromWire(row['status'] as String?),
      'status',
    ),
    createdAt: _requiredDateTime(row, 'created_at'),
    updatedAt: _requiredDateTime(row, 'updated_at'),
    createdBy: _requiredString(row, 'created_by'),
    updatedBy: _requiredString(row, 'updated_by'),
    version: _requiredInt(row, 'version'),
    entity: _parseEntityRef(row),
    propertyId: _optionalString(row, 'property_id'),
    description: _optionalString(row, 'description'),
    category: _optionalString(row, 'category'),
    assignedTo: _optionalString(row, 'assigned_to'),
    dueAt: _optionalDateTime(row, 'due_at'),
    generatedKey: _optionalString(row, 'generated_key'),
    archivedAt: _optionalDateTime(row, 'archived_at'),
  );
}

NotificationDto _parseNotification(Map<String, dynamic> row) {
  return NotificationDto(
    id: _requiredString(row, 'id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    recipientUserId: _requiredString(row, 'recipient_user_id'),
    kind: _requiredString(row, 'kind'),
    title: _requiredString(row, 'title'),
    createdAt: _requiredDateTime(row, 'created_at'),
    updatedAt: _requiredDateTime(row, 'updated_at'),
    createdBy: _requiredString(row, 'created_by'),
    updatedBy: _requiredString(row, 'updated_by'),
    version: _requiredInt(row, 'version'),
    body: _optionalString(row, 'body'),
    entity: _parseEntityRef(row),
    readAt: _optionalDateTime(row, 'read_at'),
  );
}

NotificationFanOutReceipt _parseFanOutReceipt(Map<String, dynamic> entity) {
  final ids = entity['notification_ids'];
  if (ids is! List) {
    throw const FormatException('Expected a notification id list.');
  }
  final notificationIds = ids
      .map((id) {
        if (id is! String || id.isEmpty) {
          throw const FormatException('Expected a non-empty notification id.');
        }
        return id;
      })
      .toList(growable: false);
  final receipt = NotificationFanOutReceipt(
    kind: _requiredString(entity, 'kind'),
    recipientCount: _requiredInt(entity, 'recipient_count'),
    notificationIds: notificationIds,
  );
  // The batch is all-or-nothing server-side; a count that disagrees with the
  // ids would mean a partial delivery the contract says cannot happen.
  if (receipt.recipientCount != receipt.notificationIds.length) {
    throw const FormatException('Fan-out recipient count does not match ids.');
  }
  return receipt;
}

ImportJobDto _parseImportJob(Map<String, dynamic> row) {
  return ImportJobDto(
    id: _requiredString(row, 'id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    sourceKind: _requiredString(row, 'source_kind'),
    targetScope: _requiredString(row, 'target_scope'),
    status: _requiredEnum(
      ImportJobStatus.fromWire(row['status'] as String?),
      'status',
    ),
    mapping: _requiredJsonObject(row, 'mapping'),
    createdAt: _requiredDateTime(row, 'created_at'),
    updatedAt: _requiredDateTime(row, 'updated_at'),
    createdBy: _requiredString(row, 'created_by'),
    updatedBy: _requiredString(row, 'updated_by'),
    version: _requiredInt(row, 'version'),
    dryRun: _optionalJsonObject(row, 'dry_run'),
    reconciliation: _optionalJsonObject(row, 'reconciliation'),
    errorReport: _optionalJsonObject(row, 'error_report'),
    startedAt: _optionalDateTime(row, 'started_at'),
    finishedAt: _optionalDateTime(row, 'finished_at'),
  );
}

SearchEntryDto _parseSearchEntry(Map<String, dynamic> row) {
  final entity = _parseEntityRef(row);
  if (entity == null) {
    throw const FormatException('A search entry must reference an entity.');
  }
  return SearchEntryDto(
    id: _requiredString(row, 'id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    entity: entity,
    title: _requiredString(row, 'title'),
    updatedAt: _requiredDateTime(row, 'updated_at'),
    createdAt: _requiredDateTime(row, 'created_at'),
    createdBy: _requiredString(row, 'created_by'),
    updatedBy: _requiredString(row, 'updated_by'),
    subtitle: _optionalString(row, 'subtitle'),
    body: _optionalString(row, 'body'),
  );
}

SearchEntryRemoval _parseSearchRemoval(Map<String, dynamic> entity) {
  final ref = _parseEntityRef(entity);
  if (ref == null) {
    throw const FormatException('A removal must reference an entity.');
  }
  final removed = entity['removed'];
  if (removed is! bool) {
    throw const FormatException('Expected a boolean removal flag.');
  }
  return SearchEntryRemoval(
    workspaceId: _requiredString(entity, 'workspace_id'),
    entity: ref,
    removed: removed,
  );
}

/// Both halves of an entity link move together — the server enforces
/// `(entity_type is null) = (entity_id is null)`, so a half-set pair is a
/// contract violation rather than a degraded link.
PlatformEntityRef? _parseEntityRef(Map<String, dynamic> row) {
  final type = row['entity_type'];
  final id = row['entity_id'];
  if (type == null && id == null) {
    return null;
  }
  if (type is! String || id is! String || id.isEmpty) {
    throw const FormatException('Incomplete entity reference.');
  }
  final parsed = PlatformEntityType.fromWire(type);
  if (parsed == null) {
    throw FormatException('Unknown entity type: $type.');
  }
  return PlatformEntityRef(type: parsed, id: id);
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw const FormatException('Expected a JSON object.');
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected non-empty string field: $key.');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Expected string field: $key.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is int) {
    return value;
  }
  if (value is num && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('Expected integer field: $key.');
}

DateTime _requiredDateTime(Map<String, dynamic> row, String key) {
  final value = _optionalDateTime(row, key);
  if (value == null) {
    throw FormatException('Expected timestamp field: $key.');
  }
  return value;
}

DateTime? _optionalDateTime(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Expected timestamp field: $key.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Malformed timestamp field: $key.');
  }
  return parsed;
}

Map<String, Object?> _requiredJsonObject(Map<String, dynamic> row, String key) {
  final value = _optionalJsonObject(row, key);
  if (value == null) {
    throw FormatException('Expected JSON object field: $key.');
  }
  return value;
}

Map<String, Object?>? _optionalJsonObject(
  Map<String, dynamic> row,
  String key,
) {
  final value = row[key];
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    throw FormatException('Expected JSON object field: $key.');
  }
  return Map<String, Object?>.from(value);
}

T _requiredEnum<T>(T? value, String key) {
  if (value == null) {
    throw FormatException('Unknown enum value for field: $key.');
  }
  return value;
}

String? _formatTimestamp(DateTime? value) => value?.toUtc().toIso8601String();
