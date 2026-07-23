import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/document_repository.dart';
import '../domain/document_dto.dart';

/// The single seam over the Supabase SDK for documents_compliance. No other
/// part of the feature (and nothing above it) may touch `SupabaseClient`, so
/// the adapter can be exercised without a live client, exactly like the
/// contacts_parties gateway.
abstract interface class DocumentSupabaseGateway {
  String? get currentUserId;

  Future<List<Map<String, dynamic>>> getDocument({
    required String workspaceId,
    required String documentId,
  });

  Future<List<Map<String, dynamic>>> listDocuments({
    required String workspaceId,
    required String? afterId,
    required int limit,
    required bool includeInactive,
    required String? documentTypeId,
    required String? entityType,
    required String? entityId,
  });

  Future<List<Map<String, dynamic>>> listVersions({
    required String workspaceId,
    required String documentId,
  });

  Future<List<Map<String, dynamic>>> listLinks({
    required String workspaceId,
    required String documentId,
  });

  Future<List<Map<String, dynamic>>> listTypes({
    required String workspaceId,
    required bool activeOnly,
  });

  Future<List<Map<String, dynamic>>> listRequirements({
    required String workspaceId,
    required String entityType,
    required String? entityId,
  });

  Future<Object?> callRpc(String function, Map<String, Object?> parameters);

  /// Mints a Storage signed URL. The TTL is already clamped by the caller.
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required int ttlSeconds,
  });
}

class SupabaseDocumentGateway implements DocumentSupabaseGateway {
  SupabaseDocumentGateway(this._client);

  final SupabaseClient _client;

  static const String _documentColumns =
      'id, workspace_id, document_type_id, title, status, current_version_no, '
      'valid_from, valid_until, retention_until, superseded_by_document_id, '
      'archived_at, notes, created_at, updated_at, created_by, updated_by, '
      'version';

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> getDocument({
    required String workspaceId,
    required String documentId,
  }) async {
    final rows = await _client
        .from('documents')
        .select(_documentColumns)
        .eq('workspace_id', workspaceId)
        .eq('id', documentId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listDocuments({
    required String workspaceId,
    required String? afterId,
    required int limit,
    required bool includeInactive,
    required String? documentTypeId,
    required String? entityType,
    required String? entityId,
  }) async {
    final columns = entityType == null
        ? _documentColumns
        : '$_documentColumns, document_links!inner(entity_type, entity_id)';
    var query = _client
        .from('documents')
        .select(columns)
        .eq('workspace_id', workspaceId);
    if (entityType != null && entityId != null) {
      // Entity-scoped read: only documents linked to this EntityRef.
      query = query
          .eq('document_links.entity_type', entityType)
          .eq('document_links.entity_id', entityId);
    }
    if (documentTypeId != null) {
      query = query.eq('document_type_id', documentTypeId);
    }
    if (!includeInactive) {
      // Mirrors DocumentStatus.isActive and the server-side exclusion in
      // evaluate_document_requirements.
      query = query.neq('status', 'superseded').neq('status', 'archived');
    }
    if (afterId != null) {
      query = query.gt('id', afterId);
    }
    final rows = await query.order('id', ascending: true).limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listVersions({
    required String workspaceId,
    required String documentId,
  }) async {
    final rows = await _client
        .from('document_versions')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('document_id', documentId)
        .order('version_no', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listLinks({
    required String workspaceId,
    required String documentId,
  }) async {
    final rows = await _client
        .from('document_links')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('document_id', documentId)
        .order('created_at', ascending: true)
        .order('id', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listTypes({
    required String workspaceId,
    required bool activeOnly,
  }) async {
    var query = _client
        .from('document_types')
        .select()
        .eq('workspace_id', workspaceId);
    if (activeOnly) {
      query = query.eq('is_active', true);
    }
    final rows = await query.order('key', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listRequirements({
    required String workspaceId,
    required String entityType,
    required String? entityId,
  }) async {
    var query = _client
        .from('required_documents')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('entity_type', entityType)
        // Retired rules are history, not policy.
        .isFilter('retired_at', null);
    if (entityId != null) {
      // Same rule lookup the server performs: workspace-wide rules for the
      // type plus the instance-level ones for this entity.
      query = query.or('entity_id.is.null,entity_id.eq.$entityId');
    }
    final rows = await query.order('id', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) {
    return _client.rpc(function, params: parameters);
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required int ttlSeconds,
  }) {
    return _client.storage.from(bucket).createSignedUrl(path, ttlSeconds);
  }
}

/// Supabase-backed implementation of all six documents_compliance ports.
class SupabaseDocumentRepositoryAdapter
    implements
        DocumentRepository,
        DocumentContentPort,
        DocumentLinkPort,
        RequirementPolicyRepository,
        DocumentVerificationPort,
        SignedUrlPort {
  SupabaseDocumentRepositoryAdapter({required SupabaseClient client})
    : _gateway = SupabaseDocumentGateway(client);

  SupabaseDocumentRepositoryAdapter.withGateway(DocumentSupabaseGateway gateway)
    : _gateway = gateway;

  final DocumentSupabaseGateway _gateway;

  // --- DocumentRepository ---

  @override
  Future<DocumentRepositoryResult<DocumentDto>> getById({
    required String workspaceId,
    required String documentId,
  }) async {
    try {
      final rows = await _gateway.getDocument(
        workspaceId: workspaceId,
        documentId: documentId,
      );
      if (rows.isEmpty) {
        return const DocumentRepositoryFailure<DocumentDto>(
          kind: DocumentRepositoryFailureKind.notFound,
          message: 'Document not found.',
        );
      }
      final document = _parseDocument(rows.first);
      _requireWorkspace(document.workspaceId, workspaceId);
      return DocumentRepositorySuccess<DocumentDto>(document);
    } catch (_) {
      return const DocumentRepositoryFailure<DocumentDto>(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase document could not be loaded.',
      );
    }
  }

  @override
  Future<DocumentRepositoryResult<DocumentPageResult>> search(
    DocumentListQuery query,
  ) async {
    try {
      final rows = await _gateway.listDocuments(
        workspaceId: query.workspaceId,
        afterId: query.page.cursor,
        limit: query.page.limit + 1,
        includeInactive: query.includeInactive,
        documentTypeId: query.documentTypeId,
        entityType: query.entityType?.wireName,
        entityId: query.entityId,
      );
      final hasNextPage = rows.length > query.page.limit;
      final pageRows = hasNextPage ? rows.take(query.page.limit) : rows;
      final items = pageRows.map(_parseDocument).toList(growable: false);
      if (items.any(
        (document) => document.workspaceId != query.workspaceId,
      )) {
        throw const FormatException('Document workspace mismatch.');
      }
      return DocumentRepositorySuccess<DocumentPageResult>(
        DocumentPageResult(
          items: items,
          nextCursor: hasNextPage && items.isNotEmpty ? items.last.id : null,
        ),
      );
    } catch (_) {
      return const DocumentRepositoryFailure<DocumentPageResult>(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase documents could not be loaded.',
      );
    }
  }

  @override
  Future<DocumentRepositoryResult<DocumentDto>> create(
    CreateDocumentCommand command,
  ) {
    final draft = command.draft;
    return _executeCommand<DocumentDto>(
      context: command.context,
      function: 'create_document',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_title': draft.title,
        'p_storage_object_path': draft.content.storageObjectPath,
        // Lowercase hex sha256 — the RPC decodes it, no bytes cross the wire.
        'p_content_hash': draft.content.contentHash,
        'p_byte_size': draft.content.byteSize,
        'p_mime_type': draft.content.mimeType,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_document_type_id': draft.documentTypeId,
        'p_original_filename': draft.content.originalFilename,
        'p_valid_from': _formatNullableDate(draft.validFrom),
        'p_valid_until': _formatNullableDate(draft.validUntil),
        'p_retention_until': _formatNullableDate(draft.retentionUntil),
        'p_notes': draft.notes,
        'p_reason': command.context.reason,
      },
      // The create snapshot carries a nested current_version object.
      parseEntity: (entity) =>
          _parseScopedDocument(entity, command.context.workspaceId),
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentDto>> transitionStatus(
    TransitionDocumentStatusCommand command,
  ) {
    return _executeCommand<DocumentDto>(
      context: command.context,
      function: 'transition_document_status',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_document_id': command.documentId,
        'p_expected_version': command.expectedVersion,
        'p_target_status': command.transition.wireName,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_superseded_by_document_id': command.supersededByDocumentId,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) =>
          _parseScopedDocument(entity, command.context.workspaceId),
      versioned: true,
    );
  }

  // --- DocumentContentPort ---

  @override
  Future<DocumentRepositoryResult<List<DocumentVersionDto>>> listVersions({
    required String workspaceId,
    required String documentId,
  }) async {
    try {
      final rows = await _gateway.listVersions(
        workspaceId: workspaceId,
        documentId: documentId,
      );
      final versions = rows.map(_parseVersion).toList(growable: false);
      if (versions.any((version) => version.workspaceId != workspaceId)) {
        throw const FormatException('Document version workspace mismatch.');
      }
      return DocumentRepositorySuccess<List<DocumentVersionDto>>(versions);
    } catch (_) {
      return const DocumentRepositoryFailure<List<DocumentVersionDto>>(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase document versions could not be loaded.',
      );
    }
  }

  @override
  Future<DocumentRepositoryResult<DocumentVersionDto>> addVersion(
    AddDocumentVersionCommand command,
  ) {
    final content = command.content;
    return _executeCommand<DocumentVersionDto>(
      context: command.context,
      function: 'add_document_version',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_document_id': command.documentId,
        'p_expected_version': command.expectedVersion,
        'p_storage_object_path': content.storageObjectPath,
        'p_content_hash': content.contentHash,
        'p_byte_size': content.byteSize,
        'p_mime_type': content.mimeType,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_original_filename': content.originalFilename,
        'p_reason': command.context.reason,
      },
      // A version snapshot carrying a nested document object; the port returns
      // the version.
      parseEntity: (entity) =>
          _parseScopedVersion(entity, command.context.workspaceId),
      versioned: true,
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentDto>> confirmContent(
    ConfirmDocumentContentCommand command,
  ) {
    return _executeCommand<DocumentDto>(
      context: command.context,
      function: 'confirm_document_content',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_document_id': command.documentId,
        'p_version_no': command.versionNo,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      // A mismatch is NOT a failure: the server drives STM-008 to `rejected`
      // and still answers ok. Callers inspect DocumentDto.status; the extra
      // `content_verified` flag is redundant with it and stays unread.
      parseEntity: (entity) =>
          _parseScopedDocument(entity, command.context.workspaceId),
      versioned: true,
    );
  }

  // --- DocumentVerificationPort ---

  @override
  Future<DocumentRepositoryResult<DocumentVersionDto>> verify(
    VerifyDocumentVersionCommand command,
  ) {
    return _executeCommand<DocumentVersionDto>(
      context: command.context,
      function: 'verify_document_version',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_document_id': command.documentId,
        'p_version_no': command.versionNo,
        'p_expected_version': command.expectedVersion,
        'p_outcome': command.outcome.wireName,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_note': command.note,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) =>
          _parseScopedVersion(entity, command.context.workspaceId),
      versioned: true,
    );
  }

  // --- DocumentLinkPort ---

  @override
  Future<DocumentRepositoryResult<List<DocumentLinkDto>>> listLinks({
    required String workspaceId,
    required String documentId,
  }) async {
    try {
      final rows = await _gateway.listLinks(
        workspaceId: workspaceId,
        documentId: documentId,
      );
      final links = rows.map(_parseLink).toList(growable: false);
      if (links.any((link) => link.workspaceId != workspaceId)) {
        throw const FormatException('Document link workspace mismatch.');
      }
      return DocumentRepositorySuccess<List<DocumentLinkDto>>(links);
    } catch (_) {
      return const DocumentRepositoryFailure<List<DocumentLinkDto>>(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase document links could not be loaded.',
      );
    }
  }

  @override
  Future<DocumentRepositoryResult<DocumentLinkDto>> link(
    LinkDocumentCommand command,
  ) {
    return _executeCommand<DocumentLinkDto>(
      context: command.context,
      function: 'link_document',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_document_id': command.documentId,
        'p_entity_type': command.entityType.wireName,
        'p_entity_id': command.entityId,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_link_role': command.linkRole,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) {
        final link = _parseLink(entity);
        _requireWorkspace(link.workspaceId, command.context.workspaceId);
        return link;
      },
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentLinkDto>> unlink(
    UnlinkDocumentCommand command,
  ) {
    return _executeCommand<DocumentLinkDto>(
      context: command.context,
      function: 'unlink_document',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_document_link_id': command.documentLinkId,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) {
        final link = _parseLink(entity);
        _requireWorkspace(link.workspaceId, command.context.workspaceId);
        return link;
      },
    );
  }

  // --- RequirementPolicyRepository ---

  @override
  Future<DocumentRepositoryResult<List<DocumentTypeDto>>> listTypes({
    required String workspaceId,
    bool activeOnly = true,
  }) async {
    try {
      final rows = await _gateway.listTypes(
        workspaceId: workspaceId,
        activeOnly: activeOnly,
      );
      final types = rows.map(_parseType).toList(growable: false);
      if (types.any((type) => type.workspaceId != workspaceId)) {
        throw const FormatException('Document type workspace mismatch.');
      }
      return DocumentRepositorySuccess<List<DocumentTypeDto>>(types);
    } catch (_) {
      return const DocumentRepositoryFailure<List<DocumentTypeDto>>(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase document types could not be loaded.',
      );
    }
  }

  @override
  Future<DocumentRepositoryResult<DocumentTypeDto>> upsertType(
    UpsertDocumentTypeCommand command,
  ) {
    final draft = command.draft;
    return _executeCommand<DocumentTypeDto>(
      context: command.context,
      function: 'upsert_document_type',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_key': draft.key,
        'p_name': draft.name,
        'p_entity_type': draft.entityType.wireName,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_default_validity_months': draft.defaultValidityMonths,
        'p_is_active': draft.isActive,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) {
        final type = _parseType(entity);
        _requireWorkspace(type.workspaceId, command.context.workspaceId);
        return type;
      },
    );
  }

  @override
  Future<DocumentRepositoryResult<List<RequiredDocumentDto>>> listRequirements({
    required String workspaceId,
    required DocumentLinkEntityType entityType,
    String? entityId,
  }) async {
    try {
      final rows = await _gateway.listRequirements(
        workspaceId: workspaceId,
        entityType: entityType.wireName,
        entityId: entityId,
      );
      final requirements = rows.map(_parseRequirement).toList(growable: false);
      if (requirements.any(
        (requirement) => requirement.workspaceId != workspaceId,
      )) {
        throw const FormatException('Requirement workspace mismatch.');
      }
      return DocumentRepositorySuccess<List<RequiredDocumentDto>>(requirements);
    } catch (_) {
      return const DocumentRepositoryFailure<List<RequiredDocumentDto>>(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase document requirements could not be loaded.',
      );
    }
  }

  @override
  Future<DocumentRepositoryResult<RequiredDocumentDto>> upsertRequirement(
    UpsertRequiredDocumentCommand command,
  ) {
    final draft = command.draft;
    return _executeCommand<RequiredDocumentDto>(
      context: command.context,
      function: 'upsert_required_document',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_entity_type': draft.entityType.wireName,
        'p_document_type_id': draft.documentTypeId,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_entity_id': draft.entityId,
        'p_scope_key': draft.scopeKey,
        'p_is_mandatory': draft.isMandatory,
        'p_due_at': _formatNullableDate(draft.dueAt),
        'p_validity_months': draft.validityMonths,
        'p_owner_user_id': draft.ownerUserId,
        'p_note': draft.note,
        'p_requested': draft.requested,
        'p_waived': draft.waived,
        'p_waiver_reason': draft.waiverReason,
        'p_retired': draft.retired,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) {
        final requirement = _parseRequirement(entity);
        _requireWorkspace(requirement.workspaceId, command.context.workspaceId);
        return requirement;
      },
    );
  }

  @override
  Future<DocumentRepositoryResult<List<DocumentRequirementProjection>>> evaluate(
    DocumentRequirementQuery query,
  ) async {
    try {
      final response = await _gateway.callRpc(
        'evaluate_document_requirements',
        <String, Object?>{
          'p_workspace_id': query.workspaceId,
          'p_entity_type': query.entityType.wireName,
          'p_entity_id': query.entityId,
          'p_scope_key': query.scopeKey,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        final entity = payload['entity'];
        if (entity is! List) {
          throw const FormatException('Expected a projection list.');
        }
        final projections = entity
            .map((row) => _parseProjection(_asMap(row)))
            .toList(growable: false);
        // The projection snapshot carries no workspace_id (it is derived, not a
        // row), so the strongest available scope guard is the EntityRef the
        // caller asked about.
        if (projections.any(
          (projection) =>
              projection.entityId != query.entityId ||
              projection.entityType != query.entityType,
        )) {
          throw const FormatException('Projection entity mismatch.');
        }
        return DocumentRepositorySuccess<List<DocumentRequirementProjection>>(
          projections,
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<List<DocumentRequirementProjection>>(
        _asMap(payload['error']),
        null,
      );
    } catch (_) {
      return const DocumentRepositoryFailure<
        List<DocumentRequirementProjection>
      >(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase requirement evaluation failed.',
      );
    }
  }

  // --- SignedUrlPort ---

  @override
  Future<DocumentRepositoryResult<DocumentContentRef>> resolveContentRef({
    required String workspaceId,
    required String documentId,
    int? versionNo,
  }) async {
    try {
      final response = await _gateway
          .callRpc('resolve_document_content_ref', <String, Object?>{
            'p_workspace_id': workspaceId,
            'p_document_id': documentId,
            'p_version_no': versionNo,
          });
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        final ref = _parseContentRef(_asMap(payload['entity']));
        _requireWorkspace(ref.workspaceId, workspaceId);
        return DocumentRepositorySuccess<DocumentContentRef>(ref);
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<DocumentContentRef>(_asMap(payload['error']), null);
    } catch (_) {
      return const DocumentRepositoryFailure<DocumentContentRef>(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase document content reference could not be resolved.',
      );
    }
  }

  @override
  Future<DocumentRepositoryResult<SignedDocumentUrl>> createSignedUrl({
    required String workspaceId,
    required String documentId,
    int? versionNo,
    Duration? ttl,
  }) async {
    // Resolve first: that RPC is the server-side permission check, so a URL is
    // never minted for content the caller may not read.
    final resolved = await resolveContentRef(
      workspaceId: workspaceId,
      documentId: documentId,
      versionNo: versionNo,
    );
    if (resolved is DocumentRepositoryFailure<DocumentContentRef>) {
      return DocumentRepositoryFailure<SignedDocumentUrl>(
        kind: resolved.kind,
        message: resolved.message,
        versionConflict: resolved.versionConflict,
      );
    }
    final ref = (resolved as DocumentRepositorySuccess<DocumentContentRef>).value;

    // The policy lives in exactly one place; this never re-implements it.
    final appliedTtl = SignedUrlPort.clampTtl(ttl);
    try {
      final url = await _gateway.createSignedUrl(
        bucket: ref.storageBucket,
        path: ref.storageObjectPath,
        ttlSeconds: appliedTtl.inSeconds,
      );
      return DocumentRepositorySuccess<SignedDocumentUrl>(
        SignedDocumentUrl(
          url: url,
          expiresAt: DateTime.now().add(appliedTtl),
          appliedTtl: appliedTtl,
          contentRef: ref,
        ),
      );
    } catch (_) {
      return const DocumentRepositoryFailure<SignedDocumentUrl>(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase signed document url could not be created.',
      );
    }
  }

  // --- shared command execution ---

  Future<DocumentRepositoryResult<T>> _executeCommand<T>({
    required DocumentCommandContext context,
    required String function,
    required Map<String, Object?> parameters,
    required T Function(Map<String, dynamic> entity) parseEntity,
    bool versioned = false,
  }) async {
    if (_gateway.currentUserId != context.actorId) {
      return DocumentRepositoryFailure<T>(
        kind: DocumentRepositoryFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }

    try {
      final response = await _gateway.callRpc(function, parameters);
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return DocumentRepositorySuccess<T>(
          parseEntity(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<T>(
        _asMap(payload['error']),
        // Every versioned document command reports the same conflict shape:
        // the current DOCUMENT, never a version or a link.
        versioned
            ? (entity) => _parseScopedDocument(entity, context.workspaceId)
            : null,
      );
    } catch (_) {
      return DocumentRepositoryFailure<T>(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase document command failed.',
      );
    }
  }

  DocumentRepositoryFailure<T> _mapRpcFailure<T>(
    Map<String, dynamic> error,
    DocumentDto Function(Map<String, dynamic> entity)? parseConflictDocument,
  ) {
    final code = _requiredString(error, 'code');
    final message = error['message'] is String
        ? error['message'] as String
        : 'Document command failed.';
    switch (code) {
      case 'not_found':
        return DocumentRepositoryFailure<T>(
          kind: DocumentRepositoryFailureKind.notFound,
          message: message,
        );
      case 'forbidden':
        return DocumentRepositoryFailure<T>(
          kind: DocumentRepositoryFailureKind.forbidden,
          message: message,
        );
      case 'validation_failed':
        return DocumentRepositoryFailure<T>(
          kind: DocumentRepositoryFailureKind.validationFailed,
          message: message,
        );
      case 'mutation_conflict':
        return DocumentRepositoryFailure<T>(
          kind: DocumentRepositoryFailureKind.mutationConflict,
          message: message,
        );
      case 'in_progress':
        return DocumentRepositoryFailure<T>(
          kind: DocumentRepositoryFailureKind.mutationInProgress,
          message: message,
        );
      case 'dependency_conflict':
        // link_document / upsert_required_document against a domain that has
        // not been migrated yet (DEBT-006).
        return DocumentRepositoryFailure<T>(
          kind: DocumentRepositoryFailureKind.dependencyConflict,
          message: message,
        );
      case 'version_conflict':
        if (parseConflictDocument == null) {
          throw const FormatException('Unexpected version conflict.');
        }
        return DocumentRepositoryFailure<T>(
          kind: DocumentRepositoryFailureKind.versionConflict,
          message: message,
          versionConflict: DocumentVersionConflict(
            expectedVersion: _requiredInt(error, 'expected_version'),
            actualVersion: _requiredInt(error, 'actual_version'),
            currentDocument: parseConflictDocument(
              _asMap(error['current_entity']),
            ),
          ),
        );
      case 'infrastructure_failure':
      default:
        return DocumentRepositoryFailure<T>(
          kind: DocumentRepositoryFailureKind.infrastructureFailure,
          message: 'Supabase document command failed.',
        );
    }
  }
}

DocumentDto _parseScopedDocument(
  Map<String, dynamic> entity,
  String workspaceId,
) {
  final document = _parseDocument(entity);
  _requireWorkspace(document.workspaceId, workspaceId);
  return document;
}

DocumentVersionDto _parseScopedVersion(
  Map<String, dynamic> entity,
  String workspaceId,
) {
  final version = _parseVersion(entity);
  _requireWorkspace(version.workspaceId, workspaceId);
  return version;
}

DocumentDto _parseDocument(Map<String, dynamic> json) {
  final currentVersion = json['current_version'];
  return DocumentDto(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    title: _requiredString(json, 'title'),
    status: _requiredEnum(
      DocumentStatus.fromWire(_nullableString(json, 'status')),
      'status',
    ),
    currentVersionNo: _requiredInt(json, 'current_version_no'),
    version: _requiredInt(json, 'version'),
    documentTypeId: _nullableString(json, 'document_type_id'),
    validFrom: _nullableDateTime(json, 'valid_from'),
    validUntil: _nullableDateTime(json, 'valid_until'),
    retentionUntil: _nullableDateTime(json, 'retention_until'),
    supersededByDocumentId: _nullableString(json, 'superseded_by_document_id'),
    archivedAt: _nullableDateTime(json, 'archived_at'),
    notes: _nullableString(json, 'notes'),
    createdAt: _nullableDateTime(json, 'created_at'),
    updatedAt: _nullableDateTime(json, 'updated_at'),
    createdBy: _nullableString(json, 'created_by'),
    updatedBy: _nullableString(json, 'updated_by'),
    currentVersion: currentVersion == null
        ? null
        : _parseVersion(_asMap(currentVersion)),
  );
}

DocumentVersionDto _parseVersion(Map<String, dynamic> json) {
  return DocumentVersionDto(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    documentId: _requiredString(json, 'document_id'),
    versionNo: _requiredInt(json, 'version_no'),
    storageBucket: _requiredString(json, 'storage_bucket'),
    storageObjectPath: _requiredString(json, 'storage_object_path'),
    contentHash: _parseContentHash(json),
    byteSize: _requiredInt(json, 'byte_size'),
    mimeType: _requiredString(json, 'mime_type'),
    verificationStatus: _requiredEnum(
      DocumentVerificationStatus.fromWire(
        _nullableString(json, 'verification_status'),
      ),
      'verification_status',
    ),
    version: _requiredInt(json, 'version'),
    originalFilename: _nullableString(json, 'original_filename'),
    contentConfirmedAt: _nullableDateTime(json, 'content_confirmed_at'),
    verifiedAt: _nullableDateTime(json, 'verified_at'),
    verifiedBy: _nullableString(json, 'verified_by'),
    verificationNote: _nullableString(json, 'verification_note'),
    supersededAt: _nullableDateTime(json, 'superseded_at'),
    supersededByVersionNo: _nullableInt(json, 'superseded_by_version_no'),
  );
}

DocumentLinkDto _parseLink(Map<String, dynamic> json) {
  return DocumentLinkDto(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    documentId: _requiredString(json, 'document_id'),
    entityType: _requiredEnum(
      DocumentLinkEntityType.fromWire(_nullableString(json, 'entity_type')),
      'entity_type',
    ),
    entityId: _requiredString(json, 'entity_id'),
    linkRole: _nullableString(json, 'link_role'),
    createdAt: _nullableDateTime(json, 'created_at'),
    createdBy: _nullableString(json, 'created_by'),
  );
}

DocumentTypeDto _parseType(Map<String, dynamic> json) {
  return DocumentTypeDto(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    key: _requiredString(json, 'key'),
    name: _requiredString(json, 'name'),
    entityType: _requiredEnum(
      DocumentLinkEntityType.fromWire(_nullableString(json, 'entity_type')),
      'entity_type',
    ),
    isActive: json['is_active'] == true,
    version: _requiredInt(json, 'version'),
    defaultValidityMonths: _nullableInt(json, 'default_validity_months'),
  );
}

RequiredDocumentDto _parseRequirement(Map<String, dynamic> json) {
  return RequiredDocumentDto(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    entityType: _requiredEnum(
      DocumentLinkEntityType.fromWire(_nullableString(json, 'entity_type')),
      'entity_type',
    ),
    documentTypeId: _requiredString(json, 'document_type_id'),
    isMandatory: json['is_mandatory'] == true,
    version: _requiredInt(json, 'version'),
    entityId: _nullableString(json, 'entity_id'),
    scopeKey: _nullableString(json, 'scope_key'),
    dueAt: _nullableDateTime(json, 'due_at'),
    validityMonths: _nullableInt(json, 'validity_months'),
    ownerUserId: _nullableString(json, 'owner_user_id'),
    note: _nullableString(json, 'note'),
    requestedAt: _nullableDateTime(json, 'requested_at'),
    waivedAt: _nullableDateTime(json, 'waived_at'),
    waivedBy: _nullableString(json, 'waived_by'),
    waiverReason: _nullableString(json, 'waiver_reason'),
    retiredAt: _nullableDateTime(json, 'retired_at'),
  );
}

DocumentRequirementProjection _parseProjection(Map<String, dynamic> json) {
  return DocumentRequirementProjection(
    requirementId: _requiredString(json, 'requirement_id'),
    documentTypeId: _requiredString(json, 'document_type_id'),
    documentTypeKey: _requiredString(json, 'document_type_key'),
    documentTypeName: _requiredString(json, 'document_type_name'),
    entityType: _requiredEnum(
      DocumentLinkEntityType.fromWire(_nullableString(json, 'entity_type')),
      'entity_type',
    ),
    entityId: _requiredString(json, 'entity_id'),
    isMandatory: json['is_mandatory'] == true,
    isInstanceRule: json['is_instance_rule'] == true,
    state: _requiredEnum(
      DocumentRequirementState.fromWire(_nullableString(json, 'state')),
      'state',
    ),
    scopeKey: _nullableString(json, 'scope_key'),
    dueAt: _nullableDateTime(json, 'due_at'),
    ownerUserId: _nullableString(json, 'owner_user_id'),
    note: _nullableString(json, 'note'),
    documentId: _nullableString(json, 'document_id'),
    documentStatus: DocumentStatus.fromWire(
      _nullableString(json, 'document_status'),
    ),
    documentValidUntil: _nullableDateTime(json, 'document_valid_until'),
  );
}

DocumentContentRef _parseContentRef(Map<String, dynamic> json) {
  return DocumentContentRef(
    documentId: _requiredString(json, 'document_id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    versionNo: _requiredInt(json, 'version_no'),
    storageBucket: _requiredString(json, 'storage_bucket'),
    storageObjectPath: _requiredString(json, 'storage_object_path'),
    contentHash: _parseContentHash(json),
    byteSize: _requiredInt(json, 'byte_size'),
    mimeType: _requiredString(json, 'mime_type'),
    verificationStatus: _requiredEnum(
      DocumentVerificationStatus.fromWire(
        _nullableString(json, 'verification_status'),
      ),
      'verification_status',
    ),
    originalFilename: _nullableString(json, 'original_filename'),
    contentConfirmedAt: _nullableDateTime(json, 'content_confirmed_at'),
  );
}

void _requireWorkspace(String workspaceId, String expectedWorkspaceId) {
  if (workspaceId != expectedWorkspaceId) {
    throw const FormatException('Entity workspace mismatch.');
  }
}

/// `date` columns cross the wire as `yyyy-MM-dd`; the RPCs take the same shape.
String? _formatNullableDate(DateTime? value) {
  if (value == null) {
    return null;
  }
  final utc = value.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-$month-$day';
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected an object.');
  }
  return Map<String, dynamic>.from(value);
}

T _requiredEnum<T>(T? value, String field) {
  if (value == null) {
    throw FormatException('Unknown enum value for field: $field.');
  }
  return value;
}

/// The DTO contract is lowercase hex, but the hash reaches this adapter in two
/// different wire forms: the RPC snapshots emit `encode(content_hash, 'hex')`,
/// while a direct PostgREST read of `document_versions` serialises the `bytea`
/// column as `\x…`. Normalising here keeps that difference from leaking into
/// the domain — and keeps the two read paths from disagreeing.
String _parseContentHash(Map<String, dynamic> json) {
  var value = _requiredString(json, 'content_hash').trim().toLowerCase();
  if (value.startsWith(r'\x')) {
    value = value.substring(2);
  }
  if (!_hexSha256.hasMatch(value)) {
    throw const FormatException('Expected a hex sha256 content hash.');
  }
  return value;
}

final RegExp _hexSha256 = RegExp(r'^[0-9a-f]{64}$');

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Expected string field: $key.');
  }
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Expected nullable string field: $key.');
  }
  return value;
}

/// Both `date` and `timestamptz` arrive as strings. Parsing is deliberately
/// total: an unreadable optional timestamp degrades to null rather than
/// throwing out of the adapter and losing the whole entity.
DateTime? _nullableDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    return null;
  }
  return DateTime.tryParse(value);
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Expected integer field: $key.');
}

int? _nullableInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('Expected nullable integer field: $key.');
}
