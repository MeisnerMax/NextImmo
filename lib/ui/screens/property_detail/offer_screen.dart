import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offer/offer_solver.dart';
import '../../state/analysis_state.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_parse.dart';
import '../../widgets/kpi_tile.dart';

class OfferScreen extends ConsumerStatefulWidget {
  const OfferScreen({super.key, required this.scenarioId});

  final String scenarioId;

  @override
  ConsumerState<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends ConsumerState<OfferScreen> {
  String _metric = 'cash_on_cash';
  final _targetController = TextEditingController(text: '0.12');
  final _highController = TextEditingController(text: '400000');
  OfferSolveResult? _result;
  String? _error;

  @override
  void dispose() {
    _targetController.dispose();
    _highController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(
      scenarioAnalysisControllerProvider(widget.scenarioId),
    );

    return stateAsync.when(
      data: (state) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 380,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Objective',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.component),
                        DropdownButtonFormField<String>(
                          value: _metric,
                          decoration: const InputDecoration(
                            labelText: 'Objective',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'cash_on_cash',
                              child: Text('Reach cash on cash'),
                            ),
                            DropdownMenuItem(
                              value: 'irr',
                              child: Text('Reach IRR'),
                            ),
                            DropdownMenuItem(
                              value: 'monthly_cashflow',
                              child: Text('Reach monthly cashflow'),
                            ),
                            DropdownMenuItem(
                              value: 'roi',
                              child: Text('Reach ROI'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _metric = value);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _targetController,
                          decoration: const InputDecoration(
                            labelText: 'Target value',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _highController,
                          decoration: const InputDecoration(
                            labelText: 'High price bound',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.component),
                        ElevatedButton(
                          onPressed: () => _solve(state),
                          child: const Text('Calculate MAO'),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.section),
              Expanded(
                child:
                    _result == null
                        ? const Card(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(AppSpacing.section),
                              child: Text('No MAO calculated yet.'),
                            ),
                          ),
                        )
                        : Card(
                          child: Padding(
                            padding: const EdgeInsets.all(
                              AppSpacing.cardPadding,
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  KpiTile(
                                    title: 'Maximum Allowable Offer',
                                    value: _result!.mao.toStringAsFixed(2),
                                    metricKey: 'mao',
                                    status:
                                        _result!.isFeasible
                                            ? KpiTileStatus.positive
                                            : KpiTileStatus.warning,
                                    width: double.infinity,
                                  ),
                                  const SizedBox(height: AppSpacing.component),
                                  Wrap(
                                    spacing: AppSpacing.component,
                                    runSpacing: AppSpacing.component,
                                    children: [
                                      KpiTile(
                                        title: 'Cash on Cash',
                                        value:
                                            '${(_result!.analysisAtMao.metrics.cashOnCash * 100).toStringAsFixed(2)}%',
                                        metricKey: 'cash_on_cash',
                                      ),
                                      KpiTile(
                                        title: 'IRR',
                                        value:
                                            _result!
                                                        .analysisAtMao
                                                        .metrics
                                                        .irr ==
                                                    null
                                                ? 'N/A'
                                                : '${(_result!.analysisAtMao.metrics.irr! * 100).toStringAsFixed(2)}%',
                                        metricKey: 'irr',
                                      ),
                                      KpiTile(
                                        title: 'Monthly Cashflow',
                                        value: _result!
                                            .analysisAtMao
                                            .metrics
                                            .monthlyCashflowYear1
                                            .toStringAsFixed(2),
                                        metricKey: 'monthly_cashflow',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Feasible: ${_result!.isFeasible ? 'yes' : 'no'}',
                                  ),
                                  Text(
                                    'Final gap: ${_result!.finalGap?.toStringAsFixed(6) ?? 'N/A'}',
                                  ),
                                  Text(
                                    'Bounds gap: low=${_result!.lowBoundGap?.toStringAsFixed(6) ?? 'N/A'} high=${_result!.highBoundGap?.toStringAsFixed(6) ?? 'N/A'}',
                                  ),
                                  if (_result!.warnings.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    ..._result!.warnings.map(
                                      (warning) => Text('Warning: $warning'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
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

  void _solve(ScenarioAnalysisState state) {
    final target = parseDoubleFlexible(_targetController.text);
    final high = parseDoubleFlexible(_highController.text);

    if (target == null || high == null || high <= 0) {
      setState(() {
        _error = 'Provide valid numeric target and high bound.';
      });
      return;
    }

    final solver = ref.read(offerSolverProvider);
    final result = solver.solve(
      OfferSolveRequest(
        baseInputs: state.inputs,
        settings: state.settings,
        incomeLines: state.incomeLines,
        expenseLines: state.expenseLines,
        targetMetricKey: _metric,
        targetValue: target,
        highBound: high,
      ),
    );

    setState(() {
      _result = result;
      _error = null;
    });
  }
}
