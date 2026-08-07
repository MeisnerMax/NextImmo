// Deterministic, read-only dry-run contract for migrating the legacy
// units / leases stores into the canonical cloud leasing schema
// (P2-D05 increment 3, MIG-BND-001).
//
// Mirrors the P1-012 property mapper and the P2-D02 party mapper: UUIDv5 target
// ids, canonical JSON + SHA-256 reconciliation checksums, per-entity
// count/checksum reconciliation and a signed manifest. It never mutates the
// source; a real import is only authorized once the produced report reconciles.
//
// Two entities, deliberately, where the domain has four aggregates:
//
//   * Legacy leasing cases do not exist. The legacy pipeline was UI-only status
//     strings that were never persisted (FTR-024) — there is nothing to migrate,
//     not a gap being skipped.
//   * Legacy rent roll snapshots exist but cannot become AGG-007 snapshots. They
//     are keyed by reporting period rather than by date and carry no currency,
//     no unit-status partition and no base/ancillary/parking split. Deriving
//     those four would mean inventing figures inside a document whose entire
//     purpose is that it was frozen. The mapper reports how many it is leaving
//     behind (`mapping.rent_roll_not_migrated`) rather than silently omitting
//     them.
//
// Tenants are likewise absent here: they were already folded into `parties` by
// the P2-D02 mapper (AGG-005 — there is no cloud `tenants` table). What this
// mapper owes that fold is the *same* target id, so a migrated lease points at
// a party that actually exists. See `leasingMigrationTenantPartyId`.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

const leasingMigrationContractVersion = 1;
const _leasingMigrationHashDomain = 'neximmo:p2-d05:v1\n';

/// The target party id a legacy tenant row receives.
///
/// **This must stay byte-identical to the P2-D02 mapper's derivation for the
/// `tenant` entity** (`sqlite_to_postgres_contacts_parties_dry_run_mapper.dart`,
/// `_party`). It is mirrored rather than imported because a migrated vertical
/// must not depend on another one — the same rule P2-D04 followed for the
/// document entity-type registry. A parity test drives both mappers and fails
/// if they ever disagree, so drift breaks a build instead of silently orphaning
/// every migrated lease.
String leasingMigrationTenantPartyId({
  required String targetWorkspaceId,
  required String legacyTenantId,
}) {
  return const Uuid().v5(
    targetWorkspaceId,
    'neximmo/p2-d02/party/tenant/$legacyTenantId',
  );
}

/// The target property id a legacy property row receives.
///
/// Same contract as above against the P1-012 reference mapper
/// (`sqlite_to_postgres_reference_dry_run_mapper.dart`): a migrated unit's
/// `property_id` has to hit the property that mapper produced, or the FK fails
/// at import time.
String leasingMigrationPropertyId({
  required String targetWorkspaceId,
  required String legacyPropertyId,
}) {
  return const Uuid().v5(
    targetWorkspaceId,
    'neximmo/p1-012/property/$legacyPropertyId',
  );
}

class LeasingMigrationDryRunRequest {
  const LeasingMigrationDryRunRequest({
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

class LeasingMigrationSourceSnapshot {
  const LeasingMigrationSourceSnapshot({
    required this.units,
    required this.leases,
    this.rentRollSnapshotCount = 0,
  });

  final List<Map<String, Object?>> units;
  final List<Map<String, Object?>> leases;

  /// How many legacy rent roll snapshots exist. Carried as a count rather than
  /// as rows because they are not migrated — the count is what turns "not
  /// migrated" from an omission into a reported fact.
  final int rentRollSnapshotCount;
}

abstract interface class LeasingMigrationSource {
  Future<LeasingMigrationSourceSnapshot> read();
}

abstract interface class LeasingMigrationAbortSignal {
  bool get isAborted;
}

class NeverAbortLeasingMigration implements LeasingMigrationAbortSignal {
  const NeverAbortLeasingMigration();

  @override
  bool get isAborted => false;
}

enum LeasingMigrationStatus { ready, invalid, aborted }

enum LeasingMigrationEntity { unit, lease }

enum LeasingMigrationIssueSeverity { warning, error }

class LeasingMigrationIssue {
  const LeasingMigrationIssue({
    required this.code,
    required this.severity,
    this.entity,
    this.sourceId,
    this.field,
  });

  final String code;
  final LeasingMigrationIssueSeverity severity;
  final LeasingMigrationEntity? entity;
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

class LeasingMigrationMapping {
  const LeasingMigrationMapping({
    required this.entity,
    required this.sourceId,
    required this.targetId,
    required this.sourceChecksum,
    required this.targetChecksum,
  });

  final LeasingMigrationEntity entity;
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

class LeasingMigrationEntitySummary {
  const LeasingMigrationEntitySummary({
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

  final LeasingMigrationEntity entity;
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

class LeasingMigrationDryRunReport {
  const LeasingMigrationDryRunReport({
    required this.status,
    required this.request,
    required this.summaries,
    required this.mappings,
    required this.issues,
    required this.manifestChecksum,
  });

  final LeasingMigrationStatus status;
  final LeasingMigrationDryRunRequest request;
  final List<LeasingMigrationEntitySummary> summaries;
  final List<LeasingMigrationMapping> mappings;
  final List<LeasingMigrationIssue> issues;
  final String manifestChecksum;

  bool get productionImportReady =>
      status == LeasingMigrationStatus.ready &&
      summaries.every(
        (summary) => summary.countsReconcile && summary.checksumsReconcile,
      ) &&
      issues.every(
        (issue) => issue.severity != LeasingMigrationIssueSeverity.error,
      );

  Map<String, Object?> toCanonicalMap({bool includeManifestChecksum = true}) {
    return <String, Object?>{
      'contract_version': leasingMigrationContractVersion,
      'issues': issues.map((issue) => issue.toCanonicalMap()).toList(),
      if (includeManifestChecksum) 'manifest_checksum': manifestChecksum,
      'mappings': mappings.map((mapping) => mapping.toCanonicalMap()).toList(),
      'production_import_ready': productionImportReady,
      'request': request.toCanonicalMap(),
      'status': status.name,
      'summaries': summaries
          .map((summary) => summary.toCanonicalMap())
          .toList(),
    };
  }

  String toCanonicalJson() => canonicalLeasingMigrationJson(toCanonicalMap());

  LeasingMigrationDryRunReport withManifestChecksum(String checksum) {
    return LeasingMigrationDryRunReport(
      status: status,
      request: request,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: checksum,
    );
  }
}

String leasingMigrationChecksum(Object? value) {
  final canonical = canonicalLeasingMigrationJson(value);
  return sha256
      .convert(utf8.encode('$_leasingMigrationHashDomain$canonical'))
      .toString();
}

String canonicalLeasingMigrationJson(Object? value) {
  return jsonEncode(_canonicalizeLeasingMigrationValue(value));
}

Object? _canonicalizeLeasingMigrationValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys)
        key: _canonicalizeLeasingMigrationValue(value[key]),
    };
  }
  if (value is Iterable) {
    return value
        .map(_canonicalizeLeasingMigrationValue)
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
