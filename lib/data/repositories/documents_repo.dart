import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_service.dart';
import '../../core/audit/audit_writer.dart';
import '../../core/models/audit_log.dart';
import '../../core/docs/doc_compliance_engine.dart';
import '../../core/models/documents.dart';
import 'audit_log_repo.dart';
import 'required_documents_repo.dart';
import 'search_repo.dart';

class DocumentsRepo {
  const DocumentsRepo(
    this._db,
    this._requiredRepo,
    this._complianceEngine, {
    this.auditLogRepo,
    this.auditWriter,
    SearchRepo? searchRepo,
  }) : _searchRepo = searchRepo;

  final Database _db;
  final RequiredDocumentsRepo _requiredRepo;
  final DocComplianceEngine _complianceEngine;
  final AuditLogRepo? auditLogRepo;
  final AuditWriter? auditWriter;
  final SearchRepo? _searchRepo;
  static const AuditService _auditService = AuditService();

  Future<List<DocumentRecord>> listDocuments({
    String? entityType,
    String? entityId,
    String? typeId,
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
    if (typeId != null && typeId.trim().isNotEmpty) {
      where.add('type_id = ?');
      args.add(typeId.trim());
    }
    final rows = await _db.query(
      'documents',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(DocumentRecord.fromMap).toList(growable: false);
  }

  Future<List<DocumentWorkflowRecord>> listWorkflowDocuments({
    String? entityType,
    String? entityId,
    String? typeId,
  }) async {
    final docs = await listDocuments(
      entityType: entityType,
      entityId: entityId,
      typeId: typeId,
    );
    final types = await _db.query('document_types');
    final typeNames = <String, String>{
      for (final row in types) row['id']! as String: row['name']! as String,
    };
    final requirements = await _requiredRepo.list();
    final records = <DocumentWorkflowRecord>[];
    for (final doc in docs) {
      final metadataRows = await listMetadata(doc.id);
      final metadata = <String, String>{
        for (final item in metadataRows) item.key: item.value,
      };
      final propertyId = await _resolvePropertyIdForEntity(
        doc.entityType,
        doc.entityId,
      );
      final propertyName = await _loadPropertyName(propertyId);
      final context = await _resolveDocumentContext(doc);
      RequiredDocumentRecord? requirement;
      for (final item in requirements) {
        if (item.entityType == doc.entityType && item.typeId == doc.typeId) {
          requirement = item;
          break;
        }
      }
      records.add(
        DocumentWorkflowRecord(
          document: doc,
          metadata: metadata,
          typeName: doc.typeId == null ? null : typeNames[doc.typeId!],
          status: _resolveDocumentStatus(
            metadata: metadata,
            requirement: requirement,
          ),
          propertyId: propertyId,
          propertyName: propertyName,
          contextTitle: context.$1,
          contextSubtitle: context.$2,
          isRequired: requirement?.required ?? false,
        ),
      );
    }
    return records;
  }

  Future<DocumentRecord> createDocument({
    required String entityType,
    required String entityId,
    String? typeId,
    required String filePath,
    required String fileName,
    String? mimeType,
    int? sizeBytes,
    String? sha256,
    String? createdBy,
    Map<String, String> metadata = const <String, String>{},
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = DocumentRecord(
      id: const Uuid().v4(),
      entityType: entityType.trim(),
      entityId: entityId.trim(),
      typeId: typeId?.trim().isEmpty ?? true ? null : typeId!.trim(),
      filePath: filePath.trim(),
      fileName: fileName.trim(),
      mimeType: mimeType?.trim(),
      sizeBytes: sizeBytes,
      sha256: sha256?.trim(),
      createdAt: now,
      createdBy: createdBy?.trim(),
      updatedAt: now,
    );

    await _db.transaction((txn) async {
      await txn.insert(
        'documents',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      for (final entry in metadata.entries) {
        final meta = DocumentMetadataRecord(
          id: const Uuid().v4(),
          documentId: record.id,
          key: entry.key.trim(),
          value: entry.value.trim(),
        );
        await txn.insert(
          'document_metadata',
          meta.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    final parentPropertyId = await _resolvePropertyIdForEntity(
      record.entityType,
      record.entityId,
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildDocumentRecord(record));
    }
    await _recordAudit(
      entityType: 'document',
      entityId: record.id,
      action: 'create',
      summary: 'Document added for ${record.entityType}:${record.entityId}',
      newValues: record.toMap(),
      parentEntityType: parentPropertyId == null ? null : 'property',
      parentEntityId: parentPropertyId,
    );
    return record;
  }

  Future<void> updateDocument(DocumentRecord record) async {
    final before = await _db.query(
      'documents',
      where: 'id = ?',
      whereArgs: <Object?>[record.id],
      limit: 1,
    );
    await _db.update(
      'documents',
      record.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[record.id],
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildDocumentRecord(record));
    }
    final parentPropertyId = await _resolvePropertyIdForEntity(
      record.entityType,
      record.entityId,
    );
    await _recordAudit(
      entityType: 'document',
      entityId: record.id,
      action: 'update',
      summary: 'Document updated',
      oldValues: before.isEmpty ? null : before.first,
      newValues: record.toMap(),
      diffItems:
          before.isEmpty
              ? const <AuditDiffItem>[]
              : _auditService.buildDiff(before.first, record.toMap()),
      parentEntityType: parentPropertyId == null ? null : 'property',
      parentEntityId: parentPropertyId,
    );
  }

  Future<void> deleteDocument(String id) async {
    final before = await _db.query(
      'documents',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    await _db.delete('documents', where: 'id = ?', whereArgs: <Object?>[id]);
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.deleteIndexEntryByEntity(
        entityType: 'document',
        entityId: id,
      );
    }
    final doc = before.isEmpty ? null : DocumentRecord.fromMap(before.first);
    final parentPropertyId =
        doc == null
            ? null
            : await _resolvePropertyIdForEntity(doc.entityType, doc.entityId);
    await _recordAudit(
      entityType: 'document',
      entityId: id,
      action: 'delete',
      summary: 'Document deleted',
      oldValues: before.isEmpty ? null : before.first,
      parentEntityType: parentPropertyId == null ? null : 'property',
      parentEntityId: parentPropertyId,
    );
  }

  Future<List<DocumentMetadataRecord>> listMetadata(String documentId) async {
    final rows = await _db.query(
      'document_metadata',
      where: 'document_id = ?',
      whereArgs: <Object?>[documentId],
      orderBy: 'key COLLATE NOCASE',
    );
    return rows.map(DocumentMetadataRecord.fromMap).toList(growable: false);
  }

  Future<void> upsertMetadata({
    required String documentId,
    required String key,
    required String value,
  }) async {
    final record = DocumentMetadataRecord(
      id: const Uuid().v4(),
      documentId: documentId,
      key: key.trim(),
      value: value.trim(),
    );
    await _db.insert(
      'document_metadata',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final parentPropertyId = await _resolvePropertyIdForDocument(documentId);
    await _recordAudit(
      entityType: 'document_metadata',
      entityId: record.id,
      action: 'update',
      summary: 'Document metadata updated',
      newValues: record.toMap(),
      parentEntityType: parentPropertyId == null ? null : 'property',
      parentEntityId: parentPropertyId,
    );
  }

  Future<void> deleteMetadata({
    required String documentId,
    required String key,
  }) async {
    final before = await _db.query(
      'document_metadata',
      where: 'document_id = ? AND key = ?',
      whereArgs: <Object?>[documentId, key],
      limit: 1,
    );
    await _db.delete(
      'document_metadata',
      where: 'document_id = ? AND key = ?',
      whereArgs: <Object?>[documentId, key],
    );
    final parentPropertyId = await _resolvePropertyIdForDocument(documentId);
    await _recordAudit(
      entityType: 'document_metadata',
      entityId: '$documentId:$key',
      action: 'delete',
      summary: 'Document metadata deleted',
      oldValues: before.isEmpty ? null : before.first,
      parentEntityType: parentPropertyId == null ? null : 'property',
      parentEntityId: parentPropertyId,
    );
  }

  Future<List<DocumentWithMetadata>> listDocumentsWithMetadata({
    required String entityType,
    required String entityId,
  }) async {
    final docs = await listDocuments(
      entityType: entityType,
      entityId: entityId,
    );
    final result = <DocumentWithMetadata>[];
    for (final doc in docs) {
      final metadataRows = await listMetadata(doc.id);
      result.add(
        DocumentWithMetadata(
          document: doc,
          metadata: <String, String>{
            for (final row in metadataRows) row.key: row.value,
          },
        ),
      );
    }
    return result;
  }

  Future<List<DocumentComplianceIssue>> checkComplianceForEntity({
    required String entityType,
    required String entityId,
    String? propertyType,
  }) async {
    final requirements = await _requiredRepo.list(
      entityType: entityType,
      propertyType: propertyType,
    );
    final docs = await listDocumentsWithMetadata(
      entityType: entityType,
      entityId: entityId,
    );
    return _complianceEngine.checkEntityCompliance(
      entityType: entityType,
      entityId: entityId,
      requirements: requirements,
      documents: docs,
    );
  }

  Future<String?> _resolvePropertyIdForDocument(String documentId) async {
    final rows = await _db.query(
      'documents',
      columns: const <String>['entity_type', 'entity_id'],
      where: 'id = ?',
      whereArgs: <Object?>[documentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _resolvePropertyIdForEntity(
      rows.first['entity_type']! as String,
      rows.first['entity_id']! as String,
    );
  }

  Future<String?> _resolvePropertyIdForEntity(
    String entityType,
    String entityId,
  ) async {
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
      default:
        return null;
    }
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
    final writer = auditWriter;
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
    await auditLogRepo?.recordEvent(
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

  String _resolveDocumentStatus({
    required Map<String, String> metadata,
    required RequiredDocumentRecord? requirement,
  }) {
    final verifiedRaw =
        metadata['verified'] ??
        metadata['verified_at'] ??
        metadata['checked_at'];
    if (verifiedRaw != null && verifiedRaw.trim().isNotEmpty) {
      return 'verified';
    }
    final expiryKey = requirement?.expiresFieldKey;
    if (expiryKey != null && expiryKey.trim().isNotEmpty) {
      final rawValue = metadata[expiryKey.trim()];
      final parsed = _tryParseDate(rawValue);
      if (parsed != null) {
        final threshold = DateTime.now().add(const Duration(days: 45));
        if (!parsed.isAfter(threshold)) {
          return 'expiring';
        }
      }
    }
    if (requirement?.required == true) {
      return 'available';
    }
    return 'available';
  }

  DateTime? _tryParseDate(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) {
      return null;
    }
    final epoch = int.tryParse(rawValue.trim());
    if (epoch != null) {
      return DateTime.fromMillisecondsSinceEpoch(epoch);
    }
    return DateTime.tryParse(rawValue.trim());
  }

  Future<(String, String)> _resolveDocumentContext(DocumentRecord doc) async {
    switch (doc.entityType) {
      case 'property':
      case 'asset_property':
        final propertyName =
            await _loadPropertyName(doc.entityId) ?? doc.entityId;
        return ('Property', propertyName);
      case 'unit':
        final rows = await _db.query(
          'units',
          columns: const <String>['unit_code', 'asset_property_id'],
          where: 'id = ?',
          whereArgs: <Object?>[doc.entityId],
          limit: 1,
        );
        if (rows.isEmpty) {
          return ('Unit', doc.entityId);
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
          whereArgs: <Object?>[doc.entityId],
          limit: 1,
        );
        if (rows.isEmpty) {
          return ('Lease', doc.entityId);
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
          whereArgs: <Object?>[doc.entityId],
          limit: 1,
        );
        final name =
            rows.isEmpty ? doc.entityId : rows.first['display_name']! as String;
        return ('Tenant', name);
      case 'scenario':
        final rows = await _db.query(
          'scenarios',
          columns: const <String>['name'],
          where: 'id = ?',
          whereArgs: <Object?>[doc.entityId],
          limit: 1,
        );
        final name =
            rows.isEmpty ? doc.entityId : rows.first['name']! as String;
        return ('Scenario', name);
      default:
        return (doc.entityType, doc.entityId);
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
}
