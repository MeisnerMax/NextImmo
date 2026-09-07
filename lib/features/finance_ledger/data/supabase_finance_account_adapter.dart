/// Supabase adapter for the cost type tree (`FINANCE-COST-TYPES-01`).
///
/// The commands it calls have existed since `FINANCE-01a` — audited,
/// idempotent, granted to `authenticated` — and no client called them, because
/// `update_finance_account` requires an account version that the only read
/// listing accounts did not return. This adapter is the other half of that
/// fix; the migration is the one field.
///
/// Two refusals happen here, before the round trip, and both are refused
/// server-side as well: an account kind this build does not recognise, and a
/// code that could not be stored. The second is not pedantry — a code is set
/// once and never changed, because it is what a booking, a report and an
/// export cite.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/finance_ledger_port.dart';
import '../domain/cost_allocation_dto.dart';
import '../domain/finance_actuals_dto.dart';
import 'supabase_finance_ledger_adapter.dart' show FinanceSupabaseGateway;

/// The shape `finance_accounts_code_check` enforces server-side. Kept here so
/// the reason arrives before the round trip rather than as a constraint name.
final RegExp financeAccountCodePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$');

class SupabaseFinanceAccountAdapter implements FinanceAccountsPort {
  SupabaseFinanceAccountAdapter({required SupabaseClient client})
    : _gateway = _DirectGateway(client);

  SupabaseFinanceAccountAdapter.withGateway(this._gateway);

  final FinanceSupabaseGateway _gateway;

  @override
  Future<FinanceRepositoryResult<CostAccountAllocationDto>> createAccount(
    CreateFinanceAccountCommand command,
  ) async {
    if (command.accountType == FinanceAccountType.unknown) {
      return const FinanceRepositoryFailure<CostAccountAllocationDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Eine Kontoart, die dieser Stand nicht kennt, kann nicht '
            'geschrieben werden. Sie kann nur von einem neueren Server stammen.',
        field: 'accountType',
      );
    }
    final String code = command.code.trim();
    if (!financeAccountCodePattern.hasMatch(code)) {
      return const FinanceRepositoryFailure<CostAccountAllocationDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Der Schlüssel besteht aus Buchstaben, Ziffern, Punkt, Bindestrich '
            'oder Unterstrich (max. 50 Zeichen) und beginnt mit einem '
            'Buchstaben oder einer Ziffer. Er lässt sich später nicht mehr '
            'ändern, weil Buchungen und Berichte ihn zitieren.',
        field: 'code',
      );
    }
    if (command.name.trim().isEmpty) {
      return const FinanceRepositoryFailure<CostAccountAllocationDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message: 'Eine Bezeichnung ist erforderlich.',
        field: 'name',
      );
    }
    try {
      final response = await _gateway.callRpc(
        'create_finance_account',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_code': code,
          'p_name': command.name.trim(),
          'p_account_type': financeAccountTypeKey(command.accountType),
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_parent_account_id': command.parentAccountId,
          'p_reason': command.context.reason,
        },
      );
      return _result(response);
    } catch (_) {
      return const FinanceRepositoryFailure<CostAccountAllocationDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Kostenart konnte nicht angelegt werden.',
      );
    }
  }

  @override
  Future<FinanceRepositoryResult<CostAccountAllocationDto>> updateAccount(
    UpdateFinanceAccountCommand command,
  ) async {
    if (command.name != null && command.name!.trim().isEmpty) {
      return const FinanceRepositoryFailure<CostAccountAllocationDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Eine leere Bezeichnung löscht den Namen nicht, sie ist nur keine '
            'Bezeichnung. Zum Unverändertlassen das Feld nicht anfassen.',
        field: 'name',
      );
    }
    try {
      final response = await _gateway.callRpc(
        'update_finance_account',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_account_id': command.accountId,
          'p_expected_version': command.expectedVersion,
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_name': command.name?.trim(),
          'p_parent_account_id': command.parentAccountId,
          'p_clear_parent': command.clearParent,
          'p_is_active': command.isActive,
          'p_reason': command.context.reason,
        },
      );
      return _result(response);
    } catch (_) {
      return const FinanceRepositoryFailure<CostAccountAllocationDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Kostenart konnte nicht geändert werden.',
      );
    }
  }

  FinanceRepositoryResult<CostAccountAllocationDto> _result(Object? response) {
    final payload = _asMap(response);
    final ok = payload['ok'];
    if (ok == true) {
      return FinanceRepositorySuccess<CostAccountAllocationDto>(
        _parseAccount(_asMap(payload['entity'])),
      );
    }
    if (ok != false) {
      throw const FormatException('Missing RPC result status.');
    }
    return _mapFailure<CostAccountAllocationDto>(_asMap(payload['error']));
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

/// The server speaks English, the form speaks German.
///
/// The refusals this surface actually meets are few and known, so they are
/// translated rather than passed through: a taken code is the commonest thing
/// a person creating cost types will hit, and meeting it as "An account with
/// this code already exists" in an otherwise German dialog is a seam the
/// reader has to step over. Anything not on this list still comes through
/// verbatim — an untranslated sentence is better than a wrong one.
String? _germanFor(String message) => switch (message) {
  'An account with this code already exists' =>
    'Diesen Schlüssel gibt es in diesem Workspace schon.',
  'Cost account version is stale' || 'The account was changed by someone else' =>
    'Die Kostenart wurde zwischenzeitlich von jemand anderem geändert. '
        'Bitte schließen, neu öffnen und die Änderung wiederholen.',
  'Account not found' || 'Finance account not found' =>
    'Diese Kostenart gibt es nicht (mehr).',
  'Finance management is not permitted' =>
    'Für Kostenarten fehlt die Berechtigung zur Finanzverwaltung.',
  'That parent would create a cycle in the chart of accounts' =>
    'Diese Zuordnung würde einen Kreis im Kontenbaum erzeugen.',
  _ => null,
};

FinanceRepositoryFailure<T> _mapFailure<T>(Map<String, dynamic> error) {
  final code = error['code'] is String ? error['code'] as String : '';
  final raw = error['message'] is String
      ? error['message'] as String
      : 'Die Anfrage wurde abgelehnt.';
  final message = _germanFor(raw) ?? raw;
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
    // `dependency_conflict` is the taken code. It lands as a validation
    // failure carrying the server's message, because the caller's fix is the
    // same either way: change the input.
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

/// The command's own snapshot, which is the account row rather than the
/// list-read's shape: it names the id as `id`, and carries no allocation rule
/// because creating a cost type decides nothing about apportionment.
CostAccountAllocationDto _parseAccount(Map<String, dynamic> row) {
  return CostAccountAllocationDto(
    financeAccountId: _requiredString(row, 'id'),
    code: _requiredString(row, 'code'),
    name: _requiredString(row, 'name'),
    accountType: _requiredString(row, 'account_type'),
    isActive: row['is_active'] == true,
    version: _optionalInt(row['version']),
    parentAccountId: _optionalString(row['parent_account_id']),
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
