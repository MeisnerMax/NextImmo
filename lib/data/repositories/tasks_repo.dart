import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_service.dart';
import '../../core/audit/audit_writer.dart';
import '../../core/models/audit_log.dart';
import '../../core/models/task.dart';
import 'audit_log_repo.dart';
import 'search_repo.dart';

class TasksRepo {
  const TasksRepo(
    this._db, {
    SearchRepo? searchRepo,
    AuditLogRepo? auditLogRepo,
    AuditWriter? auditWriter,
  }) : _searchRepo = searchRepo,
       _auditLogRepo = auditLogRepo,
       _auditWriter = auditWriter;

  final Database _db;
  final SearchRepo? _searchRepo;
  final AuditLogRepo? _auditLogRepo;
  final AuditWriter? _auditWriter;
  static const AuditService _auditService = AuditService();

  Future<List<TaskRecord>> listTasks({
    String? status,
    int? dueFrom,
    int? dueTo,
    String? entityType,
    String? entityId,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    if (dueFrom != null) {
      where.add('due_at >= ?');
      args.add(dueFrom);
    }
    if (dueTo != null) {
      where.add('due_at <= ?');
      args.add(dueTo);
    }
    if (entityType != null) {
      where.add('entity_type = ?');
      args.add(entityType);
    }
    if (entityId != null) {
      where.add('entity_id = ?');
      args.add(entityId);
    }
    final rows = await _db.query(
      'tasks',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'due_at ASC, created_at DESC',
    );
    return rows.map(TaskRecord.fromMap).toList();
  }

  Future<List<TaskWorkflowRecord>> listWorkflowTasks({
    String? status,
    int? dueFrom,
    int? dueTo,
    String? entityType,
    String? entityId,
  }) async {
    final tasks = await listTasks(
      status: status,
      dueFrom: dueFrom,
      dueTo: dueTo,
      entityType: entityType,
      entityId: entityId,
    );
    final records = <TaskWorkflowRecord>[];
    for (final task in tasks) {
      records.add(await _buildWorkflowRecord(task));
    }
    return records;
  }

  Future<TaskRecord> createTask({
    required String entityType,
    String? entityId,
    required String title,
    String status = 'todo',
    String priority = 'normal',
    int? dueAt,
    String? createdBy,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = TaskRecord(
      id: const Uuid().v4(),
      entityType: entityType,
      entityId: entityId,
      title: title,
      status: status,
      priority: priority,
      dueAt: dueAt,
      createdAt: now,
      updatedAt: now,
      createdBy: createdBy,
    );
    await _db.insert(
      'tasks',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildTaskRecord(record));
    }
    final parentPropertyId = await _resolvePropertyIdForTask(record);
    await _recordAudit(
      entityType: 'task',
      entityId: record.id,
      action: 'create',
      summary: 'Task created: ${record.title}',
      newValues: record.toMap(),
      parentEntityType: parentPropertyId == null ? null : 'property',
      parentEntityId: parentPropertyId,
    );
    return record;
  }

  Future<void> updateTask(TaskRecord task) async {
    final before = await _db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: <Object?>[task.id],
      limit: 1,
    );
    await _db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[task.id],
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildTaskRecord(task));
    }
    final parentPropertyId = await _resolvePropertyIdForTask(task);
    await _recordAudit(
      entityType: 'task',
      entityId: task.id,
      action: 'update',
      summary: 'Task updated',
      oldValues: before.isEmpty ? null : before.first,
      newValues: task.toMap(),
      diffItems:
          before.isEmpty
              ? const <AuditDiffItem>[]
              : _auditService.buildDiff(before.first, task.toMap()),
      parentEntityType: parentPropertyId == null ? null : 'property',
      parentEntityId: parentPropertyId,
    );
  }

  Future<void> updateTaskStatus({
    required String id,
    required String status,
  }) async {
    final rows = await _db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return;
    }
    final task = TaskRecord.fromMap(rows.first);
    await updateTask(
      TaskRecord(
        id: task.id,
        entityType: task.entityType,
        entityId: task.entityId,
        title: task.title,
        status: status,
        priority: task.priority,
        dueAt: task.dueAt,
        createdAt: task.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        createdBy: task.createdBy,
      ),
    );
  }

  Future<void> deleteTask(String id) async {
    final before = await _db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    await _db.delete('tasks', where: 'id = ?', whereArgs: <Object?>[id]);
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.deleteIndexEntryByEntity(
        entityType: 'task',
        entityId: id,
      );
    }
    final task = before.isEmpty ? null : TaskRecord.fromMap(before.first);
    final parentPropertyId =
        task == null ? null : await _resolvePropertyIdForTask(task);
    await _recordAudit(
      entityType: 'task',
      entityId: id,
      action: 'delete',
      summary: 'Task deleted',
      oldValues: before.isEmpty ? null : before.first,
      parentEntityType: parentPropertyId == null ? null : 'property',
      parentEntityId: parentPropertyId,
    );
  }

  Future<List<TaskChecklistItemRecord>> listChecklistItems(
    String taskId,
  ) async {
    final rows = await _db.query(
      'task_checklist_items',
      where: 'task_id = ?',
      whereArgs: <Object?>[taskId],
      orderBy: 'position ASC',
    );
    return rows.map(TaskChecklistItemRecord.fromMap).toList();
  }

  Future<TaskChecklistItemRecord> addChecklistItem({
    required String taskId,
    required String text,
    required int position,
  }) async {
    final item = TaskChecklistItemRecord(
      id: const Uuid().v4(),
      taskId: taskId,
      text: text,
      position: position,
      done: false,
    );
    await _db.insert(
      'task_checklist_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final parentPropertyId = await _resolvePropertyIdForTaskId(taskId);
    await _recordAudit(
      entityType: 'task_checklist_item',
      entityId: item.id,
      action: 'create',
      summary: 'Task checklist item created',
      newValues: item.toMap(),
      parentEntityType: parentPropertyId == null ? null : 'property',
      parentEntityId: parentPropertyId,
    );
    return item;
  }

  Future<void> toggleChecklistItem({
    required String id,
    required bool done,
  }) async {
    final before = await _db.query(
      'task_checklist_items',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    await _db.update(
      'task_checklist_items',
      <String, Object?>{'done': done ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    final after = await _db.query(
      'task_checklist_items',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    final parentPropertyId = await _resolvePropertyIdForChecklistItem(id);
    await _recordAudit(
      entityType: 'task_checklist_item',
      entityId: id,
      action: 'update',
      summary: 'Task checklist item toggled',
      oldValues: before.isEmpty ? null : before.first,
      newValues: after.isEmpty ? null : after.first,
      diffItems:
          before.isEmpty || after.isEmpty
              ? const <AuditDiffItem>[]
              : _auditService.buildDiff(before.first, after.first),
      parentEntityType: parentPropertyId == null ? null : 'property',
      parentEntityId: parentPropertyId,
    );
  }

  Future<void> deleteChecklistItem(String id) async {
    final before = await _db.query(
      'task_checklist_items',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    final parentPropertyId = await _resolvePropertyIdForChecklistItem(id);
    await _db.delete(
      'task_checklist_items',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    await _recordAudit(
      entityType: 'task_checklist_item',
      entityId: id,
      action: 'delete',
      summary: 'Task checklist item deleted',
      oldValues: before.isEmpty ? null : before.first,
      parentEntityType: parentPropertyId == null ? null : 'property',
      parentEntityId: parentPropertyId,
    );
  }

  Future<List<TaskTemplateRecord>> listTemplates() async {
    final rows = await _db.query(
      'task_templates',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(TaskTemplateRecord.fromMap).toList();
  }

  Future<TaskTemplateRecord> createTemplate({
    required String name,
    required String entityType,
    required String defaultTitle,
    String defaultPriority = 'normal',
    int? defaultDueDaysOffset,
    String recurrenceRule = 'none',
    int recurrenceInterval = 1,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = TaskTemplateRecord(
      id: const Uuid().v4(),
      name: name.trim(),
      entityType: entityType,
      defaultTitle: defaultTitle,
      defaultPriority: defaultPriority,
      defaultDueDaysOffset: defaultDueDaysOffset,
      recurrenceRule: recurrenceRule,
      recurrenceInterval: recurrenceInterval,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert(
      'task_templates',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return record;
  }

  Future<void> updateTemplate(TaskTemplateRecord template) async {
    await _db.update(
      'task_templates',
      template.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[template.id],
    );
  }

  Future<void> deleteTemplate(String id) async {
    await _db.delete(
      'task_templates',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<TaskTemplateChecklistItemRecord>> listTemplateChecklistItems(
    String templateId,
  ) async {
    final rows = await _db.query(
      'task_template_checklist_items',
      where: 'template_id = ?',
      whereArgs: <Object?>[templateId],
      orderBy: 'position ASC',
    );
    return rows.map(TaskTemplateChecklistItemRecord.fromMap).toList();
  }

  Future<TaskTemplateChecklistItemRecord> addTemplateChecklistItem({
    required String templateId,
    required String text,
    required int position,
  }) async {
    final item = TaskTemplateChecklistItemRecord(
      id: const Uuid().v4(),
      templateId: templateId,
      text: text,
      position: position,
    );
    await _db.insert(
      'task_template_checklist_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return item;
  }

  Future<void> deleteTemplateChecklistItem(String id) async {
    await _db.delete(
      'task_template_checklist_items',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<bool> hasGeneratedKey(String generatedKey) async {
    final count = _firstIntValue(
      await _db.rawQuery(
        'SELECT COUNT(*) FROM task_generated_instances WHERE generated_key = ?',
        <Object?>[generatedKey],
      ),
    );
    return count > 0;
  }

  Future<void> addGeneratedInstance(TaskGeneratedInstanceRecord record) async {
    await _db.insert(
      'task_generated_instances',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  int _firstIntValue(List<Map<String, Object?>> rows) {
    if (rows.isEmpty || rows.first.isEmpty) {
      return 0;
    }
    final value = rows.first.values.first;
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString()) ?? 0;
  }

  Future<String?> _resolvePropertyIdForChecklistItem(
    String checklistItemId,
  ) async {
    final rows = await _db.query(
      'task_checklist_items',
      columns: const <String>['task_id'],
      where: 'id = ?',
      whereArgs: <Object?>[checklistItemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _resolvePropertyIdForTaskId(rows.first['task_id']! as String);
  }

  Future<String?> _resolvePropertyIdForTaskId(String taskId) async {
    final rows = await _db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: <Object?>[taskId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _resolvePropertyIdForTask(TaskRecord.fromMap(rows.first));
  }

  Future<String?> _resolvePropertyIdForTask(TaskRecord task) async {
    final entityType = task.entityType;
    final entityId = task.entityId;
    if (entityId == null || entityId.trim().isEmpty) {
      return null;
    }
    switch (entityType) {
      case 'property':
        return entityId;
      case 'unit':
        final unitRows = await _db.query(
          'units',
          columns: const <String>['asset_property_id'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        return unitRows.isEmpty
            ? null
            : unitRows.first['asset_property_id'] as String?;
      case 'lease':
        final leaseRows = await _db.query(
          'leases',
          columns: const <String>['asset_property_id'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        return leaseRows.isEmpty
            ? null
            : leaseRows.first['asset_property_id'] as String?;
      case 'tenant':
        final tenantRows = await _db.query(
          'leases',
          columns: const <String>['asset_property_id'],
          where: 'tenant_id = ?',
          whereArgs: <Object?>[entityId],
          orderBy: 'updated_at DESC',
          limit: 1,
        );
        return tenantRows.isEmpty
            ? null
            : tenantRows.first['asset_property_id'] as String?;
      case 'scenario':
        final scenarioRows = await _db.query(
          'scenarios',
          columns: const <String>['property_id'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        return scenarioRows.isEmpty
            ? null
            : scenarioRows.first['property_id'] as String?;
      case 'maintenance_ticket':
        final ticketRows = await _db.query(
          'maintenance_tickets',
          columns: const <String>['asset_property_id'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        return ticketRows.isEmpty
            ? null
            : ticketRows.first['asset_property_id'] as String?;
      case 'document':
        final documentRows = await _db.query(
          'documents',
          columns: const <String>['entity_type', 'entity_id'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        if (documentRows.isEmpty) {
          return null;
        }
        final nestedTask = TaskRecord(
          id: task.id,
          entityType: documentRows.first['entity_type']! as String,
          entityId: documentRows.first['entity_id']! as String,
          title: task.title,
          status: task.status,
          priority: task.priority,
          dueAt: task.dueAt,
          createdAt: task.createdAt,
          updatedAt: task.updatedAt,
          createdBy: task.createdBy,
        );
        return _resolvePropertyIdForTask(nestedTask);
      default:
        return null;
    }
  }

  Future<TaskWorkflowRecord> _buildWorkflowRecord(TaskRecord task) async {
    final propertyId = await _resolvePropertyIdForTask(task);
    final propertyName = await _loadPropertyName(propertyId);
    final context = await _resolveTaskContext(task);
    return TaskWorkflowRecord(
      task: task,
      propertyId: propertyId,
      propertyName: propertyName,
      contextTitle: context.$1,
      contextSubtitle: context.$2,
    );
  }

  Future<(String, String)> _resolveTaskContext(TaskRecord task) async {
    final entityId = task.entityId;
    if (entityId == null || entityId.trim().isEmpty) {
      return ('Unassigned', 'No workflow context linked yet');
    }
    switch (task.entityType) {
      case 'property':
      case 'asset_property':
        final rows = await _db.query(
          'properties',
          columns: const <String>['name'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        final name = rows.isEmpty ? entityId : rows.first['name']! as String;
        return ('Property', name);
      case 'unit':
        final rows = await _db.query(
          'units',
          columns: const <String>['unit_code', 'asset_property_id'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        if (rows.isEmpty) {
          return ('Unit', entityId);
        }
        final propertyName = await _loadPropertyName(
          rows.first['asset_property_id'] as String?,
        );
        return (
          'Unit',
          '${rows.first['unit_code']! as String}${propertyName == null ? '' : ' · $propertyName'}',
        );
      case 'lease':
        final rows = await _db.query(
          'leases',
          columns: const <String>['lease_name', 'asset_property_id'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        if (rows.isEmpty) {
          return ('Lease', entityId);
        }
        final propertyName = await _loadPropertyName(
          rows.first['asset_property_id'] as String?,
        );
        return (
          'Lease',
          '${rows.first['lease_name']! as String}${propertyName == null ? '' : ' · $propertyName'}',
        );
      case 'tenant':
        final rows = await _db.query(
          'tenants',
          columns: const <String>['display_name'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        final name =
            rows.isEmpty ? entityId : rows.first['display_name']! as String;
        return ('Tenant', name);
      case 'document':
        final rows = await _db.query(
          'documents',
          columns: const <String>['file_name', 'entity_type', 'entity_id'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        if (rows.isEmpty) {
          return ('Document', entityId);
        }
        final nestedTitle = rows.first['file_name']! as String;
        final nestedType = rows.first['entity_type']! as String;
        final nestedId = rows.first['entity_id']! as String;
        final nestedContext = await _resolveTaskContext(
          TaskRecord(
            id: task.id,
            entityType: nestedType,
            entityId: nestedId,
            title: task.title,
            status: task.status,
            priority: task.priority,
            dueAt: task.dueAt,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            createdBy: task.createdBy,
          ),
        );
        return ('Document', '$nestedTitle · ${nestedContext.$2}');
      case 'maintenance_ticket':
        final rows = await _db.query(
          'maintenance_tickets',
          columns: const <String>['title', 'asset_property_id'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        if (rows.isEmpty) {
          return ('Maintenance', entityId);
        }
        final propertyName = await _loadPropertyName(
          rows.first['asset_property_id'] as String?,
        );
        return (
          'Maintenance',
          '${rows.first['title']! as String}${propertyName == null ? '' : ' · $propertyName'}',
        );
      case 'portfolio':
        final rows = await _db.query(
          'portfolios',
          columns: const <String>['name'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        final name = rows.isEmpty ? entityId : rows.first['name']! as String;
        return ('Portfolio', name);
      case 'scenario':
        final rows = await _db.query(
          'scenarios',
          columns: const <String>['name'],
          where: 'id = ?',
          whereArgs: <Object?>[entityId],
          limit: 1,
        );
        final name = rows.isEmpty ? entityId : rows.first['name']! as String;
        return ('Scenario', name);
      default:
        return (task.entityType, entityId);
    }
  }

  Future<String?> _loadPropertyName(String? propertyId) async {
    if (propertyId == null || propertyId.trim().isEmpty) {
      return null;
    }
    final rows = await _db.query(
      'properties',
      columns: const <String>['name'],
      where: 'id = ?',
      whereArgs: <Object?>[propertyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['name']! as String;
  }

  Future<void> _recordAudit({
    required String entityType,
    required String entityId,
    required String action,
    String? summary,
    String? parentEntityType,
    String? parentEntityId,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
    List<AuditDiffItem> diffItems = const <AuditDiffItem>[],
  }) async {
    final writer = _auditWriter;
    if (writer != null) {
      await writer.record(
        entityType: entityType,
        entityId: entityId,
        action: action,
        summary: summary,
        parentEntityType: parentEntityType,
        parentEntityId: parentEntityId,
        oldValues: oldValues,
        newValues: newValues,
        diffItems: diffItems,
      );
      return;
    }
    await _auditLogRepo?.recordEvent(
      entityType: entityType,
      entityId: entityId,
      action: action,
      summary: summary,
      parentEntityType: parentEntityType,
      parentEntityId: parentEntityId,
      oldValues: oldValues,
      newValues: newValues,
      diffItems: diffItems,
      source: 'ui',
    );
  }
}
