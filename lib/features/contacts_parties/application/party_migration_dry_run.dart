// Deterministic, read-only dry-run contract for migrating the legacy
// tenants / contractors / contacts stores into the canonical
// parties / party_roles / satellite schema (P2-D02 step 7, MIG-BND-001).
//
// Mirrors the P1-012 property reference mapper: UUIDv5 target ids, canonical
// JSON + SHA-256 reconciliation checksums, per-entity count/checksum
// reconciliation and a signed manifest. No legacy table is dropped until this
// report reconciles.
import 'dart:convert';

import 'package:crypto/crypto.dart';

const partyMigrationContractVersion = 1;
const _partyMigrationHashDomain = 'neximmo:p2-d02:v1\n';

class PartyMigrationDryRunRequest {
  const PartyMigrationDryRunRequest({
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
    'target_workspace_id': targetWorkspaceId,
    'target_workspace_key': targetWorkspaceKey,
  };
}

class PartyMigrationSourceSnapshot {
  const PartyMigrationSourceSnapshot({
    required this.tenants,
    required this.contractors,
    required this.contacts,
  });

  final List<Map<String, Object?>> tenants;
  final List<Map<String, Object?>> contractors;
  final List<Map<String, Object?>> contacts;
}

abstract interface class PartyMigrationSource {
  Future<PartyMigrationSourceSnapshot> read();
}

abstract interface class PartyMigrationAbortSignal {
  bool get isAborted;
}

class NeverAbortPartyMigration implements PartyMigrationAbortSignal {
  const NeverAbortPartyMigration();

  @override
  bool get isAborted => false;
}

enum PartyMigrationStatus { ready, invalid, aborted }

enum PartyMigrationEntity { tenant, contractor, contact }

enum PartyMigrationIssueSeverity { warning, error }

class PartyMigrationIssue {
  const PartyMigrationIssue({
    required this.code,
    required this.severity,
    this.entity,
    this.sourceId,
    this.field,
  });

  final String code;
  final PartyMigrationIssueSeverity severity;
  final PartyMigrationEntity? entity;
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

class PartyMigrationMapping {
  const PartyMigrationMapping({
    required this.entity,
    required this.sourceId,
    required this.targetPartyId,
    required this.sourceChecksum,
    required this.targetChecksum,
    this.targetRoleId,
  });

  final PartyMigrationEntity entity;
  final String sourceId;
  final String targetPartyId;
  final String? targetRoleId;
  final String sourceChecksum;
  final String targetChecksum;

  Map<String, Object?> toCanonicalMap() => <String, Object?>{
    'entity': entity.name,
    'source_checksum': sourceChecksum,
    'source_id': sourceId,
    'target_checksum': targetChecksum,
    'target_party_id': targetPartyId,
    'target_role_id': targetRoleId,
  };
}

class PartyMigrationEntitySummary {
  const PartyMigrationEntitySummary({
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

  final PartyMigrationEntity entity;
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

class PartyMigrationDryRunReport {
  const PartyMigrationDryRunReport({
    required this.status,
    required this.request,
    required this.summaries,
    required this.mappings,
    required this.issues,
    required this.manifestChecksum,
  });

  final PartyMigrationStatus status;
  final PartyMigrationDryRunRequest request;
  final List<PartyMigrationEntitySummary> summaries;
  final List<PartyMigrationMapping> mappings;
  final List<PartyMigrationIssue> issues;
  final String manifestChecksum;

  bool get productionImportReady =>
      status == PartyMigrationStatus.ready &&
      summaries.every(
        (summary) => summary.countsReconcile && summary.checksumsReconcile,
      ) &&
      issues.every(
        (issue) => issue.severity != PartyMigrationIssueSeverity.error,
      );

  Map<String, Object?> toCanonicalMap({bool includeManifestChecksum = true}) {
    return <String, Object?>{
      'contract_version': partyMigrationContractVersion,
      'issues': issues.map((issue) => issue.toCanonicalMap()).toList(),
      if (includeManifestChecksum) 'manifest_checksum': manifestChecksum,
      'mappings': mappings.map((mapping) => mapping.toCanonicalMap()).toList(),
      'production_import_ready': productionImportReady,
      'request': request.toCanonicalMap(),
      'status': status.name,
      'summaries': summaries.map((summary) => summary.toCanonicalMap()).toList(),
    };
  }

  String toCanonicalJson() => canonicalPartyMigrationJson(toCanonicalMap());

  PartyMigrationDryRunReport withManifestChecksum(String checksum) {
    return PartyMigrationDryRunReport(
      status: status,
      request: request,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: checksum,
    );
  }
}

String partyMigrationChecksum(Object? value) {
  final canonical = canonicalPartyMigrationJson(value);
  return sha256
      .convert(utf8.encode('$_partyMigrationHashDomain$canonical'))
      .toString();
}

String canonicalPartyMigrationJson(Object? value) {
  return jsonEncode(_canonicalizePartyMigrationValue(value));
}

Object? _canonicalizePartyMigrationValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalizePartyMigrationValue(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalizePartyMigrationValue).toList(growable: false);
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
