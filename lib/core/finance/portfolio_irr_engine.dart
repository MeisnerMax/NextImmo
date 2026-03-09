import 'dart:math' as math;

import '../models/portfolio_analytics.dart';

class PortfolioIrrEngine {
  const PortfolioIrrEngine();

  PortfolioIrrResult compute({
    required List<PortfolioCashflowRecord> cashflows,
  }) {
    if (cashflows.isEmpty) {
      return const PortfolioIrrResult(
        irr: null,
        warning: 'No cashflows available in selected range.',
        totalInflows: 0,
        totalOutflows: 0,
        netCashflow: 0,
        averageMonthlyNet: 0,
        datedCashflows: <PortfolioCashflowRecord>[],
        periodTable: <PortfolioCashflowPeriodAggregate>[],
      );
    }

    final sorted = List<PortfolioCashflowRecord>.from(cashflows)
      ..sort((a, b) => a.date.compareTo(b.date));
    final periodTable = aggregateByPeriod(sorted);

    final totalInflows = sorted
        .where((entry) => entry.amountSigned > 0)
        .fold<double>(0, (sum, entry) => sum + entry.amountSigned);
    final totalOutflows = sorted
        .where((entry) => entry.amountSigned < 0)
        .fold<double>(0, (sum, entry) => sum + entry.amountSigned.abs());
    final netCashflow = totalInflows - totalOutflows;
    final averageMonthlyNet =
        periodTable.isEmpty ? 0.0 : netCashflow / periodTable.length;

    final irr = computeXirr(sorted);
    final warning = irr == null ? 'Not enough signed variation for IRR.' : null;

    return PortfolioIrrResult(
      irr: irr,
      warning: warning,
      totalInflows: totalInflows,
      totalOutflows: totalOutflows,
      netCashflow: netCashflow,
      averageMonthlyNet: averageMonthlyNet,
      datedCashflows: sorted,
      periodTable: periodTable,
    );
  }

  List<PortfolioCashflowPeriodAggregate> aggregateByPeriod(
    List<PortfolioCashflowRecord> cashflows,
  ) {
    final grouped = <String, List<PortfolioCashflowRecord>>{};
    for (final row in cashflows) {
      grouped.putIfAbsent(row.periodKey, () => <PortfolioCashflowRecord>[]);
      grouped[row.periodKey]!.add(row);
    }
    final keys = grouped.keys.toList()..sort();
    return keys
        .map((key) {
          final rows = grouped[key]!;
          final inflows = rows
              .where((entry) => entry.amountSigned > 0)
              .fold<double>(0, (sum, entry) => sum + entry.amountSigned);
          final outflows = rows
              .where((entry) => entry.amountSigned < 0)
              .fold<double>(0, (sum, entry) => sum + entry.amountSigned.abs());
          return PortfolioCashflowPeriodAggregate(
            periodKey: key,
            totalInflows: inflows,
            totalOutflows: outflows,
            netCashflow: inflows - outflows,
          );
        })
        .toList(growable: false);
  }

  double? computeXirr(
    List<PortfolioCashflowRecord> cashflows, {
    int maxIterations = 200,
    double epsilon = 1e-7,
  }) {
    if (cashflows.length < 2) {
      return null;
    }
    final hasPositive = cashflows.any((entry) => entry.amountSigned > 0);
    final hasNegative = cashflows.any((entry) => entry.amountSigned < 0);
    if (!hasPositive || !hasNegative) {
      return null;
    }

    final sorted = List<PortfolioCashflowRecord>.from(cashflows)
      ..sort((a, b) => a.date.compareTo(b.date));
    final t0 = sorted.first.date;

    double npv(double rate) {
      var sum = 0.0;
      for (final entry in sorted) {
        final days = entry.date.difference(t0).inDays;
        final years = days / 365.0;
        sum += entry.amountSigned / _pow1p(rate, years);
      }
      return sum;
    }

    double dnpv(double rate) {
      var sum = 0.0;
      for (final entry in sorted) {
        final days = entry.date.difference(t0).inDays;
        final years = days / 365.0;
        if (years == 0) {
          continue;
        }
        sum -= (years * entry.amountSigned) / _pow1p(rate, years + 1);
      }
      return sum;
    }

    var guess = 0.1;
    for (var i = 0; i < maxIterations; i++) {
      final f = npv(guess);
      if (f.abs() < epsilon) {
        return guess;
      }
      final d = dnpv(guess);
      if (d.abs() < 1e-12) {
        break;
      }
      final next = guess - (f / d);
      if (!next.isFinite || next <= -0.9999) {
        break;
      }
      if ((next - guess).abs() < epsilon) {
        return next;
      }
      guess = next;
    }

    var low = -0.99;
    var high = 10.0;
    var lowValue = npv(low);
    var highValue = npv(high);
    if (lowValue * highValue > 0) {
      return null;
    }
    for (var i = 0; i < maxIterations; i++) {
      final mid = (low + high) / 2;
      final midValue = npv(mid);
      if (midValue.abs() < epsilon) {
        return mid;
      }
      if (lowValue * midValue <= 0) {
        high = mid;
        highValue = midValue;
      } else {
        low = mid;
        lowValue = midValue;
      }
    }
    return (low + high) / 2;
  }

  double _pow1p(double rate, double exponent) {
    final base = (1 + rate).clamp(1e-9, double.infinity).toDouble();
    return _pow(base, exponent);
  }

  double _pow(double base, double exponent) {
    if (exponent == 0) {
      return 1;
    }
    return math.pow(base, exponent).toDouble();
  }
}
