import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/data/supabase_document_repository_adapter.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';

const String _workspaceId = 'e1000000-0000-0000-0000-000000000001';
const String _otherWorkspaceId = 'e1000000-0000-0000-0000-0000000000ff';
const String _actorId = 'ea000000-0000-0000-0000-000000000001';
const String _documentId = 'ed000000-0000-0000-0000-000000000001';
const String _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

DocumentCommandContext _context({String actorId = _actorId}) =>
    DocumentCommandContext(
      workspaceId: _workspaceId,
      actorId: actorId,
      mutationId: 'ae000000-0000-0000-0000-000000000001',
      correlationId: 'ac000000-0000-0000-0000-000000000001',
      reason: 'test',
    );

Map<String, dynamic> _documentSnapshot({
  String workspaceId = _workspaceId,
  String status = 'uploaded',
  int version = 1,
  int currentVersionNo = 1,
  Map<String, dynamic>? currentVersion,
}) => <String, dynamic>{
  'id': _documentId,
  'workspace_id': workspaceId,
  'document_type_id': null,
  'title': 'Expose',
  'status': status,
  'current_version_no': currentVersionNo,
  'valid_from': null,
  'valid_until': null,
  'retention_until': null,
  'superseded_by_document_id': null,
  'archived_at': null,
  'notes': null,
  'created_at': '2026-07-23T10:00:00.000Z',
  'updated_at': '2026-07-23T10:00:00.000Z',
  'created_by': _actorId,
  'updated_by': _actorId,
  'version': version,
  if (currentVersion != null) 'current_version': currentVersion,
};

Map<String, dynamic> _versionSnapshot({
  String workspaceId = _workspaceId,
  int versionNo = 1,
  String verificationStatus = 'pending',
  String? contentConfirmedAt,
  int? supersededByVersionNo,
  String contentHash = _hash,
}) => <String, dynamic>{
  'id': 'ev000000-0000-0000-0000-00000000000$versionNo',
  'workspace_id': workspaceId,
  'document_id': _documentId,
  'version_no': versionNo,
  'storage_bucket': 'documents',
  'storage_object_path': '$_workspaceId/$_documentId/$versionNo/expose.pdf',
  'content_hash': contentHash,
  'byte_size': 1024,
  'mime_type': 'application/pdf',
  'original_filename': 'expose.pdf',
  'content_confirmed_at': contentConfirmedAt,
  'verification_status': verificationStatus,
  'verified_at': verificationStatus == 'pending'
      ? null
      : '2026-07-23T11:00:00.000Z',
  'verified_by': verificationStatus == 'pending' ? null : _actorId,
  'verification_note': null,
  'superseded_at': supersededByVersionNo == null
      ? null
      : '2026-07-23T12:00:00.000Z',
  'superseded_by_version_no': supersededByVersionNo,
  'created_at': '2026-07-23T10:00:00.000Z',
  'updated_at': '2026-07-23T10:00:00.000Z',
  'created_by': _actorId,
  'updated_by': _actorId,
  'version': 1,
};

Map<String, dynamic> _ok(Object entity) => <String, dynamic>{
  'ok': true,
  'entity': entity,
};

Map<String, dynamic> _workspaceRequirementRow({
  required String entityId,
  required String state,
  String entityType = 'property',
}) => <String, dynamic>{
  'requirement_id': 'er-$entityId',
  'document_type_id': 'et000000-0000-0000-0000-000000000001',
  'document_type_key': 'grundbuchauszug',
  'document_type_name': 'Grundbuchauszug',
  'entity_type': entityType,
  'entity_id': entityId,
  'scope_key': null,
  'is_mandatory': true,
  'is_instance_rule': false,
  'due_at': null,
  'owner_user_id': null,
  'note': null,
  'document_id': null,
  'document_status': null,
  'document_valid_until': null,
  'state': state,
};

Map<String, dynamic> _error(String code, [Map<String, dynamic>? extra]) =>
    <String, dynamic>{
      'ok': false,
      'error': <String, dynamic>{
        'code': code,
        'message': 'server message',
        ...?extra,
      },
    };

void main() {
  group('SupabaseDocumentRepositoryAdapter commands', () {
    test('create sends the exact RPC contract and parses the nested version',
        () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'create_document': _ok(
            _documentSnapshot(currentVersion: _versionSnapshot()),
          ),
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.create(
        CreateDocumentCommand(
          context: _context(),
          draft: const DocumentDraft(
            title: 'Expose',
            content: DocumentContentDraft(
              storageObjectPath: '$_workspaceId/$_documentId/1/expose.pdf',
              contentHash: _hash,
              byteSize: 1024,
              mimeType: 'application/pdf',
              originalFilename: 'expose.pdf',
            ),
          ),
        ),
      );

      expect(result, isA<DocumentRepositorySuccess<DocumentDto>>());
      final document =
          (result as DocumentRepositorySuccess<DocumentDto>).value;
      expect(document.status, DocumentStatus.uploaded);
      expect(document.currentVersion, isNotNull);
      // The hash crosses the wire as lowercase hex, never as bytes.
      expect(document.currentVersion!.contentHash, _hash);
      expect(document.currentVersion!.isContentConfirmed, isFalse);

      final call = gateway.rpcCalls.single;
      expect(call.function, 'create_document');
      expect(call.parameters['p_content_hash'], _hash);
      expect(call.parameters['p_byte_size'], 1024);
      expect(call.parameters['p_mutation_id'], isNotNull);
      expect(call.parameters['p_correlation_id'], isNotNull);
    });

    test('confirmContent treats a rejected outcome as success, not failure',
        () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'confirm_document_content': <String, dynamic>{
            'ok': true,
            'entity': <String, dynamic>{
              ..._documentSnapshot(status: 'rejected', version: 2),
              'current_version': _versionSnapshot(),
              'content_verified': false,
            },
          },
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.confirmContent(
        ConfirmDocumentContentCommand(
          context: _context(),
          documentId: _documentId,
          versionNo: 1,
          expectedVersion: 1,
        ),
      );

      expect(result, isA<DocumentRepositorySuccess<DocumentDto>>());
      expect(
        (result as DocumentRepositorySuccess<DocumentDto>).value.status,
        DocumentStatus.rejected,
      );
    });

    test('confirmContent maps a confirmed upload to available', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'confirm_document_content': _ok(<String, dynamic>{
            ..._documentSnapshot(status: 'available', version: 2),
            'current_version': _versionSnapshot(
              contentConfirmedAt: '2026-07-23T10:30:00.000Z',
            ),
            'content_verified': true,
          }),
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.confirmContent(
        ConfirmDocumentContentCommand(
          context: _context(),
          documentId: _documentId,
          versionNo: 1,
          expectedVersion: 1,
        ),
      );

      final document =
          (result as DocumentRepositorySuccess<DocumentDto>).value;
      expect(document.status, DocumentStatus.available);
      expect(document.currentVersion!.isContentConfirmed, isTrue);
    });

    test('addVersion returns the new version and reports the supersede link',
        () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'add_document_version': _ok(<String, dynamic>{
            ..._versionSnapshot(versionNo: 2),
            'document': _documentSnapshot(
              status: 'uploaded',
              version: 4,
              currentVersionNo: 2,
            ),
          }),
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.addVersion(
        AddDocumentVersionCommand(
          context: _context(),
          documentId: _documentId,
          expectedVersion: 3,
          content: const DocumentContentDraft(
            storageObjectPath: '$_workspaceId/$_documentId/2/expose-v2.pdf',
            contentHash: _hash,
            byteSize: 2048,
            mimeType: 'application/pdf',
          ),
        ),
      );

      final version =
          (result as DocumentRepositorySuccess<DocumentVersionDto>).value;
      expect(version.versionNo, 2);
      expect(gateway.rpcCalls.single.parameters['p_expected_version'], 3);
    });

    test('verify sends the outcome wire name and returns the version',
        () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'verify_document_version': _ok(<String, dynamic>{
            ..._versionSnapshot(
              verificationStatus: 'verified',
              contentConfirmedAt: '2026-07-23T10:30:00.000Z',
            ),
            'document': _documentSnapshot(status: 'verified', version: 3),
          }),
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.verify(
        VerifyDocumentVersionCommand(
          context: _context(),
          documentId: _documentId,
          versionNo: 1,
          expectedVersion: 2,
          outcome: DocumentVerificationOutcome.verified,
        ),
      );

      final version =
          (result as DocumentRepositorySuccess<DocumentVersionDto>).value;
      expect(version.verificationStatus, DocumentVerificationStatus.verified);
      expect(gateway.rpcCalls.single.parameters['p_outcome'], 'verified');
    });

    test('transitionStatus sends the target status wire name', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'transition_document_status': _ok(
            _documentSnapshot(status: 'archived', version: 7),
          ),
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.transitionStatus(
        TransitionDocumentStatusCommand(
          context: _context(),
          documentId: _documentId,
          expectedVersion: 6,
          transition: DocumentStatusTransition.archive,
        ),
      );

      expect(
        (result as DocumentRepositorySuccess<DocumentDto>).value.status,
        DocumentStatus.archived,
      );
      expect(
        gateway.rpcCalls.single.parameters['p_target_status'],
        'archived',
      );
    });
  });

  group('SupabaseDocumentRepositoryAdapter failures', () {
    test('a version conflict carries the current document', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'transition_document_status': _error('version_conflict', {
            'expected_version': 3,
            'actual_version': 5,
            'current_entity': _documentSnapshot(
              status: 'available',
              version: 5,
            ),
          }),
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.transitionStatus(
        TransitionDocumentStatusCommand(
          context: _context(),
          documentId: _documentId,
          expectedVersion: 3,
          transition: DocumentStatusTransition.archive,
        ),
      );

      final failure = result as DocumentRepositoryFailure<DocumentDto>;
      expect(failure.kind, DocumentRepositoryFailureKind.versionConflict);
      expect(failure.versionConflict, isNotNull);
      expect(failure.versionConflict!.expectedVersion, 3);
      expect(failure.versionConflict!.actualVersion, 5);
      expect(failure.versionConflict!.currentDocument.version, 5);
    });

    test('an unmigrated link domain maps to dependencyConflict', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'link_document': _error('dependency_conflict'),
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.link(
        LinkDocumentCommand(
          context: _context(),
          documentId: _documentId,
          entityType: DocumentLinkEntityType.lease,
          entityId: 'e5000000-0000-0000-0000-000000000001',
        ),
      );

      expect(
        (result as DocumentRepositoryFailure<DocumentLinkDto>).kind,
        DocumentRepositoryFailureKind.dependencyConflict,
      );
    });

    test('forbidden and not_found map to their own kinds', () async {
      final forbidden = _FakeGateway(
        rpcResponses: <String, Object?>{'create_document': _error('forbidden')},
      );
      final notFound = _FakeGateway(
        rpcResponses: <String, Object?>{'create_document': _error('not_found')},
      );

      const draft = DocumentDraft(
        title: 'Expose',
        content: DocumentContentDraft(
          storageObjectPath: '$_workspaceId/$_documentId/1/expose.pdf',
          contentHash: _hash,
          byteSize: 1024,
          mimeType: 'application/pdf',
        ),
      );

      final forbiddenResult =
          await SupabaseDocumentRepositoryAdapter.withGateway(forbidden).create(
        CreateDocumentCommand(context: _context(), draft: draft),
      );
      final notFoundResult =
          await SupabaseDocumentRepositoryAdapter.withGateway(notFound).create(
        CreateDocumentCommand(context: _context(), draft: draft),
      );

      expect(
        (forbiddenResult as DocumentRepositoryFailure<DocumentDto>).kind,
        DocumentRepositoryFailureKind.forbidden,
      );
      expect(
        (notFoundResult as DocumentRepositoryFailure<DocumentDto>).kind,
        DocumentRepositoryFailureKind.notFound,
      );
    });

    test('an actor mismatch short-circuits before any network call', () async {
      final gateway = _FakeGateway(rpcResponses: const <String, Object?>{});
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.create(
        CreateDocumentCommand(
          context: _context(actorId: 'someone-else'),
          draft: const DocumentDraft(
            title: 'Expose',
            content: DocumentContentDraft(
              storageObjectPath: '$_workspaceId/$_documentId/1/expose.pdf',
              contentHash: _hash,
              byteSize: 1024,
              mimeType: 'application/pdf',
            ),
          ),
        ),
      );

      expect(result, isA<DocumentRepositoryFailure<DocumentDto>>());
      expect(gateway.rpcCalls, isEmpty);
    });

    test('an entity from another workspace is rejected', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'create_document': _ok(
            _documentSnapshot(workspaceId: _otherWorkspaceId),
          ),
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.create(
        CreateDocumentCommand(
          context: _context(),
          draft: const DocumentDraft(
            title: 'Expose',
            content: DocumentContentDraft(
              storageObjectPath: '$_workspaceId/$_documentId/1/expose.pdf',
              contentHash: _hash,
              byteSize: 1024,
              mimeType: 'application/pdf',
            ),
          ),
        ),
      );

      expect(result, isA<DocumentRepositoryFailure<DocumentDto>>());
    });

    // The server's own `message` is a controlled string authored in our
    // migration, and the party adapter deliberately passes it through. What
    // must never escape is an unexpected exception's text, which can carry SDK
    // internals or connection details.
    test('an unexpected exception never leaks its text into the failure',
        () async {
      final gateway = _FakeGateway(
        rpcResponses: const <String, Object?>{},
        throwOnRpc: StateError('postgrest internals: secret-connection-string'),
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.create(
        CreateDocumentCommand(
          context: _context(),
          draft: const DocumentDraft(
            title: 'Expose',
            content: DocumentContentDraft(
              storageObjectPath: '$_workspaceId/$_documentId/1/expose.pdf',
              contentHash: _hash,
              byteSize: 1024,
              mimeType: 'application/pdf',
            ),
          ),
        ),
      );

      final failure = result as DocumentRepositoryFailure<DocumentDto>;
      expect(failure.kind, DocumentRepositoryFailureKind.infrastructureFailure);
      expect(failure.message, isNot(contains('secret-connection-string')));
      expect(failure.message, isNot(contains('postgrest')));
    });
  });

  group('SupabaseDocumentRepositoryAdapter reads', () {
    test('search paginates by keyset and hides the probe row', () async {
      final rows = List<Map<String, dynamic>>.generate(
        3,
        (index) => <String, dynamic>{
          ..._documentSnapshot(status: 'available'),
          'id': 'ed000000-0000-0000-0000-00000000000$index',
        },
      );
      final gateway = _FakeGateway(
        rpcResponses: const <String, Object?>{},
        documents: rows,
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.search(
        const DocumentListQuery(
          workspaceId: _workspaceId,
          page: DocumentPageRequest(limit: 2),
        ),
      );

      final page =
          (result as DocumentRepositorySuccess<DocumentPageResult>).value;
      expect(page.items, hasLength(2));
      expect(page.nextCursor, isNotNull);
      expect(gateway.listDocumentCalls.single.limit, 3);
    });

    test('search passes the entity filter through to the gateway', () async {
      final gateway = _FakeGateway(
        rpcResponses: const <String, Object?>{},
        documents: <Map<String, dynamic>>[_documentSnapshot()],
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      await adapter.search(
        const DocumentListQuery(
          workspaceId: _workspaceId,
          entityType: DocumentLinkEntityType.property,
          entityId: 'e5000000-0000-0000-0000-000000000001',
        ),
      );

      final call = gateway.listDocumentCalls.single;
      expect(call.entityType, 'property');
      expect(call.entityId, 'e5000000-0000-0000-0000-000000000001');
      expect(call.includeInactive, isFalse);
    });

    test('evaluate parses the derived requirement projection', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'evaluate_document_requirements': _ok(<Object>[
            <String, dynamic>{
              'requirement_id': 'er000000-0000-0000-0000-000000000001',
              'document_type_id': 'et000000-0000-0000-0000-000000000001',
              'document_type_key': 'grundbuchauszug',
              'document_type_name': 'Grundbuchauszug',
              'entity_type': 'property',
              'entity_id': 'e5000000-0000-0000-0000-000000000001',
              'scope_key': null,
              'is_mandatory': true,
              'is_instance_rule': false,
              'due_at': null,
              'owner_user_id': null,
              'note': null,
              'document_id': _documentId,
              'document_status': 'verified',
              'document_valid_until': null,
              'state': 'satisfied',
            },
            <String, dynamic>{
              'requirement_id': 'er000000-0000-0000-0000-000000000002',
              'document_type_id': 'et000000-0000-0000-0000-000000000002',
              'document_type_key': 'flurkarte',
              'document_type_name': 'Flurkarte',
              'entity_type': 'property',
              'entity_id': 'e5000000-0000-0000-0000-000000000001',
              'scope_key': null,
              'is_mandatory': true,
              'is_instance_rule': true,
              'due_at': '2026-08-01',
              'owner_user_id': null,
              'note': null,
              'document_id': null,
              'document_status': null,
              'document_valid_until': null,
              'state': 'missing',
            },
          ]),
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.evaluate(
        const DocumentRequirementQuery(
          workspaceId: _workspaceId,
          entityType: DocumentLinkEntityType.property,
          entityId: 'e5000000-0000-0000-0000-000000000001',
        ),
      );

      final rows =
          (result
                  as DocumentRepositorySuccess<
                    List<DocumentRequirementProjection>
                  >)
              .value;
      expect(rows, hasLength(2));
      expect(rows.first.state, DocumentRequirementState.satisfied);
      expect(rows.first.isBlocking, isFalse);
      expect(rows.last.state, DocumentRequirementState.missing);
      // A mandatory, unmet requirement is what the checklist used to call
      // "fehlt" and the compliance engine "missing_required_document".
      expect(rows.last.isBlocking, isTrue);
      expect(rows.last.isInstanceRule, isTrue);
      // A SQL `date` is a calendar date: local midnight, never shifted.
      expect(rows.last.dueAt, DateTime(2026, 8, 1));
    });

    test('evaluateWorkspace sends one call and reports skipped scoped rules', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'evaluate_workspace_document_requirements': <String, dynamic>{
            'ok': true,
            'scoped_rule_count': 2,
            'requirements': <Object>[
              _workspaceRequirementRow(
                entityId: 'e5000000-0000-0000-0000-000000000001',
                state: 'missing',
              ),
              _workspaceRequirementRow(
                entityId: 'e5000000-0000-0000-0000-000000000002',
                state: 'expiring',
              ),
            ],
          },
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.evaluateWorkspace(
        const WorkspaceDocumentRequirementQuery(
          workspaceId: _workspaceId,
          entityType: DocumentLinkEntityType.property,
          entityIds: <String>[
            'e5000000-0000-0000-0000-000000000001',
            'e5000000-0000-0000-0000-000000000002',
          ],
          onlyUnmet: true,
        ),
      );

      final projection =
          (result
                  as DocumentRepositorySuccess<WorkspaceDocumentRequirements>)
              .value;
      expect(projection.requirements, hasLength(2));
      // The whole point of the increment: one round trip for every entity, not
      // one per entity.
      expect(gateway.rpcCalls, hasLength(1));
      final call = gateway.rpcCalls.single;
      expect(call.function, 'evaluate_workspace_document_requirements');
      expect(call.parameters['p_entity_type'], 'property');
      expect(call.parameters['p_entity_ids'], hasLength(2));
      expect(call.parameters['p_only_unmet'], isTrue);
      // Scoped rules are surfaced, so a caller can say what it did not cover.
      expect(projection.scopedRuleCount, 2);
      expect(projection.hasUnevaluatedScopedRules, isTrue);
      expect(projection.blocking, hasLength(1));
    });

    test('evaluateWorkspace omits empty entity ids instead of sending []', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'evaluate_workspace_document_requirements': <String, dynamic>{
            'ok': true,
            'scoped_rule_count': 0,
            'requirements': <Object>[],
          },
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      await adapter.evaluateWorkspace(
        const WorkspaceDocumentRequirementQuery(workspaceId: _workspaceId),
      );

      final call = gateway.rpcCalls.single;
      expect(call.parameters['p_entity_type'], isNull);
      expect(call.parameters['p_entity_ids'], isNull);
    });

    test('evaluateWorkspace rejects a projection outside the requested type', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'evaluate_workspace_document_requirements': <String, dynamic>{
            'ok': true,
            'scoped_rule_count': 0,
            'requirements': <Object>[
              _workspaceRequirementRow(
                entityId: 'e5000000-0000-0000-0000-000000000001',
                state: 'missing',
                entityType: 'lease',
              ),
            ],
          },
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.evaluateWorkspace(
        const WorkspaceDocumentRequirementQuery(
          workspaceId: _workspaceId,
          entityType: DocumentLinkEntityType.property,
        ),
      );

      expect(
        result,
        isA<DocumentRepositoryFailure<WorkspaceDocumentRequirements>>(),
      );
    });

    test('evaluateWorkspace maps a server refusal to forbidden', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'evaluate_workspace_document_requirements': _error('forbidden'),
        },
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.evaluateWorkspace(
        const WorkspaceDocumentRequirementQuery(workspaceId: _workspaceId),
      );

      expect(
        (result as DocumentRepositoryFailure<WorkspaceDocumentRequirements>)
            .kind,
        DocumentRepositoryFailureKind.forbidden,
      );
    });

    test('upload puts the bytes in the private bucket and declares them', () async {
      final gateway = _FakeGateway(rpcResponses: const <String, Object?>{});
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);
      final bytes = Uint8List.fromList(utf8.encode('Mietvertrag'));

      final result = await adapter.upload(
        workspaceId: _workspaceId,
        scopeId: 'scope-1',
        versionNo: 1,
        filename: 'mietvertrag.pdf',
        mimeType: 'application/pdf',
        bytes: bytes,
      );

      final draft =
          (result as DocumentRepositorySuccess<DocumentContentDraft>).value;
      final call = gateway.uploadCalls.single;
      expect(call.bucket, DocumentUploadPort.bucket);
      // The path convention the storage policy and the RPC both check:
      // {workspace}/{scope}/{version}/{file}, workspace-prefixed.
      expect(call.path, '$_workspaceId/scope-1/1/mietvertrag.pdf');
      expect(draft.storageObjectPath, call.path);
      expect(draft.byteSize, bytes.length);
      // The declaration must be the hash of what was really sent, or
      // confirm_document_content would reject the document.
      expect(draft.contentHash, sha256.convert(bytes).toString());
      expect(draft.originalFilename, 'mietvertrag.pdf');
    });

    test('upload refuses a file over the bucket limit before sending it', () async {
      final gateway = _FakeGateway(rpcResponses: const <String, Object?>{});
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.upload(
        workspaceId: _workspaceId,
        scopeId: 'scope-1',
        versionNo: 1,
        filename: 'gross.bin',
        mimeType: 'application/octet-stream',
        bytes: Uint8List(DocumentUploadPort.maxByteSize + 1),
      );

      expect(
        (result as DocumentRepositoryFailure<DocumentContentDraft>).kind,
        DocumentRepositoryFailureKind.validationFailed,
      );
      expect(gateway.uploadCalls, isEmpty);
    });

    test('upload refuses an empty file', () async {
      final gateway = _FakeGateway(rpcResponses: const <String, Object?>{});
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.upload(
        workspaceId: _workspaceId,
        scopeId: 'scope-1',
        versionNo: 1,
        filename: 'leer.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List(0),
      );

      expect(
        (result as DocumentRepositoryFailure<DocumentContentDraft>).kind,
        DocumentRepositoryFailureKind.validationFailed,
      );
      expect(gateway.uploadCalls, isEmpty);
    });

    test('a refused upload never leaks the storage error text', () async {
      final gateway =
          _FakeGateway(rpcResponses: const <String, Object?>{})
            ..throwOnUpload = StateError('duplicate key value violates …');
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.upload(
        workspaceId: _workspaceId,
        scopeId: 'scope-1',
        versionNo: 1,
        filename: 'mietvertrag.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );

      final failure = result as DocumentRepositoryFailure<DocumentContentDraft>;
      expect(failure.kind, DocumentRepositoryFailureKind.infrastructureFailure);
      expect(failure.message, isNot(contains('duplicate key')));
    });

    test('the object path stays inside the workspace prefix', () {
      // A traversal attempt must not escape the workspace folder, because that
      // prefix is the whole storage isolation.
      final path = DocumentUploadPort.storageObjectPath(
        workspaceId: _workspaceId,
        scopeId: 'scope-1',
        versionNo: 2,
        filename: '../../etc/passwd',
      );

      expect(path.startsWith('$_workspaceId/'), isTrue);
      expect(path.contains('..'), isFalse);
    });

    test('listVersions rejects a version from another workspace', () async {
      final gateway = _FakeGateway(
        rpcResponses: const <String, Object?>{},
        versions: <Map<String, dynamic>>[
          _versionSnapshot(workspaceId: _otherWorkspaceId),
        ],
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.listVersions(
        workspaceId: _workspaceId,
        documentId: _documentId,
      );

      expect(
        result,
        isA<DocumentRepositoryFailure<List<DocumentVersionDto>>>(),
      );
    });

    test('listVersions normalises a bytea-encoded hash to lowercase hex', () async {
      // A direct PostgREST read of `document_versions` serialises the bytea
      // column as `\x…`, while the RPC snapshots emit plain hex. The DTO
      // contract is hex either way.
      final gateway = _FakeGateway(
        rpcResponses: const <String, Object?>{},
        versions: <Map<String, dynamic>>[
          _versionSnapshot(contentHash: '\\x${_hash.toUpperCase()}'),
        ],
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result =
          await adapter.listVersions(
                workspaceId: _workspaceId,
                documentId: _documentId,
              )
              as DocumentRepositorySuccess<List<DocumentVersionDto>>;

      expect(result.value.single.contentHash, _hash);
    });

    test('listVersions rejects a hash that is not a sha256', () async {
      final gateway = _FakeGateway(
        rpcResponses: const <String, Object?>{},
        versions: <Map<String, dynamic>>[
          _versionSnapshot(contentHash: 'nicht-hex'),
        ],
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      expect(
        await adapter.listVersions(
          workspaceId: _workspaceId,
          documentId: _documentId,
        ),
        isA<DocumentRepositoryFailure<List<DocumentVersionDto>>>(),
      );
    });
  });

  group('SupabaseDocumentRepositoryAdapter signed urls', () {
    test('clamps an over-long ttl to the one-hour ceiling', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'resolve_document_content_ref': _ok(_contentRef()),
        },
        signedUrl: 'https://local/storage/signed',
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.createSignedUrl(
        workspaceId: _workspaceId,
        documentId: _documentId,
        ttl: const Duration(hours: 10),
      );

      final signed =
          (result as DocumentRepositorySuccess<SignedDocumentUrl>).value;
      expect(signed.appliedTtl, SignedUrlPort.maxTtl);
      expect(gateway.signedUrlTtlSeconds, SignedUrlPort.maxTtl.inSeconds);
      expect(
        signed.expiresAt.difference(DateTime.now()).inMinutes,
        closeTo(60, 2),
      );
    });

    test('raises a sub-second ttl to the floor and passes the floor through',
        () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'resolve_document_content_ref': _ok(_contentRef()),
        },
        signedUrl: 'https://local/storage/signed',
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final raised = await adapter.createSignedUrl(
        workspaceId: _workspaceId,
        documentId: _documentId,
        ttl: Duration.zero,
      );
      expect(
        (raised as DocumentRepositorySuccess<SignedDocumentUrl>).value
            .appliedTtl,
        SignedUrlPort.minTtl,
      );
      expect(gateway.signedUrlTtlSeconds, SignedUrlPort.minTtl.inSeconds);

      // Exactly the floor is a valid request and is applied as asked -- the
      // clamp only ever narrows, it never widens a window.
      final atFloor = await adapter.createSignedUrl(
        workspaceId: _workspaceId,
        documentId: _documentId,
        ttl: const Duration(seconds: 1),
      );
      expect(
        (atFloor as DocumentRepositorySuccess<SignedDocumentUrl>).value
            .appliedTtl,
        const Duration(seconds: 1),
      );
      expect(gateway.signedUrlTtlSeconds, 1);
      expect(SignedUrlPort.minTtl, const Duration(seconds: 1));
      expect(SignedUrlPort.maxTtl, const Duration(hours: 1));
    });

    test('uses the five-minute default when no ttl is requested', () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'resolve_document_content_ref': _ok(_contentRef()),
        },
        signedUrl: 'https://local/storage/signed',
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.createSignedUrl(
        workspaceId: _workspaceId,
        documentId: _documentId,
      );

      expect(
        (result as DocumentRepositorySuccess<SignedDocumentUrl>).value
            .appliedTtl,
        SignedUrlPort.defaultTtl,
      );
      expect(
        gateway.signedUrlTtlSeconds,
        SignedUrlPort.defaultTtl.inSeconds,
      );
    });

    test('never mints a url when the server refuses to resolve the ref',
        () async {
      final gateway = _FakeGateway(
        rpcResponses: <String, Object?>{
          'resolve_document_content_ref': _error('forbidden'),
        },
        signedUrl: 'https://local/storage/signed',
      );
      final adapter = SupabaseDocumentRepositoryAdapter.withGateway(gateway);

      final result = await adapter.createSignedUrl(
        workspaceId: _workspaceId,
        documentId: _documentId,
      );

      expect(
        (result as DocumentRepositoryFailure<SignedDocumentUrl>).kind,
        DocumentRepositoryFailureKind.forbidden,
      );
      expect(gateway.signedUrlTtlSeconds, isNull);
    });
  });
}

Map<String, dynamic> _contentRef() => <String, dynamic>{
  'document_id': _documentId,
  'workspace_id': _workspaceId,
  'version_no': 1,
  'storage_bucket': 'documents',
  'storage_object_path': '$_workspaceId/$_documentId/1/expose.pdf',
  'content_hash': _hash,
  'byte_size': 1024,
  'mime_type': 'application/pdf',
  'original_filename': 'expose.pdf',
  'content_confirmed_at': '2026-07-23T10:30:00.000Z',
  'verification_status': 'verified',
};

class _UploadCall {
  const _UploadCall({
    required this.bucket,
    required this.path,
    required this.mimeType,
    required this.bytes,
  });

  final String bucket;
  final String path;
  final String mimeType;
  final Uint8List bytes;
}

class _RpcCall {
  const _RpcCall(this.function, this.parameters);

  final String function;
  final Map<String, Object?> parameters;
}

class _ListDocumentsCall {
  const _ListDocumentsCall({
    required this.limit,
    required this.includeInactive,
    required this.entityType,
    required this.entityId,
  });

  final int limit;
  final bool includeInactive;
  final String? entityType;
  final String? entityId;
}

class _FakeGateway implements DocumentSupabaseGateway {
  _FakeGateway({
    required Map<String, Object?> rpcResponses,
    List<Map<String, dynamic>>? documents,
    List<Map<String, dynamic>>? versions,
    String? signedUrl,
    Object? throwOnRpc,
  }) : _rpcResponses = rpcResponses,
       _throwOnRpc = throwOnRpc,
       _documents = documents ?? const <Map<String, dynamic>>[],
       _versions = versions ?? const <Map<String, dynamic>>[],
       _signedUrl = signedUrl;

  final Map<String, Object?> _rpcResponses;
  final List<Map<String, dynamic>> _documents;
  final List<Map<String, dynamic>> _versions;
  final String? _signedUrl;
  final Object? _throwOnRpc;

  final List<_RpcCall> rpcCalls = <_RpcCall>[];
  final List<_ListDocumentsCall> listDocumentCalls = <_ListDocumentsCall>[];
  int? signedUrlTtlSeconds;

  @override
  String? get currentUserId => _actorId;

  @override
  Future<List<Map<String, dynamic>>> getDocument({
    required String workspaceId,
    required String documentId,
  }) async => _documents;

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
    listDocumentCalls.add(
      _ListDocumentsCall(
        limit: limit,
        includeInactive: includeInactive,
        entityType: entityType,
        entityId: entityId,
      ),
    );
    return _documents.take(limit).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listVersions({
    required String workspaceId,
    required String documentId,
  }) async => _versions;

  @override
  Future<List<Map<String, dynamic>>> listLinks({
    required String workspaceId,
    required String documentId,
  }) async => const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> listTypes({
    required String workspaceId,
    required bool activeOnly,
  }) async => const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> listRequirements({
    required String workspaceId,
    required String entityType,
    required String? entityId,
  }) async => const <Map<String, dynamic>>[];

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) {
    rpcCalls.add(_RpcCall(function, parameters));
    final failure = _throwOnRpc;
    if (failure != null) {
      throw failure;
    }
    if (!_rpcResponses.containsKey(function)) {
      throw StateError('Unexpected RPC: $function');
    }
    return Future<Object?>.value(_rpcResponses[function]);
  }

  final List<_UploadCall> uploadCalls = <_UploadCall>[];
  Object? throwOnUpload;

  @override
  Future<void> uploadObject({
    required String bucket,
    required String path,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    uploadCalls.add(
      _UploadCall(bucket: bucket, path: path, mimeType: mimeType, bytes: bytes),
    );
    final failure = throwOnUpload;
    if (failure != null) {
      throw failure;
    }
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required int ttlSeconds,
  }) async {
    signedUrlTtlSeconds = ttlSeconds;
    final url = _signedUrl;
    if (url == null) {
      throw StateError('No signed url configured.');
    }
    return url;
  }
}
