import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/investment_modules.dart';
import '../../core/models/property.dart';
import '../../core/models/settings.dart';
import '../../core/models/valuation.dart';
import '../../core/services/datasheet_export_service.dart';
import '../components/nx_card.dart';
import '../components/nx_empty_state.dart';
import '../components/nx_status_badge.dart';
import '../state/app_state.dart';
import '../state/property_state.dart';
import '../state/scenario_state.dart';
import '../templates/list_filter_template.dart';
import '../theme/app_theme.dart';
import '../utils/datasheet_file_export.dart';
import '../utils/number_parse.dart';

class QuickScreeningScreen extends ConsumerStatefulWidget {
  const QuickScreeningScreen({super.key});

  @override
  ConsumerState<QuickScreeningScreen> createState() =>
      _QuickScreeningScreenState();
}

class _QuickScreeningScreenState extends ConsumerState<QuickScreeningScreen> {
  final _titleCtrl = TextEditingController(text: 'Neues Deal Screening');
  final _sourceCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _federalStateCtrl = TextEditingController();
  final _yearBuiltCtrl = TextEditingController();
  final _unitsCtrl = TextEditingController(text: '0');
  final _areaCtrl = TextEditingController(text: '0');
  final _commercialAreaCtrl = TextEditingController(text: '0');
  final _landAreaCtrl = TextEditingController(text: '0');
  final _energyClassCtrl = TextEditingController();
  final _purchaseCtrl = TextEditingController(text: '0');
  final _rentCtrl = TextEditingController(text: '0');
  final _marketRentCtrl = TextEditingController(text: '0');
  final _otherIncomeCtrl = TextEditingController(text: '0');
  final _vacancyCtrl = TextEditingController(text: '5');
  final _costsCtrl = TextEditingController(text: '0');
  final _closingCostPercentCtrl = TextEditingController(text: '10');
  final _brokerFeeCtrl = TextEditingController(text: '0');
  final _transferTaxCtrl = TextEditingController(text: '0');
  final _notaryCtrl = TextEditingController(text: '0');
  final _otherAcquisitionCostsCtrl = TextEditingController(text: '0');
  final _renovationBudgetCtrl = TextEditingController(text: '0');
  final _renovationSafetyCtrl = TextEditingController(text: '10');
  final _maintenanceCtrl = TextEditingController(text: '0');
  final _managementCtrl = TextEditingController(text: '0');
  final _insuranceCtrl = TextEditingController(text: '0');
  final _propertyTaxCtrl = TextEditingController(text: '0');
  final _otherCostsCtrl = TextEditingController(text: '0');
  final _equityCtrl = TextEditingController(text: '0');
  final _loanCtrl = TextEditingController(text: '0');
  final _interestCtrl = TextEditingController(text: '4');
  final _amortizationCtrl = TextEditingController(text: '2');
  final _loanTermCtrl = TextEditingController(text: '10');
  final _minimumCashflowCtrl = TextEditingController(text: '0');
  final _minimumGrossYieldCtrl = TextEditingController(text: '4');
  final _minimumCapRateCtrl = TextEditingController(text: '3.5');
  final _minimumCashOnCashCtrl = TextEditingController(text: '4');
  final _maxPurchasePricePerSqmCtrl = TextEditingController(text: '4000');
  final _maxLoanToValueCtrl = TextEditingController(text: '80');
  final _maxRenovationShareCtrl = TextEditingController(text: '25');
  final _targetCapRateCtrl = TextEditingController(text: '5');
  final _desiredMarginCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();

  String _propertyType = 'multifamily';
  String _condition = 'mittel';
  String _scenarioType = 'base';
  bool _monumentProtected = false;
  String? _selectedPropertyId;
  QuickScreeningRecord? _lastSaved;
  String? _lastDatasheetId;
  String? _lastExportFileName;
  bool _saving = false;
  String? _error;

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
    _titleCtrl,
    _sourceCtrl,
    _addressCtrl,
    _cityCtrl,
    _federalStateCtrl,
    _yearBuiltCtrl,
    _unitsCtrl,
    _areaCtrl,
    _commercialAreaCtrl,
    _landAreaCtrl,
    _energyClassCtrl,
    _purchaseCtrl,
    _rentCtrl,
    _marketRentCtrl,
    _otherIncomeCtrl,
    _vacancyCtrl,
    _costsCtrl,
    _closingCostPercentCtrl,
    _brokerFeeCtrl,
    _transferTaxCtrl,
    _notaryCtrl,
    _otherAcquisitionCostsCtrl,
    _renovationBudgetCtrl,
    _renovationSafetyCtrl,
    _maintenanceCtrl,
    _managementCtrl,
    _insuranceCtrl,
    _propertyTaxCtrl,
    _otherCostsCtrl,
    _equityCtrl,
    _loanCtrl,
    _interestCtrl,
    _amortizationCtrl,
    _loanTermCtrl,
    _minimumCashflowCtrl,
    _minimumGrossYieldCtrl,
    _minimumCapRateCtrl,
    _minimumCashOnCashCtrl,
    _maxPurchasePricePerSqmCtrl,
    _maxLoanToValueCtrl,
    _maxRenovationShareCtrl,
    _targetCapRateCtrl,
    _desiredMarginCtrl,
    _notesCtrl,
  ];

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final propertiesAsync = ref.watch(propertiesControllerProvider);
    final screeningsAsync = ref.watch(_quickScreeningsProvider);

    return ListFilterTemplate(
      title: 'Schnellbewertung',
      breadcrumbs: const <String>['Bewertung & Szenarien', 'Schnellbewertung'],
      subtitle:
          'Niedrigschwellige Erstpruefung fuer Angebote, Exposes und Marktchancen ohne Property-Pflicht.',
      primaryAction: ElevatedButton.icon(
        onPressed: _saving ? null : _saveScreening,
        icon: const Icon(Icons.save_outlined),
        label: Text(_saving ? 'Speichern...' : 'Szenario speichern'),
      ),
      secondaryActions: [
        OutlinedButton.icon(
          onPressed: _clearForm,
          icon: const Icon(Icons.refresh),
          label: const Text('Neu starten'),
        ),
        OutlinedButton.icon(
          onPressed: _saving
              ? null
              : () => _saveDatasheet(DatasheetExportFormat.json),
          icon: const Icon(Icons.description_outlined),
          label: const Text('JSON exportieren'),
        ),
        OutlinedButton.icon(
          onPressed: _saving
              ? null
              : () => _saveDatasheet(DatasheetExportFormat.csv),
          icon: const Icon(Icons.table_view_outlined),
          label: const Text('CSV exportieren'),
        ),
        OutlinedButton.icon(
          onPressed: _saving
              ? null
              : () => _saveDatasheet(DatasheetExportFormat.pdf),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('PDF exportieren'),
        ),
      ],
      scrollable: true,
      expandContent: false,
      content: settingsAsync.when(
        data: (settings) => _buildContent(
          context,
          settings: settings,
          propertiesAsync: propertiesAsync,
          screeningsAsync: screeningsAsync,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, _) =>
                Center(child: Text('Einstellungen konnten nicht geladen werden: $error')),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required AppSettingsRecord settings,
    required AsyncValue<List<PropertyRecord>> propertiesAsync,
    required AsyncValue<List<QuickScreeningRecord>> screeningsAsync,
  }) {
    final inputs = _draftAcquisitionInputs();
    final result = ref.read(acquisitionCalculationServiceProvider).calculateQuickEvaluation(
      inputs,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ...[
          NxCard(
            child: Row(
              children: [
                Icon(Icons.error_outline, color: context.semanticColors.error),
                const SizedBox(width: 12),
                Expanded(child: Text(_error!)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.component),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumn = constraints.maxWidth >= 1100;
            final form = _buildForm(context);
            final results = _buildResults(
              context,
              result: result,
              propertiesAsync: propertiesAsync,
            );
            if (!twoColumn) {
              return Column(
                children: [
                  form,
                  const SizedBox(height: AppSpacing.component),
                  results,
                ],
              );
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
        _buildRecentScreenings(context, screeningsAsync),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Deal-Daten', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.component),
          _field(_titleCtrl, 'Titel'),
          _field(_sourceCtrl, 'Quelle / Expose'),
          _field(_addressCtrl, 'Adresse oder Lagehinweis'),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _textField(_cityCtrl, 'Stadt'),
              _textField(_federalStateCtrl, 'Bundesland'),
              _numberField(_yearBuiltCtrl, 'Baujahr'),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          DropdownButtonFormField<String>(
            value: _propertyType,
            items: const [
              DropdownMenuItem(value: 'multifamily', child: Text('Mehrfamilienhaus')),
              DropdownMenuItem(value: 'apartment', child: Text('Wohnung')),
              DropdownMenuItem(value: 'commercial', child: Text('Gewerbe')),
              DropdownMenuItem(value: 'mixed_use', child: Text('Mixed Use')),
              DropdownMenuItem(value: 'development', child: Text('Entwicklung')),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _propertyType = value);
            },
            decoration: const InputDecoration(labelText: 'Objektart'),
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
            value: _condition,
            items: const [
              DropdownMenuItem(value: 'sehr gut', child: Text('sehr gut')),
              DropdownMenuItem(value: 'gut', child: Text('gut')),
              DropdownMenuItem(value: 'mittel', child: Text('mittel')),
              DropdownMenuItem(value: 'sanierungsbeduerftig', child: Text('sanierungsbeduerftig')),
              DropdownMenuItem(value: 'kritisch', child: Text('kritisch')),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _condition = value);
            },
            decoration: const InputDecoration(labelText: 'Zustand'),
          ),
          CheckboxListTile(
            value: _monumentProtected,
            onChanged: (value) {
              setState(() => _monumentProtected = value ?? false);
            },
            title: const Text('Denkmalschutz'),
            contentPadding: EdgeInsets.zero,
          ),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _numberField(_unitsCtrl, 'Einheiten'),
              _numberField(_areaCtrl, 'Wohnflaeche m2'),
              _numberField(_commercialAreaCtrl, 'Gewerbeflaeche m2'),
              _numberField(_landAreaCtrl, 'Grundstueck m2'),
              _textField(_energyClassCtrl, 'Energieklasse'),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Text('Kauf und Renovierung', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _numberField(_purchaseCtrl, 'Kaufpreis', prefixText: 'EUR '),
              _numberField(_closingCostPercentCtrl, 'Kaufnebenkosten', suffixText: '%'),
              _numberField(_brokerFeeCtrl, 'Makler', prefixText: 'EUR '),
              _numberField(_transferTaxCtrl, 'Grunderwerbsteuer', prefixText: 'EUR '),
              _numberField(_notaryCtrl, 'Notar / Grundbuch', prefixText: 'EUR '),
              _numberField(_otherAcquisitionCostsCtrl, 'sonst. Erwerbskosten', prefixText: 'EUR '),
              _numberField(_renovationBudgetCtrl, 'Renovierungsbudget', prefixText: 'EUR '),
              _numberField(_renovationSafetyCtrl, 'Renovierungsreserve', suffixText: '%'),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Text('Miete und Kosten', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _numberField(_rentCtrl, 'Sollmiete mtl.', prefixText: 'EUR '),
              _numberField(_marketRentCtrl, 'Marktmiete m2', prefixText: 'EUR '),
              _numberField(_otherIncomeCtrl, 'sonst. Einnahmen', prefixText: 'EUR '),
              _numberField(_vacancyCtrl, 'Leerstand', suffixText: '%'),
              _numberField(_costsCtrl, 'Kosten mtl.', prefixText: 'EUR '),
              _numberField(_maintenanceCtrl, 'Instandhaltung m2 p.a.', prefixText: 'EUR '),
              _numberField(_managementCtrl, 'Verwaltung mtl.', prefixText: 'EUR '),
              _numberField(_insuranceCtrl, 'Versicherung mtl.', prefixText: 'EUR '),
              _numberField(_propertyTaxCtrl, 'Grundsteuer mtl.', prefixText: 'EUR '),
              _numberField(_otherCostsCtrl, 'sonst. Kosten mtl.', prefixText: 'EUR '),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Text('Finanzierung', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _numberField(_equityCtrl, 'Eigenkapital', prefixText: 'EUR '),
              _numberField(_loanCtrl, 'Darlehen', prefixText: 'EUR '),
              _numberField(_interestCtrl, 'Zins', suffixText: '%'),
              _numberField(_amortizationCtrl, 'Tilgung', suffixText: '%'),
              _numberField(_loanTermCtrl, 'Laufzeit Jahre'),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Text('Zielkriterien', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _numberField(_minimumCashflowCtrl, 'Mindest-Cashflow', prefixText: 'EUR '),
              _numberField(_minimumGrossYieldCtrl, 'Mindest-Bruttorendite', suffixText: '%'),
              _numberField(_minimumCapRateCtrl, 'Mindest-Cap-Rate', suffixText: '%'),
              _numberField(_minimumCashOnCashCtrl, 'Mindest-CoC', suffixText: '%'),
              _numberField(_maxPurchasePricePerSqmCtrl, 'Max. Kaufpreis m2', prefixText: 'EUR '),
              _numberField(_maxLoanToValueCtrl, 'Max. LTV', suffixText: '%'),
              _numberField(_maxRenovationShareCtrl, 'Max. Renovierungsanteil', suffixText: '%'),
              _numberField(_targetCapRateCtrl, 'Ziel-Cap-Rate', suffixText: '%'),
              _numberField(_desiredMarginCtrl, 'Zielmarge', prefixText: 'EUR '),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          TextField(
            controller: _notesCtrl,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Notizen'),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(
    BuildContext context, {
    required AcquisitionQuickResult result,
    required AsyncValue<List<PropertyRecord>> propertiesAsync,
  }) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ergebnis',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const NxStatusBadge(label: 'ohne Property-Pflicht', kind: NxBadgeKind.info),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          _metric(context, 'Kaufpreis pro m2', _nullableCurrency(result.purchasePricePerSqm)),
          _metric(context, 'Gesamtinvestition', _currency(result.totalInvestment)),
          _metric(context, 'Ist-Rendite', _nullablePercent(result.grossInitialYield)),
          _metric(context, 'Soll-Rendite', _nullablePercent(result.netInitialYield)),
          _metric(context, 'NOI', _currency(result.noi)),
          _metric(
            context,
            'Cashflow',
            _currency(result.cashflowBeforeTax / 12),
          ),
          _metric(context, 'Cash on Cash', _nullablePercent(result.cashOnCash)),
          _metric(context, 'LTV', _nullablePercent(result.loanToValue)),
          _metric(
            context,
            'Max. Kaufpreis',
            _nullableCurrency(result.maxReasonablePurchasePrice),
          ),
          _metric(context, 'Empfehlung', result.recommendation),
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.component),
            _warningsInline(context, result.warnings),
          ],
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: result.criteria
                .map(
                  (item) => NxStatusBadge(
                    label: item.label,
                    kind: _badgeKindForTrafficLight(item.status),
                  ),
                )
                .toList(growable: false),
          ),
          if (_lastDatasheetId != null) ...[
            const SizedBox(height: 8),
            Text(
              'Letztes Datasheet gespeichert: $_lastDatasheetId',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_lastExportFileName != null) ...[
            const SizedBox(height: 4),
            Text(
              'Letzter Export: $_lastExportFileName',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.component),
          Divider(color: context.semanticColors.border),
          const SizedBox(height: AppSpacing.component),
          Text(
            'Optional ueberfuehren',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          propertiesAsync.when(
            data: (properties) {
              if (properties.isEmpty) {
                return const Text('Keine Property vorhanden.');
              }
              return DropdownButtonFormField<String>(
                value: properties.any((p) => p.id == _selectedPropertyId)
                    ? _selectedPropertyId
                    : null,
                isExpanded: true,
                items: properties
                    .map(
                      (property) => DropdownMenuItem<String>(
                        value: property.id,
                        child: Text(property.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _selectedPropertyId = value),
                decoration: const InputDecoration(labelText: 'Bestehende Property'),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text('Properties konnten nicht geladen werden: $error'),
          ),
          const SizedBox(height: AppSpacing.component),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  _lastSaved == null || _selectedPropertyId == null || _saving
                      ? null
                      : _convertToIntensiveValuation,
              icon: const Icon(Icons.call_split_outlined),
              label: const Text('Als Intensivbewertung anlegen'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  _lastSaved == null || _saving
                      ? null
                      : _createPropertyFromScreening,
              icon: const Icon(Icons.add_home_work_outlined),
              label: const Text('Neue Property anlegen'),
            ),
          ),
          if (_lastSaved == null) ...[
            const SizedBox(height: 8),
            Text(
              'Speichere das Screening, bevor du es verknuepfst.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentScreenings(
    BuildContext context,
    AsyncValue<List<QuickScreeningRecord>> screeningsAsync,
  ) {
    return screeningsAsync.when(
      data: (screenings) {
        if (screenings.isEmpty) {
          return const NxEmptyState(
            title: 'Noch keine Schnellbewertungen',
            description:
                'Gespeicherte Erstpruefungen erscheinen hier und bleiben unabhaengig von Properties.',
            icon: Icons.speed_outlined,
          );
        }
        return NxCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Text(
                  'Gespeicherte Schnellbewertungen',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Divider(height: 1, color: context.semanticColors.border),
              ...screenings.map(
                (screening) => ListTile(
                  leading: Icon(
                    screening.linkedScenarioId == null
                        ? Icons.speed_outlined
                        : Icons.link_outlined,
                  ),
                  title: Text(screening.title),
                  subtitle: Text(
                    [
                      if (screening.sourceLabel != null) screening.sourceLabel!,
                      _currency(screening.purchasePrice),
                      if (screening.linkedScenarioId != null) 'ueberfuehrt',
                    ].join(' | '),
                  ),
                  trailing: Text(_percent(_capRate(screening))),
                  onTap: () => _loadScreening(screening),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const LinearProgressIndicator(),
      error:
          (error, _) =>
              NxEmptyState(title: 'Schnellbewertungen nicht verfuegbar', description: '$error'),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    String? prefixText,
    String? suffixText,
  }) {
    return SizedBox(
      width: 190,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefixText,
          suffixText: suffixText,
        ),
      ),
    );
  }

  Widget _textField(TextEditingController controller, String label) {
    return SizedBox(
      width: 190,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: context.tabularNumericStyle.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: semantic.warning),
              const SizedBox(width: 8),
              Text(
                'Warnungen',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
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

  AcquisitionQuickInputs _draftAcquisitionInputs() {
    return AcquisitionQuickInputs(
      objectName:
          _titleCtrl.text.trim().isEmpty ? 'Unbenannt' : _titleCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      federalState: _federalStateCtrl.text.trim().isEmpty
          ? null
          : _federalStateCtrl.text.trim(),
      propertyType: _propertyType,
      yearBuilt: parseIntFlexible(_yearBuiltCtrl.text),
      residentialAreaSqm: _double(_areaCtrl),
      commercialAreaSqm: _double(_commercialAreaCtrl),
      landAreaSqm: _double(_landAreaCtrl),
      units: _int(_unitsCtrl),
      vacancyPercent: _double(_vacancyCtrl) / 100,
      condition: _condition,
      monumentProtected: _monumentProtected,
      energyClass: _energyClassCtrl.text.trim().isEmpty
          ? null
          : _energyClassCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      offerPrice: _double(_purchaseCtrl),
      closingCostPercent: _double(_closingCostPercentCtrl) / 100,
      brokerFee: _double(_brokerFeeCtrl),
      transferTax: _double(_transferTaxCtrl),
      notaryAndLandRegistry: _double(_notaryCtrl),
      otherAcquisitionCosts: _double(_otherAcquisitionCostsCtrl),
      renovationBudget: _double(_renovationBudgetCtrl),
      renovationSafetyPercent: _double(_renovationSafetyCtrl) / 100,
      currentColdRentMonthly: _double(_rentCtrl),
      marketRentPerSqm: _double(_marketRentCtrl),
      otherIncomeMonthly: _double(_otherIncomeCtrl),
      nonRecoverableCostsMonthly: _double(_costsCtrl),
      maintenancePerSqmYear: _double(_maintenanceCtrl),
      managementCostsMonthly: _double(_managementCtrl),
      insuranceMonthly: _double(_insuranceCtrl),
      propertyTaxMonthly: _double(_propertyTaxCtrl),
      otherCostsMonthly: _double(_otherCostsCtrl),
      equity: _double(_equityCtrl),
      loanAmount: _double(_loanCtrl),
      interestRatePercent: _double(_interestCtrl) / 100,
      amortizationPercent: _double(_amortizationCtrl) / 100,
      loanTermYears: _int(_loanTermCtrl),
      minimumCashflow: _double(_minimumCashflowCtrl),
      minimumGrossYield: _double(_minimumGrossYieldCtrl) / 100,
      minimumCapRate: _double(_minimumCapRateCtrl) / 100,
      minimumCashOnCash: _double(_minimumCashOnCashCtrl) / 100,
      maxPurchasePricePerSqm: _double(_maxPurchasePricePerSqmCtrl),
      maxLoanToValue: _double(_maxLoanToValueCtrl) / 100,
      maxRenovationShare: _double(_maxRenovationShareCtrl) / 100,
      targetCapRate: _double(_targetCapRateCtrl) / 100,
      desiredMargin: _double(_desiredMarginCtrl),
    );
  }

  Future<void> _saveDatasheet(DatasheetExportFormat format) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final inputs = _draftAcquisitionInputs();
      final result = ref
          .read(acquisitionCalculationServiceProvider)
          .calculateQuickEvaluation(inputs);
      final datasheet = ref
          .read(datasheetBuilderServiceProvider)
          .buildAcquisitionQuickDatasheet(inputs: inputs, result: result);
      await ref.read(calculationDatasheetRepositoryProvider).saveDatasheet(
            datasheet,
          );
      final export = ref.read(datasheetExportServiceProvider).prepareFromDatasheet(
            datasheet: datasheet,
            format: format,
          );
      final exportPath = await saveDatasheetArtifact(export);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastDatasheetId = datasheet.id;
        _lastExportFileName = exportPath ?? export.suggestedFileName;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Datasheet konnte nicht gespeichert werden: $error';
        _saving = false;
      });
    }
  }

  void _applyPendingRenovationImpact() {
    final transfer = ref.read(renovationImpactTransferProvider);
    if (transfer == null) {
      return;
    }
    _renovationBudgetCtrl.text = transfer.forecastTotalCosts.toStringAsFixed(0);
    if (transfer.targetRentMonthly > 0) {
      _rentCtrl.text = transfer.targetRentMonthly.toStringAsFixed(0);
    }
    if (transfer.currentRentMonthly > 0 && transfer.targetRentMonthly > 0) {
      _notesCtrl.text = [
        if (_notesCtrl.text.trim().isNotEmpty) _notesCtrl.text.trim(),
        'Renovierungswirkung uebernommen: ${transfer.projectName}',
        'Miete vorher: ${transfer.currentRentMonthly.toStringAsFixed(0)} EUR mtl.',
        'Zielmiete nach Renovierung: ${transfer.targetRentMonthly.toStringAsFixed(0)} EUR mtl.',
        if (transfer.renovationNpv != null)
          'Renovierungs-NPV: ${transfer.renovationNpv!.toStringAsFixed(0)} EUR',
        if (transfer.renovationIrr != null)
          'Renovierungs-IRR: ${(transfer.renovationIrr! * 100).toStringAsFixed(2)}%',
      ].join('\n');
    }
    ref.read(renovationImpactTransferProvider.notifier).state = null;
  }

  Future<void> _saveScreening() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final record = await ref
          .read(valuationDataRepositoryProvider)
          .createQuickScreening(
            title: _titleCtrl.text.trim().isEmpty
                ? 'Unbenanntes Screening'
                : _titleCtrl.text.trim(),
            sourceLabel: _sourceCtrl.text,
            addressText: _addressCtrl.text,
            propertyType: _propertyType,
            units: _int(_unitsCtrl),
            areaSqm: _double(_areaCtrl),
            purchasePrice: _double(_purchaseCtrl),
            rentMonthlyTotal: _double(_rentCtrl),
            vacancyPercent: _double(_vacancyCtrl) / 100,
            operatingCostsMonthly: _double(_costsCtrl),
            notes: _notesCtrl.text,
          );
      final acquisitionInputs = _draftAcquisitionInputs();
      final acquisitionResult = ref
          .read(acquisitionCalculationServiceProvider)
          .calculateQuickEvaluation(acquisitionInputs);
      await ref
          .read(calculationDatasheetRepositoryProvider)
          .saveAcquisitionQuickEvaluation(
            id: record.id,
            title: record.title,
            inputs: acquisitionInputs,
            result: acquisitionResult,
            scenarioType: _scenarioType,
          );
      ref.invalidate(_quickScreeningsProvider);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastSaved = record;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Schnellbewertung konnte nicht gespeichert werden: $error';
        _saving = false;
      });
    }
  }

  Future<void> _convertToIntensiveValuation() async {
    final screening = _lastSaved;
    final propertyId = _selectedPropertyId;
    if (screening == null || propertyId == null) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final controller = ref.read(
        scenariosByPropertyProvider(propertyId).notifier,
      );
      final scenario = await controller.create(
        name: '${screening.title} Intensivbewertung',
        strategyType: 'quick_screening',
      );
      if (scenario == null) {
        throw StateError('Szenario konnte nicht erstellt werden.');
      }
      final settings = await ref.read(inputsRepositoryProvider).getSettings();
      final inputs = ref
          .read(valuationDataRepositoryProvider)
          .inputsFromQuickScreening(
            screening: screening,
            scenarioId: scenario.id,
            settings: settings,
          );
      await ref.read(inputsRepositoryProvider).upsertInputs(inputs);
      await ref.read(valuationDataRepositoryProvider).markManualAdjustments(
        scenarioId: scenario.id,
        fields: const <String>[
          'purchasePrice',
          'rentMonthlyTotal',
          'grossAreaSqm',
          'lettableAreaSqm',
          'vacancyPercent',
          'otherExpensesMonthly',
        ],
      );
      await ref.read(valuationDataRepositoryProvider).linkQuickScreening(
        quickScreeningId: screening.id,
        propertyId: propertyId,
        scenarioId: scenario.id,
      );
      ref.invalidate(_quickScreeningsProvider);
      ref.read(selectedPropertyIdProvider.notifier).state = propertyId;
      ref.read(selectedScenarioIdProvider.notifier).state = scenario.id;
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.inputs;
      ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Ueberfuehrung konnte nicht abgeschlossen werden: $error';
        _saving = false;
      });
    }
  }

  Future<void> _createPropertyFromScreening() async {
    final screening = _lastSaved;
    if (screening == null) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final inputs = _draftAcquisitionInputs();
      final result = await ref
          .read(propertiesControllerProvider.notifier)
          .createPropertyWithBaseScenarioResult(
            name: inputs.objectName,
            address: inputs.address ?? inputs.objectName,
            city: inputs.city ?? 'Unbekannt',
            zip: 'n/a',
            country: 'DE',
            propertyType: inputs.propertyType,
            units: inputs.units,
            sqft: inputs.totalAreaSqm,
            yearBuilt: inputs.yearBuilt,
            notes: [
              if (inputs.notes != null) inputs.notes!,
              if (_sourceCtrl.text.trim().isNotEmpty)
                'Quelle: ${_sourceCtrl.text.trim()}',
              'Aus Schnellbewertung uebernommen.',
            ].join('\n'),
            strategyType: 'quick_screening',
            purchasePrice: inputs.offerPrice,
            rentMonthly: inputs.currentColdRentMonthly,
            rehabBudget: inputs.renovationBudget,
            financingMode: inputs.loanAmount > 0 ? 'loan' : 'cash',
          );
      if (result == null) {
        throw StateError('Property konnte nicht erstellt werden.');
      }
      final acquisitionResult = ref
          .read(acquisitionCalculationServiceProvider)
          .calculateQuickEvaluation(inputs);
      await ref
          .read(calculationDatasheetRepositoryProvider)
          .saveAcquisitionQuickEvaluation(
            id: screening.id,
            title: screening.title,
            inputs: inputs,
            result: acquisitionResult,
            propertyId: result.property.id,
            scenarioId: result.scenario.id,
            scenarioType: _scenarioType,
          );
      await ref.read(valuationDataRepositoryProvider).linkQuickScreening(
            quickScreeningId: screening.id,
            propertyId: result.property.id,
            scenarioId: result.scenario.id,
          );
      ref.invalidate(_quickScreeningsProvider);
      ref.read(selectedPropertyIdProvider.notifier).state = result.property.id;
      ref.read(selectedScenarioIdProvider.notifier).state = result.scenario.id;
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.inputs;
      ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedPropertyId = result.property.id;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Property konnte nicht aus Schnellbewertung angelegt werden: $error';
        _saving = false;
      });
    }
  }

  void _loadScreening(QuickScreeningRecord screening) {
    final inputData = _decodeAcquisitionInput(screening.acquisitionInputJson);
    if (inputData != null) {
      _loadScreeningFromInput(screening, inputData);
      return;
    }

    _titleCtrl.text = screening.title;
    _sourceCtrl.text = screening.sourceLabel ?? '';
    _addressCtrl.text = screening.addressText ?? '';
    _cityCtrl.clear();
    _federalStateCtrl.clear();
    _yearBuiltCtrl.clear();
    _propertyType = _allowedPropertyType(screening.propertyType);
    _scenarioType = 'base';
    _condition = 'mittel';
    _monumentProtected = false;
    _unitsCtrl.text = screening.units.toString();
    _areaCtrl.text = screening.areaSqm.toStringAsFixed(0);
    _commercialAreaCtrl.text = '0';
    _landAreaCtrl.text = '0';
    _energyClassCtrl.clear();
    _purchaseCtrl.text = screening.purchasePrice.toStringAsFixed(0);
    _rentCtrl.text = screening.rentMonthlyTotal.toStringAsFixed(0);
    _marketRentCtrl.text = screening.areaSqm > 0
        ? (screening.rentMonthlyTotal / screening.areaSqm).toStringAsFixed(2)
        : '0';
    _otherIncomeCtrl.text = '0';
    _vacancyCtrl.text = (screening.vacancyPercent * 100).toStringAsFixed(1);
    _costsCtrl.text = screening.operatingCostsMonthly.toStringAsFixed(0);
    _closingCostPercentCtrl.text = '10';
    _brokerFeeCtrl.text = '0';
    _transferTaxCtrl.text = '0';
    _notaryCtrl.text = '0';
    _otherAcquisitionCostsCtrl.text = '0';
    _renovationBudgetCtrl.text = '0';
    _renovationSafetyCtrl.text = '10';
    _maintenanceCtrl.text = '0';
    _managementCtrl.text = '0';
    _insuranceCtrl.text = '0';
    _propertyTaxCtrl.text = '0';
    _otherCostsCtrl.text = '0';
    _equityCtrl.text = (screening.purchasePrice * 0.25).toStringAsFixed(0);
    _loanCtrl.text = (screening.purchasePrice * 0.75).toStringAsFixed(0);
    _interestCtrl.text = '4';
    _amortizationCtrl.text = '2';
    _loanTermCtrl.text = '10';
    _minimumCashflowCtrl.text = '0';
    _minimumGrossYieldCtrl.text = '4';
    _minimumCapRateCtrl.text = '3.5';
    _minimumCashOnCashCtrl.text = '4';
    _maxPurchasePricePerSqmCtrl.text = '4000';
    _maxLoanToValueCtrl.text = '80';
    _maxRenovationShareCtrl.text = '25';
    _targetCapRateCtrl.text = '5';
    _desiredMarginCtrl.text = '0';
    _notesCtrl.text = screening.notes ?? '';
    setState(() => _lastSaved = screening);
  }

  void _loadScreeningFromInput(
    QuickScreeningRecord screening,
    Map<String, Object?> input,
  ) {
    _titleCtrl.text = _stringInput(input, 'object_name', screening.title);
    _sourceCtrl.text = screening.sourceLabel ?? '';
    _addressCtrl.text = _stringInput(
      input,
      'address',
      screening.addressText ?? '',
    );
    _cityCtrl.text = _stringInput(input, 'city', '');
    _federalStateCtrl.text = _stringInput(input, 'federal_state', '');
    _yearBuiltCtrl.text = _intInput(input, 'year_built');
    _propertyType = _allowedPropertyType(
      _stringInput(input, 'property_type', screening.propertyType),
    );
    _scenarioType = _allowedScenarioType(
      screening.acquisitionScenarioType ?? 'base',
    );
    _condition = _allowedCondition(_stringInput(input, 'condition', 'mittel'));
    _monumentProtected = input['monument_protected'] == true;
    _unitsCtrl.text = _intInput(input, 'units', fallback: '${screening.units}');
    _areaCtrl.text = _numberInput(input, 'residential_area_sqm');
    _commercialAreaCtrl.text = _numberInput(input, 'commercial_area_sqm');
    _landAreaCtrl.text = _numberInput(input, 'land_area_sqm');
    _energyClassCtrl.text = _stringInput(input, 'energy_class', '');
    _purchaseCtrl.text = _numberInput(input, 'offer_price');
    _rentCtrl.text = _numberInput(input, 'current_cold_rent_monthly');
    _marketRentCtrl.text = _numberInput(input, 'market_rent_per_sqm');
    _otherIncomeCtrl.text = _numberInput(input, 'other_income_monthly');
    _vacancyCtrl.text = _percentInput(input, 'vacancy_percent');
    _costsCtrl.text = _numberInput(input, 'non_recoverable_costs_monthly');
    _closingCostPercentCtrl.text = _percentInput(input, 'closing_cost_percent');
    _brokerFeeCtrl.text = _numberInput(input, 'broker_fee');
    _transferTaxCtrl.text = _numberInput(input, 'transfer_tax');
    _notaryCtrl.text = _numberInput(input, 'notary_and_land_registry');
    _otherAcquisitionCostsCtrl.text =
        _numberInput(input, 'other_acquisition_costs');
    _renovationBudgetCtrl.text = _numberInput(input, 'renovation_budget');
    _renovationSafetyCtrl.text =
        _percentInput(input, 'renovation_safety_percent');
    _maintenanceCtrl.text = _numberInput(input, 'maintenance_per_sqm_year');
    _managementCtrl.text = _numberInput(input, 'management_costs_monthly');
    _insuranceCtrl.text = _numberInput(input, 'insurance_monthly');
    _propertyTaxCtrl.text = _numberInput(input, 'property_tax_monthly');
    _otherCostsCtrl.text = _numberInput(input, 'other_costs_monthly');
    _equityCtrl.text = _numberInput(input, 'equity');
    _loanCtrl.text = _numberInput(input, 'loan_amount');
    _interestCtrl.text = _percentInput(input, 'interest_rate_percent');
    _amortizationCtrl.text = _percentInput(input, 'amortization_percent');
    _loanTermCtrl.text = _intInput(input, 'loan_term_years');
    _minimumCashflowCtrl.text = _numberInput(input, 'minimum_cashflow');
    _minimumGrossYieldCtrl.text = _percentInput(input, 'minimum_gross_yield');
    _minimumCapRateCtrl.text = _percentInput(input, 'minimum_cap_rate');
    _minimumCashOnCashCtrl.text = _percentInput(input, 'minimum_cash_on_cash');
    _maxPurchasePricePerSqmCtrl.text =
        _numberInput(input, 'max_purchase_price_per_sqm');
    _maxLoanToValueCtrl.text = _percentInput(input, 'max_loan_to_value');
    _maxRenovationShareCtrl.text =
        _percentInput(input, 'max_renovation_share');
    _targetCapRateCtrl.text = _percentInput(input, 'target_cap_rate');
    _desiredMarginCtrl.text = _numberInput(input, 'desired_margin');
    _notesCtrl.text = _stringInput(input, 'notes', screening.notes ?? '');
    setState(() => _lastSaved = screening);
  }

  Map<String, Object?>? _decodeAcquisitionInput(String? jsonText) {
    if (jsonText == null || jsonText.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _stringInput(
    Map<String, Object?> input,
    String key,
    String fallback,
  ) {
    final value = input[key];
    if (value == null) {
      return fallback;
    }
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _numberInput(
    Map<String, Object?> input,
    String key, {
    String fallback = '0',
  }) {
    final value = (input[key] as num?)?.toDouble();
    if (value == null) {
      return fallback;
    }
    return _compactNumber(value);
  }

  String _percentInput(Map<String, Object?> input, String key) {
    final value = (input[key] as num?)?.toDouble();
    if (value == null) {
      return '0';
    }
    return _compactNumber(value * 100);
  }

  String _intInput(
    Map<String, Object?> input,
    String key, {
    String fallback = '',
  }) {
    final value = (input[key] as num?)?.toInt();
    return value == null ? fallback : '$value';
  }

  String _compactNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  String _allowedPropertyType(String value) {
    const allowed = <String>{
      'multifamily',
      'apartment',
      'commercial',
      'mixed_use',
      'development',
    };
    return allowed.contains(value) ? value : 'multifamily';
  }

  String _allowedScenarioType(String value) {
    const allowed = <String>{'base', 'best', 'worst', 'custom'};
    return allowed.contains(value) ? value : 'base';
  }

  String _allowedCondition(String value) {
    const allowed = <String>{'sehr gut', 'gut', 'mittel', 'sanierungsbeduerftig', 'kritisch'};
    return allowed.contains(value) ? value : 'mittel';
  }

  void _clearForm() {
    _titleCtrl.text = 'Neues Deal Screening';
    _sourceCtrl.clear();
    _addressCtrl.clear();
    _cityCtrl.clear();
    _federalStateCtrl.clear();
    _yearBuiltCtrl.clear();
    _propertyType = 'multifamily';
    _scenarioType = 'base';
    _condition = 'mittel';
    _monumentProtected = false;
    _unitsCtrl.text = '0';
    _areaCtrl.text = '0';
    _commercialAreaCtrl.text = '0';
    _landAreaCtrl.text = '0';
    _energyClassCtrl.clear();
    _purchaseCtrl.text = '0';
    _rentCtrl.text = '0';
    _marketRentCtrl.text = '0';
    _otherIncomeCtrl.text = '0';
    _vacancyCtrl.text = '5';
    _costsCtrl.text = '0';
    _closingCostPercentCtrl.text = '10';
    _brokerFeeCtrl.text = '0';
    _transferTaxCtrl.text = '0';
    _notaryCtrl.text = '0';
    _otherAcquisitionCostsCtrl.text = '0';
    _renovationBudgetCtrl.text = '0';
    _renovationSafetyCtrl.text = '10';
    _maintenanceCtrl.text = '0';
    _managementCtrl.text = '0';
    _insuranceCtrl.text = '0';
    _propertyTaxCtrl.text = '0';
    _otherCostsCtrl.text = '0';
    _equityCtrl.text = '0';
    _loanCtrl.text = '0';
    _interestCtrl.text = '4';
    _amortizationCtrl.text = '2';
    _loanTermCtrl.text = '10';
    _minimumCashflowCtrl.text = '0';
    _minimumGrossYieldCtrl.text = '4';
    _minimumCapRateCtrl.text = '3.5';
    _minimumCashOnCashCtrl.text = '4';
    _maxPurchasePricePerSqmCtrl.text = '4000';
    _maxLoanToValueCtrl.text = '80';
    _maxRenovationShareCtrl.text = '25';
    _targetCapRateCtrl.text = '5';
    _desiredMarginCtrl.text = '0';
    _notesCtrl.clear();
    setState(() {
      _lastSaved = null;
      _lastDatasheetId = null;
      _lastExportFileName = null;
      _error = null;
    });
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  double _double(TextEditingController controller) {
    return parseDoubleFlexible(controller.text) ?? 0;
  }

  int _int(TextEditingController controller) {
    return parseIntFlexible(controller.text) ?? 0;
  }

  double _capRate(QuickScreeningRecord screening) {
    if (screening.purchasePrice <= 0) {
      return 0;
    }
    final effectiveRent =
        screening.rentMonthlyTotal * (1 - screening.vacancyPercent);
    final noi = (effectiveRent - screening.operatingCostsMonthly) * 12;
    return noi / screening.purchasePrice;
  }

  String _currency(double value) => 'EUR ${value.toStringAsFixed(0)}';

  String _nullableCurrency(double? value) =>
      value == null ? 'N/A' : _currency(value);

  String _percent(double value) => '${(value * 100).toStringAsFixed(2)}%';

  String _nullablePercent(double? value) =>
      value == null ? 'N/A' : _percent(value);

  NxBadgeKind _badgeKindForTrafficLight(String status) {
    switch (status) {
      case 'green':
        return NxBadgeKind.success;
      case 'yellow':
        return NxBadgeKind.warning;
      case 'red':
        return NxBadgeKind.error;
      default:
        return NxBadgeKind.neutral;
    }
  }
}

final _quickScreeningsProvider =
    FutureProvider.autoDispose<List<QuickScreeningRecord>>((ref) async {
  return ref.watch(valuationDataRepositoryProvider).listQuickScreenings();
});
