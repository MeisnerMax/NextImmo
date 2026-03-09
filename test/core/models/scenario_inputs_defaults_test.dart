import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/settings.dart';

void main() {
  test('new scenario defaults use configured settings values', () {
    final settings = AppSettingsRecord(
      defaultHorizonYears: 14,
      defaultVacancyPercent: 0.11,
      defaultManagementPercent: 0.12,
      defaultMaintenancePercent: 0.08,
      defaultCapexPercent: 0.07,
      defaultAppreciationPercent: 0.04,
      defaultRentGrowthPercent: 0.03,
      defaultExpenseGrowthPercent: 0.025,
      defaultSaleCostPercent: 0.055,
      defaultClosingCostBuyPercent: 0.021,
      defaultClosingCostSellPercent: 0.019,
      defaultDownPaymentPercent: 0.35,
      defaultInterestRatePercent: 0.052,
      defaultTermYears: 20,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final inputs = ScenarioInputs.defaults(
      scenarioId: 's1',
      settings: settings,
    );

    expect(inputs.vacancyPercent, settings.defaultVacancyPercent);
    expect(inputs.managementPercent, settings.defaultManagementPercent);
    expect(inputs.maintenancePercent, settings.defaultMaintenancePercent);
    expect(inputs.capexPercent, settings.defaultCapexPercent);
    expect(inputs.appreciationPercent, settings.defaultAppreciationPercent);
    expect(inputs.rentGrowthPercent, settings.defaultRentGrowthPercent);
    expect(inputs.expenseGrowthPercent, settings.defaultExpenseGrowthPercent);
    expect(inputs.saleCostPercent, settings.defaultSaleCostPercent);
    expect(inputs.closingCostBuyPercent, settings.defaultClosingCostBuyPercent);
    expect(
      inputs.closingCostSellPercent,
      settings.defaultClosingCostSellPercent,
    );
    expect(inputs.sellAfterYears, settings.defaultHorizonYears);
    expect(inputs.downPaymentPercent, settings.defaultDownPaymentPercent);
    expect(inputs.interestRatePercent, settings.defaultInterestRatePercent);
    expect(inputs.termYears, settings.defaultTermYears);
  });
}
