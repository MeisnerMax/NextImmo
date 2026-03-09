class NotificationRecord {
  const NotificationRecord({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.kind,
    required this.message,
    required this.dueAt,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String kind;
  final String message;
  final int? dueAt;
  final int? readAt;
  final int createdAt;

  bool get isRead => readAt != null;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'kind': kind,
      'message': message,
      'due_at': dueAt,
      'read_at': readAt,
      'created_at': createdAt,
    };
  }

  factory NotificationRecord.fromMap(Map<String, Object?> map) {
    return NotificationRecord(
      id: map['id']! as String,
      entityType: map['entity_type']! as String,
      entityId: map['entity_id']! as String,
      kind: map['kind']! as String,
      message: map['message']! as String,
      dueAt: (map['due_at'] as num?)?.toInt(),
      readAt: (map['read_at'] as num?)?.toInt(),
      createdAt: ((map['created_at'] as num?) ?? 0).toInt(),
    );
  }
}
