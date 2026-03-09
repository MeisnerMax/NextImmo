class NoteRecord {
  const NoteRecord({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.text,
    required this.createdAt,
    this.createdBy,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String text;
  final int createdAt;
  final String? createdBy;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'text': text,
      'created_at': createdAt,
      'created_by': createdBy,
    };
  }

  factory NoteRecord.fromMap(Map<String, Object?> map) {
    return NoteRecord(
      id: map['id']! as String,
      entityType: map['entity_type']! as String,
      entityId: map['entity_id']! as String,
      text: map['text']! as String,
      createdAt: ((map['created_at'] as num?) ?? 0).toInt(),
      createdBy: map['created_by'] as String?,
    );
  }
}
