import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/property.dart';
import '../../../state/property_state.dart';
import '../../../theme/app_theme.dart';
import '../../properties/create_property_dialog.dart';
import 'overview_view_model.dart';

/// Master-data edit dialog of the overview screen (moved out of the legacy
/// monolith, BIG-010 split). Behavior and fields are unchanged; styling is
/// token-based.
Future<void> showOverviewEditPropertyDialog({
  required BuildContext context,
  required WidgetRef ref,
  required PropertyRecord property,
}) async {
  final nameCtrl = TextEditingController(text: property.name);
  final addr1Ctrl = TextEditingController(text: property.addressLine1);
  final addr2Ctrl = TextEditingController(text: property.addressLine2 ?? '');
  final zipCtrl = TextEditingController(text: property.zip);
  final cityCtrl = TextEditingController(text: property.city);
  final countryCtrl = TextEditingController(text: property.country);
  final typeCtrl = TextEditingController(text: property.propertyType);
  final unitsCtrl = TextEditingController(text: property.units.toString());

  final landAreaCtrl =
      TextEditingController(text: property.landArea?.toString() ?? '');
  final resAreaCtrl =
      TextEditingController(text: property.residentialArea?.toString() ?? '');
  final comAreaCtrl =
      TextEditingController(text: property.commercialArea?.toString() ?? '');
  final parkingCtrl =
      TextEditingController(text: property.parkingSpots?.toString() ?? '');
  final ownerCtrl = TextEditingController(text: property.ownerCompany ?? '');
  final purchasePriceCtrl =
      TextEditingController(text: property.purchasePrice?.toString() ?? '');
  final notaryCtrl = TextEditingController(text: property.notary ?? '');
  final sellerCtrl = TextEditingController(text: property.seller ?? '');
  final registryCtrl =
      TextEditingController(text: property.landRegistryDetails ?? '');
  final parcelCtrl = TextEditingController(text: property.parcel ?? '');
  final energyCtrl =
      TextEditingController(text: property.energyCertificate ?? '');
  final insuranceCtrl =
      TextEditingController(text: property.insuranceDetails ?? '');
  final taxCtrl = TextEditingController(text: property.taxAssignment ?? '');
  final notesCtrl = TextEditingController(text: property.notes ?? '');

  DateTime? purchaseDate = property.purchaseDate != null
      ? DateTime.fromMillisecondsSinceEpoch(property.purchaseDate!)
      : null;

  final formKey = GlobalKey<FormState>();

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Stammdaten bearbeiten'),
        content: SizedBox(
          width: 700,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Passen Sie die Grunddaten und rechtlichen Angaben des Objekts an.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.semanticColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 16),
                  const _DialogSectionHeader('Allgemeine Informationen'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Name des Objekts *',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Pflichtfeld'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: ownerCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Eigentümergesellschaft',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: propertyTypeOptions
                                  .any((opt) => opt.value == typeCtrl.text)
                              ? typeCtrl.text
                              : propertyTypeOptions.first.value,
                          items: propertyTypeOptions
                              .map((opt) => DropdownMenuItem(
                                    value: opt.value,
                                    child: Text(opt.label),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              typeCtrl.text = val;
                            }
                          },
                          decoration:
                              const InputDecoration(labelText: 'Objektart'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: unitsCtrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Einheiten *'),
                          validator: (v) => int.tryParse(v ?? '') == null
                              ? 'Ungültige Zahl'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _DialogSectionHeader('Adresse'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: addr1Ctrl,
                          decoration: const InputDecoration(
                            labelText: 'Straße & Hausnummer *',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Pflichtfeld'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: addr2Ctrl,
                          decoration:
                              const InputDecoration(labelText: 'Zusatz'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: zipCtrl,
                          decoration:
                              const InputDecoration(labelText: 'PLZ *'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Pflichtfeld'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: cityCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Ort *'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Pflichtfeld'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: countryCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Land *'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Pflichtfeld'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _DialogSectionHeader('Flächen & Parken'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: resAreaCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Wohnfläche (m²)',
                            suffixText: 'm²',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: comAreaCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Gewerbefläche (m²)',
                            suffixText: 'm²',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: landAreaCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Grundstücksfläche (m²)',
                            suffixText: 'm²',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: parkingCtrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Stellplätze'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _DialogSectionHeader('Kauf & Rechtliches'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: purchasePriceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Kaufpreis (€)',
                            suffixText: '€',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InputDecorator(
                          decoration:
                              const InputDecoration(labelText: 'Kaufdatum'),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  purchaseDate != null
                                      ? formatOverviewDate(
                                          purchaseDate!.millisecondsSinceEpoch,
                                        )
                                      : '-',
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.calendar_today,
                                  size: 18,
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: purchaseDate ?? DateTime.now(),
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => purchaseDate = picked);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: sellerCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Verkäufer'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: notaryCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Notar'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: registryCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Grundbuchdaten',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: parcelCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Flurstück'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _DialogSectionHeader('Dokumentation & Steuern'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: energyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Energieausweis',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: insuranceCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Versicherungsdaten',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: taxCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Steuerliche Zuordnung',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notizen'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final updatedProperty = PropertyRecord(
                  id: property.id,
                  name: nameCtrl.text.trim(),
                  addressLine1: addr1Ctrl.text.trim(),
                  addressLine2: addr2Ctrl.text.trim().isEmpty
                      ? null
                      : addr2Ctrl.text.trim(),
                  zip: zipCtrl.text.trim(),
                  city: cityCtrl.text.trim(),
                  country: countryCtrl.text.trim(),
                  propertyType: typeCtrl.text,
                  units: int.parse(unitsCtrl.text.trim()),
                  sqft: property.sqft,
                  yearBuilt: property.yearBuilt,
                  notes: notesCtrl.text.trim().isEmpty
                      ? null
                      : notesCtrl.text.trim(),
                  createdAt: property.createdAt,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                  archived: property.archived,
                  landArea: double.tryParse(landAreaCtrl.text.trim()),
                  residentialArea: double.tryParse(resAreaCtrl.text.trim()),
                  commercialArea: double.tryParse(comAreaCtrl.text.trim()),
                  parkingSpots: int.tryParse(parkingCtrl.text.trim()),
                  ownerCompany: ownerCtrl.text.trim().isEmpty
                      ? null
                      : ownerCtrl.text.trim(),
                  purchaseDate: purchaseDate?.millisecondsSinceEpoch,
                  purchasePrice:
                      double.tryParse(purchasePriceCtrl.text.trim()),
                  notary: notaryCtrl.text.trim().isEmpty
                      ? null
                      : notaryCtrl.text.trim(),
                  seller: sellerCtrl.text.trim().isEmpty
                      ? null
                      : sellerCtrl.text.trim(),
                  landRegistryDetails: registryCtrl.text.trim().isEmpty
                      ? null
                      : registryCtrl.text.trim(),
                  parcel: parcelCtrl.text.trim().isEmpty
                      ? null
                      : parcelCtrl.text.trim(),
                  energyCertificate: energyCtrl.text.trim().isEmpty
                      ? null
                      : energyCtrl.text.trim(),
                  insuranceDetails: insuranceCtrl.text.trim().isEmpty
                      ? null
                      : insuranceCtrl.text.trim(),
                  taxAssignment: taxCtrl.text.trim().isEmpty
                      ? null
                      : taxCtrl.text.trim(),
                );
                await ref
                    .read(propertiesControllerProvider.notifier)
                    .updateProperty(updatedProperty);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
}

class _DialogSectionHeader extends StatelessWidget {
  const _DialogSectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const Divider(),
      ],
    );
  }
}
