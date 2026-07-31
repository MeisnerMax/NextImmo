import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/application/valuation_repository.dart';
import 'package:neximmo_app/features/valuation/data/supabase_valuation_repository_adapter.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case_dto.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_report.dart';

class _RpcCall {
  const _RpcCall(this.function, this.parameters);

  final String function;
  final Map<String, Object?> parameters;
}

class _FakeGateway implements ValuationSupabaseGateway {
  _FakeGateway({
    this.rpcResponse,
    this.cases = const [],
    this.factors = const [],
    this.methodResults = const [],
    this.opinions = const [],
  });

  Object? rpcResponse;
  List<Map<String, dynamic>> cases;
  List<Map<String, dynamic>> factors;
  List<Map<String, dynamic>> methodResults;
  List<Map<String, dynamic>> opinions;

  final calls = <_RpcCall>[];

  @override
  String? get currentUserId => 'user-1';

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) async {
    calls.add(_RpcCall(function, parameters));
    return rpcResponse;
  }

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
  }) async => cases;

  @override
  Future<List<Map<String, dynamic>>> getValuationCase({
    required String workspaceId,
    required String valuationCaseId,
  }) async => cases;

  @override
  Future<List<Map<String, dynamic>>> listFactors({
    required String workspaceId,
    required String valuationCaseId,
  }) async => factors;

  @override
  Future<List<Map<String, dynamic>>> listMethodResults({
    required String workspaceId,
    required String valuationCaseId,
  }) async => methodResults;

  @override
  Future<List<Map<String, dynamic>>> getOpinion({
    required String workspaceId,
    required String valuationCaseId,
  }) async => opinions;
}

Map<String, dynamic> _caseRow({
  String workspaceId = 'ws-1',
  int version = 1,
  String status = 'draft',
}) => <String, dynamic>{
  'id': 'case-1',
  'workspace_id': workspaceId,
  'property_id': 'prop-1',
  'scenario_id': null,
  'title': 'Musterfall MFH',
  'kind': 'holding',
  'status': status,
  'dcf_terminal': 'exit_cap',
  'enabled_methods': ['income_approach_de', 'cost_approach_de'],
  'weight_overrides': <String, dynamic>{},
  'minimum_comparables': 3,
  'created_at': '2026-07-28T09:00:00.000Z',
  'updated_at': '2026-07-28T11:30:00.000Z',
  'created_by': 'user-1',
  'updated_by': 'user-1',
  'version': version,
};

const _context = ValuationCommandContext(
  workspaceId: 'ws-1',
  actorId: 'user-1',
  mutationId: 'mut-1',
  correlationId: 'corr-1',
  reason: 'Ersterfassung',
);

void main() {
  group('createValuationCase', () {
    test('sends wire names and returns the case with its factors', () async {
      final gateway = _FakeGateway(
        rpcResponse: {
          'ok': true,
          'entity': {
            ..._caseRow(),
            'factors': [
              {
                'valuation_case_id': 'case-1',
                'factor_id': ValuationFactorIds.grossRentAnnual,
                'label': 'Rohertrag',
                'provenance': 'user_provided',
                'value': 60000,
                'confidence': 'high',
              },
            ],
          },
        },
      );
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(gateway);

      final result = await adapter.createValuationCase(
        CreateValuationCaseCommand(
          context: _context,
          propertyId: 'prop-1',
          title: 'Musterfall MFH',
          kind: ValuationCaseKind.holding,
          enabledMethods: const {ValuationMethodKind.incomeApproachDe},
          factors: [
            ValuationFactorDto.fromDomain(
              caseId: 'case-1',
              factor: ValuationFactor.user(
                id: ValuationFactorIds.grossRentAnnual,
                label: 'Rohertrag',
                value: 60000,
              ),
            ),
          ],
        ),
      );

      expect(result, isA<ValuationRepositorySuccess<ValuationCaseDetail>>());
      final detail =
          (result as ValuationRepositorySuccess<ValuationCaseDetail>).value;
      expect(detail.valuationCase.title, 'Musterfall MFH');
      expect(detail.factors.single.provenance, FactorProvenance.userProvided);

      final call = gateway.calls.single;
      expect(call.function, 'create_valuation_case');
      expect(call.parameters['p_kind'], 'holding');
      expect(call.parameters['p_enabled_methods'], ['income_approach_de']);
      expect(call.parameters['p_reason'], 'Ersterfassung');
      // The case id is implied by the command target, so it is not repeated
      // inside each factor payload.
      final factorPayload =
          (call.parameters['p_factors']! as List).single as Map;
      expect(factorPayload.containsKey('valuation_case_id'), isFalse);
      expect(factorPayload['provenance'], 'user_provided');
    });

    test('maps approved_immutable to its own failure kind', () async {
      final gateway = _FakeGateway(
        rpcResponse: {
          'ok': false,
          'error': {
            'code': 'approved_immutable',
            'message': 'Freigegebene Bewertung ist ein Datensatz.',
          },
        },
      );
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(gateway);

      final result = await adapter.upsertFactors(
        UpsertValuationFactorsCommand(
          context: _context,
          valuationCaseId: 'case-1',
          expectedVersion: 5,
          factors: const [],
          removeFactorIds: const ['sachwertfaktor'],
        ),
      );

      final failure =
          result as ValuationRepositoryFailure<List<ValuationFactorDto>>;
      expect(failure.kind, ValuationRepositoryFailureKind.approvedImmutable);
      expect(failure.kind, isNot(ValuationRepositoryFailureKind.forbidden));
      expect(failure.message, contains('Datensatz'));
    });

    test('maps a version conflict with the server\'s current case', () async {
      final gateway = _FakeGateway(
        rpcResponse: {
          'ok': false,
          'error': {
            'code': 'version_conflict',
            'message': 'stale',
            'expected_version': 1,
            'actual_version': 3,
            'current_entity': _caseRow(version: 3),
          },
        },
      );
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(gateway);

      final result = await adapter.updateValuationCase(
        UpdateValuationCaseCommand(
          context: _context,
          valuationCaseId: 'case-1',
          expectedVersion: 1,
          title: 'Neuer Titel',
        ),
      );

      final failure = result as ValuationRepositoryFailure<ValuationCaseDetail>;
      expect(failure.kind, ValuationRepositoryFailureKind.versionConflict);
      expect(failure.versionConflict!.actualVersion, 3);
      expect(failure.versionConflict!.currentCase!.version, 3);
    });

    test('an unexpected payload becomes an infrastructure failure', () async {
      final gateway = _FakeGateway(rpcResponse: 'not-json');
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(gateway);

      final result = await adapter.transitionValuationCaseStatus(
        TransitionValuationCaseStatusCommand(
          context: _context,
          valuationCaseId: 'case-1',
          expectedVersion: 1,
          targetStatus: ValuationCaseStatus.inReview,
        ),
      );

      expect(
        (result as ValuationRepositoryFailure).kind,
        ValuationRepositoryFailureKind.infrastructureFailure,
      );
    });
  });

  group('createValuationVariant', () {
    test('sends the source case and both labels', () async {
      final gateway = _FakeGateway(
        rpcResponse: {
          'ok': true,
          'entity': {
            ..._caseRow(),
            'id': 'case-2',
            'variant_group_id': 'group-1',
            'variant_label': 'Konservativ',
            'factors': <Object>[],
          },
        },
      );
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(gateway);

      final result = await adapter.createValuationVariant(
        const CreateValuationVariantCommand(
          context: _context,
          sourceValuationCaseId: 'case-1',
          variantLabel: 'Konservativ',
        ),
      );

      final detail =
          (result as ValuationRepositorySuccess<ValuationCaseDetail>).value;
      expect(detail.valuationCase.variantLabel, 'Konservativ');
      expect(detail.valuationCase.variantGroupId, 'group-1');

      final call = gateway.calls.single;
      expect(call.function, 'create_valuation_variant');
      expect(call.parameters['p_source_valuation_case_id'], 'case-1');
      expect(call.parameters['p_variant_label'], 'Konservativ');
      expect(call.parameters['p_source_variant_label'], 'Basis');
    });

    test('a duplicate label comes back as a validation failure', () async {
      final gateway = _FakeGateway(
        rpcResponse: {
          'ok': false,
          'error': {
            'code': 'validation_failed',
            'message': 'A variant with this name already exists in the group',
          },
        },
      );
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(gateway);

      final result = await adapter.createValuationVariant(
        const CreateValuationVariantCommand(
          context: _context,
          sourceValuationCaseId: 'case-1',
          variantLabel: 'Konservativ',
        ),
      );

      expect(
        (result as ValuationRepositoryFailure).kind,
        ValuationRepositoryFailureKind.validationFailed,
      );
    });
  });

  group('publishReport', () {
    test('serializes an unavailable method without an amount', () async {
      final gateway = _FakeGateway(
        rpcResponse: {
          'ok': true,
          'entity': {
            'valuation_case_id': 'case-1',
            'computed_from_version': 3,
            'method_results': [
              {
                'method': 'income_approach_de',
                'is_available': true,
                'amount': 1091313,
                'confidence': 'high',
              },
              {
                'method': 'cost_approach_de',
                'is_available': false,
                'amount': null,
                'missing_factors': [
                  {'factor_id': 'sachwertfaktor', 'label': 'Sachwertfaktor'},
                ],
              },
            ],
            'opinion': {
              'is_available': true,
              'amount': 1091313,
              'confidence': 'high',
              'weights': {'income_approach_de': 1.0},
              'rationale': 'Nur ein Verfahren verfügbar.',
            },
          },
        },
      );
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(gateway);

      final result = await adapter.publishReport(
        PublishValuationReportCommand(
          context: _context,
          valuationCaseId: 'case-1',
          expectedVersion: 3,
          report: const ValuationReport(
            methodResults: {
              ValuationMethodKind.incomeApproachDe: MethodValue(
                amount: 1091313,
                confidence: ConfidenceBand.high,
              ),
              ValuationMethodKind.costApproachDe: MethodUnavailable(
                missingFactors: [
                  MissingFactor(
                    factorId: ValuationFactorIds.sachwertfaktor,
                    label: 'Sachwertfaktor',
                    reason: MissingFactorReason.notEntered,
                    message: 'fehlt',
                  ),
                ],
              ),
            },
            opinion: MarketValue(
              amount: 1091313,
              confidence: ConfidenceBand.high,
              weights: {ValuationMethodKind.incomeApproachDe: 1.0},
              rationale: 'Nur ein Verfahren verfügbar.',
            ),
          ),
        ),
      );

      final snapshot =
          (result as ValuationRepositorySuccess<ValuationReportSnapshot>).value;
      expect(snapshot.computedFromVersion, 3);
      expect(snapshot.methodResults, hasLength(2));
      expect(
        snapshot.methodResults
            .firstWhere((r) => r.method == ValuationMethodKind.costApproachDe)
            .amount,
        isNull,
      );
      expect(snapshot.opinion!.amount, 1091313);

      final sent = gateway.calls.single.parameters['p_method_results']! as List;
      final unavailable = sent.cast<Map>().firstWhere(
        (r) => r['method'] == 'cost_approach_de',
      );
      expect(unavailable['is_available'], isFalse);
      expect(unavailable['amount'], isNull);
      expect(unavailable['missing_factors'], hasLength(1));
    });

    test('latestReport reports notFound instead of an empty report', () async {
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(
        _FakeGateway(),
      );

      final result = await adapter.latestReport(
        workspaceId: 'ws-1',
        valuationCaseId: 'case-1',
      );

      expect(
        (result as ValuationRepositoryFailure).kind,
        ValuationRepositoryFailureKind.notFound,
      );
    });
  });

  group('reads', () {
    test('a full page produces a keyset cursor, a partial page does not', () async {
      final gateway = _FakeGateway(cases: [_caseRow()]);
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(gateway);

      final partial = await adapter.searchValuationCases(
        const ValuationCaseListQuery(
          workspaceId: 'ws-1',
          page: ValuationPageRequest(limit: 50),
        ),
      );
      expect(
        (partial as ValuationRepositorySuccess<ValuationPageResult<ValuationCaseDto>>)
            .value
            .nextCursor,
        isNull,
      );

      final full = await adapter.searchValuationCases(
        const ValuationCaseListQuery(
          workspaceId: 'ws-1',
          page: ValuationPageRequest(limit: 1),
        ),
      );
      final cursor =
          (full as ValuationRepositorySuccess<ValuationPageResult<ValuationCaseDto>>)
              .value
              .nextCursor;
      expect(ValuationKeysetCursor.decode(cursor)!.id, 'case-1');
    });

    test('a row from another workspace fails closed', () async {
      final gateway = _FakeGateway(cases: [_caseRow(workspaceId: 'ws-2')]);
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(gateway);

      final result = await adapter.searchValuationCases(
        const ValuationCaseListQuery(workspaceId: 'ws-1'),
      );

      expect(
        (result as ValuationRepositoryFailure).kind,
        ValuationRepositoryFailureKind.infrastructureFailure,
      );
    });

    test('a report computed from an older version is flagged as stale', () async {
      final gateway = _FakeGateway(
        cases: [_caseRow(version: 5)],
        factors: [
          {
            'valuation_case_id': 'case-1',
            'factor_id': ValuationFactorIds.grossRentAnnual,
            'label': 'Rohertrag',
            'provenance': 'user_provided',
            'value': 60000,
            'confidence': 'high',
          },
        ],
        methodResults: [
          {
            'valuation_case_id': 'case-1',
            'method': 'income_approach_de',
            'is_available': true,
            'amount': 1091313,
            'confidence': 'high',
            'computed_from_version': 3,
          },
        ],
        opinions: [
          {
            'valuation_case_id': 'case-1',
            'is_available': true,
            'amount': 1091313,
            'confidence': 'high',
            'weights': {'income_approach_de': 1.0},
            'rationale': 'Abgeglichen.',
          },
        ],
      );
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(gateway);

      final result = await adapter.getValuationCaseById(
        workspaceId: 'ws-1',
        valuationCaseId: 'case-1',
      );

      final detail =
          (result as ValuationRepositorySuccess<ValuationCaseDetail>).value;
      expect(detail.report!.computedFromVersion, 3);
      expect(detail.valuationCase.version, 5);
      expect(detail.hasStaleReport, isTrue);
    });

    test('a missing case is notFound', () async {
      final adapter = SupabaseValuationRepositoryAdapter.withGateway(
        _FakeGateway(),
      );

      final result = await adapter.getValuationCaseById(
        workspaceId: 'ws-1',
        valuationCaseId: 'case-1',
      );

      expect(
        (result as ValuationRepositoryFailure).kind,
        ValuationRepositoryFailureKind.notFound,
      );
    });
  });
}
