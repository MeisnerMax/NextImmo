class PortfolioPackPlan {
  const PortfolioPackPlan({
    required this.portfolioId,
    required this.portfolioName,
    required this.fromPeriodKey,
    required this.toPeriodKey,
    required this.includePortfolioSummaryPdf,
    required this.includeAssetFactsheetsPdf,
    required this.includeEsgReport,
    required this.includeRentRollCsv,
    required this.includeBudgetVsActualCsv,
    required this.includeLedgerSummaryCsv,
    required this.includeDebtScheduleCsv,
    required this.includeCovenantStatusCsv,
  });

  final String portfolioId;
  final String portfolioName;
  final String fromPeriodKey;
  final String toPeriodKey;
  final bool includePortfolioSummaryPdf;
  final bool includeAssetFactsheetsPdf;
  final bool includeEsgReport;
  final bool includeRentRollCsv;
  final bool includeBudgetVsActualCsv;
  final bool includeLedgerSummaryCsv;
  final bool includeDebtScheduleCsv;
  final bool includeCovenantStatusCsv;

  Map<String, Object?> toIncludedSectionsJson() {
    return <String, Object?>{
      'include_portfolio_summary_pdf': includePortfolioSummaryPdf,
      'include_asset_factsheets_pdf': includeAssetFactsheetsPdf,
      'include_esg_report': includeEsgReport,
      'include_rent_roll_csv': includeRentRollCsv,
      'include_budget_vs_actual_csv': includeBudgetVsActualCsv,
      'include_ledger_summary_csv': includeLedgerSummaryCsv,
      'include_debt_schedule_csv': includeDebtScheduleCsv,
      'include_covenant_status_csv': includeCovenantStatusCsv,
    };
  }
}

class PortfolioPackFile {
  const PortfolioPackFile({
    required this.relativePath,
    required this.bytes,
    required this.includeSha256,
  });

  final String relativePath;
  final List<int> bytes;
  final bool includeSha256;
}

class PortfolioPackBuildOutput {
  const PortfolioPackBuildOutput({
    required this.files,
    required this.manifestJson,
  });

  final List<PortfolioPackFile> files;
  final String manifestJson;
}
