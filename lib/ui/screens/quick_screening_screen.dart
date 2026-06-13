import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/analysis_result.dart';
import '../../core/models/inputs.dart';
import '../../core/models/property.dart';
import '../../core/models/scenario_valuation.dart';
import '../../core/models/settings.dart';
import '../../core/models/valuation.dart';
import '../components/nx_card.dart';
import '../components/nx_empty_state.dart';
import '../components/nx_status_badge.dart';
import '../state/app_state.dart';
import '../state/property_state.dart';
import '../state/scenario_state.dart';
import '../templates/list_filter_template.dart';
import '../theme/app_theme.dart';
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
  final _unitsCtrl = TextEditingController(text: '0');
  final _areaCtrl = TextEditingController(text: '0');
  final _purchaseCtrl = TextEditingController(text: '0');
  final _rentCtrl = TextEditingController(text: '0');
  final _vacancyCtrl = TextEditingController(text: '5');
  final _costsCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();

  String _propertyType = 'multifamily';
  String? _selectedPropertyId;
  QuickScreeningRecord? _lastSaved;
  bool _saving = false;
  String? _error;

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
    _titleCtrl,
    _sourceCtrl,
    _addressCtrl,
    _unitsCtrl,
    _areaCtrl,
    _purchaseCtrl,
    _rentCtrl,
    _vacancyCtrl,
    _costsCtrl,
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
        label: Text(_saving ? 'Speichern...' : 'Screening speichern'),
      ),
      secondaryActions: [
        OutlinedButton.icon(
          onPressed: _clearForm,
          icon: const Icon(Icons.refresh),
          label: const Text('Neu starten'),
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
    final inputs = _draftInputs(settings);
    final analysis = ref.read(analysisEngineProvider).run(
      inputs: inputs,
      settings: settings,
      incomeLines: const <IncomeLine>[],
      expenseLines: const <ExpenseLine>[],
      valuation: ScenarioValuationRecord.defaults(
        scenarioId: 'quick-screening-preview',
      ),
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
              analysis: analysis,
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
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _numberField(_unitsCtrl, 'Einheiten'),
              _numberField(_areaCtrl, 'Flaeche m2'),
              _numberField(_purchaseCtrl, 'Kaufpreis', prefixText: 'EUR '),
              _numberField(_rentCtrl, 'Sollmiete mtl.', prefixText: 'EUR '),
              _numberField(_vacancyCtrl, 'Leerstand', suffixText: '%'),
              _numberField(_costsCtrl, 'Kosten mtl.', prefixText: 'EUR '),
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
    required AnalysisResult analysis,
    required AsyncValue<List<PropertyRecord>> propertiesAsync,
  }) {
    final metrics = analysis.metrics;
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
          _metric('NOI Jahr 1', _currency(metrics.noiYear1)),
          _metric('Cap Rate', _percent(metrics.capRate)),
          _metric('Cashflow mtl.', _currency(metrics.monthlyCashflowYear1)),
          _metric('Cash on Cash', _percent(metrics.cashOnCash)),
          _metric('IRR', metrics.irr == null ? 'N/A' : _percent(metrics.irr!)),
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

  Widget _metric(String label, String value) {
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

  ScenarioInputs _draftInputs(AppSettingsRecord settings) {
    return ScenarioInputs.defaults(
      scenarioId: 'quick-screening-preview',
      settings: settings,
    ).copyWith(
      purchasePrice: _double(_purchaseCtrl),
      rentMonthlyTotal: _double(_rentCtrl),
      grossAreaSqm: _double(_areaCtrl),
      lettableAreaSqm: _double(_areaCtrl),
      vacancyPercent: _double(_vacancyCtrl) / 100,
      otherExpensesMonthly: _double(_costsCtrl),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
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

  void _loadScreening(QuickScreeningRecord screening) {
    _titleCtrl.text = screening.title;
    _sourceCtrl.text = screening.sourceLabel ?? '';
    _addressCtrl.text = screening.addressText ?? '';
    _propertyType = screening.propertyType;
    _unitsCtrl.text = screening.units.toString();
    _areaCtrl.text = screening.areaSqm.toStringAsFixed(0);
    _purchaseCtrl.text = screening.purchasePrice.toStringAsFixed(0);
    _rentCtrl.text = screening.rentMonthlyTotal.toStringAsFixed(0);
    _vacancyCtrl.text = (screening.vacancyPercent * 100).toStringAsFixed(1);
    _costsCtrl.text = screening.operatingCostsMonthly.toStringAsFixed(0);
    _notesCtrl.text = screening.notes ?? '';
    setState(() => _lastSaved = screening);
  }

  void _clearForm() {
    _titleCtrl.text = 'Neues Deal Screening';
    _sourceCtrl.clear();
    _addressCtrl.clear();
    _propertyType = 'multifamily';
    _unitsCtrl.text = '0';
    _areaCtrl.text = '0';
    _purchaseCtrl.text = '0';
    _rentCtrl.text = '0';
    _vacancyCtrl.text = '5';
    _costsCtrl.text = '0';
    _notesCtrl.clear();
    setState(() {
      _lastSaved = null;
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

  String _percent(double value) => '${(value * 100).toStringAsFixed(2)}%';
}

final _quickScreeningsProvider =
    FutureProvider.autoDispose<List<QuickScreeningRecord>>((ref) async {
  return ref.watch(valuationDataRepositoryProvider).listQuickScreenings();
});
