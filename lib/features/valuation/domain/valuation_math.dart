/// Deterministic valuation math shared across methods.
///
/// Every helper returns `null` for invalid inputs instead of a substitute
/// number, so callers surface "nicht ermittelbar" rather than a wrong value.
library;

import 'dart:math' as math;

/// Barwertfaktor / Vervielfältiger for an annuity of 1 per period over [years]
/// at interest rate [rate] (a fraction, e.g. `0.045` for 4.5 %):
///
///   V = (qⁿ − 1) / (qⁿ · (q − 1)),  with q = 1 + rate.
///
/// Used by the Ertragswertverfahren to capitalize the Gebäudereinertrag over
/// the Restnutzungsdauer. Returns `null` for `years <= 0` or `rate <= -1`.
double? presentValueAnnuityFactor({required double rate, required int years}) {
  if (years <= 0 || rate <= -1) return null;
  if (rate == 0) return years.toDouble();
  final q = 1 + rate;
  final qN = math.pow(q, years).toDouble();
  return (qN - 1) / (qN * (q - 1));
}

/// Present value of a single amount of 1 due in [years] at [rate]:
/// `1 / (1 + rate)^years`. Returns `null` for `years < 0` or `rate <= -1`.
double? discountFactor({required double rate, required int years}) {
  if (years < 0 || rate <= -1) return null;
  return 1 / math.pow(1 + rate, years);
}

/// Linear Alterswertminderung expressed as the *remaining* share of value per
/// the Sachwertverfahren: `1 − age / totalUsefulLife`, clamped to `[0, 1]`.
/// Returns `null` for `totalUsefulLife <= 0` or `age < 0`.
double? linearRemainingValueFactor({
  required int age,
  required int totalUsefulLife,
}) {
  if (totalUsefulLife <= 0 || age < 0) return null;
  return (1 - age / totalUsefulLife).clamp(0.0, 1.0);
}

/// Restnutzungsdauer = `max(0, Gesamtnutzungsdauer − Alter)`.
/// Returns `null` for `totalUsefulLife <= 0` or `age < 0`.
int? remainingUsefulLife({required int totalUsefulLife, required int age}) {
  if (totalUsefulLife <= 0 || age < 0) return null;
  final rnd = totalUsefulLife - age;
  return rnd < 0 ? 0 : rnd;
}
