import 'package:flutter/material.dart';

import 'package:neximmo_app/core/models/property_creation.dart';
import 'package:neximmo_app/ui/components/nx_form_section_card.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
import '../property_creation_support.dart';
import '../widgets/creation_editors.dart';
import '../widgets/creation_summary_widgets.dart';

/// Step 3 — areas, capacities, and the unit structure editor.
class CreationAreasStep extends StatelessWidget {
  const CreationAreasStep({
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
          title: 'Flaechen und Kapazitaeten',
          margin: EdgeInsets.zero,
          body: CreationFieldGrid(
            children: [
              fields.number('Gesamtflaeche qm', draft.totalArea,
                  (v) => draft.totalArea = v),
              fields.number('Wohnflaeche qm', draft.residentialArea,
                  (v) => draft.residentialArea = v),
              fields.number('Gewerbeflaeche qm', draft.commercialArea,
                  (v) => draft.commercialArea = v),
              fields.number('Nutzflaeche qm', draft.usableArea,
                  (v) => draft.usableArea = v),
              fields.number('Grundstuecksflaeche qm', draft.landArea,
                  (v) => draft.landArea = v),
              fields.intField('Anzahl Wohneinheiten', draft.residentialUnits,
                  (v) => draft.residentialUnits = v),
              fields.intField('Anzahl Gewerbeeinheiten', draft.commercialUnits,
                  (v) => draft.commercialUnits = v),
              fields.intField('Anzahl Stellplaetze', draft.parkingSpots,
                  (v) => draft.parkingSpots = v),
              fields.intField('Anzahl Garagen', draft.garages,
                  (v) => draft.garages = v),
              fields.number('Kellerflaechen qm', draft.basementArea,
                  (v) => draft.basementArea = v),
              fields.number('Leerstehende Flaeche qm', draft.vacantArea,
                  (v) => draft.vacantArea = v),
              fields.number('Vermietete Flaeche qm', draft.leasedArea,
                  (v) => draft.leasedArea = v),
              fields.text('Ausbaupotenzial', draft.expansionPotential,
                  (v) => draft.expansionPotential = v),
              fields.text('Nachverdichtungspotenzial',
                  draft.densificationPotential,
                  (v) => draft.densificationPotential = v),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        CreationMetricStrip(
          items: [
            CreationMetricItem('Gesamt',
                formatCreationSqm(assessment.metrics.totalArea)),
            CreationMetricItem('Vermietet',
                formatCreationSqm(assessment.metrics.leasedArea)),
            CreationMetricItem('Leerstand',
                formatCreationSqm(assessment.metrics.vacantArea)),
            CreationMetricItem('Quote',
                formatCreationPercent(assessment.metrics.vacancyRate)),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        _UnitsEditorSection(draft: draft, onChanged: onChanged),
      ],
    );
  }
}

class _UnitsEditorSection extends StatelessWidget {
  const _UnitsEditorSection({required this.draft, required this.onChanged});

  final PropertyCreationDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return NxFormSectionCard(
      title: 'Einheitenstruktur',
      margin: EdgeInsets.zero,
      trailing: FilledButton.icon(
        onPressed: () {
          draft.units.add(PropertyCreationUnitDraft());
          onChanged();
        },
        icon: const Icon(Icons.add),
        label: const Text('Einheit hinzufuegen'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (draft.units.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Noch keine Einheiten angelegt.'),
            ),
          for (var i = 0; i < draft.units.length; i++)
            CreationUnitEditor(
              unit: draft.units[i],
              onChanged: onChanged,
              onDuplicate: () {
                draft.units.insert(i + 1, draft.units[i].duplicate());
                onChanged();
              },
              onRemove: () {
                draft.units.removeAt(i);
                onChanged();
              },
            ),
        ],
      ),
    );
  }
}

/// Step 4 — usage mix, rents, and the optional tenant editor.
class CreationUsageStep extends StatelessWidget {
  const CreationUsageStep({
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
          title: 'Nutzung und Mieten',
          margin: EdgeInsets.zero,
          body: CreationFieldGrid(
            children: [
              fields.text('Hauptnutzung', draft.mainUse,
                  (v) => draft.mainUse = v),
              fields.text('Nutzungsmix', draft.usageMix,
                  (v) => draft.usageMix = v),
              fields.number('Aktuelle Jahreskaltmiete', draft.annualColdRent,
                  (v) => draft.annualColdRent = v),
              fields.number('Monatliche Ist-Miete', draft.monthlyActualRent,
                  (v) => draft.monthlyActualRent = v),
              fields.number('Geschaetzte Soll-Miete monatlich', draft.targetRent,
                  (v) => draft.targetRent = v),
              fields.number('Leerstand in Prozent', draft.vacancyPercent,
                  (v) => draft.vacancyPercent = v),
              fields.number('Durchschnittsmiete pro qm',
                  draft.averageRentPerSqm,
                  (v) => draft.averageRentPerSqm = v),
              fields.number('Marktmiete pro qm', draft.marketRentPerSqm,
                  (v) => draft.marketRentPerSqm = v),
              fields.text('Mietvertragsstatus', draft.leaseContractStatus,
                  (v) => draft.leaseContractStatus = v),
              fields.switchTile('Indexmiete', draft.indexedRent,
                  (v) => draft.indexedRent = v),
              fields.switchTile('Staffelmiete', draft.steppedRent,
                  (v) => draft.steppedRent = v),
              fields.switchTile('Mietrueckstaende', draft.rentArrears,
                  (v) => draft.rentArrears = v),
              fields.text('Besondere Mietvereinbarungen',
                  draft.specialLeaseTerms,
                  (v) => draft.specialLeaseTerms = v, maxLines: 3),
              fields.switchTile('Mieterdaten jetzt erfassen',
                  draft.captureTenantsNow,
                  (v) => draft.captureTenantsNow = v),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        CreationMetricStrip(
          items: [
            CreationMetricItem('Ist/qm',
                formatCreationCurrency(assessment.metrics.actualRentPerSqm)),
            CreationMetricItem('Soll/qm',
                formatCreationCurrency(assessment.metrics.targetRentPerSqm)),
            CreationMetricItem('Ist p.a.',
                formatCreationCurrency(assessment.metrics.annualActualRent)),
            CreationMetricItem('Potenzial',
                formatCreationCurrency(assessment.metrics.rentUpside)),
          ],
        ),
        if (draft.captureTenantsNow) ...[
          const SizedBox(height: AppSpacing.component),
          _TenantsEditorSection(draft: draft, onChanged: onChanged),
        ],
      ],
    );
  }
}

class _TenantsEditorSection extends StatelessWidget {
  const _TenantsEditorSection({required this.draft, required this.onChanged});

  final PropertyCreationDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return NxFormSectionCard(
      title: 'Mieter optional',
      margin: EdgeInsets.zero,
      trailing: FilledButton.icon(
        onPressed: () {
          draft.tenants.add(PropertyCreationTenantDraft());
          onChanged();
        },
        icon: const Icon(Icons.add),
        label: const Text('Mieter hinzufuegen'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (draft.tenants.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'Mieterdaten koennen jetzt oder spaeter erfasst werden.'),
            ),
          for (var i = 0; i < draft.tenants.length; i++)
            CreationTenantEditor(
              tenant: draft.tenants[i],
              unitCodes: draft.units
                  .map((unit) => unit.unitCode)
                  .where((code) => code.trim().isNotEmpty)
                  .toList(growable: false),
              onChanged: onChanged,
              onRemove: () {
                draft.tenants.removeAt(i);
                onChanged();
              },
            ),
        ],
      ),
    );
  }
}
