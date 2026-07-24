// Deterministic, read-only dry-run contract for migrating the legacy tasks /
// notifications / import_jobs stores into the canonical P2-D04 schema
// (P2-D04 increment 4 step 7).
//
// Mirrors the P1-012 property, P2-D02 party and P2-D03 document mappers:
// UUIDv5 target ids, canonical JSON + SHA-256 reconciliation checksums,
// per-entity count/checksum reconciliation and a signed manifest. No legacy
// table is dropped until this report reconciles, and the mapper never mutates
// the source.
//
// The derived `search_index` is deliberately absent from this contract. DOM-010
// classifies it as a projection rather than truth, so it is rebuilt by
// reindexing the owning domains after they migrate — migrating stale index rows
// would carry a snapshot of a projection whose sources have moved.
import 'dart:convert';

import 'package:crypto/crypto.dart';

const platformMigrationContractVersion = 1;
const _platformMigrationHashDomain = 'neximmo:p2-d04:v1\n';

class PlatformMigrationDryRunRequest {
  const PlatformMigrationDryRunRequest({
    required this.sourceWorkspaceId,
    required this.targetWorkspaceId,
    required this.targetWorkspaceKey,
    required this.migrationActorId,
    required this.notificationRecipientUserId,
  });

  final String sourceWorkspaceId;
  final String targetWorkspaceId;
  final String targetWorkspaceKey;
  final String migrationActorId;

  /// The legacy `notifications` table has no recipient column — the local app
  /// is single-user — while the canonical table addresses every notification to
  /// a recipient. There is no fact in the source that answers "who was this
  /// for", so the answer is supplied explicitly by whoever runs the migration
  /// and recorded as a synthesized value on every mapped row, rather than being
  /// silently invented by the mapper.
  final String notificationRecipientUserId;

  Map<String, Object?> toCanonicalMap() => <String, Object?>{
    'migration_actor_id': migrationActorId,
    'notification_recipient_user_id': notificationRecipientUserId,
    'source_workspace_id': sourceWorkspaceId,
    'target_workspace_id': targetWorkspaceId,
    'target_workspace_key': targetWorkspaceKey,
  };
}

class PlatformMigrationSourceSnapshot {
  const PlatformMigrationSourceSnapshot({
    required this.tasks,
    required this.notifications,
    required this.importJobs,
    required this.importMappings,
  });

  final List<Map<String, Object?>> tasks;
  final List<Map<String, Object?>> notifications;
  final List<Map<String, Object?>> importJobs;

  /// Legacy `import_mappings` rows are not an entity of their own: one job
  /// targets one scope, so they collapse into that job's `mapping` object.
  /// They are carried in the snapshot so the mapper can fold and reconcile
  /// them, and so an orphaned mapping row is visible rather than lost.
  final List<Map<String, Object?>> importMappings;
}

abstract interface class PlatformMigrationSource {
  Future<PlatformMigrationSourceSnapshot> read();
}

abstract interface class PlatformMigrationAbortSignal {
  bool get isAborted;
}

class NeverAbortPlatformMigration implements PlatformMigrationAbortSignal {
  const NeverAbortPlatformMigration();

  @override
  bool get isAborted => false;
}

enum PlatformMigrationStatus { ready, invalid, aborted }

enum PlatformMigrationEntity { task, notification, importJob }

enum PlatformMigrationIssueSeverity { warning, error }

class PlatformMigrationIssue {
  const PlatformMigrationIssue({
    required this.code,
    required this.severity,
    this.entity,
    this.sourceId,
    this.field,
  });

  final String code;
  final PlatformMigrationIssueSeverity severity;
  final PlatformMigrationEntity? entity;
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

class PlatformMigrationMapping {
  const PlatformMigrationMapping({
    required this.entity,
    required this.sourceId,
    required this.targetId,
    required this.sourceChecksum,
    required this.targetChecksum,
  });

  final PlatformMigrationEntity entity;
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

class PlatformMigrationEntitySummary {
  const PlatformMigrationEntitySummary({
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

  final PlatformMigrationEntity entity;
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

class PlatformMigrationDryRunReport {
  const PlatformMigrationDryRunReport({
    required this.status,
    required this.request,
    required this.summaries,
    required this.mappings,
    required this.issues,
    required this.manifestChecksum,
  });

  final PlatformMigrationStatus status;
  final PlatformMigrationDryRunRequest request;
  final List<PlatformMigrationEntitySummary> summaries;
  final List<PlatformMigrationMapping> mappings;
  final List<PlatformMigrationIssue> issues;
  final String manifestChecksum;

  bool get productionImportReady =>
      status == PlatformMigrationStatus.ready &&
      summaries.every(
        (summary) => summary.countsReconcile && summary.checksumsReconcile,
      ) &&
      issues.every(
        (issue) => issue.severity != PlatformMigrationIssueSeverity.error,
      );

  Map<String, Object?> toCanonicalMap({bool includeManifestChecksum = true}) {
    return <String, Object?>{
      'contract_version': platformMigrationContractVersion,
      'issues': issues.map((issue) => issue.toCanonicalMap()).toList(),
      if (includeManifestChecksum) 'manifest_checksum': manifestChecksum,
      'mappings': mappings.map((mapping) => mapping.toCanonicalMap()).toList(),
      'production_import_ready': productionImportReady,
      'request': request.toCanonicalMap(),
      'status': status.name,
      'summaries': summaries.map((summary) => summary.toCanonicalMap()).toList(),
    };
  }

  String toCanonicalJson() => canonicalPlatformMigrationJson(toCanonicalMap());

  PlatformMigrationDryRunReport withManifestChecksum(String checksum) {
    return PlatformMigrationDryRunReport(
      status: status,
      request: request,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: checksum,
    );
  }
}

String platformMigrationChecksum(Object? value) {
  final canonical = canonicalPlatformMigrationJson(value);
  return sha256
      .convert(utf8.encode('$_platformMigrationHashDomain$canonical'))
      .toString();
}

String canonicalPlatformMigrationJson(Object? value) {
  return jsonEncode(_canonicalizePlatformMigrationValue(value));
}

Object? _canonicalizePlatformMigrationValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys)
        key: _canonicalizePlatformMigrationValue(value[key]),
    };
  }
  if (value is Iterable) {
    return value
        .map(_canonicalizePlatformMigrationValue)
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
