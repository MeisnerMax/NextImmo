class ImportJobRecord {
  const ImportJobRecord({
    required this.id,
    required this.kind,
    required this.status,
    required this.targetScope,
    required this.createdAt,
    required this.finishedAt,
    required this.error,
  });

  final String id;
  final String kind;
  final String status;
  final String targetScope;
  final int createdAt;
  final int? finishedAt;
  final String? error;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'kind': kind,
      'status': status,
      'target_scope': targetScope,
      'created_at': createdAt,
      'finished_at': finishedAt,
      'error': error,
    };
  }

  factory ImportJobRecord.fromMap(Map<String, Object?> map) {
    return ImportJobRecord(
      id: map['id']! as String,
      kind: map['kind']! as String,
      status: map['status']! as String,
      targetScope: map['target_scope']! as String,
      createdAt: ((map['created_at'] as num?) ?? 0).toInt(),
      finishedAt: (map['finished_at'] as num?)?.toInt(),
      error: map['error'] as String?,
    );
  }
}

class ImportMappingRecord {
  const ImportMappingRecord({
    required this.id,
    required this.importJobId,
    required this.targetTable,
    required this.mappingJson,
    required this.createdAt,
  });

  final String id;
  final String importJobId;
  final String targetTable;
  final String mappingJson;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'import_job_id': importJobId,
      'target_table': targetTable,
      'mapping_json': mappingJson,
      'created_at': createdAt,
    };
  }

  factory ImportMappingRecord.fromMap(Map<String, Object?> map) {
    return ImportMappingRecord(
      id: map['id']! as String,
      importJobId: map['import_job_id']! as String,
      targetTable: map['target_table']! as String,
      mappingJson: map['mapping_json']! as String,
      createdAt: ((map['created_at'] as num?) ?? 0).toInt(),
    );
  }
}
