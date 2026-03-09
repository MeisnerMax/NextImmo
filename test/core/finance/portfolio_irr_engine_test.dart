import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/finance/portfolio_irr_engine.dart';
import 'package:neximmo_app/core/models/portfolio_analytics.dart';

void main() {
  test('computes deterministic xirr for dated cashflows', () {
    const engine = PortfolioIrrEngine();
    final result = engine.compute(
      cashflows: <PortfolioCashflowRecord>[
        PortfolioCashflowRecord(
          date: DateTime(2024, 1, 1),
          periodKey: '2024-01',
          amountSigned: -100000,
          sourceType: 'acquisition',
          assetId: 'a1',
          notes: null,
        ),
        PortfolioCashflowRecord(
          date: DateTime(2024, 12, 31),
          periodKey: '2024-12',
          amountSigned: 120000,
          sourceType: 'disposition',
          assetId: 'a1',
          notes: null,
        ),
      ],
    );

    expect(result.irr, isNotNull);
    expect(result.irr!, closeTo(0.2, 0.002));
    expect(result.warning, isNull);
  });

  test('returns warning when no signed variation exists', () {
    const engine = PortfolioIrrEngine();
    final result = engine.compute(
      cashflows: <PortfolioCashflowRecord>[
        PortfolioCashflowRecord(
          date: DateTime(2024, 1, 1),
          periodKey: '2024-01',
          amountSigned: 1000,
          sourceType: 'ledger:income',
          assetId: 'a1',
          notes: null,
        ),
      ],
    );

    expect(result.irr, isNull);
    expect(result.warning, isNotNull);
  });
}
