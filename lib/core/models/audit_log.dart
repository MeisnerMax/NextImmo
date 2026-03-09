import 'dart:convert';

class AuditDiffItem {
  const AuditDiffItem({
    required this.fieldKey,
    required this.before,
    required this.after,
  });

  final String fieldKey;
  final Object? before;
  final Object? after;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'field_key': fieldKey,
      'before': before,
      'after': after,
    };
  }

  factory AuditDiffItem.fromMap(Map<String, Object?> map) {
    return AuditDiffItem(
      fieldKey: map['field_key']! as String,
      before: map['before'],
      after: map['after'],
    );
  }
}

class AuditLogRecord {
  const AuditLogRecord({
    required this.id,
    required this.occurredAt,
    required this.workspaceId,
    required this.actorUserId,
    required this.actorRole,
    required this.entityType,
    required this.entityId,
    required this.parentEntityType,
    required this.parentEntityId,
    required this.action,
    required this.oldValues,
    required this.newValues,
    required this.summary,
    required this.diffItems,
    required this.source,
    required this.correlationId,
    required this.reason,
    required this.isSystemEvent,
  });

  final String id;
  final int occurredAt;
  final String? workspaceId;
  final String? actorUserId;
  final String? actorRole;
  final String entityType;
  final String entityId;
  final String? parentEntityType;
  final String? parentEntityId;
  final String action;
  final Map<String, Object?>? oldValues;
  final Map<String, Object?>? newValues;
  final String? summary;
  final List<AuditDiffItem> diffItems;
  final String source;
  final String? correlationId;
  final String? reason;
  final bool isSystemEvent;

  int get changedAt => occurredAt;
  String? get userId => actorUserId;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'occurred_at': occurredAt,
      'changed_at': occurredAt,
      'workspace_id': workspaceId,
      'actor_user_id': actorUserId,
      'user_id': actorUserId,
      'actor_role': actorRole,
      'entity_type': entityType,
      'entity_id': entityId,
      'parent_entity_type': parentEntityType,
      'parent_entity_id': parentEntityId,
      'action': action,
      'old_values_json':
          oldValues == null ? null : jsonEncode(oldValues),
      'new_values_json':
          newValues == null ? null : jsonEncode(newValues),
      'summary': summary,
      'diff_json':
          diffItems.isEmpty
              ? null
              : jsonEncode(diffItems.map((item) => item.toMap()).toList()),
      'source': source,
      'correlation_id': correlationId,
      'reason': reason,
      'is_system_event': isSystemEvent ? 1 : 0,
    };
  }

  factory AuditLogRecord.fromMap(Map<String, Object?> map) {
    final rawDiff = map['diff_json'] as String?;
    final rawOldValues = map['old_values_json'] as String?;
    final rawNewValues = map['new_values_json'] as String?;
    final parsed =
        rawDiff == null || rawDiff.trim().isEmpty
            ? const <AuditDiffItem>[]
            : (jsonDecode(rawDiff) as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .map(
                  (item) => AuditDiffItem.fromMap(
                    item.map(
                      (key, value) => MapEntry<String, Object?>(key, value),
                    ),
                  ),
                )
                .toList(growable: false);
    return AuditLogRecord(
      id: map['id']! as String,
      occurredAt:
          ((map['occurred_at'] as num?) ?? (map['changed_at'] as num))
              .toInt(),
      workspaceId: map['workspace_id'] as String?,
      actorUserId:
          (map['actor_user_id'] as String?) ?? (map['user_id'] as String?),
      actorRole: map['actor_role'] as String?,
      entityType: map['entity_type']! as String,
      entityId: map['entity_id']! as String,
      parentEntityType: map['parent_entity_type'] as String?,
      parentEntityId: map['parent_entity_id'] as String?,
      action: map['action']! as String,
      oldValues: _decodeJsonMap(rawOldValues),
      newValues: _decodeJsonMap(rawNewValues),
      summary: map['summary'] as String?,
      diffItems: parsed,
      source: map['source']! as String,
      correlationId: map['correlation_id'] as String?,
      reason: map['reason'] as String?,
      isSystemEvent: ((map['is_system_event'] as num?) ?? 0) == 1,
    );
  }

  static Map<String, Object?>? _decodeJsonMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return decoded.map(
      (key, value) => MapEntry<String, Object?>(key.toString(), value),
    );
  }
}
