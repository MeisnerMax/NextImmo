import 'package:flutter/material.dart';

import 'package:neximmo_app/core/models/property_creation.dart';
import 'package:neximmo_app/ui/components/nx_form_section_card.dart';
import 'package:neximmo_app/ui/components/responsive_constraints.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
import '../property_creation_support.dart';
import '../widgets/creation_summary_widgets.dart';

/// Step 7 — technical condition and derived scores.
class CreationTechnicalStep extends StatelessWidget {
  const CreationTechnicalStep({
    super.key,
    required this.draft,
    required this.assessment,
    required this.onChanged,
  });

  final PropertyCreationDraft draft;
  final PropertyCreationAssessment assessment;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = CreationFieldFactory(onChanged);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NxFormSectionCard(
          title: 'Technischer Zustand',
          margin: EdgeInsets.zero,
          body: CreationFieldGrid(
            children: [
              fields.intField('Baujahr', draft.yearBuilt,
                  (v) => draft.yearBuilt = v),
              fields.intField('Letzte Sanierung', draft.lastRenovationYear,
                  (v) => draft.lastRenovationYear = v),
              fields.switchTile('Energieausweis vorhanden',
                  draft.energyCertificateAvailable,
                  (v) => draft.energyCertificateAvailable = v),
              fields.text('Energieklasse', draft.energyClass,
                  (v) => draft.energyClass = v),
              fields.text('Heizungsart', draft.heatingType,
                  (v) => draft.heatingType = v),
              fields.condition('Dachzustand', draft.roofCondition,
                  (v) => draft.roofCondition = v),
              fields.condition('Fassadenzustand', draft.facadeCondition,
                  (v) => draft.facadeCondition = v),
              fields.condition('Fensterzustand', draft.windowsCondition,
                  (v) => draft.windowsCondition = v),
              fields.condition('Elektrikzustand', draft.electricCondition,
                  (v) => draft.electricCondition = v),
              fields.condition('Leitungszustand', draft.pipesCondition,
                  (v) => draft.pipesCondition = v),
              fields.condition('Brandschutzstatus', draft.fireSafetyStatus,
                  (v) => draft.fireSafetyStatus = v),
              fields.condition('Barrierefreiheit', draft.accessibility,
                  (v) => draft.accessibility = v),
              fields.switchTile('Feuchtigkeitsschaeden', draft.moistureDamage,
                  (v) => draft.moistureDamage = v),
              fields.switchTile('Denkmalschutz', draft.monumentProtection,
                  (v) => draft.monumentProtection = v),
              fields.text('Bekannter Sanierungsbedarf', draft.renovationNeed,
                  (v) => draft.renovationNeed = v, maxLines: 3),
              fields.number('Geschaetztes Renovierungsbudget',
                  draft.renovationBudget,
                  (v) => draft.renovationBudget = v),
              fields.text('Technische Risiken', draft.technicalRisks,
                  (v) => draft.technicalRisks = v, maxLines: 3),
              fields.text('Technische Notizen', draft.technicalNotes,
                  (v) => draft.technicalNotes = v, maxLines: 3),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        CreationMetricStrip(
          items: [
            CreationMetricItem(
                'Zustands-Score', '${assessment.metrics.conditionScore}%'),
            CreationMetricItem(
                'Datenqualitaet', '${assessment.metrics.dataQualityScore}%'),
            CreationMetricItem('Status', assessment.metrics.dataQualityStatus),
          ],
        ),
      ],
    );
  }
}

/// Step 8 — legal and organisational data.
class CreationLegalStep extends StatelessWidget {
  const CreationLegalStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final PropertyCreationDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = CreationFieldFactory(onChanged);
    return NxFormSectionCard(
      title: 'Rechtliche und organisatorische Angaben',
      margin: EdgeInsets.zero,
      body: CreationFieldGrid(
        children: [
          fields.text('Eigentuemergesellschaft', draft.ownerCompany,
              (v) => draft.ownerCompany = v),
          fields.switchTile('Grundbuchinformationen vorhanden',
              draft.landRegisterAvailable,
              (v) => draft.landRegisterAvailable = v),
          fields.text('Flurstueck', draft.parcel, (v) => draft.parcel = v),
          fields.switchTile('Baulasten bekannt', draft.knownBuildingCharges,
              (v) => draft.knownBuildingCharges = v),
          fields.switchTile('Denkmalschutz rechtlich',
              draft.legalMonumentProtection,
              (v) => draft.legalMonumentProtection = v),
          fields.switchTile('Teilungserklaerung vorhanden',
              draft.declarationOfDivisionAvailable,
              (v) => draft.declarationOfDivisionAvailable = v),
          fields.switchTile('WEG', draft.weg, (v) => draft.weg = v),
          fields.text('Bestehende Dienstbarkeiten', draft.easements,
              (v) => draft.easements = v, maxLines: 3),
          fields.text('Bestehende Rechtsstreitigkeiten', draft.legalDisputes,
              (v) => draft.legalDisputes = v, maxLines: 3),
          fields.text('Versicherungen', draft.insurances,
              (v) => draft.insurances = v),
          fields.text('Hausverwaltung', draft.propertyManagement,
              (v) => draft.propertyManagement = v),
          fields.text('Ansprechpartner intern', draft.internalContact,
              (v) => draft.internalContact = v),
          fields.text('Ansprechpartner extern', draft.externalContact,
              (v) => draft.externalContact = v),
          fields.text('Steuerliche Besonderheiten', draft.taxNotes,
              (v) => draft.taxNotes = v, maxLines: 3),
          fields.text('Organisatorische Notizen', draft.organisationalNotes,
              (v) => draft.organisationalNotes = v, maxLines: 3),
          fields.switchTile('Kritische Risiken bewusst bestaetigt',
              draft.criticalRisksConfirmed,
              (v) => draft.criticalRisksConfirmed = v),
        ],
      ),
    );
  }
}

/// Step 9 — document checklist feeding the data-quality score.
class CreationDocumentsStep extends StatelessWidget {
  const CreationDocumentsStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final PropertyCreationDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = CreationFieldFactory(onChanged);
    return NxFormSectionCard(
      title: 'Dokumente und Datenqualitaet',
      margin: EdgeInsets.zero,
      body: Column(
        children: [
          for (final doc in draft.documents)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  SizedBox(
                    width: ResponsiveConstraints.itemWidth(
                      context,
                      idealWidth: 210,
                      maxWidth: 260,
                    ),
                    child: Text(doc.label),
                  ),
                  SizedBox(
                    width: ResponsiveConstraints.itemWidth(
                      context,
                      idealWidth: 150,
                      maxWidth: 220,
                    ),
                    child: fields.dropdown(
                      label: 'Status',
                      value: doc.status,
                      items: const {
                        'vorhanden': 'Vorhanden',
                        'fehlt': 'Fehlt',
                        'angefordert': 'Angefordert',
                        'nicht_relevant': 'Nicht relevant',
                      },
                      onSelected: (value) => doc.status = value,
                    ),
                  ),
                  creationWorkflowField(
                    context,
                    fields.text('Upload/Pfad optional', doc.uploadPath,
                        (v) => doc.uploadPath = v),
                  ),
                  creationWorkflowField(
                    context,
                    fields.text('Notiz', doc.note, (v) => doc.note = v),
                  ),
                  SizedBox(
                    width: ResponsiveConstraints.itemWidth(
                      context,
                      idealWidth: 150,
                      maxWidth: 220,
                    ),
                    child: fields.date('Frist', doc.dueDate,
                        (v) => doc.dueDate = v),
                  ),
                  SizedBox(
                    width: ResponsiveConstraints.itemWidth(
                      context,
                      idealWidth: 160,
                      maxWidth: 240,
                    ),
                    child: fields.text('Verantwortlich', doc.owner,
                        (v) => doc.owner = v),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
