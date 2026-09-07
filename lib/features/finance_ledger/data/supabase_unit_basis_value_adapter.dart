/// Supabase adapter for the per-unit distribution basis values
/// (`UNIT-BASIS-VALUES-01`, P-2c).
///
/// Nothing here decides what a figure means. Whether a basis resolves, what it
/// totals, how many units are missing a value and whether the units agree on a
/// convention are all the server's answers — including the verdict, which is
/// the same one the allocation keys receive so the two surfaces cannot
/// disagree about whether a basis is usable.
///
/// This layer refuses exactly two things before the round trip, and both are
/// refused server-side as well: a basis this schema does not store per unit,
/// and a figure with no convention. The second is not a formatting rule — no
/// counting convention is agreed for any of these three bases, so a figure
/// that does not say how it was measured cannot be checked by anyone and
/// cannot be added to its neighbour.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/finance_ledger_port.dart';
import '../domain/cost_pool_dto.dart';
import 'supabase_finance_ledger_adapter.dart' show FinanceSupabaseGateway;

class SupabaseUnitBasisValueAdapter implements UnitBasisValuesPort {
  SupabaseUnitBasisValueAdapter({required SupabaseClient client})
    : _gateway = _DirectGateway(client);

  SupabaseUnitBasisValueAdapter.withGateway(this._gateway);

  final FinanceSupabaseGateway _gateway;

  @override
  Future<FinanceRepositoryResult<UnitBasisOverviewDto>> readBasisValues({
    required String workspaceId,
    required String propertyId,
    required AllocationBasis basis,
    DateTime? asOf,
  }) async {
    if (!allocationBasisIsStoredPerUnit(basis)) {
      return const FinanceRepositoryFailure<UnitBasisOverviewDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Nur fester Anteil, Personenzahl und Miteigentumsanteil werden je '
            'Einheit erfasst. Die Fläche steht an der Einheit selbst, die '
            'Anzahl der Einheiten wird gezählt.',
        field: 'basis',
      );
    }
    try {
      final response = await _gateway.callRpc(
        'unit_basis_values_as_of',
        <String, Object?>{
          'p_workspace_id': workspaceId,
          'p_property_id': propertyId,
          'p_basis': allocationBasisKey(basis),
          'p_as_of': asOf == null ? null : _formatDate(asOf),
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<UnitBasisOverviewDto>(
          _parseOverview(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<UnitBasisOverviewDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<UnitBasisOverviewDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Basiswerte konnten nicht geladen werden.',
      );
    }
  }

  @override
  Future<FinanceRepositoryResult<UnitBasisValueDto>> upsertBasisValue(
    UpsertUnitBasisValueCommand command,
  ) async {
    if (!allocationBasisIsStoredPerUnit(command.basis)) {
      return const FinanceRepositoryFailure<UnitBasisValueDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Dieser Maßstab wird nicht je Einheit erfasst. Eine zweite Kopie '
            'könnte der bestehenden Angabe nur widersprechen.',
        field: 'basis',
      );
    }
    // Refused rather than defaulted. For none of these three bases is a
    // counting rule agreed, so the convention is part of the figure.
    if (command.convention.trim().isEmpty) {
      return const FinanceRepositoryFailure<UnitBasisValueDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Bitte angeben, wie diese Zahl ermittelt wurde. Für diesen Maßstab '
            'ist keine Zählregel vereinbart, deshalb gehört die Konvention zur '
            'Zahl.',
        field: 'convention',
      );
    }
    // Checked before `< 0`, because NaN fails every comparison: `NaN < 0` is
    // false, so a sign test alone lets through the one value that makes every
    // share derived from it meaningless. Without this the figure reaches
    // `jsonEncode`, which throws, and the blanket catch below reports a pure
    // input error as a transport failure.
    if (!command.value.isFinite) {
      return const FinanceRepositoryFailure<UnitBasisValueDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Das ist keine Zahl, mit der gerechnet werden kann. Bitte einen '
            'endlichen Wert eingeben.',
        field: 'value',
      );
    }
    if (command.value < 0) {
      return const FinanceRepositoryFailure<UnitBasisValueDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Ein negativer Anteil ist keine kleinere Zahl, sondern eine '
            'falsche. Null ist erlaubt und heißt: die Angabe ist null — nicht '
            'dasselbe wie nicht erfasst.',
        field: 'value',
      );
    }
    try {
      final response = await _gateway.callRpc(
        'upsert_unit_basis_value',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_unit_id': command.unitId,
          'p_basis': allocationBasisKey(command.basis),
          'p_value': command.value,
          'p_convention': command.convention,
          'p_valid_from': _formatDate(command.validFrom),
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_value_id': command.valueId,
          'p_expected_version': command.expectedVersion,
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
        return FinanceRepositorySuccess<UnitBasisValueDto>(
          _parseValue(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<UnitBasisValueDto>(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<UnitBasisValueDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Der Basiswert konnte nicht gespeichert werden.',
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

UnitBasisOverviewDto _parseOverview(Map<String, dynamic> entity) {
  final rows = entity['units'];
  if (rows is! List) {
    throw const FormatException('Expected a unit list.');
  }
  final rawBasis = _requiredString(entity, 'basis');
  final basis = allocationBasisFromKey(rawBasis);
  final rawResolution = entity['resolution'];
  return UnitBasisOverviewDto(
    asOfDate: _requiredDate(entity, 'as_of_date'),
    basis: basis,
    rawBasisKey: basis == AllocationBasis.unknown ? rawBasis : null,
    units: rows.map((row) => _parseRow(_asMap(row))).toList(growable: false),
    // Absent must not read as resolvable. This read exists to say whether the
    // basis can be used, so a payload that did not answer is an unresolved
    // basis with an unstated reason, never a resolved one.
    resolution: rawResolution is Map
        ? _parseResolution(_asMap(rawResolution))
        : const AllocationBasisResolutionDto(
            resolvable: false,
            reason: AllocationUnresolvableReason.notEvaluated,
          ),
  );
}

UnitBasisRowDto _parseRow(Map<String, dynamic> row) {
  final rawValue = row['value'];
  return UnitBasisRowDto(
    unitId: _requiredString(row, 'unit_id'),
    unitCode: _requiredString(row, 'unit_code'),
    areaSqm: _optionalNum(row['area_sqm']),
    // Null stays null. A unit nobody has recorded and a unit recorded as zero
    // mean different things, and collapsing them would make the missing count
    // unexplainable.
    value: rawValue is Map ? _parseValue(_asMap(rawValue)) : null,
  );
}

UnitBasisValueDto _parseValue(Map<String, dynamic> row) {
  return UnitBasisValueDto(
    id: _requiredString(row, 'id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    unitId: _requiredString(row, 'unit_id'),
    basis: allocationBasisFromKey(_requiredString(row, 'basis')),
    value: _requiredNum(row, 'value'),
    convention: _requiredString(row, 'convention'),
    validFrom: _requiredDate(row, 'valid_from'),
    validTo: _optionalDate(row['valid_to']),
    note: _optionalString(row['note']),
    version: _requiredInt(row, 'version'),
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
    convention: _optionalString(row['convention']),
    conventionCount: _optionalInt(row['convention_count']),
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
    // validity boundary across a midnight, which is the day a figure takes
    // effect.
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

num _requiredNum(Map<String, dynamic> row, String key) {
  final value = _optionalNum(row[key]);
  if (value == null) {
    throw FormatException('Missing numeric field: $key');
  }
  return value;
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
