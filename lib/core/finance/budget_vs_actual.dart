import '../models/budget.dart';
import '../models/ledger.dart';

class BudgetVsActual {
  const BudgetVsActual();

  List<BudgetVarianceRecord> computeVariance({
    required List<BudgetLineRecord> budgetLines,
    required List<LedgerEntryRecord> ledgerEntries,
  }) {
    final budgetByKey = <String, double>{};
    for (final line in budgetLines) {
      final key = '${line.accountId}|${line.periodKey}';
      final value = _signed(line.direction, line.amount);
      budgetByKey[key] = (budgetByKey[key] ?? 0.0) + value;
    }

    final actualByKey = <String, double>{};
    for (final entry in ledgerEntries) {
      final key = '${entry.accountId}|${entry.periodKey}';
      final value = _signed(entry.direction, entry.amount);
      actualByKey[key] = (actualByKey[key] ?? 0.0) + value;
    }

    final keys =
        <String>{...budgetByKey.keys, ...actualByKey.keys}.toList()..sort();

    return keys
        .map((key) {
          final parts = key.split('|');
          final accountId = parts[0];
          final periodKey = parts[1];
          final budget = budgetByKey[key] ?? 0.0;
          final actual = actualByKey[key] ?? 0.0;
          final variance = actual - budget;
          final percent = budget == 0 ? null : (variance / budget);
          return BudgetVarianceRecord(
            accountId: accountId,
            periodKey: periodKey,
            budgetAmount: budget,
            actualAmount: actual,
            varianceAmount: variance,
            variancePercent: percent,
          );
        })
        .toList(growable: false);
  }

  double _signed(String direction, double amount) {
    return direction == 'in' ? amount.abs() : -amount.abs();
  }
}
