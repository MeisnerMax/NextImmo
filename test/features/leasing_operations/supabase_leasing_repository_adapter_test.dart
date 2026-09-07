import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_repository_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_component_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/leasing_case_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/rent_roll_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';

/// Records what the adapter sends and replays canned responses, so the mapping
/// between the contract and the P2-D05 RPC surface is testable without a live
/// Supabase client (same shape as the P2-D02 party adapter tests).
class _FakeGateway implements LeasingSupabaseGateway {
  _FakeGateway({this.actorId = _actor});

  static const String _actor = 'aa000000-0000-0000-0000-000000000001';

  final String? actorId;

  Object? rpcResponse;
  List<Map<String, dynamic>> rows = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> lineRows = const <Map<String, dynamic>>[];

  final List<({String function, Map<String, Object?> parameters})> calls =
      <({String function, Map<String, Object?> parameters})>[];
  final List<Map<String, Object?>> listCalls = <Map<String, Object?>>[];

  @override
  String? get currentUserId => actorId;

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) async {
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
  }) async {
    listCalls.add(<String, Object?>{
      'workspaceId': workspaceId,
      'propertyId': propertyId,
      'status': status,
      'afterId': afterId,
      'limit': limit,
    });
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> getUnit({
    required String workspaceId,
    required String unitId,
  }) async => rows;

  @override
  Future<List<Map<String, dynamic>>> listLeases({
    required String workspaceId,
    required String? propertyId,
    required String? unitId,
    required String? tenantPartyId,
    required String? status,
    required String? afterId,
    required int limit,
  }) async {
    listCalls.add(<String, Object?>{
      'workspaceId': workspaceId,
      'propertyId': propertyId,
      'unitId': unitId,
      'tenantPartyId': tenantPartyId,
      'status': status,
      'afterId': afterId,
      'limit': limit,
    });
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> getLease({
    required String workspaceId,
    required String leaseId,
  }) async => rows;

  @override
  Future<List<Map<String, dynamic>>> listLeasingCases({
    required String workspaceId,
    required String? propertyId,
    required String? unitId,
    required String? status,
    required bool openOnly,
    required String? afterId,
    required int limit,
  }) async {
    listCalls.add(<String, Object?>{
      'workspaceId': workspaceId,
      'propertyId': propertyId,
      'unitId': unitId,
      'status': status,
      'openOnly': openOnly,
      'afterId': afterId,
      'limit': limit,
    });
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> getLeasingCase({
    required String workspaceId,
    required String caseId,
  }) async => rows;

  @override
  Future<List<Map<String, dynamic>>> listRentRollSnapshots({
    required String workspaceId,
    required String propertyId,
    required String? afterId,
    required int limit,
  }) async => rows;

  @override
  Future<List<Map<String, dynamic>>> getRentRollSnapshot({
    required String workspaceId,
    required String snapshotId,
  }) async => rows;

  @override
  Future<List<Map<String, dynamic>>> listRentRollSnapshotLines({
    required String workspaceId,
    required String snapshotId,
  }) async => lineRows;
}

const String _workspaceId = 'b1000000-0000-0000-0000-000000000001';
const String _actorId = 'aa000000-0000-0000-0000-000000000001';

LeasingCommandContext _context({String? reason}) => LeasingCommandContext(
  workspaceId: _workspaceId,
  actorId: _actorId,
  mutationId: 'be000000-0000-0000-0000-000000000001',
  correlationId: 'cc000000-0000-0000-0000-000000000001',
  reason: reason,
);

Map<String, dynamic> _unitRow({
  String status = 'vacant',
  String unitCode = 'EG-links',
  int version = 1,
}) => <String, dynamic>{
  'id': 'u1000000-0000-0000-0000-000000000001',
  'workspace_id': _workspaceId,
  'property_id': 'p1000000-0000-0000-0000-000000000001',
  'unit_code': unitCode,
  'status': status,
  'version': version,
  'unit_type': 'apartment',
  'floor': '0',
  // Postgres numeric arrives as a String over PostgREST.
  'area_sqm': '68.5',
  'rooms': '3',
  'bathrooms': '1',
  'target_rent_monthly': '950',
  'market_rent_monthly': '1050',
  'currency_code': 'EUR',
  'vacancy_since': '2026-01-01',
  'vacancy_reason': null,
  'offline_reason': null,
  'marketing_status': null,
  'renovation_status': null,
  'expected_ready_date': null,
  'next_action': null,
  'notes': null,
  'created_at': '2026-01-01T10:00:00Z',
  'updated_at': '2026-01-01T10:00:00Z',
  'created_by': _actorId,
  'updated_by': _actorId,
};

Map<String, dynamic> _leaseRow({String status = 'tenant_signed'}) =>
    <String, dynamic>{
      'id': 'l1000000-0000-0000-0000-000000000001',
      'workspace_id': _workspaceId,
      'property_id': 'p1000000-0000-0000-0000-000000000001',
      'unit_id': 'u1000000-0000-0000-0000-000000000001',
      'lease_name': 'Mietvertrag EG-links',
      'status': status,
      'start_date': '2026-01-01',
      'end_date': null,
      'base_rent_monthly': '950',
      'currency_code': 'EUR',
      'tenant_party_id': 't1000000-0000-0000-0000-000000000001',
      'version': 2,
      'billing_frequency': 'monthly',
      'move_in_date': null,
      'move_out_date': null,
      'signed_date': null,
      'notice_date': null,
      'renewal_option_date': null,
      'break_option_date': null,
      'ancillary_charges_monthly': '150',
      'parking_other_charges_monthly': '50',
      'security_deposit': null,
      'payment_day_of_month': null,
      'rent_free_period_months': null,
      'ended_at': null,
      'cancelled_at': null,
      'notes': null,
      'created_at': '2026-01-01T10:00:00Z',
      'updated_at': '2026-01-01T10:00:00Z',
      'created_by': _actorId,
      'updated_by': _actorId,
    };

Map<String, dynamic> _caseRow({String status = 'documents_pending'}) =>
    <String, dynamic>{
      'id': 'c1000000-0000-0000-0000-000000000001',
      'workspace_id': _workspaceId,
      'property_id': 'p1000000-0000-0000-0000-000000000001',
      'case_name': 'Anfrage Meier',
      'status': status,
      'source': 'walk_in',
      'opened_at': '2026-01-01T10:00:00Z',
      'version': 3,
      'unit_id': null,
      'prospect_party_id': null,
      'lease_id': null,
      'completed_at': null,
      'cancelled_at': null,
      'notes': null,
      'created_at': '2026-01-01T10:00:00Z',
      'updated_at': '2026-01-01T10:00:00Z',
      'created_by': _actorId,
      'updated_by': _actorId,
    };

Map<String, dynamic> _snapshotRow() => <String, dynamic>{
  'id': 's1000000-0000-0000-0000-000000000001',
  'workspace_id': _workspaceId,
  'property_id': 'p1000000-0000-0000-0000-000000000001',
  'as_of_date': '2026-03-31',
  'currency_code': 'EUR',
  'generated_at': '2026-03-31T12:00:00Z',
  'unit_count': 3,
  'occupied_unit_count': 2,
  'vacant_unit_count': 1,
  'offline_unit_count': 0,
  'effective_lease_count': 2,
  'total_base_rent_monthly': '1050',
  'total_ancillary_charges_monthly': '170',
  'total_parking_other_charges_monthly': '60',
  'total_rent_monthly': '1280',
  'created_at': '2026-03-31T12:00:00Z',
  'created_by': _actorId,
};

Map<String, dynamic> _liveEntity() => <String, dynamic>{
  'workspace_id': _workspaceId,
  'property_id': 'p1000000-0000-0000-0000-000000000001',
  'as_of_date': '2026-03-31',
  'computed_at': '2026-03-31T12:00:00Z',
  'currency_code': 'EUR',
  'currencies': <String>['EUR'],
  'unit_count': 1,
  'occupied_unit_count': 1,
  'vacant_unit_count': 0,
  'offline_unit_count': 0,
  'effective_lease_count': 1,
  'total_base_rent_monthly': '1250',
  'total_ancillary_charges_monthly': '30',
  'total_parking_other_charges_monthly': '0',
  'total_rent_monthly': '1280',
  'lines': <Map<String, dynamic>>[],
};

Map<String, dynamic> _lineRow({
  String unitCode = 'EG-links',
  String unitStatus = 'occupied',
  int leaseCount = 2,
  String total = '1280',
}) => <String, dynamic>{
  'id': 'ln100000-0000-0000-0000-000000000001',
  'unit_id': 'u1000000-0000-0000-0000-000000000001',
  'unit_code': unitCode,
  'unit_status': unitStatus,
  'effective_lease_count': leaseCount,
  'base_rent_monthly': '1050',
  'ancillary_charges_monthly': '170',
  'parking_other_charges_monthly': '60',
  'total_rent_monthly': total,
  'area_sqm': '68.5',
};

void main() {
  group('unit adapter', () {
    test('create sends every draft field under the RPC parameter names', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{'ok': true, 'entity': _unitRow()};
      final adapter = SupabaseUnitRepositoryAdapter.withGateway(gateway);

      final result = await adapter.create(
        CreateUnitCommand(
          context: _context(),
          draft: UnitDraft(
            propertyId: 'p1000000-0000-0000-0000-000000000001',
            unitCode: 'EG-links',
            areaSqm: 68.5,
            currencyCode: 'EUR',
            expectedReadyDate: DateTime(2026, 6, 1),
          ),
        ),
      );

      expect(result, isA<LeasingRepositorySuccess<UnitDto>>());
      final call = gateway.calls.single;
      expect(call.function, 'create_unit');
      expect(call.parameters['p_workspace_id'], _workspaceId);
      expect(call.parameters['p_unit_code'], 'EG-links');
      expect(call.parameters['p_area_sqm'], 68.5);
      // A date column takes a calendar day, never a full timestamp.
      expect(call.parameters['p_expected_ready_date'], '2026-06-01');
    });

    test('parses numeric-as-string and the derived status', () async {
      final gateway = _FakeGateway()..rows = <Map<String, dynamic>>[_unitRow()];
      final adapter = SupabaseUnitRepositoryAdapter.withGateway(gateway);

      final result = await adapter.getById(
        workspaceId: _workspaceId,
        unitId: 'u1000000-0000-0000-0000-000000000001',
      );

      final unit = (result as LeasingRepositorySuccess<UnitDto>).value;
      expect(unit.areaSqm, 68.5);
      expect(unit.targetRentMonthly, 950);
      expect(unit.status, UnitStatus.vacant);
      expect(unit.vacancySince, DateTime.parse('2026-01-01'));
    });

    test('a transition into offline forwards the reason the server stores as '
        'offline_reason', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': _unitRow(status: 'offline'),
        };
      final adapter = SupabaseUnitRepositoryAdapter.withGateway(gateway);

      await adapter.transitionStatus(
        TransitionUnitStatusCommand(
          context: _context(reason: 'Wasserschaden'),
          unitId: 'u1000000-0000-0000-0000-000000000001',
          expectedVersion: 1,
          targetStatus: UnitStatus.offline,
        ),
      );

      final call = gateway.calls.single;
      expect(call.function, 'transition_unit_status');
      expect(call.parameters['p_target_status'], 'offline');
      expect(call.parameters['p_reason'], 'Wasserschaden');
    });

    test('a version conflict carries the current unit, not a lease or case',
        () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': false,
          'error': <String, dynamic>{
            'code': 'version_conflict',
            'message': 'Unit version is stale',
            'expected_version': 1,
            'actual_version': 4,
            'current_entity': _unitRow(version: 4),
          },
        };
      final adapter = SupabaseUnitRepositoryAdapter.withGateway(gateway);

      final result = await adapter.transitionStatus(
        TransitionUnitStatusCommand(
          context: _context(reason: 'x'),
          unitId: 'u1000000-0000-0000-0000-000000000001',
          expectedVersion: 1,
          targetStatus: UnitStatus.offline,
        ),
      );

      final failure = result as LeasingRepositoryFailure<UnitDto>;
      expect(failure.kind, LeasingRepositoryFailureKind.versionConflict);
      expect(failure.versionConflict!.actualVersion, 4);
      expect(failure.versionConflict!.currentUnit!.version, 4);
      expect(failure.versionConflict!.currentLease, isNull);
      expect(failure.versionConflict!.currentCase, isNull);
    });

    test('refuses to act when the command actor is not the signed-in user',
        () async {
      final gateway = _FakeGateway(actorId: 'someone-else');
      final adapter = SupabaseUnitRepositoryAdapter.withGateway(gateway);

      final result = await adapter.transitionStatus(
        TransitionUnitStatusCommand(
          context: _context(reason: 'x'),
          unitId: 'u1000000-0000-0000-0000-000000000001',
          expectedVersion: 1,
          targetStatus: UnitStatus.offline,
        ),
      );

      expect(
        (result as LeasingRepositoryFailure<UnitDto>).kind,
        LeasingRepositoryFailureKind.forbidden,
      );
      expect(gateway.calls, isEmpty, reason: 'no RPC may be attempted');
    });

    test('a row from another workspace never reaches the caller', () async {
      final gateway = _FakeGateway()
        ..rows = <Map<String, dynamic>>[
          _unitRow()..['workspace_id'] = 'other-workspace',
        ];
      final adapter = SupabaseUnitRepositoryAdapter.withGateway(gateway);

      final result = await adapter.getById(
        workspaceId: _workspaceId,
        unitId: 'u1000000-0000-0000-0000-000000000001',
      );

      expect(
        (result as LeasingRepositoryFailure<UnitDto>).kind,
        LeasingRepositoryFailureKind.infrastructureFailure,
      );
    });

    test('paging asks for one row beyond the page and exposes a cursor',
        () async {
      final gateway = _FakeGateway()
        ..rows = <Map<String, dynamic>>[
          _unitRow(unitCode: 'A'),
          _unitRow(unitCode: 'B'),
        ];
      final adapter = SupabaseUnitRepositoryAdapter.withGateway(gateway);

      final result = await adapter.search(
        const UnitListQuery(
          workspaceId: _workspaceId,
          status: UnitStatus.occupied,
          page: LeasingPageRequest(limit: 1),
        ),
      );

      final page =
          (result as LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>)
              .value;
      expect(page.items, hasLength(1));
      expect(page.nextCursor, isNotNull);
      expect(gateway.listCalls.single['limit'], 2);
      expect(gateway.listCalls.single['status'], 'occupied');
    });
  });

  group('lease adapter', () {
    test('maps camelCase statuses onto the snake_case Postgres enum', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{'ok': true, 'entity': _leaseRow()};
      final adapter = SupabaseLeaseRepositoryAdapter.withGateway(gateway);

      await adapter.transitionStatus(
        TransitionLeaseStatusCommand(
          context: _context(),
          leaseId: 'l1000000-0000-0000-0000-000000000001',
          expectedVersion: 1,
          targetStatus: LeaseStatus.tenantSigned,
        ),
      );

      expect(gateway.calls.single.parameters['p_target_status'], 'tenant_signed');
    });

    test('reads landlord_signed back as the Dart label', () async {
      final gateway = _FakeGateway()
        ..rows = <Map<String, dynamic>>[_leaseRow(status: 'landlord_signed')];
      final adapter = SupabaseLeaseRepositoryAdapter.withGateway(gateway);

      final result = await adapter.getById(
        workspaceId: _workspaceId,
        leaseId: 'l1000000-0000-0000-0000-000000000001',
      );

      final lease = (result as LeasingRepositorySuccess<LeaseDto>).value;
      expect(lease.status, LeaseStatus.landlordSigned);
      expect(lease.status.isEffective, isFalse);
      expect(lease.totalRentMonthly, 1150);
    });

    test('effectiveOnly narrows the query to active leases server-side',
        () async {
      final gateway = _FakeGateway();
      final adapter = SupabaseLeaseRepositoryAdapter.withGateway(gateway);

      await adapter.search(
        const LeaseListQuery(
          workspaceId: _workspaceId,
          unitId: 'u1000000-0000-0000-0000-000000000001',
          effectiveOnly: true,
        ),
      );

      expect(gateway.listCalls.single['status'], 'active');
      expect(
        gateway.listCalls.single['unitId'],
        'u1000000-0000-0000-0000-000000000001',
        reason: 'OPN-DOM-001: a unit read returns every lease, not one',
      );
    });
  });

  group('leasing case adapter', () {
    test('maps the multi-word STM-004 labels in both directions', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': _caseRow(status: 'contract_draft'),
        };
      final adapter = SupabaseLeasingCaseRepositoryAdapter.withGateway(gateway);

      final result = await adapter.transitionStatus(
        TransitionLeasingCaseStatusCommand(
          context: _context(),
          caseId: 'c1000000-0000-0000-0000-000000000001',
          expectedVersion: 3,
          targetStatus: LeasingCaseStatus.contractDraft,
        ),
      );

      expect(gateway.calls.single.parameters['p_target_status'], 'contract_draft');
      final entity = (result as LeasingRepositorySuccess<LeasingCaseDto>).value;
      expect(entity.status, LeasingCaseStatus.contractDraft);
      expect(entity.source, LeasingCaseSource.walkIn);
    });

    test('create sends walk_in rather than the Dart label', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{'ok': true, 'entity': _caseRow()};
      final adapter = SupabaseLeasingCaseRepositoryAdapter.withGateway(gateway);

      await adapter.create(
        CreateLeasingCaseCommand(
          context: _context(),
          draft: const LeasingCaseDraft(
            propertyId: 'p1000000-0000-0000-0000-000000000001',
            caseName: 'Anfrage Meier',
            source: LeasingCaseSource.walkIn,
          ),
        ),
      );

      expect(gateway.calls.single.parameters['p_source'], 'walk_in');
    });

    test('openOnly reaches the gateway so terminal cases stay out of the board',
        () async {
      final gateway = _FakeGateway();
      final adapter = SupabaseLeasingCaseRepositoryAdapter.withGateway(gateway);

      await adapter.search(
        const LeasingCaseListQuery(workspaceId: _workspaceId, openOnly: true),
      );

      expect(gateway.listCalls.single['openOnly'], isTrue);
    });
  });

  group('rent roll adapter', () {
    test('readLive parses the server-computed document', () async {
      // P2-D05b: one RPC, no client arithmetic. The adapter's job is to parse,
      // not to decide which lease counts.
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <String, dynamic>{
            'workspace_id': _workspaceId,
            'property_id': 'p1000000-0000-0000-0000-000000000001',
            'as_of_date': '2026-03-31',
            'computed_at': '2026-03-31T12:00:00Z',
            'currency_code': 'EUR',
            'currencies': <String>['EUR'],
            'unit_count': 2,
            'occupied_unit_count': 1,
            'vacant_unit_count': 1,
            'offline_unit_count': 0,
            'effective_lease_count': 2,
            'total_base_rent_monthly': '1250',
            'total_ancillary_charges_monthly': '30',
            'total_parking_other_charges_monthly': '0',
            'total_rent_monthly': '1280',
            'lines': <Map<String, dynamic>>[
              <String, dynamic>{
                'unit_id': 'u1000000-0000-0000-0000-000000000001',
                'unit_code': 'EG-links',
                'unit_status': 'occupied',
                'area_sqm': '60',
                'effective_lease_count': 2,
                'base_rent_monthly': '1250',
                'ancillary_charges_monthly': '30',
                'parking_other_charges_monthly': '0',
                'total_rent_monthly': '1280',
                'currency_code': 'EUR',
                'currencies': <String>['EUR'],
              },
              <String, dynamic>{
                'unit_id': 'u1000000-0000-0000-0000-000000000002',
                'unit_code': 'EG-rechts',
                'unit_status': 'occupied',
                'area_sqm': null,
                'effective_lease_count': 0,
                'base_rent_monthly': '0',
                'ancillary_charges_monthly': '0',
                'parking_other_charges_monthly': '0',
                'total_rent_monthly': '0',
                'currency_code': null,
                'currencies': <String>[],
              },
            ],
          },
        };
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      final result = await adapter.readLive(
        workspaceId: _workspaceId,
        propertyId: 'p1000000-0000-0000-0000-000000000001',
        asOfDate: DateTime(2026, 3, 31),
      );

      final live = (result as LeasingRepositorySuccess<RentRollLiveDto>).value;
      expect(gateway.calls.single.function, 'rent_roll_live');
      expect(gateway.calls.single.parameters['p_as_of_date'], '2026-03-31');
      expect(live.lines, hasLength(2));
      expect(live.totalRentMonthly, 1280);
      expect(live.currencyCode, 'EUR');
      // The one figure that looks like a bug and is not.
      expect(live.occupiedOutsideTermLines.single.unitCode, 'EG-rechts');
    });

    test('a live document with disagreeing currencies has no total', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <String, dynamic>{
            'workspace_id': _workspaceId,
            'property_id': 'p1000000-0000-0000-0000-000000000001',
            'as_of_date': '2026-03-31',
            'computed_at': '2026-03-31T12:00:00Z',
            'currency_code': null,
            'currencies': <String>['CHF', 'EUR'],
            'unit_count': 1,
            'occupied_unit_count': 1,
            'vacant_unit_count': 0,
            'offline_unit_count': 0,
            'effective_lease_count': 2,
            'total_base_rent_monthly': null,
            'total_ancillary_charges_monthly': null,
            'total_parking_other_charges_monthly': null,
            'total_rent_monthly': null,
            'lines': <Map<String, dynamic>>[],
          },
        };
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      final result = await adapter.readLive(
        workspaceId: _workspaceId,
        propertyId: 'p1000000-0000-0000-0000-000000000001',
        asOfDate: DateTime(2026, 3, 31),
      );

      final live = (result as LeasingRepositorySuccess<RentRollLiveDto>).value;
      // DEC-011: null says "not summable"; a zero would say something false.
      expect(live.totalRentMonthly, isNull);
      expect(live.hasMixedCurrencies, isTrue);
      expect(live.currencies, <String>['CHF', 'EUR']);
    });

    test('createSnapshot returns the embedded frozen lines', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <String, dynamic>{
            ..._snapshotRow(),
            'lines': <Map<String, dynamic>>[
              _lineRow(),
              _lineRow(
                unitCode: 'EG-rechts',
                unitStatus: 'vacant',
                leaseCount: 0,
                total: '0',
              ),
            ],
          },
        };
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      final result = await adapter.createSnapshot(
        CreateRentRollSnapshotCommand(
          context: _context(),
          propertyId: 'p1000000-0000-0000-0000-000000000001',
          asOfDate: DateTime(2026, 3, 31),
        ),
      );

      final snapshot =
          (result as LeasingRepositorySuccess<RentRollSnapshotDto>).value;
      expect(gateway.calls.single.parameters['p_as_of_date'], '2026-03-31');
      expect(snapshot.lines, hasLength(2));
      // OPN-DOM-001: one line per unit, its figures summed over both leases.
      expect(snapshot.lines.first.effectiveLeaseCount, 2);
      expect(snapshot.lines.first.totalRentMonthly, 1280);
      expect(snapshot.lines.last.isEmpty, isTrue);
      expect(snapshot.occupancyRate, closeTo(2 / 3, 1e-9));
    });

    test('a currency mismatch keeps the currencies that caused it', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': false,
          'error': <String, dynamic>{
            'code': 'currency_mismatch',
            'message': 'The contributing leases do not share one currency',
            'currencies': <String>['CHF', 'EUR'],
          },
        };
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      final result = await adapter.createSnapshot(
        CreateRentRollSnapshotCommand(
          context: _context(),
          propertyId: 'p1000000-0000-0000-0000-000000000001',
          asOfDate: DateTime(2026, 3, 31),
        ),
      );

      final failure = result as LeasingRepositoryFailure<RentRollSnapshotDto>;
      expect(failure.kind, LeasingRepositoryFailureKind.currencyMismatch);
      expect(failure.currencyMismatch!.currencies, <String>['CHF', 'EUR']);
    });

    test('an explicit currency is forwarded for an all-vacant property',
        () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <String, dynamic>{
            ..._snapshotRow(),
            'lines': <Map<String, dynamic>>[],
          },
        };
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      await adapter.createSnapshot(
        CreateRentRollSnapshotCommand(
          context: _context(),
          propertyId: 'p1000000-0000-0000-0000-000000000001',
          asOfDate: DateTime(2026, 3, 31),
          currencyCode: 'EUR',
        ),
      );

      expect(gateway.calls.single.parameters['p_currency_code'], 'EUR');
    });

    test('getSnapshot surfaces the occupied-but-outside-term lines', () async {
      final gateway = _FakeGateway()
        ..rows = <Map<String, dynamic>>[_snapshotRow()]
        ..lineRows = <Map<String, dynamic>>[
          _lineRow(
            unitCode: 'OG-links',
            unitStatus: 'occupied',
            leaseCount: 0,
            total: '0',
          ),
        ];
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      final result = await adapter.getSnapshot(
        workspaceId: _workspaceId,
        snapshotId: 's1000000-0000-0000-0000-000000000001',
      );

      final snapshot =
          (result as LeasingRepositorySuccess<RentRollSnapshotDto>).value;
      expect(snapshot.occupiedOutsideTermLines, hasLength(1));
      expect(snapshot.occupiedOutsideTermLines.single.unitCode, 'OG-links');
    });

    // RENT-ROLL-RULE-01: three states, and the adapter must keep them apart.
    // Collapsing any two of them is how a rule change becomes invisible.
    test('a snapshot names the rule that produced it', () async {
      final gateway = _FakeGateway()
        ..rows = <Map<String, dynamic>>[
          <String, dynamic>{
            ..._snapshotRow(),
            'effectiveness_rule_version': 2,
          },
        ];
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      final result = await adapter.getSnapshot(
        workspaceId: _workspaceId,
        snapshotId: 's1000000-0000-0000-0000-000000000001',
      );

      final snapshot =
          (result as LeasingRepositorySuccess<RentRollSnapshotDto>).value;
      expect(snapshot.effectivenessRuleVersion, 2);
      expect(snapshot.effectivenessRule, RentRollEffectivenessRule.v2);
      expect(snapshot.hasUnknownEffectivenessRule, isFalse);
    });

    test('a snapshot without a marker stays unlabelled and is not read as '
        'rule 1', () async {
      // _snapshotRow carries no version — a snapshot frozen before
      // RENT-ROLL-RULE-01, or a database that has not received it. Migration 50
      // opened a second era, so "no marker" is genuinely unknown and the
      // adapter refuses to pick a side.
      final gateway = _FakeGateway()
        ..rows = <Map<String, dynamic>>[_snapshotRow()];
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      final result = await adapter.getSnapshot(
        workspaceId: _workspaceId,
        snapshotId: 's1000000-0000-0000-0000-000000000001',
      );

      final snapshot =
          (result as LeasingRepositorySuccess<RentRollSnapshotDto>).value;
      expect(snapshot.effectivenessRuleVersion, isNull);
      expect(snapshot.effectivenessRule, isNull);
      // Not "unknown": there is no version to fail to recognise.
      expect(snapshot.hasUnknownEffectivenessRule, isFalse);
    });

    test('a rule version newer than this build survives as a number', () async {
      // The database can be ahead of the web build — they reach an environment
      // through different pipelines. Mapping an unrecognised version to null,
      // or silently to the current rule, would hide exactly the change the
      // marker exists to show.
      final gateway = _FakeGateway()
        ..rows = <Map<String, dynamic>>[
          <String, dynamic>{
            ..._snapshotRow(),
            'effectiveness_rule_version': 99,
          },
        ];
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      final result = await adapter.getSnapshot(
        workspaceId: _workspaceId,
        snapshotId: 's1000000-0000-0000-0000-000000000001',
      );

      final snapshot =
          (result as LeasingRepositorySuccess<RentRollSnapshotDto>).value;
      expect(snapshot.effectivenessRuleVersion, 99);
      expect(snapshot.effectivenessRule, isNull);
      expect(snapshot.hasUnknownEffectivenessRule, isTrue);
    });

    test('the live read carries the rule the server applied', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <String, dynamic>{
            ..._liveEntity(),
            'effectiveness_rule_version': 2,
          },
        };
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      final result = await adapter.readLive(
        workspaceId: _workspaceId,
        propertyId: 'p1000000-0000-0000-0000-000000000001',
        asOfDate: DateTime(2026, 3, 31),
      );

      final live = (result as LeasingRepositorySuccess<RentRollLiveDto>).value;
      expect(live.effectivenessRuleVersion, 2);
      expect(live.effectivenessRule, RentRollEffectivenessRule.v2);
    });

    test('a server that publishes no rule version still answers', () async {
      // The web build deploys automatically on merge, the database by hand.
      // Demanding the key would break the rent roll for the length of that gap.
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': _liveEntity(),
        };
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      final result = await adapter.readLive(
        workspaceId: _workspaceId,
        propertyId: 'p1000000-0000-0000-0000-000000000001',
        asOfDate: DateTime(2026, 3, 31),
      );

      final live = (result as LeasingRepositorySuccess<RentRollLiveDto>).value;
      expect(live.totalRentMonthly, 1280);
      expect(live.effectivenessRuleVersion, isNull);
    });

    test('a missing snapshot is notFound, not an infrastructure failure',
        () async {
      final gateway = _FakeGateway()..rows = const <Map<String, dynamic>>[];
      final adapter = SupabaseRentRollAdapter.withGateway(gateway);

      final result = await adapter.getSnapshot(
        workspaceId: _workspaceId,
        snapshotId: 's1000000-0000-0000-0000-000000000001',
      );

      expect(
        (result as LeasingRepositoryFailure<RentRollSnapshotDto>).kind,
        LeasingRepositoryFailureKind.notFound,
      );
    });
  });

  group('STM-004 client mirror', () {
    test('allows exactly one forward step or a cancellation', () {
      expect(
        LeasingCaseStatus.inquiry.canTransitionTo(LeasingCaseStatus.contact),
        isTrue,
      );
      expect(
        LeasingCaseStatus.inquiry.canTransitionTo(LeasingCaseStatus.viewing),
        isFalse,
      );
      expect(
        LeasingCaseStatus.contact.canTransitionTo(LeasingCaseStatus.inquiry),
        isFalse,
        reason: 'STM-004 has no backward edge',
      );
      expect(
        LeasingCaseStatus.screening.canTransitionTo(LeasingCaseStatus.cancelled),
        isTrue,
      );
      expect(
        LeasingCaseStatus.completed.canTransitionTo(LeasingCaseStatus.cancelled),
        isFalse,
        reason: 'nothing leaves a terminal state',
      );
    });

    test('names the precondition that blocks the next step', () {
      LeasingCaseDto caseAt(LeasingCaseStatus status, {String? unitId,
          String? prospectId, String? leaseId}) => LeasingCaseDto(
        id: 'c1',
        workspaceId: _workspaceId,
        propertyId: 'p1',
        caseName: 'x',
        status: status,
        source: LeasingCaseSource.other,
        openedAt: DateTime(2026),
        version: 1,
        unitId: unitId,
        prospectPartyId: prospectId,
        leaseId: leaseId,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        createdBy: _actorId,
        updatedBy: _actorId,
      );

      expect(
        caseAt(LeasingCaseStatus.documentsPending).blockedReason,
        LeasingCaseBlockedReason.prospectRequired,
      );
      expect(
        caseAt(LeasingCaseStatus.screening, prospectId: 't1').blockedReason,
        LeasingCaseBlockedReason.unitRequired,
      );
      expect(
        caseAt(
          LeasingCaseStatus.contractDraft,
          prospectId: 't1',
          unitId: 'u1',
        ).blockedReason,
        LeasingCaseBlockedReason.leaseRequired,
      );
      expect(
        caseAt(
          LeasingCaseStatus.offer,
          prospectId: 't1',
          unitId: 'u1',
        ).blockedReason,
        isNull,
      );
      expect(caseAt(LeasingCaseStatus.completed).blockedReason, isNull);
    });
  });

  group('lease term coverage', () {
    test('a lease starting in July does not cover a March reporting date', () {
      final lease = LeaseSummaryDto(
        id: 'l1',
        workspaceId: _workspaceId,
        propertyId: 'p1',
        unitId: 'u1',
        leaseName: 'ab Juli',
        status: LeaseStatus.active,
        startDate: DateTime(2026, 7, 1),
        baseRentMonthly: 1000,
        currencyCode: 'EUR',
        version: 1,
      );

      expect(lease.isEffective, isTrue, reason: 'AGG-004 counts it as occupied');
      expect(
        lease.coversDate(DateTime(2026, 3, 31)),
        isFalse,
        reason: 'the rent roll additionally applies the term window',
      );
      expect(lease.coversDate(DateTime(2026, 7, 1)), isTrue);
    });
  });

  group('lease component adapter', () {
    LeasingCommandContext context() => const LeasingCommandContext(
      workspaceId: _workspaceId,
      actorId: 'aa000000-0000-0000-0000-000000000001',
      mutationId: 'mm000000-0000-0000-0000-000000000001',
      correlationId: 'cc000000-0000-0000-0000-000000000001',
    );

    Map<String, dynamic> row({
      String id = 'k1',
      String type = 'base_rent',
      double amount = 1000.0,
      String currency = 'EUR',
      String vatMode = 'exempt',
      Object? vatRate,
      Object? validTo,
    }) => <String, dynamic>{
      'id': id,
      'lease_id': 'l1',
      'property_id': 'p1',
      'component_type': type,
      'amount': amount,
      'currency_code': currency,
      'vat_mode': vatMode,
      'vat_rate_percent': vatRate,
      'valid_from': '2026-01-01',
      'valid_to': validTo,
      'version': 1,
    };

    Future<LeasingRepositoryResult<LeaseComponentsAsOfDto>> readWith(
      _FakeGateway gateway,
    ) => SupabaseLeaseComponentAdapter.withGateway(gateway).readAsOf(
      LeaseComponentListQuery(
        workspaceId: _workspaceId,
        asOfDate: DateTime(2026, 3, 15),
        leaseId: 'l1',
      ),
    );

    test('parses the envelope, including the date it is true on', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <String, dynamic>{
            'as_of_date': '2026-03-15',
            'components': <Map<String, dynamic>>[row()],
          },
        };

      final result = await readWith(gateway);

      final value = (result as LeasingRepositorySuccess<LeaseComponentsAsOfDto>)
          .value;
      // The date travels with the answer rather than being remembered by the
      // caller: amounts without it are the misreading LEASING-ASOF-01 removes.
      expect(value.asOfDate, DateTime(2026, 3, 15));
      expect(value.components.single.amount, 1000.0);
      expect(value.components.single.isOpenEnded, isTrue);
      expect(gateway.calls.single.function, 'lease_components_as_of');
    });

    test('a refusal arrives as a typed code, not as an exception', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': false,
          'error': <String, dynamic>{
            'code': 'forbidden',
            'message': 'Not permitted to read leases',
          },
        };

      final result = await readWith(gateway);

      expect(
        (result as LeasingRepositoryFailure<LeaseComponentsAsOfDto>).kind,
        LeasingRepositoryFailureKind.forbidden,
        reason:
            'this is what LEASING-COMPONENTS-01b bought: while the read raised '
            'instead of answering, the adapter could only report an '
            'infrastructure failure and the screen could not say why',
      );
    });

    test('an unfamiliar type is kept and labelled, not dropped', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <String, dynamic>{
            'as_of_date': '2026-03-15',
            'components': <Map<String, dynamic>>[
              row(id: 'k9', type: 'garden_levy', amount: 25.0),
            ],
          },
        };

      final result = await readWith(gateway);

      final component =
          (result as LeasingRepositorySuccess<LeaseComponentsAsOfDto>)
              .value
              .components
              .single;
      // Dropping it would understate what a tenant pays; throwing would break
      // a whole contract view over one row a newer server sent.
      expect(component.componentType, LeaseComponentType.unknown);
      expect(component.rawTypeKey, 'garden_levy');
      expect(component.amount, 25.0);
    });

    test('an empty answer is a success, not a failure', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <String, dynamic>{
            'as_of_date': '2026-11-15',
            'components': <Map<String, dynamic>>[],
          },
        };

      final result = await readWith(gateway);

      final value = (result as LeasingRepositorySuccess<LeaseComponentsAsOfDto>)
          .value;
      expect(value.components, isEmpty);
      // DEC-029: nothing recorded is not nothing owed. There is no zero here
      // and no total either — since WARM-RENT-01 the sum is the server's.
      expect(value.ofType(LeaseComponentType.baseRent), isNull);
      expect(value.complete, isTrue, reason: 'nothing to be incomplete about');
    });

    test('create sends the wire keys and reads the entity back', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': row(id: 'k2', type: 'heating_advance', amount: 90.0),
        };
      final adapter = SupabaseLeaseComponentAdapter.withGateway(gateway);

      final result = await adapter.create(
        CreateLeaseComponentCommand(
          context: context(),
          leaseId: 'l1',
          componentType: LeaseComponentType.heatingAdvance,
          validFrom: DateTime(2026, 1, 1),
          amount: 90,
        ),
      );

      expect(result, isA<LeasingRepositorySuccess<LeaseComponentDto>>());
      final call = gateway.calls.single;
      expect(call.function, 'create_lease_component');
      expect(call.parameters['p_component_type'], 'heating_advance');
      // Never sent: the server reads it from the lease, so a caller cannot
      // introduce a mismatch.
      expect(call.parameters.containsKey('p_currency_code'), isFalse);
    });

    test('an unknown type is refused before it reaches the server', () async {
      final gateway = _FakeGateway();
      final adapter = SupabaseLeaseComponentAdapter.withGateway(gateway);

      final result = await adapter.create(
        CreateLeaseComponentCommand(
          context: context(),
          leaseId: 'l1',
          componentType: LeaseComponentType.unknown,
          validFrom: DateTime(2026, 1, 1),
          amount: 10,
        ),
      );

      expect(
        (result as LeasingRepositoryFailure<LeaseComponentDto>).kind,
        LeasingRepositoryFailureKind.validationFailed,
      );
      expect(
        gateway.calls,
        isEmpty,
        reason: 'the enum is owned here, so the reason stays legible',
      );
    });

    test('closing is its own call, not an update with an end date', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': row(id: 'k2', validTo: '2026-04-30'),
        };
      final adapter = SupabaseLeaseComponentAdapter.withGateway(gateway);

      await adapter.close(
        CloseLeaseComponentCommand(
          context: context(),
          componentId: 'k2',
          expectedVersion: 1,
          validTo: DateTime(2026, 4, 30),
        ),
      );

      // Ending a component and correcting its end date are different events,
      // and the audit trail says so — which it can only do if the client calls
      // the command that means it.
      expect(gateway.calls.single.function, 'close_lease_component');
    });

    test('a net amount without a rate has no gross figure', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <String, dynamic>{
            'as_of_date': '2026-03-15',
            'components': <Map<String, dynamic>>[
              row(id: 'n1', vatMode: 'net'),
              row(id: 'n2', vatMode: 'net', vatRate: 19.0, amount: 100.0),
            ],
          },
        };

      final result = await readWith(gateway);
      final components =
          (result as LeasingRepositorySuccess<LeaseComponentsAsOfDto>)
              .value
              .components;

      // Null rather than the net amount: returning it would present a net
      // figure as a gross one, which is the quiet kind of wrong.
      expect(components.first.grossMonthly, isNull);
      expect(components.last.grossMonthly, closeTo(119, 0.001));
    });

    test('components in different currencies are not summed', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <String, dynamic>{
            'as_of_date': '2026-03-15',
            'components': <Map<String, dynamic>>[
              row(id: 'c1', amount: 100.0),
              row(id: 'c2', amount: 50.0, currency: 'CHF'),
            ],
          },
        };

      final result = await readWith(gateway);
      final value = (result as LeasingRepositorySuccess<LeaseComponentsAsOfDto>)
          .value;

      // Both rows survive parsing with their own currency. Refusing to add
      // them is no longer this layer's job — `warm_rent_as_of` withholds the
      // figure — but losing one of them here would hide the conflict entirely.
      expect(value.components, hasLength(2));
      expect(
        value.components.map((c) => c.currencyCode).toSet(),
        <String>{'EUR', 'CHF'},
      );
    });
  });
}
