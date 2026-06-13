import 'package:flutter/material.dart';

import '../../../core/models/property.dart';
import '../../../core/models/property_creation.dart';
import '../../../core/services/property_creation_validation_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_parse.dart';

class PropertyCreationWorkflowScreen extends StatefulWidget {
  const PropertyCreationWorkflowScreen({
    super.key,
    required this.existingProperties,
    required this.onCreateProperty,
  });

  final List<PropertyRecord> existingProperties;
  final Future<PropertyRecord?> Function(
    PropertyCreationDraft draft,
    PropertyCreationAssessment assessment,
  )
  onCreateProperty;

  @override
  State<PropertyCreationWorkflowScreen> createState() =>
      _PropertyCreationWorkflowScreenState();
}

class _PropertyCreationWorkflowScreenState
    extends State<PropertyCreationWorkflowScreen> {
  static const _validation = PropertyCreationValidationService();
  late final PropertyCreationDraft _draft;
  int _step = 0;
  bool _saving = false;
  PropertyRecord? _createdProperty;

  @override
  void initState() {
    super.initState();
    _draft = PropertyCreationDraft(
      internalId: _suggestNextInternalId(widget.existingProperties),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assessment = _validation.assess(
      _draft,
      existingProperties: widget.existingProperties,
    );
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Objekt anlegen'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : () => Navigator.of(context).pop(null),
            icon: const Icon(Icons.close),
            label: const Text('Schliessen'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 310,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.semanticColors.surfaceAlt,
                border: Border(
                  right: BorderSide(color: context.semanticColors.border),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.component),
                children: [
                  _QualityPanel(assessment: assessment),
                  const SizedBox(height: AppSpacing.component),
                  for (var i = 0; i < _steps.length; i++)
                    _StepNavTile(
                      index: i,
                      label: _steps[i],
                      selected: i == _step,
                      state:
                          assessment.stepStates[i] ??
                          PropertyCreationStepState.untouched,
                      onTap: _createdProperty == null
                          ? () => setState(() => _step = i)
                          : null,
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.section),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _steps[_step],
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _stepSubtitles[_step],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: context.semanticColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.section),
                          _buildStep(context, assessment),
                        ],
                      ),
                    ),
                  ),
                ),
                _FooterBar(
                  currentStep: _step,
                  totalSteps: _steps.length,
                  canSave: assessment.canSave,
                  saving: _saving,
                  created: _createdProperty != null,
                  onBack: _step == 0 || _saving
                      ? null
                      : () => setState(() => _step--),
                  onNext: _step >= _steps.length - 1 || _saving
                      ? null
                      : () => setState(() => _step++),
                  onSummary: _saving ? null : () => setState(() => _step = 10),
                  onSave: _saving || _createdProperty != null
                      ? null
                      : () => _save(assessment),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(
    BuildContext context,
    PropertyCreationAssessment assessment,
  ) {
    return switch (_step) {
      0 => _buildEntryStep(context),
      1 => _buildBaseStep(context),
      2 => _buildAddressStep(context),
      3 => _buildAreasStep(context, assessment),
      4 => _buildUsageStep(context, assessment),
      5 => _buildPurchaseStep(context, assessment),
      6 => _buildFinancingStep(context, assessment),
      7 => _buildTechnicalStep(context, assessment),
      8 => _buildLegalStep(context),
      9 => _buildDocumentsStep(context),
      10 => _buildSummaryStep(context, assessment),
      _ => _buildSaveStep(context, assessment),
    };
  }

  Widget _buildEntryStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          title: 'Objektart',
          child: _OptionGrid(
            options: const [
              _OptionSpec('residential', 'Wohnimmobilie', Icons.apartment, 'Mehrfamilienhaus, Wohnung oder Wohnportfolio.'),
              _OptionSpec('commercial', 'Gewerbeimmobilie', Icons.business_outlined, 'Buero, Retail, Logistik oder sonstige Gewerbeflaechen.'),
              _OptionSpec('mixed_use', 'Mischobjekt', Icons.domain_add_outlined, 'Kombinierte Wohn- und Gewerbenutzung.'),
              _OptionSpec('hotel', 'Hotel', Icons.hotel_outlined, 'Hotel- oder Beherbergungsbetrieb.'),
              _OptionSpec('land', 'Grundstueck', Icons.landscape_outlined, 'Unbebautes oder entwickelbares Grundstueck.'),
              _OptionSpec('renovation', 'Sanierungsobjekt', Icons.construction_outlined, 'Objekt mit erkennbarem Sanierungsfokus.'),
              _OptionSpec('development', 'Projektentwicklung', Icons.architecture_outlined, 'Neubau- oder Entwicklungsprojekt.'),
              _OptionSpec('other', 'Sonstiges', Icons.home_work_outlined, 'Spezialfall ausserhalb der Standardkategorien.'),
            ],
            selected: _draft.propertyType,
            onSelected: (value) => setState(() => _draft.propertyType = value),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _Section(
          title: 'Anlagegrund und Bearbeitungsmodus',
          child: _twoColumnGrid([
            _dropdown(
              label: 'Anlagegrund',
              value: _draft.creationReason,
              items: const {
                'bestand': 'Bestand erfassen',
                'ankauf_pruefen': 'Ankauf pruefen',
                'neu_gekauft': 'Neu gekauft',
                'sanierung_planen': 'Sanierung planen',
                'verkauf_vorbereiten': 'Verkauf vorbereiten',
                'datenobjekt': 'Reines Datenobjekt',
              },
              onChanged: (value) => _draft.creationReason = value,
            ),
            _dropdown(
              label: 'Bearbeitungsmodus',
              value: _draft.creationMode,
              items: const {
                'quick': 'Schnell anlegen',
                'complete': 'Vollstaendig anlegen',
                'later': 'Spaeter vervollstaendigen',
              },
              onChanged: (value) => _draft.creationMode = value,
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildBaseStep(BuildContext context) {
    return _Section(
      title: 'Basisdaten',
      child: _twoColumnGrid([
        _text('Objektname *', _draft.objectName, (v) => _draft.objectName = v),
        _text('Interne Objekt-ID *', _draft.internalId, (v) => _draft.internalId = v),
        _text('Externe Referenznummer', _draft.externalReference, (v) => _draft.externalReference = v),
        _dropdown(
          label: 'Objektstatus *',
          value: _draft.status,
          items: const {
            'aktiv': 'Aktiv',
            'in_pruefung': 'In Pruefung',
            'gekauft': 'Gekauft',
            'in_sanierung': 'In Sanierung',
            'vermietet': 'Vermietet',
            'teilweise_leerstehend': 'Teilweise leerstehend',
            'verkauft': 'Verkauft',
            'archiviert': 'Archiviert',
          },
          onChanged: (value) => _draft.status = value,
        ),
        _text('Zustaendiger Asset Manager', _draft.assetManager, (v) => _draft.assetManager = v),
        _dropdown(
          label: 'Prioritaet',
          value: _draft.priority,
          items: const {
            'niedrig': 'Niedrig',
            'normal': 'Normal',
            'hoch': 'Hoch',
            'kritisch': 'Kritisch',
          },
          onChanged: (value) => _draft.priority = value,
        ),
        _text('Tags oder Kategorien', _draft.tags, (v) => _draft.tags = v),
        _text('Kurzbeschreibung', _draft.shortDescription, (v) => _draft.shortDescription = v, maxLines: 4),
      ]),
    );
  }

  Widget _buildAddressStep(BuildContext context) {
    return Column(
      children: [
        _Section(
          title: 'Adresse',
          child: _twoColumnGrid([
            _text('Strasse *', _draft.street, (v) => _draft.street = v),
            _text('Hausnummer *', _draft.houseNumber, (v) => _draft.houseNumber = v),
            _text('PLZ *', _draft.zip, (v) => _draft.zip = v),
            _text('Ort *', _draft.city, (v) => _draft.city = v),
            _text('Bundesland', _draft.federalState, (v) => _draft.federalState = v),
            _text('Land *', _draft.country, (v) => _draft.country = v),
          ]),
        ),
        const SizedBox(height: AppSpacing.component),
        _Section(
          title: 'Lage',
          child: _twoColumnGrid([
            _dropdown(
              label: 'Lagequalitaet',
              value: _draft.locationQuality,
              items: const {
                'a': 'A-Lage',
                'b': 'B-Lage',
                'c': 'C-Lage',
                'd': 'D-Lage',
                'nicht_bewertet': 'Nicht bewertet',
              },
              onChanged: (value) => _draft.locationQuality = value,
            ),
            _text('Mikrostandort', _draft.microLocation, (v) => _draft.microLocation = v),
            _text('Makrostandort', _draft.macroLocation, (v) => _draft.macroLocation = v),
            _text('OePNV-Anbindung', _draft.transit, (v) => _draft.transit = v),
            _text('Parkmoeglichkeiten', _draft.parking, (v) => _draft.parking = v),
            _text('Umfeldnotizen', _draft.environmentNotes, (v) => _draft.environmentNotes = v, maxLines: 3),
            _text('Lage-Risiken', _draft.locationRisks, (v) => _draft.locationRisks = v, maxLines: 3),
            _text('Lage-Potenziale', _draft.locationPotentials, (v) => _draft.locationPotentials = v, maxLines: 3),
          ]),
        ),
      ],
    );
  }

  Widget _buildAreasStep(
    BuildContext context,
    PropertyCreationAssessment assessment,
  ) {
    return Column(
      children: [
        _Section(
          title: 'Flaechen und Kapazitaeten',
          child: _twoColumnGrid([
            _number('Gesamtflaeche qm', _draft.totalArea, (v) => _draft.totalArea = v),
            _number('Wohnflaeche qm', _draft.residentialArea, (v) => _draft.residentialArea = v),
            _number('Gewerbeflaeche qm', _draft.commercialArea, (v) => _draft.commercialArea = v),
            _number('Nutzflaeche qm', _draft.usableArea, (v) => _draft.usableArea = v),
            _number('Grundstuecksflaeche qm', _draft.landArea, (v) => _draft.landArea = v),
            _intField('Anzahl Wohneinheiten', _draft.residentialUnits, (v) => _draft.residentialUnits = v),
            _intField('Anzahl Gewerbeeinheiten', _draft.commercialUnits, (v) => _draft.commercialUnits = v),
            _intField('Anzahl Stellplaetze', _draft.parkingSpots, (v) => _draft.parkingSpots = v),
            _intField('Anzahl Garagen', _draft.garages, (v) => _draft.garages = v),
            _number('Kellerflaechen qm', _draft.basementArea, (v) => _draft.basementArea = v),
            _number('Leerstehende Flaeche qm', _draft.vacantArea, (v) => _draft.vacantArea = v),
            _number('Vermietete Flaeche qm', _draft.leasedArea, (v) => _draft.leasedArea = v),
            _text('Ausbaupotenzial', _draft.expansionPotential, (v) => _draft.expansionPotential = v),
            _text('Nachverdichtungspotenzial', _draft.densificationPotential, (v) => _draft.densificationPotential = v),
          ]),
        ),
        const SizedBox(height: AppSpacing.component),
        _MetricStrip(
          items: [
            _MetricItem('Gesamt', _formatSqm(assessment.metrics.totalArea)),
            _MetricItem('Vermietet', _formatSqm(assessment.metrics.leasedArea)),
            _MetricItem('Leerstand', _formatSqm(assessment.metrics.vacantArea)),
            _MetricItem('Quote', _formatPercent(assessment.metrics.vacancyRate)),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        _buildUnitsEditor(context),
      ],
    );
  }

  Widget _buildUsageStep(
    BuildContext context,
    PropertyCreationAssessment assessment,
  ) {
    return Column(
      children: [
        _Section(
          title: 'Nutzung und Mieten',
          child: _twoColumnGrid([
            _text('Hauptnutzung', _draft.mainUse, (v) => _draft.mainUse = v),
            _text('Nutzungsmix', _draft.usageMix, (v) => _draft.usageMix = v),
            _number('Aktuelle Jahreskaltmiete', _draft.annualColdRent, (v) => _draft.annualColdRent = v),
            _number('Monatliche Ist-Miete', _draft.monthlyActualRent, (v) => _draft.monthlyActualRent = v),
            _number('Geschaetzte Soll-Miete monatlich', _draft.targetRent, (v) => _draft.targetRent = v),
            _number('Leerstand in Prozent', _draft.vacancyPercent, (v) => _draft.vacancyPercent = v),
            _number('Durchschnittsmiete pro qm', _draft.averageRentPerSqm, (v) => _draft.averageRentPerSqm = v),
            _number('Marktmiete pro qm', _draft.marketRentPerSqm, (v) => _draft.marketRentPerSqm = v),
            _text('Mietvertragsstatus', _draft.leaseContractStatus, (v) => _draft.leaseContractStatus = v),
            _switch('Indexmiete', _draft.indexedRent, (v) => _draft.indexedRent = v),
            _switch('Staffelmiete', _draft.steppedRent, (v) => _draft.steppedRent = v),
            _switch('Mietrueckstaende', _draft.rentArrears, (v) => _draft.rentArrears = v),
            _text('Besondere Mietvereinbarungen', _draft.specialLeaseTerms, (v) => _draft.specialLeaseTerms = v, maxLines: 3),
            _switch('Mieterdaten jetzt erfassen', _draft.captureTenantsNow, (v) => _draft.captureTenantsNow = v),
          ]),
        ),
        const SizedBox(height: AppSpacing.component),
        _MetricStrip(
          items: [
            _MetricItem('Ist/qm', _formatCurrency(assessment.metrics.actualRentPerSqm)),
            _MetricItem('Soll/qm', _formatCurrency(assessment.metrics.targetRentPerSqm)),
            _MetricItem('Ist p.a.', _formatCurrency(assessment.metrics.annualActualRent)),
            _MetricItem('Potenzial', _formatCurrency(assessment.metrics.rentUpside)),
          ],
        ),
        if (_draft.captureTenantsNow) ...[
          const SizedBox(height: AppSpacing.component),
          _buildTenantsEditor(context),
        ],
      ],
    );
  }

  Widget _buildPurchaseStep(
    BuildContext context,
    PropertyCreationAssessment assessment,
  ) {
    final acquisition = _draft.isAcquisitionCase;
    return Column(
      children: [
        _Section(
          title: acquisition ? 'Kaufdaten' : 'Bestandsdaten',
          child: acquisition
              ? _twoColumnGrid([
                  _number('Angebotspreis', _draft.offerPrice, (v) => _draft.offerPrice = v),
                  _number('Kaufpreis', _draft.purchasePrice, (v) => _draft.purchasePrice = v),
                  _date('Kaufdatum', _draft.purchaseDate, (v) => _draft.purchaseDate = v),
                  _date('Notartermin', _draft.notaryDate, (v) => _draft.notaryDate = v),
                  _text('Verkaeufer', _draft.seller, (v) => _draft.seller = v),
                  _text('Makler', _draft.broker, (v) => _draft.broker = v),
                  _number('Grunderwerbsteuer', _draft.propertyTransferTax, (v) => _draft.propertyTransferTax = v),
                  _number('Notarkosten', _draft.notaryCosts, (v) => _draft.notaryCosts = v),
                  _number('Grundbuchkosten', _draft.landRegistryCosts, (v) => _draft.landRegistryCosts = v),
                  _number('Maklercourtage', _draft.brokerFee, (v) => _draft.brokerFee = v),
                  _number('Sonstige Erwerbskosten', _draft.otherAcquisitionCosts, (v) => _draft.otherAcquisitionCosts = v),
                  _date('Uebergang Nutzen und Lasten', _draft.transferBenefitsDate, (v) => _draft.transferBenefitsDate = v),
                ])
              : _twoColumnGrid([
                  _number('Urspruenglicher Kaufpreis', _draft.originalPurchasePrice, (v) => _draft.originalPurchasePrice = v),
                  _date('Urspruengliches Kaufdatum', _draft.originalPurchaseDate, (v) => _draft.originalPurchaseDate = v),
                  _number('Aktueller Buchwert', _draft.bookValue, (v) => _draft.bookValue = v),
                  _number('Aktueller Marktwert', _draft.marketValue, (v) => _draft.marketValue = v),
                  _text('Letzte interne Bewertung', _draft.lastInternalValuation, (v) => _draft.lastInternalValuation = v),
                  _date('Bewertung zum Stichtag', _draft.valuationDate, (v) => _draft.valuationDate = v),
                  _text('Historische Notizen', _draft.historicNotes, (v) => _draft.historicNotes = v, maxLines: 4),
                ]),
        ),
        const SizedBox(height: AppSpacing.component),
        _MetricStrip(
          items: [
            _MetricItem('Preis/qm', _formatCurrency(assessment.metrics.purchasePricePerSqm)),
            _MetricItem('Nebenkosten', _formatCurrency(assessment.metrics.acquisitionCosts)),
            _MetricItem('NK-Quote', _formatPercent(assessment.metrics.acquisitionCostRatio)),
            _MetricItem('Gesamtinvestition', _formatCurrency(assessment.metrics.totalInvestment)),
            _MetricItem('Faktor Ist', _formatNumber(assessment.metrics.purchaseFactorActual)),
            _MetricItem('Faktor Soll', _formatNumber(assessment.metrics.purchaseFactorTarget)),
          ],
        ),
      ],
    );
  }

  Widget _buildFinancingStep(
    BuildContext context,
    PropertyCreationAssessment assessment,
  ) {
    return Column(
      children: [
        _Section(
          title: 'Finanzierung optional',
          child: _twoColumnGrid([
            _switch('Darlehen vorhanden', _draft.hasLoan, (v) => _draft.hasLoan = v),
            _number('Darlehensbetrag', _draft.loanAmount, (v) => _draft.loanAmount = v),
            _number('Eigenkapital', _draft.equity, (v) => _draft.equity = v),
            _number('Zinssatz Prozent', _draft.interestRate, (v) => _draft.interestRate = v),
            _number('Tilgung Prozent', _draft.amortizationRate, (v) => _draft.amortizationRate = v),
            _text('Zinsbindung', _draft.fixedInterestPeriod, (v) => _draft.fixedInterestPeriod = v),
            _intField('Laufzeit Jahre', _draft.termYears, (v) => _draft.termYears = v),
            _number('Monatliche Rate', _draft.monthlyRate, (v) => _draft.monthlyRate = v),
            _number('Jaehrlicher Kapitaldienst', _draft.annualDebtService, (v) => _draft.annualDebtService = v),
            _text('Bank', _draft.bank, (v) => _draft.bank = v),
            _text('Darlehensnummer', _draft.loanNumber, (v) => _draft.loanNumber = v),
            _number('Restschuld', _draft.remainingDebt, (v) => _draft.remainingDebt = v),
            _switch('Sondertilgung moeglich', _draft.specialRepayment, (v) => _draft.specialRepayment = v),
            _text('Finanzierungsnotizen', _draft.financingNotes, (v) => _draft.financingNotes = v, maxLines: 4),
          ]),
        ),
        const SizedBox(height: AppSpacing.component),
        _MetricStrip(
          items: [
            _MetricItem('LTV', _formatPercent(assessment.metrics.loanToValue)),
            _MetricItem('EK-Quote', _formatPercent(assessment.metrics.equityRatio)),
            _MetricItem('Kapitaldienst p.a.', _formatCurrency(_draft.annualDebtService)),
            _MetricItem('Kapitaldienst mtl.', _formatCurrency(_draft.monthlyRate)),
          ],
        ),
      ],
    );
  }

  Widget _buildTechnicalStep(
    BuildContext context,
    PropertyCreationAssessment assessment,
  ) {
    return Column(
      children: [
        _Section(
          title: 'Technischer Zustand',
          child: _twoColumnGrid([
            _intField('Baujahr', _draft.yearBuilt, (v) => _draft.yearBuilt = v),
            _intField('Letzte Sanierung', _draft.lastRenovationYear, (v) => _draft.lastRenovationYear = v),
            _switch('Energieausweis vorhanden', _draft.energyCertificateAvailable, (v) => _draft.energyCertificateAvailable = v),
            _text('Energieklasse', _draft.energyClass, (v) => _draft.energyClass = v),
            _text('Heizungsart', _draft.heatingType, (v) => _draft.heatingType = v),
            _condition('Dachzustand', _draft.roofCondition, (v) => _draft.roofCondition = v),
            _condition('Fassadenzustand', _draft.facadeCondition, (v) => _draft.facadeCondition = v),
            _condition('Fensterzustand', _draft.windowsCondition, (v) => _draft.windowsCondition = v),
            _condition('Elektrikzustand', _draft.electricCondition, (v) => _draft.electricCondition = v),
            _condition('Leitungszustand', _draft.pipesCondition, (v) => _draft.pipesCondition = v),
            _condition('Brandschutzstatus', _draft.fireSafetyStatus, (v) => _draft.fireSafetyStatus = v),
            _condition('Barrierefreiheit', _draft.accessibility, (v) => _draft.accessibility = v),
            _switch('Feuchtigkeitsschaeden', _draft.moistureDamage, (v) => _draft.moistureDamage = v),
            _switch('Denkmalschutz', _draft.monumentProtection, (v) => _draft.monumentProtection = v),
            _text('Bekannter Sanierungsbedarf', _draft.renovationNeed, (v) => _draft.renovationNeed = v, maxLines: 3),
            _number('Geschaetztes Renovierungsbudget', _draft.renovationBudget, (v) => _draft.renovationBudget = v),
            _text('Technische Risiken', _draft.technicalRisks, (v) => _draft.technicalRisks = v, maxLines: 3),
            _text('Technische Notizen', _draft.technicalNotes, (v) => _draft.technicalNotes = v, maxLines: 3),
          ]),
        ),
        const SizedBox(height: AppSpacing.component),
        _MetricStrip(
          items: [
            _MetricItem('Zustands-Score', '${assessment.metrics.conditionScore}%'),
            _MetricItem('Datenqualitaet', '${assessment.metrics.dataQualityScore}%'),
            _MetricItem('Status', assessment.metrics.dataQualityStatus),
          ],
        ),
      ],
    );
  }

  Widget _buildLegalStep(BuildContext context) {
    return _Section(
      title: 'Rechtliche und organisatorische Angaben',
      child: _twoColumnGrid([
        _text('Eigentuemergesellschaft', _draft.ownerCompany, (v) => _draft.ownerCompany = v),
        _switch('Grundbuchinformationen vorhanden', _draft.landRegisterAvailable, (v) => _draft.landRegisterAvailable = v),
        _text('Flurstueck', _draft.parcel, (v) => _draft.parcel = v),
        _switch('Baulasten bekannt', _draft.knownBuildingCharges, (v) => _draft.knownBuildingCharges = v),
        _switch('Denkmalschutz rechtlich', _draft.legalMonumentProtection, (v) => _draft.legalMonumentProtection = v),
        _switch('Teilungserklaerung vorhanden', _draft.declarationOfDivisionAvailable, (v) => _draft.declarationOfDivisionAvailable = v),
        _switch('WEG', _draft.weg, (v) => _draft.weg = v),
        _text('Bestehende Dienstbarkeiten', _draft.easements, (v) => _draft.easements = v, maxLines: 3),
        _text('Bestehende Rechtsstreitigkeiten', _draft.legalDisputes, (v) => _draft.legalDisputes = v, maxLines: 3),
        _text('Versicherungen', _draft.insurances, (v) => _draft.insurances = v),
        _text('Hausverwaltung', _draft.propertyManagement, (v) => _draft.propertyManagement = v),
        _text('Ansprechpartner intern', _draft.internalContact, (v) => _draft.internalContact = v),
        _text('Ansprechpartner extern', _draft.externalContact, (v) => _draft.externalContact = v),
        _text('Steuerliche Besonderheiten', _draft.taxNotes, (v) => _draft.taxNotes = v, maxLines: 3),
        _text('Organisatorische Notizen', _draft.organisationalNotes, (v) => _draft.organisationalNotes = v, maxLines: 3),
        _switch('Kritische Risiken bewusst bestaetigt', _draft.criticalRisksConfirmed, (v) => _draft.criticalRisksConfirmed = v),
      ]),
    );
  }

  Widget _buildDocumentsStep(BuildContext context) {
    return _Section(
      title: 'Dokumente und Datenqualitaet',
      child: Column(
        children: [
          for (final doc in _draft.documents)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 210, child: Text(doc.label)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 150,
                    child: _dropdown(
                      label: 'Status',
                      value: doc.status,
                      items: const {
                        'vorhanden': 'Vorhanden',
                        'fehlt': 'Fehlt',
                        'angefordert': 'Angefordert',
                        'nicht_relevant': 'Nicht relevant',
                      },
                      onChanged: (value) => doc.status = value,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _text('Upload/Pfad optional', doc.uploadPath, (v) => doc.uploadPath = v)),
                  const SizedBox(width: 10),
                  Expanded(child: _text('Notiz', doc.note, (v) => doc.note = v)),
                  const SizedBox(width: 10),
                  SizedBox(width: 150, child: _date('Frist', doc.dueDate, (v) => doc.dueDate = v)),
                  const SizedBox(width: 10),
                  SizedBox(width: 160, child: _text('Verantwortlich', doc.owner, (v) => doc.owner = v)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryStep(
    BuildContext context,
    PropertyCreationAssessment assessment,
  ) {
    return Column(
      children: [
        _MetricStrip(
          items: [
            _MetricItem('Datenqualitaet', '${assessment.metrics.dataQualityScore}%'),
            _MetricItem('Status', assessment.metrics.dataQualityStatus),
            _MetricItem('Pflicht offen', '${assessment.missingRequired.length}'),
            _MetricItem('Warnungen', '${assessment.criticalWarnings.length}'),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        _Section(
          title: 'Pruefansicht',
          child: _twoColumnGrid([
            _SummaryBlock(
              title: 'Objekt',
              lines: [
                _draft.objectName,
                _draft.internalId,
                '${_draft.addressLine1}, ${_draft.zip} ${_draft.city}',
                _draft.propertyType,
                _draft.status,
              ],
            ),
            _SummaryBlock(
              title: 'Flaechen und Einheiten',
              lines: [
                'Gesamt: ${_formatSqm(assessment.metrics.totalArea)}',
                'Einheiten: ${_draft.units.length}',
                'Vermietet: ${_formatSqm(assessment.metrics.leasedArea)}',
                'Leerstand: ${_formatPercent(assessment.metrics.vacancyRate)}',
              ],
            ),
            _SummaryBlock(
              title: 'Mieten und Kauf',
              lines: [
                'Ist-Miete p.a.: ${_formatCurrency(assessment.metrics.annualActualRent)}',
                'Soll-Miete p.a.: ${_formatCurrency(assessment.metrics.annualTargetRent)}',
                'Kaufpreis/qm: ${_formatCurrency(assessment.metrics.purchasePricePerSqm)}',
                'Gesamtinvestition: ${_formatCurrency(assessment.metrics.totalInvestment)}',
              ],
            ),
            _SummaryBlock(
              title: 'Technik, Recht, Dokumente',
              lines: [
                'Zustand: ${assessment.metrics.conditionScore}%',
                'Grundbuch: ${_draft.landRegisterAvailable ? 'vorhanden' : 'offen'}',
                'Energieausweis: ${_draft.energyCertificateAvailable ? 'vorhanden' : 'offen'}',
                'Dokumente geprueft: ${_draft.documents.where((doc) => doc.status != 'fehlt').length}/${_draft.documents.length}',
              ],
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.component),
        _ChecklistPanel(
          title: 'Fehlende Pflichtangaben',
          icon: Icons.error_outline,
          items: assessment.missingRequired,
          emptyText: 'Alle Pflichtangaben sind vorhanden.',
          color: context.semanticColors.error,
        ),
        const SizedBox(height: AppSpacing.component),
        _ChecklistPanel(
          title: 'Empfohlene Angaben',
          icon: Icons.info_outline,
          items: assessment.recommended,
          emptyText: 'Keine empfohlenen Angaben offen.',
          color: context.semanticColors.warning,
        ),
        const SizedBox(height: AppSpacing.component),
        _ChecklistPanel(
          title: 'Kritische Warnungen',
          icon: Icons.warning_amber_outlined,
          items: assessment.criticalWarnings,
          emptyText: 'Keine kritischen Warnungen.',
          color: context.semanticColors.error,
        ),
        const SizedBox(height: AppSpacing.component),
        _Section(
          title: 'Transparente Datenqualitaet',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in assessment.qualityItems)
                Chip(
                  avatar: Icon(
                    item.complete ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: item.complete
                        ? context.semanticColors.success
                        : context.semanticColors.textSecondary,
                    size: 18,
                  ),
                  label: Text(item.label),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSaveStep(
    BuildContext context,
    PropertyCreationAssessment assessment,
  ) {
    final created = _createdProperty;
    if (created == null) {
      return _Section(
        title: 'Final speichern',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              assessment.canSave
                  ? 'Das Objekt ist bereit fuer die Anlage. Erst mit dieser finalen Bestaetigung wird gespeichert.'
                  : 'Vor dem Speichern muessen die Pflichtangaben und kritischen Warnungen geklaert werden.',
            ),
            const SizedBox(height: AppSpacing.component),
            FilledButton.icon(
              onPressed: assessment.canSave && !_saving ? () => _save(assessment) : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Property final speichern'),
            ),
          ],
        ),
      );
    }

    return _Section(
      title: 'Property wurde erfolgreich angelegt',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricStrip(
            items: [
              _MetricItem('Datenqualitaet', '${assessment.metrics.dataQualityScore}%'),
              _MetricItem('Status', assessment.metrics.dataQualityStatus),
              _MetricItem('Vollstaendig', '${assessment.qualityItems.where((item) => item.complete).length}/${assessment.qualityItems.length}'),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(created),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Property Detail Page oeffnen'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(created),
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Intensivbewertung starten'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(created),
                icon: const Icon(Icons.construction_outlined),
                label: const Text('Renovierungsprojekt anlegen'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(created),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Dokumente ergaenzen'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(created),
                icon: const Icon(Icons.people_alt_outlined),
                label: const Text('Mieterliste vervollstaendigen'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(created),
                icon: const Icon(Icons.account_balance_outlined),
                label: const Text('Finanzierung ergaenzen'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(created),
                icon: const Icon(Icons.sell_outlined),
                label: const Text('Verkaufsszenario vorbereiten'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(null),
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('Zur Property-Uebersicht'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnitsEditor(BuildContext context) {
    return _Section(
      title: 'Einheitenstruktur',
      trailing: FilledButton.icon(
        onPressed: () => setState(() {
          _draft.units.add(PropertyCreationUnitDraft());
        }),
        icon: const Icon(Icons.add),
        label: const Text('Einheit hinzufuegen'),
      ),
      child: Column(
        children: [
          if (_draft.units.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Noch keine Einheiten angelegt.'),
            ),
          for (var i = 0; i < _draft.units.length; i++)
            _UnitEditor(
              unit: _draft.units[i],
              onChanged: () => setState(() {}),
              onDuplicate: () => setState(() {
                _draft.units.insert(i + 1, _draft.units[i].duplicate());
              }),
              onRemove: () => setState(() => _draft.units.removeAt(i)),
            ),
        ],
      ),
    );
  }

  Widget _buildTenantsEditor(BuildContext context) {
    return _Section(
      title: 'Mieter optional',
      trailing: FilledButton.icon(
        onPressed: () => setState(() {
          _draft.tenants.add(PropertyCreationTenantDraft());
        }),
        icon: const Icon(Icons.add),
        label: const Text('Mieter hinzufuegen'),
      ),
      child: Column(
        children: [
          if (_draft.tenants.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Mieterdaten koennen jetzt oder spaeter erfasst werden.'),
            ),
          for (var i = 0; i < _draft.tenants.length; i++)
            _TenantEditor(
              tenant: _draft.tenants[i],
              unitCodes: _draft.units.map((unit) => unit.unitCode).where((code) => code.trim().isNotEmpty).toList(growable: false),
              onChanged: () => setState(() {}),
              onRemove: () => setState(() => _draft.tenants.removeAt(i)),
            ),
        ],
      ),
    );
  }

  Future<void> _save(PropertyCreationAssessment assessment) async {
    if (!assessment.canSave) {
      setState(() => _step = 10);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Pflichtangaben und kritische Warnungen pruefen.')),
      );
      return;
    }
    setState(() {
      _saving = true;
      _step = 11;
    });
    try {
      final property = await widget.onCreateProperty(_draft, assessment);
      if (!mounted) {
        return;
      }
      if (property == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Property konnte nicht gespeichert werden.')),
        );
        return;
      }
      setState(() {
        _createdProperty = property;
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _text(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    int maxLines = 1,
  }) {
    return TextFormField(
      initialValue: value,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => setState(() => onChanged(value)),
    );
  }

  Widget _number(
    String label,
    double? value,
    ValueChanged<double?> onChanged,
  ) {
    return TextFormField(
      initialValue: value == null ? '' : _trimNumber(value),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => setState(() => onChanged(parseDoubleFlexible(value))),
    );
  }

  Widget _intField(
    String label,
    int? value,
    ValueChanged<int?> onChanged,
  ) {
    return TextFormField(
      initialValue: value?.toString() ?? '',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => setState(() => onChanged(parseIntFlexible(value))),
    );
  }

  Widget _date(
    String label,
    int? value,
    ValueChanged<int?> onChanged,
  ) {
    return TextFormField(
      initialValue: value == null ? '' : _formatDate(value),
      decoration: InputDecoration(labelText: label, hintText: 'YYYY-MM-DD'),
      onChanged: (value) => setState(() => onChanged(_parseDate(value))),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: items.containsKey(value) ? value : items.keys.first,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final entry in items.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (value) {
        if (value == null) {
          return;
        }
        setState(() => onChanged(value));
      },
    );
  }

  Widget _condition(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) {
    return _dropdown(
      label: label,
      value: value,
      items: const {
        'very_good': 'Sehr gut',
        'good': 'Gut',
        'medium': 'Mittel',
        'poor': 'Schlecht',
        'critical': 'Kritisch',
        'unknown': 'Unbekannt',
      },
      onChanged: onChanged,
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      value: value,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      onChanged: (value) => setState(() => onChanged(value)),
    );
  }

  Widget _twoColumnGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 760;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            for (final child in children)
              SizedBox(
                width: twoColumns
                    ? (constraints.maxWidth - AppSpacing.component) / 2
                    : constraints.maxWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }

  static String _suggestNextInternalId(List<PropertyRecord> properties) {
    final year = DateTime.now().year;
    var maxNumber = 0;
    final regex = RegExp('^NX-$year-(\\d+)\$');
    for (final property in properties) {
      final match = regex.firstMatch(property.id);
      if (match == null) {
        continue;
      }
      final value = int.tryParse(match.group(1) ?? '');
      if (value != null && value > maxNumber) {
        maxNumber = value;
      }
    }
    return 'NX-$year-${(maxNumber + 1).toString().padLeft(4, '0')}';
  }

  static int? _parseDate(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day).millisecondsSinceEpoch;
  }
}

const _steps = <String>[
  'Einstieg und Objektart',
  'Basisdaten',
  'Adresse und Lage',
  'Flaechen und Einheiten',
  'Nutzung und Mieterstruktur',
  'Kaufdaten oder Bestandsdaten',
  'Finanzierung optional',
  'Technischer Zustand',
  'Rechtliche und organisatorische Angaben',
  'Dokumente und Datenqualitaet',
  'Zusammenfassung und Pruefung',
  'Speichern und naechste Schritte',
];

const _stepSubtitles = <String>[
  'Lege fest, was fuer ein Objekt angelegt wird und wie tief der Prozess laufen soll.',
  'Stammdaten, interne ID, Status, Verantwortlichkeiten und Kategorien.',
  'Klare Trennung zwischen Adresse, Lagequalitaet und Standortnotizen.',
  'Flaechen, Einheiten und Plausibilitaet der Flaechensummen.',
  'Nutzungsmix, Mieten, Leerstand und optionale Mieterdaten.',
  'Abhaengig vom Anlagegrund: Ankauf oder Bestandsdaten mit Kennzahlen.',
  'Optionaler Finanzierungsblock ohne Speicherblockade bei fehlenden Daten.',
  'Technische Angaben und ein nachvollziehbarer Zustands-Score.',
  'Rechtliche, organisatorische und kritisch zu bestaetigende Punkte.',
  'Dokumentencheckliste und Grundlage fuer die Datenqualitaet.',
  'Pruefansicht mit Pflichtangaben, Empfehlungen, Risiken und Kennzahlen.',
  'Finale Speicherung und empfohlene naechste Aktionen.',
];

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          child,
        ],
      ),
    );
  }
}

class _OptionSpec {
  const _OptionSpec(this.value, this.title, this.icon, this.description);

  final String value;
  final String title;
  final IconData icon;
  final String description;
}

class _OptionGrid extends StatelessWidget {
  const _OptionGrid({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<_OptionSpec> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 3 * AppSpacing.component) / 4
            : (constraints.maxWidth - AppSpacing.component) / 2;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            for (final option in options)
              SizedBox(
                width: width,
                child: InkWell(
                  onTap: () => onSelected(option.value),
                  borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 128),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected == option.value
                          ? Theme.of(context).colorScheme.primaryContainer
                          : context.semanticColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                      border: Border.all(
                        color: selected == option.value
                            ? Theme.of(context).colorScheme.primary
                            : context.semanticColors.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(option.icon),
                        const SizedBox(height: 10),
                        Text(
                          option.title,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          option.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.semanticColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StepNavTile extends StatelessWidget {
  const _StepNavTile({
    required this.index,
    required this.label,
    required this.selected,
    required this.state,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool selected;
  final PropertyCreationStepState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      PropertyCreationStepState.complete => Icons.check_circle,
      PropertyCreationStepState.warning => Icons.warning_amber,
      PropertyCreationStepState.incomplete => Icons.error_outline,
      PropertyCreationStepState.untouched => Icons.radio_button_unchecked,
    };
    final color = switch (state) {
      PropertyCreationStepState.complete => context.semanticColors.success,
      PropertyCreationStepState.warning => context.semanticColors.warning,
      PropertyCreationStepState.incomplete => context.semanticColors.error,
      PropertyCreationStepState.untouched => context.semanticColors.textSecondary,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        enabled: onTap != null,
        selected: selected,
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        ),
        leading: Icon(icon, color: color, size: 20),
        title: Text('${index + 1}. $label', maxLines: 2),
        onTap: onTap,
      ),
    );
  }
}

class _QualityPanel extends StatelessWidget {
  const _QualityPanel({required this.assessment});

  final PropertyCreationAssessment assessment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Datenqualitaet',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: assessment.metrics.dataQualityScore / 100),
          const SizedBox(height: 8),
          Text(
            '${assessment.metrics.dataQualityScore}% · ${assessment.metrics.dataQualityStatus}',
          ),
        ],
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.items});

  final List<_MetricItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.component,
      runSpacing: AppSpacing.component,
      children: [
        for (final item in items)
          Container(
            width: 170,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.semanticColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
              border: Border.all(color: context.semanticColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.semanticColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MetricItem {
  const _MetricItem(this.label, this.value);

  final String label;
  final String value;
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final line in lines.where((line) => line.trim().isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line),
            ),
        ],
      ),
    );
  }
}

class _ChecklistPanel extends StatelessWidget {
  const _ChecklistPanel({
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyText,
    required this.color,
  });

  final String title;
  final IconData icon;
  final List<String> items;
  final String emptyText;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isEmpty)
            Text(emptyText)
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _UnitEditor extends StatelessWidget {
  const _UnitEditor({
    required this.unit,
    required this.onChanged,
    required this.onDuplicate,
    required this.onRemove,
  });

  final PropertyCreationUnitDraft unit;
  final VoidCallback onChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _inlineText('Einheitennummer', unit.unitCode, (v) => unit.unitCode = v)),
              const SizedBox(width: 10),
              Expanded(child: _inlineText('Nutzung', unit.useType, (v) => unit.useType = v)),
              const SizedBox(width: 10),
              Expanded(child: _inlineText('Etage', unit.floor, (v) => unit.floor = v)),
              const SizedBox(width: 10),
              Expanded(child: _inlineNumber('Flaeche', unit.area, (v) => unit.area = v)),
              IconButton(
                tooltip: 'Duplizieren',
                onPressed: onDuplicate,
                icon: const Icon(Icons.copy_outlined),
              ),
              IconButton(
                tooltip: 'Entfernen',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _inlineNumber('Zimmer optional', unit.rooms, (v) => unit.rooms = v)),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: unit.status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'occupied', child: Text('Vermietet')),
                    DropdownMenuItem(value: 'vacant', child: Text('Leer')),
                    DropdownMenuItem(value: 'reserved', child: Text('Reserviert')),
                    DropdownMenuItem(value: 'renovation', child: Text('In Sanierung')),
                    DropdownMenuItem(value: 'offline', child: Text('Nicht nutzbar')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      unit.status = value;
                      onChanged();
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _inlineNumber('Kaltmiete', unit.coldRent, (v) => unit.coldRent = v)),
              const SizedBox(width: 10),
              Expanded(child: _inlineNumber('Nebenkosten', unit.serviceCharge, (v) => unit.serviceCharge = v)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _inlineText('Stellplatzzuordnung', unit.parkingAssignment, (v) => unit.parkingAssignment = v)),
              const SizedBox(width: 10),
              Expanded(child: _inlineText('Notizen', unit.notes, (v) => unit.notes = v)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inlineText(String label, String value, ValueChanged<String> setter) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) {
        setter(value);
        onChanged();
      },
    );
  }

  Widget _inlineNumber(String label, double? value, ValueChanged<double?> setter) {
    return TextFormField(
      initialValue: value == null ? '' : _trimNumber(value),
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (value) {
        setter(parseDoubleFlexible(value));
        onChanged();
      },
    );
  }
}

class _TenantEditor extends StatelessWidget {
  const _TenantEditor({
    required this.tenant,
    required this.unitCodes,
    required this.onChanged,
    required this.onRemove,
  });

  final PropertyCreationTenantDraft tenant;
  final List<String> unitCodes;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _inlineText('Mietername', tenant.tenantName, (v) => tenant.tenantName = v)),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: unitCodes.contains(tenant.unitCode)
                      ? tenant.unitCode
                      : (unitCodes.isEmpty ? null : unitCodes.first),
                  decoration: const InputDecoration(labelText: 'Einheit'),
                  items: [
                    for (final code in unitCodes)
                      DropdownMenuItem(value: code, child: Text(code)),
                  ],
                  onChanged: (value) {
                    tenant.unitCode = value ?? '';
                    onChanged();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Entfernen',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _inlineDate('Mietbeginn', tenant.leaseStart, (v) => tenant.leaseStart = v)),
              const SizedBox(width: 10),
              Expanded(child: _inlineDate('Mietende', tenant.leaseEnd, (v) => tenant.leaseEnd = v)),
              const SizedBox(width: 10),
              Expanded(child: _inlineText('Kuendigungsfrist', tenant.noticePeriod, (v) => tenant.noticePeriod = v)),
              const SizedBox(width: 10),
              Expanded(child: _inlineNumber('Kaltmiete', tenant.coldRent, (v) => tenant.coldRent = v)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _inlineNumber('Nebenkosten', tenant.serviceCharges, (v) => tenant.serviceCharges = v)),
              const SizedBox(width: 10),
              Expanded(child: _inlineNumber('Kaution', tenant.deposit, (v) => tenant.deposit = v)),
              const SizedBox(width: 10),
              Expanded(child: _inlineText('Zahlungsstatus', tenant.paymentStatus, (v) => tenant.paymentStatus = v)),
              const SizedBox(width: 10),
              Expanded(child: _inlineText('Notizen', tenant.notes, (v) => tenant.notes = v)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inlineText(String label, String value, ValueChanged<String> setter) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) {
        setter(value);
        onChanged();
      },
    );
  }

  Widget _inlineNumber(String label, double? value, ValueChanged<double?> setter) {
    return TextFormField(
      initialValue: value == null ? '' : _trimNumber(value),
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (value) {
        setter(parseDoubleFlexible(value));
        onChanged();
      },
    );
  }

  Widget _inlineDate(String label, int? value, ValueChanged<int?> setter) {
    return TextFormField(
      initialValue: value == null ? '' : _formatDate(value),
      decoration: InputDecoration(labelText: label, hintText: 'YYYY-MM-DD'),
      onChanged: (value) {
        setter(_PropertyCreationWorkflowScreenState._parseDate(value));
        onChanged();
      },
    );
  }
}

class _FooterBar extends StatelessWidget {
  const _FooterBar({
    required this.currentStep,
    required this.totalSteps,
    required this.canSave,
    required this.saving,
    required this.created,
    required this.onBack,
    required this.onNext,
    required this.onSummary,
    required this.onSave,
  });

  final int currentStep;
  final int totalSteps;
  final bool canSave;
  final bool saving;
  final bool created;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSummary;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: context.semanticColors.border)),
      ),
      child: Row(
        children: [
          Text('Schritt ${currentStep + 1} von $totalSteps'),
          const Spacer(),
          TextButton(onPressed: onSummary, child: const Text('Zur Pruefung')),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Zurueck'),
          ),
          const SizedBox(width: 8),
          if (currentStep < totalSteps - 1)
            FilledButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Weiter'),
            )
          else
            FilledButton.icon(
              onPressed: canSave && !saving && !created ? onSave : null,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Speichern'),
            ),
        ],
      ),
    );
  }
}

String _formatCurrency(double? value) {
  if (value == null) {
    return 'offen';
  }
  return '${value.toStringAsFixed(value.abs() >= 1000 ? 0 : 2)} EUR';
}

String _formatPercent(double? value) {
  if (value == null) {
    return 'offen';
  }
  return '${(value * 100).toStringAsFixed(1)}%';
}

String _formatSqm(double? value) {
  if (value == null) {
    return 'offen';
  }
  return '${value.toStringAsFixed(1)} qm';
}

String _formatNumber(double? value) {
  if (value == null) {
    return 'offen';
  }
  return value.toStringAsFixed(2);
}

String _trimNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toString();
}

String _formatDate(int millis) {
  return DateTime.fromMillisecondsSinceEpoch(millis)
      .toIso8601String()
      .substring(0, 10);
}
