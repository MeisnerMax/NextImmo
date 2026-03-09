class SearchIndexRecord {
  const SearchIndexRecord({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String title;
  final String? subtitle;
  final String? body;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'title': title,
      'subtitle': subtitle,
      'body': body,
      'updated_at': updatedAt,
    };
  }

  factory SearchIndexRecord.fromMap(Map<String, Object?> map) {
    return SearchIndexRecord(
      id: map['id']! as String,
      entityType: map['entity_type']! as String,
      entityId: map['entity_id']! as String,
      title: map['title']! as String,
      subtitle: map['subtitle'] as String?,
      body: map['body'] as String?,
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}
