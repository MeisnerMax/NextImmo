import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/documents.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/data/legacy_sqlite_document_repository_adapter.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';

const String _workspaceId = 'legacy-workspace';
const String _propertyId = 'property-1';

int _epoch(DateTime value) => value.millisecondsSinceEpoch;

DocumentRecord _document({
  required String id,
  String entityType = 'property',
  String entityId = _propertyId,
  String? typeId = 'type-expose',
  String filePath = r'C:\NexImmo\docs\expose.pdf',
  String fileName = 'expose.pdf',
  String? sha256 = 'abc123',
  int? sizeBytes = 2048,
  String? mimeType = 'application/pdf',
}) => DocumentRecord(
  id: id,
  entityType: entityType,
  entityId: entityId,
  typeId: typeId,
  filePath: filePath,
  fileName: fileName,
  mimeType: mimeType,
  sizeBytes: sizeBytes,
  sha256: sha256,
  createdAt: _epoch(DateTime(2026, 1, 1)),
  createdBy: 'user-1',
  updatedAt: _epoch(DateTime(2026, 1, 1)),
);

DocumentCommandContext _context() => const DocumentCommandContext(
  workspaceId: _workspaceId,
  actorId: 'user-1',
  mutationId: 'mutation-1',
  correlationId: 'correlation-1',
);

LegacySqliteDocumentRepositoryAdapter _adapter(_FakeSource source) =>
    LegacySqliteDocumentRepositoryAdapter(
      source: source,
      legacyWorkspaceId: _workspaceId,
    );

void main() {
  group('LegacySqliteDocumentRepositoryAdapter projection', () {
    test('projects a legacy document as an available cloud document', () async {
      final adapter = _adapter(
        _FakeSource(documents: <DocumentRecord>[_document(id: 'doc-1')]),
      );

      final result = await adapter.getById(
        workspaceId: _workspaceId,
        documentId: 'doc-1',
      );

      final document =
          (result as DocumentRepositorySuccess<DocumentDto>).value;
      expect(document.status, DocumentStatus.available);
      expect(document.currentVersionNo, 1);
      // Legacy has no optimistic-concurrency token at all.
      expect(document.version, 1);
    });

    test('derives verified from the legacy verification metadata keys',
        () async {
      final adapter = _adapter(
        _FakeSource(
          documents: <DocumentRecord>[_document(id: 'doc-1')],
          metadata: <String, Map<String, String>>{
            'doc-1': <String, String>{'verified_at': '2026-02-01'},
          },
        ),
      );

      final result = await adapter.getById(
        workspaceId: _workspaceId,
        documentId: 'doc-1',
      );

      expect(
        (result as DocumentRepositorySuccess<DocumentDto>).value.status,
        DocumentStatus.verified,
      );
    });

    test('the synthetic version carries the legacy path and hash but no bucket',
        () async {
      final adapter = _adapter(
        _FakeSource(documents: <DocumentRecord>[_document(id: 'doc-1')]),
      );

      final result = await adapter.listVersions(
        workspaceId: _workspaceId,
        documentId: 'doc-1',
      );

      final versions =
          (result as DocumentRepositorySuccess<List<DocumentVersionDto>>).value;
      expect(versions, hasLength(1));
      final version = versions.single;
      expect(version.versionNo, 1);
      expect(version.storageObjectPath, r'C:\NexImmo\docs\expose.pdf');
      expect(version.contentHash, 'abc123');
      // This empty bucket IS the DEBT-007 gap made explicit: there is no cloud
      // object behind a legacy row.
      expect(version.storageBucket, isEmpty);
      expect(version.isContentConfirmed, isFalse);
    });

    test('projects the legacy entity reference as a single link', () async {
      final adapter = _adapter(
        _FakeSource(documents: <DocumentRecord>[_document(id: 'doc-1')]),
      );

      final result = await adapter.listLinks(
        workspaceId: _workspaceId,
        documentId: 'doc-1',
      );

      final links =
          (result as DocumentRepositorySuccess<List<DocumentLinkDto>>).value;
      expect(links, hasLength(1));
      expect(links.single.entityType, DocumentLinkEntityType.property);
      expect(links.single.entityId, _propertyId);
    });

    test('an unmappable legacy entity type degrades to no link, never a throw',
        () async {
      final adapter = _adapter(
        _FakeSource(
          documents: <DocumentRecord>[
            _document(id: 'doc-1', entityType: 'tenant', entityId: 'tenant-9'),
          ],
        ),
      );

      final result = await adapter.listLinks(
        workspaceId: _workspaceId,
        documentId: 'doc-1',
      );

      expect(
        (result as DocumentRepositorySuccess<List<DocumentLinkDto>>).value,
        isEmpty,
      );
    });

    test('projects the legacy type registry with slugified keys', () async {
      final adapter = _adapter(
        _FakeSource(
          types: <DocumentTypeRecord>[
            DocumentTypeRecord(
              id: 'type-expose',
              name: 'Expose',
              entityType: 'property',
              requiredFields: const <String>[],
              createdAt: _epoch(DateTime(2026, 1, 1)),
            ),
          ],
        ),
      );

      final result = await adapter.listTypes(workspaceId: _workspaceId);

      final types =
          (result as DocumentRepositorySuccess<List<DocumentTypeDto>>).value;
      expect(types, hasLength(1));
      expect(types.single.key, 'expose');
      expect(types.single.isActive, isTrue);
    });

    test('projects legacy rules as workspace-level requirements', () async {
      final adapter = _adapter(
        _FakeSource(
          requirements: <RequiredDocumentRecord>[
            RequiredDocumentRecord(
              id: 'req-1',
              entityType: 'property',
              propertyType: 'residential',
              typeId: 'type-expose',
              required: true,
              expiresFieldKey: null,
              createdAt: _epoch(DateTime(2026, 1, 1)),
            ),
          ],
        ),
      );

      final result = await adapter.listRequirements(
        workspaceId: _workspaceId,
        entityType: DocumentLinkEntityType.property,
      );

      final requirements =
          (result as DocumentRepositorySuccess<List<RequiredDocumentDto>>)
              .value;
      expect(requirements, hasLength(1));
      // Legacy rules are always type-level, never instance-level.
      expect(requirements.single.isWorkspaceRule, isTrue);
      expect(requirements.single.scopeKey, 'residential');
    });
  });

  group('LegacySqliteDocumentRepositoryAdapter evaluate', () {
    test('reports missing when no document of the required type exists',
        () async {
      final adapter = _adapter(
        _FakeSource(
          types: <DocumentTypeRecord>[_type('type-expose', 'Expose')],
          requirements: <RequiredDocumentRecord>[_rule('type-expose')],
        ),
      );

      final rows = await _evaluate(adapter);

      expect(rows.single.state, DocumentRequirementState.missing);
      expect(rows.single.isBlocking, isTrue);
    });

    test('reports satisfied for a verified linked document', () async {
      final adapter = _adapter(
        _FakeSource(
          documents: <DocumentRecord>[_document(id: 'doc-1')],
          metadata: <String, Map<String, String>>{
            'doc-1': <String, String>{'verified': 'yes'},
          },
          types: <DocumentTypeRecord>[_type('type-expose', 'Expose')],
          requirements: <RequiredDocumentRecord>[_rule('type-expose')],
        ),
      );

      final rows = await _evaluate(adapter);

      expect(rows.single.state, DocumentRequirementState.satisfied);
      expect(rows.single.isBlocking, isFalse);
    });

    test('reports expired using the legacy expiry metadata key', () async {
      final expired = DateTime.now().subtract(const Duration(days: 5));
      final adapter = _adapter(
        _FakeSource(
          documents: <DocumentRecord>[_document(id: 'doc-1')],
          metadata: <String, Map<String, String>>{
            'doc-1': <String, String>{
              'valid_until': _epoch(expired).toString(),
            },
          },
          types: <DocumentTypeRecord>[_type('type-expose', 'Expose')],
          requirements: <RequiredDocumentRecord>[
            _rule('type-expose', expiresFieldKey: 'valid_until'),
          ],
        ),
      );

      final rows = await _evaluate(adapter);

      expect(rows.single.state, DocumentRequirementState.expired);
    });

    test('reports expiring inside the legacy 45-day window', () async {
      final soon = DateTime.now().add(const Duration(days: 10));
      final adapter = _adapter(
        _FakeSource(
          documents: <DocumentRecord>[_document(id: 'doc-1')],
          metadata: <String, Map<String, String>>{
            'doc-1': <String, String>{'valid_until': _epoch(soon).toString()},
          },
          types: <DocumentTypeRecord>[_type('type-expose', 'Expose')],
          requirements: <RequiredDocumentRecord>[
            _rule('type-expose', expiresFieldKey: 'valid_until'),
          ],
        ),
      );

      final rows = await _evaluate(adapter);

      expect(rows.single.state, DocumentRequirementState.expiring);
    });
  });

  group('LegacySqliteDocumentRepositoryAdapter is read-only', () {
    test('every mutation is refused with dependencyConflict', () async {
      final adapter = _adapter(
        _FakeSource(documents: <DocumentRecord>[_document(id: 'doc-1')]),
      );
      const content = DocumentContentDraft(
        storageObjectPath: 'x',
        contentHash: 'y',
        byteSize: 1,
        mimeType: 'application/pdf',
      );

      final results = <DocumentRepositoryResult<Object?>>[
        await adapter.create(
          CreateDocumentCommand(
            context: _context(),
            draft: const DocumentDraft(title: 'T', content: content),
          ),
        ),
        await adapter.addVersion(
          AddDocumentVersionCommand(
            context: _context(),
            documentId: 'doc-1',
            expectedVersion: 1,
            content: content,
          ),
        ),
        await adapter.confirmContent(
          ConfirmDocumentContentCommand(
            context: _context(),
            documentId: 'doc-1',
            versionNo: 1,
            expectedVersion: 1,
          ),
        ),
        await adapter.verify(
          VerifyDocumentVersionCommand(
            context: _context(),
            documentId: 'doc-1',
            versionNo: 1,
            expectedVersion: 1,
            outcome: DocumentVerificationOutcome.verified,
          ),
        ),
        await adapter.transitionStatus(
          TransitionDocumentStatusCommand(
            context: _context(),
            documentId: 'doc-1',
            expectedVersion: 1,
            transition: DocumentStatusTransition.archive,
          ),
        ),
        await adapter.link(
          LinkDocumentCommand(
            context: _context(),
            documentId: 'doc-1',
            entityType: DocumentLinkEntityType.property,
            entityId: _propertyId,
          ),
        ),
        await adapter.unlink(
          UnlinkDocumentCommand(context: _context(), documentLinkId: 'link-1'),
        ),
        await adapter.upsertType(
          UpsertDocumentTypeCommand(
            context: _context(),
            draft: const DocumentTypeDraft(
              key: 'expose',
              name: 'Expose',
              entityType: DocumentLinkEntityType.property,
            ),
          ),
        ),
        await adapter.upsertRequirement(
          UpsertRequiredDocumentCommand(
            context: _context(),
            draft: const RequiredDocumentDraft(
              entityType: DocumentLinkEntityType.property,
              documentTypeId: 'type-expose',
            ),
          ),
        ),
      ];

      expect(results, hasLength(9));
      for (final result in results) {
        expect(result, isA<DocumentRepositoryFailure<Object?>>());
        expect(
          (result as dynamic).kind,
          DocumentRepositoryFailureKind.dependencyConflict,
        );
      }
    });

    test('a local file has no signing authority', () async {
      final adapter = _adapter(
        _FakeSource(documents: <DocumentRecord>[_document(id: 'doc-1')]),
      );

      final result = await adapter.createSignedUrl(
        workspaceId: _workspaceId,
        documentId: 'doc-1',
      );

      expect(
        (result as DocumentRepositoryFailure<SignedDocumentUrl>).kind,
        DocumentRepositoryFailureKind.dependencyConflict,
      );
    });

    test('a foreign workspace is refused without reading anything', () async {
      final source = _FakeSource(
        documents: <DocumentRecord>[_document(id: 'doc-1')],
      );
      final adapter = _adapter(source);

      final result = await adapter.getById(
        workspaceId: 'another-workspace',
        documentId: 'doc-1',
      );

      expect(
        (result as DocumentRepositoryFailure<DocumentDto>).kind,
        DocumentRepositoryFailureKind.forbidden,
      );
      expect(source.documentReads, 0);
    });
  });
}

Future<List<DocumentRequirementProjection>> _evaluate(
  LegacySqliteDocumentRepositoryAdapter adapter,
) async {
  final result = await adapter.evaluate(
    const DocumentRequirementQuery(
      workspaceId: _workspaceId,
      entityType: DocumentLinkEntityType.property,
      entityId: _propertyId,
    ),
  );
  return (result
          as DocumentRepositorySuccess<List<DocumentRequirementProjection>>)
      .value;
}

DocumentTypeRecord _type(String id, String name) => DocumentTypeRecord(
  id: id,
  name: name,
  entityType: 'property',
  requiredFields: const <String>[],
  createdAt: _epoch(DateTime(2026, 1, 1)),
);

RequiredDocumentRecord _rule(String typeId, {String? expiresFieldKey}) =>
    RequiredDocumentRecord(
      id: 'req-$typeId',
      entityType: 'property',
      propertyType: null,
      typeId: typeId,
      required: true,
      expiresFieldKey: expiresFieldKey,
      createdAt: _epoch(DateTime(2026, 1, 1)),
    );

class _FakeSource implements LegacyDocumentReadSource {
  _FakeSource({
    List<DocumentRecord>? documents,
    Map<String, Map<String, String>>? metadata,
    List<DocumentTypeRecord>? types,
    List<RequiredDocumentRecord>? requirements,
  }) : _documents = documents ?? const <DocumentRecord>[],
       _metadata = metadata ?? const <String, Map<String, String>>{},
       _types = types ?? const <DocumentTypeRecord>[],
       _requirements = requirements ?? const <RequiredDocumentRecord>[];

  final List<DocumentRecord> _documents;
  final Map<String, Map<String, String>> _metadata;
  final List<DocumentTypeRecord> _types;
  final List<RequiredDocumentRecord> _requirements;

  int documentReads = 0;

  @override
  Future<List<DocumentRecord>> listDocuments() async {
    documentReads++;
    return _documents;
  }

  @override
  Future<List<DocumentMetadataRecord>> listMetadata(String documentId) async {
    final entries = _metadata[documentId] ?? const <String, String>{};
    return entries.entries
        .map(
          (entry) => DocumentMetadataRecord(
            id: '$documentId-${entry.key}',
            documentId: documentId,
            key: entry.key,
            value: entry.value,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<DocumentTypeRecord>> listDocumentTypes() async => _types;

  @override
  Future<List<RequiredDocumentRecord>> listRequiredDocuments() async =>
      _requirements;
}
