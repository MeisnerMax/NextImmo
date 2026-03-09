import 'dart:io';

import 'package:file_selector/file_selector.dart';
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
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
