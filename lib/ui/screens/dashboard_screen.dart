import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/property.dart';
import '../state/property_state.dart';
import '../theme/app_theme.dart';
import '../widgets/kpi_tile.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertiesAsync = ref.watch(propertiesControllerProvider);

    return propertiesAsync.when(
      data: (properties) {
        final activeProperties = properties.where((p) => !p.archived).toList();
        final unitsTotal = activeProperties.fold<int>(
          0,
          (sum, property) => sum + property.units,
        );
        final avgUnits =
            activeProperties.isEmpty ? 0 : unitsTotal / activeProperties.length;

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.component,
                runSpacing: AppSpacing.component,
                children: [
                  KpiTile(
                    title: 'Active Properties',
                    value: '${activeProperties.length}',
                    metricKey: 'portfolio_kpi',
                  ),
                  KpiTile(
                    title: 'Total Units',
                    value: '$unitsTotal',
                    metricKey: 'portfolio_kpi',
                  ),
                  KpiTile(
                    title: 'Avg Units / Asset',
                    value: avgUnits.toStringAsFixed(1),
                    metricKey: 'portfolio_kpi',
                  ),
                  const KpiTile(
                    title: 'Engine Status',
                    value: 'Deterministic',
                    metricKey: 'data_quality',
                    status: KpiTileStatus.positive,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.section),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTypeChart(context, activeProperties)),
                    const SizedBox(width: AppSpacing.component),
                    Expanded(
                      child: _buildMonthlyChart(context, activeProperties),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              Text(
                'Needs Attention',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(child: _buildAttentionList(context, activeProperties)),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildTypeChart(
    BuildContext context,
    List<PropertyRecord> properties,
  ) {
    final typeCounts = <String, int>{};
    for (final property in properties) {
      typeCounts.update(
        property.propertyType,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final sortedEntries =
        typeCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final bars = <BarChartGroupData>[];
    for (var i = 0; i < sortedEntries.length; i++) {
      bars.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: sortedEntries[i].value.toDouble(),
              width: 16,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Asset Mix by Property Type',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Distribution of active properties by type.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            Expanded(
              child:
                  sortedEntries.isEmpty
                      ? const Center(child: Text('No properties available.'))
                      : BarChart(
                        BarChartData(
                          maxY: math.max<double>(
                            1,
                            sortedEntries.first.value.toDouble() + 1,
                          ),
                          gridData: const FlGridData(show: false),
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
                                reservedSize: 24,
                                getTitlesWidget:
                                    (value, meta) =>
                                        Text(value.toInt().toString()),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index < 0 ||
                                      index >= sortedEntries.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final type = sortedEntries[index].key;
                                  final short =
                                      type.length > 10
                                          ? '${type.substring(0, 10)}…'
                                          : type;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      short,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: bars,
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyChart(
    BuildContext context,
    List<PropertyRecord> properties,
  ) {
    final now = DateTime.now();
    final buckets = <DateTime, int>{
      for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i): 0,
    };

    for (final property in properties) {
      final date = DateTime.fromMillisecondsSinceEpoch(property.createdAt);
      final month = DateTime(date.year, date.month);
      if (buckets.containsKey(month)) {
        buckets[month] = buckets[month]! + 1;
      }
    }

    final entries = buckets.entries.toList();
    final spots = <FlSpot>[];
    for (var i = 0; i < entries.length; i++) {
      spots.add(FlSpot(i.toDouble(), entries[i].value.toDouble()));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New Properties (6 Months)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Monthly intake trend for quick pipeline monitoring.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: 0,
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: true),
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
                        reservedSize: 24,
                        getTitlesWidget:
                            (value, _) => Text(value.toInt().toString()),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= entries.length) {
                            return const SizedBox.shrink();
                          }
                          final date = entries[index].key;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('${date.month}/${date.year % 100}'),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: Theme.of(context).colorScheme.secondary,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.18),
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

  Widget _buildAttentionList(
    BuildContext context,
    List<PropertyRecord> properties,
  ) {
    final sorted =
        properties.toList()..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

    if (sorted.isEmpty) {
      return Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.section),
            child: Text(
              'No deals yet. Create your first property from Properties.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }

    final stale = sorted.take(8).toList();

    return Card(
      child: ListView.separated(
        itemCount: stale.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final property = stale[index];
          final updated = DateTime.fromMillisecondsSinceEpoch(
            property.updatedAt,
          );
          return ListTile(
            title: Text(property.name),
            subtitle: Text(
              '${property.city} • Last update ${updated.toIso8601String().substring(0, 10)}',
            ),
            trailing: Text(property.propertyType),
          );
        },
      ),
    );
  }
}
