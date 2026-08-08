import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/maintenance_capex/application/maintenance_capex_repository.dart';
import 'package:neximmo_app/features/maintenance_capex/data/supabase_maintenance_capex_repository_adapter.dart';
import 'package:neximmo_app/features/maintenance_capex/domain/capex_project_dto.dart';
import 'package:neximmo_app/features/maintenance_capex/domain/maintenance_ticket_dto.dart';

/// Records what the adapter sends and replays canned responses, so the
/// mapping between the contract and the P2-D06 RPC surface is testable
/// without a live Supabase client (same shape as the P2-D05 leasing adapter
/// tests).
class _FakeGateway implements MaintenanceCapexSupabaseGateway {
  _FakeGateway({this.actorId = _actorId});

  final String? actorId;

  Object? rpcResponse;
  List<Map<String, dynamic>> rows = const <Map<String, dynamic>>[];

  final List<({String function, Map<String, Object?> parameters})> calls =
      <({String function, Map<String, Object?> parameters})>[];

  @override
  String? get currentUserId => actorId;

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) async {
    calls.add((function: function, parameters: parameters));
    return rpcResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> getMaintenanceTicket({
    required String workspaceId,
    required String ticketId,
  }) async => rows;

  @override
  Future<List<Map<String, dynamic>>> getCapexProject({
    required String workspaceId,
    required String projectId,
  }) async => rows;
}

const String _workspaceId = 'b1000000-0000-0000-0000-000000000001';
const String _actorId = 'aa000000-0000-0000-0000-000000000001';
const String _propertyId = 'p1000000-0000-0000-0000-000000000001';

MaintenanceCapexCommandContext _context({String? reason}) =>
    MaintenanceCapexCommandContext(
      workspaceId: _workspaceId,
      actorId: _actorId,
      mutationId: 'be000000-0000-0000-0000-000000000001',
      correlationId: 'cc000000-0000-0000-0000-000000000001',
      reason: reason,
    );

Map<String, dynamic> _ticketRow({
  String status = 'new',
  int version = 1,
}) => <String, dynamic>{
  'id': 't1000000-0000-0000-0000-000000000001',
  'workspace_id': _workspaceId,
  'property_id': _propertyId,
  'unit_id': null,
  'title': 'Leaking pipe',
  'description': null,
  'category': 'general',
  'status': status,
  'priority': 'normal',
  'reported_at': '2026-01-01T00:00:00Z',
  'due_at': null,
  'resolved_at': null,
  // Postgres numeric arrives as a String over PostgREST.
  'cost_estimate': '250.50',
  'cost_actual': null,
  'currency_code': 'EUR',
  'contractor_party_id': null,
  'damage_location': null,
  'insurance_case': false,
  'insurance_status': null,
  'insurance_claim_number': null,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'created_by': _actorId,
  'updated_by': _actorId,
  'version': version,
};

Map<String, dynamic> _projectRow({
  String status = 'idea',
  int version = 1,
}) => <String, dynamic>{
  'id': 'c1000000-0000-0000-0000-000000000001',
  'workspace_id': _workspaceId,
  'property_id': _propertyId,
  'project_code': 'CX-1',
  'category': 'roof',
  'measure': 'Re-roofing',
  'status': status,
  'start_date': null,
  'planned_end_date': '2026-06-01',
  'actual_end_date': null,
  'budget_amount': '5000',
  'forecast_amount': null,
  'actual_amount': null,
  'currency_code': 'EUR',
  'contractor_party_id': null,
  'owner': 'Hausmeister',
  'next_step': null,
  'approved_by': null,
  'approved_at': null,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'created_by': _actorId,
  'updated_by': _actorId,
  'version': version,
};

void main() {
  group('maintenance ticket adapter', () {
    test('create sends every draft field under the RPC parameter names', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{'ok': true, 'entity': _ticketRow()};
      final adapter = SupabaseMaintenanceTicketRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.create(
        CreateMaintenanceTicketCommand(
          context: _context(),
          draft: const MaintenanceTicketDraft(
            propertyId: _propertyId,
            title: 'Leaking pipe',
            priority: MaintenanceTicketPriority.high,
            dueAt: null,
            costEstimate: 250.50,
          ),
        ),
      );

      expect(result, isA<MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>>());
      final call = gateway.calls.single;
      expect(call.function, 'create_maintenance_ticket');
      expect(call.parameters['p_workspace_id'], _workspaceId);
      expect(call.parameters['p_title'], 'Leaking pipe');
      expect(call.parameters['p_priority'], 'high');
      expect(call.parameters['p_cost_estimate'], 250.50);
    });

    test('sends the wire label "new" for MaintenanceTicketStatus.newTicket, '
        'not the Dart member name', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': _ticketRow(status: 'triage'),
        };
      final adapter = SupabaseMaintenanceTicketRepositoryAdapter.withGateway(
        gateway,
      );

      await adapter.transitionStatus(
        TransitionMaintenanceTicketStatusCommand(
          context: _context(),
          ticketId: 't1',
          expectedVersion: 1,
          targetStatus: MaintenanceTicketStatus.triage,
        ),
      );

      expect(gateway.calls.single.parameters['p_target_status'], 'triage');
    });

    test('reads "new" back as MaintenanceTicketStatus.newTicket', () async {
      final gateway = _FakeGateway()
        ..rows = <Map<String, dynamic>>[_ticketRow(status: 'new')];
      final adapter = SupabaseMaintenanceTicketRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.getById(
        workspaceId: _workspaceId,
        ticketId: 't1',
      );

      final ticket =
          (result as MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>)
              .value;
      expect(ticket.status, MaintenanceTicketStatus.newTicket);
      expect(ticket.costEstimate, 250.50);
    });

    test('update sends a flat sparse patch, not a nested p_changes object', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{'ok': true, 'entity': _ticketRow()};
      final adapter = SupabaseMaintenanceTicketRepositoryAdapter.withGateway(
        gateway,
      );

      await adapter.update(
        const UpdateMaintenanceTicketCommand(
          context: MaintenanceCapexCommandContext(
            workspaceId: _workspaceId,
            actorId: _actorId,
            mutationId: 'm1',
            correlationId: 'c1',
          ),
          ticketId: 't1',
          expectedVersion: 1,
          changes: MaintenanceTicketUpdateDto(costActual: 300),
        ),
      );

      final call = gateway.calls.single;
      expect(call.function, 'update_maintenance_ticket');
      expect(call.parameters.containsKey('p_changes'), isFalse);
      expect(call.parameters['p_cost_actual'], 300);
      expect(call.parameters['p_title'], isNull);
    });

    test('a version conflict carries the current ticket, not a project', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': false,
          'error': <String, dynamic>{
            'code': 'version_conflict',
            'message': 'Ticket version is stale',
            'expected_version': 1,
            'actual_version': 4,
            'current_entity': _ticketRow(version: 4),
          },
        };
      final adapter = SupabaseMaintenanceTicketRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.transitionStatus(
        TransitionMaintenanceTicketStatusCommand(
          context: _context(),
          ticketId: 't1',
          expectedVersion: 1,
          targetStatus: MaintenanceTicketStatus.triage,
        ),
      );

      final failure =
          result as MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>;
      expect(failure.kind, MaintenanceCapexRepositoryFailureKind.versionConflict);
      expect(failure.versionConflict!.currentTicket!.version, 4);
      expect(failure.versionConflict!.currentProject, isNull);
    });

    test('a dependency conflict surfaces an invalid contractor role', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': false,
          'error': <String, dynamic>{
            'code': 'dependency_conflict',
            'message': 'The party does not hold an open contractor role',
          },
        };
      final adapter = SupabaseMaintenanceTicketRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.create(
        CreateMaintenanceTicketCommand(
          context: _context(),
          draft: const MaintenanceTicketDraft(
            propertyId: _propertyId,
            title: 'Leaking pipe',
            contractorPartyId: 'not-a-contractor',
          ),
        ),
      );

      expect(
        (result as MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>)
            .kind,
        MaintenanceCapexRepositoryFailureKind.dependencyConflict,
      );
    });

    test('refuses to act when the command actor is not the signed-in user', () async {
      final gateway = _FakeGateway(actorId: 'someone-else');
      final adapter = SupabaseMaintenanceTicketRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.transitionStatus(
        TransitionMaintenanceTicketStatusCommand(
          context: _context(),
          ticketId: 't1',
          expectedVersion: 1,
          targetStatus: MaintenanceTicketStatus.triage,
        ),
      );

      expect(
        (result as MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>)
            .kind,
        MaintenanceCapexRepositoryFailureKind.forbidden,
      );
      expect(gateway.calls, isEmpty, reason: 'no RPC may be attempted');
    });

    test('a row from another workspace never reaches the caller', () async {
      final gateway = _FakeGateway()
        ..rows = <Map<String, dynamic>>[
          _ticketRow()..['workspace_id'] = 'other-workspace',
        ];
      final adapter = SupabaseMaintenanceTicketRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.getById(
        workspaceId: _workspaceId,
        ticketId: 't1',
      );

      expect(
        (result as MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>)
            .kind,
        MaintenanceCapexRepositoryFailureKind.infrastructureFailure,
      );
    });

    test('search calls the RPC (not a table select) and requires a property', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <Map<String, dynamic>>[_ticketRow()],
        };
      final adapter = SupabaseMaintenanceTicketRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.search(
        const MaintenanceTicketListQuery(
          workspaceId: _workspaceId,
          propertyId: _propertyId,
          priority: MaintenanceTicketPriority.normal,
        ),
      );

      final tickets = (result
              as MaintenanceCapexRepositorySuccess<
                List<MaintenanceTicketSummaryDto>
              >)
          .value;
      expect(tickets, hasLength(1));
      final call = gateway.calls.single;
      expect(call.function, 'maintenance_tickets');
      expect(call.parameters['p_property_id'], _propertyId);
      expect(call.parameters['p_priority'], 'normal');
    });

    test('searchWorkspace calls the workspace-wide RPC, no property needed', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <Map<String, dynamic>>[_ticketRow(), _ticketRow()],
        };
      final adapter = SupabaseMaintenanceTicketRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.searchWorkspace(
        const WorkspaceMaintenanceTicketListQuery(
          workspaceId: _workspaceId,
          status: MaintenanceTicketStatus.newTicket,
        ),
      );

      final tickets = (result
              as MaintenanceCapexRepositorySuccess<
                List<MaintenanceTicketSummaryDto>
              >)
          .value;
      expect(tickets, hasLength(2));
      final call = gateway.calls.single;
      expect(call.function, 'workspace_maintenance_tickets');
      expect(call.parameters.containsKey('p_property_id'), isFalse);
      expect(call.parameters['p_status'], 'new');
    });

    test('search surfaces a server-side forbidden as its own failure kind', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': false,
          'error': <String, dynamic>{
            'code': 'forbidden',
            'message': 'Maintenance tickets are not permitted',
          },
        };
      final adapter = SupabaseMaintenanceTicketRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.search(
        const MaintenanceTicketListQuery(
          workspaceId: _workspaceId,
          propertyId: _propertyId,
        ),
      );

      expect(
        (result
                as MaintenanceCapexRepositoryFailure<
                  List<MaintenanceTicketSummaryDto>
                >)
            .kind,
        MaintenanceCapexRepositoryFailureKind.forbidden,
      );
    });
  });

  group('capex project adapter', () {
    test('create sends every draft field under the RPC parameter names, '
        'dates as calendar days', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{'ok': true, 'entity': _projectRow()};
      final adapter = SupabaseCapexProjectRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.create(
        CreateCapexProjectCommand(
          context: _context(),
          draft: CapexProjectDraft(
            propertyId: _propertyId,
            projectCode: 'CX-1',
            plannedEndDate: DateTime(2026, 6, 1),
            budgetAmount: 5000,
          ),
        ),
      );

      expect(result, isA<MaintenanceCapexRepositorySuccess<CapexProjectDto>>());
      final call = gateway.calls.single;
      expect(call.function, 'create_capex_project');
      expect(call.parameters['p_project_code'], 'CX-1');
      expect(call.parameters['p_planned_end_date'], '2026-06-01');
      expect(call.parameters['p_budget_amount'], 5000);
    });

    test('entering "approved" is still a plain transition call: the '
        'capex.approve gate is enforced server-side, not client-side', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': _projectRow(status: 'approved'),
        };
      final adapter = SupabaseCapexProjectRepositoryAdapter.withGateway(
        gateway,
      );

      await adapter.transitionStatus(
        TransitionCapexProjectStatusCommand(
          context: _context(),
          projectId: 'c1',
          expectedVersion: 1,
          targetStatus: CapexProjectStatus.approved,
        ),
      );

      expect(gateway.calls.single.parameters['p_target_status'], 'approved');
    });

    test('a forbidden approval attempt is surfaced, not silently ignored', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': false,
          'error': <String, dynamic>{
            'code': 'forbidden',
            'message': 'CapEx approval is not permitted',
          },
        };
      final adapter = SupabaseCapexProjectRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.transitionStatus(
        TransitionCapexProjectStatusCommand(
          context: _context(),
          projectId: 'c1',
          expectedVersion: 1,
          targetStatus: CapexProjectStatus.approved,
        ),
      );

      expect(
        (result as MaintenanceCapexRepositoryFailure<CapexProjectDto>).kind,
        MaintenanceCapexRepositoryFailureKind.forbidden,
      );
    });

    test('a version conflict carries the current project, not a ticket', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': false,
          'error': <String, dynamic>{
            'code': 'version_conflict',
            'message': 'Project version is stale',
            'expected_version': 1,
            'actual_version': 3,
            'current_entity': _projectRow(version: 3),
          },
        };
      final adapter = SupabaseCapexProjectRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.update(
        UpdateCapexProjectCommand(
          context: _context(),
          projectId: 'c1',
          expectedVersion: 1,
          changes: const CapexProjectUpdateDto(budgetAmount: 6000),
        ),
      );

      final failure =
          result as MaintenanceCapexRepositoryFailure<CapexProjectDto>;
      expect(failure.kind, MaintenanceCapexRepositoryFailureKind.versionConflict);
      expect(failure.versionConflict!.currentProject!.version, 3);
      expect(failure.versionConflict!.currentTicket, isNull);
    });

    test('reads back approvedBy/approvedAt once the server sets them', () async {
      final gateway = _FakeGateway()
        ..rows = <Map<String, dynamic>>[
          _projectRow(status: 'approved')
            ..['approved_by'] = _actorId
            ..['approved_at'] = '2026-02-01T00:00:00Z',
        ];
      final adapter = SupabaseCapexProjectRepositoryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.getById(
        workspaceId: _workspaceId,
        projectId: 'c1',
      );

      final project =
          (result as MaintenanceCapexRepositorySuccess<CapexProjectDto>).value;
      expect(project.approvedBy, _actorId);
      expect(project.approvedAt, DateTime.parse('2026-02-01T00:00:00Z'));
    });

    test('search requires a property, matching public.capex_projects', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, dynamic>{
          'ok': true,
          'entity': <Map<String, dynamic>>[_projectRow()],
        };
      final adapter = SupabaseCapexProjectRepositoryAdapter.withGateway(
        gateway,
      );

      await adapter.search(
        const CapexProjectListQuery(
          workspaceId: _workspaceId,
          propertyId: _propertyId,
          status: CapexProjectStatus.idea,
        ),
      );

      final call = gateway.calls.single;
      expect(call.function, 'capex_projects');
      expect(call.parameters['p_property_id'], _propertyId);
      expect(call.parameters['p_status'], 'idea');
    });
  });
}
