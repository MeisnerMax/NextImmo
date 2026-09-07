/// Supabase adapter for cost pools and allocation keys
/// (`COST-POOLS-ALLOCATION-KEYS-01`, P-2b).
///
/// Nothing here computes a distribution. Whether a basis resolves, what it
/// resolves to, and how many keys could not be resolved are all the server's
/// answers — including the counts, which are taken over every matching key
/// rather than over whatever list a caller holds.
///
/// The one thing this layer decides is what it refuses to send: a scope or
/// basis this build does not recognise, and a key with no explanation. All
/// three are refused server-side too. They are refused here as well because
/// the reason is worth stating in the caller's language before a round trip —
/// and because a missing explanation is a legal defect, not a typo.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/finance_ledger_port.dart';
import '../domain/cost_pool_dto.dart';
import 'supabase_finance_ledger_adapter.dart' show FinanceSupabaseGateway;

class SupabaseCostPoolAdapter implements CostPoolsPort {
  SupabaseCostPoolAdapter({required SupabaseClient client})
    : _gateway = _DirectGateway(client);

  SupabaseCostPoolAdapter.withGateway(this._gateway);

  final FinanceSupabaseGateway _gateway;

  @override
  Future<FinanceRepositoryResult<CostPoolOverviewDto>> readPools({
    required String workspaceId,
    String? propertyId,
    bool includeInactive = false,
  }) async {
    try {
      final response = await _gateway.callRpc(
        'workspace_cost_pools',
        <String, Object?>{
          'p_workspace_id': workspaceId,
          'p_property_id': propertyId,
          'p_include_inactive': includeInactive,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<CostPoolOverviewDto>(
          _parsePoolOverview(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<CostPoolOverviewDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<CostPoolOverviewDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Kostenpools konnten nicht geladen werden.',
      );
    }
  }

  @override
  Future<FinanceRepositoryResult<AllocationKeyOverviewDto>> readAllocationKeys({
    required String workspaceId,
    DateTime? asOf,
    String? propertyId,
    String? financeAccountId,
  }) async {
    try {
      final response = await _gateway.callRpc(
        'allocation_keys_as_of',
        <String, Object?>{
          'p_workspace_id': workspaceId,
          'p_as_of': asOf == null ? null : _formatDate(asOf),
          'p_property_id': propertyId,
          'p_finance_account_id': financeAccountId,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<AllocationKeyOverviewDto>(
          _parseKeyOverview(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<AllocationKeyOverviewDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<AllocationKeyOverviewDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Umlageschlüssel konnten nicht geladen werden.',
      );
    }
  }

  @override
  Future<FinanceRepositoryResult<CostPoolDto>> upsertPool(
    UpsertCostPoolCommand command,
  ) async {
    if (command.scope == CostPoolScope.unknown) {
      return const FinanceRepositoryFailure<CostPoolDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Ein Geltungsbereich, den dieser Stand nicht kennt, kann nicht '
            'geschrieben werden. Er kann nur von einem neueren Server stammen.',
        field: 'scope',
      );
    }
    // The label is the entire identity of a building, an entrance or a
    // Zählergruppe here, because this schema has no entity for any of the
    // three. Without it the pool would have no place at all.
    if (costPoolScopeNeedsUnit(command.scope) && command.unitId == null) {
      return const FinanceRepositoryFailure<CostPoolDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message: 'Ein Einheiten-Pool benennt die Einheit, die er abdeckt.',
        field: 'unitId',
      );
    }
    if (costPoolScopeNeedsLabel(command.scope) &&
        (command.scopeLabel == null || command.scopeLabel!.trim().isEmpty)) {
      return const FinanceRepositoryFailure<CostPoolDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Für Gebäude, Aufgang und Zählergruppe gibt es in diesem Modell '
            'keine eigene Entität. Die Bezeichnung ist die einzige Identität '
            'des Pools und daher erforderlich.',
        field: 'scopeLabel',
      );
    }
    try {
      final response = await _gateway.callRpc(
        'upsert_cost_pool',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_pool_key': command.poolKey,
          'p_name': command.name,
          'p_scope': costPoolScopeKey(command.scope),
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_pool_id': command.poolId,
          'p_expected_version': command.expectedVersion,
          'p_property_id': command.propertyId,
          'p_unit_id': command.unitId,
          'p_scope_label': command.scopeLabel,
          'p_note': command.note,
          'p_is_active': command.isActive,
          'p_reason': command.context.reason,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<CostPoolDto>(
          _parsePool(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<CostPoolDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<CostPoolDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Der Kostenpool konnte nicht gespeichert werden.',
      );
    }
  }

  @override
  Future<FinanceRepositoryResult<AllocationKeyDto>> upsertAllocationKey(
    UpsertAllocationKeyCommand command,
  ) async {
    if (command.basis == AllocationBasis.unknown) {
      return const FinanceRepositoryFailure<AllocationKeyDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Ein Verteilungsmaßstab, den dieser Stand nicht kennt, kann nicht '
            'geschrieben werden. Er kann nur von einem neueren Server stammen.',
        field: 'basis',
      );
    }
    // Refused rather than defaulted. DEC-014 model consequence 2: the
    // Verteilerschlüssel mit Erläuterung is one of the four Mindestangaben —
    // its absence makes the statement formally void, which costs the whole
    // claim rather than a correction.
    if (command.explanation.trim().isEmpty) {
      return const FinanceRepositoryFailure<AllocationKeyDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Eine Erläuterung ist Pflicht: sie gehört zu den vier '
            'Mindestangaben, ohne die eine Betriebskostenabrechnung formell '
            'unwirksam ist.',
        field: 'explanation',
      );
    }
    try {
      final response = await _gateway.callRpc(
        'upsert_allocation_key',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_property_id': command.propertyId,
          'p_basis': allocationBasisKey(command.basis),
          'p_explanation': command.explanation,
          'p_valid_from': _formatDate(command.validFrom),
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_key_id': command.keyId,
          'p_expected_version': command.expectedVersion,
          'p_finance_account_id': command.financeAccountId,
          'p_cost_pool_id': command.costPoolId,
          'p_valid_to': command.validTo == null
              ? null
              : _formatDate(command.validTo!),
          'p_note': command.note,
          'p_reason': command.context.reason,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<AllocationKeyDto>(
          _parseKey(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<AllocationKeyDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<AllocationKeyDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Der Umlageschlüssel konnte nicht gespeichert werden.',
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
    // `dependency_conflict` is the overlap: another key already covers part of
    // that period, or the pool key is taken. It lands as a validation failure
    // carrying the server's message, which names which of the two it was --
    // the caller's fix is to change the input either way.
    'validation_failed' ||
    'version_conflict' ||
    'dependency_conflict' ||
    'mutation_conflict' => FinanceRepositoryFailure<T>(
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

CostPoolOverviewDto _parsePoolOverview(Map<String, dynamic> entity) {
  final rows = entity['pools'];
  if (rows is! List) {
    throw const FormatException('Expected a pool list.');
  }
  return CostPoolOverviewDto(
    pools: rows.map((row) => _parsePool(_asMap(row))).toList(growable: false),
  );
}

CostPoolDto _parsePool(Map<String, dynamic> row) {
  final rawScope = _requiredString(row, 'scope');
  final scope = costPoolScopeFromKey(rawScope);
  return CostPoolDto(
    id: _requiredString(row, 'id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    poolKey: _requiredString(row, 'pool_key'),
    name: _requiredString(row, 'name'),
    scope: scope,
    propertyId: _optionalString(row['property_id']),
    propertyName: _optionalString(row['property_name']),
    unitId: _optionalString(row['unit_id']),
    unitCode: _optionalString(row['unit_code']),
    scopeLabel: _optionalString(row['scope_label']),
    note: _optionalString(row['note']),
    isActive: row['is_active'] == true,
    version: _requiredInt(row, 'version'),
    // Taken from the server, never derived from the scope here: a build that
    // gains a building entity should not need this rule rewritten in two
    // places. Absent means the payload did not answer -- and an unanswered
    // question must not read as "yes", or an unrecognised scope from a newer
    // server would come back as automatically distributable.
    scopeResolvable: row['scope_resolvable'] == true,
    scopeUnresolvableReason: _optionalString(row['scope_unresolvable_reason']),
    rawScopeKey: scope == CostPoolScope.unknown ? rawScope : null,
  );
}

AllocationKeyOverviewDto _parseKeyOverview(Map<String, dynamic> entity) {
  final rows = entity['keys'];
  if (rows is! List) {
    throw const FormatException('Expected a key list.');
  }
  return AllocationKeyOverviewDto(
    asOfDate: _requiredDate(entity, 'as_of_date'),
    keys: rows.map((row) => _parseKey(_asMap(row))).toList(growable: false),
    // Read, never counted from the list. The server counted over every
    // matching key, and "how many could not be resolved" is the number a
    // settlement run has to be able to state.
    resolvableCount: _requiredInt(entity, 'resolvable_count'),
    unresolvableCount: _requiredInt(entity, 'unresolvable_count'),
    totalCount: _requiredInt(entity, 'total_count'),
  );
}

AllocationKeyDto _parseKey(Map<String, dynamic> row) {
  final rawBasis = _requiredString(row, 'basis');
  final basis = allocationBasisFromKey(rawBasis);
  final rawResolution = row['basis_resolution'];
  return AllocationKeyDto(
    id: _requiredString(row, 'id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    propertyId: _requiredString(row, 'property_id'),
    propertyName: _optionalString(row['property_name']),
    financeAccountId: _optionalString(row['finance_account_id']),
    financeAccountCode: _optionalString(row['finance_account_code']),
    financeAccountName: _optionalString(row['finance_account_name']),
    costPoolId: _optionalString(row['cost_pool_id']),
    costPoolKey: _optionalString(row['cost_pool_key']),
    costPoolName: _optionalString(row['cost_pool_name']),
    basis: basis,
    explanation: _requiredString(row, 'explanation'),
    validFrom: _requiredDate(row, 'valid_from'),
    validTo: _optionalDate(row['valid_to']),
    note: _optionalString(row['note']),
    version: _requiredInt(row, 'version'),
    // The command's snapshot carries no resolution -- it answers "what did I
    // just write", not "what would it distribute over". Absent means unknown,
    // and unknown must not read as resolvable.
    basisResolution: rawResolution is Map
        ? _parseResolution(_asMap(rawResolution))
        : const AllocationBasisResolutionDto(
            resolvable: false,
            reason: AllocationUnresolvableReason.notEvaluated,
          ),
    rawBasisKey: basis == AllocationBasis.unknown ? rawBasis : null,
  );
}

AllocationBasisResolutionDto _parseResolution(Map<String, dynamic> row) {
  final rawReason = row['reason'];
  final reason = rawReason is String
      ? allocationUnresolvableReasonFromKey(rawReason)
      : null;
  return AllocationBasisResolutionDto(
    resolvable: row['resolvable'] == true,
    reason: reason,
    rawReasonKey: reason == AllocationUnresolvableReason.unknown
        ? rawReason as String?
        : null,
    total: _optionalNum(row['total']),
    unitCount: _optionalInt(row['unit_count']),
    unitsWithoutValue: _optionalInt(row['units_without_value']),
    detail: _optionalString(row['detail']),
  );
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-$month-$day';
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

DateTime _requiredDate(Map<String, dynamic> row, String key) {
  final value = _optionalDate(row[key]);
  if (value == null) {
    throw FormatException('Missing date field: $key');
  }
  return value;
}

DateTime? _optionalDate(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('Expected a date: $value');
    }
    // Dates only. Keeping the parsed time would let a UTC offset move a
    // validity boundary across a midnight, which is exactly the day a key
    // takes effect.
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
  throw const FormatException('Expected a date string.');
}

num? _optionalNum(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value;
  }
  if (value is String) {
    final parsed = num.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw const FormatException('Expected a number.');
}

int? _optionalInt(Object? value) {
  final parsed = _optionalNum(value);
  return parsed?.toInt();
}

int _requiredInt(Map<String, dynamic> row, String key) {
  final value = _optionalInt(row[key]);
  if (value == null) {
    throw FormatException('Missing integer field: $key');
  }
  return value;
}
