import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/scenario_valuation.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/core/versioning/scenario_diff.dart';
import 'package:neximmo_app/core/versioning/scenario_snapshot.dart';

void main() {
  test('scenario snapshot canonical json and hash are stable', () {
    final settings = AppSettingsRecord(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final inputs = ScenarioInputs.defaults(
      scenarioId: 's1',
      settings: settings,
    ).copyWith(purchasePrice: 123000, rentMonthlyTotal: 2000);
    final snapshotA = ScenarioSnapshot(
      scenarioId: 's1',
      inputs: inputs,
      incomeLines: const [
        IncomeLine(
          id: 'i2',
          scenarioId: 's1',
          name: 'Laundry',
          amountMonthly: 120,
          enabled: true,
        ),
        IncomeLine(
          id: 'i1',
          scenarioId: 's1',
          name: 'Parking',
          amountMonthly: 80,
          enabled: true,
        ),
      ],
      expenseLines: const [],
      valuation: ScenarioValuationRecord.defaults(scenarioId: 's1'),
    );
    final snapshotB = ScenarioSnapshot(
      scenarioId: 's1',
      inputs: inputs,
      incomeLines: const [
        IncomeLine(
          id: 'i1',
          scenarioId: 's1',
          name: 'Parking',
          amountMonthly: 80,
          enabled: true,
        ),
        IncomeLine(
          id: 'i2',
          scenarioId: 's1',
          name: 'Laundry',
          amountMonthly: 120,
          enabled: true,
        ),
      ],
      expenseLines: const [],
      valuation: ScenarioValuationRecord.defaults(scenarioId: 's1'),
    );

    expect(snapshotA.toCanonicalJson(), snapshotB.toCanonicalJson());
    expect(snapshotA.computeHash(), snapshotB.computeHash());
  });

  test('scenario diff detects changed fields', () {
    final settings = AppSettingsRecord(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final baseInputs = ScenarioInputs.defaults(
      scenarioId: 's2',
      settings: settings,
    );
    final a = ScenarioSnapshot(
      scenarioId: 's2',
      inputs: baseInputs.copyWith(purchasePrice: 100000),
      incomeLines: const [],
      expenseLines: const [],
      valuation: ScenarioValuationRecord.defaults(scenarioId: 's2'),
    );
    final b = ScenarioSnapshot(
      scenarioId: 's2',
      inputs: baseInputs.copyWith(purchasePrice: 120000),
      incomeLines: const [],
      expenseLines: const [],
      valuation: ScenarioValuationRecord.defaults(
        scenarioId: 's2',
      ).copyWith(valuationMode: 'exit_cap', exitCapRatePercent: 0.05),
    );

    final diff = const ScenarioDiff().computeDiff(a, b);
    expect(
      diff.where((item) => item.fieldKey.contains('purchase_price')),
      isNotEmpty,
    );
    expect(
      diff.where((item) => item.fieldKey.contains('valuation_mode')),
      isNotEmpty,
    );
  });
}
