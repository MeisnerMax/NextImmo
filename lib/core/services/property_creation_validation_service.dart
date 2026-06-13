import '../models/property.dart';
import '../models/property_creation.dart';

class PropertyCreationValidationService {
  const PropertyCreationValidationService();

  PropertyCreationAssessment assess(
    PropertyCreationDraft draft, {
    List<PropertyRecord> existingProperties = const <PropertyRecord>[],
  }) {
    final metrics = PropertyCreationCalculationsService.calculate(draft);
    final missing = <String>[];
    final recommended = <String>[];
    final critical = <String>[];

    if (draft.propertyType.trim().isEmpty) {
      missing.add('Objektart fehlt.');
    }
    if (draft.objectName.trim().isEmpty) {
      missing.add('Objektname fehlt.');
    }
    if (draft.internalId.trim().isEmpty) {
      missing.add('Interne Objekt-ID fehlt.');
    } else if (_hasDuplicateInternalId(draft, existingProperties)) {
      missing.add('Interne Objekt-ID ist bereits vergeben.');
    }
    if (draft.status.trim().isEmpty) {
      missing.add('Objektstatus fehlt.');
    }
    if (draft.addressLine1.trim().isEmpty ||
        draft.zip.trim().isEmpty ||
        draft.city.trim().isEmpty ||
        draft.country.trim().isEmpty) {
      missing.add('Adresse ist unvollstaendig.');
    }

    if (draft.totalArea == null) {
      recommended.add('Gesamtflaeche fehlt.');
    }
    if (draft.units.isEmpty) {
      recommended.add('Keine Einheiten erfasst.');
    }
    if (draft.monthlyActualRent == null && draft.annualColdRent == null) {
      recommended.add('Mietdaten fehlen.');
    }
    if (draft.isAcquisitionCase && draft.purchasePrice == null) {
      recommended.add('Kaufpreis fehlt.');
    }
    if (!draft.energyCertificateAvailable) {
      recommended.add('Energieausweis fehlt oder wurde nicht bestaetigt.');
    }
    if (!draft.landRegisterAvailable) {
      recommended.add('Grundbuchinformationen fehlen.');
    }
    if (draft.hasLoan && draft.loanAmount == null) {
      recommended.add('Finanzierung ist markiert, aber Darlehensbetrag fehlt.');
    }

    final unitArea = _sumNullable(draft.units.map((unit) => unit.area));
    if (draft.totalArea != null &&
        unitArea != null &&
        (draft.totalArea! - unitArea).abs() > 1) {
      critical.add('Miet-/Einheitenflaeche weicht von der Gesamtflaeche ab.');
    }
    if ((draft.monumentProtection || draft.legalMonumentProtection) &&
        !_documentAvailable(draft, 'denkmalauskunft')) {
      critical.add('Denkmalschutz markiert, aber keine Denkmalauskunft hinterlegt.');
    }
    if (draft.knownBuildingCharges && !_documentAvailable(draft, 'baulastenverzeichnis')) {
      critical.add('Baulasten markiert, aber kein Baulastenverzeichnis hinterlegt.');
    }
    if (draft.legalDisputes.trim().isNotEmpty && !draft.criticalRisksConfirmed) {
      critical.add('Rechtsstreitigkeiten muessen vor dem Speichern bewusst bestaetigt werden.');
    }
    if (draft.renovationBudget != null && draft.renovationNeed.trim().isEmpty) {
      recommended.add('Renovierungsbudget vorhanden, aber Sanierungsbedarf nicht beschrieben.');
    }

    final qualityItems = _qualityItems(draft, critical);
    final score = PropertyCreationCalculationsService.dataQualityScore(qualityItems);
    final dataQualityMetrics = PropertyCreationMetrics(
      purchasePricePerSqm: metrics.purchasePricePerSqm,
      totalArea: metrics.totalArea,
      leasedArea: metrics.leasedArea,
      vacantArea: metrics.vacantArea,
      vacancyRate: metrics.vacancyRate,
      actualRentPerSqm: metrics.actualRentPerSqm,
      targetRentPerSqm: metrics.targetRentPerSqm,
      annualActualRent: metrics.annualActualRent,
      annualTargetRent: metrics.annualTargetRent,
      rentUpside: metrics.rentUpside,
      purchaseFactorActual: metrics.purchaseFactorActual,
      purchaseFactorTarget: metrics.purchaseFactorTarget,
      acquisitionCosts: metrics.acquisitionCosts,
      acquisitionCostRatio: metrics.acquisitionCostRatio,
      totalInvestment: metrics.totalInvestment,
      loanToValue: metrics.loanToValue,
      equityRatio: metrics.equityRatio,
      conditionScore: metrics.conditionScore,
      dataQualityScore: score,
      dataQualityStatus: PropertyCreationCalculationsService.dataQualityStatus(score),
    );

    return PropertyCreationAssessment(
      metrics: dataQualityMetrics,
      missingRequired: missing,
      recommended: recommended,
      criticalWarnings: critical,
      qualityItems: qualityItems,
      stepStates: _stepStates(draft, missing, recommended, critical),
    );
  }

  bool _hasDuplicateInternalId(
    PropertyCreationDraft draft,
    List<PropertyRecord> existingProperties,
  ) {
    final id = draft.internalId.trim().toLowerCase();
    return existingProperties.any((property) => property.id.toLowerCase() == id);
  }

  Map<int, PropertyCreationStepState> _stepStates(
    PropertyCreationDraft draft,
    List<String> missing,
    List<String> recommended,
    List<String> critical,
  ) {
    final states = <int, PropertyCreationStepState>{};
    states[0] = draft.propertyType.isEmpty
        ? PropertyCreationStepState.incomplete
        : PropertyCreationStepState.complete;
    states[1] = missing.any((item) =>
            item.contains('Objektname') ||
            item.contains('Objekt-ID') ||
            item.contains('Objektstatus'))
        ? PropertyCreationStepState.incomplete
        : PropertyCreationStepState.complete;
    states[2] = missing.any((item) => item.contains('Adresse'))
        ? PropertyCreationStepState.incomplete
        : PropertyCreationStepState.complete;
    states[3] = critical.any((item) => item.contains('Flaeche'))
        ? PropertyCreationStepState.warning
        : (draft.totalArea == null && draft.units.isEmpty
            ? PropertyCreationStepState.incomplete
            : PropertyCreationStepState.complete);
    states[4] = draft.monthlyActualRent == null &&
            draft.annualColdRent == null &&
            draft.tenants.isEmpty
        ? PropertyCreationStepState.incomplete
        : PropertyCreationStepState.complete;
    states[5] = draft.isAcquisitionCase && draft.purchasePrice == null
        ? PropertyCreationStepState.incomplete
        : PropertyCreationStepState.complete;
    states[6] = draft.hasLoan && draft.loanAmount == null
        ? PropertyCreationStepState.warning
        : PropertyCreationStepState.complete;
    states[7] = draft.yearBuilt == null &&
            draft.energyClass.trim().isEmpty &&
            draft.renovationNeed.trim().isEmpty
        ? PropertyCreationStepState.incomplete
        : PropertyCreationStepState.complete;
    states[8] = critical.any((item) =>
            item.contains('Rechtsstreitigkeiten') ||
            item.contains('Baulasten') ||
            item.contains('Denkmalschutz'))
        ? PropertyCreationStepState.warning
        : PropertyCreationStepState.complete;
    states[9] = draft.documents.any((doc) => doc.status != 'fehlt')
        ? PropertyCreationStepState.complete
        : PropertyCreationStepState.incomplete;
    states[10] = missing.isEmpty
        ? PropertyCreationStepState.complete
        : PropertyCreationStepState.incomplete;
    states[11] = PropertyCreationStepState.untouched;
    return states;
  }

  List<PropertyCreationQualityItem> _qualityItems(
    PropertyCreationDraft draft,
    List<String> critical,
  ) {
    return <PropertyCreationQualityItem>[
      PropertyCreationQualityItem(
        label: 'Basisdaten vollstaendig',
        complete: draft.objectName.trim().isNotEmpty &&
            draft.internalId.trim().isNotEmpty &&
            draft.status.trim().isNotEmpty,
        weight: 12,
      ),
      PropertyCreationQualityItem(
        label: 'Adresse vollstaendig',
        complete: draft.addressLine1.trim().isNotEmpty &&
            draft.zip.trim().isNotEmpty &&
            draft.city.trim().isNotEmpty &&
            draft.country.trim().isNotEmpty,
        weight: 12,
      ),
      PropertyCreationQualityItem(
        label: 'Flaechen plausibel',
        complete: draft.totalArea != null &&
            !critical.any((item) => item.contains('Flaeche')),
        weight: 10,
      ),
      PropertyCreationQualityItem(
        label: 'Einheiten vorhanden',
        complete: draft.units.isNotEmpty,
        weight: 10,
      ),
      PropertyCreationQualityItem(
        label: 'Mietdaten vorhanden',
        complete: draft.monthlyActualRent != null ||
            draft.annualColdRent != null ||
            draft.tenants.isNotEmpty,
        weight: 10,
      ),
      PropertyCreationQualityItem(
        label: 'Kauf- oder Bestandsdaten vorhanden',
        complete: draft.purchasePrice != null ||
            draft.originalPurchasePrice != null ||
            draft.bookValue != null ||
            draft.marketValue != null,
        weight: 10,
      ),
      PropertyCreationQualityItem(
        label: 'Technische Daten vorhanden',
        complete: draft.yearBuilt != null ||
            draft.energyClass.trim().isNotEmpty ||
            draft.renovationNeed.trim().isNotEmpty,
        weight: 10,
      ),
      PropertyCreationQualityItem(
        label: 'Rechtliche Daten vorhanden',
        complete: draft.ownerCompany.trim().isNotEmpty ||
            draft.landRegisterAvailable ||
            draft.parcel.trim().isNotEmpty,
        weight: 10,
      ),
      PropertyCreationQualityItem(
        label: 'Dokumentenstatus geprueft',
        complete: draft.documents.any((doc) => doc.status != 'fehlt'),
        weight: 8,
      ),
      PropertyCreationQualityItem(
        label: 'Kritische Risiken bestaetigt',
        complete: critical.isEmpty || draft.criticalRisksConfirmed,
        weight: 8,
      ),
    ];
  }

  bool _documentAvailable(PropertyCreationDraft draft, String key) {
    return draft.documents.any(
      (doc) => doc.key == key && (doc.status == 'vorhanden' || doc.uploadPath.trim().isNotEmpty),
    );
  }

  double? _sumNullable(Iterable<double?> values) {
    var hasValue = false;
    var sum = 0.0;
    for (final value in values) {
      if (value == null) {
        continue;
      }
      hasValue = true;
      sum += value;
    }
    return hasValue ? sum : null;
  }
}

class PropertyCreationCalculationsService {
  const PropertyCreationCalculationsService._();

  static PropertyCreationMetrics calculate(PropertyCreationDraft draft) {
    final totalArea = draft.totalArea ?? _sum(draft.units.map((unit) => unit.area));
    final leasedArea = draft.leasedArea ??
        _sum(draft.units
            .where((unit) => unit.status == 'occupied')
            .map((unit) => unit.area));
    final vacantArea = draft.vacantArea ??
        (totalArea != null && leasedArea != null ? totalArea - leasedArea : null);
    final annualActualRent = draft.annualColdRent ?? _multiply(draft.monthlyActualRent, 12);
    final annualTargetRent = _multiply(draft.targetRent, 12);
    final acquisitionCosts = _sum(<double?>[
      draft.propertyTransferTax,
      draft.notaryCosts,
      draft.landRegistryCosts,
      draft.brokerFee,
      draft.otherAcquisitionCosts,
    ]);
    final price = draft.purchasePrice ?? draft.offerPrice ?? draft.originalPurchasePrice;
    final totalInvestment = price == null && acquisitionCosts == null
        ? null
        : (price ?? 0) + (acquisitionCosts ?? 0);
    final conditionScore = _conditionScore(draft);
    final emptyQuality = dataQualityScore(const <PropertyCreationQualityItem>[]);

    return PropertyCreationMetrics(
      purchasePricePerSqm: _divide(price, totalArea),
      totalArea: totalArea,
      leasedArea: leasedArea,
      vacantArea: vacantArea,
      vacancyRate: draft.vacancyPercent == null
          ? _divide(vacantArea, totalArea)
          : draft.vacancyPercent! / 100,
      actualRentPerSqm: draft.averageRentPerSqm ?? _divide(draft.monthlyActualRent, leasedArea ?? totalArea),
      targetRentPerSqm: draft.marketRentPerSqm ?? _divide(draft.targetRent, totalArea),
      annualActualRent: annualActualRent,
      annualTargetRent: annualTargetRent,
      rentUpside: annualActualRent == null || annualTargetRent == null
          ? null
          : annualTargetRent - annualActualRent,
      purchaseFactorActual: _divide(price, annualActualRent),
      purchaseFactorTarget: _divide(price, annualTargetRent),
      acquisitionCosts: acquisitionCosts,
      acquisitionCostRatio: _divide(acquisitionCosts, price),
      totalInvestment: totalInvestment,
      loanToValue: _divide(draft.loanAmount ?? draft.remainingDebt, draft.marketValue ?? price),
      equityRatio: _divide(draft.equity, totalInvestment),
      conditionScore: conditionScore,
      dataQualityScore: emptyQuality,
      dataQualityStatus: dataQualityStatus(emptyQuality),
    );
  }

  static int dataQualityScore(List<PropertyCreationQualityItem> items) {
    if (items.isEmpty) {
      return 0;
    }
    final totalWeight = items.fold<int>(0, (sum, item) => sum + item.weight);
    if (totalWeight == 0) {
      return 0;
    }
    final achieved = items
        .where((item) => item.complete)
        .fold<int>(0, (sum, item) => sum + item.weight);
    return ((achieved / totalWeight) * 100).round().clamp(0, 100);
  }

  static String dataQualityStatus(int score) {
    if (score >= 90) {
      return 'sehr gut';
    }
    if (score >= 75) {
      return 'gut';
    }
    if (score >= 55) {
      return 'mittel';
    }
    if (score >= 35) {
      return 'unvollstaendig';
    }
    return 'kritisch';
  }

  static int _conditionScore(PropertyCreationDraft draft) {
    final values = <String>[
      draft.roofCondition,
      draft.facadeCondition,
      draft.windowsCondition,
      draft.electricCondition,
      draft.pipesCondition,
      draft.fireSafetyStatus,
      draft.accessibility,
    ];
    var total = 0;
    var count = 0;
    for (final value in values) {
      final score = switch (value) {
        'very_good' => 100,
        'good' => 80,
        'medium' => 60,
        'poor' => 35,
        'critical' => 10,
        _ => null,
      };
      if (score != null) {
        total += score;
        count++;
      }
    }
    if (draft.moistureDamage) {
      total -= 10;
    }
    if (count == 0) {
      return 0;
    }
    return (total / count).round().clamp(0, 100);
  }

  static double? _sum(Iterable<double?> values) {
    var hasValue = false;
    var sum = 0.0;
    for (final value in values) {
      if (value == null) {
        continue;
      }
      hasValue = true;
      sum += value;
    }
    return hasValue ? sum : null;
  }

  static double? _multiply(double? value, double factor) {
    if (value == null) {
      return null;
    }
    return value * factor;
  }

  static double? _divide(double? numerator, double? denominator) {
    if (numerator == null || denominator == null || denominator == 0) {
      return null;
    }
    return numerator / denominator;
  }
}
