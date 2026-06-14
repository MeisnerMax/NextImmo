class FormulaAuditEntry {
  const FormulaAuditEntry({
    required this.formulaName,
    required this.description,
    required this.inputs,
    required this.result,
    required this.unit,
    required this.module,
    this.propertyId,
    this.scenarioId,
    required this.calculatedAt,
  });

  final String formulaName;
  final String description;
  final Map<String, Object?> inputs;
  final double? result;
  final String unit;
  final String module;
  final String? propertyId;
  final String? scenarioId;
  final int calculatedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'formula_name': formulaName,
      'description': description,
      'inputs': inputs,
      'result': result,
      'unit': unit,
      'module': module,
      'property_id': propertyId,
      'scenario_id': scenarioId,
      'calculated_at': calculatedAt,
    };
  }
}

class ModuleDatasheet {
  const ModuleDatasheet({
    required this.id,
    required this.module,
    required this.title,
    this.propertyId,
    this.scenarioId,
    required this.createdAt,
    required this.header,
    required this.executiveSummary,
    required this.inputData,
    required this.assumptions,
    required this.calculations,
    required this.metrics,
    required this.sensitivities,
    required this.risks,
    required this.recommendation,
    required this.formulaAppendix,
    required this.dataQuality,
  });

  final String id;
  final String module;
  final String title;
  final String? propertyId;
  final String? scenarioId;
  final int createdAt;
  final Map<String, Object?> header;
  final Map<String, Object?> executiveSummary;
  final Map<String, Object?> inputData;
  final Map<String, Object?> assumptions;
  final List<Map<String, Object?>> calculations;
  final Map<String, Object?> metrics;
  final Map<String, Object?> sensitivities;
  final List<String> risks;
  final String recommendation;
  final List<Map<String, Object?>> formulaAppendix;
  final Map<String, Object?> dataQuality;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'module': module,
      'title': title,
      'property_id': propertyId,
      'scenario_id': scenarioId,
      'created_at': createdAt,
      'header': header,
      'executive_summary': executiveSummary,
      'input_data': inputData,
      'assumptions': assumptions,
      'calculations': calculations,
      'metrics': metrics,
      'sensitivities': sensitivities,
      'risks': risks,
      'recommendation': recommendation,
      'formula_appendix': formulaAppendix,
      'data_quality': dataQuality,
    };
  }
}

class AcquisitionQuickInputs {
  const AcquisitionQuickInputs({
    required this.objectName,
    this.address,
    this.city,
    this.federalState,
    required this.propertyType,
    this.yearBuilt,
    required this.residentialAreaSqm,
    required this.commercialAreaSqm,
    required this.landAreaSqm,
    required this.units,
    required this.vacancyPercent,
    required this.condition,
    required this.monumentProtected,
    this.energyClass,
    this.notes,
    required this.offerPrice,
    required this.closingCostPercent,
    required this.brokerFee,
    required this.transferTax,
    required this.notaryAndLandRegistry,
    required this.otherAcquisitionCosts,
    required this.renovationBudget,
    required this.renovationSafetyPercent,
    required this.currentColdRentMonthly,
    required this.marketRentPerSqm,
    required this.otherIncomeMonthly,
    required this.nonRecoverableCostsMonthly,
    required this.maintenancePerSqmYear,
    required this.managementCostsMonthly,
    required this.insuranceMonthly,
    required this.propertyTaxMonthly,
    required this.otherCostsMonthly,
    required this.equity,
    required this.loanAmount,
    required this.interestRatePercent,
    required this.amortizationPercent,
    required this.loanTermYears,
    required this.minimumCashflow,
    required this.minimumGrossYield,
    required this.minimumCapRate,
    required this.minimumCashOnCash,
    required this.maxPurchasePricePerSqm,
    required this.maxLoanToValue,
    required this.maxRenovationShare,
    required this.targetCapRate,
    required this.desiredMargin,
  });

  final String objectName;
  final String? address;
  final String? city;
  final String? federalState;
  final String propertyType;
  final int? yearBuilt;
  final double residentialAreaSqm;
  final double commercialAreaSqm;
  final double landAreaSqm;
  final int units;
  final double vacancyPercent;
  final String condition;
  final bool monumentProtected;
  final String? energyClass;
  final String? notes;
  final double offerPrice;
  final double closingCostPercent;
  final double brokerFee;
  final double transferTax;
  final double notaryAndLandRegistry;
  final double otherAcquisitionCosts;
  final double renovationBudget;
  final double renovationSafetyPercent;
  final double currentColdRentMonthly;
  final double marketRentPerSqm;
  final double otherIncomeMonthly;
  final double nonRecoverableCostsMonthly;
  final double maintenancePerSqmYear;
  final double managementCostsMonthly;
  final double insuranceMonthly;
  final double propertyTaxMonthly;
  final double otherCostsMonthly;
  final double equity;
  final double loanAmount;
  final double interestRatePercent;
  final double amortizationPercent;
  final int loanTermYears;
  final double minimumCashflow;
  final double minimumGrossYield;
  final double minimumCapRate;
  final double minimumCashOnCash;
  final double maxPurchasePricePerSqm;
  final double maxLoanToValue;
  final double maxRenovationShare;
  final double targetCapRate;
  final double desiredMargin;

  double get totalAreaSqm => residentialAreaSqm + commercialAreaSqm;
  double get possibleRentMonthly => marketRentPerSqm * totalAreaSqm;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'object_name': objectName,
      'address': address,
      'city': city,
      'federal_state': federalState,
      'property_type': propertyType,
      'year_built': yearBuilt,
      'residential_area_sqm': residentialAreaSqm,
      'commercial_area_sqm': commercialAreaSqm,
      'land_area_sqm': landAreaSqm,
      'units': units,
      'vacancy_percent': vacancyPercent,
      'condition': condition,
      'monument_protected': monumentProtected,
      'energy_class': energyClass,
      'notes': notes,
      'offer_price': offerPrice,
      'closing_cost_percent': closingCostPercent,
      'broker_fee': brokerFee,
      'transfer_tax': transferTax,
      'notary_and_land_registry': notaryAndLandRegistry,
      'other_acquisition_costs': otherAcquisitionCosts,
      'renovation_budget': renovationBudget,
      'renovation_safety_percent': renovationSafetyPercent,
      'current_cold_rent_monthly': currentColdRentMonthly,
      'market_rent_per_sqm': marketRentPerSqm,
      'possible_rent_monthly': possibleRentMonthly,
      'other_income_monthly': otherIncomeMonthly,
      'non_recoverable_costs_monthly': nonRecoverableCostsMonthly,
      'maintenance_per_sqm_year': maintenancePerSqmYear,
      'management_costs_monthly': managementCostsMonthly,
      'insurance_monthly': insuranceMonthly,
      'property_tax_monthly': propertyTaxMonthly,
      'other_costs_monthly': otherCostsMonthly,
      'equity': equity,
      'loan_amount': loanAmount,
      'interest_rate_percent': interestRatePercent,
      'amortization_percent': amortizationPercent,
      'loan_term_years': loanTermYears,
      'minimum_cashflow': minimumCashflow,
      'minimum_gross_yield': minimumGrossYield,
      'minimum_cap_rate': minimumCapRate,
      'minimum_cash_on_cash': minimumCashOnCash,
      'max_purchase_price_per_sqm': maxPurchasePricePerSqm,
      'max_loan_to_value': maxLoanToValue,
      'max_renovation_share': maxRenovationShare,
      'target_cap_rate': targetCapRate,
      'desired_margin': desiredMargin,
    };
  }
}

class CriterionTrafficLight {
  const CriterionTrafficLight({
    required this.label,
    required this.value,
    required this.target,
    required this.status,
  });

  final String label;
  final double value;
  final double target;
  final String status;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'value': value,
      'target': target,
      'status': status,
    };
  }
}

class AcquisitionQuickResult {
  const AcquisitionQuickResult({
    required this.purchasePricePerSqm,
    required this.totalInvestment,
    required this.grossInitialYield,
    required this.netInitialYield,
    required this.effectiveGrossIncome,
    required this.operatingExpenses,
    required this.noi,
    required this.debtServiceAnnual,
    required this.cashflowBeforeTax,
    required this.cashOnCash,
    required this.loanToValue,
    required this.valueBasedOnCapRate,
    required this.maxReasonablePurchasePrice,
    required this.score,
    required this.recommendation,
    required this.criteria,
    required this.warnings,
    required this.formulas,
  });

  final double? purchasePricePerSqm;
  final double totalInvestment;
  final double? grossInitialYield;
  final double? netInitialYield;
  final double effectiveGrossIncome;
  final double operatingExpenses;
  final double noi;
  final double debtServiceAnnual;
  final double cashflowBeforeTax;
  final double? cashOnCash;
  final double? loanToValue;
  final double? valueBasedOnCapRate;
  final double? maxReasonablePurchasePrice;
  final int score;
  final String recommendation;
  final List<CriterionTrafficLight> criteria;
  final List<String> warnings;
  final List<FormulaAuditEntry> formulas;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'purchase_price_per_sqm': purchasePricePerSqm,
      'total_investment': totalInvestment,
      'gross_initial_yield': grossInitialYield,
      'net_initial_yield': netInitialYield,
      'effective_gross_income': effectiveGrossIncome,
      'operating_expenses': operatingExpenses,
      'noi': noi,
      'debt_service_annual': debtServiceAnnual,
      'cashflow_before_tax': cashflowBeforeTax,
      'cash_on_cash': cashOnCash,
      'loan_to_value': loanToValue,
      'value_based_on_cap_rate': valueBasedOnCapRate,
      'max_reasonable_purchase_price': maxReasonablePurchasePrice,
      'score': score,
      'recommendation': recommendation,
      'criteria': criteria.map((item) => item.toJson()).toList(),
      'warnings': warnings,
      'formulas': formulas.map((item) => item.toJson()).toList(),
    };
  }
}

class RenovationMeasureInput {
  const RenovationMeasureInput({
    required this.measureType,
    required this.category,
    this.trade,
    this.description,
    this.status = 'planned',
    this.dueDate,
    this.responsible,
    required this.affectedAreaSqm,
    required this.budgetAmount,
    required this.committedAmount,
    required this.actualAmount,
    required this.remainingAmount,
    required this.isRequired,
    required this.isValueAdd,
    required this.isRecoverable,
    required this.isFundable,
    required this.requiresPermit,
  });

  final String measureType;
  final String category;
  final String? trade;
  final String? description;
  final String status;
  final String? dueDate;
  final String? responsible;
  final double affectedAreaSqm;
  final double budgetAmount;
  final double committedAmount;
  final double actualAmount;
  final double remainingAmount;
  final bool isRequired;
  final bool isValueAdd;
  final bool isRecoverable;
  final bool isFundable;
  final bool requiresPermit;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'measure_type': measureType,
      'category': category,
      'trade': trade,
      'description': description,
      'status': status,
      'due_date': dueDate,
      'responsible': responsible,
      'affected_area_sqm': affectedAreaSqm,
      'budget_amount': budgetAmount,
      'committed_amount': committedAmount,
      'actual_amount': actualAmount,
      'remaining_amount': remainingAmount,
      'is_required': isRequired,
      'is_value_add': isValueAdd,
      'is_recoverable': isRecoverable,
      'is_fundable': isFundable,
      'requires_permit': requiresPermit,
    };
  }
}

class RenovationModuleInputs {
  const RenovationModuleInputs({
    required this.projectName,
    this.propertyId,
    this.unitId,
    this.projectType,
    this.projectStatus = 'idea',
    this.startDate,
    this.plannedEndDate,
    this.actualEndDate,
    this.responsible,
    this.priority = 'medium',
    this.description,
    this.permitRequired = false,
    this.permitStatus = 'not_required',
    this.permitSubmittedDate,
    this.permitApprovalDate,
    this.subsidyProgram,
    this.modernizationLegalBasis,
    required this.budget,
    required this.actualCosts,
    required this.expectedRemainingCosts,
    required this.reservePercent,
    required this.maintenanceShare,
    required this.subsidies,
    required this.insuranceRecoveries,
    required this.nonRecoverableCostShare,
    required this.modernizationCapPerSqm,
    required this.affectedAreaSqm,
    required this.currentRentMonthly,
    required this.targetRentMonthly,
    required this.vacancyMonthsDuringWorks,
    required this.noiBefore,
    required this.noiAfter,
    required this.capRateBefore,
    required this.capRateAfter,
    required this.totalInvestmentAfterRenovation,
    required this.targetYield,
    required this.renovationHorizonYears,
    required this.discountRate,
    required this.plannedConstructionMonths,
    required this.actualConstructionMonths,
    required this.delayCostPerMonth,
    required this.permitRisk,
    required this.costRisk,
    required this.rentLossRisk,
    required this.technicalRisk,
    required this.contractorAvailabilityRisk,
    required this.riskBufferPercent,
  });

  final String projectName;
  final String? propertyId;
  final String? unitId;
  final String? projectType;
  final String projectStatus;
  final String? startDate;
  final String? plannedEndDate;
  final String? actualEndDate;
  final String? responsible;
  final String priority;
  final String? description;
  final bool permitRequired;
  final String permitStatus;
  final String? permitSubmittedDate;
  final String? permitApprovalDate;
  final String? subsidyProgram;
  final String? modernizationLegalBasis;
  final double budget;
  final double actualCosts;
  final double expectedRemainingCosts;
  final double reservePercent;
  final double maintenanceShare;
  final double subsidies;
  final double insuranceRecoveries;
  final double nonRecoverableCostShare;
  final double modernizationCapPerSqm;
  final double affectedAreaSqm;
  final double currentRentMonthly;
  final double targetRentMonthly;
  final double vacancyMonthsDuringWorks;
  final double noiBefore;
  final double noiAfter;
  final double capRateBefore;
  final double capRateAfter;
  final double totalInvestmentAfterRenovation;
  final double targetYield;
  final int renovationHorizonYears;
  final double discountRate;
  final double plannedConstructionMonths;
  final double actualConstructionMonths;
  final double delayCostPerMonth;
  final int permitRisk;
  final int costRisk;
  final int rentLossRisk;
  final int technicalRisk;
  final int contractorAvailabilityRisk;
  final double riskBufferPercent;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'project_name': projectName,
      'property_id': propertyId,
      'unit_id': unitId,
      'project_type': projectType,
      'project_status': projectStatus,
      'start_date': startDate,
      'planned_end_date': plannedEndDate,
      'actual_end_date': actualEndDate,
      'responsible': responsible,
      'priority': priority,
      'description': description,
      'permit_required': permitRequired,
      'permit_status': permitStatus,
      'permit_submitted_date': permitSubmittedDate,
      'permit_approval_date': permitApprovalDate,
      'subsidy_program': subsidyProgram,
      'modernization_legal_basis': modernizationLegalBasis,
      'budget': budget,
      'actual_costs': actualCosts,
      'expected_remaining_costs': expectedRemainingCosts,
      'reserve_percent': reservePercent,
      'maintenance_share': maintenanceShare,
      'subsidies': subsidies,
      'insurance_recoveries': insuranceRecoveries,
      'non_recoverable_cost_share': nonRecoverableCostShare,
      'modernization_cap_per_sqm': modernizationCapPerSqm,
      'affected_area_sqm': affectedAreaSqm,
      'current_rent_monthly': currentRentMonthly,
      'target_rent_monthly': targetRentMonthly,
      'vacancy_months_during_works': vacancyMonthsDuringWorks,
      'noi_before': noiBefore,
      'noi_after': noiAfter,
      'cap_rate_before': capRateBefore,
      'cap_rate_after': capRateAfter,
      'total_investment_after_renovation': totalInvestmentAfterRenovation,
      'target_yield': targetYield,
      'renovation_horizon_years': renovationHorizonYears,
      'discount_rate': discountRate,
      'planned_construction_months': plannedConstructionMonths,
      'actual_construction_months': actualConstructionMonths,
      'delay_cost_per_month': delayCostPerMonth,
      'permit_risk': permitRisk,
      'cost_risk': costRisk,
      'rent_loss_risk': rentLossRisk,
      'technical_risk': technicalRisk,
      'contractor_availability_risk': contractorAvailabilityRisk,
      'risk_buffer_percent': riskBufferPercent,
    };
  }
}

class RenovationModuleResult {
  const RenovationModuleResult({
    required this.plannedTotalCosts,
    required this.forecastTotalCosts,
    required this.costVariance,
    required this.costVariancePercent,
    required this.costPerSqm,
    required this.recoverableModernizationCosts,
    required this.theoreticalModernizationRentIncreaseAnnual,
    required this.theoreticalModernizationRentIncreaseMonthly,
    required this.legalModelCapMonthly,
    required this.modeledAllowableRentIncreaseMonthly,
    required this.plannedRentIncreaseMonthly,
    required this.additionalAnnualRent,
    required this.rentLossDuringWorks,
    required this.yearOneRentEffect,
    required this.additionalNoi,
    required this.valueBefore,
    required this.valueAfter,
    required this.valueUplift,
    required this.netValueUplift,
    required this.returnOnCost,
    required this.yieldOnCost,
    required this.paybackYears,
    required this.breakEvenRentIncreaseMonthly,
    required this.renovationNpv,
    required this.renovationIrr,
    required this.delayMonths,
    required this.delayDays,
    required this.delayCosts,
    required this.riskBufferAmount,
    required this.worstCaseCosts,
    required this.riskScore,
    required this.warnings,
    required this.formulas,
  });

  final double plannedTotalCosts;
  final double forecastTotalCosts;
  final double costVariance;
  final double? costVariancePercent;
  final double? costPerSqm;
  final double recoverableModernizationCosts;
  final double theoreticalModernizationRentIncreaseAnnual;
  final double theoreticalModernizationRentIncreaseMonthly;
  final double legalModelCapMonthly;
  final double modeledAllowableRentIncreaseMonthly;
  final double plannedRentIncreaseMonthly;
  final double additionalAnnualRent;
  final double rentLossDuringWorks;
  final double yearOneRentEffect;
  final double additionalNoi;
  final double? valueBefore;
  final double? valueAfter;
  final double? valueUplift;
  final double? netValueUplift;
  final double? returnOnCost;
  final double? yieldOnCost;
  final double? paybackYears;
  final double breakEvenRentIncreaseMonthly;
  final double? renovationNpv;
  final double? renovationIrr;
  final double delayMonths;
  final int delayDays;
  final double delayCosts;
  final double riskBufferAmount;
  final double worstCaseCosts;
  final int riskScore;
  final List<String> warnings;
  final List<FormulaAuditEntry> formulas;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'planned_total_costs': plannedTotalCosts,
      'forecast_total_costs': forecastTotalCosts,
      'cost_variance': costVariance,
      'cost_variance_percent': costVariancePercent,
      'cost_per_sqm': costPerSqm,
      'recoverable_modernization_costs': recoverableModernizationCosts,
      'theoretical_modernization_rent_increase_annual':
          theoreticalModernizationRentIncreaseAnnual,
      'theoretical_modernization_rent_increase_monthly':
          theoreticalModernizationRentIncreaseMonthly,
      'legal_model_cap_monthly': legalModelCapMonthly,
      'modeled_allowable_rent_increase_monthly':
          modeledAllowableRentIncreaseMonthly,
      'planned_rent_increase_monthly': plannedRentIncreaseMonthly,
      'additional_annual_rent': additionalAnnualRent,
      'rent_loss_during_works': rentLossDuringWorks,
      'year_one_rent_effect': yearOneRentEffect,
      'additional_noi': additionalNoi,
      'value_before': valueBefore,
      'value_after': valueAfter,
      'value_uplift': valueUplift,
      'net_value_uplift': netValueUplift,
      'return_on_cost': returnOnCost,
      'yield_on_cost': yieldOnCost,
      'payback_years': paybackYears,
      'break_even_rent_increase_monthly': breakEvenRentIncreaseMonthly,
      'renovation_npv': renovationNpv,
      'renovation_irr': renovationIrr,
      'delay_months': delayMonths,
      'delay_days': delayDays,
      'delay_costs': delayCosts,
      'risk_buffer_amount': riskBufferAmount,
      'worst_case_costs': worstCaseCosts,
      'risk_score': riskScore,
      'warnings': warnings,
      'formulas': formulas.map((item) => item.toJson()).toList(),
    };
  }
}

class RenovationImpactTransfer {
  const RenovationImpactTransfer({
    required this.projectName,
    required this.forecastTotalCosts,
    required this.currentRentMonthly,
    required this.targetRentMonthly,
    required this.plannedRentIncreaseMonthly,
    required this.noiAfter,
    required this.valueAfter,
    required this.netValueUplift,
    required this.renovationNpv,
    required this.renovationIrr,
  });

  final String projectName;
  final double forecastTotalCosts;
  final double currentRentMonthly;
  final double targetRentMonthly;
  final double plannedRentIncreaseMonthly;
  final double noiAfter;
  final double? valueAfter;
  final double? netValueUplift;
  final double? renovationNpv;
  final double? renovationIrr;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'project_name': projectName,
      'forecast_total_costs': forecastTotalCosts,
      'current_rent_monthly': currentRentMonthly,
      'target_rent_monthly': targetRentMonthly,
      'planned_rent_increase_monthly': plannedRentIncreaseMonthly,
      'noi_after': noiAfter,
      'value_after': valueAfter,
      'net_value_uplift': netValueUplift,
      'renovation_npv': renovationNpv,
      'renovation_irr': renovationIrr,
    };
  }
}

class DispositionModuleInputs {
  const DispositionModuleInputs({
    required this.caseName,
    this.propertyId,
    this.saleStatus = 'idea',
    this.plannedSaleDate,
    this.loiDate,
    this.spaSignedDate,
    this.notaryDate,
    this.closingDate,
    this.handoverDate,
    required this.expectedSalePrice,
    required this.minimumSalePrice,
    required this.targetSalePrice,
    required this.brokerOpinionValue,
    required this.appraiserValue,
    required this.internalTargetValue,
    required this.marketValue,
    this.buyerGroup,
    this.saleStrategy,
    this.buyerDueDiligenceStatus = 'not_started',
    this.dataRoomStatus = 'not_started',
    this.taxAssessmentStatus = 'estimate',
    this.closingConditions,
    this.taxNotes,
    required this.currentNoi,
    required this.stabilizedNoi,
    required this.exitCapRate,
    required this.annualColdRent,
    required this.areaSqm,
    required this.brokerCosts,
    required this.legalCosts,
    required this.notaryCosts,
    required this.dueDiligenceCosts,
    required this.prepaymentPenalty,
    required this.remainingDebt,
    required this.taxes,
    required this.openCapex,
    required this.marketingCosts,
    required this.otherCosts,
    required this.originalPurchasePrice,
    required this.acquisitionCosts,
    required this.renovationCosts,
    required this.runningCashflows,
    required this.equityInvested,
    required this.holdPeriodYears,
    required this.holdValue,
    this.notes,
  });

  final String caseName;
  final String? propertyId;
  final String saleStatus;
  final String? plannedSaleDate;
  final String? loiDate;
  final String? spaSignedDate;
  final String? notaryDate;
  final String? closingDate;
  final String? handoverDate;
  final double expectedSalePrice;
  final double minimumSalePrice;
  final double targetSalePrice;
  final double brokerOpinionValue;
  final double appraiserValue;
  final double internalTargetValue;
  final double marketValue;
  final String? buyerGroup;
  final String? saleStrategy;
  final String buyerDueDiligenceStatus;
  final String dataRoomStatus;
  final String taxAssessmentStatus;
  final String? closingConditions;
  final String? taxNotes;
  final double currentNoi;
  final double stabilizedNoi;
  final double exitCapRate;
  final double annualColdRent;
  final double areaSqm;
  final double brokerCosts;
  final double legalCosts;
  final double notaryCosts;
  final double dueDiligenceCosts;
  final double prepaymentPenalty;
  final double remainingDebt;
  final double taxes;
  final double openCapex;
  final double marketingCosts;
  final double otherCosts;
  final double originalPurchasePrice;
  final double acquisitionCosts;
  final double renovationCosts;
  final double runningCashflows;
  final double equityInvested;
  final int holdPeriodYears;
  final double holdValue;
  final String? notes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'case_name': caseName,
      'property_id': propertyId,
      'sale_status': saleStatus,
      'planned_sale_date': plannedSaleDate,
      'loi_date': loiDate,
      'spa_signed_date': spaSignedDate,
      'notary_date': notaryDate,
      'closing_date': closingDate,
      'handover_date': handoverDate,
      'expected_sale_price': expectedSalePrice,
      'minimum_sale_price': minimumSalePrice,
      'target_sale_price': targetSalePrice,
      'broker_opinion_value': brokerOpinionValue,
      'appraiser_value': appraiserValue,
      'internal_target_value': internalTargetValue,
      'market_value': marketValue,
      'buyer_group': buyerGroup,
      'sale_strategy': saleStrategy,
      'buyer_due_diligence_status': buyerDueDiligenceStatus,
      'data_room_status': dataRoomStatus,
      'tax_assessment_status': taxAssessmentStatus,
      'closing_conditions': closingConditions,
      'tax_notes': taxNotes,
      'current_noi': currentNoi,
      'stabilized_noi': stabilizedNoi,
      'exit_cap_rate': exitCapRate,
      'annual_cold_rent': annualColdRent,
      'area_sqm': areaSqm,
      'broker_costs': brokerCosts,
      'legal_costs': legalCosts,
      'notary_costs': notaryCosts,
      'due_diligence_costs': dueDiligenceCosts,
      'prepayment_penalty': prepaymentPenalty,
      'remaining_debt': remainingDebt,
      'taxes': taxes,
      'open_capex': openCapex,
      'marketing_costs': marketingCosts,
      'other_costs': otherCosts,
      'original_purchase_price': originalPurchasePrice,
      'acquisition_costs': acquisitionCosts,
      'renovation_costs': renovationCosts,
      'running_cashflows': runningCashflows,
      'equity_invested': equityInvested,
      'hold_period_years': holdPeriodYears,
      'hold_value': holdValue,
      'notes': notes,
    };
  }
}

class DispositionModuleResult {
  const DispositionModuleResult({
    required this.grossSaleProceeds,
    required this.totalSaleCostsBeforeTax,
    required this.totalSaleCosts,
    required this.netSaleProceedsBeforeTax,
    required this.netSaleProceeds,
    required this.totalInvestment,
    required this.totalReturnBeforeTax,
    required this.totalReturnAfterTax,
    required this.profitBeforeTax,
    required this.profitAfterTax,
    required this.profitMargin,
    required this.gainVsTotalInvestment,
    required this.gainOnCost,
    required this.performanceVsAcquisitionCost,
    required this.performanceVsRenovationAdjustedCost,
    required this.salePricePerSqm,
    required this.salePriceFactor,
    required this.exitCapRate,
    required this.valueByTargetCapRate,
    required this.irr,
    required this.equityMultiple,
    required this.holdVsSellDifference,
    required this.minimumSalePriceForTarget,
    required this.warnings,
    required this.formulas,
  });

  final double grossSaleProceeds;
  final double totalSaleCostsBeforeTax;
  final double totalSaleCosts;
  final double netSaleProceedsBeforeTax;
  final double netSaleProceeds;
  final double totalInvestment;
  final double totalReturnBeforeTax;
  final double totalReturnAfterTax;
  final double profitBeforeTax;
  final double profitAfterTax;
  final double? profitMargin;
  final double gainVsTotalInvestment;
  final double? gainOnCost;
  final double performanceVsAcquisitionCost;
  final double performanceVsRenovationAdjustedCost;
  final double? salePricePerSqm;
  final double? salePriceFactor;
  final double? exitCapRate;
  final double? valueByTargetCapRate;
  final double? irr;
  final double? equityMultiple;
  final double holdVsSellDifference;
  final double minimumSalePriceForTarget;
  final List<String> warnings;
  final List<FormulaAuditEntry> formulas;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'gross_sale_proceeds': grossSaleProceeds,
      'total_sale_costs_before_tax': totalSaleCostsBeforeTax,
      'total_sale_costs': totalSaleCosts,
      'net_sale_proceeds_before_tax': netSaleProceedsBeforeTax,
      'net_sale_proceeds': netSaleProceeds,
      'total_investment': totalInvestment,
      'total_return_before_tax': totalReturnBeforeTax,
      'total_return_after_tax': totalReturnAfterTax,
      'profit_before_tax': profitBeforeTax,
      'profit_after_tax': profitAfterTax,
      'profit_margin': profitMargin,
      'gain_vs_total_investment': gainVsTotalInvestment,
      'gain_on_cost': gainOnCost,
      'performance_vs_acquisition_cost': performanceVsAcquisitionCost,
      'performance_vs_renovation_adjusted_cost':
          performanceVsRenovationAdjustedCost,
      'sale_price_per_sqm': salePricePerSqm,
      'sale_price_factor': salePriceFactor,
      'exit_cap_rate': exitCapRate,
      'value_by_target_cap_rate': valueByTargetCapRate,
      'irr': irr,
      'equity_multiple': equityMultiple,
      'hold_vs_sell_difference': holdVsSellDifference,
      'minimum_sale_price_for_target': minimumSalePriceForTarget,
      'warnings': warnings,
      'formulas': formulas.map((item) => item.toJson()).toList(),
    };
  }
}

class DispositionOfferInput {
  const DispositionOfferInput({
    required this.buyerName,
    required this.offerPrice,
    required this.financingConfirmed,
    required this.closingProbability,
    required this.riskScore,
    this.dueDiligenceDeadline,
    this.exclusivityUntil,
    this.paymentTarget,
    this.offerVersion,
    this.conditions,
    this.notes,
  });

  final String buyerName;
  final double offerPrice;
  final bool financingConfirmed;
  final double closingProbability;
  final int riskScore;
  final String? dueDiligenceDeadline;
  final String? exclusivityUntil;
  final String? paymentTarget;
  final String? offerVersion;
  final String? conditions;
  final String? notes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'buyer_name': buyerName,
      'offer_price': offerPrice,
      'financing_confirmed': financingConfirmed,
      'closing_probability': closingProbability,
      'risk_score': riskScore,
      'due_diligence_deadline': dueDiligenceDeadline,
      'exclusivity_until': exclusivityUntil,
      'payment_target': paymentTarget,
      'offer_version': offerVersion,
      'conditions': conditions,
      'notes': notes,
    };
  }
}

class DispositionOfferRanking {
  const DispositionOfferRanking({
    required this.offer,
    required this.deviationToTarget,
    required this.riskAdjustedValue,
    required this.rank,
    required this.warning,
  });

  final DispositionOfferInput offer;
  final double deviationToTarget;
  final double riskAdjustedValue;
  final int rank;
  final String? warning;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'offer': offer.toJson(),
      'deviation_to_target': deviationToTarget,
      'risk_adjusted_value': riskAdjustedValue,
      'rank': rank,
      'warning': warning,
    };
  }
}
