/// Supabase adapter for the finance ledger read (FINANCE-01a).
///
/// One RPC, no arithmetic. The parser maps what the server sent and refuses to
/// invent: an unknown account class keeps its raw key rather than being folded
/// into a known one, and there is nowhere in the DTO to put a computed result.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/finance_ledger_port.dart';
import '../domain/finance_actuals_dto.dart';
import '../domain/finance_kpi_dto.dart';

/// The narrow slice of Supabase this adapter needs, so tests can replay a
/// canned payload without a live client.
abstract interface class FinanceSupabaseGateway {
  Future<Object?> callRpc(String function, Map<String, Object?> parameters);
}

class SupabaseFinanceGateway implements FinanceSupabaseGateway {
  SupabaseFinanceGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> callRpc(
    String function,
    Map<String, Object?> parameters,
  ) => _client.rpc(function, params: parameters);
}

class SupabaseFinanceLedgerAdapter implements PropertyFinanceActualsPort {
  SupabaseFinanceLedgerAdapter({required SupabaseClient client})
    : _gateway = SupabaseFinanceGateway(client);

  SupabaseFinanceLedgerAdapter.withGateway(this._gateway);

  final FinanceSupabaseGateway _gateway;

  @override
  Future<FinanceRepositoryResult<PropertyFinanceActualsDto>> read({
    required String workspaceId,
    required String propertyId,
    FinancePeriodRange range = const FinancePeriodRange.unbounded(),
  }) async {
    try {
      final response = await _gateway
          .callRpc('property_finance_actuals', <String, Object?>{
            'p_workspace_id': workspaceId,
            'p_property_id': propertyId,
            'p_from_year': range.fromYear,
            'p_from_month': range.fromMonth,
            'p_to_year': range.toYear,
            'p_to_month': range.toMonth,
          });
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<PropertyFinanceActualsDto>(
          _parseActuals(payload),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<PropertyFinanceActualsDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<PropertyFinanceActualsDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Buchungen konnten nicht geladen werden.',
      );
    }
  }

}

/// The computed figures (FINANCE-01b).
///
/// Its own class rather than a second method on the adapter above: both ports
/// name their method `read`, and one class cannot carry two. The leasing
/// feature splits its adapters for exactly this reason — the aggregates share
/// the natural method name, so the split is an implementation fact of the data
/// layer, not a shape a screen ever sees.
class SupabaseFinanceKpisAdapter implements PropertyFinanceKpisPort {
  SupabaseFinanceKpisAdapter({required SupabaseClient client})
    : _gateway = SupabaseFinanceGateway(client);

  SupabaseFinanceKpisAdapter.withGateway(this._gateway);

  final FinanceSupabaseGateway _gateway;

  @override
  Future<FinanceRepositoryResult<PropertyFinanceKpisDto>> read({
    required String workspaceId,
    required String propertyId,
    FinancePeriodRange range = const FinancePeriodRange.unbounded(),
  }) async {
    try {
      final response = await _gateway
          .callRpc('property_finance_kpis', <String, Object?>{
            'p_workspace_id': workspaceId,
            'p_property_id': propertyId,
            'p_from_year': range.fromYear,
            'p_from_month': range.fromMonth,
            'p_to_year': range.toYear,
            'p_to_month': range.toMonth,
          });
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<PropertyFinanceKpisDto>(
          _parseKpis(payload),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<PropertyFinanceKpisDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<PropertyFinanceKpisDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Kennzahlen konnten nicht geladen werden.',
      );
    }
  }
}

FinanceRepositoryFailure<T> _mapFailure<T>(Map<String, dynamic> error) {
  final message = error['message'] is String
      ? error['message'] as String
      : 'Der Finanz-Read ist fehlgeschlagen.';
  final field = error['field'] is String ? error['field'] as String : null;
  return switch (error['code']) {
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
    'validation_failed' => FinanceRepositoryFailure<T>(
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

PropertyFinanceActualsDto _parseActuals(Map<String, dynamic> payload) {
  final rawLines = payload['accounts'];
  final rawPeriods = payload['periods'];
  return PropertyFinanceActualsDto(
    asOf: _requiredDate(payload, 'as_of'),
    lines: <FinanceActualLine>[
      if (rawLines is List)
        for (final entry in rawLines)
          if (entry is Map) _parseLine(_asMap(entry)),
    ],
    periods: <FinancePeriodCoverage>[
      if (rawPeriods is List)
        for (final entry in rawPeriods)
          if (entry is Map) _parsePeriod(_asMap(entry)),
    ],
    isProvisional: payload['is_provisional'] == true,
    openPeriods: _requiredInt(payload, 'open_periods'),
    coveredPeriods: _requiredInt(payload, 'covered_periods'),
  );
}

FinanceActualLine _parseLine(Map<String, dynamic> row) {
  final typeKey = _requiredString(row, 'account_type');
  return FinanceActualLine(
    accountId: _requiredString(row, 'account_id'),
    accountCode: _requiredString(row, 'account_code'),
    accountName: _requiredString(row, 'account_name'),
    accountType: financeAccountTypeFromWire(typeKey),
    accountTypeKey: typeKey,
    currencyCode: _requiredString(row, 'currency_code'),
    amount: _requiredNumber(row, 'amount'),
    entries: _requiredInt(row, 'entries'),
  );
}

FinancePeriodCoverage _parsePeriod(Map<String, dynamic> row) {
  return FinancePeriodCoverage(
    periodId: _requiredString(row, 'period_id'),
    fiscalYear: _requiredInt(row, 'fiscal_year'),
    periodMonth: _requiredInt(row, 'period_month'),
    // An unrecognised status reads as open, never as closed: treating an
    // unknown state as final would let a provisional figure pass for a settled
    // one, which is the failure that actually costs something.
    status: row['status'] == 'closed'
        ? FinancePeriodStatus.closed
        : FinancePeriodStatus.open,
    entries: _requiredInt(row, 'entries'),
  );
}

PropertyFinanceKpisDto _parseKpis(Map<String, dynamic> payload) {
  final raw = payload['values'];
  return PropertyFinanceKpisDto(
    asOf: _requiredDate(payload, 'as_of'),
    values: <FinanceKpiValue>[
      if (raw is List)
        for (final entry in raw)
          if (entry is Map) _parseKpiValue(_asMap(entry)),
    ],
    isProvisional: payload['is_provisional'] == true,
    openPeriods: _requiredInt(payload, 'open_periods'),
    coveredPeriods: _requiredInt(payload, 'covered_periods'),
    activeDefinitions: _requiredInt(payload, 'active_definitions'),
  );
}

FinanceKpiValue _parseKpiValue(Map<String, dynamic> row) {
  return FinanceKpiValue(
    kpiKey: _requiredString(row, 'kpi_key'),
    definitionId: _requiredString(row, 'definition_id'),
    // Required, not optional: a value whose version failed to parse is not a
    // value with an unknown version, it is a value this client must not show.
    definitionVersion: _requiredInt(row, 'definition_version'),
    name: _requiredString(row, 'name'),
    currencyCode: _requiredString(row, 'currency_code'),
    value: _requiredNumber(row, 'value'),
    entries: _requiredInt(row, 'entries'),
  );
}

// --- Primitives -------------------------------------------------------------

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

/// Postgres `numeric` arrives as a String over PostgREST to avoid the precision
/// loss a double round trip would cause; both forms are accepted.
num _requiredNumber(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is num) {
    return value;
  }
  if (value is String) {
    final parsed = num.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw FormatException('Missing numeric field: $key');
}

DateTime _requiredDate(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw FormatException('Missing timestamp field: $key');
}
