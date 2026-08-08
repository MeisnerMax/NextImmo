import 'package:flutter/material.dart';

import 'package:neximmo_app/core/models/property_creation.dart';
import 'package:neximmo_app/ui/components/nx_form_section_card.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
import '../property_creation_support.dart';
import '../widgets/creation_option_grid.dart';

/// Step 0 — property type plus creation reason and mode.
class CreationEntryStep extends StatelessWidget {
  const CreationEntryStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final PropertyCreationDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = CreationFieldFactory(onChanged);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NxFormSectionCard(
          title: 'Objektart',
          margin: EdgeInsets.zero,
          body: CreationOptionGrid(
            options: const [
              CreationOptionSpec('rental', 'Vermietungsobjekt', Icons.apartment,
                  'Wohn-, Gewerbe- oder Bestandsobjekt mit Mietverhaeltnissen.'),
              CreationOptionSpec('sale', 'Verkaufsobjekt', Icons.sell_outlined,
                  'Objekt mit Verkaufsprozess, Angeboten und Interessenten.'),
              CreationOptionSpec(
                  'condo_sale',
                  'Eigentumswohnungen',
                  Icons.domain_add_outlined,
                  'Aufgeteilte Wohnungen mit Kaeufern, Reservierungen und Kaufpreisen.'),
              CreationOptionSpec('hotel', 'Hotel', Icons.hotel_outlined,
                  'Hotel- oder Beherbergungsbetrieb mit Zimmern und Reservierungen.'),
              CreationOptionSpec('mixed', 'Mischobjekt',
                  Icons.home_work_outlined,
                  'Objekt mit mehreren aktiven Nutzungsmodulen.'),
              CreationOptionSpec('other', 'Sonstiges', Icons.more_horiz,
                  'Spezialfall ausserhalb der Standardkategorien.'),
            ],
            selected: draft.propertyType,
            onSelected: (value) {
              draft.propertyType = value;
              onChanged();
            },
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxFormSectionCard(
          title: 'Anlagegrund und Bearbeitungsmodus',
          margin: EdgeInsets.zero,
          body: CreationFieldGrid(
            children: [
              fields.dropdown(
                label: 'Anlagegrund',
                value: draft.creationReason,
                items: const {
                  'bestand': 'Bestand erfassen',
                  'ankauf_pruefen': 'Ankauf pruefen',
                  'neu_gekauft': 'Neu gekauft',
                  'sanierung_planen': 'Sanierung planen',
                  'verkauf_vorbereiten': 'Verkauf vorbereiten',
                  'datenobjekt': 'Reines Datenobjekt',
                },
                onSelected: (value) => draft.creationReason = value,
              ),
              fields.dropdown(
                label: 'Bearbeitungsmodus',
                value: draft.creationMode,
                items: const {
                  'quick': 'Schnell anlegen',
                  'complete': 'Vollstaendig anlegen',
                  'later': 'Spaeter vervollstaendigen',
                },
                onSelected: (value) => draft.creationMode = value,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Step 1 — base data (name, ids, status, responsibilities).
class CreationBaseStep extends StatelessWidget {
  const CreationBaseStep({
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
      title: 'Basisdaten',
      margin: EdgeInsets.zero,
      body: CreationFieldGrid(
        children: [
          fields.text('Objektname *', draft.objectName,
              (v) => draft.objectName = v),
          fields.text('Interne Objekt-ID *', draft.internalId,
              (v) => draft.internalId = v),
          fields.text('Externe Referenznummer', draft.externalReference,
              (v) => draft.externalReference = v),
          fields.dropdown(
            label: 'Objektstatus *',
            value: draft.status,
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
            onSelected: (value) => draft.status = value,
          ),
          fields.text('Zustaendiger Asset Manager', draft.assetManager,
              (v) => draft.assetManager = v),
          fields.dropdown(
            label: 'Prioritaet',
            value: draft.priority,
            items: const {
              'niedrig': 'Niedrig',
              'normal': 'Normal',
              'hoch': 'Hoch',
              'kritisch': 'Kritisch',
            },
            onSelected: (value) => draft.priority = value,
          ),
          fields.text('Tags oder Kategorien', draft.tags,
              (v) => draft.tags = v),
          fields.text('Kurzbeschreibung', draft.shortDescription,
              (v) => draft.shortDescription = v, maxLines: 4),
        ],
      ),
    );
  }
}

/// Step 2 — address and location.
class CreationAddressStep extends StatelessWidget {
  const CreationAddressStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final PropertyCreationDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = CreationFieldFactory(onChanged);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NxFormSectionCard(
          title: 'Adresse',
          margin: EdgeInsets.zero,
          body: CreationFieldGrid(
            children: [
              fields.text('Strasse *', draft.street, (v) => draft.street = v),
              fields.text('Hausnummer *', draft.houseNumber,
                  (v) => draft.houseNumber = v),
              fields.text('PLZ *', draft.zip, (v) => draft.zip = v),
              fields.text('Ort *', draft.city, (v) => draft.city = v),
              fields.text('Bundesland', draft.federalState,
                  (v) => draft.federalState = v),
              fields.text('Land *', draft.country, (v) => draft.country = v),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxFormSectionCard(
          title: 'Lage',
          margin: EdgeInsets.zero,
          body: CreationFieldGrid(
            children: [
              fields.dropdown(
                label: 'Lagequalitaet',
                value: draft.locationQuality,
                items: const {
                  'a': 'A-Lage',
                  'b': 'B-Lage',
                  'c': 'C-Lage',
                  'd': 'D-Lage',
                  'nicht_bewertet': 'Nicht bewertet',
                },
                onSelected: (value) => draft.locationQuality = value,
              ),
              fields.text('Mikrostandort', draft.microLocation,
                  (v) => draft.microLocation = v),
              fields.text('Makrostandort', draft.macroLocation,
                  (v) => draft.macroLocation = v),
              fields.text('OePNV-Anbindung', draft.transit,
                  (v) => draft.transit = v),
              fields.text('Parkmoeglichkeiten', draft.parking,
                  (v) => draft.parking = v),
              fields.text('Umfeldnotizen', draft.environmentNotes,
                  (v) => draft.environmentNotes = v, maxLines: 3),
              fields.text('Lage-Risiken', draft.locationRisks,
                  (v) => draft.locationRisks = v, maxLines: 3),
              fields.text('Lage-Potenziale', draft.locationPotentials,
                  (v) => draft.locationPotentials = v, maxLines: 3),
            ],
          ),
        ),
      ],
    );
  }
}
