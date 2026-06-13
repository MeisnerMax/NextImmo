import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/inputs.dart';
import '../../core/models/property.dart';
import '../../core/models/settings.dart';
import '../../core/models/valuation.dart';

class ValuationDataRepo {
  ValuationDataRepo(this._db);

  final Database _db;

  Future<List<QuickScreeningRecord>> listQuickScreenings() async {
    final rows = await _db.query(
      'quick_screenings',
      orderBy: 'updated_at DESC',
      limit: 25,
    );
    return rows.map(QuickScreeningRecord.fromMap).toList(growable: false);
  }

  Future<QuickScreeningRecord> createQuickScreening({
    required String title,
    String? sourceLabel,
    String? addressText,
    required String propertyType,
    required int units,
    required double areaSqm,
    required double purchasePrice,
    required double rentMonthlyTotal,
    required double vacancyPercent,
    required double operatingCostsMonthly,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = QuickScreeningRecord(
      id: const Uuid().v4(),
      title: title,
      sourceLabel: _emptyToNull(sourceLabel),
      addressText: _emptyToNull(addressText),
      propertyType: propertyType,
      units: units,
      areaSqm: areaSqm,
      purchasePrice: purchasePrice,
      rentMonthlyTotal: rentMonthlyTotal,
      vacancyPercent: vacancyPercent,
      operatingCostsMonthly: operatingCostsMonthly,
      linkedPropertyId: null,
      linkedScenarioId: null,
      status: 'draft',
      notes: _emptyToNull(notes),
      createdAt: now,
      updatedAt: now,
    );

    await _db.insert(
      'quick_screenings',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return record;
  }

  Future<void> linkQuickScreening({
    required String quickScreeningId,
    required String propertyId,
    required String scenarioId,
  }) async {
    await _db.update(
      'quick_screenings',
      <String, Object?>{
        'linked_property_id': propertyId,
        'linked_scenario_id': scenarioId,
        'status': 'converted',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[quickScreeningId],
    );
  }

  ScenarioInputs inputsFromQuickScreening({
    required QuickScreeningRecord screening,
    required String scenarioId,
    required AppSettingsRecord settings,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ScenarioInputs.defaults(
      scenarioId: scenarioId,
      settings: settings,
    ).copyWith(
      purchasePrice: screening.purchasePrice,
      rentMonthlyTotal: screening.rentMonthlyTotal,
      grossAreaSqm: screening.areaSqm,
      lettableAreaSqm: screening.areaSqm,
      vacancyPercent: screening.vacancyPercent,
      otherExpensesMonthly: screening.operatingCostsMonthly,
      updatedAt: now,
    );
  }

  Future<ScenarioInputs> inputsFromProperty({
    required String propertyId,
    required String scenarioId,
    required AppSettingsRecord settings,
  }) async {
    final property = await _loadProperty(propertyId);
    final defaults = ScenarioInputs.defaults(
      scenarioId: scenarioId,
      settings: settings,
    );
    if (property == null) {
      return defaults;
    }

    final rent = await _latestRentMonthly(propertyId);
    final vacancy = await _latestVacancyPercent(propertyId);
    final costs = await _operatingCostsMonthly(propertyId);
    final grossArea = _grossArea(property);

    return defaults.copyWith(
      purchasePrice: property.purchasePrice ?? defaults.purchasePrice,
      rentMonthlyTotal: rent ?? defaults.rentMonthlyTotal,
      vacancyPercent: vacancy ?? defaults.vacancyPercent,
      otherExpensesMonthly: costs ?? defaults.otherExpensesMonthly,
      grossAreaSqm: grossArea ?? defaults.grossAreaSqm,
      lettableAreaSqm:
          (property.residentialArea ?? 0) + (property.commercialArea ?? 0),
      residentialAreaSqm:
          property.residentialArea ?? defaults.residentialAreaSqm,
      commercialAreaSqm:
          property.commercialArea ?? defaults.commercialAreaSqm,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<ValuationPropertySnapshot?> getPropertySnapshot(
    String scenarioId,
  ) async {
    final rows = await _db.query(
      'valuation_property_snapshots',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ValuationPropertySnapshot.fromMap(rows.first);
  }

  Future<void> createPropertySnapshot({
    required String scenarioId,
    required String propertyId,
  }) async {
    final property = await _loadProperty(propertyId);
    if (property == null) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final rent = await _latestRentMonthly(propertyId);
    final vacancy = await _latestVacancyPercent(propertyId);
    final costs = await _operatingCostsMonthly(propertyId);
    final documentStatus = await _documentStatus(propertyId);
    final technicalInfo = _technicalInfo(property);
    final snapshot = ValuationPropertySnapshot(
      scenarioId: scenarioId,
      sourcePropertyId: propertyId,
      propertyName: property.name,
      addressLine1: property.addressLine1,
      addressLine2: property.addressLine2,
      zip: property.zip,
      city: property.city,
      country: property.country,
      propertyType: property.propertyType,
      units: property.units,
      grossAreaSqm: _grossArea(property),
      residentialAreaSqm: property.residentialArea,
      commercialAreaSqm: property.commercialArea,
      yearBuilt: property.yearBuilt,
      purchasePrice: property.purchasePrice,
      rentMonthlyTotal: rent,
      vacancyPercent: vacancy,
      operatingCostsMonthly: costs,
      documentStatus: documentStatus,
      technicalInfo: technicalInfo,
      autoImportedFields: _autoImportedFields(
        property: property,
        rent: rent,
        vacancy: vacancy,
        costs: costs,
        documentStatus: documentStatus,
        technicalInfo: technicalInfo,
      ),
      manualAdjustedFields: const <String>[],
      createdAt: now,
      updatedAt: now,
    );

    await _db.insert(
      'valuation_property_snapshots',
      snapshot.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markManualAdjustments({
    required String scenarioId,
    required Iterable<String> fields,
  }) async {
    final normalized =
        fields.map((field) => field.trim()).where((field) => field.isNotEmpty);
    if (normalized.isEmpty) {
      return;
    }
    final snapshot = await getPropertySnapshot(scenarioId);
    if (snapshot == null) {
      return;
    }
    final merged = <String>{
      ...snapshot.manualAdjustedFields,
      ...normalized,
    }.toList()..sort();

    await _db.update(
      'valuation_property_snapshots',
      <String, Object?>{
        'manual_adjusted_fields_json': jsonEncode(merged),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'scenario_id = ?',
      whereArgs: <Object?>[scenarioId],
    );
  }

  Future<PropertyRecord?> _loadProperty(String propertyId) async {
    final rows = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[propertyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PropertyRecord.fromMap(rows.first);
  }

  Future<double?> _latestRentMonthly(String propertyId) async {
    final rentRoll = await _db.query(
      'rent_roll_snapshots',
      columns: const <String>['in_place_rent_monthly', 'gpr_monthly'],
      where: 'asset_property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'period_key DESC',
      limit: 1,
    );
    if (rentRoll.isNotEmpty) {
      final inPlace = (rentRoll.first['in_place_rent_monthly'] as num?)
          ?.toDouble();
      final gpr = (rentRoll.first['gpr_monthly'] as num?)?.toDouble();
      return inPlace ?? gpr;
    }

    final leaseRows = await _db.rawQuery(
      '''
      SELECT SUM(base_rent_monthly) AS rent
      FROM leases
      WHERE asset_property_id = ? AND status IN ('active', 'signed')
      ''',
      <Object?>[propertyId],
    );
    return (leaseRows.first['rent'] as num?)?.toDouble();
  }

  Future<double?> _latestVacancyPercent(String propertyId) async {
    final rows = await _db.query(
      'rent_roll_snapshots',
      columns: const <String>['occupancy_rate'],
      where: 'asset_property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'period_key DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final occupancy = (rows.first['occupancy_rate'] as num?)?.toDouble();
    if (occupancy == null) {
      return null;
    }
    return (1 - occupancy).clamp(0, 1).toDouble();
  }

  Future<double?> _operatingCostsMonthly(String propertyId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT
        SUM(COALESCE(monthly_amount, yearly_amount / 12.0, 0)) AS costs
      FROM asset_operating_costs
      WHERE property_id = ? AND canceled = 0
      ''',
      <Object?>[propertyId],
    );
    return (rows.first['costs'] as num?)?.toDouble();
  }

  Future<String?> _documentStatus(String propertyId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM documents
      WHERE entity_type IN ('property', 'asset_property') AND entity_id = ?
      ''',
      <Object?>[propertyId],
    );
    final count = ((rows.first['count'] as num?) ?? 0).toInt();
    return count == 0 ? 'Keine Dokumente' : '$count Dokumente vorhanden';
  }

  double? _grossArea(PropertyRecord property) {
    final detailed =
        (property.residentialArea ?? 0) + (property.commercialArea ?? 0);
    if (detailed > 0) {
      return detailed;
    }
    if (property.sqft != null && property.sqft! > 0) {
      return property.sqft! * 0.09290304;
    }
    return null;
  }

  String? _technicalInfo(PropertyRecord property) {
    final parts = <String>[
      if (_hasText(property.energyCertificate))
        'Energieausweis: ${property.energyCertificate}',
      if (_hasText(property.insuranceDetails))
        'Versicherung: ${property.insuranceDetails}',
      if (_hasText(property.parcel)) 'Flurstueck: ${property.parcel}',
      if (_hasText(property.landRegistryDetails))
        'Grundbuch: ${property.landRegistryDetails}',
    ];
    return parts.isEmpty ? null : parts.join(' | ');
  }

  List<String> _autoImportedFields({
    required PropertyRecord property,
    required double? rent,
    required double? vacancy,
    required double? costs,
    required String? documentStatus,
    required String? technicalInfo,
  }) {
    final fields = <String>[
      'propertyName',
      'addressLine1',
      'zip',
      'city',
      'country',
      'propertyType',
      'units',
      if (property.yearBuilt != null) 'yearBuilt',
      if (_grossArea(property) != null) 'grossAreaSqm',
      if (property.residentialArea != null) 'residentialAreaSqm',
      if (property.commercialArea != null) 'commercialAreaSqm',
      if (property.purchasePrice != null) 'purchasePrice',
      if (rent != null) 'rentMonthlyTotal',
      if (vacancy != null) 'vacancyPercent',
      if (costs != null) 'otherExpensesMonthly',
      if (documentStatus != null) 'documentStatus',
      if (technicalInfo != null) 'technicalInfo',
    ];
    fields.sort();
    return fields;
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
