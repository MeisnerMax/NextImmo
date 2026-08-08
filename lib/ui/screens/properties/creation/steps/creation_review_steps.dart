import 'package:flutter/material.dart';

import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/core/models/property_creation.dart';
import 'package:neximmo_app/ui/components/nx_form_section_card.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
import '../property_creation_support.dart';
import '../widgets/creation_summary_widgets.dart';

/// Step 10 — review of the entered data plus the missing/recommended/critical
/// checklists.
class CreationSummaryStep extends StatelessWidget {
  const CreationSummaryStep({
    super.key,
    required this.draft,
    required this.assessment,
  });

  final PropertyCreationDraft draft;
  final PropertyCreationAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CreationMetricStrip(
          items: [
            CreationMetricItem(
                'Datenqualitaet', '${assessment.metrics.dataQualityScore}%'),
            CreationMetricItem('Status', assessment.metrics.dataQualityStatus),
            CreationMetricItem(
                'Pflicht offen', '${assessment.missingRequired.length}'),
            CreationMetricItem(
                'Warnungen', '${assessment.criticalWarnings.length}'),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        NxFormSectionCard(
          title: 'Pruefansicht',
          margin: EdgeInsets.zero,
          body: CreationFieldGrid(
            children: [
              CreationSummaryBlock(
                title: 'Objekt',
                lines: [
                  draft.objectName,
                  draft.internalId,
                  '${draft.addressLine1}, ${draft.zip} ${draft.city}',
                  draft.propertyType,
                  draft.status,
                ],
              ),
              CreationSummaryBlock(
                title: 'Flaechen und Einheiten',
                lines: [
                  'Gesamt: ${formatCreationSqm(assessment.metrics.totalArea)}',
                  'Einheiten: ${draft.units.length}',
                  'Vermietet: ${formatCreationSqm(assessment.metrics.leasedArea)}',
                  'Leerstand: ${formatCreationPercent(assessment.metrics.vacancyRate)}',
                ],
              ),
              CreationSummaryBlock(
                title: 'Mieten und Kauf',
                lines: [
                  'Ist-Miete p.a.: ${formatCreationCurrency(assessment.metrics.annualActualRent)}',
                  'Soll-Miete p.a.: ${formatCreationCurrency(assessment.metrics.annualTargetRent)}',
                  'Kaufpreis/qm: ${formatCreationCurrency(assessment.metrics.purchasePricePerSqm)}',
                  'Gesamtinvestition: ${formatCreationCurrency(assessment.metrics.totalInvestment)}',
                ],
              ),
              CreationSummaryBlock(
                title: 'Technik, Recht, Dokumente',
                lines: [
                  'Zustand: ${assessment.metrics.conditionScore}%',
                  'Grundbuch: ${draft.landRegisterAvailable ? 'vorhanden' : 'offen'}',
                  'Energieausweis: ${draft.energyCertificateAvailable ? 'vorhanden' : 'offen'}',
                  'Dokumente geprueft: ${draft.documents.where((doc) => doc.status != 'fehlt').length}/${draft.documents.length}',
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        CreationChecklistPanel(
          title: 'Fehlende Pflichtangaben',
          icon: Icons.error_outline,
          items: assessment.missingRequired,
          emptyText: 'Alle Pflichtangaben sind vorhanden.',
          color: semantic.error,
        ),
        const SizedBox(height: AppSpacing.component),
        CreationChecklistPanel(
          title: 'Empfohlene Angaben',
          icon: Icons.info_outline,
          items: assessment.recommended,
          emptyText: 'Keine empfohlenen Angaben offen.',
          color: semantic.warning,
        ),
        const SizedBox(height: AppSpacing.component),
        CreationChecklistPanel(
          title: 'Kritische Warnungen',
          icon: Icons.warning_amber_outlined,
          items: assessment.criticalWarnings,
          emptyText: 'Keine kritischen Warnungen.',
          color: semantic.error,
        ),
        const SizedBox(height: AppSpacing.component),
        NxFormSectionCard(
          title: 'Transparente Datenqualitaet',
          margin: EdgeInsets.zero,
          body: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in assessment.qualityItems)
                Chip(
                  avatar: Icon(
                    item.complete
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: item.complete
                        ? semantic.success
                        : semantic.textSecondary,
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
}

/// Step 11 — final save. Renders four explicit states: a clear loading state
/// while [saving], a retry-without-data-loss state on [saveFailed], the
/// success state once [created], and otherwise the ready-to-save prompt.
class CreationSaveStep extends StatelessWidget {
  const CreationSaveStep({
    super.key,
    required this.assessment,
    required this.saving,
    required this.saveFailed,
    required this.created,
    required this.onSave,
    required this.onOpenCreated,
    required this.onDismiss,
  });

  final PropertyCreationAssessment assessment;
  final bool saving;
  final bool saveFailed;
  final PropertyRecord? created;
  final VoidCallback onSave;
  final VoidCallback onOpenCreated;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final createdProperty = created;
    if (createdProperty != null) {
      return _buildSuccess(context);
    }
    if (saving) {
      return _buildLoading(context);
    }
    if (saveFailed) {
      return _buildError(context);
    }
    return _buildReady(context);
  }

  Widget _buildReady(BuildContext context) {
    return NxFormSectionCard(
      title: 'Final speichern',
      margin: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            assessment.canSave
                ? 'Das Objekt ist bereit fuer die Anlage. Erst mit dieser finalen Bestaetigung wird gespeichert.'
                : 'Vor dem Speichern muessen die Pflichtangaben und kritischen Warnungen geklaert werden.',
          ),
          const SizedBox(height: AppSpacing.component),
          FilledButton.icon(
            onPressed: assessment.canSave && !saving ? onSave : null,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Property final speichern'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return NxFormSectionCard(
      title: 'Objekt wird gespeichert',
      margin: EdgeInsets.zero,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.component),
          Expanded(
            child: Text(
              'Das Objekt wird gespeichert. Bitte einen Moment Geduld.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final semantic = context.semanticColors;
    return NxFormSectionCard(
      title: 'Speichern fehlgeschlagen',
      margin: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: semantic.error, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Das Objekt konnte nicht gespeichert werden. Ihre Eingaben '
                  'bleiben erhalten - bitte erneut versuchen.',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return NxFormSectionCard(
      title: 'Property wurde erfolgreich angelegt',
      margin: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CreationMetricStrip(
            items: [
              CreationMetricItem(
                  'Datenqualitaet', '${assessment.metrics.dataQualityScore}%'),
              CreationMetricItem(
                  'Status', assessment.metrics.dataQualityStatus),
              CreationMetricItem(
                'Vollstaendig',
                '${assessment.qualityItems.where((item) => item.complete).length}'
                    '/${assessment.qualityItems.length}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onOpenCreated,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Property Detail Page oeffnen'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenCreated,
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Intensivbewertung starten'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenCreated,
                icon: const Icon(Icons.construction_outlined),
                label: const Text('Renovierungsprojekt anlegen'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenCreated,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Dokumente ergaenzen'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenCreated,
                icon: const Icon(Icons.people_alt_outlined),
                label: const Text('Mieterliste vervollstaendigen'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenCreated,
                icon: const Icon(Icons.account_balance_outlined),
                label: const Text('Finanzierung ergaenzen'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenCreated,
                icon: const Icon(Icons.sell_outlined),
                label: const Text('Verkaufsszenario vorbereiten'),
              ),
              TextButton.icon(
                onPressed: onDismiss,
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('Zur Property-Uebersicht'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
