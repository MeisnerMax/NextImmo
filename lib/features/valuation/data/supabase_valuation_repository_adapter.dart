import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/valuation_repository.dart';
import '../domain/valuation_case_dto.dart';
import '../domain/valuation_method.dart';

/// The single seam between the valuation ports and the Supabase SDK. Reads go
/// through PostgREST (RLS-authorized on `valuation.read`), every mutation goes
/// through an RPC — there is no direct-DML path, and the server grants none.
abstract interface class ValuationSupabaseGateway {
  String? get currentUserId;

  Future<List<Map<String, dynamic>>> listValuationCases({
    required String workspaceId,
    required String? propertyId,
    required String? scenarioId,
    required String? kind,
    required String? status,
    required bool includeArchived,
    required ValuationKeysetCursor? after,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> getValuationCase({
    required String workspaceId,
    required String valuationCaseId,
  });

  Future<List<Map<String, dynamic>>> listFactors({
    required String workspaceId,
    required String valuationCaseId,
  });

  Future<List<Map<String, dynamic>>> listMethodResults({
    required String workspaceId,
    required String valuationCaseId,
  });

  Future<List<Map<String, dynamic>>> getOpinion({
    required String workspaceId,
    required String valuationCaseId,
  });

  Future<Object?> callRpc(String function, Map<String, Object?> parameters);
}

class SupabaseValuationGateway implements ValuationSupabaseGateway {
  SupabaseValuationGateway(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> listValuationCases({
    required String workspaceId,
    required String? propertyId,
    required String? scenarioId,
    required String? kind,
    required String? status,
    required bool includeArchived,
    required ValuationKeysetCursor? after,
    required int limit,
  }) async {
    var query = _client
        .from('valuation_cases')
        .select()
        .eq('workspace_id', workspaceId);
    if (propertyId != null) {
      query = query.eq('property_id', propertyId);
    }
    if (scenarioId != null) {
      query = query.eq('scenario_id', scenarioId);
    }
    if (kind != null) {
      query = query.eq('kind', kind);
    }
    if (status != null) {
      query = query.eq('status', status);
    }
    if (!includeArchived) {
      query = query.neq('status', 'archived');
    }
    if (after != null) {
      query = query.or(_keysetFilter('updated_at', after));
    }
    final rows = await query
        .order('updated_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getValuationCase({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    final rows = await _client
        .from('valuation_cases')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('id', valuationCaseId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listFactors({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    final rows = await _client
        .from('valuation_factors')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('valuation_case_id', valuationCaseId)
        .order('factor_id');
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listMethodResults({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    final rows = await _client
        .from('valuation_method_results')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('valuation_case_id', valuationCaseId)
        .order('method');
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getOpinion({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    final rows = await _client
        .from('market_value_opinions')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('valuation_case_id', valuationCaseId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) {
    return _client.rpc(function, params: parameters);
  }

  /// Descending composite keyset: strictly older, or the same instant with a
  /// smaller id. The tie-break matters because `now()` is transaction-bound, so
  /// rows written by one command share a timestamp.
  static String _keysetFilter(String column, ValuationKeysetCursor cursor) {
    final stamp = cursor.timestamp.toUtc().toIso8601String();
    return '$column.lt.$stamp,and($column.eq.$stamp,id.lt.${cursor.id})';
  }
}

/// Supabase-backed implementation of the three P2-D07 valuation ports.
class SupabaseValuationRepositoryAdapter
    implements ValuationCaseRepository, ValuationFactorPort, ValuationReportPort {
  SupabaseValuationRepositoryAdapter({required SupabaseClient client})
    : _gateway = SupabaseValuationGateway(client);

  SupabaseValuationRepositoryAdapter.withGateway(ValuationSupabaseGateway gateway)
    : _gateway = gateway;

  final ValuationSupabaseGateway _gateway;

  // ---------------------------------------------------------------------------
  // ValuationCaseRepository
  // ---------------------------------------------------------------------------

  @override
  Future<ValuationRepositoryResult<ValuationPageResult<ValuationCaseDto>>>
  searchValuationCases(ValuationCaseListQuery query) async {
    try {
      final rows = await _gateway.listValuationCases(
        workspaceId: query.workspaceId,
        propertyId: query.propertyId,
        scenarioId: query.scenarioId,
        kind: query.kind?.wireName,
        status: query.status?.wireName,
        includeArchived: query.includeArchived,
        after: ValuationKeysetCursor.decode(query.page.cursor),
        limit: query.page.limit,
      );
      final cases = rows.map(_parseCase).toList(growable: false);
      for (final entry in cases) {
        _requireWorkspace(entry.workspaceId, query.workspaceId);
      }
      final nextCursor = cases.length < query.page.limit
          ? null
          : ValuationKeysetCursor(
              timestamp: cases.last.updatedAt,
              id: cases.last.id,
            ).encode();
      return ValuationRepositorySuccess(
        ValuationPageResult(items: cases, nextCursor: nextCursor),
      );
    } catch (_) {
      return _infrastructureFailure<ValuationPageResult<ValuationCaseDto>>();
    }
  }

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> getValuationCaseById({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    try {
      final rows = await _gateway.getValuationCase(
        workspaceId: workspaceId,
        valuationCaseId: valuationCaseId,
      );
      if (rows.isEmpty) {
        return const ValuationRepositoryFailure(
          kind: ValuationRepositoryFailureKind.notFound,
          message: 'Bewertungsfall nicht gefunden.',
        );
      }
      final valuationCase = _parseCase(rows.first);
      _requireWorkspace(valuationCase.workspaceId, workspaceId);

      final factorRows = await _gateway.listFactors(
        workspaceId: workspaceId,
        valuationCaseId: valuationCaseId,
      );
      final report = await _readReport(
        workspaceId: workspaceId,
        valuationCaseId: valuationCaseId,
      );

      return ValuationRepositorySuccess(
        ValuationCaseDetail(
          valuationCase: valuationCase,
          factors: factorRows.map(_parseFactor).toList(growable: false),
          report: report,
        ),
      );
    } catch (_) {
      return _infrastructureFailure<ValuationCaseDetail>();
    }
  }

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> createValuationCase(
    CreateValuationCaseCommand command,
  ) {
    return _dispatchDetail(
      function: 'create_valuation_case',
      workspaceId: command.context.workspaceId,
      parameters: {
        'p_workspace_id': command.context.workspaceId,
        'p_property_id': command.propertyId,
        'p_title': command.title,
        'p_kind': command.kind.wireName,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_scenario_id': command.scenarioId,
        if (command.dcfTerminal != null)
          'p_dcf_terminal': command.dcfTerminal!.wireName,
        'p_enabled_methods': command.enabledMethods
            ?.map((m) => m.wireName)
            .toList(growable: false),
        'p_weight_overrides': _weightPayload(command.weightOverrides),
        if (command.minimumComparables != null)
          'p_minimum_comparables': command.minimumComparables,
        'p_factors':
            command.factors.map(_factorPayload).toList(growable: false),
        'p_reason': command.context.reason,
      },
    );
  }

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> updateValuationCase(
    UpdateValuationCaseCommand command,
  ) {
    return _dispatchDetail(
      function: 'update_valuation_case',
      workspaceId: command.context.workspaceId,
      parameters: {
        'p_workspace_id': command.context.workspaceId,
        'p_valuation_case_id': command.valuationCaseId,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_title': command.title,
        'p_kind': command.kind?.wireName,
        'p_scenario_id': command.scenarioId,
        'p_clear_scenario_id': command.clearScenarioId,
        'p_dcf_terminal': command.dcfTerminal?.wireName,
        'p_enabled_methods': command.enabledMethods
            ?.map((m) => m.wireName)
            .toList(growable: false),
        'p_weight_overrides': command.weightOverrides == null
            ? null
            : _weightPayload(command.weightOverrides!),
        'p_minimum_comparables': command.minimumComparables,
        'p_reason': command.context.reason,
      },
    );
  }

  @override
  Future<ValuationRepositoryResult<ValuationCaseDto>>
  transitionValuationCaseStatus(
    TransitionValuationCaseStatusCommand command,
  ) {
    return _dispatch<ValuationCaseDto>(
      function: 'transition_valuation_case_status',
      workspaceId: command.context.workspaceId,
      parameters: {
        'p_workspace_id': command.context.workspaceId,
        'p_valuation_case_id': command.valuationCaseId,
        'p_expected_version': command.expectedVersion,
        'p_target_status': command.targetStatus.wireName,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) {
        final parsed = _parseCase(entity);
        _requireWorkspace(parsed.workspaceId, command.context.workspaceId);
        return parsed;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // ValuationFactorPort
  // ---------------------------------------------------------------------------

  @override
  Future<ValuationRepositoryResult<List<ValuationFactorDto>>> listFactors({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    try {
      final rows = await _gateway.listFactors(
        workspaceId: workspaceId,
        valuationCaseId: valuationCaseId,
      );
      return ValuationRepositorySuccess(
        rows.map(_parseFactor).toList(growable: false),
      );
    } catch (_) {
      return _infrastructureFailure<List<ValuationFactorDto>>();
    }
  }

  @override
  Future<ValuationRepositoryResult<List<ValuationFactorDto>>> upsertFactors(
    UpsertValuationFactorsCommand command,
  ) async {
    final result = await _dispatchDetail(
      function: 'upsert_valuation_factors',
      workspaceId: command.context.workspaceId,
      parameters: {
        'p_workspace_id': command.context.workspaceId,
        'p_valuation_case_id': command.valuationCaseId,
        'p_expected_version': command.expectedVersion,
        'p_factors':
            command.factors.map(_factorPayload).toList(growable: false),
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_remove_factor_ids': command.removeFactorIds,
        'p_reason': command.context.reason,
      },
    );
    return switch (result) {
      ValuationRepositorySuccess(:final value) => ValuationRepositorySuccess(
        value.factors,
      ),
      ValuationRepositoryFailure(
        :final kind,
        :final message,
        :final versionConflict,
      ) =>
        ValuationRepositoryFailure<List<ValuationFactorDto>>(
          kind: kind,
          message: message,
          versionConflict: versionConflict,
        ),
    };
  }

  // ---------------------------------------------------------------------------
  // ValuationReportPort
  // ---------------------------------------------------------------------------

  @override
  Future<ValuationRepositoryResult<ValuationReportSnapshot>> latestReport({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    try {
      final report = await _readReport(
        workspaceId: workspaceId,
        valuationCaseId: valuationCaseId,
      );
      if (report == null) {
        return const ValuationRepositoryFailure(
          kind: ValuationRepositoryFailureKind.notFound,
          message: 'Für diesen Bewertungsfall wurde noch kein Bericht erzeugt.',
        );
      }
      return ValuationRepositorySuccess(report);
    } catch (_) {
      return _infrastructureFailure<ValuationReportSnapshot>();
    }
  }

  @override
  Future<ValuationRepositoryResult<ValuationReportSnapshot>> publishReport(
    PublishValuationReportCommand command,
  ) {
    final caseId = command.valuationCaseId;
    final methodResults = command.report.methodResults.entries
        .map(
          (entry) => ValuationMethodResultDto.fromDomain(
            caseId: caseId,
            method: entry.key,
            result: entry.value,
          ).toJson(),
        )
        .toList(growable: false);

    return _dispatch<ValuationReportSnapshot>(
      function: 'publish_valuation_report',
      workspaceId: command.context.workspaceId,
      parameters: {
        'p_workspace_id': command.context.workspaceId,
        'p_valuation_case_id': caseId,
        'p_expected_version': command.expectedVersion,
        'p_method_results': methodResults,
        'p_opinion': MarketValueOpinionDto.fromDomain(
          caseId: caseId,
          opinion: command.report.opinion,
        ).toJson(),
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) => _parseReportEntity(entity, caseId),
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<ValuationReportSnapshot?> _readReport({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    final resultRows = await _gateway.listMethodResults(
      workspaceId: workspaceId,
      valuationCaseId: valuationCaseId,
    );
    if (resultRows.isEmpty) {
      return null;
    }
    final opinionRows = await _gateway.getOpinion(
      workspaceId: workspaceId,
      valuationCaseId: valuationCaseId,
    );
    return ValuationReportSnapshot(
      valuationCaseId: valuationCaseId,
      computedFromVersion:
          (resultRows.first['computed_from_version'] as num?)?.toInt() ?? 0,
      methodResults: resultRows
          .map(
            (row) =>
                ValuationMethodResultDto.fromJson(row) ??
                (throw const FormatException('Invalid method result row.')),
          )
          .toList(growable: false),
      opinion: opinionRows.isEmpty
          ? null
          : MarketValueOpinionDto.fromJson(opinionRows.first),
    );
  }

  Future<ValuationRepositoryResult<ValuationCaseDetail>> _dispatchDetail({
    required String function,
    required String workspaceId,
    required Map<String, Object?> parameters,
  }) {
    return _dispatch<ValuationCaseDetail>(
      function: function,
      workspaceId: workspaceId,
      parameters: parameters,
      parseEntity: (entity) {
        final valuationCase = _parseCase(entity);
        _requireWorkspace(valuationCase.workspaceId, workspaceId);
        final factors = (entity['factors'] as List? ?? const [])
            .whereType<Map>()
            .map((row) => _parseFactor(Map<String, dynamic>.from(row)))
            .toList(growable: false);
        return ValuationCaseDetail(
          valuationCase: valuationCase,
          factors: factors,
        );
      },
    );
  }

  Future<ValuationRepositoryResult<T>> _dispatch<T>({
    required String function,
    required String workspaceId,
    required Map<String, Object?> parameters,
    required T Function(Map<String, dynamic> entity) parseEntity,
  }) async {
    try {
      final response = await _gateway.callRpc(function, parameters);
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return ValuationRepositorySuccess<T>(
          parseEntity(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<T>(_asMap(payload['error']));
    } catch (_) {
      return _infrastructureFailure<T>();
    }
  }

  ValuationRepositoryFailure<T> _mapRpcFailure<T>(Map<String, dynamic> error) {
    final code = error['code'] is String ? error['code'] as String : '';
    // The server's own message is passed through: these are our controlled
    // strings, not arbitrary infrastructure text.
    final message = error['message'] is String
        ? error['message'] as String
        : 'Bewertungsbefehl fehlgeschlagen.';
    switch (code) {
      case 'not_found':
        return ValuationRepositoryFailure<T>(
          kind: ValuationRepositoryFailureKind.notFound,
          message: message,
        );
      case 'forbidden':
        return ValuationRepositoryFailure<T>(
          kind: ValuationRepositoryFailureKind.forbidden,
          message: message,
        );
      case 'validation_failed':
        return ValuationRepositoryFailure<T>(
          kind: ValuationRepositoryFailureKind.validationFailed,
          message: message,
        );
      case 'mutation_conflict':
        return ValuationRepositoryFailure<T>(
          kind: ValuationRepositoryFailureKind.mutationConflict,
          message: message,
        );
      case 'in_progress':
        return ValuationRepositoryFailure<T>(
          kind: ValuationRepositoryFailureKind.mutationInProgress,
          message: message,
        );
      // Kept distinct from `forbidden` all the way to the UI: the caller may
      // hold the permission — the record is closed (AGG-014).
      case 'approved_immutable':
        return ValuationRepositoryFailure<T>(
          kind: ValuationRepositoryFailureKind.approvedImmutable,
          message: message,
        );
      case 'version_conflict':
        final current = error['current_entity'];
        return ValuationRepositoryFailure<T>(
          kind: ValuationRepositoryFailureKind.versionConflict,
          message: message,
          versionConflict: ValuationVersionConflict(
            expectedVersion: _requiredInt(error, 'expected_version'),
            actualVersion: _requiredInt(error, 'actual_version'),
            currentCase: current is Map
                ? ValuationCaseDto.fromJson(Map<String, dynamic>.from(current))
                : null,
          ),
        );
      case 'infrastructure_failure':
      default:
        return _infrastructureFailure<T>();
    }
  }

  ValuationReportSnapshot _parseReportEntity(
    Map<String, dynamic> entity,
    String expectedCaseId,
  ) {
    final caseId = entity['valuation_case_id'] as String?;
    if (caseId != expectedCaseId) {
      throw const FormatException('Valuation report case mismatch.');
    }
    final results = (entity['method_results'] as List? ?? const [])
        .whereType<Map>()
        .map((row) {
          final json = Map<String, dynamic>.from(row)
            ..['valuation_case_id'] = caseId;
          return ValuationMethodResultDto.fromJson(json) ??
              (throw const FormatException('Invalid method result payload.'));
        })
        .toList(growable: false);
    final opinionRaw = entity['opinion'];
    return ValuationReportSnapshot(
      valuationCaseId: caseId!,
      computedFromVersion: _requiredInt(entity, 'computed_from_version'),
      methodResults: results,
      opinion: opinionRaw is Map
          ? MarketValueOpinionDto.fromJson(
              Map<String, dynamic>.from(opinionRaw)
                ..['valuation_case_id'] = caseId,
            )
          : null,
    );
  }

  ValuationCaseDto _parseCase(Map<String, dynamic> row) =>
      ValuationCaseDto.fromJson(row) ??
      (throw const FormatException('Invalid valuation case row.'));

  ValuationFactorDto _parseFactor(Map<String, dynamic> row) =>
      ValuationFactorDto.fromJson(row) ??
      (throw const FormatException('Invalid valuation factor row.'));

  static Map<String, Object?> _factorPayload(ValuationFactorDto factor) {
    final json = factor.toJson()..remove('valuation_case_id');
    return json;
  }

  static Map<String, Object?> _weightPayload(
    Map<ValuationMethodKind, double> weights,
  ) => <String, Object?>{
    for (final entry in weights.entries) entry.key.wireName: entry.value,
  };

  static ValuationRepositoryFailure<T> _infrastructureFailure<T>() =>
      ValuationRepositoryFailure<T>(
        kind: ValuationRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase-Bewertungsbefehl fehlgeschlagen.',
      );
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw const FormatException('Expected a JSON object.');
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('Missing integer field: $key');
}

/// Fail closed on a workspace mismatch: a row the server returned for another
/// workspace means the scope guard was bypassed somewhere, and continuing would
/// surface foreign data as if it were the caller's.
void _requireWorkspace(String actual, String expected) {
  if (actual != expected) {
    throw const FormatException('Valuation row workspace mismatch.');
  }
}
