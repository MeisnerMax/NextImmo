class DerivedProformaYear {
  const DerivedProformaYear({
    required this.yearIndex,
    required this.gsi,
    required this.vacancyLoss,
    required this.egi,
    required this.opex,
    required this.noi,
    required this.debtService,
    required this.cashflowBeforeTax,
    required this.loanBalanceEnd,
    required this.equityEnd,
  });

  final int yearIndex;
  final double gsi;
  final double vacancyLoss;
  final double egi;
  final double opex;
  final double noi;
  final double debtService;
  final double cashflowBeforeTax;
  final double loanBalanceEnd;
  final double equityEnd;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'year_index': yearIndex,
      'gsi': gsi,
      'vacancy_loss': vacancyLoss,
      'egi': egi,
      'opex': opex,
      'noi': noi,
      'debt_service': debtService,
      'cashflow_before_tax': cashflowBeforeTax,
      'loan_balance_end': loanBalanceEnd,
      'equity_end': equityEnd,
    };
  }
}

class AmortizationEntry {
  const AmortizationEntry({
    required this.monthIndex,
    required this.payment,
    required this.interest,
    required this.principal,
    required this.balance,
  });

  final int monthIndex;
  final double payment;
  final double interest;
  final double principal;
  final double balance;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'month_index': monthIndex,
      'payment': payment,
      'interest': interest,
      'principal': principal,
      'balance': balance,
    };
  }
}

class AnalysisMetrics {
  const AnalysisMetrics({
    required this.monthlyCashflowYear1,
    required this.annualCashflowYear1,
    required this.noiYear1,
    required this.capRate,
    required this.cashOnCash,
    required this.irr,
    required this.roi,
    required this.dscr,
    required this.breakEvenYear,
    required this.totalCashInvested,
    required this.exitCashflow,
    this.exitSalePrice = 0,
    this.exitSaleCosts = 0,
    this.exitLoanPayoff = 0,
    this.exitNetSale = 0,
    this.exitStabilizedNoi,
    this.valuationMode = 'appreciation',
  });

  final double monthlyCashflowYear1;
  final double annualCashflowYear1;
  final double noiYear1;
  final double capRate;
  final double cashOnCash;
  final double? irr;
  final double roi;
  final double? dscr;
  final int? breakEvenYear;
  final double totalCashInvested;
  final double exitCashflow;
  final double exitSalePrice;
  final double exitSaleCosts;
  final double exitLoanPayoff;
  final double exitNetSale;
  final double? exitStabilizedNoi;
  final String valuationMode;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'monthly_cashflow_year1': monthlyCashflowYear1,
      'annual_cashflow_year1': annualCashflowYear1,
      'noi_year1': noiYear1,
      'cap_rate': capRate,
      'cash_on_cash': cashOnCash,
      'irr': irr,
      'roi': roi,
      'dscr': dscr,
      'break_even_year': breakEvenYear,
      'total_cash_invested': totalCashInvested,
      'exit_cashflow': exitCashflow,
      'exit_sale_price': exitSalePrice,
      'exit_sale_costs': exitSaleCosts,
      'exit_loan_payoff': exitLoanPayoff,
      'exit_net_sale': exitNetSale,
      'exit_stabilized_noi': exitStabilizedNoi,
      'valuation_mode': valuationMode,
    };
  }
}

class AnalysisResult {
  const AnalysisResult({
    required this.metrics,
    required this.proformaYears,
    required this.amortizationSchedule,
    required this.warnings,
  });

  final AnalysisMetrics metrics;
  final List<DerivedProformaYear> proformaYears;
  final List<AmortizationEntry> amortizationSchedule;
  final List<String> warnings;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'metrics': metrics.toJson(),
      'proforma_years': proformaYears.map((year) => year.toJson()).toList(),
      'amortization_schedule':
          amortizationSchedule.map((entry) => entry.toJson()).toList(),
      'warnings': warnings,
    };
  }
}
