import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/finance/budget_vs_actual.dart';
import 'package:neximmo_app/core/models/budget.dart';
import 'package:neximmo_app/core/models/ledger.dart';

void main() {
  test('computes variance with signed directions', () {
    const engine = BudgetVsActual();
    final budget = [
      const BudgetLineRecord(
        id: 'b1',
        budgetId: 'budget_1',
        accountId: 'a1',
        periodKey: '2026-01',
        direction: 'out',
        amount: 100,
        notes: null,
      ),
    ];
    final actual = [
      const LedgerEntryRecord(
        id: 'l1',
        entityType: 'asset_property',
        entityId: 'p1',
        accountId: 'a1',
        postedAt: 1,
        periodKey: '2026-01',
        direction: 'out',
        amount: 120,
        currencyCode: 'EUR',
        counterparty: null,
        memo: null,
        documentId: null,
        createdAt: 1,
      ),
    ];

    final rows = engine.computeVariance(
      budgetLines: budget,
      ledgerEntries: actual,
    );
    expect(rows.length, 1);
    expect(rows.first.budgetAmount, -100);
    expect(rows.first.actualAmount, -120);
    expect(rows.first.varianceAmount, -20);
  });
}
