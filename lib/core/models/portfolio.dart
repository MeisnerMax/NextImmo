class PortfolioRecord {
  const PortfolioRecord({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'description': description,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory PortfolioRecord.fromMap(Map<String, Object?> map) {
    return PortfolioRecord(
      id: map['id']! as String,
      name: map['name']! as String,
      description: map['description'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class PortfolioPropertyLink {
  const PortfolioPropertyLink({
    required this.portfolioId,
    required this.propertyId,
    required this.createdAt,
  });

  final String portfolioId;
  final String propertyId;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'portfolio_id': portfolioId,
      'property_id': propertyId,
      'created_at': createdAt,
    };
  }

  factory PortfolioPropertyLink.fromMap(Map<String, Object?> map) {
    return PortfolioPropertyLink(
      portfolioId: map['portfolio_id']! as String,
      propertyId: map['property_id']! as String,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class PropertyProfileRecord {
  const PropertyProfileRecord({
    required this.propertyId,
    required this.status,
    required this.unitsCountOverride,
    required this.updatedAt,
  });

  final String propertyId;
  final String status;
  final int? unitsCountOverride;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'property_id': propertyId,
      'status': status,
      'units_count_override': unitsCountOverride,
      'updated_at': updatedAt,
    };
  }

  factory PropertyProfileRecord.fromMap(Map<String, Object?> map) {
    return PropertyProfileRecord(
      propertyId: map['property_id']! as String,
      status: (map['status'] as String?) ?? 'active',
      unitsCountOverride: (map['units_count_override'] as num?)?.toInt(),
      updatedAt: ((map['updated_at'] as num?) ?? 0).toInt(),
    );
  }
}

class PropertyKpiSnapshotRecord {
  const PropertyKpiSnapshotRecord({
    required this.id,
    required this.propertyId,
    required this.scenarioId,
    required this.periodDate,
    required this.noi,
    required this.occupancy,
    required this.capex,
    required this.valuation,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String propertyId;
  final String? scenarioId;
  final String periodDate;
  final double? noi;
  final double? occupancy;
  final double? capex;
  final double? valuation;
  final String source;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'property_id': propertyId,
      'scenario_id': scenarioId,
      'period_date': periodDate,
      'noi': noi,
      'occupancy': occupancy,
      'capex': capex,
      'valuation': valuation,
      'source': source,
      'created_at': createdAt,
    };
  }

  factory PropertyKpiSnapshotRecord.fromMap(Map<String, Object?> map) {
    return PropertyKpiSnapshotRecord(
      id: map['id']! as String,
      propertyId: map['property_id']! as String,
      scenarioId: map['scenario_id'] as String?,
      periodDate: map['period_date']! as String,
      noi: (map['noi'] as num?)?.toDouble(),
      occupancy: (map['occupancy'] as num?)?.toDouble(),
      capex: (map['capex'] as num?)?.toDouble(),
      valuation: (map['valuation'] as num?)?.toDouble(),
      source: (map['source'] as String?) ?? 'manual',
      createdAt: ((map['created_at'] as num?) ?? 0).toInt(),
    );
  }
}
