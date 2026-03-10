import '../models/inputs.dart';
import '../models/settings.dart';

NormalizedInputs normalizeInputs({
  required ScenarioInputs inputs,
  required AppSettingsRecord settings,
  required List<IncomeLine> incomeLines,
  required List<ExpenseLine> expenseLines,
}) {
  final effectiveHoldMonths =
      inputs.holdMonths > 0
          ? inputs.holdMonths
          : ((inputs.sellAfterYears <= 0
                  ? settings.defaultHorizonYears
                  : inputs.sellAfterYears) *
              12);
  final effectiveHorizonYears = (effectiveHoldMonths / 12).ceil();

  final normalized = inputs.copyWith(
    closingCostBuyPercent: _sanitizePercent(
      inputs.closingCostBuyPercent,
      settings.defaultClosingCostBuyPercent,
    ),
    vacancyPercent: _sanitizePercent(
      inputs.vacancyPercent,
      settings.defaultVacancyPercent,
    ),
    managementPercent: _sanitizePercent(
      inputs.managementPercent,
      settings.defaultManagementPercent,
    ),
    maintenancePercent: _sanitizePercent(
      inputs.maintenancePercent,
      settings.defaultMaintenancePercent,
    ),
    capexPercent: _sanitizePercent(
      inputs.capexPercent,
      settings.defaultCapexPercent,
    ),
    downPaymentPercent: _sanitizePercent(inputs.downPaymentPercent, 0.25),
    interestRatePercent: _sanitizePercent(inputs.interestRatePercent, 0.06),
    appreciationPercent: _sanitizePercent(
      inputs.appreciationPercent,
      settings.defaultAppreciationPercent,
    ),
    rentGrowthPercent: _sanitizePercent(
      inputs.rentGrowthPercent,
      settings.defaultRentGrowthPercent,
    ),
    expenseGrowthPercent: _sanitizePercent(
      inputs.expenseGrowthPercent,
      settings.defaultExpenseGrowthPercent,
    ),
    saleCostPercent: _sanitizePercent(
      inputs.saleCostPercent,
      settings.defaultSaleCostPercent,
    ),
    closingCostSellPercent: _sanitizePercent(
      inputs.closingCostSellPercent,
      settings.defaultClosingCostSellPercent,
    ),
    holdMonths: effectiveHoldMonths,
    sellAfterYears: effectiveHorizonYears,
    termYears: inputs.termYears <= 0 ? 30 : inputs.termYears,
  );

  return NormalizedInputs(
    currencyCode: settings.currencyCode,
    horizonMonths: effectiveHoldMonths,
    horizonYears: effectiveHorizonYears,
    inputs: normalized,
    incomeLines: incomeLines,
    expenseLines: expenseLines,
  );
}

double _sanitizePercent(double value, double fallback) {
  if (value.isNaN || value.isInfinite || value < 0) {
    return fallback;
  }
  if (value > 1.0) {
    return value / 100.0;
  }
  return value;
}
