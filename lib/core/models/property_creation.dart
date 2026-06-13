class PropertyCreationDraft {
  PropertyCreationDraft({
    String? internalId,
    this.country = 'DE',
  }) : internalId = internalId ?? _suggestInternalId();

  String propertyType = 'residential';
  String creationReason = 'bestand';
  String creationMode = 'complete';

  String objectName = '';
  String internalId;
  String externalReference = '';
  String status = 'in_pruefung';
  String shortDescription = '';
  String assetManager = '';
  String priority = 'normal';
  String tags = '';

  String street = '';
  String houseNumber = '';
  String zip = '';
  String city = '';
  String federalState = '';
  String country;
  String locationQuality = 'nicht_bewertet';
  String microLocation = '';
  String macroLocation = '';
  String transit = '';
  String parking = '';
  String environmentNotes = '';
  String locationRisks = '';
  String locationPotentials = '';

  double? totalArea;
  double? residentialArea;
  double? commercialArea;
  double? usableArea;
  double? landArea;
  int? residentialUnits;
  int? commercialUnits;
  int? parkingSpots;
  int? garages;
  double? basementArea;
  double? vacantArea;
  double? leasedArea;
  String expansionPotential = '';
  String densificationPotential = '';
  final List<PropertyCreationUnitDraft> units = <PropertyCreationUnitDraft>[];

  String mainUse = '';
  String usageMix = '';
  double? annualColdRent;
  double? monthlyActualRent;
  double? targetRent;
  double? vacancyPercent;
  double? averageRentPerSqm;
  double? marketRentPerSqm;
  String leaseContractStatus = '';
  bool indexedRent = false;
  bool steppedRent = false;
  bool rentArrears = false;
  String specialLeaseTerms = '';
  bool captureTenantsNow = false;
  final List<PropertyCreationTenantDraft> tenants =
      <PropertyCreationTenantDraft>[];

  double? offerPrice;
  double? purchasePrice;
  int? purchaseDate;
  int? notaryDate;
  String seller = '';
  String broker = '';
  double? propertyTransferTax;
  double? notaryCosts;
  double? landRegistryCosts;
  double? brokerFee;
  double? otherAcquisitionCosts;
  int? transferBenefitsDate;
  double? originalPurchasePrice;
  int? originalPurchaseDate;
  double? bookValue;
  double? marketValue;
  String lastInternalValuation = '';
  int? valuationDate;
  String historicNotes = '';

  bool hasLoan = false;
  double? loanAmount;
  double? equity;
  double? interestRate;
  double? amortizationRate;
  String fixedInterestPeriod = '';
  int? termYears;
  double? monthlyRate;
  double? annualDebtService;
  String bank = '';
  String loanNumber = '';
  double? remainingDebt;
  bool specialRepayment = false;
  String financingNotes = '';

  int? yearBuilt;
  int? lastRenovationYear;
  bool energyCertificateAvailable = false;
  String energyClass = '';
  String heatingType = '';
  String roofCondition = 'unknown';
  String facadeCondition = 'unknown';
  String windowsCondition = 'unknown';
  String electricCondition = 'unknown';
  String pipesCondition = 'unknown';
  String fireSafetyStatus = 'unknown';
  String accessibility = 'unknown';
  bool moistureDamage = false;
  bool monumentProtection = false;
  String renovationNeed = '';
  double? renovationBudget;
  String technicalRisks = '';
  String technicalNotes = '';

  String ownerCompany = '';
  bool landRegisterAvailable = false;
  String parcel = '';
  bool knownBuildingCharges = false;
  bool legalMonumentProtection = false;
  bool declarationOfDivisionAvailable = false;
  bool weg = false;
  String easements = '';
  String legalDisputes = '';
  String insurances = '';
  String propertyManagement = '';
  String internalContact = '';
  String externalContact = '';
  String taxNotes = '';
  String organisationalNotes = '';
  bool criticalRisksConfirmed = false;

  final List<PropertyCreationDocumentDraft> documents =
      defaultPropertyCreationDocuments();

  String get addressLine1 {
    final parts = <String>[street.trim(), houseNumber.trim()]
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.join(' ');
  }

  int get effectiveUnitCount {
    final explicit = (residentialUnits ?? 0) + (commercialUnits ?? 0);
    if (explicit > 0) {
      return explicit;
    }
    if (units.isNotEmpty) {
      return units.length;
    }
    return 1;
  }

  bool get isAcquisitionCase {
    return creationReason == 'ankauf_pruefen' || creationReason == 'neu_gekauft';
  }

  static String _suggestInternalId() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return 'NX-${now.year}$month$day';
  }
}

class PropertyCreationUnitDraft {
  PropertyCreationUnitDraft({
    this.unitCode = '',
    this.useType = 'Wohnen',
    this.floor = '',
    this.area,
    this.rooms,
    this.status = 'vacant',
    this.coldRent,
    this.serviceCharge,
    this.parkingAssignment = '',
    this.notes = '',
  });

  String unitCode;
  String useType;
  String floor;
  double? area;
  double? rooms;
  String status;
  double? coldRent;
  double? serviceCharge;
  String parkingAssignment;
  String notes;

  PropertyCreationUnitDraft duplicate() {
    return PropertyCreationUnitDraft(
      unitCode: unitCode.isEmpty ? '' : '$unitCode Kopie',
      useType: useType,
      floor: floor,
      area: area,
      rooms: rooms,
      status: status,
      coldRent: coldRent,
      serviceCharge: serviceCharge,
      parkingAssignment: parkingAssignment,
      notes: notes,
    );
  }
}

class PropertyCreationTenantDraft {
  PropertyCreationTenantDraft({
    this.tenantName = '',
    this.unitCode = '',
    this.leaseStart,
    this.leaseEnd,
    this.noticePeriod = '',
    this.coldRent,
    this.serviceCharges,
    this.deposit,
    this.paymentStatus = 'unknown',
    this.notes = '',
  });

  String tenantName;
  String unitCode;
  int? leaseStart;
  int? leaseEnd;
  String noticePeriod;
  double? coldRent;
  double? serviceCharges;
  double? deposit;
  String paymentStatus;
  String notes;
}

class PropertyCreationDocumentDraft {
  PropertyCreationDocumentDraft({
    required this.key,
    required this.label,
    this.status = 'fehlt',
    this.uploadPath = '',
    this.note = '',
    this.dueDate,
    this.owner = '',
  });

  final String key;
  final String label;
  String status;
  String uploadPath;
  String note;
  int? dueDate;
  String owner;
}

class PropertyCreationMetrics {
  const PropertyCreationMetrics({
    this.purchasePricePerSqm,
    this.totalArea,
    this.leasedArea,
    this.vacantArea,
    this.vacancyRate,
    this.actualRentPerSqm,
    this.targetRentPerSqm,
    this.annualActualRent,
    this.annualTargetRent,
    this.rentUpside,
    this.purchaseFactorActual,
    this.purchaseFactorTarget,
    this.acquisitionCosts,
    this.acquisitionCostRatio,
    this.totalInvestment,
    this.loanToValue,
    this.equityRatio,
    required this.conditionScore,
    required this.dataQualityScore,
    required this.dataQualityStatus,
  });

  final double? purchasePricePerSqm;
  final double? totalArea;
  final double? leasedArea;
  final double? vacantArea;
  final double? vacancyRate;
  final double? actualRentPerSqm;
  final double? targetRentPerSqm;
  final double? annualActualRent;
  final double? annualTargetRent;
  final double? rentUpside;
  final double? purchaseFactorActual;
  final double? purchaseFactorTarget;
  final double? acquisitionCosts;
  final double? acquisitionCostRatio;
  final double? totalInvestment;
  final double? loanToValue;
  final double? equityRatio;
  final int conditionScore;
  final int dataQualityScore;
  final String dataQualityStatus;
}

class PropertyCreationAssessment {
  const PropertyCreationAssessment({
    required this.metrics,
    required this.missingRequired,
    required this.recommended,
    required this.criticalWarnings,
    required this.qualityItems,
    required this.stepStates,
    required this.criticalRisksConfirmed,
  });

  final PropertyCreationMetrics metrics;
  final List<String> missingRequired;
  final List<String> recommended;
  final List<String> criticalWarnings;
  final List<PropertyCreationQualityItem> qualityItems;
  final Map<int, PropertyCreationStepState> stepStates;
  final bool criticalRisksConfirmed;

  bool get canSave =>
      missingRequired.isEmpty &&
      (criticalWarnings.isEmpty || criticalRisksConfirmed);
}

class PropertyCreationQualityItem {
  const PropertyCreationQualityItem({
    required this.label,
    required this.complete,
    required this.weight,
    this.note,
  });

  final String label;
  final bool complete;
  final int weight;
  final String? note;
}

enum PropertyCreationStepState { untouched, complete, incomplete, warning }

List<PropertyCreationDocumentDraft> defaultPropertyCreationDocuments() {
  const labels = <String, String>{
    'expose': 'Expose',
    'grundbuchauszug': 'Grundbuchauszug',
    'flurkarte': 'Flurkarte',
    'energieausweis': 'Energieausweis',
    'mieterliste': 'Mieterliste',
    'mietvertraege': 'Mietvertraege',
    'nebenkostenabrechnungen': 'Nebenkostenabrechnungen',
    'betriebskostenuebersicht': 'Betriebskostenuebersicht',
    'versicherungsunterlagen': 'Versicherungsunterlagen',
    'bauplaene': 'Bauplaene',
    'wohnflaechenberechnung': 'Wohnflaechenberechnung',
    'teilungserklaerung': 'Teilungserklaerung',
    'baulastenverzeichnis': 'Baulastenverzeichnis',
    'denkmalauskunft': 'Denkmalliste oder Denkmalauskunft',
    'sanierungsangebote': 'Sanierungsangebote',
    'gutachten': 'Gutachten',
    'fotos': 'Fotos',
    'kaufvertragsentwurf': 'Kaufvertragsentwurf',
    'finanzierungsunterlagen': 'Finanzierungsunterlagen',
    'sonstige': 'Sonstige Dokumente',
  };
  return labels.entries
      .map((entry) => PropertyCreationDocumentDraft(
            key: entry.key,
            label: entry.value,
          ))
      .toList(growable: true);
}
