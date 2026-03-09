class LedgerAccountRecord {
  const LedgerAccountRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String kind;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'kind': kind,
      'created_at': createdAt,
    };
  }

  factory LedgerAccountRecord.fromMap(Map<String, Object?> map) {
    return LedgerAccountRecord(
      id: map['id']! as String,
      name: map['name']! as String,
      kind: map['kind']! as String,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class LedgerEntryRecord {
  const LedgerEntryRecord({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.accountId,
    required this.postedAt,
    required this.periodKey,
    required this.direction,
    required this.amount,
    required this.currencyCode,
    required this.counterparty,
    required this.memo,
    required this.documentId,
    required this.createdAt,
  });

  final String id;
  final String entityType;
  final String? entityId;
  final String accountId;
  final int postedAt;
  final String periodKey;
  final String direction;
  final double amount;
  final String currencyCode;
  final String? counterparty;
  final String? memo;
  final String? documentId;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'account_id': accountId,
      'posted_at': postedAt,
      'period_key': periodKey,
      'direction': direction,
      'amount': amount,
      'currency_code': currencyCode,
      'counterparty': counterparty,
      'memo': memo,
      'document_id': documentId,
      'created_at': createdAt,
    };
  }

  factory LedgerEntryRecord.fromMap(Map<String, Object?> map) {
    return LedgerEntryRecord(
      id: map['id']! as String,
      entityType: map['entity_type']! as String,
      entityId: map['entity_id'] as String?,
      accountId: map['account_id']! as String,
      postedAt: (map['posted_at']! as num).toInt(),
      periodKey: map['period_key']! as String,
      direction: map['direction']! as String,
      amount: (map['amount']! as num).toDouble(),
      currencyCode: map['currency_code']! as String,
      counterparty: map['counterparty'] as String?,
      memo: map['memo'] as String?,
      documentId: map['document_id'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class LedgerPeriodAggregate {
  const LedgerPeriodAggregate({
    required this.periodKey,
    required this.totalIn,
    required this.totalOut,
    required this.net,
  });

  final String periodKey;
  final double totalIn;
  final double totalOut;
  final double net;
}
