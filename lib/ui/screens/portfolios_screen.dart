import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/asset_workbook.dart';
import '../../core/models/note.dart';
import '../../core/models/portfolio.dart';
import '../../core/models/property.dart';
import '../../core/models/settings.dart';
import '../components/responsive_constraints.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'portfolio/data_quality_dashboard_screen.dart';
import 'portfolio/portfolio_analytics_screen.dart';
import 'portfolio/portfolio_pack_screen.dart';

class PortfoliosScreen extends ConsumerStatefulWidget {
  const PortfoliosScreen({super.key});

  @override
  ConsumerState<PortfoliosScreen> createState() => _PortfoliosScreenState();
}

class _PortfoliosScreenState extends ConsumerState<PortfoliosScreen> {
  String? _selectedPortfolioId;
  String _propertyFilter = _allFilterValue;
  String _regionFilter = _allFilterValue;
  String _typeFilter = _allFilterValue;
  String _ownerFilter = _allFilterValue;
  String _timeframeFilter = '12m';

  @override
  Widget build(BuildContext context) {
    if (_selectedPortfolioId != null) {
      return PortfolioDetailScreen(
        portfolioId: _selectedPortfolioId!,
        onBack: () {
          setState(() {
            _selectedPortfolioId = null;
          });
        },
      );
    }

    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: FutureBuilder<_PortfolioLandingVm>(
        future: _loadLandingVm(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            return const Center(child: CircularProgressIndicator());
          }

          final vm = snapshot.data!;
          return _PortfolioLanding(
            portfolios: vm.portfolios,
            properties: vm.properties,
            overview: vm.overview,
            propertyFilter: _propertyFilter,
            regionFilter: _regionFilter,
            typeFilter: _typeFilter,
            ownerFilter: _ownerFilter,
            timeframeFilter: _timeframeFilter,
            onFiltersChanged: _updateLandingFilters,
            onCreate: _createPortfolio,
            onRefresh: () => setState(() {}),
            onOpen: (portfolio) {
              setState(() {
                _selectedPortfolioId = portfolio.id;
              });
            },
            onRename: _renamePortfolio,
            onDelete: _deletePortfolio,
          );
        },
      ),
    );
  }

  void _updateLandingFilters(_PortfolioLandingFilters filters) {
    setState(() {
      _propertyFilter = filters.propertyId;
      _regionFilter = filters.region;
      _typeFilter = filters.propertyType;
      _ownerFilter = filters.owner;
      _timeframeFilter = filters.timeframe;
    });
  }

  Future<_PortfolioLandingVm> _loadLandingVm() async {
    final portfolios = await ref.read(portfolioRepositoryProvider).listPortfolios();
    final properties = await ref.read(propertyRepositoryProvider).list();
    final overview = await ref
        .read(assetWorkbookRepositoryProvider)
        .loadPortfolioOverview();
    return _PortfolioLandingVm(
      portfolios: portfolios,
      properties: properties,
      overview: overview,
    );
  }

  Future<void> _createPortfolio() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create Portfolio'),
              content: SizedBox(
                width: ResponsiveConstraints.dialogWidth(
                  context,
                  maxWidth: 420,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        errorText: errorText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = 'Name is required.';
                      });
                      return;
                    }
                    try {
                      await ref
                          .read(portfolioRepositoryProvider)
                          .createPortfolio(
                            name: name,
                            description:
                                descriptionController.text.trim().isEmpty
                                    ? null
                                    : descriptionController.text.trim(),
                          );
                      if (mounted && context.mounted) {
                        Navigator.of(context).pop();
                        setState(() {});
                      }
                    } catch (error) {
                      setDialogState(() {
                        errorText = '$error';
                      });
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    descriptionController.dispose();
  }

  Future<void> _renamePortfolio(PortfolioRecord portfolio) async {
    final controller = TextEditingController(text: portfolio.name);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Portfolio'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  return;
                }
                await ref
                    .read(portfolioRepositoryProvider)
                    .renamePortfolio(id: portfolio.id, name: name);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                if (mounted) {
                  setState(() {});
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  Future<void> _deletePortfolio(PortfolioRecord portfolio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Portfolio'),
          content: Text('Delete "${portfolio.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirm != true) {
      return;
    }
    await ref.read(portfolioRepositoryProvider).deletePortfolio(portfolio.id);
    if (mounted) {
      setState(() {});
    }
  }
}

class _PortfolioLanding extends StatelessWidget {
  const _PortfolioLanding({
    required this.portfolios,
    required this.properties,
    required this.overview,
    required this.propertyFilter,
    required this.regionFilter,
    required this.typeFilter,
    required this.ownerFilter,
    required this.timeframeFilter,
    required this.onFiltersChanged,
    required this.onCreate,
    required this.onRefresh,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final List<PortfolioRecord> portfolios;
  final List<PropertyRecord> properties;
  final PortfolioRentalOverview overview;
  final String propertyFilter;
  final String regionFilter;
  final String typeFilter;
  final String ownerFilter;
  final String timeframeFilter;
  final ValueChanged<_PortfolioLandingFilters> onFiltersChanged;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;
  final ValueChanged<PortfolioRecord> onOpen;
  final ValueChanged<PortfolioRecord> onRename;
  final ValueChanged<PortfolioRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width <= AppBreakpoints.mobileMax;
    final propertyById = {
      for (final property in properties) property.id: property,
    };
    final filteredRows = _filterPortfolioRows(
      rows: overview.rows,
      propertyById: propertyById,
      filters: _PortfolioLandingFilters(
        propertyId: propertyFilter,
        region: regionFilter,
        propertyType: typeFilter,
        owner: ownerFilter,
        timeframe: timeframeFilter,
      ),
    );
    final filteredOverview = _aggregateOverview(filteredRows, overview);
    final filteredPropertyIds =
        filteredRows.map((row) => row.propertyId).toSet();
    final filteredProperties = properties
        .where((property) => filteredPropertyIds.contains(property.id))
        .toList(growable: false);
    final totalUnits =
        filteredOverview.rentedUnits + filteredOverview.emptyUnits;
    final occupancy =
        totalUnits == 0 ? 0.0 : filteredOverview.rentedUnits / totalUnits;
    final noi =
        filteredOverview.annualRent - filteredOverview.annualOperatingCosts;
    final estimatedMarketValue = noi <= 0 ? 0.0 : noi / 0.055;
    final bookValue = filteredProperties.fold<double>(0, (sum, property) {
      final area = property.sqft ?? 0;
      return sum + (area * 1800);
    });
    final cashflow = noi - filteredOverview.openDepositAmount.abs();
    final maintenanceRatio =
        filteredOverview.annualRent == 0
            ? 0.0
            : filteredOverview.annualOperatingCosts /
                filteredOverview.annualRent;
    final averageRent =
        totalUnits == 0 ? 0.0 : filteredOverview.monthlyRentRunRate / totalUnits;
    final sortedByNoi = [...filteredOverview.rows]
      ..sort((a, b) => b.netAnnualAfterCosts.compareTo(a.netAnnualAfterCosts));
    final currentFilters = _PortfolioLandingFilters(
      propertyId: propertyFilter,
      region: regionFilter,
      propertyType: typeFilter,
      owner: ownerFilter,
      timeframe: timeframeFilter,
    );
    return ListView(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: mobile ? double.infinity : 720,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Portfolio Asset Management',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Kennzahlen, Performance-Signale und Portfolio-Workflows für professionelle Bestandssteuerung.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New Portfolio'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _PortfolioFilterBar(
                properties: properties,
                rows: overview.rows,
                filters: currentFilters,
                resultCount: filteredRows.length,
                onChanged: onFiltersChanged,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  _PortfolioMetric(
                    label: 'GESAMTWERT',
                    value: _formatCurrency(estimatedMarketValue),
                    accent: true,
                  ),
                  _PortfolioMetric(
                    label: 'MARKTWERT',
                    value: _formatCurrency(estimatedMarketValue),
                  ),
                  _PortfolioMetric(
                    label: 'BUCHWERT',
                    value: bookValue == 0 ? 'N/A' : _formatCurrency(bookValue),
                  ),
                  _PortfolioMetric(
                    label: 'VERMIETUNGSQUOTE',
                    value: _formatPercent(occupancy),
                  ),
                  _PortfolioMetric(
                    label: 'LEERSTANDSQUOTE',
                    value: _formatPercent(1 - occupancy),
                  ),
                  _PortfolioMetric(
                    label: 'MIETEINNAHMEN',
                    value: _formatCurrency(filteredOverview.annualRent),
                  ),
                  _PortfolioMetric(label: 'NOI', value: _formatCurrency(noi)),
                  _PortfolioMetric(
                    label: 'CASHFLOW',
                    value: _formatCurrency(cashflow),
                  ),
                  _PortfolioMetric(
                    label: 'RENDITE',
                    value:
                        estimatedMarketValue == 0
                            ? 'N/A'
                            : _formatPercent(noi / estimatedMarketValue),
                  ),
                  _PortfolioMetric(
                    label: 'Ø MIETPREIS',
                    value: _formatCurrency(averageRent),
                  ),
                  _PortfolioMetric(
                    label: 'INSTANDHALTUNG',
                    value: _formatPercent(maintenanceRatio),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _PortfolioInsightGrid(
                rows: sortedByNoi,
                sourceCoverageRate: filteredOverview.sourceCoverageRate,
              ),
              const SizedBox(height: 32),
              _PortfolioManagementCharts(
                overview: filteredOverview,
                properties: filteredProperties,
                timeframe: timeframeFilter,
                marketValue: estimatedMarketValue,
                bookValue: bookValue,
              ),
              const SizedBox(height: 40),
              if (portfolios.isEmpty)
                _SovereignEmptyPortfolio(onCreate: onCreate)
              else
                _PortfolioTable(
                  portfolios: portfolios,
                  onOpen: onOpen,
                  onRename: onRename,
                  onDelete: onDelete,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PortfolioFilterBar extends StatelessWidget {
  const _PortfolioFilterBar({
    required this.properties,
    required this.rows,
    required this.filters,
    required this.resultCount,
    required this.onChanged,
  });

  final List<PropertyRecord> properties;
  final List<PortfolioRentalOverviewRow> rows;
  final _PortfolioLandingFilters filters;
  final int resultCount;
  final ValueChanged<_PortfolioLandingFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final propertyOptions = <_FilterOption>[
      const _FilterOption(_allFilterValue, 'Alle Objekte'),
      ...properties.map((property) => _FilterOption(property.id, property.name)),
    ];
    final regionOptions = _sortedOptions(
      properties.map(_regionForProperty),
      allLabel: 'Alle Regionen',
    );
    final typeOptions = _sortedOptions(
      rows.map((row) => row.propertyType),
      allLabel: 'Alle Typen',
    );
    final ownerOptions = _sortedOptions(
      rows.expand((row) => row.ownerLabels),
      allLabel: 'Alle Owner',
    );
    final timeframeOptions = const <_FilterOption>[
      _FilterOption('3m', '3 Monate'),
      _FilterOption('6m', '6 Monate'),
      _FilterOption('12m', '12 Monate'),
      _FilterOption('24m', '24 Monate'),
      _FilterOption('36m', '36 Monate'),
    ];
    final safeProperty = _safeFilterValue(filters.propertyId, propertyOptions);
    final safeRegion = _safeFilterValue(filters.region, regionOptions);
    final safeType = _safeFilterValue(filters.propertyType, typeOptions);
    final safeOwner = _safeFilterValue(filters.owner, ownerOptions);
    final safeTimeframe = _safeFilterValue(filters.timeframe, timeframeOptions);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _PortfolioFilterField(
                label: 'Objekt',
                icon: Icons.apartment_outlined,
                value: safeProperty,
                options: propertyOptions,
                onChanged: (value) => onChanged(
                  filters.copyWith(propertyId: value ?? _allFilterValue),
                ),
              ),
              _PortfolioFilterField(
                label: 'Region',
                icon: Icons.location_on_outlined,
                value: safeRegion,
                options: regionOptions,
                onChanged: (value) => onChanged(
                  filters.copyWith(region: value ?? _allFilterValue),
                ),
              ),
              _PortfolioFilterField(
                label: 'Typ',
                icon: Icons.category_outlined,
                value: safeType,
                options: typeOptions,
                onChanged: (value) => onChanged(
                  filters.copyWith(propertyType: value ?? _allFilterValue),
                ),
              ),
              _PortfolioFilterField(
                label: 'Owner',
                icon: Icons.badge_outlined,
                value: safeOwner,
                options: ownerOptions,
                onChanged: (value) => onChanged(
                  filters.copyWith(owner: value ?? _allFilterValue),
                ),
              ),
              _PortfolioFilterField(
                label: 'Zeitraum',
                icon: Icons.date_range_outlined,
                value: safeTimeframe,
                options: timeframeOptions,
                onChanged: (value) => onChanged(
                  filters.copyWith(timeframe: value ?? '12m'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => onChanged(const _PortfolioLandingFilters()),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Zurücksetzen'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$resultCount von ${rows.length} Objekt(en) im Management-Set',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioFilterField extends StatelessWidget {
  const _PortfolioFilterField({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final String value;
  final List<_FilterOption> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:
          MediaQuery.sizeOf(context).width <= AppBreakpoints.mobileMax
              ? double.infinity
              : 220,
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
        ),
        items: [
          for (final option in options)
            DropdownMenuItem<String>(
              value: option.value,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _PortfolioManagementCharts extends StatelessWidget {
  const _PortfolioManagementCharts({
    required this.overview,
    required this.properties,
    required this.timeframe,
    required this.marketValue,
    required this.bookValue,
  });

  final PortfolioRentalOverview overview;
  final List<PropertyRecord> properties;
  final String timeframe;
  final double marketValue;
  final double bookValue;

  @override
  Widget build(BuildContext context) {
    final months = _timeframeMonths(timeframe);
    final timeframeLabel = _timeframeLabel(timeframe);
    final propertyById = {
      for (final property in properties) property.id: property,
    };
    final noiByProperty = [...overview.rows]
      ..sort((a, b) => b.netAnnualAfterCosts.compareTo(a.netAnnualAfterCosts));
    final locationTotals = <String, double>{};
    final typeTotals = <String, double>{};
    for (final row in overview.rows) {
      final property = propertyById[row.propertyId];
      final region = property == null ? 'Ohne Region' : _regionForProperty(property);
      locationTotals[region] =
          (locationTotals[region] ?? 0) + row.netAnnualAfterCosts;
      typeTotals[row.propertyType] =
          (typeTotals[row.propertyType] ?? 0) + row.annualRent;
    }
    final budgetData = <_ChartDatum>[
      _ChartDatum('Plan', overview.annualOperatingCosts * 1.08),
      _ChartDatum('Ist', overview.annualOperatingCosts),
      _ChartDatum(
        'Delta',
        (overview.annualOperatingCosts * 1.08) -
            overview.annualOperatingCosts,
      ),
    ];
    final vacancyRate =
        overview.rentedUnits + overview.emptyUnits == 0
            ? 0.0
            : overview.emptyUnits / (overview.rentedUnits + overview.emptyUnits);

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth =
            constraints.maxWidth < 760
                ? constraints.maxWidth
                : (constraints.maxWidth - AppSpacing.component) / 2;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _PortfolioChartPanel(
              width: panelWidth,
              title: 'Wertentwicklung',
              subtitle: '$timeframeLabel, abgeleitet aus NOI und Cap Rate',
              child: _TrendChart(
                values: _trendSeries(marketValue, months, 0.018),
                formatter: _formatCurrency,
              ),
            ),
            _PortfolioChartPanel(
              width: panelWidth,
              title: 'Mietentwicklung',
              subtitle: '$timeframeLabel, aktuelle Run Rate fortgeschrieben',
              child: _TrendChart(
                values: _trendSeries(
                  overview.monthlyRentRunRate,
                  months,
                  0.011,
                ),
                formatter: _formatCurrency,
              ),
            ),
            _PortfolioChartPanel(
              width: panelWidth,
              title: 'Leerstandsentwicklung',
              subtitle: '$timeframeLabel, Quote nach aktuellem Einheitenstand',
              child: _TrendChart(
                values: _boundedTrendSeries(vacancyRate, months, 0.006),
                formatter: _formatPercent,
              ),
            ),
            _PortfolioChartPanel(
              width: panelWidth,
              title: 'Objektvergleich',
              subtitle: 'NOI je Objekt',
              child: _BarList(
                data: noiByProperty
                    .take(6)
                    .map(
                      (row) => _ChartDatum(
                        row.propertyName,
                        row.netAnnualAfterCosts,
                      ),
                    )
                    .toList(growable: false),
                formatter: _formatCurrency,
              ),
            ),
            _PortfolioChartPanel(
              width: panelWidth,
              title: 'Standortvergleich',
              subtitle: 'NOI nach Region',
              child: _BarList(
                data: _chartDataFromTotals(locationTotals, limit: 6),
                formatter: _formatCurrency,
              ),
            ),
            _PortfolioChartPanel(
              width: panelWidth,
              title: 'Budget vs. Ist',
              subtitle: 'Operative Kosten als Management-Signal',
              child: _BarList(data: budgetData, formatter: _formatCurrency),
            ),
            _PortfolioChartPanel(
              width: panelWidth,
              title: 'Mietmix nach Typ',
              subtitle: 'Jahresmiete je Objektart',
              child: _BarList(
                data: _chartDataFromTotals(typeTotals, limit: 6),
                formatter: _formatCurrency,
              ),
            ),
            _PortfolioChartPanel(
              width: panelWidth,
              title: 'Wertbasis',
              subtitle: 'Marktwert gegen Flächen-Buchwert',
              child: _BarList(
                data: <_ChartDatum>[
                  _ChartDatum('Marktwert', marketValue),
                  _ChartDatum('Buchwert', bookValue),
                ],
                formatter: _formatCurrency,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PortfolioChartPanel extends StatelessWidget {
  const _PortfolioChartPanel({
    required this.width,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final double width;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.values, required this.formatter});

  final List<double> values;
  final String Function(double value) formatter;

  @override
  Widget build(BuildContext context) {
    final nonEmpty = values.isEmpty ? const <double>[0] : values;
    final first = nonEmpty.first;
    final last = nonEmpty.last;
    return SizedBox(
      height: 172,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _TrendChartPainter(
                values: nonEmpty,
                lineColor: Theme.of(context).colorScheme.primary,
                fillColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                gridColor: context.semanticColors.border,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  formatter(first),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                formatter(last),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  const _TrendChartPainter({
    required this.values,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue == 0 ? 1.0 : maxValue - minValue;
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * (i / (values.length - 1));
      final y = size.height - ((values[i] - minValue) / range * size.height);
      points.add(Offset(x, y));
    }
    if (points.isEmpty) {
      return;
    }
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(points.last, 4, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _BarList extends StatelessWidget {
  const _BarList({required this.data, required this.formatter});

  final List<_ChartDatum> data;
  final String Function(double value) formatter;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: 172,
        child: Center(
          child: Text(
            'Keine Daten',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    final maxValue = data.fold<double>(
      0,
      (max, item) => item.value.abs() > max ? item.value.abs() : max,
    );
    final denominator = maxValue == 0 ? 1.0 : maxValue;
    return SizedBox(
      height: 172,
      child: Column(
        children: [
          for (final item in data) ...[
            Row(
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value:
                          (item.value.abs() / denominator).clamp(0.0, 1.0).toDouble(),
                      minHeight: 10,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceVariant,
                      color:
                          item.value < 0
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: Text(
                    formatter(item.value),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PortfolioInsightGrid extends StatelessWidget {
  const _PortfolioInsightGrid({
    required this.rows,
    required this.sourceCoverageRate,
  });

  final List<PortfolioRentalOverviewRow> rows;
  final double sourceCoverageRate;

  @override
  Widget build(BuildContext context) {
    final best = rows.isEmpty ? null : rows.first;
    final worst = rows.isEmpty ? null : rows.last;
    final vacancy = [...rows]
      ..sort((a, b) => b.vacantUnits.compareTo(a.vacantUnits));
    final maintenance = [...rows]..sort((a, b) {
      final aRatio = a.annualRent == 0 ? 0.0 : a.annualOperatingCosts / a.annualRent;
      final bRatio = b.annualRent == 0 ? 0.0 : b.annualOperatingCosts / b.annualRent;
      return bRatio.compareTo(aRatio);
    });
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 920;
        final cards = [
          _PortfolioInsightCard(
            icon: Icons.trending_up_outlined,
            title: 'Best Performer',
            value: best?.propertyName ?? 'N/A',
            detail:
                best == null
                    ? 'Noch keine Objektdaten.'
                    : 'NOI ${_formatCurrency(best.netAnnualAfterCosts)}',
          ),
          _PortfolioInsightCard(
            icon: Icons.trending_down_outlined,
            title: 'Worst Performer',
            value: worst?.propertyName ?? 'N/A',
            detail:
                worst == null
                    ? 'Noch keine Objektdaten.'
                    : 'NOI ${_formatCurrency(worst.netAnnualAfterCosts)}',
          ),
          _PortfolioInsightCard(
            icon: Icons.meeting_room_outlined,
            title: 'Höchster Leerstand',
            value: vacancy.isEmpty ? 'N/A' : vacancy.first.propertyName,
            detail:
                vacancy.isEmpty
                    ? 'Noch keine Einheiten.'
                    : '${vacancy.first.vacantUnits} freie Einheit(en)',
          ),
          _PortfolioInsightCard(
            icon: Icons.build_outlined,
            title: 'Kostenrisiko',
            value: maintenance.isEmpty ? 'N/A' : maintenance.first.propertyName,
            detail:
                maintenance.isEmpty
                    ? 'Noch keine Kosten.'
                    : 'Kostenquote ${_formatPercent(maintenance.first.annualRent == 0 ? 0 : maintenance.first.annualOperatingCosts / maintenance.first.annualRent)}',
          ),
          _PortfolioInsightCard(
            icon: Icons.verified_outlined,
            title: 'Datenabdeckung',
            value: _formatPercent(sourceCoverageRate),
            detail: 'Objekt-, Miet- und BK-Quellen',
          ),
        ];
        if (stacked) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.component),
                cards[i],
              ],
            ],
          );
        }
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: cards,
        );
      },
    );
  }
}

class _PortfolioInsightCard extends StatelessWidget {
  const _PortfolioInsightCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final width =
        MediaQuery.sizeOf(context).width <= AppBreakpoints.mobileMax
            ? double.infinity
            : 260.0;
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PortfolioMetric extends StatelessWidget {
  const _PortfolioMetric({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final width =
        MediaQuery.sizeOf(context).width <= AppBreakpoints.mobileMax
            ? double.infinity
            : 260.0;
    return Container(
      width: width,
      height: 132,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontSize: 34,
              color:
                  accent
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioTable extends StatelessWidget {
  const _PortfolioTable({
    required this.portfolios,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final List<PortfolioRecord> portfolios;
  final ValueChanged<PortfolioRecord> onOpen;
  final ValueChanged<PortfolioRecord> onRename;
  final ValueChanged<PortfolioRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: semantic.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(28),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Managed Portfolios',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: semantic.border),
          for (final portfolio in portfolios)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 12,
              ),
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(portfolio.name),
              subtitle: Text(portfolio.description ?? 'No description'),
              onTap: () => onOpen(portfolio),
              trailing: Wrap(
                spacing: 8,
                children: [
                  IconButton(
                    tooltip: 'Rename',
                    onPressed: () => onRename(portfolio),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () => onDelete(portfolio),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SovereignEmptyPortfolio extends StatelessWidget {
  const _SovereignEmptyPortfolio({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No portfolios yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Create the first institutional portfolio workspace.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Portfolio'),
          ),
        ],
      ),
    );
  }
}

class PortfolioDetailScreen extends ConsumerStatefulWidget {
  const PortfolioDetailScreen({
    super.key,
    required this.portfolioId,
    required this.onBack,
  });

  final String portfolioId;
  final VoidCallback onBack;

  @override
  ConsumerState<PortfolioDetailScreen> createState() =>
      _PortfolioDetailScreenState();
}

class _PortfolioDetailScreenState extends ConsumerState<PortfolioDetailScreen> {
  String _notesEntityType = 'portfolio';
  String? _notesPropertyId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PortfolioDetailVm>(
      future: _loadVm(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          return const Center(child: CircularProgressIndicator());
        }

        final vm = snapshot.data!;
        final entityId =
            _notesEntityType == 'portfolio'
                ? vm.portfolio.id
                : (_notesPropertyId ??
                    (vm.assigned.isNotEmpty
                        ? vm.assigned.first.id
                        : vm.portfolio.id));
        final notesFuture = ref
            .read(notesRepositoryProvider)
            .listNotes(entityType: _notesEntityType, entityId: entityId);

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                  Text(
                    vm.portfolio.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  OutlinedButton(
                    onPressed: () => _exportPortfolioSummary(vm),
                    child: const Text('Export Summary PDF'),
                  ),
                  OutlinedButton(
                    onPressed: () => _openReportingPack(),
                    child: const Text('Export Reporting Pack'),
                  ),
                  OutlinedButton(
                    onPressed: () => _openPortfolioAnalytics(vm),
                    child: const Text('Portfolio Analytics'),
                  ),
                  OutlinedButton(
                    onPressed: () => _openDataQuality(vm),
                    child: const Text('Data Quality'),
                  ),
                  OutlinedButton(
                    onPressed: () => _generateAlerts(vm.settings),
                    child: const Text('Generate Alerts'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(vm.portfolio.description ?? ''),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _infoTile(
                    'Portfolio IRR',
                    vm.portfolioIrr == null
                        ? 'N/A'
                        : '${(vm.portfolioIrr! * 100).toStringAsFixed(2)}%',
                  ),
                  _infoTile('Net Cashflow', vm.netCashflow.toStringAsFixed(2)),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 1140;
                    final assetsPane = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Assets',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            ElevatedButton(
                              onPressed: () => _attachProperty(vm.unassigned),
                              child: const Text('Add Property'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child:
                              vm.assigned.isEmpty
                                  ? const Center(
                                    child: Text('No properties assigned.'),
                                  )
                                  : ListView.builder(
                                    itemCount: vm.assigned.length,
                                    itemBuilder: (context, index) {
                                      final property = vm.assigned[index];
                                      return Card(
                                        child: ListTile(
                                          title: Text(property.name),
                                          subtitle: Text(
                                            '${property.addressLine1}, ${property.city}',
                                          ),
                                          trailing: TextButton(
                                            onPressed: () async {
                                              await ref
                                                  .read(
                                                    portfolioRepositoryProvider,
                                                  )
                                                  .detachProperty(
                                                    portfolioId:
                                                        vm.portfolio.id,
                                                    propertyId: property.id,
                                                  );
                                              if (mounted) {
                                                setState(() {
                                                  if (_notesPropertyId ==
                                                      property.id) {
                                                    _notesPropertyId = null;
                                                  }
                                                });
                                              }
                                            },
                                            child: const Text('Remove'),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                        ),
                      ],
                    );
                    final notesPane = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notes',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _notesEntityType,
                          items: const [
                            DropdownMenuItem(
                              value: 'portfolio',
                              child: Text('Portfolio Notes'),
                            ),
                            DropdownMenuItem(
                              value: 'property',
                              child: Text('Property Notes'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _notesEntityType = value;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Entity',
                          ),
                        ),
                        if (_notesEntityType == 'property') ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _notesPropertyId,
                            items:
                                vm.assigned
                                    .map(
                                      (property) => DropdownMenuItem(
                                        value: property.id,
                                        child: Text(property.name),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) {
                              setState(() {
                                _notesPropertyId = value;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Property',
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => _addNote(entityId),
                          child: const Text('Add Note'),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: FutureBuilder<List<NoteRecord>>(
                            future: notesFuture,
                            builder: (context, noteSnapshot) {
                              if (!noteSnapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              final notes = noteSnapshot.data!;
                              if (notes.isEmpty) {
                                return const Center(
                                  child: Text('No notes yet.'),
                                );
                              }
                              return ListView.builder(
                                itemCount: notes.length,
                                itemBuilder: (context, index) {
                                  final note = notes[index];
                                  return ListTile(
                                    title: Text(note.text),
                                    subtitle: Text(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        note.createdAt,
                                      ).toIso8601String(),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        await ref
                                            .read(notesRepositoryProvider)
                                            .deleteNote(note.id);
                                        if (mounted) {
                                          setState(() {});
                                        }
                                      },
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    );

                    if (stacked) {
                      return Column(
                        children: [
                          Expanded(child: assetsPane),
                          const SizedBox(height: 12),
                          Expanded(child: notesPane),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: assetsPane),
                        const SizedBox(width: 12),
                        Expanded(child: notesPane),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_PortfolioDetailVm> _loadVm() async {
    final portfolioRepo = ref.read(portfolioRepositoryProvider);
    final inputsRepo = ref.read(inputsRepositoryProvider);
    final analyticsRepo = ref.read(portfolioAnalyticsRepositoryProvider);
    final portfolio = await portfolioRepo.getById(widget.portfolioId);
    if (portfolio == null) {
      throw StateError('Portfolio not found.');
    }
    final assigned = await portfolioRepo.listPortfolioProperties(
      widget.portfolioId,
    );
    final unassigned = await portfolioRepo.listUnassignedProperties(
      widget.portfolioId,
    );
    final settings = await inputsRepo.getSettings();
    final now = DateTime.now();
    final fromPeriod = '${now.year}-01';
    final toPeriod = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final analytics = await analyticsRepo.computePortfolioIRR(
      portfolioId: widget.portfolioId,
      fromPeriodKey: fromPeriod,
      toPeriodKey: toPeriod,
    );
    return _PortfolioDetailVm(
      portfolio: portfolio,
      assigned: assigned,
      unassigned: unassigned,
      settings: settings,
      portfolioIrr: analytics.irr,
      netCashflow: analytics.netCashflow,
    );
  }

  Future<void> _attachProperty(List<PropertyRecord> unassigned) async {
    if (unassigned.isEmpty) {
      return;
    }
    String? selected = unassigned.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Property to Portfolio'),
              content: DropdownButtonFormField<String>(
                value: selected,
                items:
                    unassigned
                        .map(
                          (property) => DropdownMenuItem(
                            value: property.id,
                            child: Text(property.name),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setDialogState(() {
                    selected = value;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || selected == null) {
      return;
    }
    await ref
        .read(portfolioRepositoryProvider)
        .attachProperty(portfolioId: widget.portfolioId, propertyId: selected!);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _addNote(String entityId) async {
    final textController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Note'),
          content: TextField(
            controller: textController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (ok != true || textController.text.trim().isEmpty) {
      textController.dispose();
      return;
    }
    await ref
        .read(notesRepositoryProvider)
        .addNote(
          entityType: _notesEntityType,
          entityId: entityId,
          text: textController.text.trim(),
        );
    textController.dispose();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _generateAlerts(AppSettingsRecord settings) async {
    final snapshots = await ref
        .read(propertyProfileRepositoryProvider)
        .listSnapshots(portfolioId: widget.portfolioId);
    final rules = ref.read(notificationRulesProvider);
    final suggestions = rules.evaluateFromSnapshots(
      snapshots: snapshots,
      settings: settings,
    );

    final notificationsRepo = ref.read(notificationsRepositoryProvider);
    for (final suggestion in suggestions) {
      await notificationsRepo.createNotification(
        entityType: suggestion.entityType,
        entityId: suggestion.entityId,
        kind: suggestion.kind,
        message: suggestion.message,
        dueAt: suggestion.dueAt,
      );
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Generated ${suggestions.length} alert(s).')),
    );
  }

  Future<void> _exportPortfolioSummary(_PortfolioDetailVm vm) async {
    final location = await getSaveLocation(
      suggestedName:
          'portfolio_${vm.portfolio.id}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: <String>['pdf']),
      ],
    );
    if (location == null) {
      return;
    }

    final esgRepo = ref.read(esgRepositoryProvider);
    final profiles = await esgRepo.listProfiles();
    final profileByProperty = <String, String>{
      for (final profile in profiles)
        profile.propertyId: profile.epcRating ?? 'N/A',
    };

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build:
            (context) => [
              pw.Header(
                level: 0,
                child: pw.Text('Portfolio Summary: ${vm.portfolio.name}'),
              ),
              pw.Paragraph(text: vm.portfolio.description ?? ''),
              pw.Paragraph(text: 'Assets: ${vm.assigned.length}'),
              pw.TableHelper.fromTextArray(
                headers: const <String>['Property', 'City', 'Type', 'EPC'],
                data:
                    vm.assigned
                        .map(
                          (property) => <String>[
                            property.name,
                            property.city,
                            property.propertyType,
                            profileByProperty[property.id] ?? 'N/A',
                          ],
                        )
                        .toList(),
              ),
            ],
      ),
    );

    await File(location.path).writeAsBytes(await doc.save());
    await _mirrorExportToWorkspace(location.path);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Portfolio summary exported: ${location.path}')),
    );
  }

  Future<void> _mirrorExportToWorkspace(String sourcePath) async {
    try {
      final settings = await ref.read(inputsRepositoryProvider).getSettings();
      final workspace = await ref
          .read(workspaceRepositoryProvider)
          .resolvePaths(settings);
      final targetPath = p.join(workspace.exportsPath, p.basename(sourcePath));
      if (p.equals(p.normalize(sourcePath), p.normalize(targetPath))) {
        return;
      }
      await File(sourcePath).copy(targetPath);
    } catch (_) {}
  }

  Future<void> _openReportingPack() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PortfolioPackScreen()),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openPortfolioAnalytics(_PortfolioDetailVm vm) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => PortfolioAnalyticsScreen(
              portfolioId: vm.portfolio.id,
              portfolioName: vm.portfolio.name,
            ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openDataQuality(_PortfolioDetailVm vm) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => DataQualityDashboardScreen(
              portfolioId: vm.portfolio.id,
              portfolioName: vm.portfolio.name,
            ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Widget _infoTile(String label, String value) {
    final semantic = context.semanticColors;
    return Container(
      width: ResponsiveConstraints.itemWidth(context, idealWidth: 180),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: semantic.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: semantic.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PortfolioDetailVm {
  const _PortfolioDetailVm({
    required this.portfolio,
    required this.assigned,
    required this.unassigned,
    required this.settings,
    required this.portfolioIrr,
    required this.netCashflow,
  });

  final PortfolioRecord portfolio;
  final List<PropertyRecord> assigned;
  final List<PropertyRecord> unassigned;
  final AppSettingsRecord settings;
  final double? portfolioIrr;
  final double netCashflow;
}

class _PortfolioLandingVm {
  const _PortfolioLandingVm({
    required this.portfolios,
    required this.properties,
    required this.overview,
  });

  final List<PortfolioRecord> portfolios;
  final List<PropertyRecord> properties;
  final PortfolioRentalOverview overview;
}

const _allFilterValue = '__all__';

class _PortfolioLandingFilters {
  const _PortfolioLandingFilters({
    this.propertyId = _allFilterValue,
    this.region = _allFilterValue,
    this.propertyType = _allFilterValue,
    this.owner = _allFilterValue,
    this.timeframe = '12m',
  });

  final String propertyId;
  final String region;
  final String propertyType;
  final String owner;
  final String timeframe;

  _PortfolioLandingFilters copyWith({
    String? propertyId,
    String? region,
    String? propertyType,
    String? owner,
    String? timeframe,
  }) {
    return _PortfolioLandingFilters(
      propertyId: propertyId ?? this.propertyId,
      region: region ?? this.region,
      propertyType: propertyType ?? this.propertyType,
      owner: owner ?? this.owner,
      timeframe: timeframe ?? this.timeframe,
    );
  }
}

class _FilterOption {
  const _FilterOption(this.value, this.label);

  final String value;
  final String label;
}

class _ChartDatum {
  const _ChartDatum(this.label, this.value);

  final String label;
  final double value;
}

List<PortfolioRentalOverviewRow> _filterPortfolioRows({
  required List<PortfolioRentalOverviewRow> rows,
  required Map<String, PropertyRecord> propertyById,
  required _PortfolioLandingFilters filters,
}) {
  return rows.where((row) {
    if (filters.propertyId != _allFilterValue &&
        row.propertyId != filters.propertyId) {
      return false;
    }
    if (filters.propertyType != _allFilterValue &&
        row.propertyType != filters.propertyType) {
      return false;
    }
    if (filters.owner != _allFilterValue &&
        !row.ownerLabels.contains(filters.owner)) {
      return false;
    }
    final property = propertyById[row.propertyId];
    if (filters.region != _allFilterValue &&
        (property == null || _regionForProperty(property) != filters.region)) {
      return false;
    }
    return true;
  }).toList(growable: false);
}

PortfolioRentalOverview _aggregateOverview(
  List<PortfolioRentalOverviewRow> rows,
  PortfolioRentalOverview fallback,
) {
  if (rows.length == fallback.rows.length) {
    return fallback;
  }
  return PortfolioRentalOverview(
    rows: rows,
    assetsTotal: rows.length,
    assetsNotActive: 0,
    rentedUnits: rows.fold<int>(0, (sum, row) => sum + row.occupiedUnits),
    emptyUnits: rows.fold<int>(0, (sum, row) => sum + row.vacantUnits),
    annualRent: rows.fold<double>(0, (sum, row) => sum + row.annualRent),
    monthlyRentRunRate:
        rows.fold<double>(0, (sum, row) => sum + row.monthlyRentRunRate),
    annualOperatingCosts:
        rows.fold<double>(0, (sum, row) => sum + row.annualOperatingCosts),
    openDepositAmount:
        rows.fold<double>(0, (sum, row) => sum + row.openDepositAmount),
    serviceChargeBalance:
        rows.fold<double>(0, (sum, row) => sum + row.serviceChargeBalance),
    sourceAreasComplete:
        rows.fold<int>(0, (sum, row) => sum + row.sourceAreasComplete),
    sourceAreasTotal:
        rows.fold<int>(0, (sum, row) => sum + row.sourceAreasTotal),
  );
}

List<_FilterOption> _sortedOptions(
  Iterable<String> values, {
  required String allLabel,
}) {
  final unique = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return <_FilterOption>[
    _FilterOption(_allFilterValue, allLabel),
    for (final value in unique) _FilterOption(value, value),
  ];
}

String _safeFilterValue(String value, List<_FilterOption> options) {
  return options.any((option) => option.value == value)
      ? value
      : options.first.value;
}

String _regionForProperty(PropertyRecord property) {
  final city = property.city.trim();
  if (city.isNotEmpty) {
    return city;
  }
  final country = property.country.trim();
  return country.isEmpty ? 'Ohne Region' : country;
}

int _timeframeMonths(String value) {
  switch (value) {
    case '3m':
      return 3;
    case '6m':
      return 6;
    case '24m':
      return 24;
    case '36m':
      return 36;
    case '12m':
    default:
      return 12;
  }
}

String _timeframeLabel(String value) {
  switch (value) {
    case '3m':
      return 'Letzte 3 Monate';
    case '6m':
      return 'Letzte 6 Monate';
    case '24m':
      return 'Letzte 24 Monate';
    case '36m':
      return 'Letzte 36 Monate';
    case '12m':
    default:
      return 'Letzte 12 Monate';
  }
}

List<double> _trendSeries(double base, int months, double monthlyGrowth) {
  final points = _seriesPointCount(months);
  if (base <= 0) {
    return List<double>.filled(points, 0);
  }
  final start = base / (1 + (monthlyGrowth * points));
  return List<double>.generate(points, (index) {
    final seasonal = index.isEven ? 0.006 : -0.003;
    return start * (1 + (monthlyGrowth * index) + seasonal);
  }, growable: false);
}

List<double> _boundedTrendSeries(double base, int months, double monthlyChange) {
  final points = _seriesPointCount(months);
  return List<double>.generate(points, (index) {
    final drift = (index - points + 1) * monthlyChange;
    return (base + drift).clamp(0.0, 1.0).toDouble();
  }, growable: false);
}

int _seriesPointCount(int months) {
  if (months <= 6) {
    return months;
  }
  return 8;
}

List<_ChartDatum> _chartDataFromTotals(
  Map<String, double> totals, {
  required int limit,
}) {
  final data = totals.entries
      .map((entry) => _ChartDatum(entry.key, entry.value))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return data.take(limit).toList(growable: false);
}

String _formatCurrency(double value) {
  final sign = value < 0 ? '-' : '';
  final absValue = value.abs();
  if (absValue >= 1000000) {
    return '$sign€ ${(absValue / 1000000).toStringAsFixed(1)} Mio.';
  }
  if (absValue >= 1000) {
    return '$sign€ ${(absValue / 1000).toStringAsFixed(1)} Tsd.';
  }
  return '$sign€ ${absValue.toStringAsFixed(0)}';
}

String _formatPercent(double value) {
  return '${(value * 100).clamp(0, 999).toStringAsFixed(1)}%';
}
