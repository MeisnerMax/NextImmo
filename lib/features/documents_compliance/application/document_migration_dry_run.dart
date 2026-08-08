// Deterministic, read-only dry-run contract for migrating the legacy
// documents / document_types / required_documents / property_document_checklist
// stores into the canonical documents_compliance schema (P2-D03 step 7,
// MIG-BND-003).
//
// Mirrors the P2-D02 party mapper: UUIDv5 target ids, canonical JSON + SHA-256
// reconciliation checksums, per-entity count/checksum reconciliation and a
// signed manifest. No legacy table is dropped until this report reconciles.
//
// The one thing documents need and parties did not: a legacy row points at a
// *local* file (`documents.file_path`), not at a cloud object (DEBT-007). The
// content is therefore hashed from the source bytes and the uploaded object is
// verified against that hash *before* the content link is considered
// switchable, and the report withholds that authorization until every entity
// reconciles. Target documents are always emitted as `uploaded` with a null
// `content_confirmed_at`, so "nothing is switched before reconciliation" is a
// property of the emitted rows, not a convention the operator has to honour.
import 'dart:convert';

import 'package:crypto/crypto.dart';

const documentMigrationContractVersion = 1;

/// The single private bucket confirmed for P2-D03; `document_versions` pins it
/// with a check constraint, so the mapper never invents another one.
const documentMigrationStorageBucket = 'documents';

const _documentMigrationHashDomain = 'neximmo:p2-d03:v1\n';

class DocumentMigrationDryRunRequest {
  const DocumentMigrationDryRunRequest({
    required this.sourceWorkspaceId,
    required this.targetWorkspaceId,
    required this.targetWorkspaceKey,
    required this.migrationActorId,
  });

  final String sourceWorkspaceId;
  final String targetWorkspaceId;
  final String targetWorkspaceKey;
  final String migrationActorId;

  Map<String, Object?> toCanonicalMap() => <String, Object?>{
    'migration_actor_id': migrationActorId,
    'source_workspace_id': sourceWorkspaceId,
    'storage_bucket': documentMigrationStorageBucket,
    'target_workspace_id': targetWorkspaceId,
    'target_workspace_key': targetWorkspaceKey,
  };
}

/// What the local file behind `documents.file_path` really contains. Produced
/// by the source (which does the IO and the hashing) so the mapper itself stays
/// pure and deterministic.
class DocumentContentProbe {
  const DocumentContentProbe({
    required this.exists,
    this.byteSize,
    this.sha256Hex,
    this.readError,
  });

  /// A path that could not be resolved at all.
  const DocumentContentProbe.missing()
    : exists = false,
      byteSize = null,
      sha256Hex = null,
      readError = null;

  final bool exists;
  final int? byteSize;

  /// Lowercase hex SHA-256 of the real bytes; null when the file could not be
  /// read, which is a blocking condition, never a silently skipped one.
  final String? sha256Hex;
  final String? readError;

  bool get isReadable =>
      exists && byteSize != null && sha256Hex != null && readError == null;
}

/// What actually landed in the private bucket at a given object path.
///
/// [sha256Hex] is optional because Supabase Storage exposes size natively but
/// not a SHA-256 — obtaining one means downloading the object back. A probe
/// without a hash is therefore *not* treated as verified
/// ([DocumentContentLinkState.uploadUnhashed]): size equality is too weak a
/// guarantee to switch a content link on.
class DocumentObjectProbe {
  const DocumentObjectProbe({required this.byteSize, this.sha256Hex});

  final int byteSize;
  final String? sha256Hex;
}

class DocumentMigrationSourceSnapshot {
  const DocumentMigrationSourceSnapshot({
    required this.documentTypes,
    required this.documents,
    required this.documentMetadata,
    required this.requiredDocuments,
    required this.checklistEntries,
    required this.contentProbes,
    required this.uploadedObjects,
  });

  final List<Map<String, Object?>> documentTypes;
  final List<Map<String, Object?>> documents;

  /// Raw `document_metadata` rows; legacy validity lives here, keyed by the
  /// `required_documents.expires_field_key` of the matching rule.
  final List<Map<String, Object?>> documentMetadata;
  final List<Map<String, Object?>> requiredDocuments;
  final List<Map<String, Object?>> checklistEntries;

  /// Keyed by the legacy `documents.file_path`.
  final Map<String, DocumentContentProbe> contentProbes;

  /// Keyed by the target `storage_object_path`. Empty on a pre-upload dry run,
  /// which is a legitimate first pass: the report then lists exactly which
  /// objects still have to be uploaded.
  final Map<String, DocumentObjectProbe> uploadedObjects;
}

abstract interface class DocumentMigrationSource {
  Future<DocumentMigrationSourceSnapshot> read();
}

abstract interface class DocumentMigrationAbortSignal {
  bool get isAborted;
}

class NeverAbortDocumentMigration implements DocumentMigrationAbortSignal {
  const NeverAbortDocumentMigration();

  @override
  bool get isAborted => false;
}

enum DocumentMigrationStatus { ready, invalid, aborted }

enum DocumentMigrationEntity {
  documentType,
  document,
  requiredDocument,
  checklistEntry,
}

enum DocumentMigrationIssueSeverity { warning, error }

/// The MIG-BND-003 content-binding verdict for one legacy document. Only
/// [verified] authorizes switching the content link, and only once the whole
/// report reconciles.
enum DocumentContentLinkState {
  /// The row never got as far as content binding (it failed metadata mapping).
  notApplicable,

  /// The local file behind `file_path` does not exist or could not be read.
  sourceMissing,

  /// The legacy `documents.sha256` column disagrees with the hashed bytes.
  hashMismatch,

  /// Hashed, but nothing has been uploaded to the target object path yet.
  uploadMissing,

  /// An object exists at the target path but its bytes are not the source's.
  uploadMismatch,

  /// An object of the right size exists but was not hashed back, so byte
  /// identity is unproven. Deliberately not authorizing.
  uploadUnhashed,

  /// Hashed locally and proven byte-identical in the bucket.
  verified;

  bool get authorizesContentLink => this == DocumentContentLinkState.verified;
}

class DocumentMigrationIssue {
  const DocumentMigrationIssue({
    required this.code,
    required this.severity,
    this.entity,
    this.sourceId,
    this.field,
  });

  final String code;
  final DocumentMigrationIssueSeverity severity;
  final DocumentMigrationEntity? entity;
  final String? sourceId;
  final String? field;

  Map<String, Object?> toCanonicalMap() => <String, Object?>{
    'code': code,
    'entity': entity?.name,
    'field': field,
    'severity': severity.name,
    'source_id': sourceId,
  };
}

class DocumentMigrationMapping {
  const DocumentMigrationMapping({
    required this.entity,
    required this.sourceId,
    required this.targetId,
    required this.sourceChecksum,
    required this.targetChecksum,
    this.targetChildId,
    this.contentLink = DocumentContentLinkState.notApplicable,
    this.storageObjectPath,
  });

  final DocumentMigrationEntity entity;
  final String sourceId;

  /// The primary target row id (document, type or requirement).
  final String targetId;

  /// The dependent row a single source row also produces: the
  /// `document_versions` row for a document, the synthesized `document_types`
  /// row for a checklist entry.
  final String? targetChildId;
  final String sourceChecksum;
  final String targetChecksum;
  final DocumentContentLinkState contentLink;
  final String? storageObjectPath;

  Map<String, Object?> toCanonicalMap() => <String, Object?>{
    'content_link': contentLink.name,
    'entity': entity.name,
    'source_checksum': sourceChecksum,
    'source_id': sourceId,
    'storage_object_path': storageObjectPath,
    'target_checksum': targetChecksum,
    'target_child_id': targetChildId,
    'target_id': targetId,
  };
}

class DocumentMigrationEntitySummary {
  const DocumentMigrationEntitySummary({
    required this.entity,
    required this.sourceRows,
    required this.processedRows,
    required this.mappedRows,
    required this.rejectedRows,
    required this.errorCount,
    required this.warningCount,
    required this.sourceChecksum,
    required this.candidateChecksum,
    required this.reconciliationChecksum,
    required this.checksumsReconcile,
  });

  final DocumentMigrationEntity entity;
  final int sourceRows;
  final int processedRows;
  final int mappedRows;
  final int rejectedRows;
  final int errorCount;
  final int warningCount;
  final String? sourceChecksum;
  final String? candidateChecksum;
  final String? reconciliationChecksum;
  final bool checksumsReconcile;

  bool get countsReconcile =>
      processedRows == sourceRows && sourceRows == mappedRows + rejectedRows;

  Map<String, Object?> toCanonicalMap() => <String, Object?>{
    'candidate_checksum': candidateChecksum,
    'checksums_reconcile': checksumsReconcile,
    'counts_reconcile': countsReconcile,
    'entity': entity.name,
    'error_count': errorCount,
    'mapped_rows': mappedRows,
    'processed_rows': processedRows,
    'reconciliation_checksum': reconciliationChecksum,
    'rejected_rows': rejectedRows,
    'source_checksum': sourceChecksum,
    'source_rows': sourceRows,
    'warning_count': warningCount,
  };
}

class DocumentMigrationDryRunReport {
  const DocumentMigrationDryRunReport({
    required this.status,
    required this.request,
    required this.summaries,
    required this.mappings,
    required this.issues,
    required this.manifestChecksum,
  });

  final DocumentMigrationStatus status;
  final DocumentMigrationDryRunRequest request;
  final List<DocumentMigrationEntitySummary> summaries;
  final List<DocumentMigrationMapping> mappings;
  final List<DocumentMigrationIssue> issues;
  final String manifestChecksum;

  bool get productionImportReady =>
      status == DocumentMigrationStatus.ready &&
      summaries.every(
        (summary) => summary.countsReconcile && summary.checksumsReconcile,
      ) &&
      issues.every(
        (issue) => issue.severity != DocumentMigrationIssueSeverity.error,
      );

  Iterable<DocumentMigrationMapping> get documentMappings => mappings.where(
    (mapping) => mapping.entity == DocumentMigrationEntity.document,
  );

  /// The MIG-BND-003 gate: a legacy `file_path` may only be replaced by the
  /// cloud object reference once every document's bytes are proven to be in the
  /// bucket *and* the whole report reconciles. Anything less withholds it.
  bool get contentLinkAuthorized =>
      productionImportReady &&
      documentMappings.every(
        (mapping) => mapping.contentLink.authorizesContentLink,
      );

  /// The actionable output of a pre-upload pass: the object paths that still
  /// have to be uploaded before the report can authorize anything.
  List<String> get pendingUploadPaths =>
      documentMappings
          .where(
            (mapping) =>
                mapping.contentLink == DocumentContentLinkState.uploadMissing,
          )
          .map((mapping) => mapping.storageObjectPath)
          .whereType<String>()
          .toList(growable: false)
        ..sort();

  Map<String, Object?> toCanonicalMap({bool includeManifestChecksum = true}) {
    return <String, Object?>{
      'content_link_authorized': contentLinkAuthorized,
      'contract_version': documentMigrationContractVersion,
      'issues': issues.map((issue) => issue.toCanonicalMap()).toList(),
      if (includeManifestChecksum) 'manifest_checksum': manifestChecksum,
      'mappings': mappings.map((mapping) => mapping.toCanonicalMap()).toList(),
      'pending_upload_paths': pendingUploadPaths,
      'production_import_ready': productionImportReady,
      'request': request.toCanonicalMap(),
      'status': status.name,
      'summaries': summaries.map((summary) => summary.toCanonicalMap()).toList(),
    };
  }

  String toCanonicalJson() => canonicalDocumentMigrationJson(toCanonicalMap());

  DocumentMigrationDryRunReport withManifestChecksum(String checksum) {
    return DocumentMigrationDryRunReport(
      status: status,
      request: request,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: checksum,
    );
  }
}

String documentMigrationChecksum(Object? value) {
  final canonical = canonicalDocumentMigrationJson(value);
  return sha256
      .convert(utf8.encode('$_documentMigrationHashDomain$canonical'))
      .toString();
}

String canonicalDocumentMigrationJson(Object? value) {
  return jsonEncode(_canonicalizeDocumentMigrationValue(value));
}

Object? _canonicalizeDocumentMigrationValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys)
        key: _canonicalizeDocumentMigrationValue(value[key]),
    };
  }
  if (value is Iterable) {
    return value
        .map(_canonicalizeDocumentMigrationValue)
        .toList(growable: false);
  }
  if (value is double) {
    if (!value.isFinite) {
      throw const FormatException(
        'Non-finite numbers are not canonical migration values.',
      );
    }
    return value == 0 ? '0' : value.toString();
  }
  return value;
}
