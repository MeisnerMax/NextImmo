import 'package:uuid/uuid.dart';

import '../application/document_migration_dry_run.dart';
import '../domain/document_dto.dart';
import 'legacy_sqlite_document_repository_adapter.dart';

/// Read-only, deterministic dry-run mapper (P2-D03 step 7, MIG-BND-003): legacy
/// document_types / documents / required_documents / property_document_checklist
/// rows project onto the canonical documents_compliance schema with UUIDv5
/// target ids and SHA-256 reconciliation. It never mutates the source, never
/// uploads anything and never emits a published row.
///
/// Content binding is the part that differs from P2-D02. A legacy document
/// points at a local `file_path`; the cloud row points at an object in the
/// private bucket. The mapper therefore hashes the source bytes (via the
/// snapshot's [DocumentContentProbe]s), computes the deterministic target object
/// path, and only calls a document's content link switchable once the object at
/// that path is proven byte-identical ([DocumentContentLinkState.verified]).
/// Every emitted document is `uploaded` with a null `content_confirmed_at`:
/// publishing stays the server's job via `confirm_document_content`, which
/// re-checks storage itself.
class SqliteToPostgresDocumentsComplianceDryRunMapper {
  const SqliteToPostgresDocumentsComplianceDryRunMapper();

  /// Namespace of the P1-012 property mapper. Document links must point at the
  /// property row that migration produced, not at the legacy id, so the two
  /// derivations have to agree exactly.
  static const String propertyIdNamespace = 'neximmo/p1-012/property/';

  static const String _defaultMimeType = 'application/octet-stream';
  static const String _fallbackFilename = 'datei';
  static const String _defaultWaiverReason =
      'Legacy-Checkliste: als nicht relevant markiert';

  DocumentMigrationDryRunReport map({
    required DocumentMigrationSourceSnapshot snapshot,
    required DocumentMigrationDryRunRequest request,
    DocumentMigrationAbortSignal abortSignal =
        const NeverAbortDocumentMigration(),
  }) {
    final issues = <DocumentMigrationIssue>[];
    final mappings = <DocumentMigrationMapping>[];
    final requestValid = _validateRequest(request, issues);
    var aborted = abortSignal.isAborted;

    final documentTypeRows = _sortedRows(snapshot.documentTypes);
    final documentRows = _sortedRows(snapshot.documents);
    final requirementRows = _sortedRows(snapshot.requiredDocuments);
    final checklistRows = _sortedRows(snapshot.checklistEntries);

    // Target ids are derived from the target workspace id, so the index can
    // only be built once the request itself is known to be valid. An invalid
    // request rejects every row before the index is ever consulted.
    final typeIndex = requestValid
        ? _buildTypeIndex(documentTypeRows, request)
        : const _TypeIndex(
            byLegacyId: <String, _ResolvedType>{},
            keysClaimedByLegacyTypes: <String>{},
          );
    final metadata = _metadataByDocument(snapshot.documentMetadata);
    final expiryFields = _expiryFieldsByTypeAndEntity(requirementRows);
    final context = _MappingContext(
      request: request,
      typeIndex: typeIndex,
      metadataByDocument: metadata,
      expiryFieldByTypeAndEntity: expiryFields,
      contentProbes: snapshot.contentProbes,
      uploadedObjects: snapshot.uploadedObjects,
    );

    final specs = <(DocumentMigrationEntity, List<Map<String, Object?>>)>[
      (DocumentMigrationEntity.documentType, documentTypeRows),
      (DocumentMigrationEntity.document, documentRows),
      (DocumentMigrationEntity.requiredDocument, requirementRows),
      (DocumentMigrationEntity.checklistEntry, checklistRows),
    ];

    final summaries = <DocumentMigrationEntitySummary>[];
    for (final spec in specs) {
      final result = _processEntity(
        entity: spec.$1,
        rows: spec.$2,
        bindingValid: requestValid,
        alreadyAborted: aborted,
        abortSignal: abortSignal,
        context: context,
      );
      aborted = aborted || result.aborted;
      issues.addAll(result.issues);
      mappings.addAll(result.mappings);
      summaries.add(result.summary);
    }

    if (aborted) {
      issues.add(
        const DocumentMigrationIssue(
          code: 'run.aborted',
          severity: DocumentMigrationIssueSeverity.warning,
        ),
      );
    }

    mappings.sort(_compareMappings);
    issues.sort(_compareIssues);

    final hasErrors = issues.any(
      (issue) => issue.severity == DocumentMigrationIssueSeverity.error,
    );
    final status = aborted
        ? DocumentMigrationStatus.aborted
        : hasErrors ||
              summaries.any(
                (summary) =>
                    !summary.countsReconcile || !summary.checksumsReconcile,
              )
        ? DocumentMigrationStatus.invalid
        : DocumentMigrationStatus.ready;

    final unsigned = DocumentMigrationDryRunReport(
      status: status,
      request: request,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: '',
    );
    return unsigned.withManifestChecksum(
      documentMigrationChecksum(
        unsigned.toCanonicalMap(includeManifestChecksum: false),
      ),
    );
  }

  _EntityResult _processEntity({
    required DocumentMigrationEntity entity,
    required List<Map<String, Object?>> rows,
    required bool bindingValid,
    required bool alreadyAborted,
    required DocumentMigrationAbortSignal abortSignal,
    required _MappingContext context,
  }) {
    final issues = <DocumentMigrationIssue>[];
    final mappings = <DocumentMigrationMapping>[];
    final targets = <Map<String, Object?>>[];
    final sourceProjections = <Map<String, Object?>>[];
    final targetProjections = <Map<String, Object?>>[];
    var processed = 0;
    var mapped = 0;
    var rejected = 0;
    var aborted = alreadyAborted;

    if (!aborted) {
      for (final row in rows) {
        if (abortSignal.isAborted) {
          aborted = true;
          break;
        }
        processed++;
        if (!bindingValid) {
          rejected++;
          continue;
        }
        final result = _mapRow(entity, row, context);
        issues.addAll(result.issues);
        if (result.target == null) {
          rejected++;
          continue;
        }
        mapped++;
        targets.add(result.target!);
        sourceProjections.add(result.sourceProjection!);
        targetProjections.add(result.targetProjection!);
        mappings.add(
          DocumentMigrationMapping(
            entity: entity,
            sourceId: result.sourceId!,
            targetId: result.targetId!,
            targetChildId: result.targetChildId,
            sourceChecksum: documentMigrationChecksum(row),
            targetChecksum: documentMigrationChecksum(result.target),
            contentLink: result.contentLink,
            storageObjectPath: result.storageObjectPath,
          ),
        );
      }
    }

    return _EntityResult(
      aborted: aborted,
      issues: issues,
      mappings: mappings,
      summary: _summary(
        entity: entity,
        sourceRowsData: rows,
        processedRows: processed,
        mappedRows: mapped,
        rejectedRows: rejected,
        targets: targets,
        sourceProjections: sourceProjections,
        targetProjections: targetProjections,
        entityIssues: issues,
        aborted: aborted,
      ),
    );
  }

  _MappedRow _mapRow(
    DocumentMigrationEntity entity,
    Map<String, Object?> row,
    _MappingContext context,
  ) {
    switch (entity) {
      case DocumentMigrationEntity.documentType:
        return _mapDocumentType(row, context);
      case DocumentMigrationEntity.document:
        return _mapDocument(row, context);
      case DocumentMigrationEntity.requiredDocument:
        return _mapRequiredDocument(row, context);
      case DocumentMigrationEntity.checklistEntry:
        return _mapChecklistEntry(row, context);
    }
  }

  // --- document_types ---------------------------------------------------

  _MappedRow _mapDocumentType(Map<String, Object?> row, _MappingContext ctx) {
    final issues = <DocumentMigrationIssue>[];
    const entity = DocumentMigrationEntity.documentType;
    final sourceId = _validatedSourceId(row, entity, issues);
    final name = _requiredText(
      row,
      key: 'name',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final createdAt = _timestamp(
      row,
      key: 'created_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    _flagExcludedFields(row, entity, sourceId, issues, const <String>[
      'required_fields_json',
    ]);

    final resolved = sourceId == null ? null : ctx.typeIndex.byLegacyId[sourceId];
    if (resolved != null && !resolved.entityTypeMappable) {
      // The cloud column is a controlled registry and NOT NULL; inventing a
      // scope for free text would be worse than rejecting the row.
      issues.add(
        _fieldError(
          'source.unmapped_entity_type',
          entity,
          sourceId,
          'entity_type',
        ),
      );
    }
    if (resolved != null && !resolved.keyUnique) {
      issues.add(
        _fieldError('mapping.type_key_collision', entity, sourceId, 'name'),
      );
    }
    if (resolved != null && !resolved.keyValid) {
      issues.add(
        _fieldError('mapping.invalid_type_key', entity, sourceId, 'name'),
      );
    }

    if (_hasErrors(issues) ||
        sourceId == null ||
        name == null ||
        createdAt == null ||
        resolved == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }

    issues.add(
      _fieldWarning('mapping.id_derived_uuid_v5', entity, sourceId, 'id'),
    );
    if (resolved.key != name.toLowerCase()) {
      issues.add(
        _fieldWarning('mapping.type_key_slugified', entity, sourceId, 'name'),
      );
    }

    final target = <String, Object?>{
      'document_type': <String, Object?>{
        'id': resolved.targetId,
        'workspace_id': ctx.request.targetWorkspaceId,
        'key': resolved.key,
        'name': name,
        'entity_type': resolved.entityType!.wireName,
        'default_validity_months': null,
        'is_active': true,
        'created_at': createdAt,
        'updated_at': createdAt,
        'created_by': ctx.request.migrationActorId,
        'updated_by': ctx.request.migrationActorId,
        'version': 1,
      },
    };

    final identity = <String, Object?>{
      'source_id': sourceId,
      'key': resolved.key,
      'name': name,
      'entity_type': resolved.entityType!.wireName,
    };
    return _MappedRow(
      sourceId: sourceId,
      targetId: resolved.targetId,
      target: target,
      sourceProjection: identity,
      targetProjection: <String, Object?>{
        'source_id': sourceId,
        'key': (target['document_type']! as Map)['key'],
        'name': (target['document_type']! as Map)['name'],
        'entity_type': (target['document_type']! as Map)['entity_type'],
      },
      issues: issues,
    );
  }

  // --- documents --------------------------------------------------------

  _MappedRow _mapDocument(Map<String, Object?> row, _MappingContext ctx) {
    final issues = <DocumentMigrationIssue>[];
    const entity = DocumentMigrationEntity.document;
    final sourceId = _validatedSourceId(row, entity, issues);
    final fileName = _requiredText(
      row,
      key: 'file_name',
      maxLength: 255,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final filePath = _requiredText(
      row,
      key: 'file_path',
      maxLength: 4000,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final legacyEntityType = _requiredText(
      row,
      key: 'entity_type',
      maxLength: 100,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final legacyEntityId = _requiredText(
      row,
      key: 'entity_id',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final createdAt = _timestamp(
      row,
      key: 'created_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final updatedAt = _timestamp(
      row,
      key: 'updated_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );

    // A legacy document may reference a type that itself failed to map; the
    // document survives without a type rather than dragging the failure along.
    String? documentTypeId;
    final rawTypeId = (row['type_id'] as String?)?.trim();
    if (rawTypeId != null && rawTypeId.isNotEmpty) {
      final resolved = ctx.typeIndex.byLegacyId[rawTypeId];
      if (resolved == null || !resolved.usable) {
        issues.add(
          _fieldWarning(
            'mapping.document_type_dropped',
            entity,
            sourceId,
            'type_id',
          ),
        );
      } else {
        documentTypeId = resolved.targetId;
      }
    }

    if ((row['created_by'] as String?)?.trim().isNotEmpty ?? false) {
      // Legacy actors are local free-text ids; the cloud columns are uuids.
      issues.add(
        _fieldWarning('mapping.actor_replaced', entity, sourceId, 'created_by'),
      );
    }

    if (_hasErrors(issues) ||
        sourceId == null ||
        fileName == null ||
        filePath == null ||
        legacyEntityType == null ||
        legacyEntityId == null ||
        createdAt == null ||
        updatedAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }

    // MIG-BND-003 step 1: hash the real local bytes. Without them there is no
    // honest content version to emit at all, so the row is rejected.
    final probe = ctx.contentProbes[filePath];
    if (probe == null || !probe.isReadable) {
      issues.add(
        _fieldError('content.source_missing', entity, sourceId, 'file_path'),
      );
      return _MappedRow(sourceId: sourceId, issues: issues);
    }
    final contentHash = probe.sha256Hex!.toLowerCase();
    final byteSize = probe.byteSize!;

    final declaredHash = (row['sha256'] as String?)?.trim().toLowerCase();
    if (declaredHash == null || declaredHash.isEmpty) {
      issues.add(
        _fieldWarning('content.source_hash_absent', entity, sourceId, 'sha256'),
      );
    } else if (declaredHash != contentHash) {
      // The legacy row and the bytes disagree — never guess which one is right.
      issues.add(
        _fieldError('content.hash_mismatch', entity, sourceId, 'sha256'),
      );
      return _MappedRow(sourceId: sourceId, issues: issues);
    }
    final declaredSize = (row['size_bytes'] as num?)?.toInt();
    if (declaredSize != null && declaredSize != byteSize) {
      issues.add(
        _fieldWarning(
          'content.source_size_mismatch',
          entity,
          sourceId,
          'size_bytes',
        ),
      );
    }

    final documentId = const Uuid().v5(
      ctx.request.targetWorkspaceId,
      'neximmo/p2-d03/document/$sourceId',
    );
    final versionId = const Uuid().v5(
      ctx.request.targetWorkspaceId,
      'neximmo/p2-d03/document_version/$sourceId/1',
    );
    issues.add(
      _fieldWarning('mapping.id_derived_uuid_v5', entity, sourceId, 'id'),
    );

    final segment = _storageSegment(fileName);
    if (segment != fileName) {
      issues.add(
        _fieldWarning('mapping.filename_sanitized', entity, sourceId, 'file_name'),
      );
    }
    final storageObjectPath =
        '${ctx.request.targetWorkspaceId}/$documentId/1/$segment';

    // MIG-BND-003 step 2: verify the upload against the hash before the content
    // link is considered switchable.
    final contentLink = _verifyUpload(
      storageObjectPath: storageObjectPath,
      contentHash: contentHash,
      byteSize: byteSize,
      uploadedObjects: ctx.uploadedObjects,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );

    var mimeType = (row['mime_type'] as String?)?.trim();
    if (mimeType == null || mimeType.length < 3 || mimeType.length > 255) {
      if (mimeType != null && mimeType.isNotEmpty) {
        issues.add(
          _fieldWarning('source.invalid_mime_type', entity, sourceId, 'mime_type'),
        );
      } else {
        issues.add(
          _fieldWarning(
            'mapping.mime_type_defaulted',
            entity,
            sourceId,
            'mime_type',
          ),
        );
      }
      mimeType = _defaultMimeType;
    }

    final validUntil = _validUntilOf(row, ctx, legacyEntityType, rawTypeId);

    final linkEntityType = DocumentLinkEntityType.fromWire(legacyEntityType);
    Map<String, Object?>? link;
    if (linkEntityType == null) {
      issues.add(
        _fieldWarning(
          'mapping.entity_type_not_mapped',
          entity,
          sourceId,
          'entity_type',
        ),
      );
    } else if (linkEntityType != DocumentLinkEntityType.property) {
      // Deriving an id for another domain means adopting that domain's own
      // migration namespace; doing it here would invent dangling references.
      issues.add(
        _fieldWarning(
          'mapping.link_not_derivable',
          entity,
          sourceId,
          'entity_id',
        ),
      );
    } else {
      issues.add(
        _fieldWarning(
          'mapping.entity_id_derived_from_p1_012',
          entity,
          sourceId,
          'entity_id',
        ),
      );
      link = <String, Object?>{
        'id': const Uuid().v5(
          ctx.request.targetWorkspaceId,
          'neximmo/p2-d03/document_link/$sourceId',
        ),
        'workspace_id': ctx.request.targetWorkspaceId,
        'document_id': documentId,
        'entity_type': DocumentLinkEntityType.property.wireName,
        'entity_id': migratedPropertyId(
          ctx.request.targetWorkspaceId,
          legacyEntityId,
        ),
        'link_role': null,
        'created_at': createdAt,
        'created_by': ctx.request.migrationActorId,
      };
    }

    issues.add(
      _fieldWarning('mapping.title_from_file_name', entity, sourceId, 'title'),
    );

    final target = <String, Object?>{
      'document': <String, Object?>{
        'id': documentId,
        'workspace_id': ctx.request.targetWorkspaceId,
        'document_type_id': documentTypeId,
        'title': fileName,
        // Never `available`: publishing stays with confirm_document_content,
        // which re-verifies storage server-side.
        'status': DocumentStatus.uploaded.wireName,
        'current_version_no': 1,
        'valid_from': null,
        'valid_until': validUntil,
        'retention_until': null,
        'superseded_by_document_id': null,
        'archived_at': null,
        'notes': null,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'created_by': ctx.request.migrationActorId,
        'updated_by': ctx.request.migrationActorId,
        'version': 1,
      },
      'document_version': <String, Object?>{
        'id': versionId,
        'workspace_id': ctx.request.targetWorkspaceId,
        'document_id': documentId,
        'version_no': 1,
        'storage_bucket': documentMigrationStorageBucket,
        'storage_object_path': storageObjectPath,
        'content_hash': contentHash,
        'byte_size': byteSize,
        'mime_type': mimeType,
        'original_filename': fileName,
        // The content link is never pre-confirmed by the dry run.
        'content_confirmed_at': null,
        'verification_status': DocumentVerificationStatus.pending.wireName,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'created_by': ctx.request.migrationActorId,
        'updated_by': ctx.request.migrationActorId,
        'version': 1,
      },
      'document_link': link,
    };

    final identity = <String, Object?>{
      'source_id': sourceId,
      'title': fileName,
      'content_hash': contentHash,
      'byte_size': byteSize,
      'document_type_id': documentTypeId,
      'valid_until': validUntil,
      'link_entity_id': link?['entity_id'],
    };
    final documentTarget = target['document']! as Map<String, Object?>;
    final versionTarget = target['document_version']! as Map<String, Object?>;
    return _MappedRow(
      sourceId: sourceId,
      targetId: documentId,
      targetChildId: versionId,
      target: target,
      sourceProjection: identity,
      targetProjection: <String, Object?>{
        'source_id': sourceId,
        'title': documentTarget['title'],
        'content_hash': versionTarget['content_hash'],
        'byte_size': versionTarget['byte_size'],
        'document_type_id': documentTarget['document_type_id'],
        'valid_until': documentTarget['valid_until'],
        'link_entity_id': link?['entity_id'],
      },
      contentLink: contentLink,
      storageObjectPath: storageObjectPath,
      issues: issues,
    );
  }

  DocumentContentLinkState _verifyUpload({
    required String storageObjectPath,
    required String contentHash,
    required int byteSize,
    required Map<String, DocumentObjectProbe> uploadedObjects,
    required DocumentMigrationEntity entity,
    required String sourceId,
    required List<DocumentMigrationIssue> issues,
  }) {
    final object = uploadedObjects[storageObjectPath];
    if (object == null) {
      issues.add(
        _fieldError(
          'content.upload_missing',
          entity,
          sourceId,
          'storage_object_path',
        ),
      );
      return DocumentContentLinkState.uploadMissing;
    }
    if (object.byteSize != byteSize) {
      issues.add(
        _fieldError(
          'content.upload_size_mismatch',
          entity,
          sourceId,
          'byte_size',
        ),
      );
      return DocumentContentLinkState.uploadMismatch;
    }
    final uploadedHash = object.sha256Hex?.trim().toLowerCase();
    if (uploadedHash == null || uploadedHash.isEmpty) {
      // Size equality alone does not prove byte identity, and Storage exposes
      // no SHA-256 of its own — so this stays unauthorized by design.
      issues.add(
        _fieldError(
          'content.upload_not_hashed',
          entity,
          sourceId,
          'content_hash',
        ),
      );
      return DocumentContentLinkState.uploadUnhashed;
    }
    if (uploadedHash != contentHash) {
      issues.add(
        _fieldError(
          'content.upload_hash_mismatch',
          entity,
          sourceId,
          'content_hash',
        ),
      );
      return DocumentContentLinkState.uploadMismatch;
    }
    return DocumentContentLinkState.verified;
  }

  // --- required_documents -----------------------------------------------

  _MappedRow _mapRequiredDocument(
    Map<String, Object?> row,
    _MappingContext ctx,
  ) {
    final issues = <DocumentMigrationIssue>[];
    const entity = DocumentMigrationEntity.requiredDocument;
    final sourceId = _validatedSourceId(row, entity, issues);
    final legacyEntityType = _requiredText(
      row,
      key: 'entity_type',
      maxLength: 100,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final createdAt = _timestamp(
      row,
      key: 'created_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final scopeKey = _optionalText(
      row,
      key: 'property_type',
      maxLength: 100,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    _flagExcludedFields(row, entity, sourceId, issues, const <String>[
      // Consumed to derive document validity, but the cloud rule stores
      // validity_months, not a metadata key.
      'expires_field_key',
    ]);

    final entityType = legacyEntityType == null
        ? null
        : DocumentLinkEntityType.fromWire(legacyEntityType);
    if (legacyEntityType != null && entityType == null) {
      issues.add(
        _fieldError(
          'source.unmapped_entity_type',
          entity,
          sourceId,
          'entity_type',
        ),
      );
    }

    final rawTypeId = (row['type_id'] as String?)?.trim();
    final resolvedType = rawTypeId == null || rawTypeId.isEmpty
        ? null
        : ctx.typeIndex.byLegacyId[rawTypeId];
    if (resolvedType == null || !resolvedType.usable) {
      // document_type_id is NOT NULL on the cloud rule.
      issues.add(
        _fieldError(
          'source.unresolved_document_type',
          entity,
          sourceId,
          'type_id',
        ),
      );
    }

    if (_hasErrors(issues) ||
        sourceId == null ||
        entityType == null ||
        resolvedType == null ||
        createdAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }

    final targetId = const Uuid().v5(
      ctx.request.targetWorkspaceId,
      'neximmo/p2-d03/required_document/$sourceId',
    );
    issues.add(
      _fieldWarning('mapping.id_derived_uuid_v5', entity, sourceId, 'id'),
    );

    final target = <String, Object?>{
      'required_document': <String, Object?>{
        'id': targetId,
        'workspace_id': ctx.request.targetWorkspaceId,
        'entity_type': entityType.wireName,
        // Legacy rules are type-level only; instance requirements come from the
        // checklist below.
        'entity_id': null,
        'scope_key': scopeKey,
        'document_type_id': resolvedType.targetId,
        'is_mandatory': (row['required'] as num?)?.toInt() != 0,
        'due_at': null,
        'validity_months': null,
        'owner_user_id': null,
        'note': null,
        'requested_at': null,
        'waived_at': null,
        'waived_by': null,
        'waiver_reason': null,
        'retired_at': null,
        'created_at': createdAt,
        'updated_at': createdAt,
        'created_by': ctx.request.migrationActorId,
        'updated_by': ctx.request.migrationActorId,
        'version': 1,
      },
    };
    final rule = target['required_document']! as Map<String, Object?>;
    final identity = <String, Object?>{
      'source_id': sourceId,
      'entity_type': entityType.wireName,
      'scope_key': scopeKey,
      'document_type_id': resolvedType.targetId,
      'is_mandatory': rule['is_mandatory'],
    };
    return _MappedRow(
      sourceId: sourceId,
      targetId: targetId,
      target: target,
      sourceProjection: identity,
      targetProjection: <String, Object?>{
        'source_id': sourceId,
        'entity_type': rule['entity_type'],
        'scope_key': rule['scope_key'],
        'document_type_id': rule['document_type_id'],
        'is_mandatory': rule['is_mandatory'],
      },
      issues: issues,
    );
  }

  // --- property_document_checklist (DUP-011) -----------------------------

  _MappedRow _mapChecklistEntry(Map<String, Object?> row, _MappingContext ctx) {
    final issues = <DocumentMigrationIssue>[];
    const entity = DocumentMigrationEntity.checklistEntry;
    final sourceId = _validatedSourceId(row, entity, issues);
    final propertyId = _requiredText(
      row,
      key: 'property_id',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final documentKey = _requiredText(
      row,
      key: 'document_key',
      maxLength: 100,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final label = _requiredText(
      row,
      key: 'label',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final status = _requiredText(
      row,
      key: 'status',
      maxLength: 50,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final note = _optionalText(
      row,
      key: 'note',
      maxLength: 4000,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final createdAt = _timestamp(
      row,
      key: 'created_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final updatedAt = _timestamp(
      row,
      key: 'updated_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    _flagExcludedFields(row, entity, sourceId, issues, const <String>[
      // Free text, while owner_user_id is a uuid.
      'owner',
      // A second local file reference with no row in `documents`; naming the
      // gap beats inventing a document for it.
      'upload_path',
    ]);

    final typeKey = documentKey == null
        ? null
        : LegacySqliteDocumentRepositoryAdapter.typeKeyFor(documentKey);
    if (typeKey != null && !_isValidTypeKey(typeKey)) {
      issues.add(
        _fieldError(
          'mapping.invalid_type_key',
          entity,
          sourceId,
          'document_key',
        ),
      );
    }
    if (status != null && !_checklistStates.contains(status)) {
      issues.add(
        _fieldError('source.unknown_checklist_status', entity, sourceId, 'status'),
      );
    }

    if (_hasErrors(issues) ||
        sourceId == null ||
        propertyId == null ||
        documentKey == null ||
        label == null ||
        status == null ||
        typeKey == null ||
        createdAt == null ||
        updatedAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }

    // One synthesized type per distinct checklist key, deterministic across
    // properties: `upsert_document_type` keys on (workspace, key), so repeated
    // rows converge on the same type instead of colliding.
    final typeId = const Uuid().v5(
      ctx.request.targetWorkspaceId,
      'neximmo/p2-d03/document_type/checklist/$documentKey',
    );
    if (ctx.typeIndex.keysClaimedByLegacyTypes.contains(typeKey)) {
      issues.add(
        _fieldWarning(
          'mapping.checklist_type_key_shared',
          entity,
          sourceId,
          'document_key',
        ),
      );
    } else {
      issues.add(
        _fieldWarning(
          'mapping.checklist_type_synthesized',
          entity,
          sourceId,
          'document_key',
        ),
      );
    }

    final requirementId = const Uuid().v5(
      ctx.request.targetWorkspaceId,
      'neximmo/p2-d03/required_document/checklist/$sourceId',
    );
    issues.add(
      _fieldWarning('mapping.id_derived_uuid_v5', entity, sourceId, 'id'),
    );
    issues.add(
      _fieldWarning(
        'mapping.entity_id_derived_from_p1_012',
        entity,
        sourceId,
        'property_id',
      ),
    );

    // The lossless DUP-011 union: "angefordert" and "nicht_relevant" carry
    // state, while "vorhanden"/"fehlt" are derived per read and never stored.
    final requestedAt = status == 'angefordert' ? updatedAt : null;
    final waivedAt = status == 'nicht_relevant' ? updatedAt : null;

    final target = <String, Object?>{
      'document_type': <String, Object?>{
        'id': typeId,
        'workspace_id': ctx.request.targetWorkspaceId,
        'key': typeKey,
        'name': label,
        'entity_type': DocumentLinkEntityType.property.wireName,
        'default_validity_months': null,
        'is_active': true,
        'created_at': createdAt,
        'updated_at': createdAt,
        'created_by': ctx.request.migrationActorId,
        'updated_by': ctx.request.migrationActorId,
        'version': 1,
      },
      'required_document': <String, Object?>{
        'id': requirementId,
        'workspace_id': ctx.request.targetWorkspaceId,
        'entity_type': DocumentLinkEntityType.property.wireName,
        'entity_id': migratedPropertyId(
          ctx.request.targetWorkspaceId,
          propertyId,
        ),
        'scope_key': null,
        'document_type_id': typeId,
        'is_mandatory': true,
        'due_at': _optionalDate(row, 'due_date'),
        'validity_months': null,
        'owner_user_id': null,
        'note': note,
        'requested_at': requestedAt,
        'waived_at': waivedAt,
        'waived_by': waivedAt == null ? null : ctx.request.migrationActorId,
        'waiver_reason': waivedAt == null
            ? null
            : (note ?? _defaultWaiverReason),
        'retired_at': null,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'created_by': ctx.request.migrationActorId,
        'updated_by': ctx.request.migrationActorId,
        'version': 1,
      },
    };

    final rule = target['required_document']! as Map<String, Object?>;
    final identity = <String, Object?>{
      'source_id': sourceId,
      'document_key': typeKey,
      'label': label,
      'entity_id': rule['entity_id'],
      'requested': requestedAt != null,
      'waived': waivedAt != null,
    };
    return _MappedRow(
      sourceId: sourceId,
      targetId: requirementId,
      targetChildId: typeId,
      target: target,
      sourceProjection: identity,
      targetProjection: <String, Object?>{
        'source_id': sourceId,
        'document_key': (target['document_type']! as Map)['key'],
        'label': (target['document_type']! as Map)['name'],
        'entity_id': rule['entity_id'],
        'requested': rule['requested_at'] != null,
        'waived': rule['waived_at'] != null,
      },
      issues: issues,
    );
  }

  // --- shared -----------------------------------------------------------

  /// The P1-012-derived id of a migrated property. Document links have to point
  /// at the row that migration produced.
  static String migratedPropertyId(
    String targetWorkspaceId,
    String legacyPropertyId,
  ) => const Uuid().v5(targetWorkspaceId, '$propertyIdNamespace$legacyPropertyId');

  _TypeIndex _buildTypeIndex(
    List<Map<String, Object?>> rows,
    DocumentMigrationDryRunRequest request,
  ) {
    final keyOwners = <String, int>{};
    final entries = <String, _ResolvedType>{};
    final drafts = <(String, String, DocumentLinkEntityType?, bool)>[];

    for (final row in rows) {
      final sourceId = row['id'];
      final name = row['name'];
      if (sourceId is! String || sourceId.isEmpty || name is! String) {
        continue;
      }
      final key = LegacySqliteDocumentRepositoryAdapter.typeKeyFor(name);
      final entityType = DocumentLinkEntityType.fromWire(
        (row['entity_type'] as String?)?.trim(),
      );
      keyOwners[key] = (keyOwners[key] ?? 0) + 1;
      drafts.add((sourceId, key, entityType, _isValidTypeKey(key)));
    }

    for (final draft in drafts) {
      entries[draft.$1] = _ResolvedType(
        targetId: const Uuid().v5(
          request.targetWorkspaceId,
          'neximmo/p2-d03/document_type/${draft.$1}',
        ),
        key: draft.$2,
        entityType: draft.$3,
        keyUnique: (keyOwners[draft.$2] ?? 0) == 1,
        keyValid: draft.$4,
      );
    }
    return _TypeIndex(
      byLegacyId: entries,
      keysClaimedByLegacyTypes: keyOwners.keys.toSet(),
    );
  }

  Map<String, Map<String, String>> _metadataByDocument(
    List<Map<String, Object?>> rows,
  ) {
    final result = <String, Map<String, String>>{};
    for (final row in rows) {
      final documentId = row['document_id'];
      final key = row['key'];
      final value = row['value'];
      if (documentId is! String || key is! String || value is! String) {
        continue;
      }
      (result[documentId] ??= <String, String>{})[key] = value;
    }
    return result;
  }

  /// `entity_type|type_id` -> the expiry metadata key its rules declare. More
  /// than one distinct key is resolved deterministically (lexicographically
  /// smallest) and flagged where it is used.
  Map<String, List<String>> _expiryFieldsByTypeAndEntity(
    List<Map<String, Object?>> rows,
  ) {
    final result = <String, Set<String>>{};
    for (final row in rows) {
      final entityType = (row['entity_type'] as String?)?.trim();
      final typeId = (row['type_id'] as String?)?.trim();
      final field = (row['expires_field_key'] as String?)?.trim();
      if (entityType == null || typeId == null || field == null || field.isEmpty) {
        continue;
      }
      (result['$entityType|$typeId'] ??= <String>{}).add(field);
    }
    return <String, List<String>>{
      for (final entry in result.entries)
        entry.key: entry.value.toList(growable: false)..sort(),
    };
  }

  String? _validUntilOf(
    Map<String, Object?> row,
    _MappingContext ctx,
    String legacyEntityType,
    String? rawTypeId,
  ) {
    if (rawTypeId == null || rawTypeId.isEmpty) {
      return null;
    }
    final fields = ctx.expiryFieldByTypeAndEntity['$legacyEntityType|$rawTypeId'];
    if (fields == null || fields.isEmpty) {
      return null;
    }
    final documentId = row['id'];
    if (documentId is! String) {
      return null;
    }
    final metadata = ctx.metadataByDocument[documentId];
    if (metadata == null) {
      return null;
    }
    for (final field in fields) {
      final parsed = _tryParseLegacyDate(metadata[field]);
      if (parsed != null) {
        return _asDate(parsed);
      }
    }
    return null;
  }

  DocumentMigrationEntitySummary _summary({
    required DocumentMigrationEntity entity,
    required List<Map<String, Object?>> sourceRowsData,
    required int processedRows,
    required int mappedRows,
    required int rejectedRows,
    required List<Map<String, Object?>> targets,
    required List<Map<String, Object?>> sourceProjections,
    required List<Map<String, Object?>> targetProjections,
    required List<DocumentMigrationIssue> entityIssues,
    required bool aborted,
  }) {
    final sourceRows = sourceRowsData.length;
    final errorCount = entityIssues
        .where((issue) => issue.severity == DocumentMigrationIssueSeverity.error)
        .length;
    final warningCount = entityIssues
        .where(
          (issue) => issue.severity == DocumentMigrationIssueSeverity.warning,
        )
        .length;
    if (aborted) {
      return DocumentMigrationEntitySummary(
        entity: entity,
        sourceRows: sourceRows,
        processedRows: processedRows,
        mappedRows: mappedRows,
        rejectedRows: rejectedRows,
        errorCount: errorCount,
        warningCount: warningCount,
        sourceChecksum: null,
        candidateChecksum: null,
        reconciliationChecksum: null,
        checksumsReconcile: false,
      );
    }
    final sourceReconciliation = documentMigrationChecksum(
      _sortProjectionRows(sourceProjections),
    );
    final targetReconciliation = documentMigrationChecksum(
      _sortProjectionRows(targetProjections),
    );
    return DocumentMigrationEntitySummary(
      entity: entity,
      sourceRows: sourceRows,
      processedRows: processedRows,
      mappedRows: mappedRows,
      rejectedRows: rejectedRows,
      errorCount: errorCount,
      warningCount: warningCount,
      sourceChecksum: documentMigrationChecksum(sourceRowsData),
      candidateChecksum: documentMigrationChecksum(
        _sortProjectionRows(targets),
      ),
      reconciliationChecksum: sourceReconciliation,
      checksumsReconcile: sourceReconciliation == targetReconciliation,
    );
  }

  bool _validateRequest(
    DocumentMigrationDryRunRequest request,
    List<DocumentMigrationIssue> issues,
  ) {
    var valid = true;
    if (request.sourceWorkspaceId.isEmpty ||
        request.sourceWorkspaceId.trim() != request.sourceWorkspaceId) {
      issues.add(
        const DocumentMigrationIssue(
          code: 'request.invalid_source_workspace_id',
          severity: DocumentMigrationIssueSeverity.error,
        ),
      );
      valid = false;
    }
    for (final entry in <MapEntry<String, String>>[
      MapEntry('request.invalid_target_workspace_id', request.targetWorkspaceId),
      MapEntry('request.invalid_migration_actor_id', request.migrationActorId),
    ]) {
      if (!Uuid.isValidUUID(fromString: entry.value)) {
        issues.add(
          DocumentMigrationIssue(
            code: entry.key,
            severity: DocumentMigrationIssueSeverity.error,
          ),
        );
        valid = false;
      }
    }
    if (!_normalizedKey.hasMatch(request.targetWorkspaceKey)) {
      issues.add(
        const DocumentMigrationIssue(
          code: 'request.invalid_target_workspace_key',
          severity: DocumentMigrationIssueSeverity.error,
        ),
      );
      valid = false;
    }
    return valid;
  }

  String? _validatedSourceId(
    Map<String, Object?> row,
    DocumentMigrationEntity entity,
    List<DocumentMigrationIssue> issues,
  ) {
    final value = row['id'];
    if (value is! String || value.isEmpty || value.trim() != value) {
      issues.add(_fieldError('source.invalid_id', entity, null, 'id'));
      return null;
    }
    return value;
  }

  String? _requiredText(
    Map<String, Object?> row, {
    required String key,
    required int maxLength,
    required DocumentMigrationEntity entity,
    required String? sourceId,
    required List<DocumentMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      issues.add(
        _fieldError('source.required_value_missing', entity, sourceId, key),
      );
      return null;
    }
    final normalized = value.trim();
    if (normalized.length > maxLength) {
      issues.add(_fieldError('source.text_too_long', entity, sourceId, key));
      return null;
    }
    if (normalized != value) {
      issues.add(_fieldWarning('mapping.text_trimmed', entity, sourceId, key));
    }
    return normalized;
  }

  String? _optionalText(
    Map<String, Object?> row, {
    required String key,
    required int maxLength,
    required DocumentMigrationEntity entity,
    required String? sourceId,
    required List<DocumentMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      issues.add(_fieldError('source.invalid_text', entity, sourceId, key));
      return null;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      issues.add(
        _fieldWarning('mapping.empty_text_to_null', entity, sourceId, key),
      );
      return null;
    }
    if (normalized.length > maxLength) {
      issues.add(_fieldError('source.text_too_long', entity, sourceId, key));
      return null;
    }
    if (normalized != value) {
      issues.add(_fieldWarning('mapping.text_trimmed', entity, sourceId, key));
    }
    return normalized;
  }

  String? _timestamp(
    Map<String, Object?> row, {
    required String key,
    required DocumentMigrationEntity entity,
    required String? sourceId,
    required List<DocumentMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      issues.add(
        _fieldError('source.invalid_epoch_millis', entity, sourceId, key),
      );
      return null;
    }
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
        isUtc: true,
      ).toIso8601String();
    } on RangeError {
      issues.add(
        _fieldError('source.invalid_epoch_millis', entity, sourceId, key),
      );
      return null;
    }
  }

  String? _optionalDate(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! num || !value.isFinite) {
      return null;
    }
    return _asDate(
      DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true),
    );
  }

  void _flagExcludedFields(
    Map<String, Object?> row,
    DocumentMigrationEntity entity,
    String? sourceId,
    List<DocumentMigrationIssue> issues,
    List<String> fields,
  ) {
    for (final field in fields) {
      final value = row[field];
      if (value != null && !(value is String && value.trim().isEmpty)) {
        issues.add(
          _fieldWarning('mapping.field_excluded', entity, sourceId, field),
        );
      }
    }
  }

  /// Mirrors `LegacySqliteDocumentRepositoryAdapter.tryParseLegacyDate`: an
  /// expiry is stored either as epoch millis or as an ISO date string.
  static DateTime? _tryParseLegacyDate(String? rawValue) {
    final raw = rawValue?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final epoch = int.tryParse(raw);
    if (epoch != null) {
      return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
    }
    return DateTime.tryParse(raw);
  }

  static String _asDate(DateTime value) {
    final utc = value.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-$month-$day';
  }

  /// Object-path segment for a legacy filename. The cloud check constraint
  /// rejects `..` anywhere in the path, so traversal sequences cannot survive.
  static String _storageSegment(String fileName) {
    final sanitized = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'^[._-]+'), '')
        .replaceAll(RegExp(r'[._-]+$'), '');
    if (sanitized.isEmpty) {
      return _fallbackFilename;
    }
    return sanitized.length > 120 ? sanitized.substring(0, 120) : sanitized;
  }

  static bool _isValidTypeKey(String key) =>
      key.length >= 2 && key.length <= 100 && _normalizedKey.hasMatch(key);

  static DocumentMigrationIssue _fieldError(
    String code,
    DocumentMigrationEntity entity,
    String? sourceId,
    String field,
  ) => DocumentMigrationIssue(
    code: code,
    severity: DocumentMigrationIssueSeverity.error,
    entity: entity,
    sourceId: sourceId,
    field: field,
  );

  static DocumentMigrationIssue _fieldWarning(
    String code,
    DocumentMigrationEntity entity,
    String? sourceId,
    String field,
  ) => DocumentMigrationIssue(
    code: code,
    severity: DocumentMigrationIssueSeverity.warning,
    entity: entity,
    sourceId: sourceId,
    field: field,
  );

  bool _hasErrors(List<DocumentMigrationIssue> issues) => issues.any(
    (issue) => issue.severity == DocumentMigrationIssueSeverity.error,
  );
}

/// The four legacy checklist states (DUP-011).
const Set<String> _checklistStates = <String>{
  'vorhanden',
  'fehlt',
  'angefordert',
  'nicht_relevant',
};

class _MappingContext {
  const _MappingContext({
    required this.request,
    required this.typeIndex,
    required this.metadataByDocument,
    required this.expiryFieldByTypeAndEntity,
    required this.contentProbes,
    required this.uploadedObjects,
  });

  final DocumentMigrationDryRunRequest request;
  final _TypeIndex typeIndex;
  final Map<String, Map<String, String>> metadataByDocument;
  final Map<String, List<String>> expiryFieldByTypeAndEntity;
  final Map<String, DocumentContentProbe> contentProbes;
  final Map<String, DocumentObjectProbe> uploadedObjects;
}

class _TypeIndex {
  const _TypeIndex({
    required this.byLegacyId,
    required this.keysClaimedByLegacyTypes,
  });

  final Map<String, _ResolvedType> byLegacyId;
  final Set<String> keysClaimedByLegacyTypes;
}

class _ResolvedType {
  const _ResolvedType({
    required this.targetId,
    required this.key,
    required this.entityType,
    required this.keyUnique,
    required this.keyValid,
  });

  final String targetId;
  final String key;
  final DocumentLinkEntityType? entityType;
  final bool keyUnique;
  final bool keyValid;

  bool get entityTypeMappable => entityType != null;

  bool get usable => entityTypeMappable && keyUnique && keyValid;
}

class _MappedRow {
  const _MappedRow({
    required this.sourceId,
    required this.issues,
    this.targetId,
    this.targetChildId,
    this.target,
    this.sourceProjection,
    this.targetProjection,
    this.contentLink = DocumentContentLinkState.notApplicable,
    this.storageObjectPath,
  });

  final String? sourceId;
  final String? targetId;
  final String? targetChildId;
  final Map<String, Object?>? target;
  final Map<String, Object?>? sourceProjection;
  final Map<String, Object?>? targetProjection;
  final DocumentContentLinkState contentLink;
  final String? storageObjectPath;
  final List<DocumentMigrationIssue> issues;
}

class _EntityResult {
  const _EntityResult({
    required this.aborted,
    required this.issues,
    required this.mappings,
    required this.summary,
  });

  final bool aborted;
  final List<DocumentMigrationIssue> issues;
  final List<DocumentMigrationMapping> mappings;
  final DocumentMigrationEntitySummary summary;
}

List<Map<String, Object?>> _sortedRows(List<Map<String, Object?>> rows) {
  final sorted = rows.map(Map<String, Object?>.from).toList(growable: false)
    ..sort((left, right) => _rowId(left).compareTo(_rowId(right)));
  return sorted;
}

List<Map<String, Object?>> _sortProjectionRows(List<Map<String, Object?>> rows) {
  final sorted = rows.map(Map<String, Object?>.from).toList(growable: false)
    ..sort((left, right) {
      final leftId = (left['source_id'] ?? left['id'] ?? '').toString();
      final rightId = (right['source_id'] ?? right['id'] ?? '').toString();
      return leftId.compareTo(rightId);
    });
  return sorted;
}

String _rowId(Map<String, Object?> row) => row['id']?.toString() ?? '';

int _compareMappings(
  DocumentMigrationMapping left,
  DocumentMigrationMapping right,
) {
  final entity = left.entity.name.compareTo(right.entity.name);
  return entity != 0 ? entity : left.sourceId.compareTo(right.sourceId);
}

int _compareIssues(DocumentMigrationIssue left, DocumentMigrationIssue right) {
  final leftKey = <String>[
    left.entity?.name ?? '',
    left.sourceId ?? '',
    left.field ?? '',
    left.code,
    left.severity.name,
  ].join(' ');
  final rightKey = <String>[
    right.entity?.name ?? '',
    right.sourceId ?? '',
    right.field ?? '',
    right.code,
    right.severity.name,
  ].join(' ');
  return leftKey.compareTo(rightKey);
}

final RegExp _normalizedKey = RegExp(r'^[a-z0-9]+([._-][a-z0-9]+)*$');
