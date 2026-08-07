import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/maintenance_capex_repository.dart';
import '../domain/capex_project_dto.dart';
import '../domain/maintenance_ticket_dto.dart';

/// The narrow surface this adapter needs from Supabase, so the adapter itself
/// is testable without a live client (mirrors `LeasingSupabaseGateway`).
///
/// Listing goes through the `maintenance_tickets`/`capex_projects` **RPCs**,
/// not a direct table select: unlike the leasing aggregates, the read RPC
/// also validates that [propertyId] belongs to the workspace
/// (`private.leasing_property_in_workspace`) and returns `not_found`
/// otherwise, a check a raw `select` cannot express. A single-row read has no
/// such extra rule, so [getMaintenanceTicket]/[getCapexProject] use a direct
/// table select against the `select` RLS policy, exactly like every other
/// aggregate's `getById`.
abstract interface class MaintenanceCapexSupabaseGateway {
  String? get currentUserId;

  Future<List<Map<String, dynamic>>> getMaintenanceTicket({
    required String workspaceId,
    required String ticketId,
  });

  Future<List<Map<String, dynamic>>> getCapexProject({
    required String workspaceId,
    required String projectId,
  });

  Future<Object?> callRpc(String function, Map<String, Object?> parameters);
}

class SupabaseMaintenanceCapexGateway
    implements MaintenanceCapexSupabaseGateway {
  SupabaseMaintenanceCapexGateway(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> getMaintenanceTicket({
    required String workspaceId,
    required String ticketId,
  }) async {
    final rows = await _client
        .from('maintenance_tickets')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('id', ticketId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getCapexProject({
    required String workspaceId,
    required String projectId,
  }) async {
    final rows = await _client
        .from('capex_projects')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('id', projectId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) {
    return _client.rpc(function, params: parameters);
  }
}

/// Shared plumbing for the two aggregate adapters below.
///
/// One adapter class per aggregate rather than a single class implementing
/// all four ports, because the ports intentionally use the same natural
/// method names (`getById`, `create`, `update`, `transitionStatus`, `search`)
/// for two different entity types — one class cannot implement them all. They
/// still share one gateway, so a workspace still opens one client.
abstract class _SupabaseMaintenanceCapexBase {
  _SupabaseMaintenanceCapexBase(this._gateway);

  final MaintenanceCapexSupabaseGateway _gateway;

  Future<MaintenanceCapexRepositoryResult<T>> _getOne<T>({
    required Future<List<Map<String, dynamic>>> Function() load,
    required T Function(Map<String, dynamic> row) parse,
    required String workspaceId,
    required String Function(T value) workspaceOf,
    required String missingMessage,
    required String failureMessage,
  }) async {
    try {
      final rows = await load();
      if (rows.isEmpty) {
        return MaintenanceCapexRepositoryFailure<T>(
          kind: MaintenanceCapexRepositoryFailureKind.notFound,
          message: missingMessage,
        );
      }
      final value = parse(rows.first);
      if (workspaceOf(value) != workspaceId) {
        throw const FormatException('Workspace mismatch.');
      }
      return MaintenanceCapexRepositorySuccess<T>(value);
    } catch (_) {
      return MaintenanceCapexRepositoryFailure<T>(
        kind: MaintenanceCapexRepositoryFailureKind.infrastructureFailure,
        message: failureMessage,
      );
    }
  }

  /// The list RPCs return the same `{ok, entity, error}` envelope as the
  /// mutating RPCs — `entity` is a jsonb array rather than a single object.
  Future<MaintenanceCapexRepositoryResult<List<T>>> _executeQuery<T>({
    required String function,
    required Map<String, Object?> parameters,
    required T Function(Map<String, dynamic> row) parseRow,
    required String workspaceId,
    required String Function(T item) workspaceOf,
  }) async {
    try {
      final response = await _gateway.callRpc(function, parameters);
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        final raw = payload['entity'];
        if (raw is! List) {
          throw const FormatException('Expected a list entity.');
        }
        final items = raw
            .map((row) => parseRow(_asMap(row)))
            .toList(growable: false);
        if (items.any((item) => workspaceOf(item) != workspaceId)) {
          throw const FormatException('Workspace mismatch.');
        }
        return MaintenanceCapexRepositorySuccess<List<T>>(items);
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<List<T>>(_asMap(payload['error']), null);
    } catch (_) {
      return MaintenanceCapexRepositoryFailure<List<T>>(
        kind: MaintenanceCapexRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase maintenance_capex query failed.',
      );
    }
  }

  Future<MaintenanceCapexRepositoryResult<T>> _executeCommand<T>({
    required MaintenanceCapexCommandContext context,
    required String function,
    required Map<String, Object?> parameters,
    required T Function(Map<String, dynamic> entity) parseEntity,
    _ConflictEntity Function(Map<String, dynamic> entity)? parseConflictEntity,
  }) async {
    if (_gateway.currentUserId != context.actorId) {
      return MaintenanceCapexRepositoryFailure<T>(
        kind: MaintenanceCapexRepositoryFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }

    try {
      final response = await _gateway.callRpc(function, parameters);
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return MaintenanceCapexRepositorySuccess<T>(
          parseEntity(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<T>(_asMap(payload['error']), parseConflictEntity);
    } catch (_) {
      return MaintenanceCapexRepositoryFailure<T>(
        kind: MaintenanceCapexRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase maintenance_capex command failed.',
      );
    }
  }

  MaintenanceCapexRepositoryFailure<T> _mapRpcFailure<T>(
    Map<String, dynamic> error,
    _ConflictEntity Function(Map<String, dynamic> entity)? parseConflictEntity,
  ) {
    final code = _requiredString(error, 'code');
    final message = error['message'] is String
        ? error['message'] as String
        : 'Maintenance/CapEx command failed.';
    switch (code) {
      case 'not_found':
        return MaintenanceCapexRepositoryFailure<T>(
          kind: MaintenanceCapexRepositoryFailureKind.notFound,
          message: message,
        );
      case 'forbidden':
        return MaintenanceCapexRepositoryFailure<T>(
          kind: MaintenanceCapexRepositoryFailureKind.forbidden,
          message: message,
        );
      case 'validation_failed':
        return MaintenanceCapexRepositoryFailure<T>(
          kind: MaintenanceCapexRepositoryFailureKind.validationFailed,
          message: message,
        );
      case 'dependency_conflict':
        return MaintenanceCapexRepositoryFailure<T>(
          kind: MaintenanceCapexRepositoryFailureKind.dependencyConflict,
          message: message,
        );
      case 'mutation_conflict':
        return MaintenanceCapexRepositoryFailure<T>(
          kind: MaintenanceCapexRepositoryFailureKind.mutationConflict,
          message: message,
        );
      case 'in_progress':
        return MaintenanceCapexRepositoryFailure<T>(
          kind: MaintenanceCapexRepositoryFailureKind.mutationInProgress,
          message: message,
        );
      case 'version_conflict':
        if (parseConflictEntity == null) {
          throw const FormatException('Unexpected version conflict.');
        }
        final conflictEntity = parseConflictEntity(
          _asMap(error['current_entity']),
        );
        return MaintenanceCapexRepositoryFailure<T>(
          kind: MaintenanceCapexRepositoryFailureKind.versionConflict,
          message: message,
          versionConflict: MaintenanceCapexVersionConflict(
            expectedVersion: _requiredInt(error, 'expected_version'),
            actualVersion: _requiredInt(error, 'actual_version'),
            currentTicket: conflictEntity.currentTicket,
            currentProject: conflictEntity.currentProject,
          ),
        );
      case 'infrastructure_failure':
      default:
        return MaintenanceCapexRepositoryFailure<T>(
          kind: MaintenanceCapexRepositoryFailureKind.infrastructureFailure,
          message: 'Supabase maintenance_capex command failed.',
        );
    }
  }
}

/// Maintenance tickets (STM-006, AGG-008).
class SupabaseMaintenanceTicketRepositoryAdapter
    extends _SupabaseMaintenanceCapexBase
    implements MaintenanceTicketRepository, MaintenanceTicketSearchPort {
  SupabaseMaintenanceTicketRepositoryAdapter({required SupabaseClient client})
    : super(SupabaseMaintenanceCapexGateway(client));

  SupabaseMaintenanceTicketRepositoryAdapter.withGateway(super.gateway);

  // --- MaintenanceTicketSearchPort ---

  @override
  Future<MaintenanceCapexRepositoryResult<List<MaintenanceTicketSummaryDto>>>
  search(MaintenanceTicketListQuery query) {
    return _executeQuery<MaintenanceTicketSummaryDto>(
      function: 'maintenance_tickets',
      parameters: <String, Object?>{
        'p_workspace_id': query.workspaceId,
        'p_property_id': query.propertyId,
        'p_unit_id': query.unitId,
        'p_status': query.status == null
            ? null
            : _ticketStatusToWire[query.status!],
        'p_priority': query.priority == null
            ? null
            : _ticketPriorityToWire[query.priority!],
      },
      parseRow: _parseMaintenanceTicketSummary,
      workspaceId: query.workspaceId,
      workspaceOf: (item) => item.workspaceId,
    );
  }

  // --- MaintenanceTicketRepository ---

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> getById({
    required String workspaceId,
    required String ticketId,
  }) {
    return _getOne<MaintenanceTicketDto>(
      load: () => _gateway.getMaintenanceTicket(
        workspaceId: workspaceId,
        ticketId: ticketId,
      ),
      parse: _parseMaintenanceTicket,
      workspaceId: workspaceId,
      workspaceOf: (ticket) => ticket.workspaceId,
      missingMessage: 'Ticket not found.',
      failureMessage: 'Supabase maintenance ticket could not be loaded.',
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> create(
    CreateMaintenanceTicketCommand command,
  ) {
    final draft = command.draft;
    return _executeCommand<MaintenanceTicketDto>(
      context: command.context,
      function: 'create_maintenance_ticket',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_property_id': draft.propertyId,
        'p_title': draft.title,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_unit_id': draft.unitId,
        'p_description': draft.description,
        'p_category': draft.category,
        'p_priority': _ticketPriorityToWire[draft.priority],
        'p_due_at': _timestampToWire(draft.dueAt),
        'p_cost_estimate': draft.costEstimate,
        'p_currency_code': draft.currencyCode,
        'p_contractor_party_id': draft.contractorPartyId,
        'p_damage_location': draft.damageLocation,
        'p_insurance_case': draft.insuranceCase,
        'p_insurance_status': draft.insuranceStatus,
        'p_insurance_claim_number': draft.insuranceClaimNumber,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) => _requireWorkspace(
        _parseMaintenanceTicket(entity),
        command.context.workspaceId,
      ),
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> update(
    UpdateMaintenanceTicketCommand command,
  ) {
    final changes = command.changes;
    return _executeCommand<MaintenanceTicketDto>(
      context: command.context,
      function: 'update_maintenance_ticket',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_maintenance_ticket_id': command.ticketId,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        // Sparse patch: only supplied fields change server-side (coalesce
        // against the existing row) — see MaintenanceTicketUpdateDto.
        'p_title': changes.title,
        'p_description': changes.description,
        'p_category': changes.category,
        'p_priority': changes.priority == null
            ? null
            : _ticketPriorityToWire[changes.priority!],
        'p_due_at': _timestampToWire(changes.dueAt),
        'p_cost_estimate': changes.costEstimate,
        'p_cost_actual': changes.costActual,
        'p_currency_code': changes.currencyCode,
        'p_contractor_party_id': changes.contractorPartyId,
        'p_damage_location': changes.damageLocation,
        'p_insurance_case': changes.insuranceCase,
        'p_insurance_status': changes.insuranceStatus,
        'p_insurance_claim_number': changes.insuranceClaimNumber,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) => _requireWorkspace(
        _parseMaintenanceTicket(entity),
        command.context.workspaceId,
      ),
      parseConflictEntity: (entity) => (
        currentTicket: _requireWorkspace(
          _parseMaintenanceTicket(entity),
          command.context.workspaceId,
        ),
        currentProject: null,
      ),
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>>
  transitionStatus(TransitionMaintenanceTicketStatusCommand command) {
    return _executeCommand<MaintenanceTicketDto>(
      context: command.context,
      function: 'transition_maintenance_ticket_status',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_maintenance_ticket_id': command.ticketId,
        'p_expected_version': command.expectedVersion,
        'p_target_status': _ticketStatusToWire[command.targetStatus],
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_cost_actual': command.costActual,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) => _requireWorkspace(
        _parseMaintenanceTicket(entity),
        command.context.workspaceId,
      ),
      parseConflictEntity: (entity) => (
        currentTicket: _requireWorkspace(
          _parseMaintenanceTicket(entity),
          command.context.workspaceId,
        ),
        currentProject: null,
      ),
    );
  }
}

/// CapEx projects (STM-007, AGG-009).
class SupabaseCapexProjectRepositoryAdapter
    extends _SupabaseMaintenanceCapexBase
    implements CapexProjectRepository, CapexProjectSearchPort {
  SupabaseCapexProjectRepositoryAdapter({required SupabaseClient client})
    : super(SupabaseMaintenanceCapexGateway(client));

  SupabaseCapexProjectRepositoryAdapter.withGateway(super.gateway);

  // --- CapexProjectSearchPort ---

  @override
  Future<MaintenanceCapexRepositoryResult<List<CapexProjectSummaryDto>>>
  search(CapexProjectListQuery query) {
    return _executeQuery<CapexProjectSummaryDto>(
      function: 'capex_projects',
      parameters: <String, Object?>{
        'p_workspace_id': query.workspaceId,
        'p_property_id': query.propertyId,
        'p_status': query.status == null
            ? null
            : _projectStatusToWire[query.status!],
      },
      parseRow: _parseCapexProjectSummary,
      workspaceId: query.workspaceId,
      workspaceOf: (item) => item.workspaceId,
    );
  }

  // --- CapexProjectRepository ---

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> getById({
    required String workspaceId,
    required String projectId,
  }) {
    return _getOne<CapexProjectDto>(
      load: () => _gateway.getCapexProject(
        workspaceId: workspaceId,
        projectId: projectId,
      ),
      parse: _parseCapexProject,
      workspaceId: workspaceId,
      workspaceOf: (project) => project.workspaceId,
      missingMessage: 'Project not found.',
      failureMessage: 'Supabase CapEx project could not be loaded.',
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> create(
    CreateCapexProjectCommand command,
  ) {
    final draft = command.draft;
    return _executeCommand<CapexProjectDto>(
      context: command.context,
      function: 'create_capex_project',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_property_id': draft.propertyId,
        'p_project_code': draft.projectCode,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_category': draft.category,
        'p_measure': draft.measure,
        'p_start_date': _dateToWire(draft.startDate),
        'p_planned_end_date': _dateToWire(draft.plannedEndDate),
        'p_budget_amount': draft.budgetAmount,
        'p_forecast_amount': draft.forecastAmount,
        'p_currency_code': draft.currencyCode,
        'p_contractor_party_id': draft.contractorPartyId,
        'p_owner': draft.owner,
        'p_next_step': draft.nextStep,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) => _requireWorkspace(
        _parseCapexProject(entity),
        command.context.workspaceId,
      ),
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> update(
    UpdateCapexProjectCommand command,
  ) {
    final changes = command.changes;
    return _executeCommand<CapexProjectDto>(
      context: command.context,
      function: 'update_capex_project',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_capex_project_id': command.projectId,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        // Sparse patch: only supplied fields change server-side (coalesce
        // against the existing row) — see CapexProjectUpdateDto.
        'p_project_code': changes.projectCode,
        'p_category': changes.category,
        'p_measure': changes.measure,
        'p_start_date': _dateToWire(changes.startDate),
        'p_planned_end_date': _dateToWire(changes.plannedEndDate),
        'p_actual_end_date': _dateToWire(changes.actualEndDate),
        'p_budget_amount': changes.budgetAmount,
        'p_forecast_amount': changes.forecastAmount,
        'p_actual_amount': changes.actualAmount,
        'p_currency_code': changes.currencyCode,
        'p_contractor_party_id': changes.contractorPartyId,
        'p_owner': changes.owner,
        'p_next_step': changes.nextStep,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) => _requireWorkspace(
        _parseCapexProject(entity),
        command.context.workspaceId,
      ),
      parseConflictEntity: (entity) => (
        currentTicket: null,
        currentProject: _requireWorkspace(
          _parseCapexProject(entity),
          command.context.workspaceId,
        ),
      ),
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> transitionStatus(
    TransitionCapexProjectStatusCommand command,
  ) {
    return _executeCommand<CapexProjectDto>(
      context: command.context,
      function: 'transition_capex_project_status',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_capex_project_id': command.projectId,
        'p_expected_version': command.expectedVersion,
        'p_target_status': _projectStatusToWire[command.targetStatus],
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_actual_amount': command.actualAmount,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) => _requireWorkspace(
        _parseCapexProject(entity),
        command.context.workspaceId,
      ),
      parseConflictEntity: (entity) => (
        currentTicket: null,
        currentProject: _requireWorkspace(
          _parseCapexProject(entity),
          command.context.workspaceId,
        ),
      ),
    );
  }
}

typedef _ConflictEntity =
    ({MaintenanceTicketDto? currentTicket, CapexProjectDto? currentProject});

// --- Wire vocabulary ---------------------------------------------------
//
// Explicit maps rather than `.name`: `newTicket` has no snake_case
// counterpart at all (it exists only because `new` is a Dart reserved word),
// and `quoteRequested` is camelCase where the Postgres enum is snake_case.
// Deriving the wire value would silently produce a label the server rejects.

const Map<MaintenanceTicketStatus, String> _ticketStatusToWire =
    <MaintenanceTicketStatus, String>{
      MaintenanceTicketStatus.newTicket: 'new',
      MaintenanceTicketStatus.triage: 'triage',
      MaintenanceTicketStatus.quoteRequested: 'quote_requested',
      MaintenanceTicketStatus.commissioned: 'commissioned',
      MaintenanceTicketStatus.scheduled: 'scheduled',
      MaintenanceTicketStatus.inProgress: 'in_progress',
      MaintenanceTicketStatus.waiting: 'waiting',
      MaintenanceTicketStatus.resolved: 'resolved',
      MaintenanceTicketStatus.invoiced: 'invoiced',
      MaintenanceTicketStatus.archived: 'archived',
    };

const Map<String, MaintenanceTicketStatus> _ticketStatusFromWire =
    <String, MaintenanceTicketStatus>{
      'new': MaintenanceTicketStatus.newTicket,
      'triage': MaintenanceTicketStatus.triage,
      'quote_requested': MaintenanceTicketStatus.quoteRequested,
      'commissioned': MaintenanceTicketStatus.commissioned,
      'scheduled': MaintenanceTicketStatus.scheduled,
      'in_progress': MaintenanceTicketStatus.inProgress,
      'waiting': MaintenanceTicketStatus.waiting,
      'resolved': MaintenanceTicketStatus.resolved,
      'invoiced': MaintenanceTicketStatus.invoiced,
      'archived': MaintenanceTicketStatus.archived,
    };

const Map<MaintenanceTicketPriority, String> _ticketPriorityToWire =
    <MaintenanceTicketPriority, String>{
      MaintenanceTicketPriority.low: 'low',
      MaintenanceTicketPriority.normal: 'normal',
      MaintenanceTicketPriority.high: 'high',
      MaintenanceTicketPriority.urgent: 'urgent',
    };

const Map<String, MaintenanceTicketPriority> _ticketPriorityFromWire =
    <String, MaintenanceTicketPriority>{
      'low': MaintenanceTicketPriority.low,
      'normal': MaintenanceTicketPriority.normal,
      'high': MaintenanceTicketPriority.high,
      'urgent': MaintenanceTicketPriority.urgent,
    };

const Map<CapexProjectStatus, String> _projectStatusToWire =
    <CapexProjectStatus, String>{
      CapexProjectStatus.idea: 'idea',
      CapexProjectStatus.planned: 'planned',
      CapexProjectStatus.quoteRequested: 'quote_requested',
      CapexProjectStatus.approved: 'approved',
      CapexProjectStatus.inProgress: 'in_progress',
      CapexProjectStatus.completed: 'completed',
      CapexProjectStatus.invoiced: 'invoiced',
      CapexProjectStatus.archived: 'archived',
    };

const Map<String, CapexProjectStatus> _projectStatusFromWire =
    <String, CapexProjectStatus>{
      'idea': CapexProjectStatus.idea,
      'planned': CapexProjectStatus.planned,
      'quote_requested': CapexProjectStatus.quoteRequested,
      'approved': CapexProjectStatus.approved,
      'in_progress': CapexProjectStatus.inProgress,
      'completed': CapexProjectStatus.completed,
      'invoiced': CapexProjectStatus.invoiced,
      'archived': CapexProjectStatus.archived,
    };

// --- Parsing -------------------------------------------------------------

MaintenanceTicketSummaryDto _parseMaintenanceTicketSummary(
  Map<String, dynamic> row,
) => MaintenanceTicketSummaryDto(
  id: _requiredString(row, 'id'),
  workspaceId: _requiredString(row, 'workspace_id'),
  propertyId: _requiredString(row, 'property_id'),
  title: _requiredString(row, 'title'),
  status: _requiredEnum(row, 'status', _ticketStatusFromWire),
  priority: _requiredEnum(row, 'priority', _ticketPriorityFromWire),
  reportedAt: _requiredDate(row, 'reported_at'),
  version: _requiredInt(row, 'version'),
  unitId: _optionalString(row['unit_id']),
  dueAt: _optionalDate(row['due_at']),
  costEstimate: _optionalDouble(row['cost_estimate']),
  costActual: _optionalDouble(row['cost_actual']),
  currencyCode: _optionalString(row['currency_code']),
  contractorPartyId: _optionalString(row['contractor_party_id']),
);

MaintenanceTicketDto _parseMaintenanceTicket(Map<String, dynamic> row) =>
    MaintenanceTicketDto(
      id: _requiredString(row, 'id'),
      workspaceId: _requiredString(row, 'workspace_id'),
      propertyId: _requiredString(row, 'property_id'),
      title: _requiredString(row, 'title'),
      status: _requiredEnum(row, 'status', _ticketStatusFromWire),
      priority: _requiredEnum(row, 'priority', _ticketPriorityFromWire),
      reportedAt: _requiredDate(row, 'reported_at'),
      version: _requiredInt(row, 'version'),
      unitId: _optionalString(row['unit_id']),
      dueAt: _optionalDate(row['due_at']),
      costEstimate: _optionalDouble(row['cost_estimate']),
      costActual: _optionalDouble(row['cost_actual']),
      currencyCode: _optionalString(row['currency_code']),
      contractorPartyId: _optionalString(row['contractor_party_id']),
      category: _requiredString(row, 'category'),
      description: _optionalString(row['description']),
      resolvedAt: _optionalDate(row['resolved_at']),
      damageLocation: _optionalString(row['damage_location']),
      insuranceCase: _requiredBool(row, 'insurance_case'),
      insuranceStatus: _optionalString(row['insurance_status']),
      insuranceClaimNumber: _optionalString(row['insurance_claim_number']),
      createdAt: _requiredDate(row, 'created_at'),
      updatedAt: _requiredDate(row, 'updated_at'),
      createdBy: _requiredString(row, 'created_by'),
      updatedBy: _requiredString(row, 'updated_by'),
    );

CapexProjectSummaryDto _parseCapexProjectSummary(Map<String, dynamic> row) =>
    CapexProjectSummaryDto(
      id: _requiredString(row, 'id'),
      workspaceId: _requiredString(row, 'workspace_id'),
      propertyId: _requiredString(row, 'property_id'),
      projectCode: _requiredString(row, 'project_code'),
      status: _requiredEnum(row, 'status', _projectStatusFromWire),
      version: _requiredInt(row, 'version'),
      currencyCode: _optionalString(row['currency_code']),
      budgetAmount: _optionalDouble(row['budget_amount']),
      forecastAmount: _optionalDouble(row['forecast_amount']),
      actualAmount: _optionalDouble(row['actual_amount']),
      plannedEndDate: _optionalDate(row['planned_end_date']),
      contractorPartyId: _optionalString(row['contractor_party_id']),
    );

CapexProjectDto _parseCapexProject(Map<String, dynamic> row) =>
    CapexProjectDto(
      id: _requiredString(row, 'id'),
      workspaceId: _requiredString(row, 'workspace_id'),
      propertyId: _requiredString(row, 'property_id'),
      projectCode: _requiredString(row, 'project_code'),
      status: _requiredEnum(row, 'status', _projectStatusFromWire),
      version: _requiredInt(row, 'version'),
      currencyCode: _optionalString(row['currency_code']),
      budgetAmount: _optionalDouble(row['budget_amount']),
      forecastAmount: _optionalDouble(row['forecast_amount']),
      actualAmount: _optionalDouble(row['actual_amount']),
      plannedEndDate: _optionalDate(row['planned_end_date']),
      contractorPartyId: _optionalString(row['contractor_party_id']),
      category: _optionalString(row['category']),
      measure: _optionalString(row['measure']),
      startDate: _optionalDate(row['start_date']),
      actualEndDate: _optionalDate(row['actual_end_date']),
      owner: _optionalString(row['owner']),
      nextStep: _optionalString(row['next_step']),
      approvedBy: _optionalString(row['approved_by']),
      approvedAt: _optionalDate(row['approved_at']),
      createdAt: _requiredDate(row, 'created_at'),
      updatedAt: _requiredDate(row, 'updated_at'),
      createdBy: _requiredString(row, 'created_by'),
      updatedBy: _requiredString(row, 'updated_by'),
    );

// --- Primitives ------------------------------------------------------------

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw const FormatException('Expected an object.');
}

T _requireWorkspace<T>(T value, String workspaceId) {
  final actual = switch (value) {
    MaintenanceTicketDto ticket => ticket.workspaceId,
    CapexProjectDto project => project.workspaceId,
    _ => workspaceId,
  };
  if (actual != workspaceId) {
    throw const FormatException('Workspace mismatch.');
  }
  return value;
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('Missing string field: $key');
}

int _requiredInt(Map<String, dynamic> row, String key) {
  final value = _optionalInt(row[key]);
  if (value == null) {
    throw FormatException('Missing integer field: $key');
  }
  return value;
}

DateTime _requiredDate(Map<String, dynamic> row, String key) {
  final value = _optionalDate(row[key]);
  if (value == null) {
    throw FormatException('Missing date field: $key');
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> row, String key) {
  final value = _optionalBool(row[key]);
  if (value == null) {
    throw FormatException('Missing boolean field: $key');
  }
  return value;
}

T _requiredEnum<T>(Map<String, dynamic> row, String key, Map<String, T> wire) {
  final raw = row[key];
  final value = raw is String ? wire[raw] : null;
  if (value == null) {
    throw FormatException('Unknown value for $key: $raw');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value.isEmpty ? null : value;
  }
  throw const FormatException('Expected a string.');
}

int? _optionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  throw const FormatException('Expected an integer.');
}

/// Postgres `numeric` arrives as a String over PostgREST to avoid the
/// precision loss a double round trip would cause; both forms are accepted.
double? _optionalDouble(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  throw const FormatException('Expected a number.');
}

DateTime? _optionalDate(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  throw const FormatException('Expected a date.');
}

bool? _optionalBool(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw const FormatException('Expected a boolean.');
}

/// Postgres `date` columns (CapEx's `start_date`/`planned_end_date`/
/// `actual_end_date`) hold a calendar day, not an instant. The Y/M/D
/// components are taken exactly as the caller supplied them, with no UTC
/// conversion — normalising through UTC would silently shift the day for
/// anyone east of Greenwich.
String? _dateToWire(DateTime? value) {
  if (value == null) {
    return null;
  }
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Ticket `timestamptz` columns (`due_at`) hold an instant, unlike CapEx's
/// `date` columns — this preserves it via ISO 8601 rather than collapsing to
/// a calendar day.
String? _timestampToWire(DateTime? value) => value?.toIso8601String();
