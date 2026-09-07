/// ALERT-READER-01 (P-10): the client half of the workspace worklist.
///
/// Everything here is one rule stated four ways: **the numbers are the
/// server's, and the client never re-derives them from what it can see.**
///
/// The list is capped. So a count taken over the returned rows is a count of
/// what fitted, and reporting it as the workspace total is the single most
/// plausible way this feature could go wrong — the screen would say "3
/// kritisch" while forty criticals sat behind the cap, and it would look
/// perfectly reasonable. The same applies to filtering: a client-side filter
/// over a capped page searches only what came back.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_signals_contract.dart';
import 'package:neximmo_app/features/leasing_operations/application/workspace_alerts_controller.dart';
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_repository_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/domain/operations_signal_dto.dart';

import 'leasing_gateway_fake.dart';

void main() {
  group('adapter', () {
    late FakeLeasingGateway gateway;
    late SupabaseOperationsSignalsAdapter adapter;

    setUp(() {
      gateway = FakeLeasingGateway();
      adapter = SupabaseOperationsSignalsAdapter.withGateway(gateway);
    });

    Future<OperationsSignalsResult<WorkspaceOperationsSignalsDto>> read({
      String? severity,
      String? status,
      int? limit,
    }) {
      return adapter.listWorkspace(
        WorkspaceOperationsSignalsQuery(
          workspaceId: 'ws-1',
          severity: severity,
          status: status,
          limit: limit,
        ),
      );
    }

    WorkspaceOperationsSignalsDto valueOf(
      OperationsSignalsResult<WorkspaceOperationsSignalsDto> result,
    ) {
      return (result
              as OperationsSignalsSuccess<WorkspaceOperationsSignalsDto>)
          .value;
    }

    test('parses the signals and the property they belong to', () async {
      gateway.rpcResult = _answer();

      final value = valueOf(await read());

      expect(value.signals, hasLength(2));
      expect(value.signals.first.type, 'lease_expiry');
      expect(
        value.signals.first.propertyName,
        'Alpha-Haus',
        reason: 'a workspace list without it is unusable: "Lease 4B expires in '
            '12 days" says nothing when forty buildings are in scope',
      );
      expect(value.computedAt, DateTime.parse('2026-09-07T08:00:00Z'));
    });

    test('the totals are read, never counted from the returned rows', () async {
      // Two rows back, forty matched. If the adapter ever starts counting
      // `signals.length`, this is what fails.
      gateway.rpcResult = _answer(
        total: 40,
        truncated: true,
        bySeverity: <String, Object?>{'critical': 31, 'warning': 9},
      );

      final value = valueOf(await read());

      expect(value.signals, hasLength(2));
      expect(value.total, 40);
      expect(value.truncated, isTrue);
      expect(value.criticalCount, 31);
      expect(value.warningCount, 9);
      expect(value.infoCount, 0);
    });

    test('a list that fits is not truncated', () async {
      gateway.rpcResult = _answer();

      final value = valueOf(await read());

      expect(value.total, 2);
      expect(
        value.truncated,
        isFalse,
        reason: 'paired with the assertion above so neither could pass by the '
            'adapter hard-coding one answer',
      );
    });

    test('the filters reach the server rather than being applied here', () async {
      gateway.rpcResult = _answer();

      await read(severity: 'critical', status: 'open', limit: 50);

      expect(gateway.lastRpcName, 'workspace_operations_signals');
      expect(gateway.lastRpcParameters?['p_severity'], 'critical');
      expect(gateway.lastRpcParameters?['p_status'], 'open');
      expect(gateway.lastRpcParameters?['p_limit'], 50);
    });

    test('forbidden maps to the forbidden failure', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'forbidden',
          'message': 'AAL2 is required for the alert list',
        },
      };

      final result = await read();

      expect(
        (result as OperationsSignalsFailure<WorkspaceOperationsSignalsDto>).kind,
        OperationsSignalsFailureKind.forbidden,
      );
    });

    test('a malformed answer fails rather than returning an empty worklist',
        () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': <String, Object?>{'computed_at': '2026-09-07T08:00:00Z'},
      };

      final result = await read();

      expect(
        (result as OperationsSignalsFailure<WorkspaceOperationsSignalsDto>).kind,
        OperationsSignalsFailureKind.infrastructureFailure,
        reason: 'an empty list here reads as "nothing to do today", which is '
            'the one thing a broken worklist must never say',
      );
    });
  });

  group('controller', () {
    late _FakePort port;

    WorkspaceAlertsController controller({String? workspaceId = 'ws-1'}) {
      final subject = WorkspaceAlertsController(
        signals: port,
        scope: workspaceId == null
            ? const WorkspaceSessionScope.unresolved()
            : WorkspaceSessionScope(
                workspaceId: workspaceId,
                actorId: 'actor-a',
                permissions: const <String>{'lease.read'},
                mutationsSupported: true,
              ),
      );
      addTearDown(subject.dispose);
      return subject;
    }

    setUp(() {
      port = _FakePort();
    });

    test('loads open signals by default', () async {
      final subject = controller();

      await subject.load();

      expect(subject.state.phase, WorkspaceAlertsPhase.ready);
      expect(
        port.queries.single.status,
        'open',
        reason: 'a worklist is what has not been dealt with. Dismissed and '
            'resolved stay reachable through the filter',
      );
      expect(port.queries.single.severity, isNull);
    });

    test('changing a filter re-queries instead of filtering what it holds',
        () async {
      final subject = controller();
      await subject.load();

      await subject.setSeverityFilter('critical');

      expect(port.queries, hasLength(2));
      expect(
        port.queries.last.severity,
        'critical',
        reason: 'the list is capped, so filtering the returned page would '
            'search only what fitted and could report "no criticals" while '
            'criticals were cut off',
      );
    });

    test('setting the same filter again does not re-query', () async {
      final subject = controller();
      await subject.load();

      await subject.setStatusFilter('open');

      expect(port.queries, hasLength(1));
    });

    test('a refusal drops the list rather than leaving a stale one', () async {
      final subject = controller();
      await subject.load();
      expect(subject.state.signals, isNotEmpty);

      port.failure = OperationsSignalsFailureKind.forbidden;
      await subject.load();

      expect(subject.state.phase, WorkspaceAlertsPhase.forbidden);
      expect(
        subject.state.result,
        isNull,
        reason: 'a stale worklist beside an error message invites acting on '
            'numbers nobody is maintaining any more',
      );
      expect(subject.state.total, 0);
    });

    test('a broken read is an error, not a refusal', () async {
      port.failure = OperationsSignalsFailureKind.infrastructureFailure;
      final subject = controller();

      await subject.load();

      expect(subject.state.phase, WorkspaceAlertsPhase.error);
    });

    test('without a workspace nothing is asked for', () async {
      final subject = controller(workspaceId: null);

      await subject.load();

      expect(port.queries, isEmpty);
      expect(subject.state.phase, WorkspaceAlertsPhase.forbidden);
    });

    test('the counts come from the answer, not from the rows', () async {
      port.total = 40;
      port.truncated = true;
      port.bySeverity = const <String, int>{'critical': 31, 'warning': 9};
      final subject = controller();

      await subject.load();

      expect(subject.state.signals, hasLength(1));
      expect(subject.state.total, 40);
      expect(subject.state.criticalCount, 31);
      expect(subject.state.truncated, isTrue);
    });
  });
}

Map<String, Object?> _answer({
  int total = 2,
  bool truncated = false,
  Map<String, Object?> bySeverity = const <String, Object?>{
    'critical': 1,
    'warning': 1,
  },
}) {
  return <String, Object?>{
    'ok': true,
    'entity': <String, Object?>{
      'computed_at': '2026-09-07T08:00:00Z',
      'signals': <Object?>[
        <String, Object?>{
          'signal_key': 'lease_expiry:-:l-1:-',
          'type': 'lease_expiry',
          'severity': 'critical',
          'message': 'Lease Alpha expires in 20 days.',
          'recommended_action': 'Review renewal.',
          'property_id': 'p-1',
          'property_name': 'Alpha-Haus',
          'unit_id': null,
          'lease_id': 'l-1',
          'tenant_party_id': null,
          'status': 'open',
          'resolution_note': null,
          'status_version': null,
          'status_updated_at': null,
        },
        <String, Object?>{
          'signal_key': 'vacancy_aged:u-1:-:-',
          'type': 'vacancy_aged',
          'severity': 'warning',
          'message': 'Unit B-01 has been vacant for 60 days.',
          'recommended_action': 'Review marketing status.',
          'property_id': 'p-2',
          'property_name': 'Beta-Haus',
          'unit_id': 'u-1',
          'lease_id': null,
          'tenant_party_id': null,
          'status': 'open',
          'resolution_note': null,
          'status_version': null,
          'status_updated_at': null,
        },
      ],
      'total': total,
      'returned': 2,
      'truncated': truncated,
      'limit': 200,
      'total_by_severity': bySeverity,
    },
  };
}

class _FakePort implements OperationsSignalsPort {
  final List<WorkspaceOperationsSignalsQuery> queries =
      <WorkspaceOperationsSignalsQuery>[];
  OperationsSignalsFailureKind? failure;
  int total = 1;
  bool truncated = false;
  Map<String, int> bySeverity = const <String, int>{'critical': 1};

  @override
  Future<OperationsSignalsResult<WorkspaceOperationsSignalsDto>> listWorkspace(
    WorkspaceOperationsSignalsQuery query,
  ) async {
    queries.add(query);
    final kind = failure;
    if (kind != null) {
      return OperationsSignalsFailure<WorkspaceOperationsSignalsDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return OperationsSignalsSuccess<WorkspaceOperationsSignalsDto>(
      WorkspaceOperationsSignalsDto(
        computedAt: DateTime.utc(2026, 9, 7, 8),
        signals: const <OperationsSignalDto>[
          OperationsSignalDto(
            signalKey: 'lease_expiry:-:l-1:-',
            type: 'lease_expiry',
            severity: 'critical',
            message: 'Lease Alpha expires in 20 days.',
            recommendedAction: 'Review renewal.',
            propertyId: 'p-1',
            propertyName: 'Alpha-Haus',
            leaseId: 'l-1',
            status: 'open',
          ),
        ],
        total: total,
        truncated: truncated,
        limit: 200,
        totalBySeverity: bySeverity,
      ),
    );
  }

  @override
  Future<OperationsSignalsResult<List<OperationsSignalDto>>> list(
    OperationsSignalsQuery query,
  ) async => throw UnimplementedError('list');

  @override
  Future<OperationsSignalsResult<OperationsSignalStateDto>> updateStatus(
    UpdateOperationsSignalStatusCommand command,
  ) async => throw UnimplementedError('updateStatus');
}
