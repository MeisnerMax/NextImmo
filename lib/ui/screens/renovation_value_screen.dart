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

class RenovationValueScreen extends ConsumerStatefulWidget {
  const RenovationValueScreen({super.key});

  @override
  ConsumerState<RenovationValueScreen> createState() =>
      _RenovationValueScreenState();
}

class _RenovationValueScreenState
    extends ConsumerState<RenovationValueScreen> {
  final _projectCtrl = TextEditingController(text: 'Renovierungsszenario');
  final _projectTypeCtrl = TextEditingController();
  final _startDateCtrl = TextEditingController();
  final _plannedEndDateCtrl = TextEditingController();
  final _actualEndDateCtrl = TextEditingController();
  final _responsibleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _permitSubmittedDateCtrl = TextEditingController();
  final _permitApprovalDateCtrl = TextEditingController();
  final _subsidyProgramCtrl = TextEditingController();
  final _modernizationLegalBasisCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController(text: '0');
  final _actualCtrl = TextEditingController(text: '0');
  final _remainingCtrl = TextEditingController(text: '0');
  final _reserveCtrl = TextEditingController(text: '10');
  final _maintenanceShareCtrl = TextEditingController(text: '0');
  final _subsidiesCtrl = TextEditingController(text: '0');
  final _insuranceRecoveriesCtrl = TextEditingController(text: '0');
  final _nonRecoverableShareCtrl = TextEditingController(text: '0');
  final _modernizationCapCtrl = TextEditingController(text: '3');
  final _areaCtrl = TextEditingController(text: '0');
  final _rentNowCtrl = TextEditingController(text: '0');
  final _rentTargetCtrl = TextEditingController(text: '0');
  final _vacancyMonthsCtrl = TextEditingController(text: '0');
  final _noiBeforeCtrl = TextEditingController(text: '0');
  final _noiAfterCtrl = TextEditingController(text: '0');
  final _capBeforeCtrl = TextEditingController(text: '5');
  final _capAfterCtrl = TextEditingController(text: '5');
  final _investmentAfterCtrl = TextEditingController(text: '0');
  final _targetYieldCtrl = TextEditingController(text: '8');
  final _horizonCtrl = TextEditingController(text: '10');
  final _discountRateCtrl = TextEditingController(text: '6');
  final _plannedConstructionMonthsCtrl = TextEditingController(text: '0');
  final _actualConstructionMonthsCtrl = TextEditingController(text: '0');
  final _delayCostPerMonthCtrl = TextEditingController(text: '0');
  final _permitRiskCtrl = TextEditingController(text: '3');
  final _costRiskCtrl = TextEditingController(text: '3');
  final _rentLossRiskCtrl = TextEditingController(text: '3');
  final _technicalRiskCtrl = TextEditingController(text: '3');
  final _contractorRiskCtrl = TextEditingController(text: '3');
  final _riskBufferCtrl = TextEditingController(text: '10');

  final List<RenovationMeasureInput> _measures = <RenovationMeasureInput>[];
  String? _lastDatasheetId;
  String? _lastExportFileName;
  String? _lastScenarioId;
  String? _error;
  String _scenarioType = 'base';
  String _projectStatus = 'idea';
  String _priority = 'medium';
  String _permitStatus = 'not_required';
  bool _permitRequired = false;

  @override
  void initState() {
    super.initState();
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
        _projectCtrl,
        _projectTypeCtrl,
        _startDateCtrl,
        _plannedEndDateCtrl,
        _actualEndDateCtrl,
        _responsibleCtrl,
        _descriptionCtrl,
        _permitSubmittedDateCtrl,
        _permitApprovalDateCtrl,
        _subsidyProgramCtrl,
        _modernizationLegalBasisCtrl,
        _budgetCtrl,
        _actualCtrl,
        _remainingCtrl,
        _reserveCtrl,
        _maintenanceShareCtrl,
        _subsidiesCtrl,
        _insuranceRecoveriesCtrl,
        _nonRecoverableShareCtrl,
        _modernizationCapCtrl,
        _areaCtrl,
        _rentNowCtrl,
        _rentTargetCtrl,
        _vacancyMonthsCtrl,
        _noiBeforeCtrl,
        _noiAfterCtrl,
        _capBeforeCtrl,
        _capAfterCtrl,
        _investmentAfterCtrl,
        _targetYieldCtrl,
        _horizonCtrl,
        _discountRateCtrl,
        _plannedConstructionMonthsCtrl,
        _actualConstructionMonthsCtrl,
        _delayCostPerMonthCtrl,
        _permitRiskCtrl,
        _costRiskCtrl,
        _rentLossRiskCtrl,
        _technicalRiskCtrl,
        _contractorRiskCtrl,
        _riskBufferCtrl,
      ];

  @override
  Widget build(BuildContext context) {
    final inputs = _inputs();
    final result = ref.read(renovationCalculationServiceProvider).calculate(inputs);

    return ListFilterTemplate(
      title: 'Renovierung und Wertsteigerung',
      breadcrumbs: const <String>['Bewertung & Szenarien', 'Renovierung'],
      subtitle:
          'Kosten, Mietwirkung, Wertsteigerung, Payback und Risiko fuer Renovierungsprojekte.',
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
          label: const Text('Szenario speichern'),
        ),
        OutlinedButton.icon(
          onPressed: () => _transferToAcquisition(inputs, result),
          icon: const Icon(Icons.call_made_outlined),
          label: const Text('Wirkung in Ankauf uebernehmen'),
        ),
        OutlinedButton.icon(
          onPressed: () => _transferToDisposition(inputs, result),
          icon: const Icon(Icons.sell_outlined),
          label: const Text('Wirkung in Verkauf uebernehmen'),
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
              final results = _results(context, result);
              if (!wide) {
                return Column(children: [
                  form,
                  const SizedBox(height: AppSpacing.component),
                  results,
                ]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: form),
                  const SizedBox(width: AppSpacing.component),
                  Expanded(flex: 4, child: results),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.component),
          _measuresCard(context),
        ],
      ),
    );
  }

  Widget _measuresCard(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Massnahmen',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _showMeasureDialog,
                icon: const Icon(Icons.add),
                label: const Text('Massnahme erfassen'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          if (_measures.isEmpty)
            Text(
              'Noch keine Massnahmen erfasst.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const <DataColumn>[
                  DataColumn(label: Text('Typ')),
                  DataColumn(label: Text('Kategorie')),
                  DataColumn(label: Text('Gewerk')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Frist')),
                  DataColumn(label: Text('Verantwortlich')),
                  DataColumn(label: Text('Flaeche')),
                  DataColumn(label: Text('Budget')),
                  DataColumn(label: Text('Beauftragt')),
                  DataColumn(label: Text('Ist')),
                  DataColumn(label: Text('Rest')),
                  DataColumn(label: Text('Pflicht')),
                  DataColumn(label: Text('Wert')),
                  DataColumn(label: Text('Umlage')),
                  DataColumn(label: Text('')),
                ],
                rows: _measures
                    .asMap()
                    .entries
                    .map(
                      (entry) => DataRow(
                        cells: <DataCell>[
                          DataCell(Text(entry.value.measureType)),
                          DataCell(Text(entry.value.category)),
                          DataCell(Text(entry.value.trade ?? '')),
                          DataCell(Text(entry.value.status)),
                          DataCell(Text(entry.value.dueDate ?? '')),
                          DataCell(Text(entry.value.responsible ?? '')),
                          DataCell(Text('${entry.value.affectedAreaSqm.toStringAsFixed(0)} m2')),
                          DataCell(Text(_currency(entry.value.budgetAmount))),
                          DataCell(Text(_currency(entry.value.committedAmount))),
                          DataCell(Text(_currency(entry.value.actualAmount))),
                          DataCell(Text(_currency(entry.value.remainingAmount))),
                          DataCell(Text(entry.value.isRequired ? 'ja' : 'nein')),
                          DataCell(Text(entry.value.isValueAdd ? 'ja' : 'nein')),
                          DataCell(Text(entry.value.isRecoverable ? 'ja' : 'nein')),
                          DataCell(
                            IconButton(
                              tooltip: 'Entfernen',
                              onPressed: () {
                                setState(() {
                                  _measures.removeAt(entry.key);
                                });
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
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
          Text('Projekt und Annahmen', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.component),
          _field(_projectCtrl, 'Projektname'),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _shortField(_projectTypeCtrl, 'Projektart'),
              _shortField(_responsibleCtrl, 'Verantwortlich'),
              _shortField(_startDateCtrl, 'Startdatum YYYY-MM-DD'),
              _shortField(_plannedEndDateCtrl, 'Ende geplant YYYY-MM-DD'),
              _shortField(_actualEndDateCtrl, 'Ende Ist YYYY-MM-DD'),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          DropdownButtonFormField<String>(
            value: _projectStatus,
            items: const [
              DropdownMenuItem(value: 'idea', child: Text('Idee')),
              DropdownMenuItem(value: 'planned', child: Text('Geplant')),
              DropdownMenuItem(value: 'commissioned', child: Text('Beauftragt')),
              DropdownMenuItem(value: 'in_progress', child: Text('In Umsetzung')),
              DropdownMenuItem(value: 'completed', child: Text('Abgeschlossen')),
              DropdownMenuItem(value: 'aborted', child: Text('Abgebrochen')),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _projectStatus = value);
            },
            decoration: const InputDecoration(labelText: 'Projektstatus'),
          ),
          const SizedBox(height: AppSpacing.component),
          DropdownButtonFormField<String>(
            value: _priority,
            items: const [
              DropdownMenuItem(value: 'low', child: Text('Niedrig')),
              DropdownMenuItem(value: 'medium', child: Text('Mittel')),
              DropdownMenuItem(value: 'high', child: Text('Hoch')),
              DropdownMenuItem(value: 'critical', child: Text('Kritisch')),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _priority = value);
            },
            decoration: const InputDecoration(labelText: 'Prioritaet'),
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
          TextField(
            controller: _descriptionCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Beschreibung'),
          ),
          const SizedBox(height: AppSpacing.component),
          CheckboxListTile(
            value: _permitRequired,
            onChanged: (value) {
              setState(() => _permitRequired = value ?? false);
            },
            title: const Text('Genehmigung erforderlich'),
            contentPadding: EdgeInsets.zero,
          ),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  value: _permitStatus,
                  items: const [
                    DropdownMenuItem(value: 'not_required', child: Text('Nicht erforderlich')),
                    DropdownMenuItem(value: 'open', child: Text('Offen')),
                    DropdownMenuItem(value: 'submitted', child: Text('Eingereicht')),
                    DropdownMenuItem(value: 'approved', child: Text('Genehmigt')),
                    DropdownMenuItem(value: 'rejected', child: Text('Abgelehnt')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _permitStatus = value);
                  },
                  decoration: const InputDecoration(labelText: 'Genehmigungsstatus'),
                ),
              ),
              _shortField(_permitSubmittedDateCtrl, 'Antrag eingereicht YYYY-MM-DD'),
              _shortField(_permitApprovalDateCtrl, 'Genehmigt am YYYY-MM-DD'),
              _shortField(_subsidyProgramCtrl, 'Foerderprogramm'),
              _shortField(_modernizationLegalBasisCtrl, 'Rechtsbasis Mieterhoehung'),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _number(_budgetCtrl, 'Budget', prefixText: 'EUR '),
              _number(_actualCtrl, 'Ist-Kosten', prefixText: 'EUR '),
              _number(_remainingCtrl, 'Restkosten', prefixText: 'EUR '),
              _number(_reserveCtrl, 'Reserve', suffixText: '%'),
              _number(_maintenanceShareCtrl, 'Instandhaltungsanteil', prefixText: 'EUR '),
              _number(_subsidiesCtrl, 'Foerdermittel', prefixText: 'EUR '),
              _number(_insuranceRecoveriesCtrl, 'Erstattungen', prefixText: 'EUR '),
              _number(_nonRecoverableShareCtrl, 'nicht umlagefaehig', prefixText: 'EUR '),
              _number(_modernizationCapCtrl, 'Kappungsgrenze m2', prefixText: 'EUR '),
              _number(_areaCtrl, 'betroffene Flaeche', suffixText: 'm2'),
              _number(_rentNowCtrl, 'aktuelle Miete', prefixText: 'EUR '),
              _number(_rentTargetCtrl, 'Zielmiete', prefixText: 'EUR '),
              _number(_vacancyMonthsCtrl, 'Leerstandsmonate'),
              _number(_noiBeforeCtrl, 'NOI vorher', prefixText: 'EUR '),
              _number(_noiAfterCtrl, 'NOI nachher', prefixText: 'EUR '),
              _number(_capBeforeCtrl, 'Cap Rate vorher', suffixText: '%'),
              _number(_capAfterCtrl, 'Cap Rate nachher', suffixText: '%'),
              _number(_investmentAfterCtrl, 'Investition nachher', prefixText: 'EUR '),
              _number(_targetYieldCtrl, 'Zielrendite', suffixText: '%'),
              _number(_horizonCtrl, 'NPV-Horizont Jahre'),
              _number(_discountRateCtrl, 'Diskontzins', suffixText: '%'),
              _number(_plannedConstructionMonthsCtrl, 'Bauzeit geplant', suffixText: 'Mon.'),
              _number(_actualConstructionMonthsCtrl, 'Bauzeit Ist', suffixText: 'Mon.'),
              _number(_delayCostPerMonthCtrl, 'Verzoegerungskosten', prefixText: 'EUR/Mon. '),
              _number(_permitRiskCtrl, 'Genehmigungsrisiko 1-5'),
              _number(_costRiskCtrl, 'Kostenrisiko 1-5'),
              _number(_rentLossRiskCtrl, 'Mietausfallrisiko 1-5'),
              _number(_technicalRiskCtrl, 'Technisches Risiko 1-5'),
              _number(_contractorRiskCtrl, 'Handwerkerverfuegbarkeit 1-5'),
              _number(_riskBufferCtrl, 'Risikopuffer', suffixText: '%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _results(BuildContext context, RenovationModuleResult result) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ergebnis', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.component),
          _metric('Forecast Kosten', _currency(result.forecastTotalCosts)),
          _metric('Budgetabweichung', _currency(result.costVariance)),
          _metric('umlagefaehige Kosten', _currency(result.recoverableModernizationCosts)),
          _metric('Modellmieterhoehung', _currency(result.modeledAllowableRentIncreaseMonthly)),
          _metric('geplante Mieterhoehung', _currency(result.plannedRentIncreaseMonthly)),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Modernisierungsmieterhoehung ist eine wirtschaftliche Modellrechnung und ersetzt keine rechtliche Pruefung.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _metric('Mieteffekt Jahr 1', _currency(result.yearOneRentEffect)),
          _metric('Wertsteigerung', _nullableCurrency(result.valueUplift)),
          _metric('Net Value Uplift', _nullableCurrency(result.netValueUplift)),
          _metric('Return on Cost', _nullablePercent(result.returnOnCost)),
          _metric('Yield on Cost', _nullablePercent(result.yieldOnCost)),
          _metric('Renovierungs-NPV', _nullableCurrency(result.renovationNpv)),
          _metric('Renovierungs-IRR', _nullablePercent(result.renovationIrr)),
          _metric('Verzoegerung', '${result.delayDays} Tage'),
          _metric('Verzoegerungskosten', _currency(result.delayCosts)),
          _metric('Worst-Case-Kosten', _currency(result.worstCaseCosts)),
          _metric('Risiko-Score', '${result.riskScore}/100'),
          _metric('Payback', result.paybackYears == null ? 'N/A' : '${result.paybackYears!.toStringAsFixed(1)} Jahre'),
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

  RenovationModuleInputs _inputs() {
    return RenovationModuleInputs(
      projectName: _projectCtrl.text.trim().isEmpty
          ? 'Renovierungsszenario'
          : _projectCtrl.text.trim(),
      projectType:
          _projectTypeCtrl.text.trim().isEmpty ? null : _projectTypeCtrl.text.trim(),
      projectStatus: _projectStatus,
      startDate: _nullableText(_startDateCtrl),
      plannedEndDate: _nullableText(_plannedEndDateCtrl),
      actualEndDate: _nullableText(_actualEndDateCtrl),
      responsible: _nullableText(_responsibleCtrl),
      priority: _priority,
      description: _nullableText(_descriptionCtrl),
      permitRequired: _permitRequired,
      permitStatus: _permitStatus,
      permitSubmittedDate: _nullableText(_permitSubmittedDateCtrl),
      permitApprovalDate: _nullableText(_permitApprovalDateCtrl),
      subsidyProgram: _nullableText(_subsidyProgramCtrl),
      modernizationLegalBasis: _nullableText(_modernizationLegalBasisCtrl),
      budget: _double(_budgetCtrl),
      actualCosts: _double(_actualCtrl),
      expectedRemainingCosts: _double(_remainingCtrl),
      reservePercent: _double(_reserveCtrl) / 100,
      maintenanceShare: _double(_maintenanceShareCtrl),
      subsidies: _double(_subsidiesCtrl),
      insuranceRecoveries: _double(_insuranceRecoveriesCtrl),
      nonRecoverableCostShare: _double(_nonRecoverableShareCtrl),
      modernizationCapPerSqm: _double(_modernizationCapCtrl),
      affectedAreaSqm: _double(_areaCtrl),
      currentRentMonthly: _double(_rentNowCtrl),
      targetRentMonthly: _double(_rentTargetCtrl),
      vacancyMonthsDuringWorks: _double(_vacancyMonthsCtrl),
      noiBefore: _double(_noiBeforeCtrl),
      noiAfter: _double(_noiAfterCtrl),
      capRateBefore: _double(_capBeforeCtrl) / 100,
      capRateAfter: _double(_capAfterCtrl) / 100,
      totalInvestmentAfterRenovation: _double(_investmentAfterCtrl),
      targetYield: _double(_targetYieldCtrl) / 100,
      renovationHorizonYears: _int(_horizonCtrl),
      discountRate: _double(_discountRateCtrl) / 100,
      plannedConstructionMonths: _double(_plannedConstructionMonthsCtrl),
      actualConstructionMonths: _double(_actualConstructionMonthsCtrl),
      delayCostPerMonth: _double(_delayCostPerMonthCtrl),
      permitRisk: _int(_permitRiskCtrl),
      costRisk: _int(_costRiskCtrl),
      rentLossRisk: _int(_rentLossRiskCtrl),
      technicalRisk: _int(_technicalRiskCtrl),
      contractorAvailabilityRisk: _int(_contractorRiskCtrl),
      riskBufferPercent: _double(_riskBufferCtrl) / 100,
    );
  }

  Future<void> _saveDatasheet(
    RenovationModuleInputs inputs,
    RenovationModuleResult result,
    DatasheetExportFormat format,
  ) async {
    try {
      final datasheet = ref
          .read(datasheetBuilderServiceProvider)
          .buildRenovationDatasheet(
            inputs: inputs,
            result: result,
            measures: _measures,
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

  Future<void> _saveScenario(
    RenovationModuleInputs inputs,
    RenovationModuleResult result,
  ) async {
    try {
      final scenarioId = await ref
          .read(calculationDatasheetRepositoryProvider)
          .saveRenovationScenario(
            inputs: inputs,
            result: result,
            measures: _measures,
            scenarioType: _scenarioType,
          );
      setState(() {
        _lastScenarioId = scenarioId;
        _error = null;
      });
    } catch (error) {
      setState(() => _error = 'Szenario konnte nicht gespeichert werden: $error');
    }
  }

  void _transferToAcquisition(
    RenovationModuleInputs inputs,
    RenovationModuleResult result,
  ) {
    ref.read(renovationImpactTransferProvider.notifier).state =
        _impactTransfer(inputs, result);
    ref.read(globalPageProvider.notifier).state = GlobalPage.quickScreening;
  }

  void _transferToDisposition(
    RenovationModuleInputs inputs,
    RenovationModuleResult result,
  ) {
    ref.read(renovationImpactTransferProvider.notifier).state =
        _impactTransfer(inputs, result);
    ref.read(globalPageProvider.notifier).state = GlobalPage.dispositionExit;
  }

  RenovationImpactTransfer _impactTransfer(
    RenovationModuleInputs inputs,
    RenovationModuleResult result,
  ) {
    return RenovationImpactTransfer(
      projectName: inputs.projectName,
      forecastTotalCosts: result.forecastTotalCosts,
      currentRentMonthly: inputs.currentRentMonthly,
      targetRentMonthly: inputs.targetRentMonthly,
      plannedRentIncreaseMonthly: result.plannedRentIncreaseMonthly,
      noiAfter: inputs.noiAfter,
      valueAfter: result.valueAfter,
      netValueUplift: result.netValueUplift,
      renovationNpv: result.renovationNpv,
      renovationIrr: result.renovationIrr,
    );
  }

  Future<void> _showMeasureDialog() async {
    final typeCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final tradeCtrl = TextEditingController();
    final areaCtrl = TextEditingController(text: '0');
    final dueDateCtrl = TextEditingController();
    final responsibleCtrl = TextEditingController();
    final budgetCtrl = TextEditingController(text: '0');
    final committedCtrl = TextEditingController(text: '0');
    final actualCtrl = TextEditingController(text: '0');
    final remainingCtrl = TextEditingController(text: '0');
    final descriptionCtrl = TextEditingController();
    bool isRequired = false;
    bool isValueAdd = true;
    bool isRecoverable = false;
    bool isFundable = true;
    bool requiresPermit = false;
    String status = 'planned';
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Massnahme erfassen'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: typeCtrl,
                        decoration: const InputDecoration(labelText: 'Typ'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: categoryCtrl,
                        decoration: const InputDecoration(labelText: 'Kategorie'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tradeCtrl,
                        decoration: const InputDecoration(labelText: 'Gewerk'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: status,
                        items: const [
                          DropdownMenuItem(value: 'idea', child: Text('Idee')),
                          DropdownMenuItem(value: 'planned', child: Text('Geplant')),
                          DropdownMenuItem(value: 'commissioned', child: Text('Beauftragt')),
                          DropdownMenuItem(value: 'in_progress', child: Text('In Umsetzung')),
                          DropdownMenuItem(value: 'completed', child: Text('Abgeschlossen')),
                          DropdownMenuItem(value: 'aborted', child: Text('Abgebrochen')),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() => status = value);
                        },
                        decoration: const InputDecoration(labelText: 'Status'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: dueDateCtrl,
                        decoration: const InputDecoration(labelText: 'Frist YYYY-MM-DD'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: responsibleCtrl,
                        decoration: const InputDecoration(labelText: 'Verantwortlich'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: areaCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'betroffene Flaeche',
                          suffixText: 'm2',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: budgetCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Budget',
                          prefixText: 'EUR ',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: committedCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Beauftragt',
                          prefixText: 'EUR ',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: actualCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Ist-Kosten',
                          prefixText: 'EUR ',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: remainingCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Restkosten',
                          prefixText: 'EUR ',
                        ),
                      ),
                      CheckboxListTile(
                        value: isRequired,
                        onChanged: (value) {
                          setDialogState(() => isRequired = value ?? false);
                        },
                        title: const Text('notwendige Massnahme'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        value: isValueAdd,
                        onChanged: (value) {
                          setDialogState(() => isValueAdd = value ?? false);
                        },
                        title: const Text('wertsteigernd'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        value: isRecoverable,
                        onChanged: (value) {
                          setDialogState(() => isRecoverable = value ?? false);
                        },
                        title: const Text('umlagefaehig'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        value: isFundable,
                        onChanged: (value) {
                          setDialogState(() => isFundable = value ?? false);
                        },
                        title: const Text('finanzierbar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        value: requiresPermit,
                        onChanged: (value) {
                          setDialogState(() => requiresPermit = value ?? false);
                        },
                        title: const Text('genehmigungsrelevant'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      TextField(
                        controller: descriptionCtrl,
                        decoration: const InputDecoration(labelText: 'Beschreibung / Notizen'),
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
                    final type = typeCtrl.text.trim();
                    final category = categoryCtrl.text.trim();
                    final area = parseDoubleFlexible(areaCtrl.text);
                    final budget = parseDoubleFlexible(budgetCtrl.text);
                    final committed = parseDoubleFlexible(committedCtrl.text);
                    final actual = parseDoubleFlexible(actualCtrl.text);
                    final remaining = parseDoubleFlexible(remainingCtrl.text);
                    if (type.isEmpty ||
                        category.isEmpty ||
                        area == null ||
                        area < 0 ||
                        budget == null ||
                        committed == null ||
                        actual == null ||
                        remaining == null) {
                      setDialogState(() {
                        errorText = 'Bitte Typ, Kategorie, Flaeche und Kosten pruefen.';
                      });
                      return;
                    }
                    setState(() {
                      _measures.add(
                        RenovationMeasureInput(
                          measureType: type,
                          category: category,
                          trade: tradeCtrl.text.trim().isEmpty
                              ? null
                              : tradeCtrl.text.trim(),
                          description: descriptionCtrl.text.trim().isEmpty
                              ? null
                              : descriptionCtrl.text.trim(),
                          status: status,
                          dueDate: dueDateCtrl.text.trim().isEmpty
                              ? null
                              : dueDateCtrl.text.trim(),
                          responsible: responsibleCtrl.text.trim().isEmpty
                              ? null
                              : responsibleCtrl.text.trim(),
                          affectedAreaSqm: area,
                          budgetAmount: budget,
                          committedAmount: committed,
                          actualAmount: actual,
                          remainingAmount: remaining,
                          isRequired: isRequired,
                          isValueAdd: isValueAdd,
                          isRecoverable: isRecoverable,
                          isFundable: isFundable,
                          requiresPermit: requiresPermit,
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

    typeCtrl.dispose();
    categoryCtrl.dispose();
    tradeCtrl.dispose();
    areaCtrl.dispose();
    dueDateCtrl.dispose();
    responsibleCtrl.dispose();
    budgetCtrl.dispose();
    committedCtrl.dispose();
    actualCtrl.dispose();
    remainingCtrl.dispose();
    descriptionCtrl.dispose();
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
