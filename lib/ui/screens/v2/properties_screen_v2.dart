import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/portfolio_analytics.dart';
import '../../../core/models/property.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../i18n/app_strings.dart';
import '../properties/create_property_dialog.dart';
import '../properties/property_creation_workflow_screen.dart';
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
  String _sortKey = 'updated_desc';

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
        data: (properties) {
          final activeProperties = properties
              .where((property) => !property.archived)
              .toList(growable: false);
          final archivedProperties = properties
              .where((property) => property.archived)
              .toList(growable: false);
          final filteredActive = activeProperties
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
          final filteredArchived = archivedProperties
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
                return const Center(child: CircularProgressIndicator());
              }

              final safeMetrics = metrics ?? const PortfolioMetricsSnapshot(
                totalValue: 0,
                totalAcquisitionCosts: 0,
                netYield: 0,
                vacancyRate: 0,
                ltv: 0,
                totalLoanPrincipal: 0,
                propertyKpis: {},
              );
              final sortedActive = _sortProperties(filteredActive, safeMetrics);
              final sortedArchived =
                  _sortProperties(filteredArchived, safeMetrics);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (activeProperties.isNotEmpty) ...[
                    _buildKpisHeader(context, safeMetrics),
                    const SizedBox(height: AppSpacing.component),
                  ],
                  if (!hasMatches)
                    NxEmptyState(
                      title: hasAnyProperty ? 'Keine Treffer' : 'Keine Objekte vorhanden',
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
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Future<PortfolioMetricsSnapshot> _loadPortfolioMetrics(
    Set<String> activePropertyIds,
  ) {
    return ref
        .read(portfolioAnalyticsRepositoryProvider)
        .loadOverviewMetrics(activePropertyIds: activePropertyIds);
  }

  Widget _buildKpisHeader(
    BuildContext context,
    PortfolioMetricsSnapshot metrics,
  ) {
    final ltvColor = metrics.ltv < 0.60
        ? context.semanticColors.success
        : (metrics.ltv <= 0.75 ? context.semanticColors.warning : context.semanticColors.error);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth < 640
            ? constraints.maxWidth
            : (constraints.maxWidth - 3 * AppSpacing.component) / 4;

        final cardList = [
          _KpiCardSpec(
            title: 'PORTFOLIO-GESAMTWERT',
            value: '${_formatCurrency(metrics.totalValue)} / ${_formatCurrency(metrics.totalAcquisitionCosts)}',
            valueStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          _KpiCardSpec(
            title: 'Ø MIETRENDITE',
            value: _formatPercent(metrics.netYield),
            valueStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          _KpiCardSpec(
            title: 'GESAMT-LEERSTAND',
            value: _formatPercent(metrics.vacancyRate),
            valueStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: metrics.vacancyRate > 0.10
                      ? context.semanticColors.warning
                      : context.semanticColors.success,
                ),
          ),
          _KpiCardSpec(
            title: 'PORTFOLIO-LTV',
            value: _formatPercent(metrics.ltv),
            valueStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ltvColor,
                ),
          ),
        ];

        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: cardList
              .map((spec) => SizedBox(
                    width: width,
                    child: NxCard(
                      variant: NxCardVariant.kpi,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spec.title,
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: context.semanticColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              spec.value,
                              style: (spec.valueStyle ?? Theme.of(context).textTheme.titleLarge ?? const TextStyle()).merge(context.tabularNumericStyle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  List<PropertyRecord> _sortProperties(
    List<PropertyRecord> properties,
    PortfolioMetricsSnapshot metrics,
  ) {
    final sorted = [...properties];
    int compareText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
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
            return _buildPropertyCard(context, property, kpis);
          },
        );
      },
    );
  }

  Widget _buildPropertyCard(
    BuildContext context,
    PropertyRecord property,
    PropertyPortfolioKpis? kpis,
  ) {
    final theme = Theme.of(context);
    
    final marketValue = kpis?.estimatedMarketValue ?? 0.0;
    final yieldVal = kpis?.propertyYield ?? 0.0;
    final cashflow = kpis?.cashflowMonthly ?? 0.0;
    final occupied = kpis?.occupiedUnits ?? 0;
    final totalUnits = kpis?.units ?? 0;

    return NxCard(
      variant: NxCardVariant.interactive,
      onTap: () => _openProperty(property, ref),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              _PropertyCover(property: property),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Text(
                    context.strings.text(propertyTypeDisplayLabel(property.propertyType)),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${property.addressLine1}, ${property.city}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.semanticColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (property.archived) ...[
                  const SizedBox(height: 6),
                  const NxStatusBadge(
                    label: 'Archiviert',
                    kind: NxBadgeKind.neutral,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            context,
                            'Marktwert',
                            _formatCurrency(marketValue),
                            Icons.analytics_outlined,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricTile(
                            context,
                            'Rendite',
                            _formatPercent(yieldVal),
                            Icons.trending_up,
                            valueColor: yieldVal > 0.05
                                ? context.semanticColors.success
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            context,
                            'Cashflow',
                            '${cashflow.toStringAsFixed(0)} €/M',
                            Icons.euro_symbol,
                            valueColor: cashflow > 0
                                ? context.semanticColors.success
                                : (cashflow < 0 ? context.semanticColors.error : null),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricTile(
                            context,
                            'Belegung',
                            '$occupied / $totalUnits Einheiten',
                            Icons.people_alt_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Aktualisiert: ${_formatDate(property.updatedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.semanticColors.textSecondary,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _PropertyActions(
                  onOpen: () => _openProperty(property, ref),
                  onImages: () => _openPropertyImages(property, ref),
                  archived: property.archived,
                  dense: true,
                  onArchiveToggle: () => ref
                      .read(propertiesControllerProvider.notifier)
                      .archive(property.id, !property.archived),
                  onDelete: () => _confirmPermanentDelete(context, property),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: context.semanticColors.textSecondary.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w600,
                    color: context.semanticColors.textSecondary,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 10.5,
                    color: valueColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)} Mio. €';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}k €';
    }
    return '${value.toStringAsFixed(0)} €';
  }

  String _formatPercent(double value) {
    return '${(value * 100).toStringAsFixed(1)}%';
  }

  Future<void> _openCreateDialog(BuildContext context, WidgetRef ref) async {
    final existingProperties =
        ref.read(propertiesControllerProvider).valueOrNull ?? <PropertyRecord>[];
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

class _PropertyCover extends ConsumerWidget {
  const _PropertyCover({required this.property});

  final PropertyRecord property;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleImageAsync = ref.watch(propertyTitleImageProvider(property.id));
    final colors = _coverColors(property.propertyType);
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        child: titleImageAsync.when(
          data: (path) => _buildWithBody(path, colors, context),
          loading: () => const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => _buildWithBody(null, colors, context),
        ),
      ),
    );
  }

  Widget _buildWithBody(String? path, List<Color> colors, BuildContext context) {
    Widget base;
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        base = Image.file(file, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
      } else {
        base = _fallbackBox(colors, context);
      }
    } else {
      base = _fallbackBox(colors, context);
    }

    return base;
  }

  Widget _fallbackBox(List<Color> colors, BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.component),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Icon(
            _coverIcon(property.propertyType),
            color: Colors.white,
            size: 34,
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
    required this.archived,
    required this.onArchiveToggle,
    required this.onDelete,
    this.dense = false,
  });

  final VoidCallback onOpen;
  final VoidCallback onImages;
  final bool archived;
  final VoidCallback onArchiveToggle;
  final VoidCallback onDelete;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final openAction = dense
        ? IconButton.filledTonal(
            tooltip: 'Öffnen',
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_outlined, size: 18),
            visualDensity: VisualDensity.compact,
          )
        : FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_outlined, size: 14),
            label: const Text('Öffnen'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        openAction,
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'Weitere Aktionen',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'images') {
              onImages();
            }
            if (value == 'archiveToggle') {
              onArchiveToggle();
            }
            if (value == 'delete') {
              onDelete();
            }
          },
          itemBuilder:
              (context) => [
                const PopupMenuItem(
                  value: 'images',
                  child: Row(
                    children: [
                      Icon(Icons.photo_library_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Bilder & Dokumente'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'archiveToggle',
                  child: Row(
                    children: [
                      Icon(
                        archived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(archived ? 'Wiederherstellen' : 'Archivieren'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Endgültig löschen', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
        ),
      ],
    );
  }
}

class _KpiCardSpec {
  const _KpiCardSpec({
    required this.title,
    required this.value,
    this.valueStyle,
  });

  final String title;
  final String value;
  final TextStyle? valueStyle;
}
