import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/finance/budget_vs_actual.dart';
import 'package:neximmo_app/core/models/budget.dart';
import 'package:neximmo_app/core/models/ledger.dart';

void main() {
  test('GM-BVA-001 computes variance with signed directions', () {
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
    expect(rows.first.variancePercent, closeTo(0.2, 0.000001));
  });

  test('aggregates multiple lines by account and period', () {
    const engine = BudgetVsActual();
    final budget = [
      const BudgetLineRecord(
        id: 'b1',
        budgetId: 'budget_1',
        accountId: 'a1',
        periodKey: '2026-01',
        direction: 'out',
        amount: 40,
        notes: null,
      ),
      const BudgetLineRecord(
        id: 'b2',
        budgetId: 'budget_1',
        accountId: 'a1',
        periodKey: '2026-01',
        direction: 'out',
        amount: 60,
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
        amount: 50,
        currencyCode: 'EUR',
        counterparty: null,
        memo: null,
        documentId: null,
        createdAt: 1,
      ),
      const LedgerEntryRecord(
        id: 'l2',
        entityType: 'asset_property',
        entityId: 'p1',
        accountId: 'a1',
        postedAt: 1,
        periodKey: '2026-01',
        direction: 'out',
        amount: 70,
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

    expect(rows, hasLength(1));
    expect(rows.single.budgetAmount, -100);
    expect(rows.single.actualAmount, -120);
    expect(rows.single.varianceAmount, -20);
    expect(rows.single.variancePercent, closeTo(0.2, 0.000001));
  });
}
