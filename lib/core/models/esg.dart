class EsgProfileRecord {
  const EsgProfileRecord({
    required this.propertyId,
    required this.epcRating,
    required this.epcValidUntil,
    required this.emissionsKgCo2M2,
    required this.lastAuditDate,
    required this.targetRating,
    required this.notes,
    required this.updatedAt,
  });

  final String propertyId;
  final String? epcRating;
  final int? epcValidUntil;
  final double? emissionsKgCo2M2;
  final int? lastAuditDate;
  final String? targetRating;
  final String? notes;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'property_id': propertyId,
      'epc_rating': epcRating,
      'epc_valid_until': epcValidUntil,
      'emissions_kgco2_m2': emissionsKgCo2M2,
      'last_audit_date': lastAuditDate,
      'target_rating': targetRating,
      'notes': notes,
      'updated_at': updatedAt,
    };
  }

  factory EsgProfileRecord.fromMap(Map<String, Object?> map) {
    return EsgProfileRecord(
      propertyId: map['property_id']! as String,
      epcRating: map['epc_rating'] as String?,
      epcValidUntil: (map['epc_valid_until'] as num?)?.toInt(),
      emissionsKgCo2M2: (map['emissions_kgco2_m2'] as num?)?.toDouble(),
      lastAuditDate: (map['last_audit_date'] as num?)?.toInt(),
      targetRating: map['target_rating'] as String?,
      notes: map['notes'] as String?,
      updatedAt: ((map['updated_at'] as num?) ?? 0).toInt(),
    );
  }
}
