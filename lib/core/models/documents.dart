import 'dart:convert';

class DocumentTypeRecord {
  const DocumentTypeRecord({
    required this.id,
    required this.name,
    required this.entityType,
    required this.requiredFields,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String entityType;
  final List<String> requiredFields;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'entity_type': entityType,
      'required_fields_json': jsonEncode(requiredFields),
      'created_at': createdAt,
    };
  }

  factory DocumentTypeRecord.fromMap(Map<String, Object?> map) {
    final fieldsRaw = map['required_fields_json'] as String?;
    final fields =
        fieldsRaw == null || fieldsRaw.trim().isEmpty
            ? const <String>[]
            : (jsonDecode(fieldsRaw) as List<dynamic>)
                .map((entry) => entry.toString())
                .toList(growable: false);
    return DocumentTypeRecord(
      id: map['id']! as String,
      name: map['name']! as String,
      entityType: map['entity_type']! as String,
      requiredFields: fields,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class DocumentRecord {
  const DocumentRecord({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.typeId,
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.sha256,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String? typeId;
  final String filePath;
  final String fileName;
  final String? mimeType;
  final int? sizeBytes;
  final String? sha256;
  final int createdAt;
  final String? createdBy;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'type_id': typeId,
      'file_path': filePath,
      'file_name': fileName,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'sha256': sha256,
      'created_at': createdAt,
      'created_by': createdBy,
      'updated_at': updatedAt,
    };
  }

  factory DocumentRecord.fromMap(Map<String, Object?> map) {
    return DocumentRecord(
      id: map['id']! as String,
      entityType: map['entity_type']! as String,
      entityId: map['entity_id']! as String,
      typeId: map['type_id'] as String?,
      filePath: map['file_path']! as String,
      fileName: map['file_name']! as String,
      mimeType: map['mime_type'] as String?,
      sizeBytes: (map['size_bytes'] as num?)?.toInt(),
      sha256: map['sha256'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      createdBy: map['created_by'] as String?,
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class DocumentMetadataRecord {
  const DocumentMetadataRecord({
    required this.id,
    required this.documentId,
    required this.key,
    required this.value,
  });

  final String id;
  final String documentId;
  final String key;
  final String value;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'document_id': documentId,
      'key': key,
      'value': value,
    };
  }

  factory DocumentMetadataRecord.fromMap(Map<String, Object?> map) {
    return DocumentMetadataRecord(
      id: map['id']! as String,
      documentId: map['document_id']! as String,
      key: map['key']! as String,
      value: map['value']! as String,
    );
  }
}

class RequiredDocumentRecord {
  const RequiredDocumentRecord({
    required this.id,
    required this.entityType,
    required this.propertyType,
    required this.typeId,
    required this.required,
    required this.expiresFieldKey,
    required this.createdAt,
  });

  final String id;
  final String entityType;
  final String? propertyType;
  final String typeId;
  final bool required;
  final String? expiresFieldKey;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'entity_type': entityType,
      'property_type': propertyType,
      'type_id': typeId,
      'required': required ? 1 : 0,
      'expires_field_key': expiresFieldKey,
      'created_at': createdAt,
    };
  }

  factory RequiredDocumentRecord.fromMap(Map<String, Object?> map) {
    return RequiredDocumentRecord(
      id: map['id']! as String,
      entityType: map['entity_type']! as String,
      propertyType: map['property_type'] as String?,
      typeId: map['type_id']! as String,
      required: ((map['required'] as num?) ?? 1) == 1,
      expiresFieldKey: map['expires_field_key'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class DocumentWithMetadata {
  const DocumentWithMetadata({required this.document, required this.metadata});

  final DocumentRecord document;
  final Map<String, String> metadata;
}

class DocumentComplianceIssue {
  const DocumentComplianceIssue({
    required this.entityType,
    required this.entityId,
    required this.typeId,
    required this.code,
    required this.message,
  });

  final String entityType;
  final String entityId;
  final String typeId;
  final String code;
  final String message;
}

class DocumentWorkflowRecord {
  const DocumentWorkflowRecord({
    required this.document,
    required this.metadata,
    required this.typeName,
    required this.status,
    required this.propertyId,
    required this.propertyName,
    required this.contextTitle,
    required this.contextSubtitle,
    required this.isRequired,
  });

  final DocumentRecord document;
  final Map<String, String> metadata;
  final String? typeName;
  final String status;
  final String? propertyId;
  final String? propertyName;
  final String contextTitle;
  final String contextSubtitle;
  final bool isRequired;
}
