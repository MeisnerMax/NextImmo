import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/property.dart';
import '../../../features/valuation/application/valuation_case_lookup.dart';
import '../../../features/valuation/application/valuation_repository.dart';
import '../../../features/valuation/domain/reference_data.dart';
import '../../../features/valuation/domain/valuation_case_templates.dart';
import '../../../features/valuation/domain/valuation_factor.dart';
import '../../state/property_state.dart';

/// Creates a valuation from a case-kind template (Welle 5, AP5).
///
/// The two optional menus are the point of the "systemberechnete Werte +
/// Menüs" decision: picking an asset class or a building type *fills*
/// reference values as suggestions — visibly unconfirmed, counted by nothing
/// until somebody takes responsibility for them. The dialog says so rather than
/// letting the user believe the case arrives pre-filled with facts.
class ValuationCreateDialog extends ConsumerStatefulWidget {
  const ValuationCreateDialog({super.key, this.propertyId, this.scenarioId});

  /// Preselected when created from a property; null in the workspace queue,
  /// where the object has to be chosen.
  final String? propertyId;
  final String? scenarioId;

  @override
  ConsumerState<ValuationCreateDialog> createState() =>
      _ValuationCreateDialogState();
}

class _ValuationCreateDialogState extends ConsumerState<ValuationCreateDialog> {
  late String? _propertyId = widget.propertyId;
  ValuationCaseTemplate _template = ValuationCaseTemplates.all.first;
  AssetClass? _assetClass;
  ReferenceBuildingType? _buildingType;
  final TextEditingController _title = TextEditingController();
  bool _titleTouched = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  List<ValuationFactor> get _suggestions =>
      ValuationCaseTemplates.suggestedFactors(
        template: _template,
        assetClass: _assetClass,
        buildingType: _buildingType,
      );

  void _syncTitle(List<PropertyRecord> properties) {
    if (_titleTouched) return;
    final property = properties
        .where((entry) => entry.id == _propertyId)
        .firstOrNull;
    final proposed = property == null
        ? _template.headline
        : '${_template.headline} · ${property.name}';
    if (_title.text != proposed) _title.text = proposed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final propertiesAsync = ref.watch(propertiesControllerProvider);
    final properties = propertiesAsync.valueOrNull ?? const <PropertyRecord>[];
    _syncTitle(properties);
    final suggestions = _suggestions;

    return AlertDialog(
      title: const Text('Neue Bewertung'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.propertyId == null) ...<Widget>[
                DropdownButtonFormField<String>(
                  value: _propertyId,
                  decoration: const InputDecoration(labelText: 'Objekt'),
                  items: <DropdownMenuItem<String>>[
                    for (final property in properties)
                      DropdownMenuItem<String>(
                        value: property.id,
                        child: Text(property.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _propertyId = value),
                ),
                const SizedBox(height: 12),
              ],
              Text('Fallart', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final template in ValuationCaseTemplates.all)
                RadioListTile<ValuationCaseKindKey>(
                  value: ValuationCaseKindKey(template.kind),
                  groupValue: ValuationCaseKindKey(_template.kind),
                  onChanged: (_) => setState(() => _template = template),
                  title: Text(template.headline),
                  subtitle: Text(
                    '${template.description}\n'
                    '${template.enabledMethods.length} Verfahren aktiv',
                  ),
                  isThreeLine: true,
                  contentPadding: EdgeInsets.zero,
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AssetClass>(
                value: _assetClass,
                decoration: const InputDecoration(
                  labelText: 'Assetklasse (optional)',
                  helperText: 'Schlägt einen Liegenschaftszinssatz vor.',
                ),
                items: <DropdownMenuItem<AssetClass>>[
                  for (final value in AssetClass.values)
                    DropdownMenuItem<AssetClass>(
                      value: value,
                      child: Text(_assetClassLabel(value)),
                    ),
                ],
                onChanged: (value) => setState(() => _assetClass = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ReferenceBuildingType>(
                value: _buildingType,
                decoration: const InputDecoration(
                  labelText: 'Gebäudetyp (optional)',
                  helperText:
                      'Schlägt Normalherstellungskosten und '
                      'Gesamtnutzungsdauer vor.',
                ),
                items: <DropdownMenuItem<ReferenceBuildingType>>[
                  for (final value in ReferenceBuildingType.values)
                    DropdownMenuItem<ReferenceBuildingType>(
                      value: value,
                      child: Text(_buildingTypeLabel(value)),
                    ),
                ],
                onChanged: (value) => setState(() => _buildingType = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Bezeichnung'),
                onChanged: (_) => _titleTouched = true,
              ),
              if (suggestions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  '${suggestions.length} Referenzwert(e) werden als '
                  'unbestätigter Vorschlag angelegt — sie zählen erst, wenn du '
                  'sie in der Bewertung übernimmst.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _propertyId == null || _submitting ? null : _submit,
          child: Text(_submitting ? 'Wird angelegt …' : 'Bewertung anlegen'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref
        .read(valuationCaseCreatorProvider)
        .createFromTemplate(
          propertyId: _propertyId!,
          scenarioId: widget.scenarioId,
          title: _title.text.trim().isEmpty
              ? _template.headline
              : _title.text.trim(),
          template: _template,
          suggestedFactors: _suggestions,
        );
    if (!mounted) return;

    switch (result) {
      case ValuationRepositorySuccess(:final value):
        Navigator.of(context).pop(value.valuationCase.id);
      case ValuationRepositoryFailure(:final message):
        setState(() {
          _submitting = false;
          _error = message;
        });
    }
  }

  static String _assetClassLabel(AssetClass value) => switch (value) {
    AssetClass.wohnenEinfamilien => 'Wohnen – Einfamilien',
    AssetClass.wohnenMehrfamilien => 'Wohnen – Mehrfamilien',
    AssetClass.gemischtGenutzt => 'Gemischt genutzt',
    AssetClass.buero => 'Büro',
    AssetClass.einzelhandel => 'Einzelhandel',
  };

  static String _buildingTypeLabel(ReferenceBuildingType value) =>
      switch (value) {
        ReferenceBuildingType.einfamilienhaus => 'Einfamilienhaus',
        ReferenceBuildingType.doppelhaushaelfte => 'Doppelhaushälfte',
        ReferenceBuildingType.reihenhaus => 'Reihenhaus',
        ReferenceBuildingType.mehrfamilienhaus => 'Mehrfamilienhaus',
        ReferenceBuildingType.wohnUndGeschaeftshaus => 'Wohn- und Geschäftshaus',
        ReferenceBuildingType.buerogebaeude => 'Bürogebäude',
      };
}

/// Wrapper so the radio group compares by case kind rather than by template
/// identity — the templates are const, but comparing the kind states the intent.
class ValuationCaseKindKey {
  const ValuationCaseKindKey(this.kind);

  final Object kind;

  @override
  bool operator ==(Object other) =>
      other is ValuationCaseKindKey && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}
