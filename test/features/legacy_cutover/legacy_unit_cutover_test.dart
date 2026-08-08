import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/legacy_cutover/application/legacy_cutover.dart';
import 'package:neximmo_app/features/legacy_cutover/data/legacy_cutover_planner.dart';

void main() {
  const planner = LegacyCutoverPlanner();
  const request = LegacyCutoverRequest(
    targetWorkspaceId: 'a1000000-0000-4000-8000-000000000001',
    actorId: 'a7000000-0000-4000-8000-000000000001',
  );

  LegacyCutoverSnapshot snapshotOf(List<Map<String, Object?>> units) {
    return LegacyCutoverSnapshot(
      tenants: const <Map<String, Object?>>[],
      units: units,
      leases: const <Map<String, Object?>>[],
      scenarios: const <Map<String, Object?>>[],
    );
  }

  test('maps a unit and keeps the legacy area as square metres', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[_unit(id: 'unit-1')]),
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
    final unit = plan.targets[LegacyCutoverEntity.unit]!.single;
    // The legacy column is named sqft but stores square metres; converting
    // would corrupt every area in the workspace.
    expect(unit['area_sqm'], 78.0);
    expect(unit['status'], 'occupied');
    expect(unit['unit_code'], 'WE-01');
    expect(unit['rooms'], isNull);
    expect(unit['workspace_id'], request.targetWorkspaceId);
  });

  test('derives the currency only when a rent exists and reports it', () {
    final withRent = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[_unit(id: 'unit-1')]),
      request: request,
    );
    expect(
      withRent.targets[LegacyCutoverEntity.unit]!.single['currency_code'],
      'EUR',
    );
    expect(
      withRent.report.issues
          .where((issue) => issue.field == 'currency_code')
          .map((issue) => issue.code),
      contains('mapping.currency_inferred'),
    );

    final withoutRent = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _unit(id: 'unit-1')..['market_rent_monthly'] = null,
      ]),
      request: request,
    );
    // No money, no invented currency.
    expect(
      withoutRent.targets[LegacyCutoverEntity.unit]!.single['currency_code'],
      isNull,
    );
    expect(
      withoutRent.report.issues.where(
        (issue) => issue.field == 'currency_code',
      ),
      isEmpty,
    );
  });

  test('binds the unit to the property id the property cutover derived', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[_unit(id: 'unit-1')]),
      request: request,
    );
    final propertyId =
        plan.targets[LegacyCutoverEntity.unit]!.single['property_id']! as String;
    // Stable UUIDv5 in the workspace namespace, not a fresh random id.
    expect(propertyId, matches(_uuidPattern));
    final again = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[_unit(id: 'unit-1')]),
      request: request,
    );
    expect(
      again.targets[LegacyCutoverEntity.unit]!.single['property_id'],
      propertyId,
    );
  });

  test('an unknown unit status fails closed', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _unit(id: 'unit-1')..['status'] = 'rented',
      ]),
      request: request,
    );

    expect(plan.report.status, LegacyCutoverStatus.invalid);
    expect(
      plan.report.issues.map((issue) => issue.code),
      contains('source.invalid_unit_status'),
    );
    final summary = plan.report.summaries.singleWhere(
      (summary) => summary.entity == LegacyCutoverEntity.unit,
    );
    expect(summary.rejectedRows, 1);
    expect(summary.countsReconcile, isTrue);
  });

  test('an offline reason without offline status fails closed', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _unit(id: 'unit-1')..['offline_reason'] = 'Sanierung',
      ]),
      request: request,
    );

    expect(plan.report.status, LegacyCutoverStatus.invalid);
    expect(
      plan.report.issues.map((issue) => issue.code),
      contains('source.offline_reason_without_offline_status'),
    );
  });

  test('never exposes a source value in the shareable report', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _unit(id: 'unit-1')..['notes'] = 'Sensitive unit note',
      ]),
      request: request,
    );
    expect(
      plan.report.toCanonicalJson(),
      isNot(contains('Sensitive unit note')),
    );
  });
}

Map<String, Object?> _unit({required String id}) {
  return <String, Object?>{
    'id': id,
    'asset_property_id': 'NX-2026-0002',
    'unit_code': 'WE-01',
    'unit_type': null,
    'beds': null,
    'baths': null,
    'sqft': 78.0,
    'floor': null,
    'status': 'occupied',
    'market_rent_monthly': 850.0,
    'target_rent_monthly': null,
    'notes': null,
    'offline_reason': null,
    'vacancy_since': null,
    'vacancy_reason': null,
    'marketing_status': null,
    'renovation_status': null,
    'expected_ready_date': null,
    'next_action': null,
    'created_at': 2000,
    'updated_at': 3000,
  };
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
