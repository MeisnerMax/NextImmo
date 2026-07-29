import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/cash_flow_projection.dart';
import 'package:neximmo_app/features/valuation/domain/methods/dcf_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';


FactorSet _completeExitCapFactors({
  ValuationFactor Function(ValuationFactor)? mutateExitCap,
}) {
  final exitCap = ValuationFactor.user(
    id: ValuationFactorIds.exitCapRate,
    label: 'Exit-Cap',
    value: 0.05,
  );
  return FactorSet([
    ValuationFactor.user(id: ValuationFactorIds.grossRentAnnual, label: 'Rohertrag', value: 100000),
    ValuationFactor.user(id: ValuationFactorIds.vacancyRate, label: 'Leerstand', value: 0.05),
    ValuationFactor.user(
      id: ValuationFactorIds.operatingExpensesAnnual,
      label: 'Bewirtschaftung',
      value: 25000,
    ),
    ValuationFactor.user(id: ValuationFactorIds.rentGrowthRate, label: 'Mietwachstum', value: 0.02),
    ValuationFactor.user(
      id: ValuationFactorIds.expenseGrowthRate,
      label: 'Kostenwachstum',
      value: 0.02,
    ),
    ValuationFactor.user(id: ValuationFactorIds.holdYears, label: 'Haltedauer', value: 5),
    ValuationFactor.user(id: ValuationFactorIds.discountRate, label: 'Kalkulationszins', value: 0.06),
    ValuationFactor.user(id: ValuationFactorIds.saleCostRate, label: 'Verkaufskosten', value: 0.03),
    mutateExitCap == null ? exitCap : mutateExitCap(exitCap),
  ]);
}

void main() {
  group('DiscountedCashFlowMethod', () {
    const method = DiscountedCashFlowMethod();

    test('returns MethodUnavailable listing every missing required factor', () {
      final result = method.evaluate(FactorSet(const []));
      expect(result, isA<MethodUnavailable>());
      final unavailable = result as MethodUnavailable;
      final ids = unavailable.missingFactors.map((m) => m.factorId).toSet();
      expect(ids, contains(ValuationFactorIds.grossRentAnnual));
      expect(ids, contains(ValuationFactorIds.discountRate));
      expect(ids, contains(ValuationFactorIds.exitCapRate));
    });

    test('golden: reference exit-cap case discounts to the locked value', () {
      final result = method.evaluate(_completeExitCapFactors());
      expect(result, isA<MethodValue>());
      final value = result as MethodValue;
      // Independently hand-computed (2% NOI growth, 6% discount, 5% exit cap,
      // 3% sale costs, 5-year hold): PV income ≈ 306,191.5 + PV terminal
      // ≈ 1,120,395.1.
      expect(value.amount, closeTo(1426586.6, 2.0));
      expect(value.breakdown, isNotEmpty);
    });

    test('all-user-provided inputs yield high confidence', () {
      final result = method.evaluate(_completeExitCapFactors()) as MethodValue;
      expect(result.confidence, ConfidenceBand.high);
    });

    test('a confirmed suggestion caps confidence at medium', () {
      final result =
          method.evaluate(
                _completeExitCapFactors(
                  mutateExitCap:
                      (f) => ValuationFactor.suggested(
                        id: f.id,
                        label: f.label,
                        value: f.value!,
                      ).accept(),
                ),
              )
              as MethodValue;
      expect(result.confidence, ConfidenceBand.medium);
    });

    test('unconfirmed suggested exit cap makes the method unavailable', () {
      final result = method.evaluate(
        _completeExitCapFactors(
          mutateExitCap:
              (f) => ValuationFactor.suggested(
                id: f.id,
                label: f.label,
                value: f.value!,
              ),
        ),
      );
      expect(result, isA<MethodUnavailable>());
      final unavailable = result as MethodUnavailable;
      expect(
        unavailable.missingFactors.single.reason,
        MissingFactorReason.suggestionNotConfirmed,
      );
    });

    test('gordon growth with discount <= growth reports a reason, not a value', () {
      const gordon = DiscountedCashFlowMethod(
        terminal: DcfTerminalMethod.gordonGrowth,
      );
      final factors = FactorSet([
        ValuationFactor.user(id: ValuationFactorIds.grossRentAnnual, label: 'r', value: 100000),
        ValuationFactor.user(id: ValuationFactorIds.vacancyRate, label: 'v', value: 0.05),
        ValuationFactor.user(id: ValuationFactorIds.operatingExpensesAnnual, label: 'o', value: 25000),
        ValuationFactor.user(id: ValuationFactorIds.rentGrowthRate, label: 'g', value: 0.02),
        ValuationFactor.user(id: ValuationFactorIds.expenseGrowthRate, label: 'eg', value: 0.02),
        ValuationFactor.user(id: ValuationFactorIds.holdYears, label: 'h', value: 5),
        ValuationFactor.user(id: ValuationFactorIds.discountRate, label: 'd', value: 0.03),
        ValuationFactor.user(id: ValuationFactorIds.saleCostRate, label: 's', value: 0.03),
        ValuationFactor.user(id: ValuationFactorIds.terminalGrowthRate, label: 'tg', value: 0.04),
      ]);
      final result = gordon.evaluate(factors);
      expect(result, isA<MethodUnavailable>());
      expect((result as MethodUnavailable).reasons, isNotEmpty);
    });
  });
}
