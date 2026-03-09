import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/portfolio_pack.dart';
import 'package:neximmo_app/core/reports/portfolio_pack_builder.dart';

void main() {
  test('buildPack creates manifest with section flags and file totals', () {
    const builder = PortfolioPackBuilder();
    const plan = PortfolioPackPlan(
      portfolioId: 'p1',
      portfolioName: 'Fund I',
      fromPeriodKey: '2026-01',
      toPeriodKey: '2026-03',
      includePortfolioSummaryPdf: true,
      includeAssetFactsheetsPdf: false,
      includeEsgReport: true,
      includeRentRollCsv: true,
      includeBudgetVsActualCsv: false,
      includeLedgerSummaryCsv: true,
      includeDebtScheduleCsv: false,
      includeCovenantStatusCsv: true,
    );
    final output = builder.buildPack(
      plan: plan,
      generatedFiles: const [
        PortfolioPackFile(
          relativePath: 'pdfs/portfolio_summary.pdf',
          bytes: <int>[1, 2, 3],
          includeSha256: true,
        ),
        PortfolioPackFile(
          relativePath: 'csv/rent_roll/a.csv',
          bytes: <int>[10, 11],
          includeSha256: false,
        ),
      ],
      appVersion: '1.0.0+1',
      dbSchemaVersion: 11,
      createdAt: 123456,
      assetsCount: 2,
    );

    expect(
      output.files.any((file) => file.relativePath == 'meta/manifest.json'),
      isTrue,
    );

    final manifest = jsonDecode(output.manifestJson) as Map<String, dynamic>;
    expect(manifest['portfolio_id'], 'p1');
    expect(manifest['period_range']['from_period_key'], '2026-01');
    expect(manifest['included_sections']['include_esg_report'], isTrue);
    expect(
      manifest['included_sections']['include_budget_vs_actual_csv'],
      isFalse,
    );
    expect(manifest['totals']['assets_count'], 2);
    expect(manifest['totals']['files_count'], 3);
  });
}
