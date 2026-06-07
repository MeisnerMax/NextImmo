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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Objekt-Management',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Erfassen, bewirtschaften und analysieren Sie Ihre Liegenschaften.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.semanticColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _openCreateDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('New Property'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: controller.reload,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: propertiesAsync.when(
              data: (properties) {
                if (properties.isEmpty) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(color: context.semanticColors.border),
                      borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
                    ),
                    child: const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.section),
                        child: Text('No properties yet.'),
                      ),
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(color: context.semanticColors.border),
                    borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.component),
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: double.infinity,
                        child: DataTable(
                          sortAscending: false,
                          sortColumnIndex: 3,
                          headingRowColor: WidgetStateProperty.all(
                            context.semanticColors.surfaceAlt,
                          ),
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
                                        DataCell(
                                          Text(
                                            property.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '${property.addressLine1}, ${property.city}',
                                          ),
                                        ),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                                              borderRadius: BorderRadius.circular(999),
                                              border: Border.all(
                                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                              ),
                                            ),
                                            child: Text(
                                              context.strings.text(
                                                propertyTypeDisplayLabel(
                                                  property.propertyType,
                                                ),
                                              ),
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.primary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            DateTime.fromMillisecondsSinceEpoch(
                                              property.updatedAt,
                                            ).toIso8601String(),
                                            style: context.tabularNumericStyle,
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
                                              TextButton(
                                                onPressed:
                                                    () => _confirmPermanentDelete(
                                                      context,
                                                      ref,
                                                      property,
                                                    ),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      Theme.of(
                                                        context,
                                                      ).colorScheme.error,
                                                ),
                                                child: const Text(
                                                  'Endgültig löschen',
                                                ),
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

  Future<void> _confirmPermanentDelete(
    BuildContext context,
    WidgetRef ref,
    PropertyRecord property,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Objekt endgültig löschen'),
            content: Text(
              '"${property.name}" wird vollständig entfernt. Dazu gehören '
              'Einheiten, Mietverträge, Kosten, Dokumente, Aufgaben und '
              'Verknüpfungen. Diese Aktion kann nicht rückgängig gemacht '
              'werden.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  foregroundColor:
                      Theme.of(dialogContext).colorScheme.onError,
                ),
                child: const Text('Endgültig löschen'),
              ),
            ],
          ),
    );
    if (shouldDelete != true || !context.mounted) {
      return;
    }
    await ref
        .read(propertiesControllerProvider.notifier)
        .deletePermanently(property.id);
  }
}
