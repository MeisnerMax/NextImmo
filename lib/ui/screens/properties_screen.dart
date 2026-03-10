import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/property.dart';
import '../i18n/app_strings.dart';
import 'property_detail/property_shell.dart';
import 'properties/create_property_dialog.dart';
import '../state/app_state.dart';
import '../state/property_state.dart';
import '../theme/app_theme.dart';

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
                                          child: Text(
                                            context.strings.text(
                                              propertyTypeDisplayLabel(
                                                property.propertyType,
                                              ),
                                            ),
                                          ),
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
    final property = await showDialog<PropertyRecord>(
      context: context,
      builder:
          (dialogContext) => CreatePropertyDialog(
            onCreateProperty:
                (draft) => ref
                    .read(propertiesControllerProvider.notifier)
                    .createPropertyWithBaseScenario(
                      name: draft.name,
                      address: draft.address,
                      city: draft.city,
                      zip: draft.zip,
                      country: draft.country,
                      propertyType: draft.propertyType,
                      units: draft.units,
                      strategyType: 'rental',
                      purchasePrice: 0,
                      rentMonthly: 0,
                      rehabBudget: 0,
                      financingMode: 'cash',
                    ),
          ),
    );

    if (property != null && context.mounted) {
      ref.read(selectedScenarioIdProvider.notifier).state = null;
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.overview;
      ref.read(selectedPropertyIdProvider.notifier).state = property.id;
    }
  }
}
