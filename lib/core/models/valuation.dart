import 'dart:convert';

class ValuationPropertySnapshot {
  const ValuationPropertySnapshot({
    required this.scenarioId,
    required this.sourcePropertyId,
    required this.propertyName,
    required this.addressLine1,
    this.addressLine2,
    required this.zip,
    required this.city,
    required this.country,
    required this.propertyType,
    required this.units,
    this.grossAreaSqm,
    this.residentialAreaSqm,
    this.commercialAreaSqm,
    this.yearBuilt,
    this.purchasePrice,
    this.rentMonthlyTotal,
    this.vacancyPercent,
    this.operatingCostsMonthly,
    this.documentStatus,
    this.technicalInfo,
    required this.autoImportedFields,
    required this.manualAdjustedFields,
    required this.createdAt,
    required this.updatedAt,
  });

  final String scenarioId;
  final String sourcePropertyId;
  final String propertyName;
  final String addressLine1;
  final String? addressLine2;
  final String zip;
  final String city;
  final String country;
  final String propertyType;
  final int units;
  final double? grossAreaSqm;
  final double? residentialAreaSqm;
  final double? commercialAreaSqm;
  final int? yearBuilt;
  final double? purchasePrice;
  final double? rentMonthlyTotal;
  final double? vacancyPercent;
  final double? operatingCostsMonthly;
  final String? documentStatus;
  final String? technicalInfo;
  final List<String> autoImportedFields;
  final List<String> manualAdjustedFields;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'scenario_id': scenarioId,
      'source_property_id': sourcePropertyId,
      'property_name': propertyName,
      'address_line1': addressLine1,
      'address_line2': addressLine2,
      'zip': zip,
      'city': city,
      'country': country,
      'property_type': propertyType,
      'units': units,
      'gross_area_sqm': grossAreaSqm,
      'residential_area_sqm': residentialAreaSqm,
      'commercial_area_sqm': commercialAreaSqm,
      'year_built': yearBuilt,
      'purchase_price': purchasePrice,
      'rent_monthly_total': rentMonthlyTotal,
      'vacancy_percent': vacancyPercent,
      'operating_costs_monthly': operatingCostsMonthly,
      'document_status': documentStatus,
      'technical_info': technicalInfo,
      'auto_imported_fields_json': jsonEncode(autoImportedFields),
      'manual_adjusted_fields_json': jsonEncode(manualAdjustedFields),
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ValuationPropertySnapshot.fromMap(Map<String, Object?> map) {
    return ValuationPropertySnapshot(
      scenarioId: map['scenario_id']! as String,
      sourcePropertyId: map['source_property_id']! as String,
      propertyName: map['property_name']! as String,
      addressLine1: map['address_line1']! as String,
      addressLine2: map['address_line2'] as String?,
      zip: map['zip']! as String,
      city: map['city']! as String,
      country: map['country']! as String,
      propertyType: map['property_type']! as String,
      units: (map['units']! as num).toInt(),
      grossAreaSqm: (map['gross_area_sqm'] as num?)?.toDouble(),
      residentialAreaSqm: (map['residential_area_sqm'] as num?)?.toDouble(),
      commercialAreaSqm: (map['commercial_area_sqm'] as num?)?.toDouble(),
      yearBuilt: (map['year_built'] as num?)?.toInt(),
      purchasePrice: (map['purchase_price'] as num?)?.toDouble(),
      rentMonthlyTotal: (map['rent_monthly_total'] as num?)?.toDouble(),
      vacancyPercent: (map['vacancy_percent'] as num?)?.toDouble(),
      operatingCostsMonthly:
          (map['operating_costs_monthly'] as num?)?.toDouble(),
      documentStatus: map['document_status'] as String?,
      technicalInfo: map['technical_info'] as String?,
      autoImportedFields:
          _decodeStringList(map['auto_imported_fields_json'] as String?),
      manualAdjustedFields:
          _decodeStringList(map['manual_adjusted_fields_json'] as String?),
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class QuickScreeningRecord {
  const QuickScreeningRecord({
    required this.id,
    required this.title,
    this.sourceLabel,
    this.addressText,
    required this.propertyType,
    required this.units,
    required this.areaSqm,
    required this.purchasePrice,
    required this.rentMonthlyTotal,
    required this.vacancyPercent,
    required this.operatingCostsMonthly,
    this.linkedPropertyId,
    this.linkedScenarioId,
    required this.status,
    this.notes,
    this.acquisitionInputJson,
    this.acquisitionScenarioType,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? sourceLabel;
  final String? addressText;
  final String propertyType;
  final int units;
  final double areaSqm;
  final double purchasePrice;
  final double rentMonthlyTotal;
  final double vacancyPercent;
  final double operatingCostsMonthly;
  final String? linkedPropertyId;
  final String? linkedScenarioId;
  final String status;
  final String? notes;
  final String? acquisitionInputJson;
  final String? acquisitionScenarioType;
  final int createdAt;
  final int updatedAt;

  QuickScreeningRecord copyWith({
    String? linkedPropertyId,
    String? linkedScenarioId,
    String? status,
    int? updatedAt,
  }) {
    return QuickScreeningRecord(
      id: id,
      title: title,
      sourceLabel: sourceLabel,
      addressText: addressText,
      propertyType: propertyType,
      units: units,
      areaSqm: areaSqm,
      purchasePrice: purchasePrice,
      rentMonthlyTotal: rentMonthlyTotal,
      vacancyPercent: vacancyPercent,
      operatingCostsMonthly: operatingCostsMonthly,
      linkedPropertyId: linkedPropertyId ?? this.linkedPropertyId,
      linkedScenarioId: linkedScenarioId ?? this.linkedScenarioId,
      status: status ?? this.status,
      notes: notes,
      acquisitionInputJson: acquisitionInputJson,
      acquisitionScenarioType: acquisitionScenarioType,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'source_label': sourceLabel,
      'address_text': addressText,
      'property_type': propertyType,
      'units': units,
      'area_sqm': areaSqm,
      'purchase_price': purchasePrice,
      'rent_monthly_total': rentMonthlyTotal,
      'vacancy_percent': vacancyPercent,
      'operating_costs_monthly': operatingCostsMonthly,
      'linked_property_id': linkedPropertyId,
      'linked_scenario_id': linkedScenarioId,
      'status': status,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory QuickScreeningRecord.fromMap(Map<String, Object?> map) {
    return QuickScreeningRecord(
      id: map['id']! as String,
      title: map['title']! as String,
      sourceLabel: map['source_label'] as String?,
      addressText: map['address_text'] as String?,
      propertyType: map['property_type']! as String,
      units: ((map['units'] as num?) ?? 0).toInt(),
      areaSqm: ((map['area_sqm'] as num?) ?? 0).toDouble(),
      purchasePrice: ((map['purchase_price'] as num?) ?? 0).toDouble(),
      rentMonthlyTotal: ((map['rent_monthly_total'] as num?) ?? 0).toDouble(),
      vacancyPercent: ((map['vacancy_percent'] as num?) ?? 0).toDouble(),
      operatingCostsMonthly:
          ((map['operating_costs_monthly'] as num?) ?? 0).toDouble(),
      linkedPropertyId: map['linked_property_id'] as String?,
      linkedScenarioId: map['linked_scenario_id'] as String?,
      status: (map['status'] as String?) ?? 'draft',
      notes: map['notes'] as String?,
      acquisitionInputJson: map['acquisition_input_json'] as String?,
      acquisitionScenarioType: map['acquisition_scenario_type'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

List<String> _decodeStringList(String? value) {
  if (value == null || value.trim().isEmpty) {
    return const <String>[];
  }
  final decoded = jsonDecode(value);
  if (decoded is! List) {
    return const <String>[];
  }
  return decoded.whereType<String>().toList(growable: false);
}
