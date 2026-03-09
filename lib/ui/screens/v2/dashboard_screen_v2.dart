import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/property.dart';
import '../../components/nx_card.dart';
import '../../components/nx_chart_container.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_page_header.dart';
import '../../state/property_state.dart';
import '../../theme/app_theme.dart';

class DashboardScreenV2 extends ConsumerWidget {
  const DashboardScreenV2({super.key});

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
        final chartHeight =
            context.viewport == AppViewport.mobile ? 280.0 : 320.0;

        return Padding(
          padding: EdgeInsets.all(context.adaptivePagePadding),
          child: ListView(
            children: [
              const NxPageHeader(
                title: 'Portfolio Dashboard',
                breadcrumbs: ['Dashboard'],
                subtitle:
                    'Portfolio KPIs, trends, and operational attention points.',
              ),
              const SizedBox(height: AppSpacing.component),
              Wrap(
                spacing: AppSpacing.component,
                runSpacing: AppSpacing.component,
                children: [
                  _kpiCard(
                    context,
                    title: 'Active Properties',
                    value: '${activeProperties.length}',
                  ),
                  _kpiCard(context, title: 'Total Units', value: '$unitsTotal'),
                  _kpiCard(
                    context,
                    title: 'Avg Units / Asset',
                    value: avgUnits.toStringAsFixed(1),
                  ),
                  _kpiCard(
                    context,
                    title: 'Engine Status',
                    value: 'Deterministic',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.section),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 1080;
                  if (stacked) {
                    return Column(
                      children: [
                        SizedBox(
                          height: chartHeight,
                          child: _buildTypeChart(context, activeProperties),
                        ),
                        const SizedBox(height: AppSpacing.component),
                        SizedBox(
                          height: chartHeight,
                          child: _buildMonthlyChart(context, activeProperties),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: chartHeight,
                          child: _buildTypeChart(context, activeProperties),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.component),
                      Expanded(
                        child: SizedBox(
                          height: chartHeight,
                          child: _buildMonthlyChart(context, activeProperties),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.section),
              Text(
                'Needs Attention',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.component),
              SizedBox(
                height: 260,
                child: _buildAttentionList(context, activeProperties),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _kpiCard(
    BuildContext context, {
    required String title,
    required String value,
  }) {
    final width =
        context.viewport == AppViewport.mobile ? double.infinity : 260.0;
    return SizedBox(
      width: width,
      child: NxCard(
        variant: NxCardVariant.kpi,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
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
    return NxChartContainer(
      title: 'Asset Mix by Property Type',
      subtitle: 'Distribution of active properties by type.',
      state: sortedEntries.isEmpty ? NxChartState.empty : NxChartState.ready,
      child: BarChart(
        BarChartData(
          maxY: math.max<double>(1, sortedEntries.first.value.toDouble() + 1),
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
                    (value, meta) => Text(value.toInt().toString()),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= sortedEntries.length) {
                    return const SizedBox.shrink();
                  }
                  final type = sortedEntries[index].key;
                  final short =
                      type.length > 10 ? '${type.substring(0, 10)}…' : type;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      short,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: bars,
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
    return NxChartContainer(
      title: 'New Properties (6 Months)',
      subtitle: 'Monthly intake trend for quick pipeline monitoring.',
      state: NxChartState.ready,
      child: LineChart(
        LineChartData(
          minY: 0,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
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
                getTitlesWidget: (value, _) => Text(value.toInt().toString()),
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
    );
  }

  Widget _buildAttentionList(
    BuildContext context,
    List<PropertyRecord> properties,
  ) {
    final sorted =
        properties.toList()..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    if (sorted.isEmpty) {
      return const NxEmptyState(
        title: 'No deals yet',
        description: 'Create your first property from the Properties module.',
        icon: Icons.home_work_outlined,
      );
    }
    final stale = sorted.take(8).toList();
    return NxCard(
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
