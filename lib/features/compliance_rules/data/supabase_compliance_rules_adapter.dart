/// Supabase adapter for the legal rule layer (`COMPLIANCE-RULES-01`, V-4).
///
/// Reads and writes go through the same envelope as the rest of the product —
/// `{ok, entity}` on success, `{ok, error{code}}` on refusal. Nothing here
/// computes: the server decides which rules were in force on a date, and this
/// class parses the answer.
///
/// **The dates go out as calendar days, not instants.** A statute takes effect
/// on a day, and converting through UTC would move `2025-01-01` to
/// `2024-12-31` for anyone west of Greenwich — which would silently apply last
/// year's law to the first day of the year.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/compliance_rules_repository.dart';
import '../domain/compliance_rule_dto.dart';

abstract interface class ComplianceSupabaseGateway {
  Future<Object?> callRpc(String function, Map<String, Object?> parameters);
}

class SupabaseComplianceGateway implements ComplianceSupabaseGateway {
  const SupabaseComplianceGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) {
    return _client.rpc(function, params: parameters);
  }
}

class SupabaseComplianceRulesAdapter implements ComplianceRulesPort {
  SupabaseComplianceRulesAdapter({required SupabaseClient client})
    : _gateway = SupabaseComplianceGateway(client);

  SupabaseComplianceRulesAdapter.withGateway(this._gateway);

  final ComplianceSupabaseGateway _gateway;

  @override
  Future<ComplianceRulesResult<ComplianceRuleSetDto>> readAsOf(
    ComplianceRulesQuery query,
  ) async {
    try {
      final response = await _gateway.callRpc(
        'compliance_rules_as_of',
        <String, Object?>{
          'p_workspace_id': query.workspaceId,
          'p_as_of': _dateToWire(query.asOfDate),
          'p_rule_key': query.ruleKey,
          'p_jurisdiction': query.jurisdiction,
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return ComplianceRulesSuccess<ComplianceRuleSetDto>(
          _parseRuleSet(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure<ComplianceRuleSetDto>(_asMap(payload['error']));
    } catch (_) {
      return const ComplianceRulesFailure<ComplianceRuleSetDto>(
        kind: ComplianceRulesFailureKind.infrastructureFailure,
        message: 'Die Rechtsregeln konnten nicht geladen werden.',
      );
    }
  }

  @override
  Future<ComplianceRulesResult<ComplianceRuleDto>> upsert(
    UpsertComplianceRuleCommand command,
  ) async {
    try {
      final response = await _gateway.callRpc(
        'upsert_compliance_rule',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_rule_key': command.ruleKey,
          'p_valid_from': _dateToWire(command.validFrom),
          'p_value': command.value,
          'p_source_reference': command.sourceReference,
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_rule_id': command.ruleId,
          'p_expected_version': command.expectedVersion,
          'p_valid_to': _dateToWire(command.validTo),
          'p_unit': command.unit,
          'p_note': command.note,
          'p_jurisdiction': command.jurisdiction,
          'p_decision_support': command.decisionSupport,
          'p_reason': command.context.reason,
        },
      );
      return _parseCommand(response);
    } catch (_) {
      return const ComplianceRulesFailure<ComplianceRuleDto>(
        kind: ComplianceRulesFailureKind.infrastructureFailure,
        message: 'Die Regel konnte nicht gespeichert werden.',
      );
    }
  }

  @override
  Future<ComplianceRulesResult<ComplianceRuleDto>> verify(
    VerifyComplianceRuleCommand command,
  ) async {
    try {
      final response = await _gateway.callRpc(
        'verify_compliance_rule',
        <String, Object?>{
          'p_workspace_id': command.context.workspaceId,
          'p_rule_id': command.ruleId,
          'p_expected_version': command.expectedVersion,
          'p_verified': command.verified,
          'p_mutation_id': command.context.mutationId,
          'p_correlation_id': command.context.correlationId,
          'p_verification_note': command.verificationNote,
          'p_reason': command.context.reason,
        },
      );
      return _parseCommand(response);
    } catch (_) {
      return const ComplianceRulesFailure<ComplianceRuleDto>(
        kind: ComplianceRulesFailureKind.infrastructureFailure,
        message: 'Die Bestätigung konnte nicht gespeichert werden.',
      );
    }
  }

  ComplianceRulesResult<ComplianceRuleDto> _parseCommand(Object? response) {
    final payload = _asMap(response);
    final ok = payload['ok'];
    if (ok == true) {
      return ComplianceRulesSuccess<ComplianceRuleDto>(
        _parseRule(_asMap(payload['entity'])),
      );
    }
    if (ok != false) {
      throw const FormatException('Missing RPC result status.');
    }
    return _mapFailure<ComplianceRuleDto>(_asMap(payload['error']));
  }
}

ComplianceRulesFailure<T> _mapFailure<T>(Map<String, dynamic> error) {
  final code = error['code'] is String ? error['code'] as String : '';
  final message = error['message'] is String
      ? error['message'] as String
      : 'Die Anfrage wurde abgelehnt.';
  final field = error['field'] is String ? error['field'] as String : null;
  return switch (code) {
    'not_found' => ComplianceRulesFailure<T>(
      kind: ComplianceRulesFailureKind.notFound,
      message: message,
      field: field,
    ),
    'forbidden' => ComplianceRulesFailure<T>(
      kind: ComplianceRulesFailureKind.forbidden,
      message: message,
      field: field,
    ),
    'validation_failed' => ComplianceRulesFailure<T>(
      kind: ComplianceRulesFailureKind.validationFailed,
      message: message,
      field: field,
    ),
    // Its own kind rather than a generic conflict: the form's answer is to
    // change the period, not to reload and retry.
    'dependency_conflict' => ComplianceRulesFailure<T>(
      kind: ComplianceRulesFailureKind.overlap,
      message: message,
      field: field,
    ),
    'version_conflict' => ComplianceRulesFailure<T>(
      kind: ComplianceRulesFailureKind.versionConflict,
      message: message,
      field: field,
      versionConflict: ComplianceRuleVersionConflict(
        expectedVersion: _requiredInt(error, 'expected_version'),
        actualVersion: _requiredInt(error, 'actual_version'),
        currentRule: error['current_entity'] is Map
            ? _parseRule(_asMap(error['current_entity']))
            : null,
      ),
    ),
    'mutation_conflict' => ComplianceRulesFailure<T>(
      kind: ComplianceRulesFailureKind.mutationConflict,
      message: message,
      field: field,
    ),
    'in_progress' => ComplianceRulesFailure<T>(
      kind: ComplianceRulesFailureKind.mutationInProgress,
      message: message,
      field: field,
    ),
    _ => ComplianceRulesFailure<T>(
      kind: ComplianceRulesFailureKind.infrastructureFailure,
      message: message,
      field: field,
    ),
  };
}

ComplianceRuleSetDto _parseRuleSet(Map<String, dynamic> entity) {
  final raw = entity['rules'];
  if (raw is! List) {
    throw const FormatException('Expected a rule list.');
  }
  return ComplianceRuleSetDto(
    asOfDate: _requiredDate(entity, 'as_of_date'),
    jurisdiction: _requiredString(entity, 'jurisdiction'),
    rules: raw
        .map((row) => _parseRule(_asMap(row)))
        .toList(growable: false),
    // Read, never counted from the list. The server counted over the whole
    // matched set, and re-deriving here would tie the number to whatever the
    // list happens to hold.
    unverifiedCount: _optionalInt(entity['unverified_count']) ?? 0,
    decisionSupportCount: _optionalInt(entity['decision_support_count']) ?? 0,
  );
}

ComplianceRuleDto _parseRule(Map<String, dynamic> row) {
  final confidenceKey = _requiredString(row, 'confidence');
  final confidence = complianceRuleConfidenceFromKey(confidenceKey);
  return ComplianceRuleDto(
    id: _requiredString(row, 'id'),
    workspaceId: _requiredString(row, 'workspace_id'),
    ruleKey: _requiredString(row, 'rule_key'),
    jurisdiction: _requiredString(row, 'jurisdiction'),
    validFrom: _requiredDate(row, 'valid_from'),
    validTo: _optionalDate(row['valid_to']),
    value: row['value'],
    unit: _optionalString(row['unit']),
    sourceReference: _requiredString(row, 'source_reference'),
    note: _optionalString(row['note']),
    confidence: confidence,
    verifiedBy: _optionalString(row['verified_by']),
    verifiedAt: _optionalDate(row['verified_at']),
    verificationNote: _optionalString(row['verification_note']),
    version: _requiredInt(row, 'version'),
    rawConfidenceKey: confidence == ComplianceRuleConfidence.unknown
        ? confidenceKey
        : null,
  );
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, dynamic entry) => MapEntry(key.toString(), entry),
    );
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
  final value = _optionalInt(row[key]);
  if (value == null) {
    throw FormatException('Missing integer field: $key');
  }
  return value;
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
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  throw const FormatException('Expected a date.');
}

/// A calendar day, as the caller supplied it.
///
/// No UTC conversion: a rule taking effect on `2025-01-01` means the first of
/// January in the caller's terms, and normalising through UTC would shift it to
/// 31 December for anyone west of Greenwich — applying last year's law to the
/// first day of the year.
String? _dateToWire(DateTime? value) {
  if (value == null) {
    return null;
  }
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
