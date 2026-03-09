class BudgetRecord {
  const BudgetRecord({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.fiscalYear,
    required this.versionName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final int fiscalYear;
  final String versionName;
  final String status;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'fiscal_year': fiscalYear,
      'version_name': versionName,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory BudgetRecord.fromMap(Map<String, Object?> map) {
    return BudgetRecord(
      id: map['id']! as String,
      entityType: map['entity_type']! as String,
      entityId: map['entity_id']! as String,
      fiscalYear: (map['fiscal_year']! as num).toInt(),
      versionName: map['version_name']! as String,
      status: map['status']! as String,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class BudgetLineRecord {
  const BudgetLineRecord({
    required this.id,
    required this.budgetId,
    required this.accountId,
    required this.periodKey,
    required this.direction,
    required this.amount,
    required this.notes,
  });

  final String id;
  final String budgetId;
  final String accountId;
  final String periodKey;
  final String direction;
  final double amount;
  final String? notes;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'budget_id': budgetId,
      'account_id': accountId,
      'period_key': periodKey,
      'direction': direction,
      'amount': amount,
      'notes': notes,
    };
  }

  factory BudgetLineRecord.fromMap(Map<String, Object?> map) {
    return BudgetLineRecord(
      id: map['id']! as String,
      budgetId: map['budget_id']! as String,
      accountId: map['account_id']! as String,
      periodKey: map['period_key']! as String,
      direction: map['direction']! as String,
      amount: (map['amount']! as num).toDouble(),
      notes: map['notes'] as String?,
    );
  }
}

class BudgetVarianceRecord {
  const BudgetVarianceRecord({
    required this.accountId,
    required this.periodKey,
    required this.budgetAmount,
    required this.actualAmount,
    required this.varianceAmount,
    required this.variancePercent,
  });

  final String accountId;
  final String periodKey;
  final double budgetAmount;
  final double actualAmount;
  final double varianceAmount;
  final double? variancePercent;
}

class BudgetDetail {
  const BudgetDetail({required this.budget, required this.lines});

  final BudgetRecord budget;
  final List<BudgetLineRecord> lines;
}
