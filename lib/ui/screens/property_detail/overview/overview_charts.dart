import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/engine/normalize.dart';
import '../../../components/nx_chart_container.dart';
import '../../../state/analysis_state.dart';
import '../../../theme/app_theme.dart';

const double _chartHeight = 260;

/// Cashflow projection chart of the overview screen (SCR-011 section 4) in an
/// `NxChartContainer` with the annual/monthly toggle as header action.
class OverviewCashflowChart extends StatefulWidget {
  const OverviewCashflowChart({super.key, required this.state});

  final ScenarioAnalysisState state;

  @override
  State<OverviewCashflowChart> createState() => _OverviewCashflowChartState();
}

enum _CashflowMode { annual, monthlyAverage }

class _OverviewCashflowChartState extends State<OverviewCashflowChart> {
  _CashflowMode _mode = _CashflowMode.annual;

  @override
  Widget build(BuildContext context) {
    final useMonthly = _mode == _CashflowMode.monthlyAverage;
    final annualPeriods = widget.state.analysis.proformaYears;
    final monthlyPeriods = widget.state.analysis.proformaMonths;
    final hasData = annualPeriods.isNotEmpty && monthlyPeriods.isNotEmpty;

    final values = !hasData
        ? const <double>[]
        : useMonthly
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

    return NxChartContainer(
      title: 'Cashflow Projection',
      state: hasData ? NxChartState.ready : NxChartState.empty,
      emptyText: 'Keine Proforma-Daten vorhanden.',
      height: _chartHeight,
      trailing: hasData
          ? ToggleButtons(
              isSelected: [
                _mode == _CashflowMode.annual,
                _mode == _CashflowMode.monthlyAverage,
              ],
              onPressed: (index) {
                setState(() {
                  _mode = index == 0
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
            )
          : null,
      child: !hasData
          ? const SizedBox.shrink()
          : LineChart(
              buildOverviewLineChartData(
                context: context,
                values: values,
                spots: spots,
                minY: overviewMinAxisValue(values),
                // Series colour comes from the validated chart palette, not
                // from `colorScheme.primary`: the accent is reserved for
                // interaction, and palette steps are checked for chroma and
                // CVD separation against the chart surface.
                lineColor: AppChartPalette.at(0),
                bottomLabel: (period) => useMonthly ? 'M$period' : 'Y$period',
              ),
            ),
    );
  }
}

/// Rent projection chart of the overview screen in an `NxChartContainer`.
class OverviewRentProjectionChart extends StatelessWidget {
  const OverviewRentProjectionChart({
    super.key,
    required this.state,
    required this.monthlyRentStart,
  });

  final ScenarioAnalysisState state;
  final double monthlyRentStart;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeInputs(
      inputs: state.inputs,
      settings: state.settings,
      incomeLines: state.incomeLines,
      expenseLines: state.expenseLines,
    );
    final monthsCount = state.analysis.proformaMonths.length;
    final hasData = monthsCount > 0;

    final growth = normalized.inputs.rentGrowthPercent;
    final values = <double>[
      if (hasData)
        for (var month = 1; month <= monthsCount; month++)
          monthlyRentStart * math.pow(1 + growth, (month - 1) / 12).toDouble(),
    ];
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++)
        FlSpot((i + 1).toDouble(), values[i]),
    ];

    return NxChartContainer(
      title: 'Rent Projection',
      state: hasData ? NxChartState.ready : NxChartState.empty,
      emptyText: 'Keine Projektionsmonate vorhanden.',
      height: _chartHeight,
      child: !hasData
          ? const SizedBox.shrink()
          : LineChart(
              buildOverviewLineChartData(
                context: context,
                values: values,
                spots: spots,
                minY: 0,
                // Was `colorScheme.secondary`, which resolves to #CBD5E1 in
                // dark — a near-neutral slate that fails the chart palette's
                // chroma floor and drew this projection in grey.
                lineColor: AppChartPalette.at(1),
                bottomLabel: (period) => 'M$period',
              ),
            ),
    );
  }
}

/// Shared token-based line chart configuration for both overview charts.
LineChartData buildOverviewLineChartData({
  required BuildContext context,
  required List<double> values,
  required List<FlSpot> spots,
  required double minY,
  required Color lineColor,
  required String Function(int period) bottomLabel,
}) {
  final semantic = context.semanticColors;
  final surface = Theme.of(context).colorScheme.surface;
  return LineChartData(
    minX: 1,
    maxX: values.length.toDouble(),
    minY: minY,
    maxY: overviewMaxAxisValue(values),
    gridData: FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (value) => FlLine(
        color: semantic.border.withValues(alpha: 0.4),
        strokeWidth: 1,
        dashArray: [4, 4],
      ),
    ),
    borderData: FlBorderData(show: false),
    lineTouchData: LineTouchData(
      enabled: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (spot) => surface,
        tooltipBorder: BorderSide(color: semantic.border, width: 1.5),
        tooltipPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        tooltipRoundedRadius: AppRadiusTokens.md,
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((touchedSpot) {
            return LineTooltipItem(
              '€ ${touchedSpot.y.toStringAsFixed(2)}',
              (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                  .copyWith(fontWeight: FontWeight.w700)
                  .merge(context.tabularNumericStyle),
            );
          }).toList();
        },
      ),
    ),
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
          reservedSize: 64,
          getTitlesWidget: (value, _) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '€ ${value.toStringAsFixed(0)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: semantic.textSecondary)
                  .merge(context.tabularNumericStyle),
              textAlign: TextAlign.right,
            ),
          ),
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
                bottomLabel(period),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
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
        color: lineColor,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
            radius: 4.5,
            color: lineColor,
            strokeWidth: 2,
            strokeColor: surface,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            colors: [
              lineColor.withValues(alpha: 0.24),
              lineColor.withValues(alpha: 0.0),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        spots: spots,
      ),
    ],
  );
}

double overviewMaxAxisValue(List<double> values) {
  final maxValue = values.fold<double>(
    double.negativeInfinity,
    (current, value) => math.max(current, value),
  );
  if (!maxValue.isFinite) {
    return 1;
  }
  return maxValue <= 0 ? 1 : maxValue * 1.1;
}

double overviewMinAxisValue(List<double> values) {
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
