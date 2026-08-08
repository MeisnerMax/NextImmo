/// P2-X01-AP4: the deterministic cutover contract for the remaining legacy
/// domains (parties, units, leases, valuation cases).
///
/// This mirrors the proven property cutover in `portfolio_property`: read-only
/// source, deterministic UUIDv5 target identifiers, canonical checksums, and a
/// strict split between a shareable report and the local target rows. It is a
/// separate module rather than an extension of the P1-012 reference migration
/// because that contract is versioned and its hash domain is part of an already
/// accepted gate; widening it would invalidate the evidence of a passing gate.
///
/// Reusing [referenceMigrationChecksum] keeps one canonicalisation rule for the
/// whole codebase — only the hash domain differs, so a property manifest and a
/// domain manifest can never collide.
library;

import '../../portfolio_property/application/reference_migration_dry_run.dart';

const legacyCutoverContractVersion = 1;

/// The domains this contract covers. `partyRole` is derived from the party
/// source rather than read from its own table, but it is a separate target
/// aggregate and therefore reconciles separately.
enum LegacyCutoverEntity { party, partyRole, unit, lease, valuationCase }

enum LegacyCutoverStatus { ready, invalid }

enum LegacyCutoverIssueSeverity { warning, error }

class LegacyCutoverIssue {
  const LegacyCutoverIssue({
    required this.code,
    required this.severity,
    required this.entity,
    this.sourceId,
    this.field,
  });

  final String code;
  final LegacyCutoverIssueSeverity severity;
  final LegacyCutoverEntity entity;
  final String? sourceId;
  final String? field;

  bool get isError => severity == LegacyCutoverIssueSeverity.error;

  Map<String, Object?> toCanonicalMap() => <String, Object?>{
    'code': code,
    'entity': entity.name,
    'field': field,
    'severity': severity.name,
    'source_id': sourceId,
  };
}

class LegacyCutoverMapping {
  const LegacyCutoverMapping({
    required this.entity,
    required this.sourceId,
    required this.targetId,
    required this.sourceChecksum,
    required this.targetChecksum,
  });

  final LegacyCutoverEntity entity;
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

class LegacyCutoverEntitySummary {
  const LegacyCutoverEntitySummary({
    required this.entity,
    required this.sourceRows,
    required this.mappedRows,
    required this.rejectedRows,
    required this.errorCount,
    required this.warningCount,
    required this.sourceChecksum,
    required this.targetChecksum,
  });

  final LegacyCutoverEntity entity;
  final int sourceRows;
  final int mappedRows;
  final int rejectedRows;
  final int errorCount;
  final int warningCount;
  final String? sourceChecksum;
  final String? targetChecksum;

  bool get countsReconcile => sourceRows == mappedRows + rejectedRows;

  Map<String, Object?> toCanonicalMap() => <String, Object?>{
    'counts_reconcile': countsReconcile,
    'entity': entity.name,
    'error_count': errorCount,
    'mapped_rows': mappedRows,
    'rejected_rows': rejectedRows,
    'source_checksum': sourceChecksum,
    'source_rows': sourceRows,
    'target_checksum': targetChecksum,
    'warning_count': warningCount,
  };
}

/// The shareable evidence artifact: counts, checksums, identifiers and issue
/// codes only. It must never carry a source value.
class LegacyCutoverReport {
  const LegacyCutoverReport({
    required this.status,
    required this.summaries,
    required this.mappings,
    required this.issues,
    required this.manifestChecksum,
  });

  final LegacyCutoverStatus status;
  final List<LegacyCutoverEntitySummary> summaries;
  final List<LegacyCutoverMapping> mappings;
  final List<LegacyCutoverIssue> issues;
  final String manifestChecksum;

  bool get importReady =>
      status == LegacyCutoverStatus.ready &&
      summaries.every((summary) => summary.countsReconcile) &&
      issues.every((issue) => !issue.isError);

  Map<String, Object?> toCanonicalMap({bool includeManifestChecksum = true}) {
    return <String, Object?>{
      'contract_version': legacyCutoverContractVersion,
      'import_ready': importReady,
      'issues': issues.map((issue) => issue.toCanonicalMap()).toList(),
      if (includeManifestChecksum) 'manifest_checksum': manifestChecksum,
      'mappings': mappings.map((mapping) => mapping.toCanonicalMap()).toList(),
      'status': status.name,
      'summaries':
          summaries.map((summary) => summary.toCanonicalMap()).toList(),
    };
  }

  String toCanonicalJson() => canonicalReferenceMigrationJson(toCanonicalMap());

  LegacyCutoverReport withManifestChecksum(String checksum) {
    return LegacyCutoverReport(
      status: status,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: checksum,
    );
  }
}

/// The report plus the target rows per entity. The rows contain real data and
/// therefore stay local, exactly like the property cutover plan.
class LegacyCutoverPlan {
  const LegacyCutoverPlan({required this.report, required this.targets});

  final LegacyCutoverReport report;
  final Map<LegacyCutoverEntity, List<Map<String, Object?>>> targets;
}

class LegacyCutoverRequest {
  const LegacyCutoverRequest({
    required this.targetWorkspaceId,
    required this.actorId,
  });

  final String targetWorkspaceId;
  final String actorId;
}

/// The read-only source snapshot. Every list is the verbatim row set of the
/// legacy table, ordered by id.
class LegacyCutoverSnapshot {
  const LegacyCutoverSnapshot({
    required this.tenants,
    required this.units,
    required this.leases,
    required this.scenarios,
  });

  final List<Map<String, Object?>> tenants;
  final List<Map<String, Object?>> units;
  final List<Map<String, Object?>> leases;
  final List<Map<String, Object?>> scenarios;
}

abstract interface class LegacyCutoverSource {
  Future<LegacyCutoverSnapshot> read();
}
