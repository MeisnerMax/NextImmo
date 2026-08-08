import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/asset_workbook.dart';
import '../../core/models/covenant.dart';
import '../../core/models/portfolio.dart';
import '../../core/models/property.dart';
import '../components/nx_card.dart';
import '../components/nx_empty_state.dart';
import '../components/responsive_constraints.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'portfolio/portfolio_detail_screen.dart';
import 'portfolio/widgets/portfolio_landing_charts.dart';
import 'portfolio/widgets/portfolio_landing_support.dart';
import 'portfolio/widgets/portfolio_landing_widgets.dart';

/// Portfolio landing (SCR-043) — the managed-portfolio list plus the Übersicht
/// and Eigenkapital-Dashboard tabs. This file stays at its original path so
/// `app_scaffold.dart` keeps resolving `PortfoliosScreen`; the former 2958-LOC
/// monolith (BIG-004) was split into `portfolio/portfolio_detail_screen.dart`
/// (SCR-044) and the presentational widgets under `portfolio/widgets/`. The
/// `FutureBuilder`-based load is preserved; only the loading/error states were
/// lifted (skeleton and a retry state instead of a bare spinner / raw
/// exception text).
class PortfoliosScreen extends ConsumerStatefulWidget {
  const PortfoliosScreen({super.key});

  @override
  ConsumerState<PortfoliosScreen> createState() => _PortfoliosScreenState();
}

class _PortfoliosScreenState extends ConsumerState<PortfoliosScreen> {
  String? _selectedPortfolioId;
  String _propertyFilter = kPortfolioAllFilter;
  String _regionFilter = kPortfolioAllFilter;
  String _typeFilter = kPortfolioAllFilter;
  String _ownerFilter = kPortfolioAllFilter;
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
              return _PortfolioLandingErrorState(
                onRetry: () => setState(() {}),
              );
            }
            return const _PortfolioLandingSkeleton();
          }

          final vm = snapshot.data!;
          return _PortfolioLandingView(
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

  void _updateLandingFilters(PortfolioLandingFilters filters) {
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

class _PortfolioLandingView extends StatefulWidget {
  const _PortfolioLandingView({
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
  final ValueChanged<PortfolioLandingFilters> onFiltersChanged;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;
  final ValueChanged<PortfolioRecord> onOpen;
  final ValueChanged<PortfolioRecord> onRename;
  final ValueChanged<PortfolioRecord> onDelete;

  @override
  State<_PortfolioLandingView> createState() => _PortfolioLandingViewState();
}

class _PortfolioLandingViewState extends State<_PortfolioLandingView> with SingleTickerProviderStateMixin {
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
    final filteredRows = filterPortfolioRows(
      rows: widget.overview.rows,
      propertyById: propertyById,
      filters: PortfolioLandingFilters(
        propertyId: widget.propertyFilter,
        region: widget.regionFilter,
        propertyType: widget.typeFilter,
        owner: widget.ownerFilter,
        timeframe: widget.timeframeFilter,
      ),
    );
    final filteredOverview = aggregatePortfolioOverview(filteredRows, widget.overview);
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
    final currentFilters = PortfolioLandingFilters(
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

    final propertyEquities = <PropertyEquityData>[];

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

      propertyEquities.add(PropertyEquityData(
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
              PortfolioFilterBar(
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
                    PortfolioMetric(
                      label: 'GESAMTWERT',
                      value: formatPortfolioCurrency(estimatedMarketValue),
                      accent: true,
                    ),
                    PortfolioMetric(
                      label: 'MARKTWERT',
                      value: formatPortfolioCurrency(estimatedMarketValue),
                    ),
                    PortfolioMetric(
                      label: 'BUCHWERT',
                      value: bookValue == 0 ? 'N/A' : formatPortfolioCurrency(bookValue),
                    ),
                    PortfolioMetric(
                      label: 'VERMIETUNGSQUOTE',
                      value: formatPortfolioPercent(occupancy),
                    ),
                    PortfolioMetric(
                      label: 'LEERSTANDSQUOTE',
                      value: formatPortfolioPercent(1 - occupancy),
                    ),
                    PortfolioMetric(
                      label: 'MIETEINNAHMEN',
                      value: formatPortfolioCurrency(filteredOverview.annualRent),
                    ),
                    PortfolioMetric(label: 'NOI', value: formatPortfolioCurrency(noi)),
                    PortfolioMetric(
                      label: 'CASHFLOW',
                      value: formatPortfolioCurrency(cashflow),
                    ),
                    PortfolioMetric(
                      label: 'RENDITE',
                      value:
                          estimatedMarketValue == 0
                              ? 'N/A'
                              : formatPortfolioPercent(noi / estimatedMarketValue),
                    ),
                    PortfolioMetric(
                      label: 'Ø MIETPREIS',
                      value: formatPortfolioCurrency(averageRent),
                    ),
                    PortfolioMetric(
                      label: 'INSTANDHALTUNG',
                      value: formatPortfolioPercent(maintenanceRatio),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                PortfolioInsightGrid(
                  rows: sortedByNoi,
                  sourceCoverageRate: filteredOverview.sourceCoverageRate,
                ),
                const SizedBox(height: 32),
                PortfolioManagementCharts(
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
                    PortfolioMetric(
                      label: 'MARKTWERT GESAMT',
                      value: formatPortfolioCurrency(totalMarketValue),
                    ),
                    PortfolioMetric(
                      label: 'RESTSCHULDEN GESAMT',
                      value: formatPortfolioCurrency(totalDebt),
                      accent: totalDebt > 0,
                    ),
                    PortfolioMetric(
                      label: 'EIGENKAPITAL',
                      value: formatPortfolioCurrency(totalEquity),
                      accent: true,
                    ),
                    PortfolioMetric(
                      label: 'EIGENKAPITALQUOTE',
                      value: formatPortfolioPercent(totalEquityRatio),
                    ),
                    PortfolioMetric(
                      label: 'EK-RENDITE (ROE)',
                      value: formatPortfolioPercent(totalRoe),
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
                          child: EquityRankingCard(data: propertyEquities),
                        ),
                        PortfolioChartPanel(
                          width: panelWidth,
                          title: 'Eigenkapital-Trend',
                          subtitle: 'Simulierte EK-Entwicklung über 12 Monate bei planmäßiger Tilgung und 1,5% Wertwachstum p.a.',
                          child: PortfolioTrendChart(
                            values: equityTrendValues,
                            formatter: formatPortfolioCurrency,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 40),
              if (widget.portfolios.isEmpty)
                PortfolioEmptyState(onCreate: widget.onCreate)
              else
                PortfolioTable(
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

/// Landing-shaped loading placeholder (never a full-page spinner): a header bar,
/// a KPI-tile row and a table block mirroring the eventual layout.
class _PortfolioLandingSkeleton extends StatelessWidget {
  const _PortfolioLandingSkeleton();

  @override
  Widget build(BuildContext context) {
    final placeholderColor = context.semanticColors.surfaceAlt;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: placeholderColor,
            borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
          ),
        );
    return ListView(
      key: const ValueKey<String>('portfolio_landing_skeleton'),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              bar(280, 24),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 600
                      ? 1
                      : (constraints.maxWidth < 1080 ? 2 : 3);
                  final gap = AppSpacing.component;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: List.generate(
                      6,
                      (_) => SizedBox(
                        width: width,
                        child: NxCard(
                          variant: NxCardVariant.kpi,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              bar(120, 10),
                              const SizedBox(height: 12),
                              bar(90, 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.component),
              NxCard(
                child: bar(double.infinity, 220),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Infrastructure-error treatment for the landing: no raw exception text,
/// always a retry action (retry re-runs the same `FutureBuilder` load).
class _PortfolioLandingErrorState extends StatelessWidget {
  const _PortfolioLandingErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return NxEmptyState(
      title: 'Portfolios konnten nicht geladen werden',
      description:
          'Beim Laden der Portfolio-Übersicht ist ein Fehler aufgetreten. '
          'Bitte versuchen Sie es erneut.',
      icon: Icons.error_outline,
      primaryAction: ElevatedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Erneut versuchen'),
      ),
    );
  }
}
