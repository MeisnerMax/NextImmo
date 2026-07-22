import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/portfolio_analytics.dart';
import '../../core/models/property.dart';
import '../components/nx_data_table_shell.dart';
import '../components/nx_empty_state.dart';
import '../components/nx_status_badge.dart';
import 'properties/property_creation_workflow_screen.dart';
import 'properties/widgets/portfolio_kpi_header.dart';
import 'properties/widgets/property_card.dart';
import 'properties/widgets/property_table.dart';
import '../state/app_state.dart';
import '../state/property_state.dart';
import '../templates/list_filter_template.dart';
import '../theme/app_theme.dart';
import 'property_detail/property_shell.dart';

enum _PropertiesView { table, cards }

class PropertiesScreen extends ConsumerStatefulWidget {
  const PropertiesScreen({super.key});

  @override
  ConsumerState<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends ConsumerState<PropertiesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _sortKey = 'updated_desc';
  _PropertiesView _view = _PropertiesView.table;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPropertyId = ref.watch(selectedPropertyIdProvider);
    if (selectedPropertyId != null) {
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
        SegmentedButton<_PropertiesView>(
          segments: const [
            ButtonSegment(
              value: _PropertiesView.table,
              icon: Icon(Icons.table_rows_outlined),
              tooltip: 'Tabellenansicht',
            ),
            ButtonSegment(
              value: _PropertiesView.cards,
              icon: Icon(Icons.grid_view_outlined),
              tooltip: 'Kartenansicht',
            ),
          ],
          selected: {_view},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              setState(() => _view = selection.first),
        ),
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
          SizedBox(
            width: context.viewport == AppViewport.mobile ? 180 : 220,
            child: DropdownButtonFormField<String>(
              value: _sortKey,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Sortierung',
                prefixIcon: Icon(Icons.sort_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'updated_desc',
                  child: Text('Neueste zuerst'),
                ),
                DropdownMenuItem(
                  value: 'updated_asc',
                  child: Text('Älteste zuerst'),
                ),
                DropdownMenuItem(
                  value: 'name_asc',
                  child: Text('Name A-Z'),
                ),
                DropdownMenuItem(
                  value: 'name_desc',
                  child: Text('Name Z-A'),
                ),
                DropdownMenuItem(
                  value: 'city_asc',
                  child: Text('Ort A-Z'),
                ),
                DropdownMenuItem(
                  value: 'value_desc',
                  child: Text('Marktwert'),
                ),
                DropdownMenuItem(
                  value: 'yield_desc',
                  child: Text('Rendite'),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _sortKey = value);
              },
            ),
          ),
        ],
      ),
      scrollable: true,
      expandContent: false,
      content: propertiesAsync.when(
        data: (properties) => _buildLoadedContent(context, properties),
        loading: () => const _PropertiesSkeleton(),
        error: (error, _) => NxEmptyState(
          title: 'Objekte konnten nicht geladen werden',
          description:
              'Beim Laden der Objektliste ist ein Fehler aufgetreten. '
              'Bitte versuchen Sie es erneut.',
          icon: Icons.error_outline,
          primaryAction: ElevatedButton.icon(
            onPressed: controller.reload,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadedContent(
    BuildContext context,
    List<PropertyRecord> properties,
  ) {
    bool matchesQuery(PropertyRecord property) {
      if (_query.isEmpty) {
        return true;
      }
      final haystack =
          '${property.name} ${property.addressLine1} ${property.city} ${property.propertyType}'
              .toLowerCase();
      return haystack.contains(_query);
    }

    final activeProperties = properties
        .where((property) => !property.archived)
        .toList(growable: false);
    final filteredActive =
        activeProperties.where(matchesQuery).toList(growable: false);
    final filteredArchived = properties
        .where((property) => property.archived && matchesQuery(property))
        .toList(growable: false);
    final hasMatches = filteredActive.isNotEmpty || filteredArchived.isNotEmpty;
    final hasAnyProperty = properties.isNotEmpty;
    final activePropertyIds =
        activeProperties.map((property) => property.id).toSet();

    return FutureBuilder<PortfolioMetricsSnapshot>(
      future: _loadPortfolioMetrics(activePropertyIds),
      builder: (context, snapshot) {
        final metrics = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        if (isLoading && metrics == null) {
          return const _PropertiesSkeleton();
        }

        final safeMetrics = metrics ??
            const PortfolioMetricsSnapshot(
              totalValue: 0,
              totalAcquisitionCosts: 0,
              netYield: 0,
              vacancyRate: 0,
              ltv: 0,
              totalLoanPrincipal: 0,
              propertyKpis: {},
            );
        final sortedActive = _sortProperties(filteredActive, safeMetrics);
        final sortedArchived = _sortProperties(filteredArchived, safeMetrics);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activeProperties.isNotEmpty) ...[
              PortfolioKpiHeader(metrics: safeMetrics),
              const SizedBox(height: AppSpacing.component),
            ],
            if (!hasMatches)
              NxEmptyState(
                title:
                    hasAnyProperty ? 'Keine Treffer' : 'Keine Objekte vorhanden',
                description: hasAnyProperty
                    ? 'Versuchen Sie es mit einem anderen Suchbegriff.'
                    : 'Erstellen Sie Ihr erstes Objekt, um mit der Analyse zu starten.',
                icon: Icons.home_work_outlined,
                primaryAction: hasAnyProperty
                    ? null
                    : ElevatedButton.icon(
                        onPressed: () => _openCreateDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Objekt erstellen'),
                      ),
              )
            else if (_view == _PropertiesView.table)
              PropertyTable(
                properties: [...sortedActive, ...sortedArchived],
                metrics: safeMetrics,
                onOpen: (property) => _openProperty(property, ref),
                onImages: (property) => _openPropertyImages(property, ref),
                onArchiveToggle: (property) => ref
                    .read(propertiesControllerProvider.notifier)
                    .archive(property.id, !property.archived),
                onDelete: (property) => _confirmDelete(context, property),
                onRestore: (property) => ref
                    .read(propertiesControllerProvider.notifier)
                    .restore(property.id),
              )
            else ...[
              if (sortedActive.isNotEmpty) ...[
                if (sortedArchived.isNotEmpty)
                  _buildSectionTitle(
                    context,
                    'Aktive Objekte',
                    '${sortedActive.length}',
                  ),
                _buildPropertyGrid(context, sortedActive, safeMetrics),
              ],
              if (sortedArchived.isNotEmpty) ...[
                if (sortedActive.isNotEmpty)
                  const SizedBox(height: AppSpacing.section),
                _buildSectionTitle(
                  context,
                  'Archivierte Objekte',
                  '${sortedArchived.length}',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildPropertyGrid(context, sortedArchived, safeMetrics),
              ],
            ],
          ],
        );
      },
    );
  }

  Future<PortfolioMetricsSnapshot> _loadPortfolioMetrics(
    Set<String> activePropertyIds,
  ) {
    return ref
        .read(portfolioAnalyticsRepositoryProvider)
        .loadOverviewMetrics(activePropertyIds: activePropertyIds);
  }

  List<PropertyRecord> _sortProperties(
    List<PropertyRecord> properties,
    PortfolioMetricsSnapshot metrics,
  ) {
    final sorted = [...properties];
    int compareText(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());
    double marketValue(PropertyRecord property) =>
        metrics.propertyKpis[property.id]?.estimatedMarketValue ?? 0;
    double yieldValue(PropertyRecord property) =>
        metrics.propertyKpis[property.id]?.propertyYield ?? 0;

    switch (_sortKey) {
      case 'updated_asc':
        sorted.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        break;
      case 'name_asc':
        sorted.sort((a, b) => compareText(a.name, b.name));
        break;
      case 'name_desc':
        sorted.sort((a, b) => compareText(b.name, a.name));
        break;
      case 'city_asc':
        sorted.sort((a, b) {
          final cityCompare = compareText(a.city, b.city);
          return cityCompare == 0 ? compareText(a.name, b.name) : cityCompare;
        });
        break;
      case 'value_desc':
        sorted.sort((a, b) {
          final valueCompare = marketValue(b).compareTo(marketValue(a));
          return valueCompare == 0 ? compareText(a.name, b.name) : valueCompare;
        });
        break;
      case 'yield_desc':
        sorted.sort((a, b) {
          final yieldCompare = yieldValue(b).compareTo(yieldValue(a));
          return yieldCompare == 0 ? compareText(a.name, b.name) : yieldCompare;
        });
        break;
      case 'updated_desc':
      default:
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
    }
    return sorted;
  }

  Widget _buildSectionTitle(BuildContext context, String title, String count) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(width: 8),
        NxStatusBadge(label: count, kind: NxBadgeKind.neutral),
      ],
    );
  }

  Widget _buildPropertyGrid(
    BuildContext context,
    List<PropertyRecord> properties,
    PortfolioMetricsSnapshot metrics,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width < 640 ? 1 : (width < 900 ? 2 : 4);
        final childAspectRatio =
            width < 640 ? 0.62 : (width < 900 ? 0.58 : 0.54);

        return GridView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: AppSpacing.component,
            mainAxisSpacing: AppSpacing.component,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: properties.length,
          itemBuilder: (context, index) {
            final property = properties[index];
            final kpis = metrics.propertyKpis[property.id];
            return PropertyCard(
              property: property,
              kpis: kpis,
              onOpen: () => _openProperty(property, ref),
              onImages: () => _openPropertyImages(property, ref),
              onArchiveToggle: () => ref
                  .read(propertiesControllerProvider.notifier)
                  .archive(property.id, !property.archived),
              onDelete: () => _confirmDelete(context, property),
              onRestore: () => ref
                  .read(propertiesControllerProvider.notifier)
                  .restore(property.id),
            );
          },
        );
      },
    );
  }

  Future<void> _openCreateDialog(BuildContext context, WidgetRef ref) async {
    final existingProperties =
        ref.read(propertiesControllerProvider).valueOrNull ??
            <PropertyRecord>[];
    final property = await showDialog<PropertyRecord>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: PropertyCreationWorkflowScreen(
          existingProperties: existingProperties,
          onCreateProperty: (draft, assessment) => ref
              .read(propertiesControllerProvider.notifier)
              .createPropertyFromDraft(
                draft: draft,
                assessment: assessment,
              ),
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

  Future<void> _confirmDelete(
    BuildContext context,
    PropertyRecord property,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Objekt löschen'),
            content: Text(
              '"${property.name}" wird gelöscht und aus den aktiven Listen '
              'entfernt. Einheiten, Mietverträge, Kosten, Dokumente und '
              'Historie bleiben erhalten — du kannst das Objekt später über die '
              'Archiv-/Gelöscht-Ansicht wiederherstellen.',
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
                child: const Text('Löschen'),
              ),
            ],
          ),
    );
    if (shouldDelete != true || !mounted) {
      return;
    }
    await ref
        .read(propertiesControllerProvider.notifier)
        .tombstone(property.id);
  }
}

/// Layout-shaped loading state: KPI tile placeholders plus an empty table
/// shell, instead of a full-page spinner.
class _PropertiesSkeleton extends StatelessWidget {
  const _PropertiesSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PortfolioKpiHeaderSkeleton(),
        SizedBox(height: AppSpacing.component),
        NxDataTableShell(
          loading: true,
          child: SizedBox.shrink(),
        ),
      ],
    );
  }
}
