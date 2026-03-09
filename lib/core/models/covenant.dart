class LoanRecord {
  const LoanRecord({
    required this.id,
    required this.assetPropertyId,
    required this.lenderName,
    required this.principal,
    required this.interestRatePercent,
    required this.termYears,
    required this.startDate,
    required this.amortizationType,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String assetPropertyId;
  final String? lenderName;
  final double principal;
  final double interestRatePercent;
  final int termYears;
  final int startDate;
  final String amortizationType;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'asset_property_id': assetPropertyId,
      'lender_name': lenderName,
      'principal': principal,
      'interest_rate_percent': interestRatePercent,
      'term_years': termYears,
      'start_date': startDate,
      'amortization_type': amortizationType,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory LoanRecord.fromMap(Map<String, Object?> map) {
    return LoanRecord(
      id: map['id']! as String,
      assetPropertyId: map['asset_property_id']! as String,
      lenderName: map['lender_name'] as String?,
      principal: (map['principal']! as num).toDouble(),
      interestRatePercent: (map['interest_rate_percent']! as num).toDouble(),
      termYears: (map['term_years']! as num).toInt(),
      startDate: (map['start_date']! as num).toInt(),
      amortizationType: map['amortization_type']! as String,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class LoanPeriodRecord {
  const LoanPeriodRecord({
    required this.id,
    required this.loanId,
    required this.periodKey,
    required this.balanceEnd,
    required this.debtService,
  });

  final String id;
  final String loanId;
  final String periodKey;
  final double balanceEnd;
  final double debtService;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'loan_id': loanId,
      'period_key': periodKey,
      'balance_end': balanceEnd,
      'debt_service': debtService,
    };
  }

  factory LoanPeriodRecord.fromMap(Map<String, Object?> map) {
    return LoanPeriodRecord(
      id: map['id']! as String,
      loanId: map['loan_id']! as String,
      periodKey: map['period_key']! as String,
      balanceEnd: (map['balance_end']! as num).toDouble(),
      debtService: (map['debt_service']! as num).toDouble(),
    );
  }
}

class CovenantRecord {
  const CovenantRecord({
    required this.id,
    required this.loanId,
    required this.kind,
    required this.threshold,
    required this.operator,
    required this.severity,
    required this.createdAt,
  });

  final String id;
  final String loanId;
  final String kind;
  final double threshold;
  final String operator;
  final String severity;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'loan_id': loanId,
      'kind': kind,
      'threshold': threshold,
      'operator': operator,
      'severity': severity,
      'created_at': createdAt,
    };
  }

  factory CovenantRecord.fromMap(Map<String, Object?> map) {
    return CovenantRecord(
      id: map['id']! as String,
      loanId: map['loan_id']! as String,
      kind: map['kind']! as String,
      threshold: (map['threshold']! as num).toDouble(),
      operator: map['operator']! as String,
      severity: map['severity']! as String,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class CovenantCheckRecord {
  const CovenantCheckRecord({
    required this.id,
    required this.covenantId,
    required this.periodKey,
    required this.actualValue,
    required this.pass,
    required this.checkedAt,
    required this.notes,
  });

  final String id;
  final String covenantId;
  final String periodKey;
  final double? actualValue;
  final bool pass;
  final int checkedAt;
  final String? notes;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'covenant_id': covenantId,
      'period_key': periodKey,
      'actual_value': actualValue,
      'pass': pass ? 1 : 0,
      'checked_at': checkedAt,
      'notes': notes,
    };
  }

  factory CovenantCheckRecord.fromMap(Map<String, Object?> map) {
    return CovenantCheckRecord(
      id: map['id']! as String,
      covenantId: map['covenant_id']! as String,
      periodKey: map['period_key']! as String,
      actualValue: (map['actual_value'] as num?)?.toDouble(),
      pass: ((map['pass'] as num?) ?? 0) == 1,
      checkedAt: (map['checked_at']! as num).toInt(),
      notes: map['notes'] as String?,
    );
  }
}
