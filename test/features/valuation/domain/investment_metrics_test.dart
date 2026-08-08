import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/cash_flow_projection.dart';
import 'package:neximmo_app/features/valuation/domain/investment_metrics.dart';

void main() {
  group('netPresentValue', () {
    test('discounts each period from period 0', () {
      // -1000 + 500/1.1 + 500/1.21 + 500/1.331 = 243.4260...
      final npv = netPresentValue(
        cashFlows: const [-1000, 500, 500, 500],
        rate: 0.10,
      );

      expect(npv, closeTo(243.4260, 1e-3));
    });

    test('returns null for an empty series or an impossible rate', () {
      expect(netPresentValue(cashFlows: const [], rate: 0.1), isNull);
      expect(netPresentValue(cashFlows: const [-1, 2], rate: -1), isNull);
    });
  });

  group('internalRateOfReturn', () {
    test('solves a single-period doubling exactly', () {
      expect(
        internalRateOfReturn(cashFlows: const [-1000, 1100]),
        closeTo(0.10, 1e-6),
      );
    });

    test('solves a multi-period series', () {
      final irr = internalRateOfReturn(
        cashFlows: const [-1000, 300, 400, 500],
      );

      expect(irr, isNotNull);
      expect(
        netPresentValue(cashFlows: const [-1000, 300, 400, 500], rate: irr!),
        closeTo(0, 1e-4),
      );
    });

    test('returns null instead of 0 when no sign change exists', () {
      expect(internalRateOfReturn(cashFlows: const [-100, -50]), isNull);
      expect(internalRateOfReturn(cashFlows: const [100, 50]), isNull);
      expect(internalRateOfReturn(cashFlows: const [-100]), isNull);
    });
  });

  group('equityMultiple', () {
    test('is total distributions over the investment', () {
      expect(
        equityMultiple(investedAmount: 1000, distributions: const [500, 900]),
        closeTo(1.4, 1e-9),
      );
    });

    test('returns null for a non-positive investment', () {
      expect(
        equityMultiple(investedAmount: 0, distributions: const [100]),
        isNull,
      );
    });
  });

  group('unleveredCashFlows', () {
    final dcf = computeDcfValuation(
      grossRentAnnual: 60000,
      vacancyRate: 0.05,
      operatingExpensesAnnual: 15000,
      rentGrowthRate: 0.0,
      expenseGrowthRate: 0.0,
      holdYears: 3,
      discountRate: 0.06,
      saleCostRate: 0.03,
      terminal: DcfTerminalMethod.exitCap,
      exitCapRate: 0.05,
    )!;

    test('puts −price in period 0 and the net sale proceeds in the last', () {
      final flows = unleveredCashFlows(dcf: dcf, price: 800000)!;

      expect(flows.length, 4);
      expect(flows.first, -800000);
      expect(flows[1], closeTo(42000, 1e-6)); // 60000*0.95 − 15000
      expect(flows.last, closeTo(42000 + dcf.netTerminalValue, 1e-6));
    });

    test('returns null for a non-positive price', () {
      expect(unleveredCashFlows(dcf: dcf, price: 0), isNull);
    });
  });
}
