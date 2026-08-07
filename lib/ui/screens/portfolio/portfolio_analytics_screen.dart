import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/portfolio_analytics.dart';
import '../../components/nx_card.dart';
import '../../components/nx_chart_container.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_page_header.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Portfolio analytics (SCR-045, Phase 2 Wave 1 / AP7a): a calm metrics + chart
/// page for the portfolio's IRR and cashflows. The `setState`-based compute is
/// unchanged; the presentation was lifted to the system standard —
/// `NxPageHeader` (with an explicit back action, this is a pushed route),
/// `NxCard` metric tiles, the cashflow chart in an `NxChartContainer`, a
/// skeleton instead of a bare progress bar, and an error-with-retry state
/// instead of raw exception text. Colour literals moved onto semantic tokens.
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
  bool _hasError = false;

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
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NxPageHeader(
              title: 'Portfolio Analytics — ${widget.portfolioName}',
              secondaryActions: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Zurück'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            _controlsBar(),
            const SizedBox(height: AppSpacing.component),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _controlsBar() {
    final result = _result;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: TextFormField(
            initialValue: _fromPeriod,
            decoration: const InputDecoration(labelText: 'Von (YYYY-MM)'),
            onChanged: (value) => _fromPeriod = value.trim(),
          ),
        ),
        SizedBox(
          width: 140,
          child: TextFormField(
            initialValue: _toPeriod,
            decoration: const InputDecoration(labelText: 'Bis (YYYY-MM)'),
            onChanged: (value) => _toPeriod = value.trim(),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _load,
          icon: const Icon(Icons.calculate_outlined, size: 16),
          label: const Text('Berechnen'),
        ),
        OutlinedButton.icon(
          onPressed: result == null || result.datedCashflows.isEmpty
              ? null
              : _exportCsv,
          icon: const Icon(Icons.file_download_outlined, size: 16),
          label: const Text('Cashflows CSV'),
        ),
      ],
    );
  }

  Widget _content() {
    if (_hasError) {
      return SingleChildScrollView(
        child: NxEmptyState(
          title: 'Analytics konnte nicht berechnet werden',
          description:
              'Bei der Berechnung der Portfolio-Analytik ist ein Fehler '
              'aufgetreten. Bitte versuchen Sie es erneut.',
          icon: Icons.error_outline,
          primaryAction: ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        ),
      );
    }

    final result = _result;
    if (_isLoading || result == null) {
      return const _AnalyticsSkeleton();
    }

    final hasPeriods = result.periodTable.isNotEmpty;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.warning != null) ...[
            _WarningBanner(message: result.warning!),
            const SizedBox(height: AppSpacing.component),
          ],
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _kpiTile(
                'Portfolio IRR',
                result.irr == null
                    ? 'N/A'
                    : '${(result.irr! * 100).toStringAsFixed(2)}%',
              ),
              _kpiTile('Total Inflows', result.totalInflows.toStringAsFixed(2)),
              _kpiTile('Total Outflows', result.totalOutflows.toStringAsFixed(2)),
              _kpiTile('Net Cashflow', result.netCashflow.toStringAsFixed(2)),
              _kpiTile(
                'Avg Monthly Net',
                result.averageMonthlyNet.toStringAsFixed(2),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          NxChartContainer(
            title: 'Cashflow Verlauf',
            subtitle: 'Zu- und Abflüsse sowie Netto je Periode',
            height: 300,
            state: hasPeriods ? NxChartState.ready : NxChartState.empty,
            emptyText: 'Keine Cashflows im gewählten Zeitraum.',
            child: _PortfolioCashflowChart(periodTable: result.periodTable),
          ),
          if (hasPeriods) ...[
            const SizedBox(height: 8),
            _legend(),
          ],
          if (hasPeriods) ...[
            const SizedBox(height: AppSpacing.component),
            _periodTableCard(result.periodTable),
          ],
        ],
      ),
    );
  }

  Widget _legend() {
    final semantic = context.semanticColors;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _LegendItem(color: semantic.success, label: 'Zuflüsse'),
        _LegendItem(color: semantic.error, label: 'Abflüsse'),
        _LegendItem(
          color: Theme.of(context).colorScheme.primary,
          label: 'Netto-Cashflow',
        ),
      ],
    );
  }

  Widget _kpiTile(String label, String value) {
    return SizedBox(
      width: 200,
      child: NxCard(
        variant: NxCardVariant.kpi,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.semanticColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ).merge(context.tabularNumericStyle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodTableCard(List<PortfolioCashflowPeriodAggregate> periodTable) {
    return NxCard(
      padding: EdgeInsets.zero,
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Periode')),
              DataColumn(label: Text('Zuflüsse')),
              DataColumn(label: Text('Abflüsse')),
              DataColumn(label: Text('Netto')),
            ],
            rows: periodTable
                .map(
                  (row) => DataRow(
                    cells: [
                      DataCell(Text(row.periodKey)),
                      DataCell(Text(row.totalInflows.toStringAsFixed(2),
                          style: context.tabularNumericStyle)),
                      DataCell(Text(row.totalOutflows.toStringAsFixed(2),
                          style: context.tabularNumericStyle)),
                      DataCell(Text(row.netCashflow.toStringAsFixed(2),
                          style: context.tabularNumericStyle)),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
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
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _hasError = true;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cashflows exportiert: ${location.path}')),
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
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final warning = context.semanticColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: warning.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, size: 18, color: warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: warning,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

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
    return SingleChildScrollView(
      child: Column(
        key: const ValueKey<String>('analytics_skeleton'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: List.generate(
              5,
              (_) => SizedBox(
                width: 200,
                child: NxCard(
                  variant: NxCardVariant.kpi,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(110, 10),
                      const SizedBox(height: 12),
                      bar(70, 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.component),
          NxCard(child: bar(double.infinity, 260)),
        ],
      ),
    );
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

    final semantic = context.semanticColors;
    final primary = Theme.of(context).colorScheme.primary;
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
              gradient: LinearGradient(
                colors: [semantic.success, semantic.success.withValues(alpha: 0.7)],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
            BarChartRodData(
              toY: row.totalOutflows.abs(),
              width: 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              gradient: LinearGradient(
                colors: [semantic.error, semantic.error.withValues(alpha: 0.7)],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
            BarChartRodData(
              toY: row.netCashflow,
              width: 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              gradient: LinearGradient(
                colors: [primary, primary.withValues(alpha: 0.6)],
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

    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: minY,
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
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => Theme.of(context).colorScheme.surface,
            tooltipBorder: BorderSide(color: semantic.border, width: 1.5),
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
                (Theme.of(context).textTheme.labelMedium ?? const TextStyle())
                    .copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    )
                    .merge(context.tabularNumericStyle),
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
                    color: semantic.textSecondary,
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
                      color: semantic.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: barGroups,
      ),
    );
  }
}
