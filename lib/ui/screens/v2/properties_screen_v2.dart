import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/property.dart';
import '../../components/nx_card.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../i18n/app_strings.dart';
import '../properties/create_property_dialog.dart';
import '../../state/app_state.dart';
import '../../state/property_state.dart';
import '../../state/ui_feature_flags.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';
import '../property_detail/property_shell.dart';
import 'property_detail/property_shell_v2.dart';

class PropertiesScreenV2 extends ConsumerStatefulWidget {
  const PropertiesScreenV2({super.key});

  @override
  ConsumerState<PropertiesScreenV2> createState() => _PropertiesScreenV2State();
}

class _PropertiesScreenV2State extends ConsumerState<PropertiesScreenV2> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPropertyId = ref.watch(selectedPropertyIdProvider);
    final propertyShellV2Enabled = ref.watch(
      uiScreenFlagProvider(UiScreenFlag.propertyShellV2),
    );
    if (selectedPropertyId != null) {
      if (propertyShellV2Enabled) {
        return const PropertyShellV2();
      }
      return const PropertyShell();
    }

    final propertiesAsync = ref.watch(propertiesControllerProvider);
    final controller = ref.read(propertiesControllerProvider.notifier);

    return ListFilterTemplate(
      title: 'Properties',
      breadcrumbs: const ['Portfolio', 'Properties'],
      subtitle:
          'Manage assets, filter the portfolio, and open each property workflow.',
      primaryAction: ElevatedButton.icon(
        onPressed: () => _openCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Property'),
      ),
      secondaryActions: [
        OutlinedButton(
          onPressed: controller.reload,
          child: const Text('Refresh'),
        ),
      ],
      filters: ListFilterBar(
        children: [
          SizedBox(
            width: context.viewport == AppViewport.mobile ? 180 : 260,
            child: TextField(
              controller: _searchController,
              onChanged:
                  (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
              decoration: const InputDecoration(
                labelText: 'Search properties',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
        ],
      ),
      content: propertiesAsync.when(
        data: (properties) {
          final filtered = properties
              .where((property) {
                if (_query.isEmpty) {
                  return true;
                }
                final haystack =
                    '${property.name} ${property.addressLine1} ${property.city} ${property.propertyType}'
                        .toLowerCase();
                return haystack.contains(_query);
              })
              .toList(growable: false);
          if (filtered.isEmpty) {
            return NxEmptyState(
              title: properties.isEmpty ? 'No properties yet' : 'No match',
              description:
                  properties.isEmpty
                      ? 'Create your first property to start portfolio analysis.'
                      : 'Try another filter or clear the current search.',
              icon: Icons.home_work_outlined,
              primaryAction:
                  properties.isEmpty
                      ? ElevatedButton.icon(
                        onPressed: () => _openCreateDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Create Property'),
                      )
                      : null,
            );
          }

          return NxDataTableShell(
            minTableWidth: 980,
            mobileBreakpoint: 980,
            mobileChild: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.component),
              itemCount: filtered.length,
              separatorBuilder:
                  (_, __) => const SizedBox(height: AppSpacing.component),
              itemBuilder: (context, index) {
                final property = filtered[index];
                return NxCard(
                  variant: NxCardVariant.interactive,
                  onTap: () => _openProperty(property, ref),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  property.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${property.addressLine1}, ${property.city}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          NxStatusBadge(
                            label: context.strings.text(
                              propertyTypeDisplayLabel(property.propertyType),
                            ),
                            kind: NxBadgeKind.info,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Updated ${_formatDate(property.updatedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _openProperty(property, ref),
                            child: const Text('Open'),
                          ),
                          TextButton(
                            onPressed:
                                () => controller.archive(property.id, true),
                            child: const Text('Archive'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
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
              rows: filtered
                  .map(
                    (property) => DataRow(
                      cells: [
                        DataCell(Text(property.name)),
                        DataCell(
                          Text('${property.addressLine1}, ${property.city}'),
                        ),
                        DataCell(
                          NxStatusBadge(
                            label: context.strings.text(
                              propertyTypeDisplayLabel(property.propertyType),
                            ),
                            kind: NxBadgeKind.info,
                          ),
                        ),
                        DataCell(Text(_formatDate(property.updatedAt))),
                        DataCell(
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => _openProperty(property, ref),
                                child: const Text('Open'),
                              ),
                              TextButton(
                                onPressed:
                                    () => controller.archive(property.id, true),
                                child: const Text('Archive'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
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
      _openProperty(property, ref);
    }
  }

  void _openProperty(PropertyRecord property, WidgetRef ref) {
    ref.read(selectedScenarioIdProvider.notifier).state = null;
    ref.read(selectedPropertyIdProvider.notifier).state = property.id;
    ref.read(propertyDetailPageProvider.notifier).state =
        PropertyDetailPage.overview;
  }

  String _formatDate(int millis) {
    return DateTime.fromMillisecondsSinceEpoch(
      millis,
    ).toIso8601String().substring(0, 10);
  }
}
