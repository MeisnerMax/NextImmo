/// Supabase adapter for the cost allocation rules
/// (`COST-ALLOCATION-RULES-01`, P-2a).
///
/// Nothing here decides anything. Whether a cost may be passed on, which
/// principle it settles on, and how many accounts are still unclassified are
/// all the server's answers — including the counts, which are taken over every
/// account in the workspace rather than over whatever page a caller holds.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/finance_ledger_port.dart';
import '../domain/cost_allocation_dto.dart';
import 'supabase_finance_ledger_adapter.dart' show FinanceSupabaseGateway;

class SupabaseCostAllocationAdapter implements CostAllocationRulesPort {
  SupabaseCostAllocationAdapter({required SupabaseClient client})
    : _gateway = _DirectGateway(client);

  SupabaseCostAllocationAdapter.withGateway(this._gateway);

  final FinanceSupabaseGateway _gateway;

  @override
  Future<FinanceRepositoryResult<CostAllocationOverviewDto>> readRules({
    required String workspaceId,
    bool allocatableOnly = false,
  }) async {
    try {
      final response = await _gateway.callRpc(
        'cost_allocation_rules',
        <String, Object?>{
          'p_workspace_id': workspaceId,
          'p_allocatable_only': allocatableOnly,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<CostAllocationOverviewDto>(
          _parseOverview(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<CostAllocationOverviewDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<CostAllocationOverviewDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Umlagefähigkeit konnte nicht geladen werden.',
      );
    }
  }

  @override
  Future<FinanceRepositoryResult<CostAllocationRuleDto>> setRule(
    SetCostAllocationRuleCommand command,
  ) async {
    // Refused before the round trip, because the server refuses it too and the
    // reason is legal rather than technical: a HeizkostenV position settles on
    // the performance principle (BGH VIII ZR 156/11).
    if (command.underHeatingCostRegulation &&
        command.settlementPrinciple != CostSettlementPrinciple.performance) {
      return const FinanceRepositoryFailure<CostAllocationRuleDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Eine HeizkostenV-Position wird nach dem Leistungsprinzip '
            'abgerechnet (BGH VIII ZR 156/11).',
        field: 'settlementPrinciple',
      );
    }
    if (command.settlementPrinciple == CostSettlementPrinciple.unknown) {
      return const FinanceRepositoryFailure<CostAllocationRuleDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Ein Abrechnungsprinzip, das dieser Stand nicht kennt, kann nicht '
            'geschrieben werden. Es kann nur von einem neueren Server stammen.',
        field: 'settlementPrinciple',
      );
    }
    try {
      final response = await _gateway.callRpc(
        'set_cost_allocation_rule',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_finance_account_id': command.financeAccountId,
          'p_allocatable': command.allocatable,
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_expected_version': command.expectedVersion,
          'p_settlement_principle': command.settlementPrinciple == null
              ? null
              : costSettlementPrincipleKey(command.settlementPrinciple!),
          'p_betrkv_position': command.betrkvPosition,
          'p_under_heating_cost_regulation':
              command.underHeatingCostRegulation,
          'p_note': command.note,
          'p_reason': command.context.reason,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<CostAllocationRuleDto>(
          _parseRule(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<CostAllocationRuleDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<CostAllocationRuleDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Regel konnte nicht gespeichert werden.',
      );
    }
  }
}

class _DirectGateway implements FinanceSupabaseGateway {
  const _DirectGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) {
    return _client.rpc(function, params: parameters);
  }
}

FinanceRepositoryFailure<T> _mapFailure<T>(Map<String, dynamic> error) {
  final code = error['code'] is String ? error['code'] as String : '';
  final message = error['message'] is String
      ? error['message'] as String
      : 'Die Anfrage wurde abgelehnt.';
  final field = error['field'] is String ? error['field'] as String : null;
  return switch (code) {
    'forbidden' => FinanceRepositoryFailure<T>(
      kind: FinanceRepositoryFailureKind.forbidden,
      message: message,
      field: field,
    ),
    'not_found' => FinanceRepositoryFailure<T>(
      kind: FinanceRepositoryFailureKind.notFound,
      message: message,
      field: field,
    ),
    // A version conflict has no kind of its own on this contract, so it lands
    // as a validation failure carrying the server's message. That is honest
    // rather than convenient: the caller's fix is the same either way -- read
    // the rule again and decide against what is actually stored.
    'validation_failed' || 'version_conflict' => FinanceRepositoryFailure<T>(
      kind: FinanceRepositoryFailureKind.validationFailed,
      message: message,
      field: field,
    ),
    _ => FinanceRepositoryFailure<T>(
      kind: FinanceRepositoryFailureKind.infrastructureFailure,
      message: message,
      field: field,
    ),
  };
}

CostAllocationOverviewDto _parseOverview(Map<String, dynamic> entity) {
  final rows = entity['accounts'];
  if (rows is! List) {
    throw const FormatException('Expected an account list.');
  }
  return CostAllocationOverviewDto(
    accounts: rows
        .map((row) => _parseAccount(_asMap(row)))
        .toList(growable: false),
    // Read, never counted from the list: the server counted over every account
    // in the workspace, and "how much is still unclassified" is the number
    // this surface exists to drive to zero.
    classifiedCount: _requiredInt(entity, 'classified_count'),
    unclassifiedCount: _requiredInt(entity, 'unclassified_count'),
    totalCount: _requiredInt(entity, 'total_count'),
  );
}

CostAccountAllocationDto _parseAccount(Map<String, dynamic> row) {
  final rawRule = row['rule'];
  return CostAccountAllocationDto(
    financeAccountId: _requiredString(row, 'finance_account_id'),
    code: _requiredString(row, 'code'),
    name: _requiredString(row, 'name'),
    accountType: _requiredString(row, 'account_type'),
    isActive: row['is_active'] == true,
    // Absent from a server that predates FINANCE-COST-TYPES-01. Left null
    // rather than defaulted: `update_finance_account` refuses a wrong version,
    // so a guess would be an edit offered and then rejected.
    version: row['version'] is num ? (row['version'] as num).toInt() : null,
    parentAccountId: _optionalString(row['parent_account_id']),
    // Null stays null. An account nobody has classified and one classified as
    // "not apportionable" mean different things, and collapsing them here
    // would make the unclassified count unexplainable.
    rule: rawRule is Map ? _parseRule(_asMap(rawRule)) : null,
  );
}

CostAllocationRuleDto _parseRule(Map<String, dynamic> row) {
  final rawPrinciple = row['settlement_principle'];
  final principle = rawPrinciple is String
      ? costSettlementPrincipleFromKey(rawPrinciple)
      : null;
  return CostAllocationRuleDto(
    financeAccountId: _requiredString(row, 'finance_account_id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    allocatable: row['allocatable'] == true,
    betrkvPosition: _optionalString(row['betrkv_position']),
    underHeatingCostRegulation: row['under_heating_cost_regulation'] == true,
    settlementPrinciple: principle,
    note: _optionalString(row['note']),
    version: _requiredInt(row, 'version'),
    rawPrincipleKey: principle == CostSettlementPrinciple.unknown
        ? rawPrinciple as String?
        : null,
  );
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, dynamic entry) => MapEntry(key.toString(), entry));
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

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value.isEmpty ? null : value;
  }
  throw const FormatException('Expected a string.');
}

int _requiredInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw FormatException('Missing integer field: $key');
}
