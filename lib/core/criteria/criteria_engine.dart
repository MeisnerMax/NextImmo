import '../models/analysis_result.dart';
import '../models/criteria.dart';
import '../models/inputs.dart';

class CriteriaEngine {
  const CriteriaEngine();

  CriteriaEvaluationResult evaluate({
    required List<CriteriaRule> rules,
    required AnalysisResult analysis,
    required ScenarioInputs inputs,
  }) {
    final evaluations = <RuleEvaluation>[];

    for (final rule in rules.where((r) => r.enabled)) {
      final actual = _resolveFieldValue(rule.fieldKey, analysis, inputs);
      if (actual == null) {
        evaluations.add(
          RuleEvaluation(
            rule: rule,
            actualValue: null,
            pass: false,
            unknown: true,
          ),
        );
        continue;
      }

      evaluations.add(
        RuleEvaluation(
          rule: rule,
          actualValue: actual,
          pass: _compare(actual, rule.operator, rule.targetValue),
          unknown: false,
        ),
      );
    }

    final failed =
        evaluations
            .where((e) => !e.unknown && !e.pass && e.rule.severity == 'hard')
            .toList();
    final warnings =
        evaluations
            .where((e) => !e.unknown && !e.pass && e.rule.severity == 'soft')
            .toList();
    final unknown = evaluations.where((e) => e.unknown).toList();

    return CriteriaEvaluationResult(
      passed: failed.isEmpty,
      evaluations: evaluations,
      failed: failed,
      warnings: warnings,
      unknown: unknown,
    );
  }

  double? _resolveFieldValue(
    String fieldKey,
    AnalysisResult analysis,
    ScenarioInputs inputs,
  ) {
    switch (fieldKey) {
      case 'cap_rate':
        return analysis.metrics.capRate;
      case 'cash_on_cash':
        return analysis.metrics.cashOnCash;
      case 'irr':
        return analysis.metrics.irr;
      case 'monthly_cashflow':
        return analysis.metrics.monthlyCashflowYear1;
      case 'dscr':
        return analysis.metrics.dscr;
      case 'noi':
        return analysis.metrics.noiYear1;
      case 'purchase_price':
        return inputs.purchasePrice;
      case 'rehab_budget':
        return inputs.rehabBudget;
      case 'total_cash_invested':
        return analysis.metrics.totalCashInvested;
      default:
        return null;
    }
  }

  bool _compare(double actual, String operator, double target) {
    switch (operator) {
      case 'gte':
        return actual >= target;
      case 'lte':
        return actual <= target;
      case 'gt':
        return actual > target;
      case 'lt':
        return actual < target;
      case 'eq':
        return (actual - target).abs() < 1e-9;
      default:
        return false;
    }
  }
}
