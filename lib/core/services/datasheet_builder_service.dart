import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/investment_modules.dart';

class DatasheetBuilderService {
  const DatasheetBuilderService();

  ModuleDatasheet buildAcquisitionQuickDatasheet({
    required AcquisitionQuickInputs inputs,
    required AcquisitionQuickResult result,
    String? propertyId,
    String? scenarioId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ModuleDatasheet(
      id: const Uuid().v4(),
      module: 'acquisition_quick',
      title: 'Ankauf Schnellbewertung - ${inputs.objectName}',
      propertyId: propertyId,
      scenarioId: scenarioId,
      createdAt: now,
      header: <String, Object?>{
        'object': inputs.objectName,
        'date': now,
        'scenario': scenarioId,
        'module': 'Ankauf Schnellbewertung',
      },
      executiveSummary: <String, Object?>{
        'recommendation': result.recommendation,
        'score': result.score,
        'max_reasonable_purchase_price': result.maxReasonablePurchasePrice,
        'cashflow_before_tax': result.cashflowBeforeTax,
      },
      inputData: inputs.toJson(),
      assumptions: <String, Object?>{
        'target_cap_rate': inputs.targetCapRate,
        'desired_margin': inputs.desiredMargin,
        'target_criteria': result.criteria.map((item) => item.toJson()).toList(),
      },
      calculations: result.formulas.map((item) => item.toJson()).toList(),
      metrics: result.toJson(),
      sensitivities: _quickSensitivities(inputs, result),
      risks: result.warnings,
      recommendation: result.recommendation,
      formulaAppendix: result.formulas.map((item) => item.toJson()).toList(),
      dataQuality: _dataQuality(result.warnings),
    );
  }

  ModuleDatasheet buildRenovationDatasheet({
    required RenovationModuleInputs inputs,
    required RenovationModuleResult result,
    List<RenovationMeasureInput> measures = const <RenovationMeasureInput>[],
    String? scenarioId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ModuleDatasheet(
      id: const Uuid().v4(),
      module: 'renovation_value_add',
      title: 'Renovierung und Wertsteigerung - ${inputs.projectName}',
      propertyId: inputs.propertyId,
      scenarioId: scenarioId,
      createdAt: now,
      header: <String, Object?>{
        'object': inputs.propertyId,
        'date': now,
        'scenario': scenarioId,
        'module': 'Renovierung und Wertsteigerung',
      },
      executiveSummary: <String, Object?>{
        'project_status': inputs.projectStatus,
        'priority': inputs.priority,
        'forecast_total_costs': result.forecastTotalCosts,
        'recoverable_modernization_costs': result.recoverableModernizationCosts,
        'modeled_allowable_rent_increase_monthly':
            result.modeledAllowableRentIncreaseMonthly,
        'value_uplift': result.valueUplift,
        'net_value_uplift': result.netValueUplift,
        'renovation_npv': result.renovationNpv,
        'renovation_irr': result.renovationIrr,
        'worst_case_costs': result.worstCaseCosts,
        'risk_score': result.riskScore,
        'payback_years': result.paybackYears,
      },
      inputData: <String, Object?>{
        ...inputs.toJson(),
        'measures': measures.map((item) => item.toJson()).toList(),
        'rent_impact': <String, Object?>{
          'current_rent_monthly': inputs.currentRentMonthly,
          'target_rent_monthly': inputs.targetRentMonthly,
          'planned_rent_increase_monthly': result.plannedRentIncreaseMonthly,
          'additional_annual_rent': result.additionalAnnualRent,
          'rent_loss_during_works': result.rentLossDuringWorks,
          'year_one_rent_effect': result.yearOneRentEffect,
        },
        'value_impact': <String, Object?>{
          'noi_before': inputs.noiBefore,
          'noi_after': inputs.noiAfter,
          'additional_noi': result.additionalNoi,
          'cap_rate_before': inputs.capRateBefore,
          'cap_rate_after': inputs.capRateAfter,
          'value_before': result.valueBefore,
          'value_after': result.valueAfter,
          'value_uplift': result.valueUplift,
          'net_value_uplift': result.netValueUplift,
        },
        'time_and_risk': <String, Object?>{
          'planned_construction_months': inputs.plannedConstructionMonths,
          'actual_construction_months': inputs.actualConstructionMonths,
          'delay_months': result.delayMonths,
          'delay_days': result.delayDays,
          'delay_cost_per_month': inputs.delayCostPerMonth,
          'delay_costs': result.delayCosts,
          'permit_required': inputs.permitRequired,
          'permit_status': inputs.permitStatus,
          'permit_submitted_date': inputs.permitSubmittedDate,
          'permit_approval_date': inputs.permitApprovalDate,
          'permit_risk': inputs.permitRisk,
          'cost_risk': inputs.costRisk,
          'rent_loss_risk': inputs.rentLossRisk,
          'technical_risk': inputs.technicalRisk,
          'contractor_availability_risk': inputs.contractorAvailabilityRisk,
          'risk_buffer_percent': inputs.riskBufferPercent,
          'risk_buffer_amount': result.riskBufferAmount,
          'worst_case_costs': result.worstCaseCosts,
          'risk_score': result.riskScore,
        },
      },
      assumptions: <String, Object?>{
        'project_type': inputs.projectType,
        'project_status': inputs.projectStatus,
        'start_date': inputs.startDate,
        'planned_end_date': inputs.plannedEndDate,
        'actual_end_date': inputs.actualEndDate,
        'responsible': inputs.responsible,
        'priority': inputs.priority,
        'description': inputs.description,
        'permit_required': inputs.permitRequired,
        'permit_status': inputs.permitStatus,
        'permit_submitted_date': inputs.permitSubmittedDate,
        'permit_approval_date': inputs.permitApprovalDate,
        'modernization_legal_basis': inputs.modernizationLegalBasis,
        'budget': inputs.budget,
        'reserve_percent': inputs.reservePercent,
        'target_yield': inputs.targetYield,
        'renovation_horizon_years': inputs.renovationHorizonYears,
        'discount_rate': inputs.discountRate,
        'planned_construction_months': inputs.plannedConstructionMonths,
        'actual_construction_months': inputs.actualConstructionMonths,
        'delay_cost_per_month': inputs.delayCostPerMonth,
        'risk_buffer_percent': inputs.riskBufferPercent,
        'maintenance_share': inputs.maintenanceShare,
        'subsidies': inputs.subsidies,
        'subsidy_program': inputs.subsidyProgram,
        'insurance_recoveries': inputs.insuranceRecoveries,
        'non_recoverable_cost_share': inputs.nonRecoverableCostShare,
        'modernization_cap_per_sqm': inputs.modernizationCapPerSqm,
        'modernization_rent_model_note':
            inputs.modernizationLegalBasis == null
                ? 'Wirtschaftliche Modellrechnung, keine rechtliche Pruefung.'
                : 'Rechtsbasis/Notiz: ${inputs.modernizationLegalBasis}',
        'measure_count': measures.length,
      },
      calculations: result.formulas.map((item) => item.toJson()).toList(),
      metrics: result.toJson(),
      sensitivities: <String, Object?>{
        'cost_plus_10_percent': result.forecastTotalCosts * 1.10,
        'cost_plus_20_percent': result.forecastTotalCosts * 1.20,
        'rent_minus_10_percent': result.additionalAnnualRent * 0.90,
        'construction_delay_plus_3_months':
            inputs.currentRentMonthly * (inputs.vacancyMonthsDuringWorks + 3),
        'cap_rate_after_plus_50_bps': inputs.capRateAfter + 0.005,
      },
      risks: result.warnings,
      recommendation: _recommendationFromWarnings(result.warnings),
      formulaAppendix: result.formulas.map((item) => item.toJson()).toList(),
      dataQuality: _dataQuality(result.warnings),
    );
  }

  ModuleDatasheet buildDispositionDatasheet({
    required DispositionModuleInputs inputs,
    required DispositionModuleResult result,
    List<DispositionOfferRanking> offers = const <DispositionOfferRanking>[],
    String? scenarioId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ModuleDatasheet(
      id: const Uuid().v4(),
      module: 'disposition_exit',
      title: 'Verkauf und Exit-Analyse - ${inputs.caseName}',
      propertyId: inputs.propertyId,
      scenarioId: scenarioId,
      createdAt: now,
      header: <String, Object?>{
        'object': inputs.propertyId,
        'date': now,
        'scenario': scenarioId,
        'module': 'Verkauf und Exit-Analyse',
      },
      executiveSummary: <String, Object?>{
        'sale_status': inputs.saleStatus,
        'planned_sale_date': inputs.plannedSaleDate,
        'loi_date': inputs.loiDate,
        'spa_signed_date': inputs.spaSignedDate,
        'notary_date': inputs.notaryDate,
        'closing_date': inputs.closingDate,
        'handover_date': inputs.handoverDate,
        'buyer_due_diligence_status': inputs.buyerDueDiligenceStatus,
        'data_room_status': inputs.dataRoomStatus,
        'tax_assessment_status': inputs.taxAssessmentStatus,
        'net_sale_proceeds_before_tax': result.netSaleProceedsBeforeTax,
        'net_sale_proceeds': result.netSaleProceeds,
        'total_return_before_tax': result.totalReturnBeforeTax,
        'total_return_after_tax': result.totalReturnAfterTax,
        'profit_before_tax': result.profitBeforeTax,
        'profit_after_tax': result.profitAfterTax,
        'gain_vs_total_investment': result.gainVsTotalInvestment,
        'gain_on_cost': result.gainOnCost,
        'irr': result.irr,
        'equity_multiple': result.equityMultiple,
        'hold_vs_sell_difference': result.holdVsSellDifference,
        'best_offer': offers.isEmpty ? null : offers.first.toJson(),
      },
      inputData: <String, Object?>{
        ...inputs.toJson(),
        'ranked_offers': offers.map((item) => item.toJson()).toList(),
        'performance': <String, Object?>{
          'original_purchase_price': inputs.originalPurchasePrice,
          'acquisition_costs': inputs.acquisitionCosts,
          'renovation_costs': inputs.renovationCosts,
          'total_investment': result.totalInvestment,
          'running_cashflows': inputs.runningCashflows,
          'total_sale_costs_before_tax': result.totalSaleCostsBeforeTax,
          'taxes': inputs.taxes,
          'net_sale_proceeds_before_tax': result.netSaleProceedsBeforeTax,
          'net_sale_proceeds': result.netSaleProceeds,
          'total_return_before_tax': result.totalReturnBeforeTax,
          'total_return_after_tax': result.totalReturnAfterTax,
          'profit_before_tax': result.profitBeforeTax,
          'profit_after_tax': result.profitAfterTax,
          'gain_vs_total_investment': result.gainVsTotalInvestment,
          'gain_on_cost': result.gainOnCost,
          'performance_vs_acquisition_cost':
              result.performanceVsAcquisitionCost,
          'performance_vs_renovation_adjusted_cost':
              result.performanceVsRenovationAdjustedCost,
        },
      },
      assumptions: <String, Object?>{
        'buyer_group': inputs.buyerGroup,
        'sale_strategy': inputs.saleStrategy,
        'broker_opinion_value': inputs.brokerOpinionValue,
        'appraiser_value': inputs.appraiserValue,
        'internal_target_value': inputs.internalTargetValue,
        'market_value': inputs.marketValue,
        'exit_cap_rate': inputs.exitCapRate,
        'hold_period_years': inputs.holdPeriodYears,
        'hold_value': inputs.holdValue,
        'target_sale_price': inputs.targetSalePrice,
        'offer_count': offers.length,
        'transaction_process': <String, Object?>{
          'loi_date': inputs.loiDate,
          'spa_signed_date': inputs.spaSignedDate,
          'notary_date': inputs.notaryDate,
          'closing_date': inputs.closingDate,
          'handover_date': inputs.handoverDate,
          'buyer_due_diligence_status': inputs.buyerDueDiligenceStatus,
          'data_room_status': inputs.dataRoomStatus,
          'closing_conditions': inputs.closingConditions,
        },
        'tax': <String, Object?>{
          'taxes': inputs.taxes,
          'tax_assessment_status': inputs.taxAssessmentStatus,
          'tax_notes': inputs.taxNotes,
        },
      },
      calculations: result.formulas.map((item) => item.toJson()).toList(),
      metrics: result.toJson(),
      sensitivities: <String, Object?>{
        'sale_price_minus_10_percent': inputs.expectedSalePrice * 0.90,
        'sale_price_plus_10_percent': inputs.expectedSalePrice * 1.10,
        'exit_cap_rate_plus_50_bps': inputs.exitCapRate + 0.005,
        'remaining_debt_plus_10_percent': inputs.remainingDebt * 1.10,
        'sale_costs_plus_10_percent': result.totalSaleCosts * 1.10,
      },
      risks: result.warnings,
      recommendation: result.holdVsSellDifference >= 0 ? 'Verkauf pruefen' : 'Halten pruefen',
      formulaAppendix: result.formulas.map((item) => item.toJson()).toList(),
      dataQuality: _dataQuality(result.warnings),
    );
  }

  String toPrettyJson(ModuleDatasheet datasheet) {
    return const JsonEncoder.withIndent('  ').convert(datasheet.toJson());
  }

  Map<String, Object?> _quickSensitivities(
    AcquisitionQuickInputs inputs,
    AcquisitionQuickResult result,
  ) {
    return <String, Object?>{
      'purchase_price_minus_10_percent': inputs.offerPrice * 0.90,
      'purchase_price_plus_10_percent': inputs.offerPrice * 1.10,
      'rent_minus_10_percent': inputs.currentColdRentMonthly * 0.90,
      'rent_plus_10_percent': inputs.currentColdRentMonthly * 1.10,
      'renovation_plus_10_percent': inputs.renovationBudget * 1.10,
      'renovation_plus_20_percent': inputs.renovationBudget * 1.20,
      'base_max_reasonable_purchase_price': result.maxReasonablePurchasePrice,
    };
  }

  Map<String, Object?> _dataQuality(List<String> warnings) {
    final score = (100 - warnings.length * 10).clamp(0, 100).toInt();
    return <String, Object?>{
      'score': score,
      'status': score >= 80
          ? 'good'
          : score >= 50
              ? 'review'
              : 'critical',
      'warnings': warnings,
    };
  }

  String _recommendationFromWarnings(List<String> warnings) {
    if (warnings.isEmpty) {
      return 'Pruefen';
    }
    if (warnings.length <= 2) {
      return 'Mit offenen Punkten pruefen';
    }
    return 'Erst Datenqualitaet verbessern';
  }
}
