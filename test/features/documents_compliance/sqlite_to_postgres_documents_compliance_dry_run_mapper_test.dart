import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_migration_dry_run.dart';
import 'package:neximmo_app/features/documents_compliance/data/sqlite_to_postgres_documents_compliance_dry_run_mapper.dart';

const _mapper = SqliteToPostgresDocumentsComplianceDryRunMapper();

const _filePath = r'C:\legacy\docs\mietvertrag.pdf';
final _bytes = utf8.encode('Mietvertrag-Inhalt');
final _hash = sha256.convert(_bytes).toString();

DocumentMigrationDryRunRequest _request() {
  return const DocumentMigrationDryRunRequest(
    sourceWorkspaceId: 'legacy',
    targetWorkspaceId: 'a1a1a1a1-1111-4111-8111-111111111111',
    targetWorkspaceKey: 'target-workspace',
    migrationActorId: 'b2b2b2b2-2222-4222-9222-222222222222',
  );
}

Map<String, Object?> _documentType({
  String id = 'dt1',
  String name = 'Mietvertrag',
  String entityType = 'property',
}) => <String, Object?>{
  'id': id,
  'name': name,
  'entity_type': entityType,
  'required_fields_json': null,
  'created_at': 1000,
};

Map<String, Object?> _document({
  String id = 'd1',
  String? typeId = 'dt1',
  String entityType = 'property',
  String entityId = 'p1',
  String filePath = _filePath,
  String fileName = 'mietvertrag.pdf',
  String? sha256Hex,
  int? sizeBytes,
}) => <String, Object?>{
  'id': id,
  'entity_type': entityType,
  'entity_id': entityId,
  'type_id': typeId,
  'file_path': filePath,
  'file_name': fileName,
  'mime_type': 'application/pdf',
  'size_bytes': sizeBytes,
  'sha256': sha256Hex,
  'created_at': 1000,
  'created_by': 'local-user',
  'updated_at': 2000,
};

Map<String, Object?> _requiredDocument({
  String id = 'rq1',
  String entityType = 'property',
  String? propertyType = 'residential',
  String typeId = 'dt1',
  int required = 1,
  String? expiresFieldKey,
}) => <String, Object?>{
  'id': id,
  'entity_type': entityType,
  'property_type': propertyType,
  'type_id': typeId,
  'required': required,
  'expires_field_key': expiresFieldKey,
  'created_at': 900,
};

Map<String, Object?> _checklistEntry({
  String id = 'cl1',
  String propertyId = 'p1',
  String documentKey = 'grundbuchauszug',
  String label = 'Grundbuchauszug',
  String status = 'fehlt',
  String? note,
  String? uploadPath,
  int? dueDate,
  String? owner,
}) => <String, Object?>{
  'id': id,
  'property_id': propertyId,
  'document_key': documentKey,
  'label': label,
  'status': status,
  'upload_path': uploadPath,
  'note': note,
  'due_date': dueDate,
  'owner': owner,
  'created_at': 1000,
  'updated_at': 2000,
};

DocumentMigrationSourceSnapshot _snapshot({
  List<Map<String, Object?>>? documentTypes,
  List<Map<String, Object?>>? documents,
  List<Map<String, Object?>>? documentMetadata,
  List<Map<String, Object?>>? requiredDocuments,
  List<Map<String, Object?>>? checklistEntries,
  Map<String, DocumentContentProbe>? contentProbes,
  Map<String, DocumentObjectProbe> uploadedObjects =
      const <String, DocumentObjectProbe>{},
}) {
  return DocumentMigrationSourceSnapshot(
    documentTypes: documentTypes ?? <Map<String, Object?>>[_documentType()],
    documents: documents ?? <Map<String, Object?>>[_document()],
    documentMetadata: documentMetadata ?? const <Map<String, Object?>>[],
    requiredDocuments:
        requiredDocuments ?? <Map<String, Object?>>[_requiredDocument()],
    checklistEntries:
        checklistEntries ?? <Map<String, Object?>>[_checklistEntry()],
    contentProbes:
        contentProbes ??
        <String, DocumentContentProbe>{
          _filePath: DocumentContentProbe(
            exists: true,
            byteSize: _bytes.length,
            sha256Hex: _hash,
          ),
        },
    uploadedObjects: uploadedObjects,
  );
}

DocumentMigrationMapping _documentMapping(DocumentMigrationDryRunReport report) {
  return report.mappings.firstWhere(
    (mapping) => mapping.entity == DocumentMigrationEntity.document,
  );
}

Iterable<String> _codes(
  DocumentMigrationDryRunReport report, {
  DocumentMigrationEntity? entity,
}) => report.issues
    .where((issue) => entity == null || issue.entity == entity)
    .map((issue) => issue.code);

void main() {
  group('SqliteToPostgresDocumentsComplianceDryRunMapper', () {
    test(
      'withholds the content link before upload and grants it once the object '
      'is proven byte-identical, without changing a single planned row',
      () {
        // Pass 1: nothing uploaded yet. This is the legitimate first run.
        final before = _mapper.map(
          snapshot: _snapshot(),
          request: _request(),
        );
        expect(before.status, DocumentMigrationStatus.invalid);
        expect(before.productionImportReady, isFalse);
        expect(before.contentLinkAuthorized, isFalse);
        expect(
          _documentMapping(before).contentLink,
          DocumentContentLinkState.uploadMissing,
        );
        final path = _documentMapping(before).storageObjectPath;
        expect(path, isNotNull);
        expect(before.pendingUploadPaths, <String>[path!]);
        expect(_codes(before), contains('content.upload_missing'));

        // Pass 2: the very same rows, but the object now exists with the
        // hashed bytes.
        final after = _mapper.map(
          snapshot: _snapshot(
            uploadedObjects: <String, DocumentObjectProbe>{
              path: DocumentObjectProbe(
                byteSize: _bytes.length,
                sha256Hex: _hash,
              ),
            },
          ),
          request: _request(),
        );
        expect(after.status, DocumentMigrationStatus.ready);
        expect(after.productionImportReady, isTrue);
        expect(after.contentLinkAuthorized, isTrue);
        expect(
          _documentMapping(after).contentLink,
          DocumentContentLinkState.verified,
        );
        expect(after.pendingUploadPaths, isEmpty);

        // The decisive invariant: the planned rows are identical in both
        // passes. Upload state flips the authorization, never the mapping.
        for (final entity in DocumentMigrationEntity.values) {
          final left = before.summaries.firstWhere((s) => s.entity == entity);
          final right = after.summaries.firstWhere((s) => s.entity == entity);
          expect(
            right.candidateChecksum,
            left.candidateChecksum,
            reason: 'Planned ${entity.name} rows must not depend on upload state.',
          );
        }
        expect(
          _documentMapping(after).targetChecksum,
          _documentMapping(before).targetChecksum,
        );
      },
    );

    test('is deterministic across runs', () {
      final first = _mapper.map(snapshot: _snapshot(), request: _request());
      final second = _mapper.map(snapshot: _snapshot(), request: _request());
      expect(second.manifestChecksum, first.manifestChecksum);
      expect(second.toCanonicalJson(), first.toCanonicalJson());
    });

    test('every entity reconciles on the happy path', () {
      final path = _documentMapping(
        _mapper.map(snapshot: _snapshot(), request: _request()),
      ).storageObjectPath!;
      final report = _mapper.map(
        snapshot: _snapshot(
          uploadedObjects: <String, DocumentObjectProbe>{
            path: DocumentObjectProbe(byteSize: _bytes.length, sha256Hex: _hash),
          },
        ),
        request: _request(),
      );
      expect(report.summaries, hasLength(4));
      for (final summary in report.summaries) {
        expect(summary.sourceRows, 1);
        expect(summary.mappedRows, 1);
        expect(summary.rejectedRows, 0);
        expect(summary.countsReconcile, isTrue);
        expect(summary.checksumsReconcile, isTrue);
        expect(summary.errorCount, 0);
      }
    });

    test('an object of the right size but unproven bytes stays unauthorized', () {
      final path = _documentMapping(
        _mapper.map(snapshot: _snapshot(), request: _request()),
      ).storageObjectPath!;
      final report = _mapper.map(
        snapshot: _snapshot(
          uploadedObjects: <String, DocumentObjectProbe>{
            path: DocumentObjectProbe(byteSize: _bytes.length),
          },
        ),
        request: _request(),
      );
      expect(
        _documentMapping(report).contentLink,
        DocumentContentLinkState.uploadUnhashed,
      );
      expect(report.contentLinkAuthorized, isFalse);
      expect(_codes(report), contains('content.upload_not_hashed'));
    });

    test('a different object at the target path is reported as a mismatch', () {
      final path = _documentMapping(
        _mapper.map(snapshot: _snapshot(), request: _request()),
      ).storageObjectPath!;
      final report = _mapper.map(
        snapshot: _snapshot(
          uploadedObjects: <String, DocumentObjectProbe>{
            path: DocumentObjectProbe(
              byteSize: _bytes.length,
              sha256Hex: sha256.convert(utf8.encode('etwas anderes')).toString(),
            ),
          },
        ),
        request: _request(),
      );
      expect(
        _documentMapping(report).contentLink,
        DocumentContentLinkState.uploadMismatch,
      );
      expect(report.contentLinkAuthorized, isFalse);
      expect(_codes(report), contains('content.upload_hash_mismatch'));
    });

    test('a size mismatch is reported before any hash comparison', () {
      final path = _documentMapping(
        _mapper.map(snapshot: _snapshot(), request: _request()),
      ).storageObjectPath!;
      final report = _mapper.map(
        snapshot: _snapshot(
          uploadedObjects: <String, DocumentObjectProbe>{
            path: DocumentObjectProbe(byteSize: 1, sha256Hex: _hash),
          },
        ),
        request: _request(),
      );
      expect(
        _documentMapping(report).contentLink,
        DocumentContentLinkState.uploadMismatch,
      );
      expect(_codes(report), contains('content.upload_size_mismatch'));
    });

    test('an unreadable local file rejects the document instead of guessing', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          contentProbes: const <String, DocumentContentProbe>{
            _filePath: DocumentContentProbe.missing(),
          },
        ),
        request: _request(),
      );
      final documents = report.summaries.firstWhere(
        (summary) => summary.entity == DocumentMigrationEntity.document,
      );
      expect(documents.mappedRows, 0);
      expect(documents.rejectedRows, 1);
      expect(documents.countsReconcile, isTrue);
      expect(report.mappings.any((m) => m.entity == DocumentMigrationEntity.document), isFalse);
      expect(_codes(report), contains('content.source_missing'));
      expect(report.contentLinkAuthorized, isFalse);
    });

    test('a legacy hash disagreeing with the bytes rejects the row', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          documents: <Map<String, Object?>>[
            _document(sha256Hex: sha256.convert(utf8.encode('alt')).toString()),
          ],
        ),
        request: _request(),
      );
      expect(_codes(report), contains('content.hash_mismatch'));
      expect(
        report.summaries
            .firstWhere((s) => s.entity == DocumentMigrationEntity.document)
            .rejectedRows,
        1,
      );
    });

    test('a declared size disagreeing with the bytes is a warning, bytes win', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          documents: <Map<String, Object?>>[_document(sizeBytes: 999)],
        ),
        request: _request(),
      );
      expect(_codes(report), contains('content.source_size_mismatch'));
      expect(
        report.summaries
            .firstWhere((s) => s.entity == DocumentMigrationEntity.document)
            .mappedRows,
        1,
      );
    });

    test('a property link uses the P1-012 derived id, not the legacy id', () {
      final report = _mapper.map(snapshot: _snapshot(), request: _request());
      expect(_codes(report), contains('mapping.entity_id_derived_from_p1_012'));
      expect(
        SqliteToPostgresDocumentsComplianceDryRunMapper.migratedPropertyId(
          _request().targetWorkspaceId,
          'p1',
        ),
        isNot('p1'),
      );
    });

    test('an unmigrated or unmappable entity type yields no link', () {
      final unmapped = _mapper.map(
        snapshot: _snapshot(
          documents: <Map<String, Object?>>[
            _document(entityType: 'wartungsauftrag', typeId: null),
          ],
        ),
        request: _request(),
      );
      expect(_codes(unmapped), contains('mapping.entity_type_not_mapped'));

      final notDerivable = _mapper.map(
        snapshot: _snapshot(
          documents: <Map<String, Object?>>[
            _document(entityType: 'unit', typeId: null),
          ],
        ),
        request: _request(),
      );
      expect(_codes(notDerivable), contains('mapping.link_not_derivable'));
    });

    test('validity is derived from metadata via the rule expiry field', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          documentMetadata: <Map<String, Object?>>[
            <String, Object?>{
              'id': 'm1',
              'document_id': 'd1',
              'key': 'gueltig_bis',
              'value': '2027-03-31',
            },
          ],
          requiredDocuments: <Map<String, Object?>>[
            _requiredDocument(expiresFieldKey: 'gueltig_bis'),
          ],
        ),
        request: _request(),
      );
      final withExpiry = _documentMapping(report).targetChecksum;
      final without = _documentMapping(
        _mapper.map(snapshot: _snapshot(), request: _request()),
      ).targetChecksum;
      // The metadata really reaches the planned row.
      expect(withExpiry, isNot(without));
      expect(_codes(report), contains('mapping.field_excluded'));
    });

    test('two legacy type names slugifying onto one key reject both', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          documentTypes: <Map<String, Object?>>[
            _documentType(id: 'dt1', name: 'Mietvertrag'),
            _documentType(id: 'dt2', name: 'MIETVERTRAG'),
          ],
          requiredDocuments: const <Map<String, Object?>>[],
        ),
        request: _request(),
      );
      expect(_codes(report), contains('mapping.type_key_collision'));
      final types = report.summaries.firstWhere(
        (summary) => summary.entity == DocumentMigrationEntity.documentType,
      );
      expect(types.rejectedRows, 2);
      // The document survives the loss of its type instead of being dropped.
      expect(_codes(report), contains('mapping.document_type_dropped'));
      expect(
        report.summaries
            .firstWhere((s) => s.entity == DocumentMigrationEntity.document)
            .mappedRows,
        1,
      );
    });

    test('a type whose entity type is free text is rejected, never invented', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          documentTypes: <Map<String, Object?>>[
            _documentType(entityType: 'objekt'),
          ],
          requiredDocuments: const <Map<String, Object?>>[],
        ),
        request: _request(),
      );
      expect(_codes(report), contains('source.unmapped_entity_type'));
      expect(
        report.summaries
            .firstWhere((s) => s.entity == DocumentMigrationEntity.documentType)
            .rejectedRows,
        1,
      );
    });

    test('a rule pointing at an unusable type is rejected', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          documentTypes: const <Map<String, Object?>>[],
          requiredDocuments: <Map<String, Object?>>[_requiredDocument()],
        ),
        request: _request(),
      );
      expect(_codes(report), contains('source.unresolved_document_type'));
      expect(
        report.summaries
            .firstWhere(
              (s) => s.entity == DocumentMigrationEntity.requiredDocument,
            )
            .rejectedRows,
        1,
      );
    });

    test('checklist states project onto the DUP-011 requirement columns', () {
      final requested = _mapper.map(
        snapshot: _snapshot(
          checklistEntries: <Map<String, Object?>>[
            _checklistEntry(status: 'angefordert'),
          ],
        ),
        request: _request(),
      );
      final waived = _mapper.map(
        snapshot: _snapshot(
          checklistEntries: <Map<String, Object?>>[
            _checklistEntry(status: 'nicht_relevant'),
          ],
        ),
        request: _request(),
      );
      final plain = _mapper.map(
        snapshot: _snapshot(
          checklistEntries: <Map<String, Object?>>[
            _checklistEntry(status: 'vorhanden'),
          ],
        ),
        request: _request(),
      );
      String checklistChecksum(DocumentMigrationDryRunReport report) => report
          .mappings
          .firstWhere(
            (m) => m.entity == DocumentMigrationEntity.checklistEntry,
          )
          .targetChecksum;

      // Three distinct rows: requested and waived carry state, "vorhanden"
      // stores no fulfilment at all.
      expect(checklistChecksum(requested), isNot(checklistChecksum(waived)));
      expect(checklistChecksum(requested), isNot(checklistChecksum(plain)));
      expect(checklistChecksum(waived), isNot(checklistChecksum(plain)));
      // "vorhanden" and "fehlt" are both derived per read, so they plan the
      // same row.
      expect(checklistChecksum(plain), checklistChecksum(
        _mapper.map(snapshot: _snapshot(), request: _request()),
      ));
      expect(
        _codes(requested, entity: DocumentMigrationEntity.checklistEntry),
        contains('mapping.checklist_type_synthesized'),
      );
    });

    test('an unknown checklist state is rejected instead of guessed', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          checklistEntries: <Map<String, Object?>>[
            _checklistEntry(status: 'erledigt'),
          ],
        ),
        request: _request(),
      );
      expect(_codes(report), contains('source.unknown_checklist_status'));
      expect(
        report.summaries
            .firstWhere(
              (s) => s.entity == DocumentMigrationEntity.checklistEntry,
            )
            .rejectedRows,
        1,
      );
    });

    test('checklist rows flag the second local file reference and free-text owner', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          checklistEntries: <Map<String, Object?>>[
            _checklistEntry(uploadPath: r'C:\legacy\grundbuch.pdf', owner: 'Max'),
          ],
        ),
        request: _request(),
      );
      final fields = report.issues
          .where(
            (issue) =>
                issue.entity == DocumentMigrationEntity.checklistEntry &&
                issue.code == 'mapping.field_excluded',
          )
          .map((issue) => issue.field)
          .toSet();
      expect(fields, containsAll(<String>['upload_path', 'owner']));
    });

    test('the same checklist key across properties converges on one type', () {
      final report = _mapper.map(
        snapshot: _snapshot(
          checklistEntries: <Map<String, Object?>>[
            _checklistEntry(id: 'cl1', propertyId: 'p1'),
            _checklistEntry(id: 'cl2', propertyId: 'p2'),
          ],
        ),
        request: _request(),
      );
      final typeIds = report.mappings
          .where((m) => m.entity == DocumentMigrationEntity.checklistEntry)
          .map((m) => m.targetChildId)
          .toSet();
      expect(typeIds, hasLength(1));
      final requirementIds = report.mappings
          .where((m) => m.entity == DocumentMigrationEntity.checklistEntry)
          .map((m) => m.targetId)
          .toSet();
      expect(requirementIds, hasLength(2));
    });

    test('an invalid request rejects every row and maps nothing', () {
      final report = _mapper.map(
        snapshot: _snapshot(),
        request: const DocumentMigrationDryRunRequest(
          sourceWorkspaceId: '',
          targetWorkspaceId: 'not-a-uuid',
          targetWorkspaceKey: 'Invalid Key',
          migrationActorId: 'nope',
        ),
      );
      expect(report.status, DocumentMigrationStatus.invalid);
      expect(report.mappings, isEmpty);
      expect(report.contentLinkAuthorized, isFalse);
      expect(
        _codes(report),
        containsAll(<String>[
          'request.invalid_source_workspace_id',
          'request.invalid_target_workspace_id',
          'request.invalid_target_workspace_key',
          'request.invalid_migration_actor_id',
        ]),
      );
      for (final summary in report.summaries) {
        expect(summary.mappedRows, 0);
        expect(summary.rejectedRows, summary.sourceRows);
        expect(summary.countsReconcile, isTrue);
      }
    });

    test('an aborted run reconciles nothing and authorizes nothing', () {
      final report = _mapper.map(
        snapshot: _snapshot(),
        request: _request(),
        abortSignal: const _AlwaysAbort(),
      );
      expect(report.status, DocumentMigrationStatus.aborted);
      expect(report.productionImportReady, isFalse);
      expect(report.contentLinkAuthorized, isFalse);
      expect(_codes(report), contains('run.aborted'));
      for (final summary in report.summaries) {
        expect(summary.checksumsReconcile, isFalse);
        expect(summary.candidateChecksum, isNull);
      }
    });
  });
}

class _AlwaysAbort implements DocumentMigrationAbortSignal {
  const _AlwaysAbort();

  @override
  bool get isAborted => true;
}
