import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'property_detail/property_shell.dart';
import '../state/app_state.dart';
import '../state/property_state.dart';
import '../theme/app_theme.dart';
import '../utils/number_parse.dart';

class PropertiesScreen extends ConsumerWidget {
  const PropertiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPropertyId = ref.watch(selectedPropertyIdProvider);
    if (selectedPropertyId != null) {
      return const PropertyShell();
    }

    final propertiesAsync = ref.watch(propertiesControllerProvider);
    final controller = ref.read(propertiesControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _openCreateDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('New Property'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: controller.reload,
                child: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: propertiesAsync.when(
              data: (properties) {
                if (properties.isEmpty) {
                  return const Card(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.section),
                        child: Text('No properties yet.'),
                      ),
                    ),
                  );
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.component),
                    child: SingleChildScrollView(
                      child: DataTable(
                        sortAscending: false,
                        sortColumnIndex: 3,
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Address')),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Updated ↓')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows:
                            properties
                                .map(
                                  (property) => DataRow(
                                    cells: [
                                      DataCell(Text(property.name)),
                                      DataCell(
                                        Text(
                                          '${property.addressLine1}, ${property.city}',
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF4FA),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: AppColors.border,
                                            ),
                                          ),
                                          child: Text(property.propertyType),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          DateTime.fromMillisecondsSinceEpoch(
                                            property.updatedAt,
                                          ).toIso8601String(),
                                        ),
                                      ),
                                      DataCell(
                                        Wrap(
                                          spacing: 8,
                                          children: [
                                            TextButton(
                                              onPressed: () {
                                                ref
                                                    .read(
                                                      selectedScenarioIdProvider
                                                          .notifier,
                                                    )
                                                    .state = null;
                                                ref
                                                    .read(
                                                      selectedPropertyIdProvider
                                                          .notifier,
                                                    )
                                                    .state = property.id;
                                                ref
                                                    .read(
                                                      propertyDetailPageProvider
                                                          .notifier,
                                                    )
                                                    .state = PropertyDetailPage
                                                        .overview;
                                              },
                                              child: const Text('Open'),
                                            ),
                                            TextButton(
                                              onPressed:
                                                  () => controller.archive(
                                                    property.id,
                                                    true,
                                                  ),
                                              child: const Text('Archive'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final address = TextEditingController();
    final city = TextEditingController(text: 'Berlin');
    final zip = TextEditingController(text: '10115');
    final country = TextEditingController(text: 'DE');
    final type = TextEditingController(text: 'single_family');
    final units = TextEditingController(text: '1');
    final strategy = TextEditingController(text: 'rental');
    final price = TextEditingController(text: '250000');
    final rent = TextEditingController(text: '1800');
    final rehab = TextEditingController(text: '20000');
    final financing = TextEditingController(text: 'loan');

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Property (Wizard MVP)'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: address,
                      decoration: const InputDecoration(labelText: 'Address'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: city,
                      decoration: const InputDecoration(labelText: 'City'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: zip,
                      decoration: const InputDecoration(labelText: 'ZIP'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: country,
                      decoration: const InputDecoration(labelText: 'Country'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: type,
                      decoration: const InputDecoration(
                        labelText: 'Property Type',
                      ),
                    ),
                    TextFormField(
                      controller: units,
                      decoration: const InputDecoration(labelText: 'Units'),
                    ),
                    TextFormField(
                      controller: strategy,
                      decoration: const InputDecoration(
                        labelText: 'Strategy (rental/flip/brrrr)',
                      ),
                    ),
                    TextFormField(
                      controller: price,
                      decoration: const InputDecoration(
                        labelText: 'Purchase Price',
                      ),
                    ),
                    TextFormField(
                      controller: rent,
                      decoration: const InputDecoration(
                        labelText: 'Rent Monthly',
                      ),
                    ),
                    TextFormField(
                      controller: rehab,
                      decoration: const InputDecoration(
                        labelText: 'Rehab Budget',
                      ),
                    ),
                    TextFormField(
                      controller: financing,
                      decoration: const InputDecoration(
                        labelText: 'Financing (cash/loan)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) {
                  return;
                }

                final property = await ref
                    .read(propertiesControllerProvider.notifier)
                    .createPropertyWithBaseScenario(
                      name: name.text.trim(),
                      address: address.text.trim(),
                      city: city.text.trim(),
                      zip: zip.text.trim(),
                      country: country.text.trim(),
                      propertyType: type.text.trim(),
                      units: parseIntFlexible(units.text) ?? 1,
                      strategyType: strategy.text.trim(),
                      purchasePrice: parseDoubleFlexible(price.text) ?? 0,
                      rentMonthly: parseDoubleFlexible(rent.text) ?? 0,
                      rehabBudget: parseDoubleFlexible(rehab.text) ?? 0,
                      financingMode: financing.text.trim(),
                    );

                if (property != null && context.mounted) {
                  ref.read(selectedScenarioIdProvider.notifier).state = null;
                  ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.overview;
                  ref.read(selectedPropertyIdProvider.notifier).state =
                      property.id;
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (created == true) {
      ref.read(propertiesControllerProvider.notifier).reload();
    }

    name.dispose();
    address.dispose();
    city.dispose();
    zip.dispose();
    country.dispose();
    type.dispose();
    units.dispose();
    strategy.dispose();
    price.dispose();
    rent.dispose();
    rehab.dispose();
    financing.dispose();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }
}
