/// Supabase adapter for accounting periods and bookings
/// (`FINANCE-BOOKINGS-01`).
///
/// The commands have existed since `FINANCE-01a` — audited, idempotent,
/// granted to `authenticated` — and no client called them, so
/// `finance_ledger_entries` is empty in every workspace and every figure built
/// on it renders nothing. This adapter is the other half of that.
///
/// Two refusals happen here before the round trip, and both are refused
/// server-side as well:
///
///   * **A booking date outside its period.** The server gained that check in
///     this package's own migration; the client repeats it so the reason
///     arrives in the form rather than after a round trip.
///   * **A currency that is not three letters.** There is no workspace default
///     anywhere on the server, so every booking states its own and a typo is
///     worth catching early.
///
/// One thing this adapter deliberately does *not* offer: editing or deleting a
/// booking. No such command exists, and adding a method that could only ever
/// fail would be worse than the absence.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/finance_ledger_port.dart';
import '../domain/finance_booking_dto.dart';
import 'supabase_finance_ledger_adapter.dart' show FinanceSupabaseGateway;

final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');

class SupabaseFinanceBookingAdapter
    implements FinancePeriodsPort, PropertyLedgerPort {
  SupabaseFinanceBookingAdapter({required SupabaseClient client})
    : _gateway = _DirectGateway(client);

  SupabaseFinanceBookingAdapter.withGateway(this._gateway);

  final FinanceSupabaseGateway _gateway;

  @override
  Future<FinanceRepositoryResult<FinancePeriodOverviewDto>> readPeriods({
    required String workspaceId,
    bool includeClosed = true,
  }) async {
    try {
      final response = await _gateway.callRpc(
        'workspace_finance_periods',
        <String, Object?>{
          'p_workspace_id': workspaceId,
          'p_include_closed': includeClosed,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<FinancePeriodOverviewDto>(
          _parsePeriodOverview(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<FinancePeriodOverviewDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<FinancePeriodOverviewDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Abrechnungsperioden konnten nicht geladen werden.',
      );
    }
  }

  @override
  Future<FinanceRepositoryResult<FinancePeriodDto>> openPeriod(
    OpenFinancePeriodCommand command,
  ) async {
    if (command.periodMonth < 1 || command.periodMonth > 12) {
      return const FinanceRepositoryFailure<FinancePeriodDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message: 'Ein Monat liegt zwischen 1 und 12.',
        field: 'period_month',
      );
    }
    try {
      final response = await _gateway.callRpc(
        'open_finance_period',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_fiscal_year': command.fiscalYear,
          'p_period_month': command.periodMonth,
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_reason': command.context.reason,
        },
      );
      return _periodResult(response);
    } catch (_) {
      return const FinanceRepositoryFailure<FinancePeriodDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Periode konnte nicht geöffnet werden.',
      );
    }
  }

  @override
  Future<FinanceRepositoryResult<FinancePeriodDto>> transitionPeriod(
    TransitionFinancePeriodCommand command,
  ) async {
    if (command.targetState == FinancePeriodState.unknown) {
      return const FinanceRepositoryFailure<FinancePeriodDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Einen Status, den dieser Stand nicht kennt, kann er nicht setzen. '
            'Er kann nur von einem neueren Server stammen.',
        field: 'target_status',
      );
    }
    // The server refuses a blank reason on reopening, and a blank reason is
    // also refused by the shared gate as a *whole* — `btrim('')` has length
    // zero, which is not between 1 and 2000. So an empty string must never be
    // sent; null is the way to say "no reason".
    if (command.targetState == FinancePeriodState.open &&
        (command.context.reason == null ||
            command.context.reason!.trim().isEmpty)) {
      return const FinanceRepositoryFailure<FinancePeriodDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Eine geschlossene Periode wieder zu öffnen braucht eine '
            'Begründung — sie steht anschließend im Protokoll.',
        field: 'reason',
      );
    }
    try {
      final response = await _gateway.callRpc(
        'transition_finance_period_status',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_period_id': command.periodId,
          'p_target_status': financePeriodStateKey(command.targetState),
          'p_expected_version': command.expectedVersion,
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_reason': command.context.reason,
        },
      );
      return _periodResult(response);
    } catch (_) {
      return const FinanceRepositoryFailure<FinancePeriodDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Der Periodenstatus konnte nicht geändert werden.',
      );
    }
  }

  @override
  Future<FinanceRepositoryResult<FinanceLedgerOverviewDto>> readEntries({
    required String workspaceId,
    required String propertyId,
    String? periodId,
    String? accountId,
    int limit = 100,
  }) async {
    try {
      final response = await _gateway.callRpc(
        'property_finance_ledger_entries',
        <String, Object?>{
          'p_workspace_id': workspaceId,
          'p_property_id': propertyId,
          'p_period_id': periodId,
          'p_account_id': accountId,
          'p_limit': limit,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<FinanceLedgerOverviewDto>(
          _parseLedgerOverview(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<FinanceLedgerOverviewDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<FinanceLedgerOverviewDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Buchungen konnten nicht geladen werden.',
      );
    }
  }

  @override
  Future<FinanceRepositoryResult<FinanceLedgerEntryDto>> recordEntry(
    RecordFinanceLedgerEntryCommand command,
  ) async {
    if (!command.amount.isFinite) {
      return const FinanceRepositoryFailure<FinanceLedgerEntryDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message: 'Das ist keine Zahl, mit der gebucht werden kann.',
        field: 'amount',
      );
    }
    if (command.amount == 0) {
      return const FinanceRepositoryFailure<FinanceLedgerEntryDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Eine Buchung über null verändert nichts und lässt sich '
            'anschließend nicht mehr entfernen.',
        field: 'amount',
      );
    }
    if (!_currencyPattern.hasMatch(command.currencyCode)) {
      return const FinanceRepositoryFailure<FinanceLedgerEntryDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message: 'Eine dreibuchstabige ISO-Währung ist erforderlich, z. B. EUR.',
        field: 'currency_code',
      );
    }
    try {
      final response = await _gateway.callRpc(
        'record_finance_ledger_entry',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_property_id': command.propertyId,
          'p_account_id': command.accountId,
          'p_period_id': command.periodId,
          'p_booked_on': _formatDate(command.bookedOn),
          'p_amount': command.amount,
          'p_currency_code': command.currencyCode,
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_description': command.description,
          'p_unit_id': command.unitId,
          'p_lease_id': command.leaseId,
          'p_reason': command.context.reason,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<FinanceLedgerEntryDto>(
          _parseEntry(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<FinanceLedgerEntryDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<FinanceLedgerEntryDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Buchung konnte nicht erfasst werden.',
      );
    }
  }

  FinanceRepositoryResult<FinancePeriodDto> _periodResult(Object? response) {
    final payload = _asMap(response);
    final ok = payload['ok'];
    if (ok == true) {
      return FinanceRepositorySuccess<FinancePeriodDto>(
        _parsePeriod(_asMap(payload['entity'])),
      );
    }
    if (ok != false) {
      throw const FormatException('Missing RPC result status.');
    }
    return _mapFailure<FinancePeriodDto>(_asMap(payload['error']));
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

/// The server speaks English; the form speaks German. The refusals this
/// surface actually meets are few and known, so they are translated. Anything
/// else comes through verbatim — an untranslated sentence is better than a
/// wrong one.
String? _germanFor(String message) => switch (message) {
  'That period already exists' =>
    'Diese Periode gibt es bereits. Sie steht in der Liste — dort lässt sie '
        'sich auswählen.',
  'The period is closed and cannot receive entries' =>
    'Diese Periode ist abgeschlossen und nimmt keine Buchungen mehr auf.',
  'The period was changed by someone else' =>
    'Die Periode wurde zwischenzeitlich von jemand anderem geändert. Bitte '
        'die Liste neu laden und erneut versuchen.',
  'The period already has that status' =>
    'Die Periode hat diesen Status bereits.',
  'Reopening a closed period requires a reason' =>
    'Eine geschlossene Periode wieder zu öffnen braucht eine Begründung.',
  'Closing and reopening periods is not permitted' =>
    'Zum Abschließen und Wiederöffnen von Perioden fehlt die Berechtigung '
        '(finance.close) — sie ist bewusst von der Buchungsberechtigung '
        'getrennt.',
  'Finance management is not permitted' =>
    'Für Buchungen fehlt die Berechtigung zur Finanzverwaltung.',
  'Account not found or retired' =>
    'Diese Kostenart gibt es nicht oder sie ist stillgelegt.',
  'Property not found' => 'Dieses Objekt gibt es nicht (mehr).',
  'Period not found' => 'Diese Periode gibt es nicht (mehr).',
  'The unit does not belong to this property' =>
    'Diese Einheit gehört nicht zu diesem Objekt.',
  'The lease does not belong to this property' =>
    'Dieser Mietvertrag gehört nicht zu diesem Objekt.',
  _ => null,
};

FinanceRepositoryFailure<T> _mapFailure<T>(Map<String, dynamic> error) {
  final code = error['code'] is String ? error['code'] as String : '';
  final raw = error['message'] is String
      ? error['message'] as String
      : 'Die Anfrage wurde abgelehnt.';
  // The booking-date refusal is composed by the server from two dates, so it
  // cannot be matched exactly. It is passed through: it names both dates,
  // which is the part that helps.
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

FinancePeriodOverviewDto _parsePeriodOverview(Map<String, dynamic> entity) {
  final rows = entity['periods'];
  if (rows is! List) {
    throw const FormatException('Expected a period list.');
  }
  return FinancePeriodOverviewDto(
    periods: rows
        .map((row) => _parsePeriod(_asMap(row)))
        .toList(growable: false),
    // Read, never counted from the list.
    openCount: _requiredInt(entity, 'open_count'),
    totalCount: _requiredInt(entity, 'total_count'),
  );
}

FinancePeriodDto _parsePeriod(Map<String, dynamic> row) {
  final rawState = _requiredString(row, 'status');
  final state = financePeriodStateFromKey(rawState);
  return FinancePeriodDto(
    id: _requiredString(row, 'id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    fiscalYear: _requiredInt(row, 'fiscal_year'),
    periodMonth: _requiredInt(row, 'period_month'),
    state: state,
    version: _requiredInt(row, 'version'),
    // The command's own snapshot carries no count — it answers "what did I
    // just write", not "how full is this period". Absent reads as zero only
    // because a period the command just opened is empty by construction.
    entryCount: _optionalInt(row['entry_count']) ?? 0,
    closedAt: _optionalTimestamp(row['closed_at']),
    closedBy: _optionalString(row['closed_by']),
    rawStateKey: state == FinancePeriodState.unknown ? rawState : null,
  );
}

FinanceLedgerOverviewDto _parseLedgerOverview(Map<String, dynamic> entity) {
  final rows = entity['entries'];
  if (rows is! List) {
    throw const FormatException('Expected an entry list.');
  }
  return FinanceLedgerOverviewDto(
    entries: rows.map((row) => _parseEntry(_asMap(row))).toList(growable: false),
    returnedCount: _requiredInt(entity, 'returned_count'),
    totalCount: _requiredInt(entity, 'total_count'),
    limit: _requiredInt(entity, 'limit'),
  );
}

FinanceLedgerEntryDto _parseEntry(Map<String, dynamic> row) {
  return FinanceLedgerEntryDto(
    id: _requiredString(row, 'id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    propertyId: _requiredString(row, 'property_id'),
    accountId: _requiredString(row, 'account_id'),
    periodId: _requiredString(row, 'period_id'),
    bookedOn: _requiredDate(row, 'booked_on'),
    amount: _requiredNum(row, 'amount'),
    currencyCode: _requiredString(row, 'currency_code'),
    description: _optionalString(row['description']),
    source: _optionalString(row['source']),
    unitId: _optionalString(row['unit_id']),
    unitCode: _optionalString(row['unit_code']),
    accountCode: _optionalString(row['account_code']),
    accountName: _optionalString(row['account_name']),
    accountType: _optionalString(row['account_type']),
    periodFiscalYear: _optionalInt(row['period_fiscal_year']),
    periodMonth: _optionalInt(row['period_month']),
    periodStatus: _optionalString(row['period_status']),
    // Tri-state on purpose. Null is "nobody has classified this cost type",
    // which is not false, and the surface must not collapse them.
    allocatable: row['allocatable'] is bool ? row['allocatable'] as bool : null,
    settlementPrinciple: _optionalString(row['settlement_principle']),
    version: _requiredInt(row, 'version'),
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
  final value = row[key];
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      // Dates only: a UTC offset must not move a booking across a midnight
      // into a neighbouring period.
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
  }
  throw FormatException('Missing date field: $key');
}

DateTime? _optionalTimestamp(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  throw const FormatException('Expected a timestamp string.');
}

num _requiredNum(Map<String, dynamic> row, String key) {
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

int _requiredInt(Map<String, dynamic> row, String key) {
  final value = _optionalInt(row[key]);
  if (value == null) {
    throw FormatException('Missing integer field: $key');
  }
  return value;
}
