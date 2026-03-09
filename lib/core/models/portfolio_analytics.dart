class PortfolioCashflowRecord {
  const PortfolioCashflowRecord({
    required this.date,
    required this.periodKey,
    required this.amountSigned,
    required this.sourceType,
    required this.assetId,
    required this.notes,
  });

  final DateTime date;
  final String periodKey;
  final double amountSigned;
  final String sourceType;
  final String? assetId;
  final String? notes;
}

class PortfolioCashflowPeriodAggregate {
  const PortfolioCashflowPeriodAggregate({
    required this.periodKey,
    required this.totalInflows,
    required this.totalOutflows,
    required this.netCashflow,
  });

  final String periodKey;
  final double totalInflows;
  final double totalOutflows;
  final double netCashflow;
}

class PortfolioIrrResult {
  const PortfolioIrrResult({
    required this.irr,
    required this.warning,
    required this.totalInflows,
    required this.totalOutflows,
    required this.netCashflow,
    required this.averageMonthlyNet,
    required this.datedCashflows,
    required this.periodTable,
  });

  final double? irr;
  final String? warning;
  final double totalInflows;
  final double totalOutflows;
  final double netCashflow;
  final double averageMonthlyNet;
  final List<PortfolioCashflowRecord> datedCashflows;
  final List<PortfolioCashflowPeriodAggregate> periodTable;
}
