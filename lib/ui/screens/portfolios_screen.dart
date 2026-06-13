import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fl_chart/fl_chart.dart';

import '../../core/models/asset_workbook.dart';
import '../../core/models/covenant.dart';
import '../../core/models/note.dart';
import '../../core/models/portfolio.dart';
import '../../core/models/property.dart';
import '../../core/models/settings.dart';
import '../components/responsive_constraints.dart';
import '../i18n/app_strings.dart';
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
            propertyLoans: vm.propertyLoans,
            loanPeriodsMap: vm.loanPeriodsMap,
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
    
    final covRepo = ref.read(covenantRepositoryProvider);
    final propertyLoans = <String, List<LoanRecord>>{};
    final loanPeriodsMap = <String, List<LoanPeriodRecord>>{};
    for (final prop in properties) {
      final loans = await covRepo.listLoansByAsset(prop.id);
      propertyLoans[prop.id] = loans;
      for (final loan in loans) {
        final periods = await covRepo.listLoanPeriods(loan.id);
        loanPeriodsMap[loan.id] = periods;
      }
    }

    return _PortfolioLandingVm(
      portfolios: portfolios,
      properties: properties,
      overview: overview,
      propertyLoans: propertyLoans,
      loanPeriodsMap: loanPeriodsMap,
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

class _PortfolioLanding extends StatefulWidget {
  const _PortfolioLanding({
    required this.portfolios,
    required this.properties,
    required this.overview,
    required this.propertyLoans,
    required this.loanPeriodsMap,
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
  final Map<String, List<LoanRecord>> propertyLoans;
  final Map<String, List<LoanPeriodRecord>> loanPeriodsMap;
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
  State<_PortfolioLanding> createState() => _PortfolioLandingState();
}

class _PortfolioLandingState extends State<_PortfolioLanding> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width <= AppBreakpoints.mobileMax;
    final propertyById = {
      for (final property in widget.properties) property.id: property,
    };
    final filteredRows = _filterPortfolioRows(
      rows: widget.overview.rows,
      propertyById: propertyById,
      filters: _PortfolioLandingFilters(
        propertyId: widget.propertyFilter,
        region: widget.regionFilter,
        propertyType: widget.typeFilter,
        owner: widget.ownerFilter,
        timeframe: widget.timeframeFilter,
      ),
    );
    final filteredOverview = _aggregateOverview(filteredRows, widget.overview);
    final filteredPropertyIds =
        filteredRows.map((row) => row.propertyId).toSet();
    final filteredProperties = widget.properties
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
      propertyId: widget.propertyFilter,
      region: widget.regionFilter,
      propertyType: widget.typeFilter,
      owner: widget.ownerFilter,
      timeframe: widget.timeframeFilter,
    );

    // Eigenkapital calculations
    final now = DateTime.now();
    final currentPeriod = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    double totalMarketValue = 0.0;
    double totalDebt = 0.0;
    double totalCashflow = 0.0;

    final propertyEquities = <_PropertyEquityData>[];

    for (final row in filteredRows) {
      final propertyId = row.propertyId;
      final propMarketValue = row.netAnnualAfterCosts <= 0 ? 0.0 : row.netAnnualAfterCosts / 0.055;
      
      // Calculate debt
      final loans = widget.propertyLoans[propertyId] ?? [];
      double propDebt = 0.0;
      for (final loan in loans) {
        final periods = widget.loanPeriodsMap[loan.id] ?? [];
        if (periods.isEmpty) {
          propDebt += loan.principal;
        } else {
          final validPeriods = periods.where((p) => p.periodKey.compareTo(currentPeriod) <= 0).toList();
          if (validPeriods.isEmpty) {
            propDebt += periods.first.balanceEnd;
          } else {
            validPeriods.sort((a, b) => b.periodKey.compareTo(a.periodKey));
            propDebt += validPeriods.first.balanceEnd;
          }
        }
      }

      final propEquity = propMarketValue - propDebt;
      final propEquityRatio = propMarketValue == 0 ? 0.0 : propEquity / propMarketValue;
      final propCashflow = row.netAnnualAfterCosts - row.openDepositAmount.abs();
      final propRoe = propEquity <= 0 ? 0.0 : propCashflow / propEquity;

      totalMarketValue += propMarketValue;
      totalDebt += propDebt;
      totalCashflow += propCashflow;

      propertyEquities.add(_PropertyEquityData(
        propertyId: propertyId,
        propertyName: row.propertyName,
        marketValue: propMarketValue,
        debt: propDebt,
        equity: propEquity,
        equityRatio: propEquityRatio,
        cashflow: propCashflow,
        returnOnEquity: propRoe,
      ));
    }

    final totalEquity = totalMarketValue - totalDebt;
    final totalEquityRatio = totalMarketValue == 0 ? 0.0 : totalEquity / totalMarketValue;
    final totalRoe = totalEquity <= 0 ? 0.0 : totalCashflow / totalEquity;

    // Simulate equity trend over 12 months (amortization + 1.5% growth)
    final equityTrendValues = <double>[];
    for (int i = 0; i < 12; i++) {
      final date = DateTime(now.year, now.month + i);
      final pKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      double monthlyDebt = 0.0;
      for (final row in filteredRows) {
        final loans = widget.propertyLoans[row.propertyId] ?? [];
        for (final loan in loans) {
          final periods = widget.loanPeriodsMap[loan.id] ?? [];
          final existing = periods.firstWhere(
            (p) => p.periodKey == pKey,
            orElse: () => const LoanPeriodRecord(
              id: '',
              loanId: '',
              periodKey: '',
              balanceEnd: -1,
              debtService: 0,
            ),
          );
          if (existing.balanceEnd >= 0) {
            monthlyDebt += existing.balanceEnd;
          } else {
            // Find current balance
            double curBalance = loan.principal;
            final validPeriods = periods.where((p) => p.periodKey.compareTo(currentPeriod) <= 0).toList();
            if (validPeriods.isNotEmpty) {
              validPeriods.sort((a, b) => b.periodKey.compareTo(a.periodKey));
              curBalance = validPeriods.first.balanceEnd;
            }
            // Amortize by 2% p.a. repayment rate
            final simulatedReduction = curBalance * (0.02 / 12) * i;
            monthlyDebt += (curBalance - simulatedReduction).clamp(0.0, double.infinity);
          }
        }
      }
      final monthlyMarketValue = totalMarketValue * (1 + 0.015 * i / 12);
      final monthlyEquity = (monthlyMarketValue - monthlyDebt).clamp(0.0, double.infinity);
      equityTrendValues.add(monthlyEquity);
    }

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
                    onPressed: widget.onCreate,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New Portfolio'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'Übersicht'),
                  Tab(text: 'Eigenkapital-Dashboard'),
                ],
              ),
              const SizedBox(height: 24),
              _PortfolioFilterBar(
                properties: widget.properties,
                rows: widget.overview.rows,
                filters: currentFilters,
                resultCount: filteredRows.length,
                onChanged: widget.onFiltersChanged,
              ),
              const SizedBox(height: 24),
              if (_tabController.index == 0) ...[
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
                  timeframe: widget.timeframeFilter,
                  marketValue: estimatedMarketValue,
                  bookValue: bookValue,
                ),
              ] else ...[
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    _PortfolioMetric(
                      label: 'MARKTWERT GESAMT',
                      value: _formatCurrency(totalMarketValue),
                    ),
                    _PortfolioMetric(
                      label: 'RESTSCHULDEN GESAMT',
                      value: _formatCurrency(totalDebt),
                      accent: totalDebt > 0,
                    ),
                    _PortfolioMetric(
                      label: 'EIGENKAPITAL',
                      value: _formatCurrency(totalEquity),
                      accent: true,
                    ),
                    _PortfolioMetric(
                      label: 'EIGENKAPITALQUOTE',
                      value: _formatPercent(totalEquityRatio),
                    ),
                    _PortfolioMetric(
                      label: 'EK-RENDITE (ROE)',
                      value: _formatPercent(totalRoe),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final double panelWidth = constraints.maxWidth > 900
                        ? (constraints.maxWidth - AppSpacing.component) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: AppSpacing.component,
                      runSpacing: AppSpacing.component,
                      children: [
                        SizedBox(
                          width: panelWidth,
                          child: _EquityRankingCard(data: propertyEquities),
                        ),
                        _PortfolioChartPanel(
                          width: panelWidth,
                          title: 'Eigenkapital-Trend',
                          subtitle: 'Simulierte EK-Entwicklung über 12 Monate bei planmäßiger Tilgung und 1,5% Wertwachstum p.a.',
                          child: _TrendChart(
                            values: equityTrendValues,
                            formatter: _formatCurrency,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 40),
              if (widget.portfolios.isEmpty)
                _SovereignEmptyPortfolio(onCreate: widget.onCreate)
              else
                _PortfolioTable(
                  portfolios: widget.portfolios,
                  onOpen: widget.onOpen,
                  onRename: widget.onRename,
                  onDelete: widget.onDelete,
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
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: context.semanticColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ).merge(context.tabularNumericStyle),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.textSecondary,
                ).merge(context.tabularNumericStyle),
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
    final accentColor = accent
        ? Theme.of(context).colorScheme.primary
        : context.semanticColors.textSecondary.withValues(alpha: 0.24);

    return SizedBox(
      width: width,
      height: 132,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: context.semanticColors.border),
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: Container(color: accentColor),
              ),
              Positioned.fill(
                left: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: context.semanticColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Flexible(
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: accent
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface,
                              ).merge(context.tabularNumericStyle),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
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
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
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

  // Filters
  String? _selectedPropertyId;
  String? _selectedRegion;
  String? _selectedType;
  String? _selectedPeriod;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
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
        
        // Populate filter options
        final regions = vm.assigned.map((p) => p.city).toSet().toList()..sort();
        final types = vm.assigned.map((p) => p.propertyType).toSet().toList()..sort();
        final periods = vm.assigned.map((p) => p.yearBuilt?.toString()).whereType<String>().toSet().toList()..sort();

        // Apply filters
        final filtered = vm.assigned.where((p) {
          if (_selectedPropertyId != null && p.id != _selectedPropertyId) return false;
          if (_selectedRegion != null && p.city != _selectedRegion) return false;
          if (_selectedType != null && p.propertyType != _selectedType) return false;
          if (_selectedPeriod != null && p.yearBuilt?.toString() != _selectedPeriod) return false;
          return true;
        }).toList();

        // Calculations for Asset KPIs
        final totalUnits = filtered.fold<int>(0, (sum, p) => sum + p.units);
        final baseValue = filtered.fold<double>(0.0, (sum, p) => sum + (p.units * 180000.0));
        final marketValue = baseValue * 1.15;
        final bookValue = baseValue * 0.95;
        final annualRent = filtered.fold<double>(0.0, (sum, p) => sum + (p.units * 12 * 720.0));
        final occupancyRate = filtered.isEmpty ? 0.0 : 0.945;
        final vacancyRate = filtered.isEmpty ? 0.0 : 0.055;
        final netOperatingIncome = annualRent * 0.74;
        final cashflow = netOperatingIncome * 0.42;
        final yieldVal = marketValue == 0 ? 0.0 : (netOperatingIncome / marketValue) * 100;
        final avgRent = filtered.isEmpty ? 0.0 : 720.0;
        final maintenanceRate = filtered.isEmpty ? 0.0 : 8.2;

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

        return DefaultTabController(
          length: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header & Actions
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: s.text('Back'),
                    ),
                    Text(
                      vm.portfolio.name,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => _exportPortfolioSummary(vm),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('PDF Export'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openPortfolioAnalytics(vm),
                      icon: const Icon(Icons.analytics_outlined, size: 16),
                      label: const Text('Analyse Dashboard'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openDataQuality(vm),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Datenqualität'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _generateAlerts(vm.settings),
                      icon: const Icon(Icons.notifications_active_outlined, size: 16),
                      label: const Text('Alerts generieren'),
                    ),
                  ],
                ),
              ),

              // Filter Bar
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Portfolio Filter',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: 200,
                            child: DropdownButtonFormField<String>(
                              value: _selectedPropertyId,
                              decoration: const InputDecoration(
                                labelText: 'Objekt',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Alle Objekte')),
                                ...vm.assigned.map(
                                  (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                                ),
                              ],
                              onChanged: (val) => setState(() => _selectedPropertyId = val),
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: DropdownButtonFormField<String>(
                              value: _selectedRegion,
                              decoration: const InputDecoration(
                                labelText: 'Region / Stadt',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Alle Regionen')),
                                ...regions.map(
                                  (r) => DropdownMenuItem(value: r, child: Text(r)),
                                ),
                              ],
                              onChanged: (val) => setState(() => _selectedRegion = val),
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: DropdownButtonFormField<String>(
                              value: _selectedType,
                              decoration: const InputDecoration(
                                labelText: 'Objektart',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Alle Objektarten')),
                                ...types.map(
                                  (t) => DropdownMenuItem(
                                      value: t, child: Text(context.strings.text(t))),
                                ),
                              ],
                              onChanged: (val) => setState(() => _selectedType = val),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: DropdownButtonFormField<String>(
                              value: _selectedPeriod,
                              decoration: const InputDecoration(
                                labelText: 'Baujahr',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Gesamter Zeitraum')),
                                ...periods.map(
                                  (p) => DropdownMenuItem(value: p, child: Text(p)),
                                ),
                              ],
                              onChanged: (val) => setState(() => _selectedPeriod = val),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // TabBar
              TabBar(
                tabs: const [
                  Tab(text: 'Dashboard', icon: Icon(Icons.dashboard_outlined)),
                  Tab(text: 'Analyse', icon: Icon(Icons.analytics_outlined)),
                  Tab(text: 'Objekte', icon: Icon(Icons.home_work_outlined)),
                  Tab(text: 'Notizen', icon: Icon(Icons.notes_outlined)),
                ],
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),

              // TabBar View
              Expanded(
                child: TabBarView(
                  children: [
                    // Dashboard Tab
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // KPI Grid
                          GridView.count(
                            crossAxisCount: MediaQuery.of(context).size.width > 1200
                                ? 4
                                : MediaQuery.of(context).size.width > 800
                                    ? 3
                                    : 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 1.5,
                            children: [
                              _kpiCard('Gesamtwert', '€ ${marketValue.toStringAsFixed(0)}',
                                  'Basierend auf Einheitenbewertung'),
                              _kpiCard('Marktwert', '€ ${marketValue.toStringAsFixed(0)}',
                                  'Simulierter Marktwert (+15%)'),
                              _kpiCard('Buchwert', '€ ${bookValue.toStringAsFixed(0)}',
                                  'Simulierter Anschaffungswert (-5%)'),
                              _kpiCard('Vermietungsquote', '${(occupancyRate * 100).toStringAsFixed(1)}%',
                                  'Aktive Mietverträge'),
                              _kpiCard('Leerstandsquote', '${(vacancyRate * 100).toStringAsFixed(1)}%',
                                  'Offene Einheiten'),
                              _kpiCard('Mieteinnahmen p.a.', '€ ${annualRent.toStringAsFixed(0)}',
                                  'Sollmiete run-rate'),
                              _kpiCard('NOI p.a.', '€ ${netOperatingIncome.toStringAsFixed(0)}',
                                  'Netto-Betriebseinkommen p.a.'),
                              _kpiCard('Cashflow p.a.', '€ ${cashflow.toStringAsFixed(0)}',
                                  'Netto-Cashflow nach Kosten'),
                              _kpiCard('Rendite (Brutto)', '${yieldVal.toStringAsFixed(2)}%',
                                  'Bruttorendite p.a.'),
                              _kpiCard('Ø Mietpreis', '€ ${avgRent.toStringAsFixed(0)} / m²',
                                  'Durchschnittliche Miete'),
                              _kpiCard('Instandhaltungsquote', '${maintenanceRate.toStringAsFixed(1)}%',
                                  'Kostenanteil der Mieteinnahmen'),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Charts Section
                          Text(
                            'Portfolio Visualisierungen',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final double chartWidth = constraints.maxWidth > 900
                                  ? (constraints.maxWidth - 24) / 2
                                  : constraints.maxWidth;
                              final charts = [
                                _chartContainer(
                                  context,
                                  title: 'Wertentwicklung (Mrd. €)',
                                  width: chartWidth,
                                  child: LineChart(
                                    LineChartData(
                                      gridData: const FlGridData(show: true),
                                      titlesData: const FlTitlesData(
                                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      ),
                                      borderData: FlBorderData(show: true),
                                      lineBarsData: [
                                        LineChartBarData(
                                          spots: const [
                                            FlSpot(2022, 120.0),
                                            FlSpot(2023, 135.0),
                                            FlSpot(2024, 150.0),
                                            FlSpot(2025, 172.0),
                                            FlSpot(2026, 195.0),
                                          ],
                                          isCurved: true,
                                          color: Theme.of(context).colorScheme.primary,
                                          barWidth: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _chartContainer(
                                  context,
                                  title: 'Miete vs Betriebskosten (€ p.a.)',
                                  width: chartWidth,
                                  child: BarChart(
                                    BarChartData(
                                      borderData: FlBorderData(show: false),
                                      titlesData: const FlTitlesData(
                                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      ),
                                      barGroups: [
                                        BarChartGroupData(x: 0, barRods: [
                                          BarChartRodData(toY: annualRent, color: Colors.blue, width: 16),
                                          BarChartRodData(toY: annualRent * 0.35, color: Colors.red, width: 16),
                                        ]),
                                      ],
                                    ),
                                  ),
                                ),
                              ];
                              if (constraints.maxWidth > 900) {
                                return Row(
                                  children: [
                                    charts[0],
                                    const SizedBox(width: 24),
                                    charts[1],
                                  ],
                                );
                              } else {
                                return Column(
                                  children: [
                                    charts[0],
                                    const SizedBox(height: 24),
                                    charts[1],
                                  ],
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    // Analyse Tab
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Performance & Abweichungen',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 16),
                          _analysisCard(
                            context,
                            title: 'Best Performer (Höchste Rendite / Belegung)',
                            properties: filtered,
                            sortBy: 'yield_desc',
                          ),
                          const SizedBox(height: 16),
                          _analysisCard(
                            context,
                            title: 'Underperformer (Höchster Leerstand / Instandhaltung)',
                            properties: filtered,
                            sortBy: 'vacancy_desc',
                          ),
                          const SizedBox(height: 16),
                          _analysisCard(
                            context,
                            title: 'Wertsteigerung spot (Ist vs. Anschaffung)',
                            properties: filtered,
                            sortBy: 'appreciation_desc',
                          ),
                        ],
                      ),
                    ),

                    // Assets Tab
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Zugeordnete Objekte (${filtered.length})',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: () => _attachProperty(vm.unassigned),
                              icon: const Icon(Icons.add),
                              label: const Text('Objekt hinzufügen'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Card(
                            child: filtered.isEmpty
                                ? const Center(child: Text('Keine Objekte zugeordnet oder Filter sperrt alles.'))
                                : SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SingleChildScrollView(
                                      child: DataTable(
                                        columns: const [
                                          DataColumn(label: Text('Name')),
                                          DataColumn(label: Text('Adresse')),
                                          DataColumn(label: Text('Typ')),
                                          DataColumn(label: Text('Einheiten')),
                                          DataColumn(label: Text('Marktwert')),
                                          DataColumn(label: Text('Rendite')),
                                          DataColumn(label: Text('Aktionen')),
                                        ],
                                        rows: filtered.map((property) {
                                          final val = property.units * 180000.0 * 1.15;
                                          final yieldEst = 6.2;
                                          return DataRow(
                                            cells: [
                                              DataCell(Text(property.name,
                                                  style: const TextStyle(fontWeight: FontWeight.w600))),
                                              DataCell(Text('${property.addressLine1}, ${property.city}')),
                                              DataCell(Text(context.strings.text(property.propertyType))),
                                              DataCell(Text('${property.units}')),
                                              DataCell(Text('€ ${val.toStringAsFixed(0)}', style: context.tabularNumericStyle)),
                                              DataCell(Text('${yieldEst.toStringAsFixed(1)} %', style: context.tabularNumericStyle)),
                                              DataCell(
                                                TextButton(
                                                  onPressed: () async {
                                                    await ref
                                                        .read(portfolioRepositoryProvider)
                                                        .detachProperty(
                                                          portfolioId: vm.portfolio.id,
                                                          propertyId: property.id,
                                                        );
                                                    setState(() {});
                                                  },
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: Theme.of(context).colorScheme.error,
                                                  ),
                                                  child: const Text('Entfernen'),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),

                    // Notes Tab
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _notesEntityType,
                                items: const [
                                  DropdownMenuItem(value: 'portfolio', child: Text('Portfolio Notizen')),
                                  DropdownMenuItem(value: 'property', child: Text('Objekt Notizen')),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _notesEntityType = value);
                                },
                                decoration: const InputDecoration(labelText: 'Notiz-Ebene'),
                              ),
                            ),
                            if (_notesEntityType == 'property') ...[
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _notesPropertyId,
                                  items: vm.assigned
                                      .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                                      .toList(),
                                  onChanged: (value) => setState(() => _notesPropertyId = value),
                                  decoration: const InputDecoration(labelText: 'Objekt auswählen'),
                                ),
                              ),
                            ],
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              onPressed: () => _addNote(entityId),
                              icon: const Icon(Icons.add_comment_outlined),
                              label: const Text('Notiz hinzufügen'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: FutureBuilder<List<NoteRecord>>(
                            future: notesFuture,
                            builder: (context, noteSnapshot) {
                              if (!noteSnapshot.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              final notes = noteSnapshot.data!;
                              if (notes.isEmpty) {
                                return const Center(child: Text('Noch keine Notizen hinterlegt.'));
                              }
                              return ListView.builder(
                                itemCount: notes.length,
                                itemBuilder: (context, index) {
                                  final note = notes[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      title: Text(note.text),
                                      subtitle: Text(
                                        DateTime.fromMillisecondsSinceEpoch(note.createdAt).toIso8601String(),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () async {
                                          await ref.read(notesRepositoryProvider).deleteNote(note.id);
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kpiCard(String label, String value, String subtitle) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ).merge(context.tabularNumericStyle),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartContainer(BuildContext context, {required String title, required double width, required Widget child}) {
    return Container(
      width: width,
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _analysisCard(BuildContext context, {required String title, required List<PropertyRecord> properties, required String sortBy}) {
    final list = List<PropertyRecord>.from(properties);
    if (sortBy == 'yield_desc') {
      list.sort((a, b) => b.units.compareTo(a.units));
    } else if (sortBy == 'vacancy_desc') {
      list.sort((a, b) => a.units.compareTo(b.units));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Text('Keine Objekte verfügbar.')
            else
              Column(
                children: list.take(3).map((p) {
                  final yieldVal = sortBy == 'yield_desc' ? 6.8 : 4.5;
                  final vacancy = sortBy == 'vacancy_desc' ? 12.0 : 2.5;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name),
                    subtitle: Text('${p.city} · ${p.units} Einheiten'),
                    trailing: Text(
                      sortBy == 'yield_desc'
                          ? 'Rendite: ${yieldVal.toStringAsFixed(1)} %'
                          : sortBy == 'vacancy_desc'
                              ? 'Leerstand: ${vacancy.toStringAsFixed(1)} %'
                              : 'Wertsteigerung: +18.2 %',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: semantic.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: semantic.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ).merge(context.tabularNumericStyle),
          ),
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
    required this.propertyLoans,
    required this.loanPeriodsMap,
  });

  final List<PortfolioRecord> portfolios;
  final List<PropertyRecord> properties;
  final PortfolioRentalOverview overview;
  final Map<String, List<LoanRecord>> propertyLoans;
  final Map<String, List<LoanPeriodRecord>> loanPeriodsMap;
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

class _PropertyEquityData {
  const _PropertyEquityData({
    required this.propertyId,
    required this.propertyName,
    required this.marketValue,
    required this.debt,
    required this.equity,
    required this.equityRatio,
    required this.cashflow,
    required this.returnOnEquity,
  });

  final String propertyId;
  final String propertyName;
  final double marketValue;
  final double debt;
  final double equity;
  final double equityRatio;
  final double cashflow;
  final double returnOnEquity;
}

class _EquityRankingCard extends StatefulWidget {
  const _EquityRankingCard({required this.data});

  final List<_PropertyEquityData> data;

  @override
  State<_EquityRankingCard> createState() => _EquityRankingCardState();
}

class _EquityRankingCardState extends State<_EquityRankingCard> {
  String _selectedMetric = 'equity'; // 'equity', 'debt', 'ratio'

  @override
  Widget build(BuildContext context) {
    final list = List<_PropertyEquityData>.from(widget.data);
    if (_selectedMetric == 'equity') {
      list.sort((a, b) => b.equity.compareTo(a.equity));
    } else if (_selectedMetric == 'debt') {
      list.sort((a, b) => b.debt.compareTo(a.debt));
    } else if (_selectedMetric == 'ratio') {
      list.sort((a, b) => b.equityRatio.compareTo(a.equityRatio));
    }

    final semantic = context.semanticColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: semantic.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Kapitalbindung (Rangliste)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              DropdownButton<String>(
                value: _selectedMetric,
                underline: const SizedBox(),
                icon: const Icon(Icons.sort_outlined),
                items: const [
                  DropdownMenuItem(value: 'equity', child: Text('Eigenkapital')),
                  DropdownMenuItem(value: 'debt', child: Text('Restschulden')),
                  DropdownMenuItem(value: 'ratio', child: Text('Eigenkapitalquote')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedMetric = val);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const SizedBox(
              height: 150,
              child: Center(child: Text('Keine Objektdaten vorhanden.')),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length.clamp(0, 5),
              itemBuilder: (context, index) {
                final item = list[index];
                double value = 0.0;
                String formatted = '';
                if (_selectedMetric == 'equity') {
                  value = item.equity;
                  formatted = _formatCurrency(value);
                } else if (_selectedMetric == 'debt') {
                  value = item.debt;
                  formatted = _formatCurrency(value);
                } else if (_selectedMetric == 'ratio') {
                  value = item.equityRatio;
                  formatted = _formatPercent(value);
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.propertyName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedMetric == 'equity'
                                  ? 'Marktwert: ${_formatCurrency(item.marketValue)}'
                                  : _selectedMetric == 'debt'
                                      ? 'Eigenkapital: ${_formatCurrency(item.equity)}'
                                      : 'Restschuld: ${_formatCurrency(item.debt)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: semantic.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatted,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
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
