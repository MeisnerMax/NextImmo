import 'settings.dart';

class IncomeLine {
  const IncomeLine({
    required this.id,
    required this.scenarioId,
    required this.name,
    required this.amountMonthly,
    required this.enabled,
  });

  final String id;
  final String scenarioId;
  final String name;
  final double amountMonthly;
  final bool enabled;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'scenario_id': scenarioId,
      'name': name,
      'amount_monthly': amountMonthly,
      'enabled': enabled ? 1 : 0,
    };
  }

  factory IncomeLine.fromMap(Map<String, Object?> map) {
    return IncomeLine(
      id: map['id']! as String,
      scenarioId: map['scenario_id']! as String,
      name: map['name']! as String,
      amountMonthly: ((map['amount_monthly'] as num?) ?? 0).toDouble(),
      enabled: ((map['enabled'] as num?) ?? 1) == 1,
    );
  }
}

class ExpenseLine {
  const ExpenseLine({
    required this.id,
    required this.scenarioId,
    required this.name,
    required this.kind,
    required this.amountMonthly,
    required this.percent,
    required this.enabled,
  });

  final String id;
  final String scenarioId;
  final String name;
  final String kind;
  final double amountMonthly;
  final double percent;
  final bool enabled;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'scenario_id': scenarioId,
      'name': name,
      'kind': kind,
      'amount_monthly': amountMonthly,
      'percent': percent,
      'enabled': enabled ? 1 : 0,
    };
  }

  factory ExpenseLine.fromMap(Map<String, Object?> map) {
    return ExpenseLine(
      id: map['id']! as String,
      scenarioId: map['scenario_id']! as String,
      name: map['name']! as String,
      kind: map['kind']! as String,
      amountMonthly: ((map['amount_monthly'] as num?) ?? 0).toDouble(),
      percent: ((map['percent'] as num?) ?? 0).toDouble(),
      enabled: ((map['enabled'] as num?) ?? 1) == 1,
    );
  }
}

class ScenarioInputs {
  const ScenarioInputs({
    required this.scenarioId,
    required this.purchasePrice,
    required this.rehabBudget,
    required this.closingCostBuyPercent,
    required this.closingCostBuyFixed,
    required this.holdMonths,
    required this.rentMonthlyTotal,
    required this.otherIncomeMonthly,
    required this.vacancyPercent,
    required this.propertyTaxMonthly,
    required this.insuranceMonthly,
    required this.utilitiesMonthly,
    required this.hoaMonthly,
    required this.managementPercent,
    required this.maintenancePercent,
    required this.capexPercent,
    required this.otherExpensesMonthly,
    required this.financingMode,
    required this.downPaymentPercent,
    required this.loanAmount,
    required this.interestRatePercent,
    required this.termYears,
    required this.amortizationType,
    required this.appreciationPercent,
    required this.rentGrowthPercent,
    required this.expenseGrowthPercent,
    required this.saleCostPercent,
    required this.closingCostSellPercent,
    required this.sellAfterYears,
    required this.arvOverride,
    required this.rentOverride,
    required this.updatedAt,
  });

  final String scenarioId;
  final double purchasePrice;
  final double rehabBudget;
  final double closingCostBuyPercent;
  final double closingCostBuyFixed;
  final int holdMonths;
  final double rentMonthlyTotal;
  final double otherIncomeMonthly;
  final double vacancyPercent;
  final double propertyTaxMonthly;
  final double insuranceMonthly;
  final double utilitiesMonthly;
  final double hoaMonthly;
  final double managementPercent;
  final double maintenancePercent;
  final double capexPercent;
  final double otherExpensesMonthly;
  final String financingMode;
  final double downPaymentPercent;
  final double loanAmount;
  final double interestRatePercent;
  final int termYears;
  final String amortizationType;
  final double appreciationPercent;
  final double rentGrowthPercent;
  final double expenseGrowthPercent;
  final double saleCostPercent;
  final double closingCostSellPercent;
  final int sellAfterYears;
  final double? arvOverride;
  final double? rentOverride;
  final int updatedAt;

  ScenarioInputs copyWith({
    double? purchasePrice,
    double? rehabBudget,
    double? closingCostBuyPercent,
    double? closingCostBuyFixed,
    int? holdMonths,
    double? rentMonthlyTotal,
    double? otherIncomeMonthly,
    double? vacancyPercent,
    double? propertyTaxMonthly,
    double? insuranceMonthly,
    double? utilitiesMonthly,
    double? hoaMonthly,
    double? managementPercent,
    double? maintenancePercent,
    double? capexPercent,
    double? otherExpensesMonthly,
    String? financingMode,
    double? downPaymentPercent,
    double? loanAmount,
    double? interestRatePercent,
    int? termYears,
    String? amortizationType,
    double? appreciationPercent,
    double? rentGrowthPercent,
    double? expenseGrowthPercent,
    double? saleCostPercent,
    double? closingCostSellPercent,
    int? sellAfterYears,
    double? arvOverride,
    bool clearArvOverride = false,
    double? rentOverride,
    bool clearRentOverride = false,
    int? updatedAt,
  }) {
    return ScenarioInputs(
      scenarioId: scenarioId,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      rehabBudget: rehabBudget ?? this.rehabBudget,
      closingCostBuyPercent:
          closingCostBuyPercent ?? this.closingCostBuyPercent,
      closingCostBuyFixed: closingCostBuyFixed ?? this.closingCostBuyFixed,
      holdMonths: holdMonths ?? this.holdMonths,
      rentMonthlyTotal: rentMonthlyTotal ?? this.rentMonthlyTotal,
      otherIncomeMonthly: otherIncomeMonthly ?? this.otherIncomeMonthly,
      vacancyPercent: vacancyPercent ?? this.vacancyPercent,
      propertyTaxMonthly: propertyTaxMonthly ?? this.propertyTaxMonthly,
      insuranceMonthly: insuranceMonthly ?? this.insuranceMonthly,
      utilitiesMonthly: utilitiesMonthly ?? this.utilitiesMonthly,
      hoaMonthly: hoaMonthly ?? this.hoaMonthly,
      managementPercent: managementPercent ?? this.managementPercent,
      maintenancePercent: maintenancePercent ?? this.maintenancePercent,
      capexPercent: capexPercent ?? this.capexPercent,
      otherExpensesMonthly: otherExpensesMonthly ?? this.otherExpensesMonthly,
      financingMode: financingMode ?? this.financingMode,
      downPaymentPercent: downPaymentPercent ?? this.downPaymentPercent,
      loanAmount: loanAmount ?? this.loanAmount,
      interestRatePercent: interestRatePercent ?? this.interestRatePercent,
      termYears: termYears ?? this.termYears,
      amortizationType: amortizationType ?? this.amortizationType,
      appreciationPercent: appreciationPercent ?? this.appreciationPercent,
      rentGrowthPercent: rentGrowthPercent ?? this.rentGrowthPercent,
      expenseGrowthPercent: expenseGrowthPercent ?? this.expenseGrowthPercent,
      saleCostPercent: saleCostPercent ?? this.saleCostPercent,
      closingCostSellPercent:
          closingCostSellPercent ?? this.closingCostSellPercent,
      sellAfterYears: sellAfterYears ?? this.sellAfterYears,
      arvOverride: clearArvOverride ? null : (arvOverride ?? this.arvOverride),
      rentOverride:
          clearRentOverride ? null : (rentOverride ?? this.rentOverride),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static ScenarioInputs defaults({
    required String scenarioId,
    required AppSettingsRecord settings,
  }) {
    return ScenarioInputs(
      scenarioId: scenarioId,
      purchasePrice: 0,
      rehabBudget: 0,
      closingCostBuyPercent: settings.defaultClosingCostBuyPercent,
      closingCostBuyFixed: 0,
      holdMonths: settings.defaultHorizonYears * 12,
      rentMonthlyTotal: 0,
      otherIncomeMonthly: 0,
      vacancyPercent: settings.defaultVacancyPercent,
      propertyTaxMonthly: 0,
      insuranceMonthly: 0,
      utilitiesMonthly: 0,
      hoaMonthly: 0,
      managementPercent: settings.defaultManagementPercent,
      maintenancePercent: settings.defaultMaintenancePercent,
      capexPercent: settings.defaultCapexPercent,
      otherExpensesMonthly: 0,
      financingMode: 'cash',
      downPaymentPercent: settings.defaultDownPaymentPercent,
      loanAmount: 0,
      interestRatePercent: settings.defaultInterestRatePercent,
      termYears: settings.defaultTermYears,
      amortizationType: 'standard',
      appreciationPercent: settings.defaultAppreciationPercent,
      rentGrowthPercent: settings.defaultRentGrowthPercent,
      expenseGrowthPercent: settings.defaultExpenseGrowthPercent,
      saleCostPercent: settings.defaultSaleCostPercent,
      closingCostSellPercent: settings.defaultClosingCostSellPercent,
      sellAfterYears: settings.defaultHorizonYears,
      arvOverride: null,
      rentOverride: null,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'scenario_id': scenarioId,
      'purchase_price': purchasePrice,
      'rehab_budget': rehabBudget,
      'closing_cost_buy_percent': closingCostBuyPercent,
      'closing_cost_buy_fixed': closingCostBuyFixed,
      'hold_months': holdMonths,
      'rent_monthly_total': rentMonthlyTotal,
      'other_income_monthly': otherIncomeMonthly,
      'vacancy_percent': vacancyPercent,
      'property_tax_monthly': propertyTaxMonthly,
      'insurance_monthly': insuranceMonthly,
      'utilities_monthly': utilitiesMonthly,
      'hoa_monthly': hoaMonthly,
      'management_percent': managementPercent,
      'maintenance_percent': maintenancePercent,
      'capex_percent': capexPercent,
      'other_expenses_monthly': otherExpensesMonthly,
      'financing_mode': financingMode,
      'down_payment_percent': downPaymentPercent,
      'loan_amount': loanAmount,
      'interest_rate_percent': interestRatePercent,
      'term_years': termYears,
      'amortization_type': amortizationType,
      'appreciation_percent': appreciationPercent,
      'rent_growth_percent': rentGrowthPercent,
      'expense_growth_percent': expenseGrowthPercent,
      'sale_cost_percent': saleCostPercent,
      'closing_cost_sell_percent': closingCostSellPercent,
      'sell_after_years': sellAfterYears,
      'arv_override': arvOverride,
      'rent_override': rentOverride,
      'updated_at': updatedAt,
    };
  }

  factory ScenarioInputs.fromMap(Map<String, Object?> map) {
    return ScenarioInputs(
      scenarioId: map['scenario_id']! as String,
      purchasePrice: ((map['purchase_price'] as num?) ?? 0).toDouble(),
      rehabBudget: ((map['rehab_budget'] as num?) ?? 0).toDouble(),
      closingCostBuyPercent:
          ((map['closing_cost_buy_percent'] as num?) ?? 0).toDouble(),
      closingCostBuyFixed:
          ((map['closing_cost_buy_fixed'] as num?) ?? 0).toDouble(),
      holdMonths: ((map['hold_months'] as num?) ?? 12).toInt(),
      rentMonthlyTotal: ((map['rent_monthly_total'] as num?) ?? 0).toDouble(),
      otherIncomeMonthly:
          ((map['other_income_monthly'] as num?) ?? 0).toDouble(),
      vacancyPercent: ((map['vacancy_percent'] as num?) ?? 0).toDouble(),
      propertyTaxMonthly:
          ((map['property_tax_monthly'] as num?) ?? 0).toDouble(),
      insuranceMonthly: ((map['insurance_monthly'] as num?) ?? 0).toDouble(),
      utilitiesMonthly: ((map['utilities_monthly'] as num?) ?? 0).toDouble(),
      hoaMonthly: ((map['hoa_monthly'] as num?) ?? 0).toDouble(),
      managementPercent: ((map['management_percent'] as num?) ?? 0).toDouble(),
      maintenancePercent:
          ((map['maintenance_percent'] as num?) ?? 0).toDouble(),
      capexPercent: ((map['capex_percent'] as num?) ?? 0).toDouble(),
      otherExpensesMonthly:
          ((map['other_expenses_monthly'] as num?) ?? 0).toDouble(),
      financingMode: (map['financing_mode'] as String?) ?? 'cash',
      downPaymentPercent:
          ((map['down_payment_percent'] as num?) ?? 0).toDouble(),
      loanAmount: ((map['loan_amount'] as num?) ?? 0).toDouble(),
      interestRatePercent:
          ((map['interest_rate_percent'] as num?) ?? 0).toDouble(),
      termYears: ((map['term_years'] as num?) ?? 30).toInt(),
      amortizationType: (map['amortization_type'] as String?) ?? 'standard',
      appreciationPercent:
          ((map['appreciation_percent'] as num?) ?? 0).toDouble(),
      rentGrowthPercent: ((map['rent_growth_percent'] as num?) ?? 0).toDouble(),
      expenseGrowthPercent:
          ((map['expense_growth_percent'] as num?) ?? 0).toDouble(),
      saleCostPercent: ((map['sale_cost_percent'] as num?) ?? 0).toDouble(),
      closingCostSellPercent:
          ((map['closing_cost_sell_percent'] as num?) ?? 0).toDouble(),
      sellAfterYears: ((map['sell_after_years'] as num?) ?? 10).toInt(),
      arvOverride: (map['arv_override'] as num?)?.toDouble(),
      rentOverride: (map['rent_override'] as num?)?.toDouble(),
      updatedAt:
          ((map['updated_at'] as num?) ?? DateTime.now().millisecondsSinceEpoch)
              .toInt(),
    );
  }
}

class NormalizedInputs {
  const NormalizedInputs({
    required this.currencyCode,
    required this.horizonMonths,
    required this.horizonYears,
    required this.inputs,
    required this.incomeLines,
    required this.expenseLines,
  });

  final String currencyCode;
  final int horizonMonths;
  final int horizonYears;
  final ScenarioInputs inputs;
  final List<IncomeLine> incomeLines;
  final List<ExpenseLine> expenseLines;

  double get effectiveRentMonthly =>
      inputs.rentOverride ?? inputs.rentMonthlyTotal;

  double get enabledIncomeLinesMonthly => incomeLines
      .where((line) => line.enabled)
      .fold<double>(0, (sum, line) => sum + line.amountMonthly);

  double get enabledExpenseLinesFixedMonthly => expenseLines
      .where((line) => line.enabled && line.kind == 'fixed')
      .fold<double>(0, (sum, line) => sum + line.amountMonthly);

  double get enabledExpenseLinesPercent => expenseLines
      .where((line) => line.enabled && line.kind == 'percent_of_rent')
      .fold<double>(0, (sum, line) => sum + line.percent);
}
