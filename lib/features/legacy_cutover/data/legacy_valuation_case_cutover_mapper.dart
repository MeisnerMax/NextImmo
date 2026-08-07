/// P2-X01-AP4 stage 4: legacy `scenarios` to `public.valuation_cases`.
///
/// A legacy scenario is the ancestor of a valuation case: it names a strategy
/// and carries an approval workflow. The target adds the method configuration,
/// which has server-side defaults, so the cutover deliberately writes none of
/// it — a migrated case starts with the contract's own defaults rather than
/// with values invented here.
library;

import 'package:uuid/uuid.dart';

import '../application/legacy_cutover.dart';
import 'legacy_cutover_fields.dart';

const _valuationCaseNamespace = 'neximmo/p2-x01/valuation-case';
const _scenarioNamespace = 'neximmo/p2-x01/scenario';
const _propertyNamespace = 'neximmo/p1-012/property';

/// Legacy strategy to `valuation_case_kind`. An unlisted strategy fails closed:
/// guessing the kind would silently change how the case is valued.
const Map<String, String> _kindByStrategy = <String, String>{
  'hold': 'holding',
  'holding': 'holding',
  'bestand': 'holding',
  'acquisition': 'acquisition',
  'buy': 'acquisition',
  'ankauf': 'acquisition',
  'renovation': 'renovation',
  'sanierung': 'renovation',
  'disposition': 'disposition',
  'sell': 'disposition',
  'verkauf': 'disposition',
};

/// Legacy workflow state to `valuation_case_status`. `rejected` has no target
/// state — the valuation contract models rejection by returning the case to
/// `draft` through an explicit action, not as a stored status — so a rejected
/// scenario fails closed instead of being silently relabelled.
const Map<String, String> _statusByWorkflow = <String, String>{
  'draft': 'draft',
  'in_review': 'in_review',
  'review': 'in_review',
  'approved': 'approved',
  'archived': 'archived',
};

/// Present in the source, no target column, and all of them were empty in the
/// production data set that motivated this cutover.
const Set<String> _excludedScenarioFields = <String>{
  'changed_since_approval',
  'is_base',
  'rejected_at',
  'rejected_by',
  'review_comment',
};

const Set<String> _knownScenarioFields = <String>{
  'approved_at',
  'approved_by',
  'created_at',
  'id',
  'name',
  'property_id',
  'scenario_case_type',
  'strategy_type',
  'updated_at',
  'workflow_status',
  ..._excludedScenarioFields,
};

class LegacyValuationCaseCutoverMapper {
  const LegacyValuationCaseCutoverMapper();

  LegacyCutoverEntityResult map({
    required List<Map<String, Object?>> scenarios,
    required LegacyCutoverRequest request,
  }) {
    final targets = <Map<String, Object?>>[];
    final mappings = <LegacyCutoverMapping>[];
    final issues = <LegacyCutoverIssue>[];
    var rejected = 0;
    const entity = LegacyCutoverEntity.valuationCase;

    for (final row in sortedLegacyRows(scenarios)) {
      final rowIssues = <LegacyCutoverIssue>[];
      final sourceId = requiredSourceId(row, entity, rowIssues);
      reportUnknownFields(
        row,
        known: _knownScenarioFields,
        entity: entity,
        sourceId: sourceId,
        issues: rowIssues,
      );
      reportExcludedFields(
        row,
        excluded: _excludedScenarioFields,
        entity: entity,
        sourceId: sourceId,
        issues: rowIssues,
      );

      final propertySourceId = requiredText(
        row,
        key: 'property_id',
        maxLength: 200,
        entity: entity,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final title = requiredText(
        row,
        key: 'name',
        maxLength: 300,
        entity: entity,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final kind = _kind(row, sourceId, rowIssues);
      final status = _status(row, sourceId, rowIssues);
      final createdAt = requiredTimestamp(
        row,
        key: 'created_at',
        entity: entity,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final updatedAt = requiredTimestamp(
        row,
        key: 'updated_at',
        entity: entity,
        sourceId: sourceId,
        issues: rowIssues,
      );

      // `valuation_cases_approved_check` couples status, approved_at and
      // approved_by. The legacy approver is a local user key, not an
      // `auth.uid()`, so it cannot travel; the migration actor stands in and
      // the substitution is reported per row.
      String? approvedAt;
      String? approvedBy;
      if (status == 'approved') {
        approvedAt =
            row['approved_at'] == null
                ? updatedAt
                : requiredTimestamp(
                  row,
                  key: 'approved_at',
                  entity: entity,
                  sourceId: sourceId,
                  issues: rowIssues,
                );
        approvedBy = request.actorId;
        rowIssues.add(
          fieldWarning('mapping.approver_replaced', entity, sourceId, 'approved_by'),
        );
      } else if (row['approved_by'] != null || row['approved_at'] != null) {
        // Approval metadata on a case that is not approved would contradict the
        // target invariant, so it is dropped visibly.
        rowIssues.add(
          fieldWarning('mapping.stale_approval_dropped', entity, sourceId, 'approved_at'),
        );
      }

      final archivedAt = status == 'archived' ? updatedAt : null;
      if (status == 'archived') {
        rowIssues.add(
          fieldWarning('mapping.archived_at_inferred', entity, sourceId, 'archived_at'),
        );
      }

      issues.addAll(rowIssues);
      if (rowIssues.any((issue) => issue.isError) ||
          sourceId == null ||
          propertySourceId == null ||
          title == null ||
          kind == null ||
          status == null ||
          createdAt == null ||
          updatedAt == null) {
        rejected++;
        continue;
      }

      final uuid = const Uuid();
      final caseId = uuid.v5(
        request.targetWorkspaceId,
        '$_valuationCaseNamespace/$sourceId',
      );
      final target = <String, Object?>{
        'approved_at': approvedAt,
        'approved_by': approvedBy,
        'archived_at': archivedAt,
        'created_at': createdAt,
        'created_by': request.actorId,
        'id': caseId,
        'kind': kind,
        'property_id': uuid.v5(
          request.targetWorkspaceId,
          '$_propertyNamespace/$propertySourceId',
        ),
        // Not a foreign key: it preserves the origin scenario identity so a
        // migrated case stays traceable to the row it came from.
        'scenario_id': uuid.v5(
          request.targetWorkspaceId,
          '$_scenarioNamespace/$sourceId',
        ),
        'status': status,
        'title': title,
        'updated_at': updatedAt,
        'updated_by': request.actorId,
        'version': 1,
        'workspace_id': request.targetWorkspaceId,
      };
      targets.add(target);
      mappings.add(
        LegacyCutoverMapping(
          entity: entity,
          sourceId: sourceId,
          targetId: caseId,
          sourceChecksum: legacyRowChecksum(row),
          targetChecksum: legacyRowChecksum(target),
        ),
      );
    }

    return LegacyCutoverEntityResult(
      targets: <LegacyCutoverEntity, List<Map<String, Object?>>>{
        entity: targets,
      },
      summaries: <LegacyCutoverEntitySummary>[
        buildSummary(
          entity: entity,
          sourceRows: scenarios.length,
          targets: targets,
          sourceRowsData: sortedLegacyRows(scenarios),
          rejectedRows: rejected,
          issues: issues,
        ),
      ],
      mappings: mappings,
      issues: issues,
    );
  }

  String? _kind(
    Map<String, Object?> row,
    String? sourceId,
    List<LegacyCutoverIssue> issues,
  ) {
    // The case type is the more specific field where present; the strategy is
    // the fallback. `base` is not a case kind at all — it is the legacy default
    // marking the baseline scenario — so it falls through to the strategy
    // rather than being rejected as unmappable.
    for (final key in <String>['scenario_case_type', 'strategy_type']) {
      final raw = row[key];
      if (raw is String &&
          raw.trim().isNotEmpty &&
          raw.trim().toLowerCase() != 'base') {
        final mapped = _kindByStrategy[raw.trim().toLowerCase()];
        if (mapped != null) {
          return mapped;
        }
        issues.add(
          fieldError(
            'source.unmappable_strategy',
            LegacyCutoverEntity.valuationCase,
            sourceId,
            key,
          ),
        );
        return null;
      }
    }
    issues.add(
      fieldError(
        'source.required_value_missing',
        LegacyCutoverEntity.valuationCase,
        sourceId,
        'strategy_type',
      ),
    );
    return null;
  }

  String? _status(
    Map<String, Object?> row,
    String? sourceId,
    List<LegacyCutoverIssue> issues,
  ) {
    final raw = row['workflow_status'];
    if (raw is! String || raw.trim().isEmpty) {
      issues.add(
        fieldError(
          'source.required_value_missing',
          LegacyCutoverEntity.valuationCase,
          sourceId,
          'workflow_status',
        ),
      );
      return null;
    }
    final mapped = _statusByWorkflow[raw.trim().toLowerCase()];
    if (mapped == null) {
      issues.add(
        fieldError(
          'source.unmappable_workflow_status',
          LegacyCutoverEntity.valuationCase,
          sourceId,
          'workflow_status',
        ),
      );
      return null;
    }
    return mapped;
  }
}
