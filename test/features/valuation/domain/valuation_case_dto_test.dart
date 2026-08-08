import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/cash_flow_projection.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case_dto.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_report.dart';

ValuationCaseDto _caseDto() => ValuationCaseDto(
  id: 'case-1',
  workspaceId: 'ws-1',
  propertyId: 'prop-1',
  scenarioId: 'scn-1',
  title: 'Musterfall MFH',
  kind: ValuationCaseKind.holding,
  status: ValuationCaseStatus.inReview,
  dcfTerminal: DcfTerminalMethod.gordonGrowth,
  enabledMethods: const {
    ValuationMethodKind.incomeApproachDe,
    ValuationMethodKind.costApproachDe,
  },
  weightOverrides: const {ValuationMethodKind.incomeApproachDe: 0.6},
  minimumComparables: 4,
  createdAt: DateTime.utc(2026, 7, 20, 9),
  updatedAt: DateTime.utc(2026, 7, 28, 11, 30),
  createdBy: 'user-1',
  updatedBy: 'user-2',
  version: 3,
);

void main() {
  group('ValuationCaseDto', () {
    test('round-trips through json', () {
      final restored = ValuationCaseDto.fromJson(_caseDto().toJson())!;

      expect(restored.id, 'case-1');
      expect(restored.scenarioId, 'scn-1');
      expect(restored.kind, ValuationCaseKind.holding);
      expect(restored.status, ValuationCaseStatus.inReview);
      expect(restored.dcfTerminal, DcfTerminalMethod.gordonGrowth);
      expect(restored.enabledMethods, hasLength(2));
      expect(
        restored.weightOverrides[ValuationMethodKind.incomeApproachDe],
        0.6,
      );
      expect(restored.minimumComparables, 4);
      expect(restored.version, 3);
      expect(restored.updatedAt, DateTime.utc(2026, 7, 28, 11, 30));
    });

    test('carries the variant grouping when the row has one', () {
      final json = _caseDto().toJson()
        ..['variant_group_id'] = 'group-1'
        ..['variant_label'] = 'Konservativ';

      final restored = ValuationCaseDto.fromJson(json)!;

      expect(restored.variantGroupId, 'group-1');
      expect(restored.variantLabel, 'Konservativ');
    });

    test('a standalone case carries no grouping', () {
      final restored = ValuationCaseDto.fromJson(_caseDto().toJson())!;

      expect(restored.variantGroupId, isNull);
      expect(restored.variantLabel, isNull);
    });

    test('half a grouping is read as none, never as a variant', () {
      // The database cannot produce this (check constraint), so a row that
      // looks like it is not a variant — it is a broken row, and inventing a
      // group from it would show a variant that does not exist.
      final json = _caseDto().toJson()..['variant_group_id'] = 'group-1';

      final restored = ValuationCaseDto.fromJson(json)!;

      expect(restored.variantGroupId, isNull);
      expect(restored.variantLabel, isNull);
    });

    test('returns null for a row with an unknown status', () {
      final json = _caseDto().toJson()..['status'] = 'freigegeben';

      expect(ValuationCaseDto.fromJson(json), isNull);
    });

    test('rehydrates the engine aggregate with its factors', () {
      final domain = _caseDto().toDomain(
        factors: [
          ValuationFactor.user(
            id: ValuationFactorIds.grossRentAnnual,
            label: 'Rohertrag',
            value: 60000,
          ),
        ],
      );

      expect(domain.id, 'case-1');
      expect(domain.status, ValuationCaseStatus.inReview);
      expect(domain.factors.value(ValuationFactorIds.grossRentAnnual), 60000);
      expect(domain.enabledMethods, hasLength(2));
    });
  });

  group('ValuationFactorDto', () {
    test('keeps provenance and confidence across a round trip', () {
      final suggested = ValuationFactor.suggested(
        id: ValuationFactorIds.liegenschaftszinssatz,
        label: 'Liegenschaftszinssatz',
        value: 0.035,
        source: 'Referenztabelle',
      );

      final dto = ValuationFactorDto.fromDomain(
        caseId: 'case-1',
        factor: suggested,
      );
      final restored = ValuationFactorDto.fromJson(dto.toJson())!.toDomain();

      expect(restored.provenance, FactorProvenance.suggestedDefault);
      expect(restored.confidence, ConfidenceBand.low);
      expect(restored.source, 'Referenztabelle');
      // Still unusable after a storage round trip — persistence must not
      // launder an unconfirmed suggestion into a usable value.
      expect(restored.isUsable, isFalse);
    });

    test('a missing factor survives as missing, without a value', () {
      final dto = ValuationFactorDto.fromDomain(
        caseId: 'case-1',
        factor: ValuationFactor.missing(
          id: ValuationFactorIds.sachwertfaktor,
          label: 'Sachwertfaktor',
        ),
      );

      expect(dto.toJson()['value'], isNull);
      expect(dto.toDomain().provenance, FactorProvenance.missing);
    });
  });

  group('ValuationMethodResultDto', () {
    test('stores a value result with its breakdown and assumptions', () {
      const result = MethodValue(
        amount: 1091313,
        confidence: ConfidenceBand.high,
        breakdown: [
          MethodBreakdownLine(label: 'Ertragswert', amount: 1091313, unit: '€'),
        ],
        assumptions: [
          ValuationAssumption(
            factorId: ValuationFactorIds.liegenschaftszinssatz,
            label: 'Liegenschaftszinssatz',
            provenance: FactorProvenance.accepted,
            value: 0.035,
          ),
        ],
      );

      final dto = ValuationMethodResultDto.fromDomain(
        caseId: 'case-1',
        method: ValuationMethodKind.incomeApproachDe,
        result: result,
      );
      final restored = ValuationMethodResultDto.fromJson(dto.toJson())!;

      expect(restored.isAvailable, isTrue);
      expect(restored.amount, 1091313);
      expect(restored.confidence, ConfidenceBand.high);
      expect(restored.breakdown.single['label'], 'Ertragswert');
      expect(restored.assumptions.single['provenance'], 'accepted');
    });

    test('stores "nicht ermittelbar" as unavailable, never as an amount', () {
      const result = MethodUnavailable(
        missingFactors: [
          MissingFactor(
            factorId: ValuationFactorIds.sachwertfaktor,
            label: 'Sachwertfaktor',
            reason: MissingFactorReason.suggestionNotConfirmed,
            message: 'Systemvorschlag muss bestätigt werden.',
          ),
        ],
        reasons: ['Keine ausreichenden Vergleichsobjekte.'],
      );

      final dto = ValuationMethodResultDto.fromDomain(
        caseId: 'case-1',
        method: ValuationMethodKind.costApproachDe,
        result: result,
      );
      final restored = ValuationMethodResultDto.fromJson(dto.toJson())!;

      expect(restored.isAvailable, isFalse);
      expect(restored.amount, isNull);
      expect(restored.missingFactors.single['reason'], 'suggestionNotConfirmed');
      expect(restored.reasons.single, contains('Vergleichsobjekte'));
    });
  });

  group('MarketValueOpinionDto', () {
    test('round-trips a reconciled Verkehrswert with its weights', () {
      const opinion = MarketValue(
        amount: 987500,
        confidence: ConfidenceBand.medium,
        weights: {
          ValuationMethodKind.incomeApproachDe: 0.75,
          ValuationMethodKind.costApproachDe: 0.25,
        },
        rationale: 'Verfahrensabgleich über 2 verfügbare(s) Verfahren.',
      );

      final restored =
          MarketValueOpinionDto.fromJson(
            MarketValueOpinionDto.fromDomain(
              caseId: 'case-1',
              opinion: opinion,
            ).toJson(),
          )!;

      expect(restored.isAvailable, isTrue);
      expect(restored.amount, 987500);
      expect(restored.weights[ValuationMethodKind.costApproachDe], 0.25);
      expect(restored.rationale, contains('Verfahrensabgleich'));
    });

    test('round-trips an unavailable opinion with the blocked methods', () {
      const opinion = MarketValueUnavailable(
        reason: 'Verkehrswert nicht ermittelbar.',
        unavailableMethods: [
          ValuationMethodKind.incomeApproachDe,
          ValuationMethodKind.comparisonApproach,
        ],
      );

      final restored =
          MarketValueOpinionDto.fromJson(
            MarketValueOpinionDto.fromDomain(
              caseId: 'case-1',
              opinion: opinion,
            ).toJson(),
          )!;

      expect(restored.isAvailable, isFalse);
      expect(restored.amount, isNull);
      expect(restored.unavailableMethods, hasLength(2));
      expect(restored.rationale, contains('nicht ermittelbar'));
    });
  });
}
