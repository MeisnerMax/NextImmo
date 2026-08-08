import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/legacy_cutover/application/legacy_cutover.dart';
import 'package:neximmo_app/features/legacy_cutover/data/legacy_cutover_planner.dart';

void main() {
  const planner = LegacyCutoverPlanner();
  const request = LegacyCutoverRequest(
    targetWorkspaceId: 'a1000000-0000-4000-8000-000000000001',
    actorId: 'a7000000-0000-4000-8000-000000000001',
  );

  LegacyCutoverSnapshot snapshotOf(List<Map<String, Object?>> leases) {
    return LegacyCutoverSnapshot(
      tenants: const <Map<String, Object?>>[],
      units: const <Map<String, Object?>>[],
      leases: leases,
      scenarios: const <Map<String, Object?>>[],
    );
  }

  test('maps a lease and resolves its three foreign keys', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[_lease(id: 'lease-1')]),
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
    final lease = plan.targets[LegacyCutoverEntity.lease]!.single;
    expect(lease['lease_name'], 'Mietvertrag WE-01');
    expect(lease['status'], 'active');
    expect(lease['deposit_status'], 'open');
    // Epoch millis become calendar dates, not timestamps.
    expect(lease['start_date'], '2024-01-01');
    for (final key in <String>['property_id', 'unit_id', 'tenant_party_id']) {
      expect(lease[key], matches(_uuidPattern), reason: key);
    }
  });

  test('derives the terminal timestamps the target invariants require', () {
    final ended = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _lease(id: 'lease-1')..['status'] = 'ended',
      ]),
      request: request,
    );
    final endedLease = ended.targets[LegacyCutoverEntity.lease]!.single;
    // leases_ended_marker_check: status 'ended' requires ended_at.
    expect(endedLease['ended_at'], isNotNull);
    expect(endedLease['cancelled_at'], isNull);
    expect(
      ended.report.issues.map((issue) => issue.code),
      contains('mapping.ended_at_inferred'),
    );

    final cancelled = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _lease(id: 'lease-1')..['status'] = 'cancelled',
      ]),
      request: request,
    );
    final cancelledLease = cancelled.targets[LegacyCutoverEntity.lease]!.single;
    expect(cancelledLease['cancelled_at'], isNotNull);
    expect(cancelledLease['ended_at'], isNull);

    // An ordinary lease carries neither marker.
    final active = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[_lease(id: 'lease-1')]),
      request: request,
    );
    final activeLease = active.targets[LegacyCutoverEntity.lease]!.single;
    expect(activeLease['ended_at'], isNull);
    expect(activeLease['cancelled_at'], isNull);
  });

  test('drops a deposit status that has no deposit amount', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _lease(id: 'lease-1')..['security_deposit'] = null,
      ]),
      request: request,
    );

    // The target refuses a payment state without an amount, so the row still
    // migrates but the state is dropped visibly rather than failing the lease.
    expect(plan.report.status, LegacyCutoverStatus.ready);
    expect(
      plan.targets[LegacyCutoverEntity.lease]!.single['deposit_status'],
      isNull,
    );
    expect(
      plan.report.issues.map((issue) => issue.code),
      contains('mapping.deposit_status_without_amount'),
    );
  });

  test('the unmodelled execution date is reported, not dropped silently', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _lease(id: 'lease-1')..['executed_date'] = 1704067200000,
      ]),
      request: request,
    );

    expect(
      plan.report.issues
          .where((issue) => issue.code == 'mapping.field_excluded')
          .map((issue) => issue.field),
      contains('executed_date'),
    );
    expect(plan.report.importReady, isTrue);
  });

  test('invalid enums and money fail closed', () {
    for (final broken in <Map<String, Object?>>[
      _lease(id: 'l')..['status'] = 'terminated',
      _lease(id: 'l')..['billing_frequency'] = 'weekly',
      _lease(id: 'l')..['currency_code'] = 'eur',
      _lease(id: 'l')..['base_rent_monthly'] = -1,
      _lease(id: 'l')..['payment_day_of_month'] = 31,
    ]) {
      final plan = planner.plan(
        snapshot: snapshotOf(<Map<String, Object?>>[broken]),
        request: request,
      );
      expect(plan.report.status, LegacyCutoverStatus.invalid);
      final summary = plan.report.summaries.singleWhere(
        (summary) => summary.entity == LegacyCutoverEntity.lease,
      );
      expect(summary.rejectedRows, 1);
      expect(summary.countsReconcile, isTrue);
    }
  });

  test('an end date before the start date fails closed', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _lease(id: 'lease-1')..['end_date'] = 1600000000000,
      ]),
      request: request,
    );

    expect(plan.report.status, LegacyCutoverStatus.invalid);
    expect(
      plan.report.issues.map((issue) => issue.code),
      contains('source.end_before_start'),
    );
  });

  test('never exposes a source value in the shareable report', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _lease(id: 'lease-1')..['notes'] = 'Sensitive lease note',
      ]),
      request: request,
    );
    expect(
      plan.report.toCanonicalJson(),
      isNot(contains('Sensitive lease note')),
    );
  });
}

Map<String, Object?> _lease({required String id}) {
  return <String, Object?>{
    'id': id,
    'asset_property_id': 'FX-0001',
    'unit_id': 'FX-U-0001',
    'tenant_id': 'FX-T-0001',
    'lease_name': 'Mietvertrag WE-01',
    'status': 'active',
    'start_date': 1704067200000, // 2024-01-01
    'end_date': null,
    'move_in_date': null,
    'move_out_date': null,
    'lease_signed_date': null,
    'notice_date': null,
    'renewal_option_date': null,
    'break_option_date': null,
    'executed_date': null,
    'base_rent_monthly': 850.0,
    'ancillary_charges_monthly': null,
    'parking_other_charges_monthly': null,
    'currency_code': 'EUR',
    'security_deposit': 2550.0,
    'deposit_status': 'open',
    'payment_day_of_month': 3,
    'billing_frequency': 'monthly',
    'rent_free_period_months': null,
    'notes': null,
    'created_at': 2000,
    'updated_at': 3000,
  };
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
