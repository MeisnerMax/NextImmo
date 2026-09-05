import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/leasing_repository.dart';
import '../application/operations_signals_contract.dart';
import '../domain/lease_dto.dart';
import '../domain/leasing_case_dto.dart';
import '../domain/leasing_summary_dto.dart';
import '../domain/operations_signal_dto.dart';
import '../domain/rent_roll_dto.dart';
import '../domain/unit_dto.dart';

/// The narrow surface this adapter needs from Supabase, so the adapter itself
/// is testable without a live client (mirrors `PartySupabaseGateway`).
abstract interface class LeasingSupabaseGateway {
  String? get currentUserId;

  Future<List<Map<String, dynamic>>> listUnits({
    required String workspaceId,
    required String? propertyId,
    required String? status,
    required String? afterId,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> getUnit({
    required String workspaceId,
    required String unitId,
  });

  Future<List<Map<String, dynamic>>> listLeases({
    required String workspaceId,
    required String? propertyId,
    required String? unitId,
    required String? tenantPartyId,
    required String? status,
    required String? afterId,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> getLease({
    required String workspaceId,
    required String leaseId,
  });

  Future<List<Map<String, dynamic>>> listLeasingCases({
    required String workspaceId,
    required String? propertyId,
    required String? unitId,
    required String? status,
    required bool openOnly,
    required String? afterId,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> getLeasingCase({
    required String workspaceId,
    required String caseId,
  });

  Future<List<Map<String, dynamic>>> listRentRollSnapshots({
    required String workspaceId,
    required String propertyId,
    required String? afterId,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> getRentRollSnapshot({
    required String workspaceId,
    required String snapshotId,
  });

  Future<List<Map<String, dynamic>>> listRentRollSnapshotLines({
    required String workspaceId,
    required String snapshotId,
  });

  Future<Object?> callRpc(String function, Map<String, Object?> parameters);
}

class SupabaseLeasingGateway implements LeasingSupabaseGateway {
  SupabaseLeasingGateway(this._client);

  final SupabaseClient _client;

  static const String _unitSummaryColumns =
      'id, workspace_id, property_id, unit_code, status, version, unit_type, '
      'floor, area_sqm, rooms, vacancy_since';

  static const String _leaseSummaryColumns =
      'id, workspace_id, property_id, unit_id, lease_name, status, start_date, '
      'end_date, base_rent_monthly, currency_code, tenant_party_id, version';

  static const String _caseSummaryColumns =
      'id, workspace_id, property_id, unit_id, prospect_party_id, lease_id, '
      'case_name, status, source, opened_at, version';

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> listUnits({
    required String workspaceId,
    required String? propertyId,
    required String? status,
    required String? afterId,
    required int limit,
  }) async {
    var query = _client
        .from('units')
        .select(_unitSummaryColumns)
        .eq('workspace_id', workspaceId);
    if (propertyId != null) {
      query = query.eq('property_id', propertyId);
    }
    if (status != null) {
      query = query.eq('status', status);
    }
    if (afterId != null) {
      query = query.gt('id', afterId);
    }
    final rows = await query.order('id', ascending: true).limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getUnit({
    required String workspaceId,
    required String unitId,
  }) async {
    final rows = await _client
        .from('units')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('id', unitId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

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
    var query = _client
        .from('leases')
        .select(_leaseSummaryColumns)
        .eq('workspace_id', workspaceId);
    if (propertyId != null) {
      query = query.eq('property_id', propertyId);
    }
    if (unitId != null) {
      query = query.eq('unit_id', unitId);
    }
    if (tenantPartyId != null) {
      query = query.eq('tenant_party_id', tenantPartyId);
    }
    if (status != null) {
      query = query.eq('status', status);
    }
    if (afterId != null) {
      query = query.gt('id', afterId);
    }
    final rows = await query.order('id', ascending: true).limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getLease({
    required String workspaceId,
    required String leaseId,
  }) async {
    final rows = await _client
        .from('leases')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('id', leaseId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

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
    var query = _client
        .from('leasing_cases')
        .select(_caseSummaryColumns)
        .eq('workspace_id', workspaceId);
    if (propertyId != null) {
      query = query.eq('property_id', propertyId);
    }
    if (unitId != null) {
      query = query.eq('unit_id', unitId);
    }
    if (status != null) {
      query = query.eq('status', status);
    }
    if (openOnly) {
      // The pipeline board reads open cases only; terminal ones are history.
      query = query.not('status', 'in', '("completed","cancelled")');
    }
    if (afterId != null) {
      query = query.gt('id', afterId);
    }
    final rows = await query.order('id', ascending: true).limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getLeasingCase({
    required String workspaceId,
    required String caseId,
  }) async {
    final rows = await _client
        .from('leasing_cases')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('id', caseId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listRentRollSnapshots({
    required String workspaceId,
    required String propertyId,
    required String? afterId,
    required int limit,
  }) async {
    // Several snapshots may share an as_of_date (AGG-007 forbids changing one,
    // not taking another), so the keyset walks id after ordering by recency.
    var query = _client
        .from('rent_roll_snapshots')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('property_id', propertyId);
    if (afterId != null) {
      query = query.gt('id', afterId);
    }
    final rows = await query.order('id', ascending: true).limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getRentRollSnapshot({
    required String workspaceId,
    required String snapshotId,
  }) async {
    final rows = await _client
        .from('rent_roll_snapshots')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('id', snapshotId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listRentRollSnapshotLines({
    required String workspaceId,
    required String snapshotId,
  }) async {
    final rows = await _client
        .from('rent_roll_snapshot_lines')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('snapshot_id', snapshotId)
        .order('unit_code', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) {
    return _client.rpc(function, params: parameters);
  }
}

/// Shared plumbing for the four aggregate adapters below.
///
/// There is one adapter class per aggregate rather than a single class
/// implementing all seven ports, because the ports intentionally use the same
/// natural method names (`getById`, `create`, `update`, `transitionStatus`,
/// `search`) for four different entity types — one class cannot implement them
/// all. They still share one gateway, so a workspace still opens one client.
abstract class _SupabaseLeasingBase {
  _SupabaseLeasingBase(this._gateway);

  final LeasingSupabaseGateway _gateway;

  Future<LeasingRepositoryResult<T>> _getOne<T>({
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
        return LeasingRepositoryFailure<T>(
          kind: LeasingRepositoryFailureKind.notFound,
          message: missingMessage,
        );
      }
      final value = parse(rows.first);
      if (workspaceOf(value) != workspaceId) {
        throw const FormatException('Workspace mismatch.');
      }
      return LeasingRepositorySuccess<T>(value);
    } catch (_) {
      return LeasingRepositoryFailure<T>(
        kind: LeasingRepositoryFailureKind.infrastructureFailure,
        message: failureMessage,
      );
    }
  }

  LeasingPageResult<T> _page<T>({
    required List<Map<String, dynamic>> rows,
    required int limit,
    required T Function(Map<String, dynamic> row) parse,
    required String workspaceId,
    required String Function(T item) idOf,
    required String Function(T item) workspaceOf,
  }) {
    final hasNextPage = rows.length > limit;
    final pageRows = hasNextPage ? rows.take(limit) : rows;
    final items = pageRows.map(parse).toList(growable: false);
    if (items.any((item) => workspaceOf(item) != workspaceId)) {
      throw const FormatException('Workspace mismatch.');
    }
    return LeasingPageResult<T>(
      items: items,
      nextCursor: hasNextPage && items.isNotEmpty ? idOf(items.last) : null,
    );
  }

  Future<LeasingRepositoryResult<T>> _executeCommand<T>({
    required LeasingCommandContext context,
    required String function,
    required Map<String, Object?> parameters,
    required T Function(Map<String, dynamic> entity) parseEntity,
    _ConflictEntity Function(Map<String, dynamic> entity)? parseConflictEntity,
  }) async {
    if (_gateway.currentUserId != context.actorId) {
      return LeasingRepositoryFailure<T>(
        kind: LeasingRepositoryFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }

    try {
      final response = await _gateway.callRpc(function, parameters);
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return LeasingRepositorySuccess<T>(
          parseEntity(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<T>(_asMap(payload['error']), parseConflictEntity);
    } catch (_) {
      return LeasingRepositoryFailure<T>(
        kind: LeasingRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase leasing command failed.',
      );
    }
  }

  LeasingRepositoryFailure<T> _mapRpcFailure<T>(
    Map<String, dynamic> error,
    _ConflictEntity Function(Map<String, dynamic> entity)? parseConflictEntity,
  ) {
    final code = _requiredString(error, 'code');
    final message = error['message'] is String
        ? error['message'] as String
        : 'Leasing command failed.';
    switch (code) {
      case 'not_found':
        return LeasingRepositoryFailure<T>(
          kind: LeasingRepositoryFailureKind.notFound,
          message: message,
        );
      case 'forbidden':
        return LeasingRepositoryFailure<T>(
          kind: LeasingRepositoryFailureKind.forbidden,
          message: message,
        );
      case 'validation_failed':
        return LeasingRepositoryFailure<T>(
          kind: LeasingRepositoryFailureKind.validationFailed,
          message: message,
        );
      case 'dependency_conflict':
        return LeasingRepositoryFailure<T>(
          kind: LeasingRepositoryFailureKind.dependencyConflict,
          message: message,
        );
      case 'mutation_conflict':
        return LeasingRepositoryFailure<T>(
          kind: LeasingRepositoryFailureKind.mutationConflict,
          message: message,
        );
      case 'in_progress':
        return LeasingRepositoryFailure<T>(
          kind: LeasingRepositoryFailureKind.mutationInProgress,
          message: message,
        );
      case 'currency_mismatch':
        // Keep the currencies: they are the only thing that makes this
        // actionable, and collapsing them away would leave a UI able to say
        // only "that failed".
        return LeasingRepositoryFailure<T>(
          kind: LeasingRepositoryFailureKind.currencyMismatch,
          message: message,
          currencyMismatch: RentRollCurrencyMismatch(
            currencies: _stringList(error['currencies']),
          ),
        );
      case 'version_conflict':
        if (parseConflictEntity == null) {
          throw const FormatException('Unexpected version conflict.');
        }
        final conflictEntity = parseConflictEntity(
          _asMap(error['current_entity']),
        );
        return LeasingRepositoryFailure<T>(
          kind: LeasingRepositoryFailureKind.versionConflict,
          message: message,
          versionConflict: LeasingVersionConflict(
            expectedVersion: _requiredInt(error, 'expected_version'),
            actualVersion: _requiredInt(error, 'actual_version'),
            currentUnit: conflictEntity.currentUnit,
            currentLease: conflictEntity.currentLease,
            currentCase: conflictEntity.currentCase,
          ),
        );
      case 'infrastructure_failure':
      default:
        return LeasingRepositoryFailure<T>(
          kind: LeasingRepositoryFailureKind.infrastructureFailure,
          message: 'Supabase leasing command failed.',
        );
    }
  }
}

/// Units (STM-003, AGG-004).
class SupabaseUnitRepositoryAdapter extends _SupabaseLeasingBase
    implements UnitRepository, UnitSearchPort {
  SupabaseUnitRepositoryAdapter({required SupabaseClient client})
    : super(SupabaseLeasingGateway(client));

  SupabaseUnitRepositoryAdapter.withGateway(super.gateway);

  // --- UnitSearchPort ---

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<UnitSummaryDto>>> search(
    UnitListQuery query,
  ) async {
    try {
      final rows = await _gateway.listUnits(
        workspaceId: query.workspaceId,
        propertyId: query.propertyId,
        status: query.status == null ? null : _unitStatusToWire[query.status!],
        afterId: query.page.cursor,
        limit: query.page.limit + 1,
      );
      return LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
        _page<UnitSummaryDto>(
          rows: rows,
          limit: query.page.limit,
          parse: _parseUnitSummary,
          workspaceId: query.workspaceId,
          idOf: (item) => item.id,
          workspaceOf: (item) => item.workspaceId,
        ),
      );
    } catch (_) {
      return const LeasingRepositoryFailure<LeasingPageResult<UnitSummaryDto>>(
        kind: LeasingRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase units could not be loaded.',
      );
    }
  }

  // --- UnitRepository ---

  @override
  Future<LeasingRepositoryResult<UnitDto>> getById({
    required String workspaceId,
    required String unitId,
  }) async {
    return _getOne<UnitDto>(
      load: () => _gateway.getUnit(workspaceId: workspaceId, unitId: unitId),
      parse: _parseUnit,
      workspaceId: workspaceId,
      workspaceOf: (unit) => unit.workspaceId,
      missingMessage: 'Unit not found.',
      failureMessage: 'Supabase unit could not be loaded.',
    );
  }

  @override
  Future<LeasingRepositoryResult<UnitDto>> create(CreateUnitCommand command) {
    return _executeCommand<UnitDto>(
      context: command.context,
      function: 'create_unit',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_property_id': command.draft.propertyId,
        'p_unit_code': command.draft.unitCode,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_unit_type': command.draft.unitType,
        'p_floor': command.draft.floor,
        'p_area_sqm': command.draft.areaSqm,
        'p_rooms': command.draft.rooms,
        'p_bathrooms': command.draft.bathrooms,
        'p_target_rent_monthly': command.draft.targetRentMonthly,
        'p_market_rent_monthly': command.draft.marketRentMonthly,
        'p_currency_code': command.draft.currencyCode,
        'p_marketing_status': command.draft.marketingStatus,
        'p_renovation_status': command.draft.renovationStatus,
        'p_expected_ready_date': _dateToWire(command.draft.expectedReadyDate),
        'p_next_action': command.draft.nextAction,
        'p_notes': command.draft.notes,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) =>
          _requireWorkspace(_parseUnit(entity), command.context.workspaceId),
    );
  }

  @override
  Future<LeasingRepositoryResult<UnitDto>> update(UpdateUnitCommand command) {
    final changes = command.changes;
    return _executeCommand<UnitDto>(
      context: command.context,
      function: 'update_unit',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_unit_id': command.unitId,
        'p_expected_version': command.expectedVersion,
        // Whole-record shape: every key is sent, so a null clears the field.
        // The RPC's absent-means-unchanged path is deliberately not exercised —
        // optimistic concurrency already guarantees the caller holds the
        // current row, and one shape is easier to reason about than two.
        'p_changes': <String, Object?>{
          'unit_code': changes.unitCode,
          'unit_type': changes.unitType,
          'floor': changes.floor,
          'area_sqm': changes.areaSqm,
          'rooms': changes.rooms,
          'bathrooms': changes.bathrooms,
          'target_rent_monthly': changes.targetRentMonthly,
          'market_rent_monthly': changes.marketRentMonthly,
          'currency_code': changes.currencyCode,
          'vacancy_reason': changes.vacancyReason,
          'marketing_status': changes.marketingStatus,
          'renovation_status': changes.renovationStatus,
          'expected_ready_date': _dateToWire(changes.expectedReadyDate),
          'next_action': changes.nextAction,
          'notes': changes.notes,
        },
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) =>
          _requireWorkspace(_parseUnit(entity), command.context.workspaceId),
      parseConflictEntity: (entity) => (
        currentUnit: _requireWorkspace(
          _parseUnit(entity),
          command.context.workspaceId,
        ),
        currentLease: null,
        currentCase: null,
      ),
    );
  }

  @override
  Future<LeasingRepositoryResult<UnitDto>> transitionStatus(
    TransitionUnitStatusCommand command,
  ) {
    return _executeCommand<UnitDto>(
      context: command.context,
      function: 'transition_unit_status',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_unit_id': command.unitId,
        'p_expected_version': command.expectedVersion,
        'p_target_status': _unitStatusToWire[command.targetStatus],
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        // For a transition into `offline` this same value becomes the unit's
        // offline_reason server-side — see TransitionUnitStatusCommand.
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) =>
          _requireWorkspace(_parseUnit(entity), command.context.workspaceId),
      parseConflictEntity: (entity) => (
        currentUnit: _requireWorkspace(
          _parseUnit(entity),
          command.context.workspaceId,
        ),
        currentLease: null,
        currentCase: null,
      ),
    );
  }

}

/// Leases (STM-005, AGG-006). OPN-DOM-001: a unit may hold several
/// concurrently effective leases, so every read here returns a list.
class SupabaseLeaseRepositoryAdapter extends _SupabaseLeasingBase
    implements LeaseRepository, LeaseSearchPort {
  SupabaseLeaseRepositoryAdapter({required SupabaseClient client})
    : super(SupabaseLeasingGateway(client));

  SupabaseLeaseRepositoryAdapter.withGateway(super.gateway);

  // --- LeaseSearchPort ---

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeaseSummaryDto>>> search(
    LeaseListQuery query,
  ) async {
    try {
      final status = query.effectiveOnly
          ? _leaseStatusToWire[LeaseStatus.active]
          : (query.status == null ? null : _leaseStatusToWire[query.status!]);
      final rows = await _gateway.listLeases(
        workspaceId: query.workspaceId,
        propertyId: query.propertyId,
        unitId: query.unitId,
        tenantPartyId: query.tenantPartyId,
        status: status,
        afterId: query.page.cursor,
        limit: query.page.limit + 1,
      );
      return LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
        _page<LeaseSummaryDto>(
          rows: rows,
          limit: query.page.limit,
          parse: _parseLeaseSummary,
          workspaceId: query.workspaceId,
          idOf: (item) => item.id,
          workspaceOf: (item) => item.workspaceId,
        ),
      );
    } catch (_) {
      return const LeasingRepositoryFailure<LeasingPageResult<LeaseSummaryDto>>(
        kind: LeasingRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase leases could not be loaded.',
      );
    }
  }

  // --- LeaseRepository ---

  @override
  Future<LeasingRepositoryResult<LeaseDto>> getById({
    required String workspaceId,
    required String leaseId,
  }) async {
    return _getOne<LeaseDto>(
      load: () => _gateway.getLease(workspaceId: workspaceId, leaseId: leaseId),
      parse: _parseLease,
      workspaceId: workspaceId,
      workspaceOf: (lease) => lease.workspaceId,
      missingMessage: 'Lease not found.',
      failureMessage: 'Supabase lease could not be loaded.',
    );
  }

  @override
  Future<LeasingRepositoryResult<LeaseDto>> create(CreateLeaseCommand command) {
    final draft = command.draft;
    return _executeCommand<LeaseDto>(
      context: command.context,
      function: 'create_lease',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_unit_id': draft.unitId,
        'p_lease_name': draft.leaseName,
        'p_start_date': _dateToWire(draft.startDate),
        'p_base_rent_monthly': draft.baseRentMonthly,
        'p_currency_code': draft.currencyCode,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_tenant_party_id': draft.tenantPartyId,
        'p_end_date': _dateToWire(draft.endDate),
        'p_move_in_date': _dateToWire(draft.moveInDate),
        'p_signed_date': _dateToWire(draft.signedDate),
        'p_ancillary_charges_monthly': draft.ancillaryChargesMonthly,
        'p_parking_other_charges_monthly': draft.parkingOtherChargesMonthly,
        'p_security_deposit': draft.securityDeposit,
        'p_payment_day_of_month': draft.paymentDayOfMonth,
        'p_billing_frequency': _billingFrequencyToWire[draft.billingFrequency],
        'p_rent_free_period_months': draft.rentFreePeriodMonths,
        'p_notes': draft.notes,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) =>
          _requireWorkspace(_parseLease(entity), command.context.workspaceId),
    );
  }

  @override
  Future<LeasingRepositoryResult<LeaseDto>> update(UpdateLeaseCommand command) {
    final changes = command.changes;
    return _executeCommand<LeaseDto>(
      context: command.context,
      function: 'update_lease',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_lease_id': command.leaseId,
        'p_expected_version': command.expectedVersion,
        'p_changes': <String, Object?>{
          'lease_name': changes.leaseName,
          'start_date': _dateToWire(changes.startDate),
          'end_date': _dateToWire(changes.endDate),
          'move_in_date': _dateToWire(changes.moveInDate),
          'signed_date': _dateToWire(changes.signedDate),
          'notice_date': _dateToWire(changes.noticeDate),
          'renewal_option_date': _dateToWire(changes.renewalOptionDate),
          'break_option_date': _dateToWire(changes.breakOptionDate),
          'base_rent_monthly': changes.baseRentMonthly,
          'ancillary_charges_monthly': changes.ancillaryChargesMonthly,
          'parking_other_charges_monthly': changes.parkingOtherChargesMonthly,
          'security_deposit': changes.securityDeposit,
          'payment_day_of_month': changes.paymentDayOfMonth,
          'billing_frequency':
              _billingFrequencyToWire[changes.billingFrequency],
          'rent_free_period_months': changes.rentFreePeriodMonths,
          'tenant_party_id': changes.tenantPartyId,
          'notes': changes.notes,
        },
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) =>
          _requireWorkspace(_parseLease(entity), command.context.workspaceId),
      parseConflictEntity: (entity) => (
        currentUnit: null,
        currentLease: _requireWorkspace(
          _parseLease(entity),
          command.context.workspaceId,
        ),
        currentCase: null,
      ),
    );
  }

  @override
  Future<LeasingRepositoryResult<LeaseDto>> transitionStatus(
    TransitionLeaseStatusCommand command,
  ) {
    return _executeCommand<LeaseDto>(
      context: command.context,
      function: 'transition_lease_status',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_lease_id': command.leaseId,
        'p_expected_version': command.expectedVersion,
        'p_target_status': _leaseStatusToWire[command.targetStatus],
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_move_out_date': _dateToWire(command.moveOutDate),
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) =>
          _requireWorkspace(_parseLease(entity), command.context.workspaceId),
      parseConflictEntity: (entity) => (
        currentUnit: null,
        currentLease: _requireWorkspace(
          _parseLease(entity),
          command.context.workspaceId,
        ),
        currentCase: null,
      ),
    );
  }

}

/// The STM-004 letting pipeline.
class SupabaseLeasingCaseRepositoryAdapter extends _SupabaseLeasingBase
    implements LeasingCaseRepository, LeasingCaseSearchPort {
  SupabaseLeasingCaseRepositoryAdapter({required SupabaseClient client})
    : super(SupabaseLeasingGateway(client));

  SupabaseLeasingCaseRepositoryAdapter.withGateway(super.gateway);

  // --- LeasingCaseSearchPort ---

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeasingCaseSummaryDto>>>
  search(LeasingCaseListQuery query) async {
    try {
      final rows = await _gateway.listLeasingCases(
        workspaceId: query.workspaceId,
        propertyId: query.propertyId,
        unitId: query.unitId,
        status: query.status == null ? null : _caseStatusToWire[query.status!],
        openOnly: query.openOnly,
        afterId: query.page.cursor,
        limit: query.page.limit + 1,
      );
      return LeasingRepositorySuccess<LeasingPageResult<LeasingCaseSummaryDto>>(
        _page<LeasingCaseSummaryDto>(
          rows: rows,
          limit: query.page.limit,
          parse: _parseLeasingCaseSummary,
          workspaceId: query.workspaceId,
          idOf: (item) => item.id,
          workspaceOf: (item) => item.workspaceId,
        ),
      );
    } catch (_) {
      return const LeasingRepositoryFailure<
        LeasingPageResult<LeasingCaseSummaryDto>
      >(
        kind: LeasingRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase leasing cases could not be loaded.',
      );
    }
  }

  // --- LeasingCaseRepository ---

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> getById({
    required String workspaceId,
    required String caseId,
  }) async {
    return _getOne<LeasingCaseDto>(
      load: () =>
          _gateway.getLeasingCase(workspaceId: workspaceId, caseId: caseId),
      parse: _parseLeasingCase,
      workspaceId: workspaceId,
      workspaceOf: (leasingCase) => leasingCase.workspaceId,
      missingMessage: 'Leasing case not found.',
      failureMessage: 'Supabase leasing case could not be loaded.',
    );
  }

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> create(
    CreateLeasingCaseCommand command,
  ) {
    final draft = command.draft;
    return _executeCommand<LeasingCaseDto>(
      context: command.context,
      function: 'create_leasing_case',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_property_id': draft.propertyId,
        'p_case_name': draft.caseName,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_unit_id': draft.unitId,
        'p_prospect_party_id': draft.prospectPartyId,
        'p_source': _caseSourceToWire[draft.source],
        'p_notes': draft.notes,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) => _requireWorkspace(
        _parseLeasingCase(entity),
        command.context.workspaceId,
      ),
    );
  }

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> update(
    UpdateLeasingCaseCommand command,
  ) {
    final changes = command.changes;
    return _executeCommand<LeasingCaseDto>(
      context: command.context,
      function: 'update_leasing_case',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_case_id': command.caseId,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        // Genuinely sparse here: the RPC treats null as "leave alone" for these
        // arguments, which is what LeasingCaseUpdateDto documents. Clearing a
        // unit or prospect back to null is not offered because it would walk
        // the row into a state its own constraint forbids.
        'p_case_name': changes.caseName,
        'p_unit_id': changes.unitId,
        'p_prospect_party_id': changes.prospectPartyId,
        'p_source': changes.source == null
            ? null
            : _caseSourceToWire[changes.source!],
        'p_notes': changes.notes,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) => _requireWorkspace(
        _parseLeasingCase(entity),
        command.context.workspaceId,
      ),
      parseConflictEntity: (entity) => (
        currentUnit: null,
        currentLease: null,
        currentCase: _requireWorkspace(
          _parseLeasingCase(entity),
          command.context.workspaceId,
        ),
      ),
    );
  }

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> transitionStatus(
    TransitionLeasingCaseStatusCommand command,
  ) {
    return _executeCommand<LeasingCaseDto>(
      context: command.context,
      function: 'transition_leasing_case_status',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_case_id': command.caseId,
        'p_expected_version': command.expectedVersion,
        'p_target_status': _caseStatusToWire[command.targetStatus],
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_lease_id': command.leaseId,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) => _requireWorkspace(
        _parseLeasingCase(entity),
        command.context.workspaceId,
      ),
      parseConflictEntity: (entity) => (
        currentUnit: null,
        currentLease: null,
        currentCase: _requireWorkspace(
          _parseLeasingCase(entity),
          command.context.workspaceId,
        ),
      ),
    );
  }

}

/// Rent-roll snapshots (AGG-007). Create and read only — a frozen snapshot has
/// no update, transition or delete path, so this adapter deliberately offers
/// none either.
class SupabaseRentRollAdapter extends _SupabaseLeasingBase
    implements RentRollPort {
  SupabaseRentRollAdapter({required SupabaseClient client})
    : super(SupabaseLeasingGateway(client));

  SupabaseRentRollAdapter.withGateway(super.gateway);

  // --- RentRollPort ---

  /// P2-D05b. One server-side read, computed from the same helpers that build a
  /// snapshot — the client does no arithmetic, which is the entire point.
  @override
  Future<LeasingRepositoryResult<RentRollLiveDto>> readLive({
    required String workspaceId,
    required String propertyId,
    required DateTime asOfDate,
  }) async {
    try {
      final response = await _gateway.callRpc('rent_roll_live', <String, Object?>{
        'p_workspace_id': workspaceId,
        'p_property_id': propertyId,
        'p_as_of_date': _dateToWire(asOfDate),
      });
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return LeasingRepositorySuccess<RentRollLiveDto>(
          _requireWorkspace(
            _parseRentRollLive(_asMap(payload['entity'])),
            workspaceId,
          ),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<RentRollLiveDto>(_asMap(payload['error']), null);
    } catch (_) {
      return const LeasingRepositoryFailure<RentRollLiveDto>(
        kind: LeasingRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase live rent roll could not be loaded.',
      );
    }
  }

  @override
  Future<LeasingRepositoryResult<RentRollSnapshotDto>> getSnapshot({
    required String workspaceId,
    required String snapshotId,
  }) async {
    try {
      final rows = await _gateway.getRentRollSnapshot(
        workspaceId: workspaceId,
        snapshotId: snapshotId,
      );
      if (rows.isEmpty) {
        return const LeasingRepositoryFailure<RentRollSnapshotDto>(
          kind: LeasingRepositoryFailureKind.notFound,
          message: 'Rent roll snapshot not found.',
        );
      }
      final lineRows = await _gateway.listRentRollSnapshotLines(
        workspaceId: workspaceId,
        snapshotId: snapshotId,
      );
      final snapshot = _parseRentRollSnapshot(
        rows.first,
        lineRows.map(_parseRentRollLine).toList(growable: false),
      );
      return LeasingRepositorySuccess<RentRollSnapshotDto>(
        _requireWorkspace(snapshot, workspaceId),
      );
    } catch (_) {
      return const LeasingRepositoryFailure<RentRollSnapshotDto>(
        kind: LeasingRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase rent roll snapshot could not be loaded.',
      );
    }
  }

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<RentRollSnapshotDto>>>
  listSnapshots(RentRollSnapshotListQuery query) async {
    try {
      final rows = await _gateway.listRentRollSnapshots(
        workspaceId: query.workspaceId,
        propertyId: query.propertyId,
        afterId: query.page.cursor,
        limit: query.page.limit + 1,
      );
      return LeasingRepositorySuccess<LeasingPageResult<RentRollSnapshotDto>>(
        _page<RentRollSnapshotDto>(
          rows: rows,
          limit: query.page.limit,
          // Header-only projection: lines stay empty until getSnapshot.
          parse: (row) => _parseRentRollSnapshot(row, const []),
          workspaceId: query.workspaceId,
          idOf: (item) => item.id,
          workspaceOf: (item) => item.workspaceId,
        ),
      );
    } catch (_) {
      return const LeasingRepositoryFailure<
        LeasingPageResult<RentRollSnapshotDto>
      >(
        kind: LeasingRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase rent roll snapshots could not be loaded.',
      );
    }
  }

  @override
  Future<LeasingRepositoryResult<RentRollSnapshotDto>> createSnapshot(
    CreateRentRollSnapshotCommand command,
  ) {
    return _executeCommand<RentRollSnapshotDto>(
      context: command.context,
      function: 'create_rent_roll_snapshot',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_property_id': command.propertyId,
        'p_as_of_date': _dateToWire(command.asOfDate),
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_currency_code': command.currencyCode,
        'p_reason': command.context.reason,
      },
      // The RPC returns the whole frozen document, lines embedded, so a replay
      // hands back exactly what the first call did.
      parseEntity: (entity) => _requireWorkspace(
        _parseRentRollSnapshot(entity, _parseEmbeddedLines(entity)),
        command.context.workspaceId,
      ),
    );
  }

}

/// P2-D05a. Not a fifth `_SupabaseLeasingBase` implementer: it answers
/// [OperationsSignalsResult], not [LeasingRepositoryResult] — a signal has no
/// create/update/transition triple, only "read the computed list" and
/// "acknowledge one entry" (see `operations_signals_contract.dart`'s header).
/// It still shares the one [LeasingSupabaseGateway] the other four adapters
/// use, so a workspace still opens one client.
/// LEASING-SUMMARY-01. One RPC, no arithmetic here.
///
/// Every figure is the server's, including the expiry windows and their
/// labels. The parser below does not sum, divide or fill in: a missing area is
/// left missing and reported through the coverage counter, and there is no
/// path in this class that could produce a cross-currency total.
class SupabasePropertyLeasingSummaryAdapter extends _SupabaseLeasingBase
    implements PropertyLeasingSummaryPort {
  SupabasePropertyLeasingSummaryAdapter({required SupabaseClient client})
    : super(SupabaseLeasingGateway(client));

  SupabasePropertyLeasingSummaryAdapter.withGateway(super.gateway);

  @override
  Future<LeasingRepositoryResult<PropertyLeasingSummaryDto>> read({
    required String workspaceId,
    required String propertyId,
  }) async {
    try {
      final response = await _gateway.callRpc(
        'property_leasing_summary',
        <String, Object?>{
          'p_workspace_id': workspaceId,
          'p_property_id': propertyId,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return LeasingRepositorySuccess<PropertyLeasingSummaryDto>(
          _parseLeasingSummary(_asMap(payload['summary'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<PropertyLeasingSummaryDto>(
        _asMap(payload['error']),
        null,
      );
    } catch (_) {
      return const LeasingRepositoryFailure<PropertyLeasingSummaryDto>(
        kind: LeasingRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase leasing summary could not be loaded.',
      );
    }
  }
}

class SupabaseOperationsSignalsAdapter implements OperationsSignalsPort {
  SupabaseOperationsSignalsAdapter({required SupabaseClient client})
    : _gateway = SupabaseLeasingGateway(client);

  SupabaseOperationsSignalsAdapter.withGateway(this._gateway);

  final LeasingSupabaseGateway _gateway;

  @override
  Future<OperationsSignalsResult<List<OperationsSignalDto>>> list(
    OperationsSignalsQuery query,
  ) async {
    try {
      final response = await _gateway.callRpc('operations_signals', <String, Object?>{
        'p_workspace_id': query.workspaceId,
        'p_property_id': query.propertyId,
      });
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        final entity = _asMap(payload['entity']);
        final rawSignals = entity['signals'];
        if (rawSignals is! List) {
          throw const FormatException('Missing signals array.');
        }
        final signals = rawSignals
            .map((row) => _parseSignal(_asMap(row), query.propertyId))
            .toList(growable: false);
        return OperationsSignalsSuccess<List<OperationsSignalDto>>(signals);
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<List<OperationsSignalDto>>(_asMap(payload['error']));
    } catch (_) {
      return const OperationsSignalsFailure<List<OperationsSignalDto>>(
        kind: OperationsSignalsFailureKind.infrastructureFailure,
        message: 'Supabase operations signals could not be loaded.',
      );
    }
  }

  @override
  Future<OperationsSignalsResult<OperationsSignalStateDto>> updateStatus(
    UpdateOperationsSignalStatusCommand command,
  ) async {
    if (_gateway.currentUserId != command.context.actorId) {
      return const OperationsSignalsFailure<OperationsSignalStateDto>(
        kind: OperationsSignalsFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }

    try {
      final response = await _gateway.callRpc(
        'update_operations_signal_status',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_property_id': command.propertyId,
          'p_signal_type': command.signalType,
          'p_status': command.status,
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_unit_id': command.unitId,
          'p_lease_id': command.leaseId,
          'p_tenant_party_id': command.tenantPartyId,
          'p_expected_version': command.expectedVersion,
          'p_reason': command.context.reason,
          'p_resolution_note': command.resolutionNote,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return OperationsSignalsSuccess<OperationsSignalStateDto>(
          _parseSignalState(_asMap(payload['entity']), command.context.workspaceId),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<OperationsSignalStateDto>(_asMap(payload['error']));
    } catch (_) {
      return const OperationsSignalsFailure<OperationsSignalStateDto>(
        kind: OperationsSignalsFailureKind.infrastructureFailure,
        message: 'Supabase operations signal acknowledgement failed.',
      );
    }
  }

  OperationsSignalsFailure<T> _mapFailure<T>(Map<String, dynamic> error) {
    final code = _requiredString(error, 'code');
    final message = error['message'] is String
        ? error['message'] as String
        : 'Operations signal command failed.';
    switch (code) {
      case 'not_found':
        return OperationsSignalsFailure<T>(
          kind: OperationsSignalsFailureKind.notFound,
          message: message,
        );
      case 'forbidden':
        return OperationsSignalsFailure<T>(
          kind: OperationsSignalsFailureKind.forbidden,
          message: message,
        );
      case 'validation_failed':
        return OperationsSignalsFailure<T>(
          kind: OperationsSignalsFailureKind.validationFailed,
          message: message,
        );
      case 'mutation_conflict':
        return OperationsSignalsFailure<T>(
          kind: OperationsSignalsFailureKind.mutationConflict,
          message: message,
        );
      case 'in_progress':
        return OperationsSignalsFailure<T>(
          kind: OperationsSignalsFailureKind.mutationInProgress,
          message: message,
        );
      case 'version_conflict':
        final currentEntityRaw = error['current_entity'];
        return OperationsSignalsFailure<T>(
          kind: OperationsSignalsFailureKind.versionConflict,
          message: message,
          versionConflict: OperationsSignalVersionConflict(
            expectedVersion: _optionalInt(error['expected_version']),
            actualVersion: _optionalInt(error['actual_version']),
            currentState: currentEntityRaw == null
                ? null
                : _parseSignalState(
                    _asMap(currentEntityRaw),
                    _requiredString(_asMap(currentEntityRaw), 'workspace_id'),
                  ),
          ),
        );
      case 'infrastructure_failure':
      default:
        return OperationsSignalsFailure<T>(
          kind: OperationsSignalsFailureKind.infrastructureFailure,
          message: 'Operations signal command failed.',
        );
    }
  }
}

OperationsSignalDto _parseSignal(Map<String, dynamic> row, String propertyId) {
  final signal = OperationsSignalDto(
    signalKey: _requiredString(row, 'signal_key'),
    type: _requiredString(row, 'type'),
    severity: _requiredString(row, 'severity'),
    message: _requiredString(row, 'message'),
    recommendedAction: _requiredString(row, 'recommended_action'),
    propertyId: _requiredString(row, 'property_id'),
    unitId: _optionalString(row['unit_id']),
    leaseId: _optionalString(row['lease_id']),
    tenantPartyId: _optionalString(row['tenant_party_id']),
    status: _requiredString(row, 'status'),
    resolutionNote: _optionalString(row['resolution_note']),
    statusVersion: _optionalInt(row['status_version']),
    statusUpdatedAt: _optionalDate(row['status_updated_at']),
  );
  if (signal.propertyId != propertyId) {
    throw const FormatException('Workspace mismatch.');
  }
  return signal;
}

OperationsSignalStateDto _parseSignalState(
  Map<String, dynamic> row,
  String workspaceId,
) {
  final state = OperationsSignalStateDto(
    id: _requiredString(row, 'id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    propertyId: _requiredString(row, 'property_id'),
    signalType: _requiredString(row, 'signal_type'),
    unitId: _optionalString(row['unit_id']),
    leaseId: _optionalString(row['lease_id']),
    tenantPartyId: _optionalString(row['tenant_party_id']),
    signalKey: _requiredString(row, 'signal_key'),
    status: _requiredString(row, 'status'),
    resolutionNote: _optionalString(row['resolution_note']),
    version: _requiredInt(row, 'version'),
    createdAt: _requiredDate(row, 'created_at'),
    updatedAt: _requiredDate(row, 'updated_at'),
    createdBy: _requiredString(row, 'created_by'),
    updatedBy: _requiredString(row, 'updated_by'),
  );
  if (state.workspaceId != workspaceId) {
    throw const FormatException('Workspace mismatch.');
  }
  return state;
}

/// Guards against a row from another workspace ever reaching a caller, even if
/// RLS were somehow misconfigured — the same belt-and-braces check the party
/// and document adapters make.
T _requireWorkspace<T>(T value, String workspaceId) {
  final actual = switch (value) {
    UnitDto unit => unit.workspaceId,
    LeaseDto lease => lease.workspaceId,
    LeasingCaseDto leasingCase => leasingCase.workspaceId,
    RentRollSnapshotDto snapshot => snapshot.workspaceId,
    RentRollLiveDto live => live.workspaceId,
    _ => workspaceId,
  };
  if (actual != workspaceId) {
    throw const FormatException('Workspace mismatch.');
  }
  return value;
}

typedef _ConflictEntity =
    ({UnitDto? currentUnit, LeaseDto? currentLease, LeasingCaseDto? currentCase});

// --- Wire vocabulary -------------------------------------------------------
//
// Explicit maps rather than `.name`: several Dart labels are camelCase where the
// Postgres enum is snake_case (tenantSigned/tenant_signed,
// documentsPending/documents_pending, contractDraft/contract_draft,
// walkIn/walk_in). Deriving the wire value would silently produce a label the
// server rejects.

const Map<UnitStatus, String> _unitStatusToWire = <UnitStatus, String>{
  UnitStatus.vacant: 'vacant',
  UnitStatus.occupied: 'occupied',
  UnitStatus.offline: 'offline',
};

const Map<String, UnitStatus> _unitStatusFromWire = <String, UnitStatus>{
  'vacant': UnitStatus.vacant,
  'occupied': UnitStatus.occupied,
  'offline': UnitStatus.offline,
};

const Map<LeaseStatus, String> _leaseStatusToWire = <LeaseStatus, String>{
  LeaseStatus.draft: 'draft',
  LeaseStatus.reviewed: 'reviewed',
  LeaseStatus.sent: 'sent',
  LeaseStatus.tenantSigned: 'tenant_signed',
  LeaseStatus.landlordSigned: 'landlord_signed',
  LeaseStatus.active: 'active',
  LeaseStatus.ended: 'ended',
  LeaseStatus.cancelled: 'cancelled',
};

const Map<String, LeaseStatus> _leaseStatusFromWire = <String, LeaseStatus>{
  'draft': LeaseStatus.draft,
  'reviewed': LeaseStatus.reviewed,
  'sent': LeaseStatus.sent,
  'tenant_signed': LeaseStatus.tenantSigned,
  'landlord_signed': LeaseStatus.landlordSigned,
  'active': LeaseStatus.active,
  'ended': LeaseStatus.ended,
  'cancelled': LeaseStatus.cancelled,
};

const Map<LeaseBillingFrequency, String> _billingFrequencyToWire =
    <LeaseBillingFrequency, String>{
      LeaseBillingFrequency.monthly: 'monthly',
      LeaseBillingFrequency.quarterly: 'quarterly',
      LeaseBillingFrequency.semiannual: 'semiannual',
      LeaseBillingFrequency.annual: 'annual',
    };

const Map<String, LeaseBillingFrequency> _billingFrequencyFromWire =
    <String, LeaseBillingFrequency>{
      'monthly': LeaseBillingFrequency.monthly,
      'quarterly': LeaseBillingFrequency.quarterly,
      'semiannual': LeaseBillingFrequency.semiannual,
      'annual': LeaseBillingFrequency.annual,
    };

const Map<LeasingCaseStatus, String> _caseStatusToWire =
    <LeasingCaseStatus, String>{
      LeasingCaseStatus.inquiry: 'inquiry',
      LeasingCaseStatus.contact: 'contact',
      LeasingCaseStatus.viewing: 'viewing',
      LeasingCaseStatus.documentsPending: 'documents_pending',
      LeasingCaseStatus.screening: 'screening',
      LeasingCaseStatus.offer: 'offer',
      LeasingCaseStatus.contractDraft: 'contract_draft',
      LeasingCaseStatus.signed: 'signed',
      LeasingCaseStatus.handover: 'handover',
      LeasingCaseStatus.completed: 'completed',
      LeasingCaseStatus.cancelled: 'cancelled',
    };

const Map<String, LeasingCaseStatus> _caseStatusFromWire =
    <String, LeasingCaseStatus>{
      'inquiry': LeasingCaseStatus.inquiry,
      'contact': LeasingCaseStatus.contact,
      'viewing': LeasingCaseStatus.viewing,
      'documents_pending': LeasingCaseStatus.documentsPending,
      'screening': LeasingCaseStatus.screening,
      'offer': LeasingCaseStatus.offer,
      'contract_draft': LeasingCaseStatus.contractDraft,
      'signed': LeasingCaseStatus.signed,
      'handover': LeasingCaseStatus.handover,
      'completed': LeasingCaseStatus.completed,
      'cancelled': LeasingCaseStatus.cancelled,
    };

const Map<LeasingCaseSource, String> _caseSourceToWire =
    <LeasingCaseSource, String>{
      LeasingCaseSource.portal: 'portal',
      LeasingCaseSource.email: 'email',
      LeasingCaseSource.phone: 'phone',
      LeasingCaseSource.walkIn: 'walk_in',
      LeasingCaseSource.referral: 'referral',
      LeasingCaseSource.other: 'other',
    };

const Map<String, LeasingCaseSource> _caseSourceFromWire =
    <String, LeasingCaseSource>{
      'portal': LeasingCaseSource.portal,
      'email': LeasingCaseSource.email,
      'phone': LeasingCaseSource.phone,
      'walk_in': LeasingCaseSource.walkIn,
      'referral': LeasingCaseSource.referral,
      'other': LeasingCaseSource.other,
    };

// --- Parsing ---------------------------------------------------------------

UnitSummaryDto _parseUnitSummary(Map<String, dynamic> row) => UnitSummaryDto(
  id: _requiredString(row, 'id'),
  workspaceId: _requiredString(row, 'workspace_id'),
  propertyId: _requiredString(row, 'property_id'),
  unitCode: _requiredString(row, 'unit_code'),
  status: _requiredEnum(row, 'status', _unitStatusFromWire),
  version: _requiredInt(row, 'version'),
  unitType: _optionalString(row['unit_type']),
  floor: _optionalString(row['floor']),
  areaSqm: _optionalDouble(row['area_sqm']),
  rooms: _optionalDouble(row['rooms']),
  vacancySince: _optionalDate(row['vacancy_since']),
);

UnitDto _parseUnit(Map<String, dynamic> row) => UnitDto(
  id: _requiredString(row, 'id'),
  workspaceId: _requiredString(row, 'workspace_id'),
  propertyId: _requiredString(row, 'property_id'),
  unitCode: _requiredString(row, 'unit_code'),
  status: _requiredEnum(row, 'status', _unitStatusFromWire),
  version: _requiredInt(row, 'version'),
  unitType: _optionalString(row['unit_type']),
  floor: _optionalString(row['floor']),
  areaSqm: _optionalDouble(row['area_sqm']),
  rooms: _optionalDouble(row['rooms']),
  vacancySince: _optionalDate(row['vacancy_since']),
  bathrooms: _optionalDouble(row['bathrooms']),
  targetRentMonthly: _optionalDouble(row['target_rent_monthly']),
  marketRentMonthly: _optionalDouble(row['market_rent_monthly']),
  currencyCode: _optionalString(row['currency_code']),
  vacancyReason: _optionalString(row['vacancy_reason']),
  offlineReason: _optionalString(row['offline_reason']),
  marketingStatus: _optionalString(row['marketing_status']),
  renovationStatus: _optionalString(row['renovation_status']),
  expectedReadyDate: _optionalDate(row['expected_ready_date']),
  nextAction: _optionalString(row['next_action']),
  notes: _optionalString(row['notes']),
  createdAt: _requiredDate(row, 'created_at'),
  updatedAt: _requiredDate(row, 'updated_at'),
  createdBy: _requiredString(row, 'created_by'),
  updatedBy: _requiredString(row, 'updated_by'),
);

LeaseSummaryDto _parseLeaseSummary(Map<String, dynamic> row) => LeaseSummaryDto(
  id: _requiredString(row, 'id'),
  workspaceId: _requiredString(row, 'workspace_id'),
  propertyId: _requiredString(row, 'property_id'),
  unitId: _requiredString(row, 'unit_id'),
  leaseName: _requiredString(row, 'lease_name'),
  status: _requiredEnum(row, 'status', _leaseStatusFromWire),
  startDate: _requiredDate(row, 'start_date'),
  baseRentMonthly: _requiredDouble(row, 'base_rent_monthly'),
  currencyCode: _requiredString(row, 'currency_code'),
  version: _requiredInt(row, 'version'),
  tenantPartyId: _optionalString(row['tenant_party_id']),
  endDate: _optionalDate(row['end_date']),
);

LeaseDto _parseLease(Map<String, dynamic> row) => LeaseDto(
  id: _requiredString(row, 'id'),
  workspaceId: _requiredString(row, 'workspace_id'),
  propertyId: _requiredString(row, 'property_id'),
  unitId: _requiredString(row, 'unit_id'),
  leaseName: _requiredString(row, 'lease_name'),
  status: _requiredEnum(row, 'status', _leaseStatusFromWire),
  startDate: _requiredDate(row, 'start_date'),
  baseRentMonthly: _requiredDouble(row, 'base_rent_monthly'),
  currencyCode: _requiredString(row, 'currency_code'),
  version: _requiredInt(row, 'version'),
  tenantPartyId: _optionalString(row['tenant_party_id']),
  endDate: _optionalDate(row['end_date']),
  billingFrequency: _requiredEnum(
    row,
    'billing_frequency',
    _billingFrequencyFromWire,
  ),
  moveInDate: _optionalDate(row['move_in_date']),
  moveOutDate: _optionalDate(row['move_out_date']),
  signedDate: _optionalDate(row['signed_date']),
  noticeDate: _optionalDate(row['notice_date']),
  renewalOptionDate: _optionalDate(row['renewal_option_date']),
  breakOptionDate: _optionalDate(row['break_option_date']),
  ancillaryChargesMonthly: _optionalDouble(row['ancillary_charges_monthly']),
  parkingOtherChargesMonthly: _optionalDouble(
    row['parking_other_charges_monthly'],
  ),
  securityDeposit: _optionalDouble(row['security_deposit']),
  paymentDayOfMonth: _optionalInt(row['payment_day_of_month']),
  rentFreePeriodMonths: _optionalInt(row['rent_free_period_months']),
  endedAt: _optionalDate(row['ended_at']),
  cancelledAt: _optionalDate(row['cancelled_at']),
  notes: _optionalString(row['notes']),
  createdAt: _requiredDate(row, 'created_at'),
  updatedAt: _requiredDate(row, 'updated_at'),
  createdBy: _requiredString(row, 'created_by'),
  updatedBy: _requiredString(row, 'updated_by'),
);

LeasingCaseSummaryDto _parseLeasingCaseSummary(Map<String, dynamic> row) =>
    LeasingCaseSummaryDto(
      id: _requiredString(row, 'id'),
      workspaceId: _requiredString(row, 'workspace_id'),
      propertyId: _requiredString(row, 'property_id'),
      caseName: _requiredString(row, 'case_name'),
      status: _requiredEnum(row, 'status', _caseStatusFromWire),
      source: _requiredEnum(row, 'source', _caseSourceFromWire),
      openedAt: _requiredDate(row, 'opened_at'),
      version: _requiredInt(row, 'version'),
      unitId: _optionalString(row['unit_id']),
      prospectPartyId: _optionalString(row['prospect_party_id']),
      leaseId: _optionalString(row['lease_id']),
    );

LeasingCaseDto _parseLeasingCase(Map<String, dynamic> row) => LeasingCaseDto(
  id: _requiredString(row, 'id'),
  workspaceId: _requiredString(row, 'workspace_id'),
  propertyId: _requiredString(row, 'property_id'),
  caseName: _requiredString(row, 'case_name'),
  status: _requiredEnum(row, 'status', _caseStatusFromWire),
  source: _requiredEnum(row, 'source', _caseSourceFromWire),
  openedAt: _requiredDate(row, 'opened_at'),
  version: _requiredInt(row, 'version'),
  unitId: _optionalString(row['unit_id']),
  prospectPartyId: _optionalString(row['prospect_party_id']),
  leaseId: _optionalString(row['lease_id']),
  completedAt: _optionalDate(row['completed_at']),
  cancelledAt: _optionalDate(row['cancelled_at']),
  notes: _optionalString(row['notes']),
  createdAt: _requiredDate(row, 'created_at'),
  updatedAt: _requiredDate(row, 'updated_at'),
  createdBy: _requiredString(row, 'created_by'),
  updatedBy: _requiredString(row, 'updated_by'),
);

RentRollSnapshotDto _parseRentRollSnapshot(
  Map<String, dynamic> row,
  List<RentRollSnapshotLineDto> lines,
) => RentRollSnapshotDto(
  id: _requiredString(row, 'id'),
  workspaceId: _requiredString(row, 'workspace_id'),
  propertyId: _requiredString(row, 'property_id'),
  asOfDate: _requiredDate(row, 'as_of_date'),
  currencyCode: _requiredString(row, 'currency_code'),
  generatedAt: _requiredDate(row, 'generated_at'),
  unitCount: _requiredInt(row, 'unit_count'),
  occupiedUnitCount: _requiredInt(row, 'occupied_unit_count'),
  vacantUnitCount: _requiredInt(row, 'vacant_unit_count'),
  offlineUnitCount: _requiredInt(row, 'offline_unit_count'),
  effectiveLeaseCount: _requiredInt(row, 'effective_lease_count'),
  totalBaseRentMonthly: _requiredDouble(row, 'total_base_rent_monthly'),
  totalAncillaryChargesMonthly: _requiredDouble(
    row,
    'total_ancillary_charges_monthly',
  ),
  totalParkingOtherChargesMonthly: _requiredDouble(
    row,
    'total_parking_other_charges_monthly',
  ),
  totalRentMonthly: _requiredDouble(row, 'total_rent_monthly'),
  createdAt: _requiredDate(row, 'created_at'),
  createdBy: _requiredString(row, 'created_by'),
  lines: lines,
);

RentRollSnapshotLineDto _parseRentRollLine(Map<String, dynamic> row) =>
    RentRollSnapshotLineDto(
      id: _requiredString(row, 'id'),
      unitId: _requiredString(row, 'unit_id'),
      unitCode: _requiredString(row, 'unit_code'),
      unitStatus: _requiredEnum(row, 'unit_status', _unitStatusFromWire),
      effectiveLeaseCount: _requiredInt(row, 'effective_lease_count'),
      baseRentMonthly: _requiredDouble(row, 'base_rent_monthly'),
      ancillaryChargesMonthly: _requiredDouble(
        row,
        'ancillary_charges_monthly',
      ),
      parkingOtherChargesMonthly: _requiredDouble(
        row,
        'parking_other_charges_monthly',
      ),
      totalRentMonthly: _requiredDouble(row, 'total_rent_monthly'),
      areaSqm: _optionalDouble(row['area_sqm']),
    );

RentRollLiveDto _parseRentRollLive(Map<String, dynamic> entity) {
  final rawLines = entity['lines'];
  if (rawLines is! List) {
    throw const FormatException('Live rent roll carries no lines.');
  }
  return RentRollLiveDto(
    workspaceId: _requiredString(entity, 'workspace_id'),
    propertyId: _requiredString(entity, 'property_id'),
    asOfDate: _requiredDate(entity, 'as_of_date'),
    computedAt: _requiredDate(entity, 'computed_at'),
    currencies: _parseCurrencies(entity['currencies']),
    unitCount: _requiredInt(entity, 'unit_count'),
    occupiedUnitCount: _requiredInt(entity, 'occupied_unit_count'),
    vacantUnitCount: _requiredInt(entity, 'vacant_unit_count'),
    offlineUnitCount: _requiredInt(entity, 'offline_unit_count'),
    effectiveLeaseCount: _requiredInt(entity, 'effective_lease_count'),
    // Null on purpose when the currencies disagree — see the DTO.
    totalBaseRentMonthly: _optionalDouble(entity['total_base_rent_monthly']),
    totalAncillaryChargesMonthly: _optionalDouble(
      entity['total_ancillary_charges_monthly'],
    ),
    totalParkingOtherChargesMonthly: _optionalDouble(
      entity['total_parking_other_charges_monthly'],
    ),
    totalRentMonthly: _optionalDouble(entity['total_rent_monthly']),
    lines: rawLines
        .map((line) => _parseRentRollLiveLine(_asMap(line)))
        .toList(growable: false),
  );
}

RentRollLiveLineDto _parseRentRollLiveLine(Map<String, dynamic> row) =>
    RentRollLiveLineDto(
      unitId: _requiredString(row, 'unit_id'),
      unitCode: _requiredString(row, 'unit_code'),
      unitStatus: _requiredEnum(row, 'unit_status', _unitStatusFromWire),
      effectiveLeaseCount: _requiredInt(row, 'effective_lease_count'),
      baseRentMonthly: _requiredDouble(row, 'base_rent_monthly'),
      ancillaryChargesMonthly: _requiredDouble(
        row,
        'ancillary_charges_monthly',
      ),
      parkingOtherChargesMonthly: _requiredDouble(
        row,
        'parking_other_charges_monthly',
      ),
      totalRentMonthly: _requiredDouble(row, 'total_rent_monthly'),
      currencies: _parseCurrencies(row['currencies']),
      areaSqm: _optionalDouble(row['area_sqm']),
    );

List<String> _parseCurrencies(Object? value) {
  if (value is! List) {
    throw const FormatException('Currency list expected.');
  }
  return value.map((entry) => entry.toString()).toList(growable: false);
}

List<RentRollSnapshotLineDto> _parseEmbeddedLines(Map<String, dynamic> entity) {
  final raw = entity['lines'];
  if (raw is! List) {
    throw const FormatException('Rent roll document carries no lines.');
  }
  return raw
      .map((line) => _parseRentRollLine(_asMap(line)))
      .toList(growable: false);
}

PropertyLeasingSummaryDto _parseLeasingSummary(Map<String, dynamic> row) {
  final units = _asMap(row['units']);
  final vacancy = _asMap(row['vacancy']);
  final roll = _asMap(row['lease_roll']);
  final decisions = _asMap(row['decisions']);
  final rentRaw = row['rent_roll'];
  if (rentRaw is! List) {
    throw const FormatException('Expected a rent roll array.');
  }
  return PropertyLeasingSummaryDto(
    asOf: _requiredDate(row, 'as_of'),
    units: PropertyLeasingUnits(
      total: _requiredInt(units, 'total'),
      occupied: _requiredInt(units, 'occupied'),
      vacant: _requiredInt(units, 'vacant'),
      offline: _requiredInt(units, 'offline'),
      areaSqmTotal: _requiredDouble(units, 'area_sqm_total'),
      areaSqmOccupied: _requiredDouble(units, 'area_sqm_occupied'),
      areaSqmVacant: _requiredDouble(units, 'area_sqm_vacant'),
      unitsWithoutArea: _requiredInt(units, 'units_without_area'),
    ),
    vacancy: PropertyLeasingVacancy(
      // Null stays null: a zero here would claim the vacancy began today.
      longestVacancyDays: _optionalInt(vacancy['longest_vacancy_days']),
      vacantWithoutSince: _requiredInt(vacancy, 'vacant_without_since'),
    ),
    leaseRoll: PropertyLeaseRoll(
      active: _requiredInt(roll, 'active'),
      openEnded: _requiredInt(roll, 'open_ended'),
      expiredOpen: _requiredInt(roll, 'expired_open'),
      windows: _parseExpiryWindows(roll['windows']),
    ),
    decisions: PropertyLeaseDecisions(
      windowDays: _requiredInt(decisions, 'window_days'),
      noticeDue: _requiredInt(decisions, 'notice_due'),
      renewalOption: _requiredInt(decisions, 'renewal_option'),
      breakOption: _requiredInt(decisions, 'break_option'),
    ),
    rentRoll: rentRaw.map((entry) {
      final currency = _asMap(entry);
      return PropertyRentRollCurrency(
        currencyCode: _requiredString(currency, 'currency_code'),
        monthlyBase: _requiredDouble(currency, 'monthly_base'),
        leases: _requiredInt(currency, 'leases'),
      );
    }).toList(growable: false),
  );
}

List<PropertyLeaseExpiryWindow> _parseExpiryWindows(Object? raw) {
  if (raw is! List) {
    throw const FormatException('Expected an expiry window array.');
  }
  return raw.map((entry) {
    final window = _asMap(entry);
    return PropertyLeaseExpiryWindow(
      days: _requiredInt(window, 'days'),
      // The label is the server's wording, carried rather than rebuilt from
      // `days`, so a client cannot rename a window it did not cut.
      label: _requiredString(window, 'label'),
      expiring: _requiredInt(window, 'expiring'),
    );
  }).toList(growable: false);
}

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

double _requiredDouble(Map<String, dynamic> row, String key) {
  final value = _optionalDouble(row[key]);
  if (value == null) {
    throw FormatException('Missing numeric field: $key');
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

/// Postgres `numeric` arrives as a String over PostgREST to avoid the precision
/// loss a double round trip would cause; both forms are accepted.
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

/// Postgres `date` columns hold a calendar day, not an instant.
///
/// The Y/M/D components are taken exactly as the caller supplied them, with no
/// UTC conversion: a lease starting "1 March" means the first of March in the
/// caller's terms, and normalising through UTC would silently shift it to
/// 28 February for anyone east of Greenwich. Every date this adapter sends is a
/// `date` column, so there is no instant to preserve.
String? _dateToWire(DateTime? value) {
  if (value == null) {
    return null;
  }
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.whereType<String>().toList(growable: false);
}
