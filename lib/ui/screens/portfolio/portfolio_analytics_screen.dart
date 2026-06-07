import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/portfolio_analytics.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class PortfolioAnalyticsScreen extends ConsumerStatefulWidget {
  const PortfolioAnalyticsScreen({
    super.key,
    required this.portfolioId,
    required this.portfolioName,
  });

  final String portfolioId;
  final String portfolioName;

  @override
  ConsumerState<PortfolioAnalyticsScreen> createState() =>
      _PortfolioAnalyticsScreenState();
}

class _PortfolioAnalyticsScreenState
    extends ConsumerState<PortfolioAnalyticsScreen> {
  late String _fromPeriod;
  late String _toPeriod;
  PortfolioIrrResult? _result;
  bool _isLoading = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromPeriod = '${now.year}-01';
    _toPeriod = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text('Portfolio Analytics - ${widget.portfolioName}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    initialValue: _fromPeriod,
                    decoration: const InputDecoration(
                      labelText: 'From (YYYY-MM)',
                    ),
                    onChanged: (value) => _fromPeriod = value.trim(),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    initialValue: _toPeriod,
                    decoration: const InputDecoration(
                      labelText: 'To (YYYY-MM)',
                    ),
                    onChanged: (value) => _toPeriod = value.trim(),
                  ),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _load,
                  child: const Text('Compute'),
                ),
                OutlinedButton(
                  onPressed:
                      result == null || result.datedCashflows.isEmpty
                          ? null
                          : _exportCsv,
                  child: const Text('Export Cashflows CSV'),
                ),
              ],
            ),
            if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
            const SizedBox(height: AppSpacing.component),
            if (_isLoading) const LinearProgressIndicator(),
            if (result != null) ...[
              Wrap(
                spacing: AppSpacing.component,
                runSpacing: 8,
                children: [
                  _tile(
                    'Portfolio IRR',
                    result.irr == null
                        ? 'N/A'
                        : '${(result.irr! * 100).toStringAsFixed(2)}%',
                  ),
                  _tile(
                    'Total Inflows',
                    result.totalInflows.toStringAsFixed(2),
                  ),
                  _tile(
                    'Total Outflows',
                    result.totalOutflows.toStringAsFixed(2),
                  ),
                  _tile('Net Cashflow', result.netCashflow.toStringAsFixed(2)),
                  _tile(
                    'Avg Monthly Net',
                    result.averageMonthlyNet.toStringAsFixed(2),
                  ),
                ],
              ),
              if (result.warning != null) ...[
                const SizedBox(height: 8),
                Text(
                  result.warning!,
                  style: const TextStyle(color: Colors.orange),
                ),
              ],
              const SizedBox(height: AppSpacing.component),
              SizedBox(
                height: 280,
                child: _PortfolioCashflowChart(periodTable: result.periodTable),
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Period')),
                        DataColumn(label: Text('Inflows')),
                        DataColumn(label: Text('Outflows')),
                        DataColumn(label: Text('Net')),
                      ],
                      rows:
                          result.periodTable
                              .map(
                                (row) => DataRow(
                                  cells: [
                                    DataCell(Text(row.periodKey)),
                                    DataCell(
                                      Text(row.totalInflows.toStringAsFixed(2)),
                                    ),
                                    DataCell(
                                      Text(
                                        row.totalOutflows.toStringAsFixed(2),
                                      ),
                                    ),
                                    DataCell(
                                      Text(row.netCashflow.toStringAsFixed(2)),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(String label, String value) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700).merge(
              context.tabularNumericStyle,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _status = null;
    });
    try {
      final result = await ref
          .read(portfolioAnalyticsRepositoryProvider)
          .computePortfolioIRR(
            portfolioId: widget.portfolioId,
            fromPeriodKey: _fromPeriod,
            toPeriodKey: _toPeriod,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _status = 'Analytics failed: $error';
      });
    }
  }

  Future<void> _exportCsv() async {
    final result = _result;
    if (result == null) {
      return;
    }
    final location = await getSaveLocation(
      suggestedName:
          'portfolio_cashflows_${widget.portfolioId}_${DateTime.now().millisecondsSinceEpoch}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: <String>['csv']),
      ],
    );
    if (location == null) {
      return;
    }
    final csv = await ref
        .read(portfolioAnalyticsRepositoryProvider)
        .exportCashflowsCsv(cashflows: result.datedCashflows);
    await File(location.path).writeAsString(csv);
    await _mirrorExportToWorkspace(location.path);
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'Cashflows exported to ${location.path}';
    });
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
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PortfolioCashflowChart extends StatelessWidget {
  const _PortfolioCashflowChart({required this.periodTable});

  final List<PortfolioCashflowPeriodAggregate> periodTable;

  @override
  Widget build(BuildContext context) {
    if (periodTable.isEmpty) {
      return const SizedBox.shrink();
    }

    final barGroups = <BarChartGroupData>[];
    for (var index = 0; index < periodTable.length; index++) {
      final row = periodTable[index];
      barGroups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: row.totalInflows,
              width: 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF34D399)],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
            BarChartRodData(
              toY: row.totalOutflows.abs(),
              width: 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              gradient: const LinearGradient(
                colors: [Color(0xFFEF4444), Color(0xFFF87171)],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
            BarChartRodData(
              toY: row.netCashflow,
              width: 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                ],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
          ],
        ),
      );
    }

    double maxVal = 0;
    double minVal = 0;
    for (final row in periodTable) {
      maxVal = math.max(maxVal, math.max(row.totalInflows, math.max(row.totalOutflows.abs(), row.netCashflow)));
      minVal = math.min(minVal, math.min(row.totalInflows, math.min(-row.totalOutflows.abs(), row.netCashflow)));
    }
    final maxY = maxVal == 0 ? 1.0 : maxVal * 1.15;
    final minY = minVal >= 0 ? 0.0 : minVal * 1.15;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Cashflow Verlauf',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const Wrap(
                  spacing: 16,
                  children: [
                    _LegendItem(color: Color(0xFF10B981), label: 'Zuflüsse'),
                    _LegendItem(color: Color(0xFFEF4444), label: 'Abflüsse'),
                    _LegendItem(color: Colors.blue, label: 'Netto-Cashflow'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  minY: minY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: context.semanticColors.border.withValues(alpha: 0.4),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => Theme.of(context).colorScheme.surface,
                      tooltipBorder: BorderSide(color: context.semanticColors.border, width: 1.5),
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      tooltipRoundedRadius: AppRadiusTokens.md,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final row = periodTable[groupIndex];
                        String label = '';
                        double val = 0;
                        if (rodIndex == 0) {
                          label = 'Zuflüsse';
                          val = row.totalInflows;
                        } else if (rodIndex == 1) {
                          label = 'Abflüsse';
                          val = row.totalOutflows;
                        } else {
                          label = 'Netto-Cashflow';
                          val = row.netCashflow;
                        }
                        return BarTooltipItem(
                          '$label: € ${val.toStringAsFixed(2)}',
                          TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ).merge(context.tabularNumericStyle),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 64,
                        getTitlesWidget: (value, _) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '€ ${value.toStringAsFixed(0)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.semanticColors.textSecondary,
                            ).merge(context.tabularNumericStyle),
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
                          if (index < 0 || index >= periodTable.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              periodTable[index].periodKey,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.semanticColors.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: barGroups,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
