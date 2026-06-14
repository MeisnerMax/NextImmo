import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/investment_modules.dart';
import '../../core/services/datasheet_export_service.dart';
import '../components/nx_card.dart';
import '../state/app_state.dart';
import '../templates/list_filter_template.dart';
import '../theme/app_theme.dart';
import '../utils/datasheet_file_export.dart';
import '../utils/number_parse.dart';

class DispositionExitScreen extends ConsumerStatefulWidget {
  const DispositionExitScreen({super.key});

  @override
  ConsumerState<DispositionExitScreen> createState() =>
      _DispositionExitScreenState();
}

class _DispositionExitScreenState
    extends ConsumerState<DispositionExitScreen> {
  final _caseCtrl = TextEditingController(text: 'Exit-Szenario');
  final _plannedSaleDateCtrl = TextEditingController();
  final _loiDateCtrl = TextEditingController();
  final _spaSignedDateCtrl = TextEditingController();
  final _notaryDateCtrl = TextEditingController();
  final _closingDateCtrl = TextEditingController();
  final _handoverDateCtrl = TextEditingController();
  final _salePriceCtrl = TextEditingController(text: '0');
  final _minimumPriceCtrl = TextEditingController(text: '0');
  final _targetPriceCtrl = TextEditingController(text: '0');
  final _bovCtrl = TextEditingController(text: '0');
  final _appraiserValueCtrl = TextEditingController(text: '0');
  final _internalTargetValueCtrl = TextEditingController(text: '0');
  final _marketValueCtrl = TextEditingController(text: '0');
  final _buyerGroupCtrl = TextEditingController();
  final _saleStrategyCtrl = TextEditingController();
  final _currentNoiCtrl = TextEditingController(text: '0');
  final _stabilizedNoiCtrl = TextEditingController(text: '0');
  final _exitCapCtrl = TextEditingController(text: '5');
  final _annualRentCtrl = TextEditingController(text: '0');
  final _areaCtrl = TextEditingController(text: '0');
  final _brokerCtrl = TextEditingController(text: '0');
  final _legalCtrl = TextEditingController(text: '0');
  final _notaryCtrl = TextEditingController(text: '0');
  final _ddCtrl = TextEditingController(text: '0');
  final _penaltyCtrl = TextEditingController(text: '0');
  final _debtCtrl = TextEditingController(text: '0');
  final _taxCtrl = TextEditingController(text: '0');
  final _capexCtrl = TextEditingController(text: '0');
  final _marketingCtrl = TextEditingController(text: '0');
  final _otherCtrl = TextEditingController(text: '0');
  final _purchaseCtrl = TextEditingController(text: '0');
  final _acquisitionCostsCtrl = TextEditingController(text: '0');
  final _renovationCostsCtrl = TextEditingController(text: '0');
  final _cashflowsCtrl = TextEditingController(text: '0');
  final _equityCtrl = TextEditingController(text: '0');
  final _holdYearsCtrl = TextEditingController(text: '5');
  final _holdValueCtrl = TextEditingController(text: '0');
  final _closingConditionsCtrl = TextEditingController();
  final _taxNotesCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final List<DispositionOfferInput> _offers = <DispositionOfferInput>[];
  String? _lastDatasheetId;
  String? _lastExportFileName;
  String? _lastScenarioId;
  String? _error;
  String _scenarioType = 'base';
  String _saleStatus = 'idea';
  String _buyerDdStatus = 'not_started';
  String _dataRoomStatus = 'not_started';
  String _taxAssessmentStatus = 'estimate';

  @override
  void initState() {
    super.initState();
    _applyPendingRenovationImpact();
    for (final controller in _controllers) {
      controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_rebuild);
      controller.dispose();
    }
    super.dispose();
  }

  List<TextEditingController> get _controllers => <TextEditingController>[
        _caseCtrl,
        _plannedSaleDateCtrl,
        _loiDateCtrl,
        _spaSignedDateCtrl,
        _notaryDateCtrl,
        _closingDateCtrl,
        _handoverDateCtrl,
        _salePriceCtrl,
        _minimumPriceCtrl,
        _targetPriceCtrl,
        _bovCtrl,
        _appraiserValueCtrl,
        _internalTargetValueCtrl,
        _marketValueCtrl,
        _buyerGroupCtrl,
        _saleStrategyCtrl,
        _currentNoiCtrl,
        _stabilizedNoiCtrl,
        _exitCapCtrl,
        _annualRentCtrl,
        _areaCtrl,
        _brokerCtrl,
        _legalCtrl,
        _notaryCtrl,
        _ddCtrl,
        _penaltyCtrl,
        _debtCtrl,
        _taxCtrl,
        _capexCtrl,
        _marketingCtrl,
        _otherCtrl,
        _purchaseCtrl,
        _acquisitionCostsCtrl,
        _renovationCostsCtrl,
        _cashflowsCtrl,
        _equityCtrl,
        _holdYearsCtrl,
        _holdValueCtrl,
        _closingConditionsCtrl,
        _taxNotesCtrl,
        _notesCtrl,
      ];

  @override
  Widget build(BuildContext context) {
    final inputs = _inputs();
    final result = ref.read(dispositionCalculationServiceProvider).calculate(inputs);

    return ListFilterTemplate(
      title: 'Verkauf und Exit-Analyse',
      breadcrumbs: const <String>['Bewertung & Szenarien', 'Verkauf'],
      subtitle:
          'Nettoerloes, Gewinn, Exit Cap Rate, Equity Multiple und Hold-vs-Sell.',
      primaryAction: ElevatedButton.icon(
        onPressed: () => _saveDatasheet(
          inputs,
          result,
          DatasheetExportFormat.json,
        ),
        icon: const Icon(Icons.description_outlined),
        label: const Text('JSON exportieren'),
      ),
      secondaryActions: [
        OutlinedButton.icon(
          onPressed: () => _saveDatasheet(
            inputs,
            result,
            DatasheetExportFormat.csv,
          ),
          icon: const Icon(Icons.table_view_outlined),
          label: const Text('CSV exportieren'),
        ),
        OutlinedButton.icon(
          onPressed: () => _saveDatasheet(
            inputs,
            result,
            DatasheetExportFormat.pdf,
          ),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('PDF exportieren'),
        ),
        OutlinedButton.icon(
          onPressed: () => _saveScenario(inputs, result),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Verkaufsszenario speichern'),
        ),
        OutlinedButton.icon(
          onPressed: _closeHistoricalDeal,
          icon: const Icon(Icons.task_alt_outlined),
          label: const Text('Historischen Deal abschliessen'),
        ),
      ],
      scrollable: true,
      expandContent: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            NxCard(child: Text(_error!)),
            const SizedBox(height: AppSpacing.component),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1100;
              final form = _form(context);
              final results = _results(context, inputs, result);
              final offers = _offersCard(context, inputs);
              if (!wide) {
                return Column(children: [
                  form,
                  const SizedBox(height: AppSpacing.component),
                  results,
                  const SizedBox(height: AppSpacing.component),
                  offers,
                ]);
              }
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: form),
                      const SizedBox(width: AppSpacing.component),
                      Expanded(flex: 4, child: results),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.component),
                  offers,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _offersCard(BuildContext context, DispositionModuleInputs inputs) {
    final rankings = ref
        .read(dispositionCalculationServiceProvider)
        .rankOffers(offers: _offers, targetSalePrice: inputs.targetSalePrice);
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Kaeuferangebote',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _showOfferDialog,
                icon: const Icon(Icons.add),
                label: const Text('Angebot erfassen'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          if (rankings.isEmpty)
            Text(
              'Noch keine Angebote erfasst.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const <DataColumn>[
                  DataColumn(label: Text('Rang')),
                  DataColumn(label: Text('Kaeufer')),
                  DataColumn(label: Text('Version')),
                  DataColumn(label: Text('Angebot')),
                  DataColumn(label: Text('DD-Frist')),
                  DataColumn(label: Text('Exklusivitaet')),
                  DataColumn(label: Text('Zahlungsziel')),
                  DataColumn(label: Text('Abw. Ziel')),
                  DataColumn(label: Text('Adj. Wert')),
                  DataColumn(label: Text('Hinweis')),
                ],
                rows: rankings
                    .map(
                      (ranking) => DataRow(
                        cells: <DataCell>[
                          DataCell(Text('${ranking.rank}')),
                          DataCell(Text(ranking.offer.buyerName)),
                          DataCell(Text(ranking.offer.offerVersion ?? '')),
                          DataCell(Text(_currency(ranking.offer.offerPrice))),
                          DataCell(Text(ranking.offer.dueDiligenceDeadline ?? '')),
                          DataCell(Text(ranking.offer.exclusivityUntil ?? '')),
                          DataCell(Text(ranking.offer.paymentTarget ?? '')),
                          DataCell(Text(_currency(ranking.deviationToTarget))),
                          DataCell(Text(_currency(ranking.riskAdjustedValue))),
                          DataCell(Text(ranking.warning ?? '')),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Verkaufsfall', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.component),
          _field(_caseCtrl, 'Name'),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _shortField(_plannedSaleDateCtrl, 'Verkaufszeitpunkt YYYY-MM-DD'),
              _shortField(_buyerGroupCtrl, 'Kaeufergruppe'),
              _shortField(_saleStrategyCtrl, 'Verkaufsstrategie'),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          DropdownButtonFormField<String>(
            value: _scenarioType,
            items: const [
              DropdownMenuItem(value: 'base', child: Text('Base Case')),
              DropdownMenuItem(value: 'best', child: Text('Best Case')),
              DropdownMenuItem(value: 'worst', child: Text('Worst Case')),
              DropdownMenuItem(value: 'custom', child: Text('Eigener Case')),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _scenarioType = value);
            },
            decoration: const InputDecoration(labelText: 'Szenario'),
          ),
          const SizedBox(height: AppSpacing.component),
          DropdownButtonFormField<String>(
            value: _saleStatus,
            items: const [
              DropdownMenuItem(value: 'idea', child: Text('Idee')),
              DropdownMenuItem(value: 'valuation', child: Text('Bewertung')),
              DropdownMenuItem(value: 'broker_selection', child: Text('Maklerauswahl')),
              DropdownMenuItem(value: 'marketing', child: Text('Vermarktung')),
              DropdownMenuItem(value: 'offers', child: Text('Angebote')),
              DropdownMenuItem(value: 'negotiation', child: Text('Verhandlung')),
              DropdownMenuItem(value: 'buyer_due_diligence', child: Text('Due Diligence Kaeufer')),
              DropdownMenuItem(value: 'notary', child: Text('Notar')),
              DropdownMenuItem(value: 'sold', child: Text('Verkauft')),
              DropdownMenuItem(value: 'aborted', child: Text('Abgebrochen')),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _saleStatus = value);
            },
            decoration: const InputDecoration(labelText: 'Verkaufsstatus'),
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _field(_loiDateCtrl, 'LOI-Datum'),
              _field(_spaSignedDateCtrl, 'SPA unterschrieben'),
              _field(_notaryDateCtrl, 'Notartermin'),
              _field(_closingDateCtrl, 'Closing'),
              _field(_handoverDateCtrl, 'Uebergabe'),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  value: _buyerDdStatus,
                  items: const [
                    DropdownMenuItem(value: 'not_started', child: Text('nicht gestartet')),
                    DropdownMenuItem(value: 'open', child: Text('offen')),
                    DropdownMenuItem(value: 'in_review', child: Text('in Pruefung')),
                    DropdownMenuItem(value: 'cleared', child: Text('abgeschlossen')),
                    DropdownMenuItem(value: 'blocked', child: Text('blockiert')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _buyerDdStatus = value);
                  },
                  decoration: const InputDecoration(labelText: 'Kaeufer-DD-Status'),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  value: _dataRoomStatus,
                  items: const [
                    DropdownMenuItem(value: 'not_started', child: Text('nicht gestartet')),
                    DropdownMenuItem(value: 'collecting', child: Text('Dokumente sammeln')),
                    DropdownMenuItem(value: 'ready', child: Text('bereit')),
                    DropdownMenuItem(value: 'shared', child: Text('geteilt')),
                    DropdownMenuItem(value: 'incomplete', child: Text('unvollstaendig')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _dataRoomStatus = value);
                  },
                  decoration: const InputDecoration(labelText: 'Datenraum'),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  value: _taxAssessmentStatus,
                  items: const [
                    DropdownMenuItem(value: 'estimate', child: Text('Schaetzung')),
                    DropdownMenuItem(value: 'advisor_review', child: Text('Steuerberater prueft')),
                    DropdownMenuItem(value: 'confirmed', child: Text('bestaetigt')),
                    DropdownMenuItem(value: 'not_applicable', child: Text('nicht relevant')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _taxAssessmentStatus = value);
                  },
                  decoration: const InputDecoration(labelText: 'Steuerstatus'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _number(_salePriceCtrl, 'Verkaufspreis', prefixText: 'EUR '),
              _number(_minimumPriceCtrl, 'Mindestpreis', prefixText: 'EUR '),
              _number(_targetPriceCtrl, 'Zielpreis', prefixText: 'EUR '),
              _number(_bovCtrl, 'Broker Opinion of Value', prefixText: 'EUR '),
              _number(_appraiserValueCtrl, 'Gutachterwert', prefixText: 'EUR '),
              _number(_internalTargetValueCtrl, 'interner Zielwert', prefixText: 'EUR '),
              _number(_marketValueCtrl, 'Marktwert', prefixText: 'EUR '),
              _number(_currentNoiCtrl, 'aktueller NOI', prefixText: 'EUR '),
              _number(_stabilizedNoiCtrl, 'stabilisierter NOI', prefixText: 'EUR '),
              _number(_exitCapCtrl, 'Exit Cap Rate', suffixText: '%'),
              _number(_annualRentCtrl, 'Jahreskaltmiete', prefixText: 'EUR '),
              _number(_areaCtrl, 'Flaeche', suffixText: 'm2'),
              _number(_brokerCtrl, 'Maklerkosten', prefixText: 'EUR '),
              _number(_legalCtrl, 'Rechtsberatung', prefixText: 'EUR '),
              _number(_notaryCtrl, 'Notar', prefixText: 'EUR '),
              _number(_ddCtrl, 'Due Diligence', prefixText: 'EUR '),
              _number(_penaltyCtrl, 'Vorfaelligkeit', prefixText: 'EUR '),
              _number(_debtCtrl, 'Restschuld', prefixText: 'EUR '),
              _number(_taxCtrl, 'Steuern', prefixText: 'EUR '),
              _number(_capexCtrl, 'offene CapEx', prefixText: 'EUR '),
              _number(_marketingCtrl, 'Vermarktung', prefixText: 'EUR '),
              _number(_otherCtrl, 'sonstige Kosten', prefixText: 'EUR '),
              _number(_purchaseCtrl, 'Kaufpreis historisch', prefixText: 'EUR '),
              _number(_acquisitionCostsCtrl, 'Kaufnebenkosten', prefixText: 'EUR '),
              _number(_renovationCostsCtrl, 'Renovierungskosten', prefixText: 'EUR '),
              _number(_cashflowsCtrl, 'laufende Cashflows', prefixText: 'EUR '),
              _number(_equityCtrl, 'Eigenkapital', prefixText: 'EUR '),
              _number(_holdYearsCtrl, 'Haltedauer', suffixText: 'Jahre'),
              _number(_holdValueCtrl, 'Hold Value', prefixText: 'EUR '),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          TextField(
            controller: _closingConditionsCtrl,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Closing-Bedingungen'),
          ),
          const SizedBox(height: AppSpacing.component),
          TextField(
            controller: _taxNotesCtrl,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Steuerannahmen / Hinweise'),
          ),
          const SizedBox(height: AppSpacing.component),
          TextField(
            controller: _notesCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Notizen'),
          ),
        ],
      ),
    );
  }

  Widget _results(
    BuildContext context,
    DispositionModuleInputs inputs,
    DispositionModuleResult result,
  ) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ergebnis', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.component),
          _metric('Nettoverkaufserloes vor Steuern', _currency(result.netSaleProceedsBeforeTax)),
          _metric('Nettoverkaufserloes', _currency(result.netSaleProceeds)),
          _metric('Gesamtrueckfluss vor Steuern', _currency(result.totalReturnBeforeTax)),
          _metric('Gewinn vor Steuern', _currency(result.profitBeforeTax)),
          _metric('Gesamtrueckfluss nach Steuern', _currency(result.totalReturnAfterTax)),
          _metric('Gewinn nach Steuern', _currency(result.profitAfterTax)),
          _metric('Gewinnmarge', _nullablePercent(result.profitMargin)),
          _metric('Gesamtergebnis Investition', _currency(result.gainVsTotalInvestment)),
          _metric('Gain on Cost', _nullablePercent(result.gainOnCost)),
          _metric('Performance ggü. Ankauf', _currency(result.performanceVsAcquisitionCost)),
          _metric('Performance ggü. Renovierung', _currency(result.performanceVsRenovationAdjustedCost)),
          _metric('Preis pro m2', _nullableCurrency(result.salePricePerSqm)),
          _metric('Exit Cap Rate', _nullablePercent(result.exitCapRate)),
          if (inputs.brokerOpinionValue > 0)
            _metric('BOV', _currency(inputs.brokerOpinionValue)),
          if (inputs.appraiserValue > 0)
            _metric('Gutachterwert', _currency(inputs.appraiserValue)),
          if (inputs.internalTargetValue > 0)
            _metric('Interner Zielwert', _currency(inputs.internalTargetValue)),
          if (inputs.marketValue > 0)
            _metric('Marktwert', _currency(inputs.marketValue)),
          _metric('IRR', _nullablePercent(result.irr)),
          _metric('Equity Multiple', result.equityMultiple == null ? 'N/A' : '${result.equityMultiple!.toStringAsFixed(2)}x'),
          _metric('Hold-vs-Sell', _currency(result.holdVsSellDifference)),
          _metric('Mindestpreis Zielrendite', _currency(result.minimumSalePriceForTarget)),
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.component),
            _warningsInline(context, result.warnings),
          ],
          if (_lastDatasheetId != null) ...[
            const SizedBox(height: 8),
            Text('Letztes Datasheet gespeichert: $_lastDatasheetId'),
          ],
          if (_lastExportFileName != null) ...[
            const SizedBox(height: 8),
            Text('Letzter Export: $_lastExportFileName'),
          ],
          if (_lastScenarioId != null) ...[
            const SizedBox(height: 8),
            Text('Letztes Szenario gespeichert: $_lastScenarioId'),
          ],
        ],
      ),
    );
  }

  DispositionModuleInputs _inputs() {
    return DispositionModuleInputs(
      caseName: _caseCtrl.text.trim().isEmpty ? 'Exit-Szenario' : _caseCtrl.text.trim(),
      saleStatus: _saleStatus,
      plannedSaleDate: _nullableText(_plannedSaleDateCtrl),
      loiDate: _nullableText(_loiDateCtrl),
      spaSignedDate: _nullableText(_spaSignedDateCtrl),
      notaryDate: _nullableText(_notaryDateCtrl),
      closingDate: _nullableText(_closingDateCtrl),
      handoverDate: _nullableText(_handoverDateCtrl),
      expectedSalePrice: _double(_salePriceCtrl),
      minimumSalePrice: _double(_minimumPriceCtrl),
      targetSalePrice: _double(_targetPriceCtrl),
      brokerOpinionValue: _double(_bovCtrl),
      appraiserValue: _double(_appraiserValueCtrl),
      internalTargetValue: _double(_internalTargetValueCtrl),
      marketValue: _double(_marketValueCtrl),
      buyerGroup: _nullableText(_buyerGroupCtrl),
      saleStrategy: _nullableText(_saleStrategyCtrl),
      buyerDueDiligenceStatus: _buyerDdStatus,
      dataRoomStatus: _dataRoomStatus,
      taxAssessmentStatus: _taxAssessmentStatus,
      closingConditions: _nullableText(_closingConditionsCtrl),
      taxNotes: _nullableText(_taxNotesCtrl),
      currentNoi: _double(_currentNoiCtrl),
      stabilizedNoi: _double(_stabilizedNoiCtrl),
      exitCapRate: _double(_exitCapCtrl) / 100,
      annualColdRent: _double(_annualRentCtrl),
      areaSqm: _double(_areaCtrl),
      brokerCosts: _double(_brokerCtrl),
      legalCosts: _double(_legalCtrl),
      notaryCosts: _double(_notaryCtrl),
      dueDiligenceCosts: _double(_ddCtrl),
      prepaymentPenalty: _double(_penaltyCtrl),
      remainingDebt: _double(_debtCtrl),
      taxes: _double(_taxCtrl),
      openCapex: _double(_capexCtrl),
      marketingCosts: _double(_marketingCtrl),
      otherCosts: _double(_otherCtrl),
      originalPurchasePrice: _double(_purchaseCtrl),
      acquisitionCosts: _double(_acquisitionCostsCtrl),
      renovationCosts: _double(_renovationCostsCtrl),
      runningCashflows: _double(_cashflowsCtrl),
      equityInvested: _double(_equityCtrl),
      holdPeriodYears: _int(_holdYearsCtrl),
      holdValue: _double(_holdValueCtrl),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
  }

  void _applyPendingRenovationImpact() {
    final transfer = ref.read(renovationImpactTransferProvider);
    if (transfer == null) {
      return;
    }
    _renovationCostsCtrl.text = transfer.forecastTotalCosts.toStringAsFixed(0);
    if (transfer.noiAfter > 0) {
      _stabilizedNoiCtrl.text = transfer.noiAfter.toStringAsFixed(0);
    }
    if (transfer.valueAfter != null && transfer.valueAfter! > 0) {
      _holdValueCtrl.text = transfer.valueAfter!.toStringAsFixed(0);
      if (_salePriceCtrl.text.trim() == '0') {
        _salePriceCtrl.text = transfer.valueAfter!.toStringAsFixed(0);
      }
    }
    _notesCtrl.text = [
      if (_notesCtrl.text.trim().isNotEmpty) _notesCtrl.text.trim(),
      'Renovierungswirkung uebernommen: ${transfer.projectName}',
      'Forecast Kosten: ${transfer.forecastTotalCosts.toStringAsFixed(0)} EUR',
      if (transfer.netValueUplift != null)
        'Net Value Uplift: ${transfer.netValueUplift!.toStringAsFixed(0)} EUR',
      if (transfer.renovationIrr != null)
        'Renovierungs-IRR: ${(transfer.renovationIrr! * 100).toStringAsFixed(2)}%',
    ].join('\n');
    ref.read(renovationImpactTransferProvider.notifier).state = null;
  }

  Future<void> _saveDatasheet(
    DispositionModuleInputs inputs,
    DispositionModuleResult result,
    DatasheetExportFormat format,
  ) async {
    try {
      final rankings = ref
          .read(dispositionCalculationServiceProvider)
          .rankOffers(offers: _offers, targetSalePrice: inputs.targetSalePrice);
      final datasheet = ref
          .read(datasheetBuilderServiceProvider)
          .buildDispositionDatasheet(
            inputs: inputs,
            result: result,
            offers: rankings,
          );
      await ref.read(calculationDatasheetRepositoryProvider).saveDatasheet(datasheet);
      final export = ref.read(datasheetExportServiceProvider).prepareFromDatasheet(
            datasheet: datasheet,
            format: format,
          );
      final exportPath = await saveDatasheetArtifact(export);
      setState(() {
        _lastDatasheetId = datasheet.id;
        _lastExportFileName = exportPath ?? export.suggestedFileName;
        _error = null;
      });
    } catch (error) {
      setState(() => _error = 'Datasheet konnte nicht gespeichert werden: $error');
    }
  }

  Future<String?> _saveScenario(
    DispositionModuleInputs inputs,
    DispositionModuleResult result,
  ) async {
    try {
      final rankings = ref
          .read(dispositionCalculationServiceProvider)
          .rankOffers(offers: _offers, targetSalePrice: inputs.targetSalePrice);
      final scenarioId = await ref
          .read(calculationDatasheetRepositoryProvider)
          .saveDispositionScenario(
            inputs: inputs,
            result: result,
            offers: rankings,
            scenarioType: _scenarioType,
          );
      setState(() {
        _lastScenarioId = scenarioId;
        _error = null;
      });
      return scenarioId;
    } catch (error) {
      setState(() => _error = 'Verkaufsszenario konnte nicht gespeichert werden: $error');
      return null;
    }
  }

  Future<void> _closeHistoricalDeal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Historischen Deal abschliessen?'),
        content: const Text(
          'Der aktuelle Verkaufsfall wird als verkauft gespeichert. Property-Stammdaten werden dadurch nicht automatisch veraendert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Abschliessen'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _saleStatus = 'sold';
      _notesCtrl.text = [
        if (_notesCtrl.text.trim().isNotEmpty) _notesCtrl.text.trim(),
        'Historischer Deal abgeschlossen.',
      ].join('\n');
    });
    final closedInputs = _inputs();
    final closedResult = ref
        .read(dispositionCalculationServiceProvider)
        .calculate(closedInputs);
    final scenarioId = await _saveScenario(closedInputs, closedResult);
    if (!mounted) {
      return;
    }
    if (scenarioId == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Historischer Deal wurde abgeschlossen.')),
    );
  }

  Future<void> _showOfferDialog() async {
    final buyerCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '0');
    final probabilityCtrl = TextEditingController(text: '75');
    final riskCtrl = TextEditingController(text: '3');
    final ddDeadlineCtrl = TextEditingController();
    final exclusivityCtrl = TextEditingController();
    final paymentTargetCtrl = TextEditingController();
    final versionCtrl = TextEditingController(text: 'V1');
    final conditionsCtrl = TextEditingController();
    bool financingConfirmed = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Kaeuferangebot erfassen'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: buyerCtrl,
                        decoration: const InputDecoration(labelText: 'Kaeufername'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: versionCtrl,
                        decoration: const InputDecoration(labelText: 'Angebotsversion'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Angebotspreis',
                          prefixText: 'EUR ',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: probabilityCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Closing-Wahrscheinlichkeit',
                          suffixText: '%',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: riskCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Risiko 1 bis 5',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ddDeadlineCtrl,
                        decoration: const InputDecoration(labelText: 'Due-Diligence-Frist YYYY-MM-DD'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: exclusivityCtrl,
                        decoration: const InputDecoration(labelText: 'Exklusivitaet bis YYYY-MM-DD'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: paymentTargetCtrl,
                        decoration: const InputDecoration(labelText: 'Zahlungsziel / Closing'),
                      ),
                      CheckboxListTile(
                        value: financingConfirmed,
                        onChanged: (value) {
                          setDialogState(() {
                            financingConfirmed = value ?? false;
                          });
                        },
                        title: const Text('Finanzierungsnachweis vorhanden'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      TextField(
                        controller: conditionsCtrl,
                        decoration: const InputDecoration(labelText: 'Bedingungen / Notizen'),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(errorText!, style: TextStyle(color: context.semanticColors.error)),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final buyer = buyerCtrl.text.trim();
                    final price = parseDoubleFlexible(priceCtrl.text);
                    final probability = parseDoubleFlexible(probabilityCtrl.text);
                    final risk = parseIntFlexible(riskCtrl.text);
                    if (buyer.isEmpty ||
                        price == null ||
                        price <= 0 ||
                        probability == null ||
                        probability < 0 ||
                        probability > 100 ||
                        risk == null ||
                        risk < 1 ||
                        risk > 5) {
                      setDialogState(() {
                        errorText = 'Bitte Kaeufer, Preis, Wahrscheinlichkeit 0-100 und Risiko 1-5 pruefen.';
                      });
                      return;
                    }
                    setState(() {
                      _offers.add(
                        DispositionOfferInput(
                          buyerName: buyer,
                          offerPrice: price,
                          financingConfirmed: financingConfirmed,
                          closingProbability: probability / 100,
                          riskScore: risk,
                          dueDiligenceDeadline:
                              ddDeadlineCtrl.text.trim().isEmpty
                                  ? null
                                  : ddDeadlineCtrl.text.trim(),
                          exclusivityUntil:
                              exclusivityCtrl.text.trim().isEmpty
                                  ? null
                                  : exclusivityCtrl.text.trim(),
                          paymentTarget:
                              paymentTargetCtrl.text.trim().isEmpty
                                  ? null
                                  : paymentTargetCtrl.text.trim(),
                          offerVersion: versionCtrl.text.trim().isEmpty
                              ? null
                              : versionCtrl.text.trim(),
                          conditions: conditionsCtrl.text.trim().isEmpty
                              ? null
                              : conditionsCtrl.text.trim(),
                        ),
                      );
                    });
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    buyerCtrl.dispose();
    priceCtrl.dispose();
    probabilityCtrl.dispose();
    riskCtrl.dispose();
    ddDeadlineCtrl.dispose();
    exclusivityCtrl.dispose();
    paymentTargetCtrl.dispose();
    versionCtrl.dispose();
    conditionsCtrl.dispose();
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: TextField(controller: controller, decoration: InputDecoration(labelText: label)),
    );
  }

  Widget _shortField(TextEditingController controller, String label) {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _number(TextEditingController controller, String label, {String? prefixText, String? suffixText}) {
    return SizedBox(
      width: 190,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, prefixText: prefixText, suffixText: suffixText),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(child: Text(label)),
        Text(value, style: context.tabularNumericStyle.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _warningsInline(BuildContext context, List<String> warnings) {
    final semantic = context.semanticColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: semantic.warning.withValues(alpha: 0.12),
        border: Border.all(color: semantic.warning.withValues(alpha: 0.34)),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, color: semantic.warning),
            const SizedBox(width: 8),
            Text('Warnungen', style: Theme.of(context).textTheme.titleSmall),
          ]),
          const SizedBox(height: 8),
          ...warnings.map(
            (warning) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('- $warning'),
            ),
          ),
        ],
      ),
    );
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  double _double(TextEditingController controller) =>
      parseDoubleFlexible(controller.text) ?? 0;

  int _int(TextEditingController controller) =>
      parseIntFlexible(controller.text) ?? 0;

  String? _nullableText(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  String _currency(double value) => 'EUR ${value.toStringAsFixed(0)}';
  String _nullableCurrency(double? value) => value == null ? 'N/A' : _currency(value);
  String _nullablePercent(double? value) =>
      value == null ? 'N/A' : '${(value * 100).toStringAsFixed(2)}%';
}
