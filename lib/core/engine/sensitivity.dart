import '../models/analysis_result.dart';
import '../models/inputs.dart';
import '../models/scenario_valuation.dart';
import '../models/settings.dart';
import 'analysis_engine.dart';

enum SensitivityMetric { cashOnCash, capRate, irr, monthlyCashflow }

enum SensitivityRangePreset { tight, standard, wide }

class SensitivityConfig {
  const SensitivityConfig({
    required this.metric,
    required this.rentDeltas,
    required this.purchasePriceDeltas,
  });

  final SensitivityMetric metric;
  final List<double> rentDeltas;
  final List<double> purchasePriceDeltas;

  String cacheKey({
    required String scenarioId,
    required int inputsUpdatedAt,
    required int settingsUpdatedAt,
  }) {
    return [
      scenarioId,
      inputsUpdatedAt.toString(),
      settingsUpdatedAt.toString(),
      metric.name,
      rentDeltas.join('|'),
      purchasePriceDeltas.join('|'),
    ].join('::');
  }
}

class SensitivityGridResult {
  const SensitivityGridResult({
    required this.metric,
    required this.rentDeltas,
    required this.purchasePriceDeltas,
    required this.cells,
  });

  final SensitivityMetric metric;
  final List<double> rentDeltas;
  final List<double> purchasePriceDeltas;
  final List<List<double?>> cells;
}

class SensitivityEngine {
  const SensitivityEngine({
    AnalysisEngine analysisEngine = const AnalysisEngine(),
  }) : _analysisEngine = analysisEngine;

  final AnalysisEngine _analysisEngine;

  SensitivityGridResult run({
    required SensitivityConfig config,
    required ScenarioInputs inputs,
    required AppSettingsRecord settings,
    required List<IncomeLine> incomeLines,
    required List<ExpenseLine> expenseLines,
    ScenarioValuationRecord? valuation,
  }) {
    final baseRent = inputs.rentOverride ?? inputs.rentMonthlyTotal;
    final baseHasRentOverride = inputs.rentOverride != null;

    final cells = <List<double?>>[];
    for (final purchaseDelta in config.purchasePriceDeltas) {
      final row = <double?>[];
      for (final rentDelta in config.rentDeltas) {
        final adjustedRent = baseRent * (1 + rentDelta);
        final adjustedPurchasePrice =
            inputs.purchasePrice * (1 + purchaseDelta);

        final adjustedInputs = inputs.copyWith(
          purchasePrice: adjustedPurchasePrice,
          rentMonthlyTotal: adjustedRent,
          rentOverride: baseHasRentOverride ? adjustedRent : null,
          clearRentOverride: !baseHasRentOverride,
          updatedAt: inputs.updatedAt,
        );

        final analysis = _analysisEngine.run(
          inputs: adjustedInputs,
          settings: settings,
          incomeLines: incomeLines,
          expenseLines: expenseLines,
          valuation: valuation,
        );
        row.add(_pickMetric(config.metric, analysis.metrics));
      }
      cells.add(row);
    }

    return SensitivityGridResult(
      metric: config.metric,
      rentDeltas: List<double>.of(config.rentDeltas),
      purchasePriceDeltas: List<double>.of(config.purchasePriceDeltas),
      cells: cells,
    );
  }

  static List<double> rangeByPreset(SensitivityRangePreset preset) {
    switch (preset) {
      case SensitivityRangePreset.tight:
        return const <double>[-0.1, -0.05, 0, 0.05, 0.1];
      case SensitivityRangePreset.standard:
        return const <double>[-0.2, -0.1, 0, 0.1, 0.2];
      case SensitivityRangePreset.wide:
        return const <double>[-0.3, -0.15, 0, 0.15, 0.3];
    }
  }

  static double? _pickMetric(
    SensitivityMetric metric,
    AnalysisMetrics metrics,
  ) {
    switch (metric) {
      case SensitivityMetric.cashOnCash:
        return metrics.cashOnCash;
      case SensitivityMetric.capRate:
        return metrics.capRate;
      case SensitivityMetric.irr:
        return metrics.irr;
      case SensitivityMetric.monthlyCashflow:
        return metrics.monthlyCashflowYear1;
    }
  }
}
