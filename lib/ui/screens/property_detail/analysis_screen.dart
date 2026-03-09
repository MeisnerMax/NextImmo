import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/sensitivity.dart';
import '../../state/analysis_state.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/data_table_widget.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/info_tooltip.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key, required this.scenarioId});

  final String scenarioId;

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  final Map<String, SensitivityGridResult> _cache =
      <String, SensitivityGridResult>{};
  SensitivityMetric _metric = SensitivityMetric.cashOnCash;
  SensitivityRangePreset _preset = SensitivityRangePreset.standard;
  bool _isComputing = false;
  double _progress = 0;
  String? _computeError;
  String? _activeComputeKey;

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(
      scenarioAnalysisControllerProvider(widget.scenarioId),
    );

    return stateAsync.when(
      data: (state) {
        final m = state.analysis.metrics;
        final proformaRows =
            state.analysis.proformaYears
                .map(
                  (year) => [
                    '${year.yearIndex}',
                    year.gsi.toStringAsFixed(0),
                    year.noi.toStringAsFixed(0),
                    year.debtService.toStringAsFixed(0),
                    year.cashflowBeforeTax.toStringAsFixed(0),
                    year.loanBalanceEnd.toStringAsFixed(0),
                  ],
                )
                .toList();

        final amortizationRows =
            state.analysis.amortizationSchedule
                .take(24)
                .map(
                  (entry) => [
                    '${entry.monthIndex}',
                    entry.payment.toStringAsFixed(2),
                    entry.interest.toStringAsFixed(2),
                    entry.principal.toStringAsFixed(2),
                    entry.balance.toStringAsFixed(2),
                  ],
                )
                .toList();

        final config = _currentConfig();
        final cacheKey = config.cacheKey(
          scenarioId: widget.scenarioId,
          inputsUpdatedAt: state.inputs.updatedAt,
          settingsUpdatedAt: state.settings.updatedAt,
        );
        final grid = _cache[cacheKey];
        if (grid == null && !_isComputing && _activeComputeKey != cacheKey) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            _recompute(state: state, config: config, cacheKey: cacheKey);
          });
        }

        return DefaultTabController(
          length: 4,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Summary'),
                  Tab(text: 'Proforma'),
                  Tab(text: 'Amortization'),
                  Tab(text: 'Sensitivity'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.page),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.component,
                            runSpacing: AppSpacing.component,
                            children: [
                              KpiCard(
                                label: 'NOI',
                                value: m.noiYear1.toStringAsFixed(2),
                              ),
                              KpiCard(
                                label: 'Annual Cashflow',
                                value: m.annualCashflowYear1.toStringAsFixed(2),
                              ),
                              KpiCard(
                                label: 'Cap Rate',
                                value:
                                    '${(m.capRate * 100).toStringAsFixed(2)}%',
                              ),
                              KpiCard(
                                label: 'COC',
                                value:
                                    '${(m.cashOnCash * 100).toStringAsFixed(2)}%',
                              ),
                              KpiCard(
                                label: 'Valuation Mode',
                                value: m.valuationMode,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Wrap(
                                spacing: AppSpacing.component,
                                runSpacing: 8,
                                children: [
                                  Text(
                                    'Exit Sale: ${m.exitSalePrice.toStringAsFixed(2)}',
                                  ),
                                  Text(
                                    'Sale Costs: ${m.exitSaleCosts.toStringAsFixed(2)}',
                                  ),
                                  Text(
                                    'Loan Payoff: ${m.exitLoanPayoff.toStringAsFixed(2)}',
                                  ),
                                  Text(
                                    'Net Sale: ${m.exitNetSale.toStringAsFixed(2)}',
                                  ),
                                  Text(
                                    'Exit Cashflow: ${m.exitCashflow.toStringAsFixed(2)}',
                                  ),
                                  if (m.exitStabilizedNoi != null)
                                    Text(
                                      'Stabilized NOI: ${m.exitStabilizedNoi!.toStringAsFixed(2)}',
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.page),
                      child: DataTableWidget(
                        columns: const [
                          'Year',
                          'GSI',
                          'NOI',
                          'Debt',
                          'Cashflow',
                          'Loan Balance',
                        ],
                        rows: proformaRows,
                        metricKeysByColumn: const {
                          'GSI': 'gsi',
                          'NOI': 'noi',
                          'Debt': 'debt_service',
                          'Cashflow': 'annual_cashflow',
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.page),
                      child: DataTableWidget(
                        columns: const [
                          'Month',
                          'Payment',
                          'Interest',
                          'Principal',
                          'Balance',
                        ],
                        rows: amortizationRows,
                        metricKeysByColumn: const {'Payment': 'debt_service'},
                      ),
                    ),
                    _buildSensitivityTab(
                      context: context,
                      state: state,
                      config: config,
                      cacheKey: cacheKey,
                      grid: grid,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildSensitivityTab({
    required BuildContext context,
    required ScenarioAnalysisState state,
    required SensitivityConfig config,
    required String cacheKey,
    required SensitivityGridResult? grid,
  }) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<SensitivityMetric>(
                  value: _metric,
                  items:
                      SensitivityMetric.values
                          .map(
                            (metric) => DropdownMenuItem(
                              value: metric,
                              child: Text(_metricLabel(metric)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _metric = value;
                      _computeError = null;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'Metric'),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<SensitivityRangePreset>(
                  value: _preset,
                  items:
                      SensitivityRangePreset.values
                          .map(
                            (preset) => DropdownMenuItem(
                              value: preset,
                              child: Text(_rangeLabel(preset)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _preset = value;
                      _computeError = null;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'Range preset'),
                ),
              ),
              ElevatedButton(
                onPressed:
                    _isComputing
                        ? null
                        : () => _recompute(
                          state: state,
                          config: config,
                          cacheKey: cacheKey,
                        ),
                child: const Text('Recompute'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          if (_isComputing)
            LinearProgressIndicator(value: _progress <= 0 ? null : _progress),
          if (_isComputing) const SizedBox(height: 8),
          if (_computeError != null)
            Text(_computeError!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child:
                grid == null
                    ? const Center(
                      child: Text('Sensitivity grid is being prepared...'),
                    )
                    : _gridTable(grid),
          ),
        ],
      ),
    );
  }

  Widget _gridTable(SensitivityGridResult grid) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columns: <DataColumn>[
              DataColumn(
                label: Row(
                  children: const [
                    Text('Purchase \\ Rent'),
                    SizedBox(width: 6),
                    InfoTooltip(metricKey: 'sensitivity', size: 14),
                  ],
                ),
              ),
              ...grid.rentDeltas.map(
                (delta) => DataColumn(label: Text(_formatDelta(delta))),
              ),
            ],
            rows: List<DataRow>.generate(grid.purchasePriceDeltas.length, (
              rowIndex,
            ) {
              final purchaseDelta = grid.purchasePriceDeltas[rowIndex];
              final row = grid.cells[rowIndex];
              return DataRow(
                cells: <DataCell>[
                  DataCell(
                    Text(
                      _formatDelta(purchaseDelta),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ...row.map((value) {
                    final resolved = value ?? 0;
                    final color =
                        resolved >= 0
                            ? const Color(0xFFEAF7EE)
                            : const Color(0xFFFCECED);
                    return DataCell(
                      Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_formatMetric(value)),
                      ),
                    );
                  }),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  SensitivityConfig _currentConfig() {
    final deltas = SensitivityEngine.rangeByPreset(_preset);
    return SensitivityConfig(
      metric: _metric,
      rentDeltas: deltas,
      purchasePriceDeltas: deltas,
    );
  }

  Future<void> _recompute({
    required ScenarioAnalysisState state,
    required SensitivityConfig config,
    required String cacheKey,
  }) async {
    setState(() {
      _isComputing = true;
      _progress = 0;
      _computeError = null;
      _activeComputeKey = cacheKey;
    });

    try {
      final engine = ref.read(sensitivityEngineProvider);
      final cells = <List<double?>>[];
      final totalRows = config.purchasePriceDeltas.length;

      for (var rowIndex = 0; rowIndex < totalRows; rowIndex++) {
        final purchaseDelta = config.purchasePriceDeltas[rowIndex];
        final rowResult = engine.run(
          config: SensitivityConfig(
            metric: config.metric,
            rentDeltas: config.rentDeltas,
            purchasePriceDeltas: <double>[purchaseDelta],
          ),
          inputs: state.inputs,
          settings: state.settings,
          incomeLines: state.incomeLines,
          expenseLines: state.expenseLines,
          valuation: state.valuation,
        );
        cells.add(rowResult.cells.first);
        await Future<void>.delayed(Duration.zero);
        if (!mounted) {
          return;
        }
        setState(() {
          _progress = (rowIndex + 1) / totalRows;
        });
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _cache[cacheKey] = SensitivityGridResult(
          metric: config.metric,
          rentDeltas: config.rentDeltas,
          purchasePriceDeltas: config.purchasePriceDeltas,
          cells: cells,
        );
        _isComputing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _computeError = 'Sensitivity computation failed: $error';
        _isComputing = false;
      });
    }
  }

  String _metricLabel(SensitivityMetric metric) {
    switch (metric) {
      case SensitivityMetric.cashOnCash:
        return 'Cash on Cash';
      case SensitivityMetric.capRate:
        return 'Cap Rate';
      case SensitivityMetric.irr:
        return 'IRR';
      case SensitivityMetric.monthlyCashflow:
        return 'Monthly Cashflow';
    }
  }

  String _rangeLabel(SensitivityRangePreset preset) {
    switch (preset) {
      case SensitivityRangePreset.tight:
        return 'Tight (-10%..+10%)';
      case SensitivityRangePreset.standard:
        return 'Standard (-20%..+20%)';
      case SensitivityRangePreset.wide:
        return 'Wide (-30%..+30%)';
    }
  }

  String _formatDelta(double delta) {
    final sign = delta >= 0 ? '+' : '';
    return '$sign${(delta * 100).toStringAsFixed(0)}%';
  }

  String _formatMetric(double? value) {
    if (value == null) {
      return 'N/A';
    }
    switch (_metric) {
      case SensitivityMetric.cashOnCash:
      case SensitivityMetric.capRate:
      case SensitivityMetric.irr:
        return '${(value * 100).toStringAsFixed(2)}%';
      case SensitivityMetric.monthlyCashflow:
        return value.toStringAsFixed(2);
    }
  }
}
