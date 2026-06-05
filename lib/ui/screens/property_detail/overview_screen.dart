import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/financing.dart';
import '../../../core/engine/normalize.dart';
import '../../../core/models/analysis_result.dart';
import '../../../core/models/property.dart';
import '../../i18n/app_strings.dart';
import '../../state/app_state.dart';
import '../../state/analysis_state.dart';
import '../../state/property_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/warnings_panel.dart';

class OverviewScreen extends ConsumerStatefulWidget {
  const OverviewScreen({
    super.key,
    required this.propertyId,
    required this.scenarioId,
    this.scrollable = true,
  });

  final String propertyId;
  final String scenarioId;
  final bool scrollable;

  @override
  ConsumerState<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends ConsumerState<OverviewScreen> {
  static const Color _panel = Color(0xFFF8FBFF);
  static const Color _panelHigh = Color(0xFFEFF6FF);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _text = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _teal = Color(0xFF2563EB);
  static const Color _rose = Color(0xFFDC2626);

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

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_shouldShowOnboarding(summary, property)) ...[
              _buildOnboardingCard(context),
              const SizedBox(height: AppSpacing.component),
            ],
            _buildWorkflowHub(context),
            const SizedBox(height: AppSpacing.component),
            _buildMetricGrid(context, metrics),
            const SizedBox(height: AppSpacing.component),
            _buildSnapshotSections(context, summary, property),
            const SizedBox(height: AppSpacing.component),
            _buildCharts(context, state, summary),
            const SizedBox(height: AppSpacing.component),
            WarningsPanel(warnings: state.analysis.warnings),
          ],
        );
        if (!widget.scrollable) {
          return content;
        }
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: SingleChildScrollView(child: content),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildWorkflowHub(BuildContext context) {
    final actions = <({IconData icon, String label, PropertyDetailPage page})>[
      (
        icon: Icons.edit_outlined,
        label: 'Edit Master Data',
        page: PropertyDetailPage.overview,
      ),
      (
        icon: Icons.tune_outlined,
        label: 'Edit Valuation',
        page: PropertyDetailPage.inputs,
      ),
      (
        icon: Icons.apartment_outlined,
        label: 'Rent Management',
        page: PropertyDetailPage.rentRoll,
      ),
      (
        icon: Icons.request_quote_outlined,
        label: 'Vermietung & BK',
        page: PropertyDetailPage.assetWorkbook,
      ),
      (
        icon: Icons.checklist_outlined,
        label: 'Daily Business',
        page: PropertyDetailPage.operationsOverview,
      ),
      (
        icon: Icons.folder_open_outlined,
        label: 'Documents & Reporting',
        page: PropertyDetailPage.documents,
      ),
      (
        icon: Icons.summarize_outlined,
        label: 'Report',
        page: PropertyDetailPage.reports,
      ),
    ];
    return _assetPanel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.strings.text('Property Workflow'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 1080
                      ? 7
                      : constraints.maxWidth >= 720
                      ? 3
                      : 2;
              final tileWidth =
                  (constraints.maxWidth -
                      (AppSpacing.component * (columns - 1))) /
                  columns;
              return Wrap(
                spacing: AppSpacing.component,
                runSpacing: AppSpacing.component,
                children: [
                  for (final action in actions)
                    SizedBox(
                      width: tileWidth,
                      child: _workflowTile(
                        context,
                        icon: action.icon,
                        label: action.label,
                        onTap:
                            () =>
                                ref
                                    .read(propertyDetailPageProvider.notifier)
                                    .state = action.page,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetricGrid(BuildContext context, AnalysisMetrics metrics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final twoColumn =
            constraints.maxWidth >= 520 && constraints.maxWidth < 980;
        final metricWidth =
            compact
                ? constraints.maxWidth
                : twoColumn
                ? (constraints.maxWidth - AppSpacing.component) / 2
                : 220.0;
        final wideWidth =
            compact || twoColumn
                ? metricWidth
                : (metricWidth * 2) + AppSpacing.component;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.payments_outlined,
              label: 'Monthly Cashflow',
              value: metrics.monthlyCashflowYear1.toStringAsFixed(2),
              tone: _toneFor(metrics.monthlyCashflowYear1),
            ),
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.bar_chart_outlined,
              label: 'NOI Y1',
              value: metrics.noiYear1.toStringAsFixed(2),
              tone: _toneFor(metrics.noiYear1),
            ),
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.percent_outlined,
              label: 'Cap Rate',
              value: '${(metrics.capRate * 100).toStringAsFixed(2)}%',
              tone: _text,
            ),
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.currency_exchange_outlined,
              label: 'Cash on Cash',
              value: '${(metrics.cashOnCash * 100).toStringAsFixed(2)}%',
              tone: _toneFor(metrics.cashOnCash),
            ),
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.show_chart_outlined,
              label: 'IRR',
              value:
                  metrics.irr == null
                      ? 'N/A'
                      : '${(metrics.irr! * 100).toStringAsFixed(2)}%',
              tone: metrics.irr == null ? _text : _toneFor(metrics.irr!),
            ),
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.trending_up_outlined,
              label: 'ROI',
              value: '${(metrics.roi * 100).toStringAsFixed(2)}%',
              tone: _toneFor(metrics.roi),
            ),
            _metricCard(
              context,
              width: wideWidth,
              icon: Icons.balance_outlined,
              label: 'DSCR',
              value: metrics.dscr?.toStringAsFixed(2) ?? 'N/A',
              subtitle: metrics.dscr == null ? null : 'Ratio',
              tone: _text,
            ),
          ],
        );
      },
    );
  }

  Widget _workflowTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      child: Container(
        height: 108,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _muted, size: 28),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.strings.text(label),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(
    BuildContext context, {
    required double width,
    required IconData icon,
    required String label,
    required String value,
    required Color tone,
    String? subtitle,
  }) {
    return SizedBox(
      width: width,
      height: 132,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -4,
              top: -4,
              child: Icon(icon, size: 52, color: _muted.withValues(alpha: 0.14)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.strings.text(label).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.headlineMedium?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _muted),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
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

  Widget _buildSnapshotSections(
    BuildContext context,
    _DealSummaryViewModel summary,
    PropertyRecord? property,
  ) {
    return _assetPanel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.strings.text('Property Snapshot'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080 ? 2 : 1;
              final width =
                  columns == 2
                      ? (constraints.maxWidth - AppSpacing.component) / 2
                      : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.component,
                runSpacing: AppSpacing.component,
                children: [
                  SizedBox(
                    width: width,
                    child: _snapshotGroup(
                      context,
                      title: 'Object Profile',
                      rows: [
                        _SnapshotRow(
                          label: 'Address',
                          value: _propertyAddress(property),
                        ),
                        _SnapshotRow(
                          label: 'Property Type',
                          value: property?.propertyType ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Units',
                          value: property?.units.toString() ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Size m2',
                          value: _formatOptional(summary.sizeM2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _snapshotGroup(
                      context,
                      title: 'Valuation Snapshot',
                      rows: [
                        _SnapshotRow(
                          label: 'Purchase Price',
                          value: _formatNumber(summary.purchasePrice),
                        ),
                        _SnapshotRow(
                          label: 'Price per m2',
                          value: _formatOptional(summary.pricePerM2),
                        ),
                        _SnapshotRow(
                          label: 'Hold Period',
                          value: summary.holdPeriodLabel,
                        ),
                        _SnapshotRow(
                          label: 'Exit Assumption',
                          value: summary.exitAssumptionMode,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _snapshotGroup(
                      context,
                      title: 'Rent Snapshot',
                      rows: [
                        _SnapshotRow(
                          label: 'Monthly Rent',
                          value: _formatNumber(summary.monthlyRent),
                        ),
                        _SnapshotRow(
                          label: 'Rent per m2',
                          value: _formatOptional(summary.rentPerM2),
                        ),
                        _SnapshotRow(
                          label: 'Units',
                          value: property?.units.toString() ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Year Built',
                          value: property?.yearBuilt?.toString() ?? 'N/A',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _snapshotGroup(
                      context,
                      title: 'Financing Snapshot',
                      rows: [
                        _SnapshotRow(
                          label: 'Rehab Budget',
                          value: _formatNumber(summary.rehabBudget),
                        ),
                        _SnapshotRow(
                          label: 'Total Acquisition Cost',
                          value: _formatNumber(summary.totalAcquisitionCost),
                        ),
                        _SnapshotRow(
                          label: 'Total Equity Invested',
                          value: _formatNumber(summary.totalEquityInvested),
                        ),
                        _SnapshotRow(
                          label: 'LTV',
                          value:
                              summary.ltv == null
                                  ? 'N/A'
                                  : '${(summary.ltv! * 100).toStringAsFixed(2)}%',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _assetPanel(BuildContext context, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: 0.82),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: child,
    );
  }

  Widget _snapshotGroup(
    BuildContext context, {
    required String title,
    required List<_SnapshotRow> rows,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _panelHigh.withValues(alpha: 0.46),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.component),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.strings.text(title),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: _text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final row in rows) _snapshotRow(context, row),
          ],
        ),
      ),
    );
  }

  Widget _snapshotRow(BuildContext context, _SnapshotRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              context.strings.text(row.label),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _muted,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.component),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(
                color: _text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
    final useMonthly = _cashflowMode == _CashflowMode.monthlyAverage;
    final annualPeriods = state.analysis.proformaYears;
    final monthlyPeriods = state.analysis.proformaMonths;
    if (annualPeriods.isEmpty || monthlyPeriods.isEmpty) {
      return const Card(
        child: Center(
          child: Text('Cashflow chart unavailable: no proforma data.'),
        ),
      );
    }
    final values =
        useMonthly
            ? monthlyPeriods
                .map((entry) => entry.cashflowBeforeTax)
                .toList(growable: false)
            : annualPeriods
                .map((entry) => entry.cashflowBeforeTax)
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
                      child: Text('Monthly'),
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
                  maxX: values.length.toDouble(),
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
                          final period = value.toInt();
                          if (period <= 0 || period > values.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              useMonthly ? 'M$period' : 'Y$period',
                            ),
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
    final normalized = normalizeInputs(
      inputs: state.inputs,
      settings: state.settings,
      incomeLines: state.incomeLines,
      expenseLines: state.expenseLines,
    );
    final monthsCount = state.analysis.proformaMonths.length;
    if (monthsCount <= 0) {
      return const Card(
        child: Center(
          child: Text('Rent chart unavailable: no projection months.'),
        ),
      );
    }
    final growth = normalized.inputs.rentGrowthPercent;
    final values = <double>[
      for (var month = 1; month <= monthsCount; month++)
        monthlyRentStart * math.pow(1 + growth, (month - 1) / 12).toDouble(),
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
                  maxX: monthsCount.toDouble(),
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
                          final month = value.toInt();
                          if (month <= 0 || month > monthsCount) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('M$month'),
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

  static String _propertyAddress(PropertyRecord? property) {
    if (property == null) {
      return 'N/A';
    }
    final parts = <String>[
      property.addressLine1,
      if (property.addressLine2 != null &&
          property.addressLine2!.trim().isNotEmpty)
        property.addressLine2!,
      property.city,
      property.country,
    ].where((part) => part.trim().isNotEmpty).toList(growable: false);
    return parts.isEmpty ? 'N/A' : parts.join(', ');
  }

  static String _formatNumber(double value) => value.toStringAsFixed(2);

  static Color _toneFor(double value) {
    if (value < 0) {
      return _rose;
    }
    if (value > 0) {
      return _teal;
    }
    return _text;
  }

  static String _formatOptional(double? value) {
    if (value == null) {
      return 'N/A';
    }
    return value.toStringAsFixed(2);
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

class _SnapshotRow {
  const _SnapshotRow({required this.label, required this.value});

  final String label;
  final String value;
}

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
    final normalized = normalizeInputs(
      inputs: state.inputs,
      settings: state.settings,
      incomeLines: state.incomeLines,
      expenseLines: state.expenseLines,
    );
    final inputs = normalized.inputs;
    final financing = resolveFinancing(inputs);
    final ltv =
        financing.totalAcquisitionCost <= 0
            ? null
            : financing.loanPrincipal / financing.totalAcquisitionCost;

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
      closingCostsBuy: financing.buyClosingCosts,
      totalAcquisitionCost: financing.totalAcquisitionCost,
      totalEquityInvested: financing.totalCashInvested,
      loanAmount: financing.loanPrincipal,
      ltv: ltv,
      holdPeriodLabel: '${normalized.horizonMonths}m',
      exitAssumptionMode:
          state.valuation.valuationMode == 'exit_cap'
              ? 'Exit Cap'
              : 'Appreciation',
    );
  }
}
