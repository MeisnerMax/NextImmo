import '../models/analysis_result.dart';
import '../models/inputs.dart';
import '../models/scenario_valuation.dart';
import '../models/settings.dart';
import 'metrics.dart';
import 'normalize.dart';
import 'proforma.dart';

class AnalysisEngine {
  const AnalysisEngine();

  AnalysisResult run({
    required ScenarioInputs inputs,
    required AppSettingsRecord settings,
    required List<IncomeLine> incomeLines,
    required List<ExpenseLine> expenseLines,
    ScenarioValuationRecord? valuation,
  }) {
    final normalized = normalizeInputs(
      inputs: inputs,
      settings: settings,
      incomeLines: incomeLines,
      expenseLines: expenseLines,
    );

    final warnings = <String>[];
    if (normalized.inputs.purchasePrice <= 0) {
      warnings.add('Purchase price should be greater than 0.');
    }

    final proforma = buildProforma(
      normalized,
      valuation:
          valuation ??
          ScenarioValuationRecord.defaults(scenarioId: inputs.scenarioId),
    );
    warnings.addAll(proforma.warnings);

    final metrics = computeMetrics(
      normalized: normalized,
      proforma: proforma,
      warnings: warnings,
    );

    return AnalysisResult(
      metrics: metrics,
      proformaMonths: proforma.proformaMonths,
      proformaYears: proforma.proformaYears,
      amortizationSchedule: proforma.amortizationSchedule,
      warnings: warnings,
    );
  }
}
