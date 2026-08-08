import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_signals_contract.dart';
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_repository_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/domain/operations_signal_dto.dart';

const String _workspaceId = 'd1000000-0000-0000-0000-000000000001';
const String _propertyId = 'd7000000-0000-0000-0000-000000000001';
const String _actorId = 'aa000000-0000-0000-0000-000000000001';

const LeasingCommandContext _context = LeasingCommandContext(
  workspaceId: _workspaceId,
  actorId: _actorId,
  mutationId: 'mutation-1',
  correlationId: 'correlation-1',
);

void main() {
  group('SupabaseOperationsSignalsAdapter.list', () {
    test('parses a computed signal, including the acknowledgement fields', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, Object?>{
          'ok': true,
          'entity': <String, Object?>{
            'computed_at': '2026-08-05T00:00:00Z',
            'signals': <Object?>[
              <String, Object?>{
                'signal_key':
                    'lease_expiry:unit-1:lease-1:party-1',
                'type': 'lease_expiry',
                'severity': 'critical',
                'message': 'Lease X expires in 20 days.',
                'recommended_action': 'Review renewal.',
                'property_id': _propertyId,
                'unit_id': 'unit-1',
                'lease_id': 'lease-1',
                'tenant_party_id': 'party-1',
                'status': 'open',
                'resolution_note': null,
                'status_version': null,
                'status_updated_at': null,
              },
              <String, Object?>{
                'signal_key': 'stale_rent_roll:-:-:-',
                'type': 'stale_rent_roll',
                'severity': 'warning',
                'message': 'Rent roll is missing.',
                'recommended_action': 'Generate a snapshot.',
                'property_id': _propertyId,
                'unit_id': null,
                'lease_id': null,
                'tenant_party_id': null,
                'status': 'dismissed',
                'resolution_note': 'Not needed this quarter.',
                'status_version': 2,
                'status_updated_at': '2026-08-01T12:00:00Z',
              },
            ],
          },
        };
      final adapter = SupabaseOperationsSignalsAdapter.withGateway(gateway);

      final result = await adapter.list(
        const OperationsSignalsQuery(
          workspaceId: _workspaceId,
          propertyId: _propertyId,
        ),
      );

      final signals =
          (result as OperationsSignalsSuccess<List<OperationsSignalDto>>).value;
      expect(gateway.calls.single.function, 'operations_signals');
      expect(gateway.calls.single.parameters['p_workspace_id'], _workspaceId);
      expect(gateway.calls.single.parameters['p_property_id'], _propertyId);
      expect(signals, hasLength(2));
      expect(signals[0].signalKey, 'lease_expiry:unit-1:lease-1:party-1');
      expect(signals[0].severity, 'critical');
      expect(signals[0].statusVersion, isNull);
      expect(signals[1].status, 'dismissed');
      expect(signals[1].resolutionNote, 'Not needed this quarter.');
      expect(signals[1].statusVersion, 2);
      expect(signals[1].unitId, isNull);
    });

    test('maps forbidden', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'forbidden',
            'message': 'Operations signals are not permitted',
          },
        };
      final adapter = SupabaseOperationsSignalsAdapter.withGateway(gateway);

      final result = await adapter.list(
        const OperationsSignalsQuery(
          workspaceId: _workspaceId,
          propertyId: _propertyId,
        ),
      );

      expect(
        (result as OperationsSignalsFailure).kind,
        OperationsSignalsFailureKind.forbidden,
      );
    });

    test('maps not_found', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{'code': 'not_found', 'message': 'Property not found'},
        };
      final adapter = SupabaseOperationsSignalsAdapter.withGateway(gateway);

      final result = await adapter.list(
        const OperationsSignalsQuery(
          workspaceId: _workspaceId,
          propertyId: _propertyId,
        ),
      );

      expect(
        (result as OperationsSignalsFailure).kind,
        OperationsSignalsFailureKind.notFound,
      );
    });

    test('a signal from another property is an infrastructure failure, not a leak', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, Object?>{
          'ok': true,
          'entity': <String, Object?>{
            'computed_at': '2026-08-05T00:00:00Z',
            'signals': <Object?>[
              <String, Object?>{
                'signal_key': 'stale_rent_roll:-:-:-',
                'type': 'stale_rent_roll',
                'severity': 'warning',
                'message': 'Rent roll is missing.',
                'recommended_action': 'Generate a snapshot.',
                'property_id': 'some-other-property',
                'status': 'open',
              },
            ],
          },
        };
      final adapter = SupabaseOperationsSignalsAdapter.withGateway(gateway);

      final result = await adapter.list(
        const OperationsSignalsQuery(
          workspaceId: _workspaceId,
          propertyId: _propertyId,
        ),
      );

      expect(
        (result as OperationsSignalsFailure).kind,
        OperationsSignalsFailureKind.infrastructureFailure,
      );
    });

    test('an RPC exception is an infrastructure failure', () async {
      final gateway = _FakeGateway()..throwOnRpc = true;
      final adapter = SupabaseOperationsSignalsAdapter.withGateway(gateway);

      final result = await adapter.list(
        const OperationsSignalsQuery(
          workspaceId: _workspaceId,
          propertyId: _propertyId,
        ),
      );

      expect(
        (result as OperationsSignalsFailure).kind,
        OperationsSignalsFailureKind.infrastructureFailure,
      );
    });
  });

  group('SupabaseOperationsSignalsAdapter.updateStatus', () {
    test('refuses an actor mismatch without calling the RPC', () async {
      final gateway = _FakeGateway(actorId: 'someone-else');
      final adapter = SupabaseOperationsSignalsAdapter.withGateway(gateway);

      final result = await adapter.updateStatus(
        const UpdateOperationsSignalStatusCommand(
          context: _context,
          propertyId: _propertyId,
          signalType: 'lease_expiry',
          signalKey: 'lease_expiry:unit-1:lease-1:party-1',
          status: 'dismissed',
        ),
      );

      expect(
        (result as OperationsSignalsFailure).kind,
        OperationsSignalsFailureKind.forbidden,
      );
      expect(gateway.calls, isEmpty);
    });

    test('creates an acknowledgement and parses the state', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, Object?>{
          'ok': true,
          'entity': <String, Object?>{
            'id': 'state-1',
            'workspace_id': _workspaceId,
            'property_id': _propertyId,
            'signal_type': 'lease_expiry',
            'unit_id': 'unit-1',
            'lease_id': 'lease-1',
            'tenant_party_id': 'party-1',
            'signal_key': 'lease_expiry:unit-1:lease-1:party-1',
            'status': 'dismissed',
            'resolution_note': 'reviewed',
            'version': 1,
            'created_at': '2026-08-05T00:00:00Z',
            'updated_at': '2026-08-05T00:00:00Z',
            'created_by': _actorId,
            'updated_by': _actorId,
          },
        };
      final adapter = SupabaseOperationsSignalsAdapter.withGateway(gateway);

      final result = await adapter.updateStatus(
        const UpdateOperationsSignalStatusCommand(
          context: _context,
          propertyId: _propertyId,
          signalType: 'lease_expiry',
          signalKey: 'lease_expiry:unit-1:lease-1:party-1',
          unitId: 'unit-1',
          leaseId: 'lease-1',
          tenantPartyId: 'party-1',
          status: 'dismissed',
          resolutionNote: 'reviewed',
        ),
      );

      final state =
          (result as OperationsSignalsSuccess<OperationsSignalStateDto>).value;
      expect(gateway.calls.single.function, 'update_operations_signal_status');
      expect(gateway.calls.single.parameters['p_expected_version'], isNull);
      expect(state.status, 'dismissed');
      expect(state.version, 1);
    });

    test('maps a version_conflict with the current entity', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'version_conflict',
            'message': 'Signal state version is stale',
            'expected_version': 1,
            'actual_version': 2,
            'current_entity': <String, Object?>{
              'id': 'state-1',
              'workspace_id': _workspaceId,
              'property_id': _propertyId,
              'signal_type': 'lease_expiry',
              'signal_key': 'lease_expiry:unit-1:lease-1:party-1',
              'status': 'resolved',
              'version': 2,
              'created_at': '2026-08-05T00:00:00Z',
              'updated_at': '2026-08-05T00:00:00Z',
              'created_by': _actorId,
              'updated_by': _actorId,
            },
          },
        };
      final adapter = SupabaseOperationsSignalsAdapter.withGateway(gateway);

      final result = await adapter.updateStatus(
        const UpdateOperationsSignalStatusCommand(
          context: _context,
          propertyId: _propertyId,
          signalType: 'lease_expiry',
          signalKey: 'lease_expiry:unit-1:lease-1:party-1',
          status: 'dismissed',
          expectedVersion: 1,
        ),
      );

      final failure = result as OperationsSignalsFailure;
      expect(failure.kind, OperationsSignalsFailureKind.versionConflict);
      expect(failure.versionConflict!.expectedVersion, 1);
      expect(failure.versionConflict!.actualVersion, 2);
      expect(failure.versionConflict!.currentState!.status, 'resolved');
    });

    test('maps a version_conflict for "does not exist yet" without an entity', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'version_conflict',
            'message': 'Signal state does not exist yet',
            'expected_version': 1,
            'actual_version': null,
          },
        };
      final adapter = SupabaseOperationsSignalsAdapter.withGateway(gateway);

      final result = await adapter.updateStatus(
        const UpdateOperationsSignalStatusCommand(
          context: _context,
          propertyId: _propertyId,
          signalType: 'lease_expiry',
          signalKey: 'lease_expiry:unit-1:lease-1:party-1',
          status: 'dismissed',
          expectedVersion: 1,
        ),
      );

      final failure = result as OperationsSignalsFailure;
      expect(failure.kind, OperationsSignalsFailureKind.versionConflict);
      expect(failure.versionConflict!.actualVersion, isNull);
      expect(failure.versionConflict!.currentState, isNull);
    });

    test('maps validation_failed', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'validation_failed',
            'message': 'Unknown signal type',
            'field': 'signal_type',
          },
        };
      final adapter = SupabaseOperationsSignalsAdapter.withGateway(gateway);

      final result = await adapter.updateStatus(
        const UpdateOperationsSignalStatusCommand(
          context: _context,
          propertyId: _propertyId,
          signalType: 'not_a_real_type',
          signalKey: 'not_a_real_type:-:-:-',
          status: 'dismissed',
        ),
      );

      expect(
        (result as OperationsSignalsFailure).kind,
        OperationsSignalsFailureKind.validationFailed,
      );
    });
  });
}

class _FakeGateway implements LeasingSupabaseGateway {
  _FakeGateway({this.actorId = _actorId});

  final String? actorId;
  Object? rpcResponse;
  bool throwOnRpc = false;

  final List<({String function, Map<String, Object?> parameters})> calls =
      <({String function, Map<String, Object?> parameters})>[];

  @override
  String? get currentUserId => actorId;

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) async {
    if (throwOnRpc) {
      throw StateError('boom');
    }
    calls.add((function: function, parameters: parameters));
    return rpcResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> listUnits({
    required String workspaceId,
    required String? propertyId,
    required String? status,
    required String? afterId,
    required int limit,
  }) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> getUnit({
    required String workspaceId,
    required String unitId,
  }) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> listLeases({
    required String workspaceId,
    required String? propertyId,
    required String? unitId,
    required String? tenantPartyId,
    required String? status,
    required String? afterId,
    required int limit,
  }) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> getLease({
    required String workspaceId,
    required String leaseId,
  }) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> listLeasingCases({
    required String workspaceId,
    required String? propertyId,
    required String? unitId,
    required String? status,
    required bool openOnly,
    required String? afterId,
    required int limit,
  }) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> getLeasingCase({
    required String workspaceId,
    required String caseId,
  }) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> listRentRollSnapshots({
    required String workspaceId,
    required String propertyId,
    required String? afterId,
    required int limit,
  }) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> getRentRollSnapshot({
    required String workspaceId,
    required String snapshotId,
  }) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> listRentRollSnapshotLines({
    required String workspaceId,
    required String snapshotId,
  }) => throw UnimplementedError();
}
