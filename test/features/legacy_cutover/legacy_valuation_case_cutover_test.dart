import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/legacy_cutover/application/legacy_cutover.dart';
import 'package:neximmo_app/features/legacy_cutover/data/legacy_cutover_planner.dart';

void main() {
  const planner = LegacyCutoverPlanner();
  const request = LegacyCutoverRequest(
    targetWorkspaceId: 'a1000000-0000-4000-8000-000000000001',
    actorId: 'a7000000-0000-4000-8000-000000000001',
  );

  LegacyCutoverSnapshot snapshotOf(List<Map<String, Object?>> scenarios) {
    return LegacyCutoverSnapshot(
      tenants: const <Map<String, Object?>>[],
      units: const <Map<String, Object?>>[],
      leases: const <Map<String, Object?>>[],
      scenarios: scenarios,
    );
  }

  Map<String, Object?> caseOf(LegacyCutoverPlan plan) =>
      plan.targets[LegacyCutoverEntity.valuationCase]!.single;

  test('maps a scenario to a valuation case', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[_scenario(id: 'sc-1')]),
      request: request,
    );

    expect(
      plan.report.status,
      LegacyCutoverStatus.ready,
      reason:
          plan.report.issues
              .where((issue) => issue.isError)
              .map((issue) => issue.toCanonicalMap())
              .toList()
              .toString(),
    );
    final target = caseOf(plan);
    expect(target['title'], 'Bestandsszenario');
    expect(target['kind'], 'holding');
    expect(target['status'], 'draft');
    expect(target['approved_at'], isNull);
    expect(target['approved_by'], isNull);
    expect(target['archived_at'], isNull);
    // scenario_id keeps the origin traceable; it is not a foreign key.
    expect(target['scenario_id'], matches(_uuidPattern));
    expect(target['property_id'], matches(_uuidPattern));
  });

  test('treats the legacy base marker as "no case kind"', () {
    // `base` is the legacy default of scenario_case_type and marks the baseline
    // scenario, not a valuation kind — so the strategy decides.
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _scenario(id: 'sc-1')
          ..['scenario_case_type'] = 'base'
          ..['strategy_type'] = 'disposition',
      ]),
      request: request,
    );

    expect(plan.report.status, LegacyCutoverStatus.ready);
    expect(caseOf(plan)['kind'], 'disposition');
  });

  test('an unmappable strategy fails closed', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _scenario(id: 'sc-1')..['strategy_type'] = 'speculation',
      ]),
      request: request,
    );

    expect(plan.report.status, LegacyCutoverStatus.invalid);
    expect(
      plan.report.issues.map((issue) => issue.code),
      contains('source.unmappable_strategy'),
    );
  });

  test('a rejected workflow state fails closed instead of being relabelled', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _scenario(id: 'sc-1')..['workflow_status'] = 'rejected',
      ]),
      request: request,
    );

    expect(plan.report.status, LegacyCutoverStatus.invalid);
    expect(
      plan.report.issues.map((issue) => issue.code),
      contains('source.unmappable_workflow_status'),
    );
  });

  test('an approved case satisfies the approval invariant and reports the substitution', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _scenario(id: 'sc-1')
          ..['workflow_status'] = 'approved'
          ..['approved_at'] = 4000
          ..['approved_by'] = 'user_owner',
      ]),
      request: request,
    );

    expect(plan.report.status, LegacyCutoverStatus.ready);
    final target = caseOf(plan);
    // valuation_cases_approved_check couples all three.
    expect(target['status'], 'approved');
    expect(target['approved_at'], isNotNull);
    // The legacy approver is a local user key, not an auth.uid().
    expect(target['approved_by'], request.actorId);
    expect(
      plan.report.issues.map((issue) => issue.code),
      contains('mapping.approver_replaced'),
    );
  });

  test('approval metadata on a non-approved case is dropped visibly', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _scenario(id: 'sc-1')..['approved_by'] = 'user_owner',
      ]),
      request: request,
    );

    expect(plan.report.status, LegacyCutoverStatus.ready);
    expect(caseOf(plan)['approved_by'], isNull);
    expect(
      plan.report.issues.map((issue) => issue.code),
      contains('mapping.stale_approval_dropped'),
    );
  });

  test('an archived case carries the timestamp its invariant requires', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _scenario(id: 'sc-1')..['workflow_status'] = 'archived',
      ]),
      request: request,
    );

    expect(caseOf(plan)['archived_at'], isNotNull);
    expect(
      plan.report.issues.map((issue) => issue.code),
      contains('mapping.archived_at_inferred'),
    );
  });

  test('never exposes a source value in the shareable report', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _scenario(id: 'sc-1')..['name'] = 'Vertrauliches Szenario',
      ]),
      request: request,
    );
    expect(
      plan.report.toCanonicalJson(),
      isNot(contains('Vertrauliches Szenario')),
    );
  });
}

Map<String, Object?> _scenario({required String id}) {
  return <String, Object?>{
    'id': id,
    'property_id': 'FX-0001',
    'name': 'Bestandsszenario',
    'strategy_type': 'hold',
    'scenario_case_type': 'base',
    'workflow_status': 'draft',
    'is_base': 0,
    'approved_by': null,
    'approved_at': null,
    'rejected_by': null,
    'rejected_at': null,
    'review_comment': null,
    'changed_since_approval': null,
    'created_at': 2000,
    'updated_at': 3000,
  };
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
