import 'dart:math' as math;

import 'valuation_math.dart';

/// How the DCF terminal value is derived at the end of the hold period.
enum DcfTerminalMethod {
  /// Terminal value = forward NOI / exit cap rate.
  exitCap('exit_cap'),

  /// Gordon growth: terminal value = forward NOI / (discount − growth).
  gordonGrowth('gordon_growth');

  const DcfTerminalMethod(this.wireName);

  final String wireName;

  static DcfTerminalMethod? fromWire(String? value) {
    for (final terminal in DcfTerminalMethod.values) {
      if (terminal.wireName == value) return terminal;
    }
    return null;
  }
}

/// One projected annual period.
class ProjectionYear {
  const ProjectionYear({
    required this.year,
    required this.grossRent,
    required this.vacancyLoss,
    required this.effectiveGrossIncome,
    required this.operatingExpenses,
    required this.netOperatingIncome,
  });

  final int year;
  final double grossRent;
  final double vacancyLoss;
  final double effectiveGrossIncome;
  final double operatingExpenses;
  final double netOperatingIncome;
}

/// Deterministic DCF result: the annual projection plus the discounted asset
/// value (unlevered) and its terminal-value components.
class DcfValuation {
  const DcfValuation({
    required this.years,
    required this.forwardNoi,
    required this.terminalValue,
    required this.netTerminalValue,
    required this.presentValueOfIncome,
    required this.presentValueOfTerminal,
    required this.assetValue,
  });

  final List<ProjectionYear> years;

  /// NOI of the year *after* the hold period (year N+1), used to capitalize the
  /// terminal value.
  final double forwardNoi;
  final double terminalValue;
  final double netTerminalValue;
  final double presentValueOfIncome;
  final double presentValueOfTerminal;
  final double assetValue;
}

double _noiAt({
  required int year, // 1-based
  required double grossRentAnnual,
  required double vacancyRate,
  required double operatingExpensesAnnual,
  required double rentGrowthRate,
  required double expenseGrowthRate,
}) {
  final rentFactor = math.pow(1 + rentGrowthRate, year - 1).toDouble();
  final expenseFactor = math.pow(1 + expenseGrowthRate, year - 1).toDouble();
  final grossRent = grossRentAnnual * rentFactor;
  final egi = grossRent * (1 - vacancyRate);
  final opex = operatingExpensesAnnual * expenseFactor;
  return egi - opex;
}

/// Builds an annual projection and discounts NOI + net terminal value to an
/// unlevered asset value. Returns `null` only when the terminal method is
/// infeasible (missing/≤0 exit cap, or discount ≤ terminal growth) or the hold
/// period is non-positive — the caller then reports "nicht ermittelbar".
DcfValuation? computeDcfValuation({
  required double grossRentAnnual,
  required double vacancyRate,
  required double operatingExpensesAnnual,
  required double rentGrowthRate,
  required double expenseGrowthRate,
  required int holdYears,
  required double discountRate,
  required double saleCostRate,
  required DcfTerminalMethod terminal,
  double? exitCapRate,
  double? terminalGrowthRate,
}) {
  if (holdYears <= 0 || discountRate <= -1) return null;

  final years = <ProjectionYear>[];
  var presentValueOfIncome = 0.0;
  for (var t = 1; t <= holdYears; t++) {
    final rentFactor = math.pow(1 + rentGrowthRate, t - 1).toDouble();
    final expenseFactor = math.pow(1 + expenseGrowthRate, t - 1).toDouble();
    final grossRent = grossRentAnnual * rentFactor;
    final vacancyLoss = grossRent * vacancyRate;
    final egi = grossRent - vacancyLoss;
    final opex = operatingExpensesAnnual * expenseFactor;
    final noi = egi - opex;
    years.add(
      ProjectionYear(
        year: t,
        grossRent: grossRent,
        vacancyLoss: vacancyLoss,
        effectiveGrossIncome: egi,
        operatingExpenses: opex,
        netOperatingIncome: noi,
      ),
    );
    presentValueOfIncome += noi * discountFactor(rate: discountRate, years: t)!;
  }

  final forwardNoi = _noiAt(
    year: holdYears + 1,
    grossRentAnnual: grossRentAnnual,
    vacancyRate: vacancyRate,
    operatingExpensesAnnual: operatingExpensesAnnual,
    rentGrowthRate: rentGrowthRate,
    expenseGrowthRate: expenseGrowthRate,
  );

  final double terminalValue;
  switch (terminal) {
    case DcfTerminalMethod.exitCap:
      if (exitCapRate == null || exitCapRate <= 0) return null;
      terminalValue = forwardNoi / exitCapRate;
    case DcfTerminalMethod.gordonGrowth:
      final g = terminalGrowthRate;
      if (g == null || discountRate <= g) return null;
      terminalValue = forwardNoi / (discountRate - g);
  }

  final netTerminalValue = terminalValue * (1 - saleCostRate);
  final presentValueOfTerminal =
      netTerminalValue * discountFactor(rate: discountRate, years: holdYears)!;

  return DcfValuation(
    years: years,
    forwardNoi: forwardNoi,
    terminalValue: terminalValue,
    netTerminalValue: netTerminalValue,
    presentValueOfIncome: presentValueOfIncome,
    presentValueOfTerminal: presentValueOfTerminal,
    assetValue: presentValueOfIncome + presentValueOfTerminal,
  );
}
