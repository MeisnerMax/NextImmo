import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/reconciliation.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_report.dart';

MethodValue _value(double amount, [ConfidenceBand band = ConfidenceBand.high]) =>
    MethodValue(amount: amount, confidence: band);

const _unavailable = MethodUnavailable(
  missingFactors: [
    MissingFactor(
      factorId: 'x',
      label: 'X',
      reason: MissingFactorReason.notEntered,
      message: 'fehlt',
    ),
  ],
);

void main() {
  group('ValuationReconciler', () {
    const reconciler = ValuationReconciler();

    test('renormalizes the base weights over the available methods', () {
      // Ertragswert 0.30 and Sachwert 0.10 -> 0.75 / 0.25.
      final opinion = reconciler.reconcile({
        ValuationMethodKind.incomeApproachDe: _value(1000000),
        ValuationMethodKind.costApproachDe: _value(950000),
      });

      expect(opinion, isA<MarketValue>());
      final value = opinion as MarketValue;
      expect(value.weights[ValuationMethodKind.incomeApproachDe], closeTo(0.75, 1e-9));
      expect(value.weights[ValuationMethodKind.costApproachDe], closeTo(0.25, 1e-9));
      expect(value.amount, closeTo(987500, 1e-6));
      expect(value.confidence, ConfidenceBand.high);
    });

    test('an unavailable method carries no weight but is named in the rationale', () {
      final opinion =
          reconciler.reconcile({
                ValuationMethodKind.incomeApproachDe: _value(1000000),
                ValuationMethodKind.comparisonApproach: _unavailable,
              })
              as MarketValue;

      expect(opinion.weights.keys, [ValuationMethodKind.incomeApproachDe]);
      expect(opinion.amount, closeTo(1000000, 1e-6));
      expect(opinion.rationale, contains('Vergleichswertverfahren'));
      expect(opinion.rationale, contains('Nicht verfügbar'));
    });

    test('takes the weakest contributing confidence', () {
      final opinion =
          reconciler.reconcile({
                ValuationMethodKind.incomeApproachDe: _value(1000000),
                ValuationMethodKind.costApproachDe: _value(
                  980000,
                  ConfidenceBand.medium,
                ),
              })
              as MarketValue;

      expect(opinion.confidence, ConfidenceBand.medium);
    });

    test('downgrades the confidence when the method spread is wide', () {
      // (1,000,000 − 800,000) / 950,000 = 21 % > 20 %.
      final opinion =
          reconciler.reconcile({
                ValuationMethodKind.incomeApproachDe: _value(1000000),
                ValuationMethodKind.costApproachDe: _value(800000),
              })
              as MarketValue;

      expect(opinion.confidence, ConfidenceBand.medium);
      expect(opinion.rationale, contains('Streuung'));
      expect(opinion.rationale, contains('herabgesetzt'));
    });

    test('honours explicit weight overrides', () {
      final opinion =
          reconciler.reconcile(
                {
                  ValuationMethodKind.incomeApproachDe: _value(1000000),
                  ValuationMethodKind.costApproachDe: _value(900000),
                },
                weightOverrides: const {
                  ValuationMethodKind.incomeApproachDe: 0.5,
                  ValuationMethodKind.costApproachDe: 0.5,
                },
              )
              as MarketValue;

      expect(opinion.amount, closeTo(950000, 1e-6));
      expect(opinion.weights.values, everyElement(closeTo(0.5, 1e-9)));
    });

    test('reports "nicht ermittelbar" when no method is available', () {
      final opinion = reconciler.reconcile({
        ValuationMethodKind.incomeApproachDe: _unavailable,
        ValuationMethodKind.costApproachDe: _unavailable,
      });

      expect(opinion, isA<MarketValueUnavailable>());
      final unavailable = opinion as MarketValueUnavailable;
      expect(unavailable.unavailableMethods, hasLength(2));
      expect(unavailable.reason, contains('nicht ermittelbar'));
    });

    test('formats amounts and percentages in the rationale', () {
      final opinion =
          reconciler.reconcile({
                ValuationMethodKind.incomeApproachDe: _value(1091313),
              })
              as MarketValue;

      expect(opinion.rationale, contains('1.091.313 €'));
      expect(opinion.rationale, contains('100 %'));
    });
  });
}
