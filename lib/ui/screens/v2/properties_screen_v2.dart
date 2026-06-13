import 'dart:io';

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
                prefixIcon: const Icon(Icons.search),
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

          return FutureBuilder<_PortfolioMetricsData>(
            future: _loadPortfolioMetrics(),
            builder: (context, snapshot) {
              final metrics = snapshot.data;
              final isLoading = snapshot.connectionState == ConnectionState.waiting;

              if (isLoading && metrics == null) {
                return const Center(child: CircularProgressIndicator());
              }

              final safeMetrics = metrics ?? const _PortfolioMetricsData(
                totalValue: 0,
                totalAcquisitionCosts: 0,
                netYield: 0,
                vacancyRate: 0,
                ltv: 0,
                totalLoanPrincipal: 0,
                propertyKpis: {},
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (filtered.isNotEmpty) ...[
                    _buildKpisHeader(context, safeMetrics),
                    const SizedBox(height: AppSpacing.component),
                  ],
                  Expanded(
                    child: filtered.isEmpty
                        ? NxEmptyState(
                            title: properties.isEmpty ? 'Keine Objekte vorhanden' : 'Keine Treffer',
                            description: properties.isEmpty
                                ? 'Erstellen Sie Ihr erstes Objekt, um mit der Analyse zu starten.'
                                : 'Versuchen Sie es mit einem anderen Suchbegriff.',
                            icon: Icons.home_work_outlined,
                            primaryAction: properties.isEmpty
                                ? ElevatedButton.icon(
                                    onPressed: () => _openCreateDialog(context, ref),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Objekt erstellen'),
                                  )
                                : null,
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: MediaQuery.of(context).size.width < 640
                                  ? 1
                                  : (MediaQuery.of(context).size.width < 1100 ? 2 : 3),
                              crossAxisSpacing: AppSpacing.component,
                              mainAxisSpacing: AppSpacing.component,
                              childAspectRatio: MediaQuery.of(context).size.width < 640
                                  ? 0.95
                                  : (MediaQuery.of(context).size.width < 1100 ? 0.78 : 0.75),
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final property = filtered[index];
                              final kpis = safeMetrics.propertyKpis[property.id];
                              return _buildPropertyCard(context, property, kpis);
                            },
                          ),
                  ),
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

  Future<_PortfolioMetricsData> _loadPortfolioMetrics() async {
    final db = ref.read(databaseProvider);
    final rentalOverview = await ref.read(assetWorkbookRepositoryProvider).loadPortfolioOverview();

    final purchasePriceRows = await db.rawQuery('''
      SELECT s.property_id, si.purchase_price
      FROM scenario_inputs si
      INNER JOIN scenarios s ON s.id = si.scenario_id
      WHERE s.is_base = 1
    ''');
    final purchasePrices = {
      for (final row in purchasePriceRows)
        row['property_id'] as String: ((row['purchase_price'] as num?) ?? 0).toDouble()
    };

    final loanRows = await db.rawQuery('''
      SELECT asset_property_id, SUM(principal) AS loan_total
      FROM loans
      GROUP BY asset_property_id
    ''');
    final loanTotals = {
      for (final row in loanRows)
        row['asset_property_id'] as String: ((row['loan_total'] as num?) ?? 0).toDouble()
    };

    final rentableUnits = rentalOverview.rentedUnits + rentalOverview.emptyUnits;
    final vacancyRate = rentableUnits == 0 ? 0.0 : rentalOverview.emptyUnits / rentableUnits;

    final opex = rentalOverview.annualOperatingCosts;
    final annualRent = rentalOverview.annualRent;
    final noi = annualRent - opex;

    final estimatedMarketValue = noi <= 0 ? 0.0 : noi / 0.055;

    var totalAcquisitionCosts = 0.0;
    for (final price in purchasePrices.values) {
      totalAcquisitionCosts += price;
    }

    var totalLoanPrincipal = 0.0;
    for (final loan in loanTotals.values) {
      totalLoanPrincipal += loan;
    }

    final netYield = totalAcquisitionCosts <= 0 ? 0.0 : noi / totalAcquisitionCosts;
    final portfolioLtv = estimatedMarketValue <= 0 ? 0.0 : totalLoanPrincipal / estimatedMarketValue;

    final propertyKpis = <String, _PropertyKpis>{};
    for (final row in rentalOverview.rows) {
      final pId = row.propertyId;
      final pPrice = purchasePrices[pId] ?? 0.0;
      final pNoi = row.annualRent - row.annualOperatingCosts;
      final pYield = pPrice > 0 ? pNoi / pPrice : 0.0;
      final pCashflow = pNoi / 12;
      final pMarketValue = pNoi <= 0 ? 0.0 : pNoi / 0.055;
      final pBkQuote = row.annualRent > 0 ? row.annualOperatingCosts / row.annualRent : 0.0;
      propertyKpis[pId] = _PropertyKpis(
        propertyYield: pYield,
        cashflowMonthly: pCashflow,
        estimatedMarketValue: pMarketValue,
        units: row.units,
        occupiedUnits: row.occupiedUnits,
        annualOperatingCosts: row.annualOperatingCosts,
        bkQuote: pBkQuote,
        serviceChargeBalance: row.serviceChargeBalance,
      );
    }

    return _PortfolioMetricsData(
      totalValue: estimatedMarketValue,
      totalAcquisitionCosts: totalAcquisitionCosts,
      netYield: netYield,
      vacancyRate: vacancyRate,
      ltv: portfolioLtv,
      totalLoanPrincipal: totalLoanPrincipal,
      propertyKpis: propertyKpis,
    );
  }

  Widget _buildKpisHeader(BuildContext context, _PortfolioMetricsData metrics) {
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

  Widget _buildPropertyCard(BuildContext context, PropertyRecord property, _PropertyKpis? kpis) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final marketValue = kpis?.estimatedMarketValue ?? 0.0;
    final yieldVal = kpis?.propertyYield ?? 0.0;
    final cashflow = kpis?.cashflowMonthly ?? 0.0;
    final occupied = kpis?.occupiedUnits ?? 0;
    final totalUnits = kpis?.units ?? 0;
    final operatingCosts = kpis?.annualOperatingCosts ?? 0.0;
    final bkQuote = kpis?.bkQuote ?? 0.0;
    final bkSaldo = kpis?.serviceChargeBalance ?? 0.0;

    return NxCard(
      variant: NxCardVariant.interactive,
      onTap: () => _openProperty(property, ref),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
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
                  style: theme.textTheme.titleMedium?.copyWith(
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
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
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            context,
                            'Betriebskosten',
                            '${_formatCurrency(operatingCosts)} (${_formatPercent(bkQuote)})',
                            Icons.receipt_long_outlined,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricTile(
                            context,
                            'BK-Saldo',
                            '${bkSaldo >= 0 ? '+' : ''}${bkSaldo.toStringAsFixed(0)} €',
                            Icons.account_balance_wallet_outlined,
                            valueColor: bkSaldo > 0
                                ? context.semanticColors.success
                                : (bkSaldo < 0 ? context.semanticColors.error : null),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
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
                  onArchive: () => ref.read(propertiesControllerProvider.notifier).archive(property.id, true),
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: context.semanticColors.textSecondary.withOpacity(0.8),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: context.semanticColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
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

class _PropertyCover extends ConsumerWidget {
  const _PropertyCover({required this.property, this.compact = false, this.kpis});

  final PropertyRecord property;
  final bool compact;
  final _PropertyKpis? kpis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleImageAsync = ref.watch(propertyTitleImageProvider(property.id));
    final colors = _coverColors(property.propertyType);
    return AspectRatio(
      aspectRatio: compact ? 1.45 : 2.8,
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

    if (compact || kpis == null) {
      return base;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        base,
        Positioned(
          bottom: 8,
          left: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Rendite: ${(kpis!.propertyYield * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Cashflow: ${kpis!.cashflowMonthly.toStringAsFixed(0)} €/M',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Leerstand: ${kpis!.units - kpis!.occupiedUnits}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new_outlined, size: 14),
          label: const Text('Öffnen'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'Weitere Aktionen',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'images') {
              onImages();
            }
            if (value == 'archive') {
              onArchive();
            }
            if (value == 'delete') {
              onDelete();
            }
          },
          itemBuilder:
              (context) => const [
                PopupMenuItem(
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
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(Icons.archive_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Archivieren'),
                    ],
                  ),
                ),
                PopupMenuItem(
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

class _PortfolioMetricsData {
  const _PortfolioMetricsData({
    required this.totalValue,
    required this.totalAcquisitionCosts,
    required this.netYield,
    required this.vacancyRate,
    required this.ltv,
    required this.totalLoanPrincipal,
    required this.propertyKpis,
  });

  final double totalValue;
  final double totalAcquisitionCosts;
  final double netYield;
  final double vacancyRate;
  final double ltv;
  final double totalLoanPrincipal;
  final Map<String, _PropertyKpis> propertyKpis;
}

class _PropertyKpis {
  const _PropertyKpis({
    required this.propertyYield,
    required this.cashflowMonthly,
    required this.estimatedMarketValue,
    required this.units,
    required this.occupiedUnits,
    required this.annualOperatingCosts,
    required this.bkQuote,
    required this.serviceChargeBalance,
  });
  final double propertyYield;
  final double cashflowMonthly;
  final double estimatedMarketValue;
  final int units;
  final int occupiedUnits;
  final double annualOperatingCosts;
  final double bkQuote;
  final double serviceChargeBalance;
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
