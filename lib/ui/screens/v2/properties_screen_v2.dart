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
      breadcrumbs: const ['Assets & Portfolio', 'Properties'],
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
                      _PropertyCover(property: property),
                      const SizedBox(height: 12),
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
                      _PropertyActions(
                        onOpen: () => _openProperty(property, ref),
                        onImages: () => _openPropertyImages(property, ref),
                        onArchive: () => controller.archive(property.id, true),
                        onDelete:
                            () => _confirmPermanentDelete(context, property),
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
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 72,
                                child: _PropertyCover(
                                  property: property,
                                  compact: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 220,
                                child: Text(
                                  property.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
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
                          _PropertyActions(
                            dense: true,
                            onOpen: () => _openProperty(property, ref),
                            onImages: () => _openPropertyImages(property, ref),
                            onArchive:
                                () => controller.archive(property.id, true),
                            onDelete:
                                () =>
                                    _confirmPermanentDelete(context, property),
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

  void _openPropertyImages(PropertyRecord property, WidgetRef ref) {
    ref.read(selectedScenarioIdProvider.notifier).state = null;
    ref.read(selectedPropertyIdProvider.notifier).state = property.id;
    ref.read(propertyDetailPageProvider.notifier).state =
        PropertyDetailPage.documents;
  }

  Future<void> _confirmPermanentDelete(
    BuildContext context,
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
    if (shouldDelete != true || !mounted) {
      return;
    }
    await ref
        .read(propertiesControllerProvider.notifier)
        .deletePermanently(property.id);
  }

  String _formatDate(int millis) {
    return DateTime.fromMillisecondsSinceEpoch(
      millis,
    ).toIso8601String().substring(0, 10);
  }
}

class _PropertyCover extends StatelessWidget {
  const _PropertyCover({required this.property, this.compact = false});

  final PropertyRecord property;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = _coverColors(property.propertyType);
    return AspectRatio(
      aspectRatio: compact ? 1.45 : 2.8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: context.semanticColors.border),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : AppSpacing.component),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Icon(
              _coverIcon(property.propertyType),
              color: Colors.white,
              size: compact ? 20 : 34,
            ),
          ),
        ),
      ),
    );
  }

  List<Color> _coverColors(String propertyType) {
    switch (propertyType.toLowerCase()) {
      case 'commercial':
      case 'office':
        return const [Color(0xFF0F766E), Color(0xFF164E63)];
      case 'mixed_use':
      case 'mixed-use':
        return const [Color(0xFF7C3AED), Color(0xFF0F766E)];
      case 'hotel':
        return const [Color(0xFFB45309), Color(0xFF7F1D1D)];
      default:
        return const [Color(0xFF1D4ED8), Color(0xFF334155)];
    }
  }

  IconData _coverIcon(String propertyType) {
    switch (propertyType.toLowerCase()) {
      case 'commercial':
      case 'office':
        return Icons.business_outlined;
      case 'hotel':
        return Icons.hotel_outlined;
      default:
        return Icons.apartment_outlined;
    }
  }
}

class _PropertyActions extends StatelessWidget {
  const _PropertyActions({
    required this.onOpen,
    required this.onImages,
    required this.onArchive,
    required this.onDelete,
    this.dense = false,
  });

  final VoidCallback onOpen;
  final VoidCallback onImages;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (!dense) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_outlined, size: 16),
            label: const Text('Öffnen'),
          ),
          OutlinedButton.icon(
            onPressed: onImages,
            icon: const Icon(Icons.photo_library_outlined, size: 16),
            label: const Text('Bilder'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Weitere Aktionen',
            onSelected: (value) {
              if (value == 'archive') {
                onArchive();
              }
              if (value == 'delete') {
                onDelete();
              }
            },
            itemBuilder:
                (context) => const [
                  PopupMenuItem(value: 'archive', child: Text('Archivieren')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Endgültig löschen'),
                  ),
                ],
          ),
        ],
      );
    }
    return Wrap(
      spacing: 4,
      children: [
        IconButton(
          tooltip: 'Öffnen',
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new_outlined),
        ),
        IconButton(
          tooltip: 'Bilder und Dokumente',
          onPressed: onImages,
          icon: const Icon(Icons.photo_library_outlined),
        ),
        PopupMenuButton<String>(
          tooltip: 'Weitere Aktionen',
          onSelected: (value) {
            if (value == 'archive') {
              onArchive();
            }
            if (value == 'delete') {
              onDelete();
            }
          },
          itemBuilder:
              (context) => const [
                PopupMenuItem(value: 'archive', child: Text('Archivieren')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Endgültig löschen'),
                ),
              ],
        ),
      ],
    );
  }
}
