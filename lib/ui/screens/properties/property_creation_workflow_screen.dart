import 'package:flutter/material.dart';

import '../../../core/models/property.dart';
import '../../../core/models/property_creation.dart';
import '../../../core/services/property_creation_validation_service.dart';
import '../../components/nx_page_header.dart';
import '../../theme/app_theme.dart';
import 'creation/steps/creation_asset_steps.dart';
import 'creation/steps/creation_condition_steps.dart';
import 'creation/steps/creation_finance_steps.dart';
import 'creation/steps/creation_identity_steps.dart';
import 'creation/steps/creation_review_steps.dart';
import 'creation/widgets/creation_footer.dart';
import 'creation/widgets/creation_nav.dart';

/// SCR-008 (BIG-012 split): 12-step guided property-creation wizard. The screen
/// is provider-less local state — a mutable [PropertyCreationDraft] threaded
/// into the step widgets, the current step, and the save lifecycle. Step
/// content and validation are unchanged from the pre-redesign screen; only the
/// presentation was lifted onto the `nx_*` design system (`NxPageHeader`,
/// `NxFormSectionCard`, `NxActionToolbar`) and the building blocks moved into
/// `creation/`. The public constructor is unchanged so the caller in
/// `properties_screen.dart` keeps compiling.
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
  bool _saveFailed = false;
  bool _dirty = false;
  PropertyRecord? _createdProperty;

  @override
  void initState() {
    super.initState();
    _draft = PropertyCreationDraft(
      internalId: _suggestNextInternalId(widget.existingProperties),
    );
  }

  /// Single rebuild callback threaded into every step/editor. Any real draft
  /// mutation funnels through here, so it doubles as the dirty-tracking signal
  /// for the cancel-with-confirmation flow.
  void _onDraftChanged() {
    setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) {
    final assessment = _validation.assess(
      _draft,
      existingProperties: widget.existingProperties,
    );
    final theme = Theme.of(context);
    final semantic = context.semanticColors;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                0,
              ),
              child: NxPageHeader(
                title: 'Objekt anlegen',
                secondaryActions: [
                  TextButton.icon(
                    onPressed: _saving ? null : _handleClose,
                    icon: const Icon(Icons.close),
                    label: const Text('Schliessen'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.component),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 820;
                  final navigation = SizedBox(
                    width: compact ? double.infinity : 310,
                    height: compact ? 260 : null,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: semantic.surfaceAlt,
                        border: Border(
                          right: compact
                              ? BorderSide.none
                              : BorderSide(color: semantic.border),
                          bottom: compact
                              ? BorderSide(color: semantic.border)
                              : BorderSide.none,
                        ),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.all(AppSpacing.component),
                        children: [
                          CreationQualityPanel(assessment: assessment),
                          const SizedBox(height: AppSpacing.component),
                          for (var i = 0; i < _steps.length; i++)
                            CreationStepNavTile(
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
                  );
                  final content = Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpacing.section),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1180),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _steps[_step],
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _stepSubtitles[_step],
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        color: semantic.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.section),
                                    _buildStep(context, assessment),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.component),
                          child: CreationFooter(
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
                            onSummary:
                                _saving ? null : () => setState(() => _step = 10),
                            onSave: _saving || _createdProperty != null
                                ? null
                                : () => _save(assessment),
                          ),
                        ),
                      ],
                    ),
                  );
                  return compact
                      ? Column(children: [navigation, content])
                      : Row(children: [navigation, content]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(
    BuildContext context,
    PropertyCreationAssessment assessment,
  ) {
    return switch (_step) {
      0 => CreationEntryStep(draft: _draft, onChanged: _onDraftChanged),
      1 => CreationBaseStep(draft: _draft, onChanged: _onDraftChanged),
      2 => CreationAddressStep(draft: _draft, onChanged: _onDraftChanged),
      3 => CreationAreasStep(
        draft: _draft,
        assessment: assessment,
        onChanged: _onDraftChanged,
      ),
      4 => CreationUsageStep(
        draft: _draft,
        assessment: assessment,
        onChanged: _onDraftChanged,
      ),
      5 => CreationPurchaseStep(
        draft: _draft,
        assessment: assessment,
        onChanged: _onDraftChanged,
      ),
      6 => CreationFinancingStep(
        draft: _draft,
        assessment: assessment,
        onChanged: _onDraftChanged,
      ),
      7 => CreationTechnicalStep(
        draft: _draft,
        assessment: assessment,
        onChanged: _onDraftChanged,
      ),
      8 => CreationLegalStep(draft: _draft, onChanged: _onDraftChanged),
      9 => CreationDocumentsStep(draft: _draft, onChanged: _onDraftChanged),
      10 => CreationSummaryStep(draft: _draft, assessment: assessment),
      _ => CreationSaveStep(
        assessment: assessment,
        saving: _saving,
        saveFailed: _saveFailed,
        created: _createdProperty,
        onSave: () => _save(assessment),
        onOpenCreated: () => Navigator.of(context).pop(_createdProperty),
        onDismiss: () => Navigator.of(context).pop(null),
      ),
    };
  }

  Future<void> _save(PropertyCreationAssessment assessment) async {
    if (!assessment.canSave) {
      // Defensive fallback: surface the open items inline on the review step
      // rather than a collection snackbar.
      setState(() => _step = 10);
      return;
    }
    setState(() {
      _saving = true;
      _saveFailed = false;
      _step = 11;
    });
    try {
      final property = await widget.onCreateProperty(_draft, assessment);
      if (!mounted) {
        return;
      }
      if (property == null) {
        setState(() => _saveFailed = true);
        return;
      }
      setState(() => _createdProperty = property);
    } catch (_) {
      // The draft is never discarded, so a retry keeps every entered value.
      if (mounted) {
        setState(() => _saveFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _handleClose() async {
    if (_saving) {
      return;
    }
    if (_dirty && _createdProperty == null) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Anlage abbrechen?'),
          content: const Text(
            'Ihre bisher erfassten Angaben gehen dabei verloren. Moechten Sie '
            'die Objektanlage wirklich abbrechen?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Weiter bearbeiten'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Verwerfen'),
            ),
          ],
        ),
      );
      if (discard != true) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(null);
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
