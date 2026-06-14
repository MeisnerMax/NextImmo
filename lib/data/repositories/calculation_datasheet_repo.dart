import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/investment_modules.dart';

class CalculationDatasheetRepo {
  CalculationDatasheetRepo(this._db);

  final Database _db;

  Future<void> saveAcquisitionQuickEvaluation({
    required String id,
    required String title,
    required AcquisitionQuickInputs inputs,
    required AcquisitionQuickResult result,
    String? propertyId,
    String? scenarioId,
    String scenarioType = 'base',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert(
      'acquisition_quick_evaluations',
      <String, Object?>{
        'id': id,
        'title': title,
        'property_id': propertyId,
        'scenario_id': scenarioId,
        'scenario_type': scenarioType,
        'status': 'saved',
        'input_json': jsonEncode(inputs.toJson()),
        'result_json': jsonEncode(result.toJson()),
        'recommendation': result.recommendation,
        'score': result.score,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> saveRenovationScenario({
    required RenovationModuleInputs inputs,
    required RenovationModuleResult result,
    List<RenovationMeasureInput> measures = const <RenovationMeasureInput>[],
    String scenarioType = 'base',
    String? renovationProjectId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = const Uuid().v4();
    var effectiveProjectId = renovationProjectId;
    await _db.transaction((txn) async {
      if (effectiveProjectId == null && inputs.propertyId != null) {
        effectiveProjectId = const Uuid().v4();
        final projectColumns = await txn.rawQuery(
          'PRAGMA table_info(renovation_projects)',
        );
        final projectColumnNames = projectColumns
            .map((row) => row['name'] as String?)
            .whereType<String>()
            .toSet();
        if (projectColumnNames.isEmpty) {
          effectiveProjectId = null;
        } else {
          final projectRow = <String, Object?>{
            'id': effectiveProjectId,
            'property_id': inputs.propertyId,
            'project_code': inputs.projectName,
            'category': inputs.projectType,
            'measure': inputs.description,
            'status': inputs.projectStatus,
            'start_date': _dateMillis(inputs.startDate),
            'planned_end_date': _dateMillis(inputs.plannedEndDate),
            'actual_end_date': _dateMillis(inputs.actualEndDate),
            'budget_amount': inputs.budget,
            'actual_amount': inputs.actualCosts,
            'owner': inputs.responsible,
            'next_step': inputs.priority,
            'created_at': now,
            'updated_at': now,
          }..removeWhere((key, _) => !projectColumnNames.contains(key));
          await txn.insert(
            'renovation_projects',
            projectRow,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      await txn.insert(
        'renovation_scenarios',
        <String, Object?>{
          'id': id,
          'renovation_project_id': effectiveProjectId,
          'scenario_name': inputs.projectName,
          'scenario_type': scenarioType,
          'input_json': jsonEncode(inputs.toJson()),
          'result_json': jsonEncode(result.toJson()),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final savedMeasures = <MapEntry<RenovationMeasureInput, String>>[];
      for (final measure in measures) {
        final measureId = const Uuid().v4();
        await txn.insert(
          'renovation_measures',
          <String, Object?>{
            'id': measureId,
            'renovation_project_id': effectiveProjectId,
            'renovation_scenario_id': id,
            'measure_type': measure.measureType,
            'category': measure.category,
            'trade': measure.trade,
            'affected_area_sqm': measure.affectedAreaSqm,
            'is_required': measure.isRequired ? 1 : 0,
            'is_value_add': measure.isValueAdd ? 1 : 0,
            'is_recoverable': measure.isRecoverable ? 1 : 0,
            'payload_json': jsonEncode(measure.toJson()),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        savedMeasures.add(MapEntry<RenovationMeasureInput, String>(
          measure,
          measureId,
        ));
      }

      final costColumns = await txn.rawQuery(
        'PRAGMA table_info(renovation_cost_items)',
      );
      final costColumnNames = costColumns
          .map((row) => row['name'] as String?)
          .whereType<String>()
          .toSet();
      final projectColumn = costColumns.cast<Map<String, Object?>>().firstWhere(
            (row) => row['name'] == 'renovation_project_id',
            orElse: () => <String, Object?>{},
          );
      final projectIdRequired =
          ((projectColumn['notnull'] as num?) ?? 0).toInt() == 1;
      if (effectiveProjectId != null || !projectIdRequired) {
        final costRow = <String, Object?>{
          'id': const Uuid().v4(),
          'renovation_project_id': effectiveProjectId,
          'measure_id': null,
          'label': 'Aggregierter Kostenplan',
          'budget_amount': inputs.budget,
          'committed_amount': null,
          'actual_amount': inputs.actualCosts,
          'remaining_amount': inputs.expectedRemainingCosts,
          'payload_json': jsonEncode(<String, Object?>{
            'budget': inputs.budget,
            'actual_costs': inputs.actualCosts,
            'expected_remaining_costs': inputs.expectedRemainingCosts,
            'reserve_percent': inputs.reservePercent,
            'maintenance_share': inputs.maintenanceShare,
            'subsidies': inputs.subsidies,
            'subsidy_program': inputs.subsidyProgram,
            'insurance_recoveries': inputs.insuranceRecoveries,
            'non_recoverable_cost_share': inputs.nonRecoverableCostShare,
            'permit_required': inputs.permitRequired,
            'permit_status': inputs.permitStatus,
            'permit_submitted_date': inputs.permitSubmittedDate,
            'permit_approval_date': inputs.permitApprovalDate,
            'forecast_total_costs': result.forecastTotalCosts,
            'cost_variance': result.costVariance,
            'cost_variance_percent': result.costVariancePercent,
            'cost_per_sqm': result.costPerSqm,
            'delay_costs': result.delayCosts,
            'risk_buffer_amount': result.riskBufferAmount,
            'worst_case_costs': result.worstCaseCosts,
            'risk_score': result.riskScore,
          }),
          'created_at': now,
          'updated_at': now,
        };
        if (costColumnNames.contains('renovation_scenario_id')) {
          costRow['renovation_scenario_id'] = id;
        }
        await txn.insert(
          'renovation_cost_items',
          costRow,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        for (final entry in savedMeasures.where((entry) =>
            entry.key.budgetAmount != 0 ||
            entry.key.committedAmount != 0 ||
            entry.key.actualAmount != 0 ||
            entry.key.remainingAmount != 0)) {
          final measure = entry.key;
          final measureCostRow = <String, Object?>{
            'id': const Uuid().v4(),
            'renovation_project_id': effectiveProjectId,
            'measure_id': entry.value,
            'label': measure.measureType,
            'budget_amount': measure.budgetAmount,
            'committed_amount': measure.committedAmount,
            'actual_amount': measure.actualAmount,
            'remaining_amount': measure.remainingAmount,
            'payload_json': jsonEncode(<String, Object?>{
              ...measure.toJson(),
              'renovation_scenario_id': id,
            }),
            'created_at': now,
            'updated_at': now,
          };
          if (costColumnNames.contains('renovation_scenario_id')) {
            measureCostRow['renovation_scenario_id'] = id;
          }
          await txn.insert(
            'renovation_cost_items',
            measureCostRow,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      if (effectiveProjectId != null) {
        final rentImpactColumns = await txn.rawQuery(
          'PRAGMA table_info(renovation_rent_impacts)',
        );
        final valueImpactColumns = await txn.rawQuery(
          'PRAGMA table_info(renovation_value_impacts)',
        );
        final hasRentImpactTable = rentImpactColumns.isNotEmpty;
        final hasValueImpactTable = valueImpactColumns.isNotEmpty;
        if (hasRentImpactTable) {
          await txn.insert(
            'renovation_rent_impacts',
            <String, Object?>{
              'id': const Uuid().v4(),
              'renovation_project_id': effectiveProjectId,
              'unit_id': inputs.unitId,
              'current_rent_monthly': inputs.currentRentMonthly,
              'target_rent_monthly': inputs.targetRentMonthly,
              'vacancy_months': inputs.vacancyMonthsDuringWorks,
              'payload_json': jsonEncode(<String, Object?>{
                'renovation_scenario_id': id,
                'current_rent_monthly': inputs.currentRentMonthly,
                'target_rent_monthly': inputs.targetRentMonthly,
                'planned_rent_increase_monthly':
                    result.plannedRentIncreaseMonthly,
                'additional_annual_rent': result.additionalAnnualRent,
                'rent_loss_during_works': result.rentLossDuringWorks,
                'year_one_rent_effect': result.yearOneRentEffect,
                'modeled_allowable_rent_increase_monthly':
                    result.modeledAllowableRentIncreaseMonthly,
                'modernization_legal_basis': inputs.modernizationLegalBasis,
                'modernization_model_note':
                    inputs.modernizationLegalBasis == null
                        ? 'Wirtschaftliche Modellrechnung, keine rechtliche Pruefung.'
                        : 'Rechtsbasis/Notiz: ${inputs.modernizationLegalBasis}',
              }),
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        if (hasValueImpactTable) {
          await txn.insert(
            'renovation_value_impacts',
            <String, Object?>{
              'id': const Uuid().v4(),
              'renovation_project_id': effectiveProjectId,
              'noi_before': inputs.noiBefore,
              'noi_after': inputs.noiAfter,
              'cap_rate_before': inputs.capRateBefore,
              'cap_rate_after': inputs.capRateAfter,
              'result_json': jsonEncode(<String, Object?>{
                'renovation_scenario_id': id,
                'additional_noi': result.additionalNoi,
                'value_before': result.valueBefore,
                'value_after': result.valueAfter,
                'value_uplift': result.valueUplift,
                'net_value_uplift': result.netValueUplift,
                'return_on_cost': result.returnOnCost,
                'yield_on_cost': result.yieldOnCost,
                'payback_years': result.paybackYears,
                'renovation_npv': result.renovationNpv,
                'renovation_irr': result.renovationIrr,
                'delay_months': result.delayMonths,
                'delay_days': result.delayDays,
                'delay_costs': result.delayCosts,
                'risk_buffer_amount': result.riskBufferAmount,
                'worst_case_costs': result.worstCaseCosts,
                'risk_score': result.riskScore,
              }),
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }
    });
    return id;
  }

  Future<String> saveAcquisitionDeepEvaluation({
    required String propertyId,
    required String scenarioId,
    required String title,
    required Map<String, Object?> inputData,
    required Map<String, Object?> resultData,
    required List<String> risks,
    required String recommendation,
    String scenarioType = 'base',
    List<Map<String, Object?>> valuationMethods = const <Map<String, Object?>>[],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final evaluationId = const Uuid().v4();
    final acquisitionScenarioId = const Uuid().v4();
    final riskScore = (100 - risks.length * 10).clamp(0, 100).toInt();
    await _db.transaction((txn) async {
      await txn.insert(
        'acquisition_deep_evaluations',
        <String, Object?>{
          'id': evaluationId,
          'property_id': propertyId,
          'scenario_id': scenarioId,
          'title': title,
          'status': 'saved',
          'input_json': jsonEncode(inputData),
          'result_json': jsonEncode(resultData),
          'risk_score': riskScore,
          'recommendation': recommendation,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await txn.insert(
        'acquisition_scenarios',
        <String, Object?>{
          'id': acquisitionScenarioId,
          'evaluation_id': evaluationId,
          'scenario_name': title,
          'scenario_type': scenarioType,
          'input_json': jsonEncode(inputData),
          'result_json': jsonEncode(resultData),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      for (final method in valuationMethods) {
        await txn.insert(
          'acquisition_valuation_methods',
          <String, Object?>{
            'id': const Uuid().v4(),
            'evaluation_id': evaluationId,
            'method_name': method['method_name'] as String? ?? 'Bewertungsmethode',
            'value_low': (method['value_low'] as num?)?.toDouble(),
            'value_mid': (method['value_mid'] as num?)?.toDouble(),
            'value_high': (method['value_high'] as num?)?.toDouble(),
            'confidence': method['confidence'] as String? ?? 'low',
            'payload_json': jsonEncode(method),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      final purchasePrice =
          ((inputData['purchase_price'] as num?) ?? 0).toDouble();
      final rehabBudget =
          ((inputData['rehab_budget'] as num?) ?? 0).toDouble();
      final closingCostPercent =
          ((inputData['closing_cost_buy_percent'] as num?) ?? 0).toDouble();
      final closingCostFixed =
          ((inputData['closing_cost_buy_fixed'] as num?) ?? 0).toDouble();
      final loanAmount = ((inputData['loan_amount'] as num?) ?? 0).toDouble();
      final totalInvestment =
          purchasePrice + rehabBudget + closingCostFixed + purchasePrice * closingCostPercent;
      final equity = (totalInvestment - loanAmount).clamp(0, double.infinity).toDouble();
      await txn.insert(
        'acquisition_financing_assumptions',
        <String, Object?>{
          'id': const Uuid().v4(),
          'evaluation_id': evaluationId,
          'scenario_id': acquisitionScenarioId,
          'loan_amount': loanAmount,
          'equity': equity,
          'interest_rate_percent':
              ((inputData['interest_rate_percent'] as num?) ?? 0).toDouble(),
          'amortization_percent': null,
          'payload_json': jsonEncode(<String, Object?>{
            'financing_mode': inputData['financing_mode'],
            'loan_amount': loanAmount,
            'equity': equity,
            'interest_rate_percent': inputData['interest_rate_percent'],
            'down_payment_percent': inputData['down_payment_percent'],
            'term_years': inputData['term_years'],
            'amortization_type': inputData['amortization_type'],
            'total_investment': totalInvestment,
          }),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final rentMonthly =
          ((inputData['rent_monthly_total'] as num?) ?? 0).toDouble();
      final areaSqm = ((inputData['lettable_area_sqm'] as num?) ??
              (inputData['gross_area_sqm'] as num?) ??
              0)
          .toDouble();
      await txn.insert(
        'acquisition_rent_roll_entries',
        <String, Object?>{
          'id': const Uuid().v4(),
          'evaluation_id': evaluationId,
          'unit_label': 'Gesamtobjekt',
          'tenant_name': null,
          'usage_type': 'aggregate',
          'area_sqm': areaSqm,
          'current_rent_monthly': rentMonthly,
          'market_rent_monthly': inputData['rent_override'],
          'is_vacant':
              (((inputData['vacancy_percent'] as num?) ?? 0).toDouble() > 0)
                  ? 1
                  : 0,
          'payload_json': jsonEncode(<String, Object?>{
            'rent_monthly_total': rentMonthly,
            'other_income_monthly': inputData['other_income_monthly'],
            'vacancy_percent': inputData['vacancy_percent'],
            'gross_area_sqm': inputData['gross_area_sqm'],
            'lettable_area_sqm': inputData['lettable_area_sqm'],
            'residential_area_sqm': inputData['residential_area_sqm'],
            'commercial_area_sqm': inputData['commercial_area_sqm'],
            'rent_override': inputData['rent_override'],
          }),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final incomeLines = inputData['income_lines'];
      if (incomeLines is List) {
        for (final line in incomeLines.whereType<Map>()) {
          await txn.insert(
            'acquisition_rent_roll_entries',
            <String, Object?>{
              'id': const Uuid().v4(),
              'evaluation_id': evaluationId,
              'unit_label': line['name'] as String?,
              'tenant_name': null,
              'usage_type': 'income_line',
              'area_sqm': null,
              'current_rent_monthly':
                  ((line['amount_monthly'] as num?) ?? 0).toDouble(),
              'market_rent_monthly': null,
              'is_vacant': 0,
              'payload_json': jsonEncode(Map<String, Object?>.from(line)),
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      final marketSales = inputData['market_sales'];
      if (marketSales is List) {
        for (final comp in marketSales.whereType<Map>()) {
          if (((comp['selected'] as num?) ?? 1).toInt() != 1) {
            continue;
          }
          await txn.insert(
            'acquisition_market_comps',
            <String, Object?>{
              'id': const Uuid().v4(),
              'evaluation_id': evaluationId,
              'comp_type': 'sale',
              'address': comp['address'] as String?,
              'price': ((comp['price'] as num?) ?? 0).toDouble(),
              'rent_monthly': null,
              'area_sqm': (comp['sqft'] as num?)?.toDouble(),
              'adjustment_json': jsonEncode(<String, Object?>{
                ...Map<String, Object?>.from(comp),
                'weight': ((comp['weight'] as num?) ?? 1).toDouble(),
              }),
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      final marketRentals = inputData['market_rentals'];
      if (marketRentals is List) {
        for (final comp in marketRentals.whereType<Map>()) {
          if (((comp['selected'] as num?) ?? 1).toInt() != 1) {
            continue;
          }
          await txn.insert(
            'acquisition_market_comps',
            <String, Object?>{
              'id': const Uuid().v4(),
              'evaluation_id': evaluationId,
              'comp_type': 'rental',
              'address': comp['address'] as String?,
              'price': null,
              'rent_monthly':
                  ((comp['rent_monthly'] as num?) ?? 0).toDouble(),
              'area_sqm': (comp['sqft'] as num?)?.toDouble(),
              'adjustment_json': jsonEncode(<String, Object?>{
                ...Map<String, Object?>.from(comp),
                'weight': ((comp['weight'] as num?) ?? 1).toDouble(),
              }),
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      for (final risk in risks) {
        await txn.insert(
          'acquisition_risk_items',
          <String, Object?>{
            'id': const Uuid().v4(),
            'evaluation_id': evaluationId,
            'risk_category': 'criteria',
            'title': risk,
            'severity': 3,
            'mitigation': 'Due-Diligence-Punkt pruefen und dokumentieren.',
            'payload_json': jsonEncode(<String, Object?>{
              'source': 'criteria_failure',
              'field_key': risk,
              'recommendation': recommendation,
            }),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
    return evaluationId;
  }

  Future<String> saveDispositionScenario({
    required DispositionModuleInputs inputs,
    required DispositionModuleResult result,
    List<DispositionOfferRanking> offers = const <DispositionOfferRanking>[],
    String scenarioType = 'base',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final caseId = const Uuid().v4();
    final scenarioId = const Uuid().v4();
    await _db.transaction((txn) async {
      await txn.insert(
        'disposition_cases',
        <String, Object?>{
          'id': caseId,
          'property_id': inputs.propertyId,
          'title': inputs.caseName,
          'status': inputs.saleStatus,
          'input_json': jsonEncode(inputs.toJson()),
          'result_json': jsonEncode(result.toJson()),
          'recommendation':
              result.holdVsSellDifference >= 0 ? 'sell_review' : 'hold_review',
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await txn.insert(
        'disposition_scenarios',
        <String, Object?>{
          'id': scenarioId,
          'disposition_case_id': caseId,
          'scenario_name': inputs.caseName,
          'scenario_type': scenarioType,
          'input_json': jsonEncode(inputs.toJson()),
          'result_json': jsonEncode(result.toJson()),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      for (final rankedOffer in offers) {
        final offer = rankedOffer.offer;
        await txn.insert(
          'disposition_offers',
          <String, Object?>{
            'id': const Uuid().v4(),
            'disposition_case_id': caseId,
            'buyer_name': offer.buyerName,
            'offer_price': offer.offerPrice,
            'closing_probability': offer.closingProbability,
            'risk_level': 'rank_${rankedOffer.rank}',
            'due_diligence_deadline': offer.dueDiligenceDeadline,
            'exclusivity_until': offer.exclusivityUntil,
            'payment_target': offer.paymentTarget,
            'offer_version': offer.offerVersion,
            'payload_json': jsonEncode(<String, Object?>{
              ...rankedOffer.toJson(),
              'due_diligence_deadline': offer.dueDiligenceDeadline,
              'exclusivity_until': offer.exclusivityUntil,
              'payment_target': offer.paymentTarget,
              'offer_version': offer.offerVersion,
            }),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      final costItems = <MapEntry<String, double>>[
        MapEntry<String, double>('Maklerkosten', inputs.brokerCosts),
        MapEntry<String, double>('Rechtsberatung', inputs.legalCosts),
        MapEntry<String, double>('Notar', inputs.notaryCosts),
        MapEntry<String, double>('Due Diligence', inputs.dueDiligenceCosts),
        MapEntry<String, double>('Vorfaelligkeit', inputs.prepaymentPenalty),
        MapEntry<String, double>('Restschuld', inputs.remainingDebt),
        MapEntry<String, double>('Steuern', inputs.taxes),
        MapEntry<String, double>('Offene CapEx', inputs.openCapex),
        MapEntry<String, double>('Vermarktung', inputs.marketingCosts),
        MapEntry<String, double>('Sonstige Kosten', inputs.otherCosts),
      ];
      for (final item in costItems.where((item) => item.value != 0)) {
        await txn.insert(
          'disposition_cost_items',
          <String, Object?>{
            'id': const Uuid().v4(),
            'disposition_case_id': caseId,
            'label': item.key,
            'amount': item.value,
            'payload_json': jsonEncode(<String, Object?>{
              'label': item.key,
              'amount': item.value,
              'total_sale_costs_before_tax': result.totalSaleCostsBeforeTax,
              'total_sale_costs': result.totalSaleCosts,
              'net_sale_proceeds_before_tax': result.netSaleProceedsBeforeTax,
              'net_sale_proceeds': result.netSaleProceeds,
              'total_return_before_tax': result.totalReturnBeforeTax,
              'total_return_after_tax': result.totalReturnAfterTax,
              'profit_before_tax': result.profitBeforeTax,
              'profit_after_tax': result.profitAfterTax,
              'gain_vs_total_investment': result.gainVsTotalInvestment,
              'tax_assessment_status': inputs.taxAssessmentStatus,
              'tax_notes': inputs.taxNotes,
              'closing_date': inputs.closingDate,
              'handover_date': inputs.handoverDate,
            }),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      final capValue = result.valueByTargetCapRate;
      await txn.insert(
        'disposition_valuation_methods',
        <String, Object?>{
          'id': const Uuid().v4(),
          'disposition_case_id': caseId,
          'method_name': 'Angebotspreis',
          'value_low': inputs.minimumSalePrice,
          'value_mid': inputs.expectedSalePrice,
          'value_high': inputs.targetSalePrice,
          'payload_json': jsonEncode(<String, Object?>{
            'minimum_sale_price': inputs.minimumSalePrice,
            'expected_sale_price': inputs.expectedSalePrice,
            'target_sale_price': inputs.targetSalePrice,
            'performance_vs_acquisition_cost':
                result.performanceVsAcquisitionCost,
            'performance_vs_renovation_adjusted_cost':
                result.performanceVsRenovationAdjustedCost,
          }),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      final explicitValuations = <MapEntry<String, double>>[
        MapEntry<String, double>(
          'Broker Opinion of Value',
          inputs.brokerOpinionValue,
        ),
        MapEntry<String, double>('Gutachterwert', inputs.appraiserValue),
        MapEntry<String, double>(
          'Interner Zielwert',
          inputs.internalTargetValue,
        ),
        MapEntry<String, double>('Marktwert', inputs.marketValue),
      ];
      for (final valuation in explicitValuations.where((item) => item.value > 0)) {
        await txn.insert(
          'disposition_valuation_methods',
          <String, Object?>{
            'id': const Uuid().v4(),
            'disposition_case_id': caseId,
            'method_name': valuation.key,
            'value_low': valuation.value,
            'value_mid': valuation.value,
            'value_high': valuation.value,
            'payload_json': jsonEncode(<String, Object?>{
              'source': 'manual_input',
              'method_name': valuation.key,
              'value': valuation.value,
              'buyer_group': inputs.buyerGroup,
              'sale_strategy': inputs.saleStrategy,
            }),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      await txn.insert(
        'disposition_valuation_methods',
        <String, Object?>{
          'id': const Uuid().v4(),
          'disposition_case_id': caseId,
          'method_name': 'Exit Cap Rate',
          'value_low': capValue == null ? null : capValue * 0.95,
          'value_mid': capValue,
          'value_high': capValue == null ? null : capValue * 1.05,
          'payload_json': jsonEncode(<String, Object?>{
            'stabilized_noi': inputs.stabilizedNoi,
            'exit_cap_rate': inputs.exitCapRate,
            'value_by_target_cap_rate': capValue,
            'gain_on_cost': result.gainOnCost,
            'equity_multiple': result.equityMultiple,
          }),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
    return scenarioId;
  }

  Future<void> saveDatasheet(ModuleDatasheet datasheet) async {
    final payload = datasheet.toJson();
    await _db.transaction((txn) async {
      await txn.insert(
        'calculation_datasheets',
        <String, Object?>{
          'id': datasheet.id,
          'module': datasheet.module,
          'property_id': datasheet.propertyId,
          'scenario_id': datasheet.scenarioId,
          'title': datasheet.title,
          'payload_json': jsonEncode(payload),
          'export_json': const JsonEncoder.withIndent('  ').convert(payload),
          'created_at': datasheet.createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'formula_audit_entries',
        where: 'datasheet_id = ?',
        whereArgs: <Object?>[datasheet.id],
      );

      for (final formula in datasheet.formulaAppendix) {
        await txn.insert(
          'formula_audit_entries',
          <String, Object?>{
            'id': const Uuid().v4(),
            'datasheet_id': datasheet.id,
            'module': datasheet.module,
            'property_id': datasheet.propertyId,
            'scenario_id': datasheet.scenarioId,
            'formula_name': formula['formula_name'] as String? ?? '',
            'formula_description': formula['description'] as String? ?? '',
            'input_json': jsonEncode(formula['inputs'] ?? <String, Object?>{}),
            'result': formula['result'],
            'unit': formula['unit'] as String? ?? '',
            'calculated_at':
                (formula['calculated_at'] as num?)?.toInt() ??
                    datasheet.createdAt,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }

  Future<Map<String, Object?>?> getDatasheet(String id) async {
    final rows = await _db.query(
      'calculation_datasheets',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<String?> getDatasheetExportJson(String id) async {
    final row = await getDatasheet(id);
    return row?['export_json'] as String?;
  }

  Future<List<Map<String, Object?>>> listDatasheets({
    String? module,
    String? propertyId,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (module != null) {
      where.add('module = ?');
      args.add(module);
    }
    if (propertyId != null) {
      where.add('property_id = ?');
      args.add(propertyId);
    }
    return _db.query(
      'calculation_datasheets',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
  }

  int? _dateMillis(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim())?.millisecondsSinceEpoch;
  }
}
