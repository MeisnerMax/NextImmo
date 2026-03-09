import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/audit_log.dart';

class AuditLogRepo {
  const AuditLogRepo(this._db);

  final Database _db;

  Future<AuditLogRecord> recordEvent({
    required String entityType,
    required String entityId,
    required String action,
    String? userId,
    String? workspaceId,
    String? actorUserId,
    String? actorRole,
    String? summary,
    String? parentEntityType,
    String? parentEntityId,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
    List<AuditDiffItem> diffItems = const <AuditDiffItem>[],
    String source = 'ui',
    String? correlationId,
    String? reason,
    bool isSystemEvent = false,
    int? occurredAt,
    int? changedAt,
  }) async {
    final timestamp =
        occurredAt ?? changedAt ?? DateTime.now().millisecondsSinceEpoch;
    final event = AuditLogRecord(
      id: const Uuid().v4(),
      occurredAt: timestamp,
      workspaceId: workspaceId,
      actorUserId: actorUserId ?? userId,
      actorRole: actorRole,
      entityType: entityType,
      entityId: entityId,
      parentEntityType: parentEntityType,
      parentEntityId: parentEntityId,
      action: action,
      oldValues: oldValues,
      newValues: newValues,
      summary: summary,
      diffItems: diffItems,
      source: source,
      correlationId: correlationId,
      reason: reason,
      isSystemEvent: isSystemEvent,
    );
    await _db.insert(
      'audit_log',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return event;
  }

  Future<List<AuditLogRecord>> list({
    String? entityType,
    String? entityId,
    Iterable<String>? entityIds,
    String? action,
    String? userId,
    String? workspaceId,
    String? actorRole,
    String? source,
    String? parentEntityType,
    String? parentEntityId,
    int? fromChangedAt,
    int? toChangedAt,
    int? limit,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (entityType != null && entityType.trim().isNotEmpty) {
      where.add('entity_type = ?');
      args.add(entityType.trim());
    }
    if (entityId != null && entityId.trim().isNotEmpty) {
      where.add('entity_id = ?');
      args.add(entityId.trim());
    }
    final normalizedEntityIds =
        entityIds
            ?.map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
    if (normalizedEntityIds != null && normalizedEntityIds.isNotEmpty) {
      final placeholders =
          List<String>.filled(normalizedEntityIds.length, '?').join(', ');
      where.add('entity_id IN ($placeholders)');
      args.addAll(normalizedEntityIds);
    }
    if (action != null && action.trim().isNotEmpty) {
      where.add('action = ?');
      args.add(action.trim());
    }
    if (userId != null && userId.trim().isNotEmpty) {
      where.add('(actor_user_id = ? OR user_id = ?)');
      args.add(userId.trim());
      args.add(userId.trim());
    }
    if (workspaceId != null && workspaceId.trim().isNotEmpty) {
      where.add('workspace_id = ?');
      args.add(workspaceId.trim());
    }
    if (actorRole != null && actorRole.trim().isNotEmpty) {
      where.add('actor_role = ?');
      args.add(actorRole.trim());
    }
    if (source != null && source.trim().isNotEmpty) {
      where.add('source = ?');
      args.add(source.trim());
    }
    if (parentEntityType != null && parentEntityType.trim().isNotEmpty) {
      where.add('parent_entity_type = ?');
      args.add(parentEntityType.trim());
    }
    if (parentEntityId != null && parentEntityId.trim().isNotEmpty) {
      where.add('parent_entity_id = ?');
      args.add(parentEntityId.trim());
    }
    if (fromChangedAt != null) {
      where.add('COALESCE(occurred_at, changed_at) >= ?');
      args.add(fromChangedAt);
    }
    if (toChangedAt != null) {
      where.add('COALESCE(occurred_at, changed_at) <= ?');
      args.add(toChangedAt);
    }

    final rows = await _db.query(
      'audit_log',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'COALESCE(occurred_at, changed_at) DESC',
      limit: limit,
    );
    return rows.map(AuditLogRecord.fromMap).toList(growable: false);
  }
}
