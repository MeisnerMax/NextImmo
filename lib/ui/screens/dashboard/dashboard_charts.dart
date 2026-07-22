import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../components/nx_chart_container.dart';
import '../../theme/app_theme.dart';
import 'dashboard_view_model.dart';

const double _lineChartHeight = 320;
const double _barChartHeight = 250;

/// Right-column trend charts of the dashboard (SCR-004): portfolio value
/// development (line) and property-type distribution (bar), both wrapped in
/// `NxChartContainer` per the wave's chart-consistency rule.
class DashboardCharts extends StatelessWidget {
  const DashboardCharts({super.key, required this.overview});

  final DashboardOverviewData overview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardValuationChart(overview: overview),
        const SizedBox(height: AppSpacing.component),
        DashboardTypeMixChart(values: overview.propertyTypeMix),
      ],
    );
  }
}

/// Portfolio value development as an `NxChartContainer` line chart with the
/// period selector as the header action.
class DashboardValuationChart extends StatefulWidget {
  const DashboardValuationChart({super.key, required this.overview});

  final DashboardOverviewData overview;

  @override
  State<DashboardValuationChart> createState() =>
      _DashboardValuationChartState();
}

class _DashboardValuationChartState extends State<DashboardValuationChart> {
  String _selected = '6M';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final allValues = buildDashboardValuationTrend(widget.overview);
    final hasData = allValues.isNotEmpty;
    final values = _filteredValues(allValues);

    final currentVal = hasData ? allValues.last.value : 0.0;
    final firstVal = hasData ? allValues.first.value : 0.0;
    final changePercent =
        firstVal > 0 ? (currentVal - firstVal) / firstVal : 0.0;
    final changeColor =
        changePercent >= 0 ? semantic.success : semantic.error;

    return NxChartContainer(
      title: 'Wertentwicklung',
      subtitle: 'Portfolio-Wert aus Jahresmiete abzüglich laufender Kosten.',
      state: hasData ? NxChartState.ready : NxChartState.empty,
      emptyText: 'Noch keine Wertdaten.',
      height: _lineChartHeight,
      trailing: hasData
          ? _ValuationPeriodSelector(
              selected: _selected,
              onChanged: (value) => setState(() => _selected = value),
            )
          : null,
      child: !hasData
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'GESAMTPORTFOLIO-WERT',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: semantic.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatDashboardCurrency(currentVal),
                              style: theme.textTheme.titleLarge
                                  ?.merge(context.tabularNumericStyle)
                                  .copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.component),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          changePercent >= 0
                              ? Icons.trending_up
                              : Icons.trending_down,
                          color: changeColor,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${changePercent >= 0 ? '+' : ''}'
                          '${(changePercent * 100).toStringAsFixed(1)}% (12M)',
                          style: theme.textTheme.titleSmall
                              ?.merge(context.tabularNumericStyle)
                              .copyWith(
                                color: changeColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.component),
                Expanded(
                  child: values.isEmpty
                      ? const SizedBox.shrink()
                      : _ValuationTrendChart(values: values),
                ),
              ],
            ),
    );
  }

  List<DashboardValuePoint> _filteredValues(List<DashboardValuePoint> all) {
    if (_selected == '1J') {
      return all;
    }
    if (_selected == 'YTD') {
      final year = DateTime.now().year;
      final ytd = all.where((point) => point.date.year == year).toList();
      if (ytd.isNotEmpty) {
        return ytd;
      }
    }
    final start = math.max(0, all.length - 6);
    return all.skip(start).toList(growable: false);
  }
}

class _ValuationPeriodSelector extends StatelessWidget {
  const _ValuationPeriodSelector({
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
      segments: const [
        ButtonSegment(value: '6M', label: Text('6M')),
        ButtonSegment(value: 'YTD', label: Text('YTD')),
        ButtonSegment(value: '1J', label: Text('1J')),
      ],
      selected: <String>{selected},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _ValuationTrendChart extends StatelessWidget {
  const _ValuationTrendChart({required this.values});

  final List<DashboardValuePoint> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final surface = theme.colorScheme.surface;
    final spots = <FlSpot>[
      for (var index = 0; index < values.length; index++)
        FlSpot(index.toDouble(), values[index].value),
    ];
    final maxValue = values.fold<double>(
      0,
      (max, point) => point.value > max ? point.value : max,
    );
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxValue <= 0 ? 1 : maxValue * 1.05,
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
                  formatDashboardCurrency(touchedSpot.y),
                  (theme.textTheme.bodyMedium ?? const TextStyle())
                      .copyWith(fontWeight: FontWeight.w700)
                      .merge(context.tabularNumericStyle),
                );
              }).toList();
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 64,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  formatDashboardCurrency(value),
                  style: theme.textTheme.bodySmall
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
                final index = value.toInt();
                if (index < 0 || index >= values.length) {
                  return const SizedBox.shrink();
                }
                final date = values[index].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${date.month}/${date.year % 100}',
                    style: theme.textTheme.bodySmall?.copyWith(
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
            color: theme.colorScheme.primary,
            barWidth: 3.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius: 4.5,
                color: theme.colorScheme.primary,
                strokeWidth: 2,
                strokeColor: surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.24),
                  theme.colorScheme.primary.withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            spots: spots,
          ),
        ],
      ),
    );
  }
}

/// Property-type distribution as an `NxChartContainer` bar chart.
class DashboardTypeMixChart extends StatelessWidget {
  const DashboardTypeMixChart({super.key, required this.values});

  final List<DashboardCategoryValue> values;

  @override
  Widget build(BuildContext context) {
    return NxChartContainer(
      title: 'Objektverteilung',
      subtitle: 'Aktive Objekte nach Objekttyp.',
      state: values.isEmpty ? NxChartState.empty : NxChartState.ready,
      emptyText: 'Noch keine aktiven Objekte.',
      height: _barChartHeight,
      child: values.isEmpty
          ? const SizedBox.shrink()
          : _TypeMixChart(values: values),
    );
  }
}

class _TypeMixChart extends StatelessWidget {
  const _TypeMixChart({required this.values});

  final List<DashboardCategoryValue> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final bars = <BarChartGroupData>[
      for (var index = 0; index < values.length; index++)
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: values[index].value.toDouble(),
              width: 18,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.6),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ],
        ),
    ];

    return BarChart(
      BarChartData(
        maxY: math.max<double>(1, values.first.value.toDouble() + 1),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => theme.colorScheme.surface,
            tooltipBorder: BorderSide(color: semantic.border, width: 1.5),
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            tooltipRoundedRadius: AppRadiusTokens.md,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final val = values[groupIndex];
              return BarTooltipItem(
                '${val.label}: ${val.value}',
                (theme.textTheme.bodyMedium ?? const TextStyle())
                    .copyWith(fontWeight: FontWeight.w700)
                    .merge(context.tabularNumericStyle),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= values.length) {
                  return const SizedBox.shrink();
                }
                final label = values[index].label;
                final compact =
                    label.length > 10 ? '${label.substring(0, 10)}...' : label;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    compact,
                    style: theme.textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: bars,
      ),
    );
  }
}
