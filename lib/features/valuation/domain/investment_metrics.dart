/// The single canonical NPV/IRR implementation of the valuation engine.
///
/// The legacy code base solves IRR three times over (acquisition, renovation and
/// disposition services each ship their own); those duplicates are replaced by
/// this one at cutover. Every helper returns `null` when the input does not
/// admit a meaningful answer instead of a substitute number.
library;

import 'dart:math' as math;

import 'cash_flow_projection.dart';

/// Net present value of [cashFlows] at [rate]. `cashFlows[0]` is period 0 (the
/// investment, normally negative), `cashFlows[t]` is discounted by `(1+rate)^t`.
/// Returns `null` for `rate <= -1` or an empty series.
double? netPresentValue({
  required List<double> cashFlows,
  required double rate,
}) {
  if (cashFlows.isEmpty || rate <= -1) return null;
  var npv = 0.0;
  for (var t = 0; t < cashFlows.length; t++) {
    npv += cashFlows[t] / math.pow(1 + rate, t);
  }
  return npv;
}

/// Internal rate of return of [cashFlows], solved by bisection on
/// `(-0.9999, 10.0]`.
///
/// Returns `null` when the series has no sign change (no IRR exists) or the
/// bracket does not contain a root — never a fabricated 0 %.
double? internalRateOfReturn({
  required List<double> cashFlows,
  double tolerance = 1e-7,
  int maxIterations = 200,
}) {
  if (cashFlows.length < 2) return null;
  final hasPositive = cashFlows.any((c) => c > 0);
  final hasNegative = cashFlows.any((c) => c < 0);
  if (!hasPositive || !hasNegative) return null;

  var low = -0.9999;
  var high = 10.0;
  final npvAtLow = netPresentValue(cashFlows: cashFlows, rate: low);
  final npvAtHigh = netPresentValue(cashFlows: cashFlows, rate: high);
  if (npvAtLow == null || npvAtHigh == null) return null;
  if (npvAtLow.sign == npvAtHigh.sign) return null;

  var npvLow = npvAtLow;
  for (var i = 0; i < maxIterations; i++) {
    final mid = (low + high) / 2;
    final npvMid = netPresentValue(cashFlows: cashFlows, rate: mid)!;
    if (npvMid.abs() < tolerance || (high - low) / 2 < tolerance) return mid;
    if (npvMid.sign == npvLow.sign) {
      low = mid;
      npvLow = npvMid;
    } else {
      high = mid;
    }
  }
  return (low + high) / 2;
}

/// Total distributions divided by the invested amount. Returns `null` for a
/// non-positive investment — not 0.
double? equityMultiple({
  required double investedAmount,
  required List<double> distributions,
}) {
  if (investedAmount <= 0) return null;
  final total = distributions.fold<double>(0, (sum, d) => sum + d);
  return total / investedAmount;
}

/// Unlevered cash-flow series for a DCF hold: `-price` in period 0, the annual
/// NOI in periods 1..N, and the net sale proceeds added to the final period.
/// Returns `null` for a non-positive [price].
List<double>? unleveredCashFlows({
  required DcfValuation dcf,
  required double price,
}) {
  if (price <= 0 || dcf.years.isEmpty) return null;
  final flows = <double>[
    -price,
    ...dcf.years.map((y) => y.netOperatingIncome),
  ];
  flows[flows.length - 1] += dcf.netTerminalValue;
  return flows;
}

/// Investment key figures for a case, each `null` when not determinable.
class InvestmentMetrics {
  const InvestmentMetrics({
    this.irr,
    this.npvAtDiscountRate,
    this.equityMultiple,
    this.discountRate,
  });

  /// Unlevered IRR over the hold period.
  final double? irr;

  /// NPV at the case's Kalkulationszins.
  final double? npvAtDiscountRate;

  final double? equityMultiple;

  /// The rate [npvAtDiscountRate] was evaluated at.
  final double? discountRate;

  bool get isEmpty =>
      irr == null && npvAtDiscountRate == null && equityMultiple == null;
}
