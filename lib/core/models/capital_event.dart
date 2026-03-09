class CapitalEventRecord {
  const CapitalEventRecord({
    required this.id,
    required this.assetPropertyId,
    required this.eventType,
    required this.postedAt,
    required this.periodKey,
    required this.direction,
    required this.amount,
    required this.notes,
    required this.createdAt,
  });

  final String id;
  final String assetPropertyId;
  final String eventType;
  final int postedAt;
  final String periodKey;
  final String direction;
  final double amount;
  final String? notes;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'asset_property_id': assetPropertyId,
      'event_type': eventType,
      'posted_at': postedAt,
      'period_key': periodKey,
      'direction': direction,
      'amount': amount,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  factory CapitalEventRecord.fromMap(Map<String, Object?> map) {
    return CapitalEventRecord(
      id: map['id']! as String,
      assetPropertyId: map['asset_property_id']! as String,
      eventType: map['event_type']! as String,
      postedAt: (map['posted_at']! as num).toInt(),
      periodKey: map['period_key']! as String,
      direction: map['direction']! as String,
      amount: ((map['amount'] as num?) ?? 0).toDouble().abs(),
      notes: map['notes'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}
