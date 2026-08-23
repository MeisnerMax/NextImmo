import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/data/supabase_document_repository_adapter.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const workspaceId = 'e1000000-0000-0000-0000-000000000001';
  const adminId = 'ea000000-0000-0000-0000-000000000001';
  const propertyId = 'e5000000-0000-0000-0000-000000000001';
  const bucket = 'documents';

  var mutationCounter = 0;
  DocumentCommandContext context(String actorId, {String? reason}) {
    mutationCounter++;
    final suffix = mutationCounter.toString().padLeft(2, '0');
    return DocumentCommandContext(
      workspaceId: workspaceId,
      actorId: actorId,
      mutationId: 'e6000000-0000-0000-0000-0000000000$suffix',
      correlationId: 'e7000000-0000-0000-0000-0000000000$suffix',
      reason: reason,
    );
  }

  Future<int> statusOf(String signedUrl) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(signedUrl));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  test(
    'real client drives the document lifecycle, signed-url expiry and storage '
    'isolation end to end',
    () async {
      expect(url, isNotEmpty, reason: 'SUPABASE_URL dart define is required.');
      expect(
        publishableKey,
        isNotEmpty,
        reason: 'SUPABASE_PUBLISHABLE_KEY dart define is required.',
      );
      expect(
        Uri.tryParse(url)?.host,
        anyOf('127.0.0.1', 'localhost', '::1'),
        reason: 'This integration test is restricted to local Supabase.',
      );

      final adminClient = createSupabaseTestClient(url, publishableKey);
      final viewerClient = createSupabaseTestClient(url, publishableKey);
      try {
        await adminClient.auth.signInWithPassword(
          email: 'p2-d03-admin@example.test',
          password: 'NexImmo-Test-2026!',
        );
        await elevateSupabaseTestClientToAal2(adminClient);
        final adminRepo = SupabaseDocumentRepositoryAdapter(client: adminClient);

        // --- type registry and a workspace requirement rule -----------------
        final type =
            (await adminRepo.upsertType(
                  UpsertDocumentTypeCommand(
                    context: context(adminId, reason: 'integration type'),
                    draft: const DocumentTypeDraft(
                      key: 'mietvertrag',
                      name: 'Mietvertrag',
                      entityType: DocumentLinkEntityType.property,
                    ),
                  ),
                ))
                as DocumentRepositorySuccess<DocumentTypeDto>;
        expect(type.value.key, 'mietvertrag');

        await adminRepo.upsertRequirement(
          UpsertRequiredDocumentCommand(
            context: context(adminId),
            draft: RequiredDocumentDraft(
              entityType: DocumentLinkEntityType.property,
              documentTypeId: type.value.id,
              entityId: propertyId,
            ),
          ),
        );

        final missing =
            (await adminRepo.evaluate(
                  const DocumentRequirementQuery(
                    workspaceId: workspaceId,
                    entityType: DocumentLinkEntityType.property,
                    entityId: propertyId,
                  ),
                ))
                as DocumentRepositorySuccess<
                  List<DocumentRequirementProjection>
                >;
        expect(missing.value, hasLength(1));
        expect(missing.value.single.state, DocumentRequirementState.missing);

        // --- upload the real bytes through the port --------------------------
        // Not the raw SDK: this is the path a screen actually takes, so the
        // test proves the port satisfies the storage policy and produces a
        // declaration `confirm_document_content` will accept.
        final bytes = Uint8List.fromList(
          utf8.encode('P2-D03 Mietvertrag, Fassung 1'),
        );
        final uploaded =
            (await adminRepo.upload(
                  workspaceId: workspaceId,
                  scopeId: 'f0000000-0000-0000-0000-000000000001',
                  versionNo: 1,
                  filename: 'vertrag.pdf',
                  mimeType: 'application/pdf',
                  bytes: bytes,
                ))
                as DocumentRepositorySuccess<DocumentContentDraft>;
        final objectPath = uploaded.value.storageObjectPath;
        final contentHash = uploaded.value.contentHash;
        expect(contentHash, sha256.convert(bytes).toString());

        // --- create -> confirm ----------------------------------------------
        final created =
            (await adminRepo.create(
                  CreateDocumentCommand(
                    context: context(adminId, reason: 'integration create'),
                    draft: DocumentDraft(
                      title: 'Mietvertrag Wohnung 1',
                      documentTypeId: type.value.id,
                      // Exactly what the port returned — no hand-built
                      // declaration anywhere in the workflow.
                      content: uploaded.value,
                    ),
                  ),
                ))
                as DocumentRepositorySuccess<DocumentDto>;
        var document = created.value;
        expect(document.status, DocumentStatus.uploaded);
        expect(document.currentVersionNo, 1);
        expect(document.currentVersion?.isContentConfirmed, isFalse);

        final confirmed =
            (await adminRepo.confirmContent(
                  ConfirmDocumentContentCommand(
                    context: context(adminId),
                    documentId: document.id,
                    versionNo: 1,
                    expectedVersion: document.version,
                  ),
                ))
                as DocumentRepositorySuccess<DocumentDto>;
        document = confirmed.value;
        expect(document.status, DocumentStatus.available);
        expect(document.currentVersion?.isContentConfirmed, isTrue);

        final link =
            (await adminRepo.link(
                  LinkDocumentCommand(
                    context: context(adminId),
                    documentId: document.id,
                    entityType: DocumentLinkEntityType.property,
                    entityId: propertyId,
                  ),
                ))
                as DocumentRepositorySuccess<DocumentLinkDto>;
        expect(link.value.entityId, propertyId);

        final pending =
            (await adminRepo.evaluate(
                  const DocumentRequirementQuery(
                    workspaceId: workspaceId,
                    entityType: DocumentLinkEntityType.property,
                    entityId: propertyId,
                  ),
                ))
                as DocumentRepositorySuccess<
                  List<DocumentRequirementProjection>
                >;
        expect(
          pending.value.single.state,
          DocumentRequirementState.pendingVerification,
        );

        // --- verify -----------------------------------------------------------
        final verified =
            (await adminRepo.verify(
                  VerifyDocumentVersionCommand(
                    context: context(adminId, reason: 'integration verify'),
                    documentId: document.id,
                    versionNo: 1,
                    expectedVersion: document.version,
                    outcome: DocumentVerificationOutcome.verified,
                    note: 'Original geprüft',
                  ),
                ))
                as DocumentRepositorySuccess<DocumentVersionDto>;
        expect(
          verified.value.verificationStatus,
          DocumentVerificationStatus.verified,
        );
        expect(verified.value.contentHash, contentHash);

        document =
            (await adminRepo.getById(
                      workspaceId: workspaceId,
                      documentId: document.id,
                    )
                    as DocumentRepositorySuccess<DocumentDto>)
                .value;
        expect(document.status, DocumentStatus.verified);

        final satisfied =
            (await adminRepo.evaluate(
                  const DocumentRequirementQuery(
                    workspaceId: workspaceId,
                    entityType: DocumentLinkEntityType.property,
                    entityId: propertyId,
                  ),
                ))
                as DocumentRepositorySuccess<
                  List<DocumentRequirementProjection>
                >;
        expect(satisfied.value.single.state, DocumentRequirementState.satisfied);

        // --- workspace-wide projection (P2-D03 follow-up increment) ----------
        // One call covers every entity, and because both entry points share
        // `private.document_requirement_state` server-side they must agree on
        // the same entity — verified here against the real RPC, not a fake.
        final workspaceWide =
            (await adminRepo.evaluateWorkspace(
                  const WorkspaceDocumentRequirementQuery(
                    workspaceId: workspaceId,
                    entityType: DocumentLinkEntityType.property,
                    entityIds: <String>[propertyId],
                  ),
                ))
                as DocumentRepositorySuccess<WorkspaceDocumentRequirements>;
        final projected =
            workspaceWide.value.requirements
                .where((row) => row.entityId == propertyId)
                .toList(growable: false);
        expect(projected, hasLength(1));
        expect(projected.single.state, DocumentRequirementState.satisfied);
        expect(projected.single.requirementId, satisfied.value.single.requirementId);
        expect(workspaceWide.value.scopedRuleCount, 0);
        expect(workspaceWide.value.blocking, isEmpty);

        // The compliance view asks only for what is outstanding.
        final outstanding =
            (await adminRepo.evaluateWorkspace(
                  const WorkspaceDocumentRequirementQuery(
                    workspaceId: workspaceId,
                    entityType: DocumentLinkEntityType.property,
                    entityIds: <String>[propertyId],
                    onlyUnmet: true,
                  ),
                ))
                as DocumentRepositorySuccess<WorkspaceDocumentRequirements>;
        expect(
          outstanding.value.requirements.where(
            (row) => row.entityId == propertyId,
          ),
          isEmpty,
        );

        // --- signed url: clamping, real fetch, real expiry --------------------
        final wide =
            (await adminRepo.createSignedUrl(
                  workspaceId: workspaceId,
                  documentId: document.id,
                  ttl: const Duration(hours: 10),
                ))
                as DocumentRepositorySuccess<SignedDocumentUrl>;
        expect(
          wide.value.appliedTtl,
          SignedUrlPort.maxTtl,
          reason: 'A caller must not be able to widen the window.',
        );

        // The floor is one second: a shorter request is raised to it, and
        // exactly one second is applied as asked, not widened. Neither url is
        // fetched while it is fresh -- a one-second window is a correct policy
        // boundary, not a scheduling budget a mint-then-GET round trip can be
        // expected to fit on a slow runner (TEST-STABILITY-P2D03-01).
        final belowFloor =
            (await adminRepo.createSignedUrl(
                  workspaceId: workspaceId,
                  documentId: document.id,
                  ttl: Duration.zero,
                ))
                as DocumentRepositorySuccess<SignedDocumentUrl>;
        expect(
          belowFloor.value.appliedTtl,
          SignedUrlPort.minTtl,
          reason: 'A caller cannot ask for a window shorter than the floor.',
        );
        final shortLived =
            (await adminRepo.createSignedUrl(
                  workspaceId: workspaceId,
                  documentId: document.id,
                  ttl: const Duration(seconds: 1),
                ))
                as DocumentRepositorySuccess<SignedDocumentUrl>;
        expect(shortLived.value.appliedTtl, const Duration(seconds: 1));
        expect(shortLived.value.contentRef.storageObjectPath, objectPath);

        // One url that really serves the object and then really stops -- this
        // is why it cannot live in pgTAP. The window is wide enough that the
        // first GET cannot lose a race against the runner, and short enough to
        // wait out.
        const servedTtl = Duration(seconds: 5);
        final served =
            (await adminRepo.createSignedUrl(
                  workspaceId: workspaceId,
                  documentId: document.id,
                  ttl: servedTtl,
                ))
                as DocumentRepositorySuccess<SignedDocumentUrl>;
        expect(served.value.appliedTtl, servedTtl);
        expect(served.value.contentRef.storageObjectPath, objectPath);
        expect(await statusOf(served.value.url), 200);

        // Anchored to expiresAt rather than to a fixed sleep, so the time the
        // GET above took counts toward it. expiresAt is stamped client-side
        // after the mint returned, so it is never earlier than the token's
        // own exp; the margin covers that claim's one-second granularity.
        final remaining = served.value.expiresAt
            .add(const Duration(seconds: 2))
            .difference(DateTime.now());
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
        expect(
          await statusOf(served.value.url),
          isNot(200),
          reason: 'An expired signed url must no longer serve the object.',
        );
        expect(
          await statusOf(shortLived.value.url),
          isNot(200),
          reason: 'The one-second url has long expired as well.',
        );

        // --- supersede -> archive ---------------------------------------------
        final successorBytes = Uint8List.fromList(
          utf8.encode('P2-D03 Mietvertrag, Fassung 2 (Nachtrag)'),
        );
        const successorPath =
            '$workspaceId/f0000000-0000-0000-0000-000000000002/1/nachtrag.pdf';
        await adminClient.storage
            .from(bucket)
            .uploadBinary(
              successorPath,
              successorBytes,
              fileOptions: const FileOptions(contentType: 'application/pdf'),
            );
        final successor =
            (await adminRepo.create(
                  CreateDocumentCommand(
                    context: context(adminId),
                    draft: DocumentDraft(
                      title: 'Mietvertrag Wohnung 1 (Nachtrag)',
                      documentTypeId: type.value.id,
                      content: DocumentContentDraft(
                        storageObjectPath: successorPath,
                        contentHash: sha256.convert(successorBytes).toString(),
                        byteSize: successorBytes.length,
                        mimeType: 'application/pdf',
                        originalFilename: 'nachtrag.pdf',
                      ),
                    ),
                  ),
                ))
                as DocumentRepositorySuccess<DocumentDto>;

        final superseded =
            (await adminRepo.transitionStatus(
                  TransitionDocumentStatusCommand(
                    context: context(adminId, reason: 'integration supersede'),
                    documentId: document.id,
                    expectedVersion: document.version,
                    transition: DocumentStatusTransition.supersede,
                    supersededByDocumentId: successor.value.id,
                  ),
                ))
                as DocumentRepositorySuccess<DocumentDto>;
        expect(superseded.value.status, DocumentStatus.superseded);
        expect(superseded.value.supersededByDocumentId, successor.value.id);

        // The superseded document keeps its hash and its verification outcome.
        final versions =
            (await adminRepo.listVersions(
                  workspaceId: workspaceId,
                  documentId: document.id,
                ))
                as DocumentRepositorySuccess<List<DocumentVersionDto>>;
        expect(versions.value, hasLength(1));
        expect(versions.value.single.contentHash, contentHash);
        expect(
          versions.value.single.verificationStatus,
          DocumentVerificationStatus.verified,
        );

        // A stale transition returns a structured conflict carrying the
        // current document.
        final stale = await adminRepo.transitionStatus(
          TransitionDocumentStatusCommand(
            context: context(adminId),
            documentId: document.id,
            expectedVersion: document.version,
            transition: DocumentStatusTransition.archive,
          ),
        );
        final conflict = stale as DocumentRepositoryFailure<DocumentDto>;
        expect(conflict.kind, DocumentRepositoryFailureKind.versionConflict);
        expect(
          conflict.versionConflict?.currentDocument.version,
          superseded.value.version,
        );

        final archived =
            (await adminRepo.transitionStatus(
                  TransitionDocumentStatusCommand(
                    context: context(adminId, reason: 'integration archive'),
                    documentId: document.id,
                    expectedVersion: superseded.value.version,
                    transition: DocumentStatusTransition.archive,
                  ),
                ))
                as DocumentRepositorySuccess<DocumentDto>;
        expect(archived.value.status, DocumentStatus.archived);
        expect(archived.value.archivedAt, isNotNull);

        // Archived documents leave the active list but stay auditable.
        final active =
            (await adminRepo.search(
                  const DocumentListQuery(workspaceId: workspaceId),
                ))
                as DocumentRepositorySuccess<DocumentPageResult>;
        expect(
          active.value.items.map((item) => item.id),
          isNot(contains(document.id)),
        );
        final auditView =
            (await adminRepo.search(
                  const DocumentListQuery(
                    workspaceId: workspaceId,
                    includeInactive: true,
                  ),
                ))
                as DocumentRepositorySuccess<DocumentPageResult>;
        expect(
          auditView.value.items.map((item) => item.id),
          contains(document.id),
        );

        // --- MIG-BND-003: an unconfirmable upload drives the error path -------
        final ghost =
            (await adminRepo.create(
                  CreateDocumentCommand(
                    context: context(adminId),
                    draft: DocumentDraft(
                      title: 'Nie hochgeladen',
                      content: DocumentContentDraft(
                        storageObjectPath:
                            '$workspaceId/f0000000-0000-0000-0000-000000000003/1/fehlt.pdf',
                        contentHash: contentHash,
                        byteSize: bytes.length,
                        mimeType: 'application/pdf',
                      ),
                    ),
                  ),
                ))
                as DocumentRepositorySuccess<DocumentDto>;
        final rejected =
            (await adminRepo.confirmContent(
                  ConfirmDocumentContentCommand(
                    context: context(adminId),
                    documentId: ghost.value.id,
                    versionNo: 1,
                    expectedVersion: ghost.value.version,
                  ),
                ))
                as DocumentRepositorySuccess<DocumentDto>;
        expect(
          rejected.value.status,
          DocumentStatus.rejected,
          reason:
              'A declared object that never landed must not be published.',
        );

        // --- workspace-scoped storage isolation, over the real Storage API ----
        var foreignUploadDenied = false;
        try {
          await adminClient.storage
              .from(bucket)
              .uploadBinary(
                'f9999999-9999-4999-8999-999999999999/x/1/fremd.pdf',
                bytes,
              );
        } on StorageException {
          foreignUploadDenied = true;
        }
        expect(
          foreignUploadDenied,
          isTrue,
          reason: 'A member may not write under a foreign workspace prefix.',
        );

        var malformedPrefixDenied = false;
        try {
          await adminClient.storage
              .from(bucket)
              .uploadBinary('nicht-uuid/1/fremd.pdf', bytes);
        } on StorageException {
          malformedPrefixDenied = true;
        }
        expect(
          malformedPrefixDenied,
          isTrue,
          reason: 'An unparseable prefix must fail closed, not fall through.',
        );

        // --- the viewer holds workspace.read only ----------------------------
        await viewerClient.auth.signInWithPassword(
          email: 'p2-d03-viewer@example.test',
          password: 'NexImmo-Test-2026!',
        );
        await elevateSupabaseTestClientToAal2(viewerClient);
        final viewerRepo = SupabaseDocumentRepositoryAdapter(
          client: viewerClient,
        );

        final viewerSearch =
            (await viewerRepo.search(
                  const DocumentListQuery(workspaceId: workspaceId),
                ))
                as DocumentRepositorySuccess<DocumentPageResult>;
        expect(viewerSearch.value.items, isEmpty);

        final viewerRef = await viewerRepo.resolveContentRef(
          workspaceId: workspaceId,
          documentId: successor.value.id,
        );
        expect(
          (viewerRef as DocumentRepositoryFailure<DocumentContentRef>).kind,
          DocumentRepositoryFailureKind.forbidden,
        );

        final viewerUrl = await viewerRepo.createSignedUrl(
          workspaceId: workspaceId,
          documentId: successor.value.id,
        );
        expect(
          (viewerUrl as DocumentRepositoryFailure<SignedDocumentUrl>).kind,
          DocumentRepositoryFailureKind.forbidden,
          reason: 'No url is ever minted for content the caller may not read.',
        );

        // Bypassing the repository does not help: the bucket itself is closed.
        var viewerDownloadDenied = false;
        try {
          await viewerClient.storage.from(bucket).download(objectPath);
        } on StorageException {
          viewerDownloadDenied = true;
        }
        expect(viewerDownloadDenied, isTrue);

        final viewerListing = await viewerClient.storage
            .from(bucket)
            .list(path: workspaceId);
        expect(viewerListing, isEmpty);

        var viewerUploadDenied = false;
        try {
          await viewerClient.storage
              .from(bucket)
              .uploadBinary(
                '$workspaceId/f0000000-0000-0000-0000-000000000009/1/x.pdf',
                bytes,
              );
        } on StorageException {
          viewerUploadDenied = true;
        }
        expect(viewerUploadDenied, isTrue);
      } finally {
        await viewerClient.auth.signOut();
        await adminClient.auth.signOut();
      }
    },
    skip: url.isEmpty || publishableKey.isEmpty
        ? 'Requires the local Supabase integration harness.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
