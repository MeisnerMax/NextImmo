import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/criteria/criteria_engine.dart';
import 'package:neximmo_app/core/engine/analysis_engine.dart';
import 'package:neximmo_app/core/models/criteria.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/settings.dart';

void main() {
  test('evaluates pass/fail/unknown correctly', () {
    const analysisEngine = AnalysisEngine();
    const criteriaEngine = CriteriaEngine();

    final settings = AppSettingsRecord(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final inputs = ScenarioInputs.defaults(
      scenarioId: 'scenario',
      settings: settings,
    ).copyWith(
      purchasePrice: 200000,
      rentMonthlyTotal: 1800,
      financingMode: 'cash',
    );

    final analysis = analysisEngine.run(
      inputs: inputs,
      settings: settings,
      incomeLines: const [],
      expenseLines: const [],
    );

    final rules = <CriteriaRule>[
      const CriteriaRule(
        id: 'r1',
        criteriaSetId: 'c1',
        fieldKey: 'cap_rate',
        operator: 'gte',
        targetValue: 0.05,
        unit: 'percent',
        severity: 'hard',
        enabled: true,
      ),
      const CriteriaRule(
        id: 'r2',
        criteriaSetId: 'c1',
        fieldKey: 'dscr',
        operator: 'gte',
        targetValue: 1.2,
        unit: 'number',
        severity: 'soft',
        enabled: true,
      ),
    ];

    final result = criteriaEngine.evaluate(
      rules: rules,
      analysis: analysis,
      inputs: inputs,
    );

    expect(result.evaluations.length, 2);
    expect(result.failed.length, lessThanOrEqualTo(1));
    expect(result.unknown.length, 1);
  });
}
