import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/property.dart';
import '../../i18n/app_strings.dart';
import '../../state/app_state.dart';
import '../../state/analysis_state.dart';
import '../../state/property_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/warnings_panel.dart';

class OverviewScreen extends ConsumerStatefulWidget {
  const OverviewScreen({
    super.key,
    required this.propertyId,
    required this.scenarioId,
  });

  final String propertyId;
  final String scenarioId;

  @override
  ConsumerState<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends ConsumerState<OverviewScreen> {
  _CashflowMode _cashflowMode = _CashflowMode.annual;

  @override
  Widget build(BuildContext context) {
    final analysisAsync = ref.watch(
      scenarioAnalysisControllerProvider(widget.scenarioId),
    );
    final properties = ref.watch(propertiesControllerProvider).valueOrNull;
    final property = _findProperty(properties, widget.propertyId);

    return analysisAsync.when(
      data: (state) {
        final metrics = state.analysis.metrics;
        final summary = _DealSummaryViewModel.fromState(
          state: state,
          property: property,
        );

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_shouldShowOnboarding(summary, property)) ...[
                  _buildOnboardingCard(context),
                  const SizedBox(height: AppSpacing.component),
                ],
                Wrap(
                  spacing: AppSpacing.component,
                  runSpacing: AppSpacing.component,
                  children: [
                    KpiCard(
                      label: 'Monthly Cashflow',
                      value: metrics.monthlyCashflowYear1.toStringAsFixed(2),
                    ),
                    KpiCard(
                      label: 'NOI Y1',
                      value: metrics.noiYear1.toStringAsFixed(2),
                    ),
                    KpiCard(
                      label: 'Cap Rate',
                      value: '${(metrics.capRate * 100).toStringAsFixed(2)}%',
                    ),
                    KpiCard(
                      label: 'Cash on Cash',
                      value:
                          '${(metrics.cashOnCash * 100).toStringAsFixed(2)}%',
                    ),
                    KpiCard(
                      label: 'IRR',
                      value:
                          metrics.irr == null
                              ? 'N/A'
                              : '${(metrics.irr! * 100).toStringAsFixed(2)}%',
                    ),
                    KpiCard(
                      label: 'ROI',
                      value: '${(metrics.roi * 100).toStringAsFixed(2)}%',
                    ),
                    KpiCard(
                      label: 'DSCR',
                      value: metrics.dscr?.toStringAsFixed(2) ?? 'N/A',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.component),
                _buildSummaryCard(context, summary),
                const SizedBox(height: AppSpacing.component),
                _buildCharts(context, state, summary),
                const SizedBox(height: AppSpacing.component),
                WarningsPanel(warnings: state.analysis.warnings),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildOnboardingCard(BuildContext context) {
    final s = context.strings;
    final actions = <
      ({IconData icon, String title, String description, VoidCallback onTap})
    >[
      (
        icon: Icons.tune_outlined,
        title: s.text('Add financial assumptions'),
        description: s.text('Purchase price, financing and capex assumptions'),
        onTap:
            () =>
                ref.read(propertyDetailPageProvider.notifier).state =
                    PropertyDetailPage.inputs,
      ),
      (
        icon: Icons.flag_outlined,
        title: s.text('Set strategy'),
        description: s.text('Choose the base scenario and investment approach'),
        onTap:
            () =>
                ref.read(propertyDetailPageProvider.notifier).state =
                    PropertyDetailPage.scenarios,
      ),
      (
        icon: Icons.bar_chart_outlined,
        title: s.text('Add rent data'),
        description: s.text('Enter rent, vacancy and operating income data'),
        onTap:
            () =>
                ref.read(propertyDetailPageProvider.notifier).state =
                    PropertyDetailPage.inputs,
      ),
      (
        icon: Icons.folder_open_outlined,
        title: s.text('Add documents'),
        description: s.text(
          'Upload leases, diligence files and supporting material',
        ),
        onTap:
            () =>
                ref.read(propertyDetailPageProvider.notifier).state =
                    PropertyDetailPage.documents,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.text('Next Steps'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              s.text(
                'This property was created with the basics only. Add the next inputs to unlock a reliable analysis.',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.component),
            Wrap(
              spacing: AppSpacing.component,
              runSpacing: AppSpacing.component,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: 260,
                    child: OutlinedButton(
                      onPressed: action.onTap,
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadiusTokens.md,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(action.icon),
                          const SizedBox(height: 12),
                          Text(
                            action.title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            action.description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    _DealSummaryViewModel summary,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deal Summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.component),
            Wrap(
              spacing: AppSpacing.component,
              runSpacing: AppSpacing.component,
              children: [
                _summaryTile(
                  context,
                  label: 'Purchase Price',
                  value: _formatNumber(summary.purchasePrice),
                ),
                _summaryTile(
                  context,
                  label: 'Size m2',
                  value: _formatOptional(summary.sizeM2),
                ),
                _summaryTile(
                  context,
                  label: 'Price per m2',
                  value: _formatOptional(summary.pricePerM2),
                  tooltip: 'Purchase price divided by size in m2.',
                ),
                _summaryTile(
                  context,
                  label: 'Monthly Rent',
                  value: _formatNumber(summary.monthlyRent),
                ),
                _summaryTile(
                  context,
                  label: 'Rent per m2',
                  value: _formatOptional(summary.rentPerM2),
                  tooltip: 'Monthly rent divided by size in m2.',
                ),
                _summaryTile(
                  context,
                  label: 'Rehab Budget',
                  value: _formatNumber(summary.rehabBudget),
                ),
                _summaryTile(
                  context,
                  label: 'Closing Costs Buy',
                  value: _formatNumber(summary.closingCostsBuy),
                ),
                _summaryTile(
                  context,
                  label: 'Total Acquisition Cost',
                  value: _formatNumber(summary.totalAcquisitionCost),
                  tooltip:
                      'Purchase + rehab + buy closing costs (fixed + percent).',
                ),
                _summaryTile(
                  context,
                  label: 'Total Equity Invested',
                  value: _formatNumber(summary.totalEquityInvested),
                  tooltip:
                      'Total acquisition cost minus effective loan amount.',
                ),
                _summaryTile(
                  context,
                  label: 'Loan Amount',
                  value: _formatNumber(summary.loanAmount),
                ),
                _summaryTile(
                  context,
                  label: 'LTV',
                  value:
                      summary.ltv == null
                          ? 'N/A'
                          : '${(summary.ltv! * 100).toStringAsFixed(2)}%',
                  tooltip: 'Loan amount divided by total acquisition cost.',
                ),
                _summaryTile(
                  context,
                  label: 'Hold Period',
                  value: summary.holdPeriodLabel,
                ),
                _summaryTile(
                  context,
                  label: 'Exit Assumption',
                  value: summary.exitAssumptionMode,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharts(
    BuildContext context,
    ScenarioAnalysisState state,
    _DealSummaryViewModel summary,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 1080;
        if (stacked) {
          return Column(
            children: [
              SizedBox(height: 300, child: _buildCashflowChartCard(state)),
              const SizedBox(height: AppSpacing.component),
              SizedBox(
                height: 300,
                child: _buildRentProjectionChartCard(
                  state,
                  summary.monthlyRent,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 300,
                child: _buildCashflowChartCard(state),
              ),
            ),
            const SizedBox(width: AppSpacing.component),
            Expanded(
              child: SizedBox(
                height: 300,
                child: _buildRentProjectionChartCard(
                  state,
                  summary.monthlyRent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCashflowChartCard(ScenarioAnalysisState state) {
    final years = state.analysis.proformaYears;
    if (years.isEmpty) {
      return const Card(
        child: Center(
          child: Text('Cashflow chart unavailable: no proforma data.'),
        ),
      );
    }
    final values = years
        .map(
          (entry) =>
              _cashflowMode == _CashflowMode.annual
                  ? entry.cashflowBeforeTax
                  : entry.cashflowBeforeTax / 12,
        )
        .toList(growable: false);
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++)
        FlSpot((i + 1).toDouble(), values[i]),
    ];

    final minY = _minAxisValue(values);
    final maxY = _maxAxisValue(values);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Cashflow Projection',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                ToggleButtons(
                  isSelected: [
                    _cashflowMode == _CashflowMode.annual,
                    _cashflowMode == _CashflowMode.monthlyAverage,
                  ],
                  onPressed: (index) {
                    setState(() {
                      _cashflowMode =
                          index == 0
                              ? _CashflowMode.annual
                              : _CashflowMode.monthlyAverage;
                    });
                  },
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Annual'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Monthly Avg'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: 1,
                  maxX: years.length.toDouble(),
                  minY: minY,
                  maxY: maxY,
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget:
                            (value, _) => Text(value.toStringAsFixed(0)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          final year = value.toInt();
                          if (year <= 0 || year > years.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Y$year'),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      barWidth: 3,
                      color: Theme.of(context).colorScheme.primary,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.16),
                      ),
                      spots: spots,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRentProjectionChartCard(
    ScenarioAnalysisState state,
    double monthlyRentStart,
  ) {
    final yearsCount = state.analysis.proformaYears.length;
    if (yearsCount <= 0) {
      return const Card(
        child: Center(
          child: Text('Rent chart unavailable: no projection years.'),
        ),
      );
    }
    final growth = state.inputs.rentGrowthPercent;
    final values = <double>[
      for (var year = 1; year <= yearsCount; year++)
        monthlyRentStart * _pow(1 + growth, year - 1),
    ];
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++)
        FlSpot((i + 1).toDouble(), values[i]),
    ];
    final maxY = _maxAxisValue(values);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rent Projection',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.component),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: 1,
                  maxX: yearsCount.toDouble(),
                  minY: 0,
                  maxY: maxY,
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget:
                            (value, _) => Text(value.toStringAsFixed(0)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          final year = value.toInt();
                          if (year <= 0 || year > yearsCount) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Y$year'),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      barWidth: 3,
                      color: Theme.of(context).colorScheme.secondary,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.12),
                      ),
                      spots: spots,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTile(
    BuildContext context, {
    required String label,
    required String value,
    String? tooltip,
  }) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (tooltip != null)
                Tooltip(
                  message: tooltip,
                  child: Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Theme.of(context).hintColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  static PropertyRecord? _findProperty(
    List<PropertyRecord>? properties,
    String propertyId,
  ) {
    if (properties == null) {
      return null;
    }
    for (final property in properties) {
      if (property.id == propertyId) {
        return property;
      }
    }
    return null;
  }

  static String _formatNumber(double value) => value.toStringAsFixed(2);

  static String _formatOptional(double? value) {
    if (value == null) {
      return 'N/A';
    }
    return value.toStringAsFixed(2);
  }

  static double _pow(double base, int exponent) {
    var value = 1.0;
    for (var i = 0; i < exponent; i++) {
      value *= base;
    }
    return value;
  }

  static double _maxAxisValue(List<double> values) {
    final maxValue = values.fold<double>(
      double.negativeInfinity,
      (current, value) => math.max(current, value),
    );
    if (!maxValue.isFinite) {
      return 1;
    }
    return maxValue <= 0 ? 1 : maxValue * 1.1;
  }

  static double _minAxisValue(List<double> values) {
    final minValue = values.fold<double>(
      double.infinity,
      (current, value) => math.min(current, value),
    );
    if (!minValue.isFinite) {
      return 0;
    }
    if (minValue >= 0) {
      return 0;
    }
    return minValue * 1.1;
  }

  static bool _shouldShowOnboarding(
    _DealSummaryViewModel summary,
    PropertyRecord? property,
  ) {
    final propertyHasOnlyBasics =
        property != null &&
        (property.sqft == null || property.sqft == 0) &&
        property.yearBuilt == null &&
        (property.notes == null || property.notes!.trim().isEmpty);
    final assumptionsMissing =
        summary.purchasePrice <= 0 &&
        summary.monthlyRent <= 0 &&
        summary.rehabBudget <= 0;
    return propertyHasOnlyBasics && assumptionsMissing;
  }
}

enum _CashflowMode { annual, monthlyAverage }

class _DealSummaryViewModel {
  const _DealSummaryViewModel({
    required this.purchasePrice,
    required this.sizeM2,
    required this.pricePerM2,
    required this.monthlyRent,
    required this.rentPerM2,
    required this.rehabBudget,
    required this.closingCostsBuy,
    required this.totalAcquisitionCost,
    required this.totalEquityInvested,
    required this.loanAmount,
    required this.ltv,
    required this.holdPeriodLabel,
    required this.exitAssumptionMode,
  });

  final double purchasePrice;
  final double? sizeM2;
  final double? pricePerM2;
  final double monthlyRent;
  final double? rentPerM2;
  final double rehabBudget;
  final double closingCostsBuy;
  final double totalAcquisitionCost;
  final double totalEquityInvested;
  final double loanAmount;
  final double? ltv;
  final String holdPeriodLabel;
  final String exitAssumptionMode;

  factory _DealSummaryViewModel.fromState({
    required ScenarioAnalysisState state,
    required PropertyRecord? property,
  }) {
    final inputs = state.inputs;
    final closingCostsBuy =
        (inputs.purchasePrice * inputs.closingCostBuyPercent) +
        inputs.closingCostBuyFixed;
    final totalAcquisitionCost =
        inputs.purchasePrice + inputs.rehabBudget + closingCostsBuy;
    final downPayment = totalAcquisitionCost * inputs.downPaymentPercent;
    final autoLoan = math.max(0, totalAcquisitionCost - downPayment).toDouble();
    final loanAmount =
        inputs.financingMode == 'loan'
            ? (inputs.loanAmount > 0 ? inputs.loanAmount : autoLoan)
            : 0.0;
    final equity = totalAcquisitionCost - loanAmount;
    final ltv =
        totalAcquisitionCost <= 0 ? null : loanAmount / totalAcquisitionCost;

    final sizeM2 = property?.sqft == null ? null : property!.sqft! * 0.092903;
    final monthlyRent = inputs.rentOverride ?? inputs.rentMonthlyTotal;
    final pricePerM2 =
        sizeM2 == null || sizeM2 <= 0 ? null : inputs.purchasePrice / sizeM2;
    final rentPerM2 =
        sizeM2 == null || sizeM2 <= 0 ? null : monthlyRent / sizeM2;

    return _DealSummaryViewModel(
      purchasePrice: inputs.purchasePrice,
      sizeM2: sizeM2,
      pricePerM2: pricePerM2,
      monthlyRent: monthlyRent,
      rentPerM2: rentPerM2,
      rehabBudget: inputs.rehabBudget,
      closingCostsBuy: closingCostsBuy,
      totalAcquisitionCost: totalAcquisitionCost,
      totalEquityInvested: equity,
      loanAmount: loanAmount,
      ltv: ltv,
      holdPeriodLabel: '${inputs.sellAfterYears} years (${inputs.holdMonths}m)',
      exitAssumptionMode:
          state.valuation.valuationMode == 'exit_cap'
              ? 'Exit Cap'
              : 'Appreciation',
    );
  }
}
