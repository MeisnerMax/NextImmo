import 'dart:convert';

import 'package:crypto/crypto.dart';

const referenceMigrationContractVersion = 1;
const _referenceMigrationHashDomain = 'neximmo:p1-012:v1\n';

class ReferenceMigrationDryRunRequest {
  const ReferenceMigrationDryRunRequest({
    required this.sourceWorkspaceId,
    required this.targetWorkspaceId,
    required this.targetWorkspaceKey,
    required this.migrationActorId,
    required this.confirmGlobalPropertyWorkspaceBinding,
    required this.inferArchivedAtFromUpdatedAt,
  });

  final String sourceWorkspaceId;
  final String targetWorkspaceId;
  final String targetWorkspaceKey;
  final String migrationActorId;
  final bool confirmGlobalPropertyWorkspaceBinding;
  final bool inferArchivedAtFromUpdatedAt;

  Map<String, Object?> toCanonicalMap() => <String, Object?>{
    'confirm_global_property_workspace_binding':
        confirmGlobalPropertyWorkspaceBinding,
    'infer_archived_at_from_updated_at': inferArchivedAtFromUpdatedAt,
    'migration_actor_id': migrationActorId,
    'source_workspace_id': sourceWorkspaceId,
    'target_workspace_id': targetWorkspaceId,
    'target_workspace_key': targetWorkspaceKey,
  };
}

class ReferenceMigrationSourceSnapshot {
  const ReferenceMigrationSourceSnapshot({
    required this.workspaces,
    required this.properties,
  });

  final List<Map<String, Object?>> workspaces;
  final List<Map<String, Object?>> properties;
}

abstract interface class ReferenceMigrationSource {
  Future<ReferenceMigrationSourceSnapshot> read();
}

abstract interface class ReferenceMigrationAbortSignal {
  bool get isAborted;
}

class NeverAbortReferenceMigration implements ReferenceMigrationAbortSignal {
  const NeverAbortReferenceMigration();

  @override
  bool get isAborted => false;
}

enum ReferenceMigrationStatus { ready, invalid, aborted }

enum ReferenceMigrationEntity { workspace, property }

enum ReferenceMigrationIssueSeverity { warning, error }

class ReferenceMigrationIssue {
  const ReferenceMigrationIssue({
    required this.code,
    required this.severity,
    this.entity,
    this.sourceId,
    this.field,
  });

  final String code;
  final ReferenceMigrationIssueSeverity severity;
  final ReferenceMigrationEntity? entity;
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

class ReferenceMigrationMapping {
  const ReferenceMigrationMapping({
    required this.entity,
    required this.sourceId,
    required this.targetId,
    required this.sourceChecksum,
    required this.targetChecksum,
  });

  final ReferenceMigrationEntity entity;
  final String sourceId;
  final String targetId;
  final String sourceChecksum;
  final String targetChecksum;

  Map<String, Object?> toCanonicalMap() => <String, Object?>{
    'entity': entity.name,
    'source_checksum': sourceChecksum,
    'source_id': sourceId,
    'target_checksum': targetChecksum,
    'target_id': targetId,
  };
}

class ReferenceMigrationEntitySummary {
  const ReferenceMigrationEntitySummary({
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

  final ReferenceMigrationEntity entity;
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

class ReferenceMigrationDryRunReport {
  const ReferenceMigrationDryRunReport({
    required this.status,
    required this.request,
    required this.summaries,
    required this.mappings,
    required this.issues,
    required this.manifestChecksum,
  });

  final ReferenceMigrationStatus status;
  final ReferenceMigrationDryRunRequest request;
  final List<ReferenceMigrationEntitySummary> summaries;
  final List<ReferenceMigrationMapping> mappings;
  final List<ReferenceMigrationIssue> issues;
  final String manifestChecksum;

  bool get productionImportReady =>
      status == ReferenceMigrationStatus.ready &&
      summaries.every(
        (summary) => summary.countsReconcile && summary.checksumsReconcile,
      ) &&
      issues.every(
        (issue) => issue.severity != ReferenceMigrationIssueSeverity.error,
      );

  Map<String, Object?> toCanonicalMap({bool includeManifestChecksum = true}) {
    return <String, Object?>{
      'contract_version': referenceMigrationContractVersion,
      'issues': issues.map((issue) => issue.toCanonicalMap()).toList(),
      if (includeManifestChecksum) 'manifest_checksum': manifestChecksum,
      'mappings': mappings.map((mapping) => mapping.toCanonicalMap()).toList(),
      'production_import_ready': productionImportReady,
      'request': request.toCanonicalMap(),
      'status': status.name,
      'summaries':
          summaries.map((summary) => summary.toCanonicalMap()).toList(),
    };
  }

  String toCanonicalJson() => canonicalReferenceMigrationJson(toCanonicalMap());

  ReferenceMigrationDryRunReport withManifestChecksum(String checksum) {
    return ReferenceMigrationDryRunReport(
      status: status,
      request: request,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: checksum,
    );
  }
}

String referenceMigrationChecksum(Object? value) {
  final canonical = canonicalReferenceMigrationJson(value);
  return sha256
      .convert(utf8.encode('$_referenceMigrationHashDomain$canonical'))
      .toString();
}

String canonicalReferenceMigrationJson(Object? value) {
  return jsonEncode(_canonicalizeReferenceMigrationValue(value));
}

Object? _canonicalizeReferenceMigrationValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys)
        key: _canonicalizeReferenceMigrationValue(value[key]),
    };
  }
  if (value is Iterable) {
    return value
        .map(_canonicalizeReferenceMigrationValue)
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
