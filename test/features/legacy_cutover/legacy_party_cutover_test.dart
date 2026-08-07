import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/legacy_cutover/application/legacy_cutover.dart';
import 'package:neximmo_app/features/legacy_cutover/data/legacy_cutover_planner.dart';

void main() {
  const planner = LegacyCutoverPlanner();
  const request = LegacyCutoverRequest(
    targetWorkspaceId: 'a1000000-0000-4000-8000-000000000001',
    actorId: 'a7000000-0000-4000-8000-000000000001',
  );

  LegacyCutoverSnapshot snapshotOf(List<Map<String, Object?>> tenants) {
    return LegacyCutoverSnapshot(
      tenants: tenants,
      units: const <Map<String, Object?>>[],
      leases: const <Map<String, Object?>>[],
      scenarios: const <Map<String, Object?>>[],
    );
  }

  test('maps a tenant to one party and one open tenant role', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[_tenant(id: 'tenant-1')]),
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
    expect(plan.report.importReady, isTrue);
    expect(plan.report.manifestChecksum, hasLength(64));

    final party = plan.targets[LegacyCutoverEntity.party]!.single;
    final role = plan.targets[LegacyCutoverEntity.partyRole]!.single;
    expect(party['display_name'], 'Max');
    expect(party['workspace_id'], request.targetWorkspaceId);
    expect(party['created_by'], request.actorId);
    expect(party['version'], 1);
    expect(role['party_id'], party['id']);
    expect(role['role_type'], 'tenant');
    expect(role['valid_until'], isNull);
  });

  test('is deterministic across source order and repeated runs', () {
    final tenants = <Map<String, Object?>>[
      _tenant(id: 'tenant-1'),
      _tenant(id: 'tenant-2', displayName: 'Steen'),
    ];
    final first = planner.plan(snapshot: snapshotOf(tenants), request: request);
    final retry = planner.plan(snapshot: snapshotOf(tenants), request: request);
    final reordered = planner.plan(
      snapshot: snapshotOf(tenants.reversed.toList()),
      request: request,
    );

    expect(retry.report.toCanonicalJson(), first.report.toCanonicalJson());
    expect(reordered.report.toCanonicalJson(), first.report.toCanonicalJson());
  });

  test('never exposes a source value in the shareable report', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _tenant(id: 'tenant-1')
          ..addAll(<String, Object?>{
            'email': 'secret.person@example.com',
            'phone': '0122324325',
            'notes': 'Sensitive tenant note',
          }),
      ]),
      request: request,
    );

    final serialized = plan.report.toCanonicalJson();
    for (final sensitive in <String>[
      'secret.person@example.com',
      '0122324325',
      'Sensitive tenant note',
      'Max',
    ]) {
      expect(serialized, isNot(contains(sensitive)));
    }
  });

  test('derives the party type and reports the derivation', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _tenant(id: 'person', displayName: 'Steen', legalName: 'Steen'),
        _tenant(
          id: 'company',
          displayName: '613 Investment Group',
          legalName: '613 Investment Group GmbH',
        ),
      ]),
      request: request,
    );

    final parties = plan.targets[LegacyCutoverEntity.party]!;
    expect(
      parties.map((party) => party['party_type']),
      containsAll(<String>['person', 'organization']),
    );
    // The target requires a party type the legacy core does not store, so the
    // derivation must be visible for every row rather than assumed correct.
    expect(
      plan.report.issues
          .where((issue) => issue.field == 'party_type')
          .map((issue) => issue.code)
          .toSet(),
      <String>{'mapping.party_type_inferred'},
    );
    expect(
      plan.report.issues.where((issue) => issue.field == 'party_type').length,
      2,
    );
  });

  test('excluded leasing state is reported, not silently dropped', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _tenant(id: 'tenant-1')
          ..addAll(<String, Object?>{'move_in_reference': 'request'}),
      ]),
      request: request,
    );

    expect(
      plan.report.issues
          .where((issue) => issue.code == 'mapping.field_excluded')
          .map((issue) => issue.field),
      containsAll(<String>['status', 'move_in_reference']),
    );
    expect(plan.report.importReady, isTrue);
  });

  test('an unknown source column fails closed', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _tenant(id: 'tenant-1')
          ..addAll(<String, Object?>{'legacy_new_column': 'unexpected'}),
      ]),
      request: request,
    );

    expect(plan.report.status, LegacyCutoverStatus.invalid);
    expect(plan.report.importReady, isFalse);
    expect(
      plan.report.issues.map((issue) => issue.code),
      contains('mapping.unknown_field'),
    );
    final summary = plan.report.summaries.singleWhere(
      (summary) => summary.entity == LegacyCutoverEntity.party,
    );
    expect(summary.mappedRows, 0);
    expect(summary.rejectedRows, 1);
    expect(summary.countsReconcile, isTrue);
  });

  test('a malformed email is rejected rather than written', () {
    final plan = planner.plan(
      snapshot: snapshotOf(<Map<String, Object?>>[
        _tenant(id: 'tenant-1')..addAll(<String, Object?>{'email': '@nope'}),
      ]),
      request: request,
    );

    expect(plan.report.status, LegacyCutoverStatus.invalid);
    expect(
      plan.report.issues.map((issue) => issue.code),
      contains('source.invalid_email'),
    );
  });
}

Map<String, Object?> _tenant({
  required String id,
  String displayName = 'Max',
  String? legalName = 'Max Mustermann',
}) {
  return <String, Object?>{
    'id': id,
    'display_name': displayName,
    'legal_name': legalName,
    'email': null,
    'phone': null,
    'notes': null,
    'status': 'active',
    'alternative_contact': null,
    'billing_contact': null,
    'move_in_reference': null,
    'created_at': 2000,
    'updated_at': 3000,
  };
}
