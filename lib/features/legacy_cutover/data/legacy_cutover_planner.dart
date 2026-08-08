/// Composes the per-domain mappers into one deterministic P2-X01-AP4 plan.
///
/// Stages run in dependency order so a dependent domain can resolve foreign
/// keys from the identifiers the previous stage derived. The plan is only
/// import ready when every stage reconciles and no stage produced an error.
library;

import '../../portfolio_property/application/reference_migration_dry_run.dart';
import '../application/legacy_cutover.dart';
import 'legacy_cutover_fields.dart';
import 'legacy_lease_cutover_mapper.dart';
import 'legacy_party_cutover_mapper.dart';
import 'legacy_unit_cutover_mapper.dart';
import 'legacy_valuation_case_cutover_mapper.dart';

class LegacyCutoverPlanner {
  const LegacyCutoverPlanner();

  LegacyCutoverPlan plan({
    required LegacyCutoverSnapshot snapshot,
    required LegacyCutoverRequest request,
  }) {
    final results = <LegacyCutoverEntityResult>[
      const LegacyPartyCutoverMapper().map(
        tenants: snapshot.tenants,
        request: request,
      ),
      // Units and leases are one aggregate, not two stages:
      // `units_occupancy_invariant` (AGG-004) is a DEFERRABLE INITIALLY
      // DEFERRED constraint trigger, so an occupied unit must have an effective
      // lease by COMMIT. They are mapped together and applied in one
      // transaction.
      const LegacyUnitCutoverMapper().map(
        units: snapshot.units,
        request: request,
      ),
      const LegacyLeaseCutoverMapper().map(
        leases: snapshot.leases,
        request: request,
      ),
      const LegacyValuationCaseCutoverMapper().map(
        scenarios: snapshot.scenarios,
        request: request,
      ),
    ];

    final targets = <LegacyCutoverEntity, List<Map<String, Object?>>>{};
    final summaries = <LegacyCutoverEntitySummary>[];
    final mappings = <LegacyCutoverMapping>[];
    final issues = <LegacyCutoverIssue>[];
    for (final result in results) {
      targets.addAll(result.targets);
      summaries.addAll(result.summaries);
      mappings.addAll(result.mappings);
      issues.addAll(result.issues);
    }

    mappings.sort(_compareMappings);
    issues.sort(_compareIssues);
    summaries.sort((left, right) => left.entity.name.compareTo(right.entity.name));

    final status =
        issues.any((issue) => issue.isError) ||
                summaries.any((summary) => !summary.countsReconcile)
            ? LegacyCutoverStatus.invalid
            : LegacyCutoverStatus.ready;
    final unsigned = LegacyCutoverReport(
      status: status,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: '',
    );
    return LegacyCutoverPlan(
      report: unsigned.withManifestChecksum(
        referenceMigrationChecksum(
          unsigned.toCanonicalMap(includeManifestChecksum: false),
        ),
      ),
      targets: targets,
    );
  }
}

int _compareMappings(LegacyCutoverMapping left, LegacyCutoverMapping right) {
  final entity = left.entity.name.compareTo(right.entity.name);
  return entity != 0 ? entity : left.sourceId.compareTo(right.sourceId);
}

int _compareIssues(LegacyCutoverIssue left, LegacyCutoverIssue right) {
  String key(LegacyCutoverIssue issue) => <String>[
    issue.entity.name,
    issue.sourceId ?? '',
    issue.field ?? '',
    issue.code,
    issue.severity.name,
  ].join('\u0000');
  return key(left).compareTo(key(right));
}
