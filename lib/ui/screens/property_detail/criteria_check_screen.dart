import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/criteria.dart';
import '../../state/analysis_state.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/info_tooltip.dart';
import '../../widgets/status_badge.dart';

class CriteriaCheckScreen extends ConsumerStatefulWidget {
  const CriteriaCheckScreen({super.key, required this.scenarioId});

  final String scenarioId;

  @override
  ConsumerState<CriteriaCheckScreen> createState() =>
      _CriteriaCheckScreenState();
}

class _CriteriaCheckScreenState extends ConsumerState<CriteriaCheckScreen> {
  late Future<_CriteriaContext> _contextFuture;
  String? _sourceMode;
  String? _selectedOverrideSetId;

  @override
  void initState() {
    super.initState();
    _contextFuture = _loadContext();
  }

  @override
  void didUpdateWidget(covariant CriteriaCheckScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scenarioId != widget.scenarioId) {
      _contextFuture = _loadContext();
    }
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
          child: FutureBuilder<_CriteriaContext>(
            future: _contextFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                return const Center(child: CircularProgressIndicator());
              }

              final contextData = snapshot.data!;
              final criteria = state.criteria;
              _sourceMode ??=
                  contextData.overrideCriteriaSetId == null
                      ? 'default'
                      : 'override';
              _selectedOverrideSetId ??= contextData.overrideCriteriaSetId;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (criteria != null)
                    StatusBadge(
                      label: criteria.passed ? 'PASS' : 'FAIL',
                      color:
                          criteria.passed
                              ? AppColors.positive
                              : AppColors.negative,
                    )
                  else
                    const Text('No active criteria set. Configure one below.'),
                  const SizedBox(height: AppSpacing.component),
                  if (contextData.propertyId != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.component),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              value: _sourceMode,
                              items: const [
                                DropdownMenuItem(
                                  value: 'default',
                                  child: Text('Use global default'),
                                ),
                                DropdownMenuItem(
                                  value: 'override',
                                  child: Text('Use property override'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() {
                                  _sourceMode = value;
                                });
                              },
                              decoration: const InputDecoration(
                                labelText: 'Criteria source',
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_sourceMode == 'override')
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: _selectedOverrideSetId,
                                      items:
                                          contextData.sets
                                              .map(
                                                (set) => DropdownMenuItem(
                                                  value: set.id,
                                                  child: Text(set.name),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedOverrideSetId = value;
                                        });
                                      },
                                      decoration: const InputDecoration(
                                        labelText: 'Override set',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed:
                                        _selectedOverrideSetId == null
                                            ? null
                                            : () => _applyOverride(
                                              propertyId:
                                                  contextData.propertyId!,
                                              criteriaSetId:
                                                  _selectedOverrideSetId!,
                                            ),
                                    child: Text(
                                      contextData.overrideCriteriaSetId == null
                                          ? 'Set override'
                                          : 'Change override',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed:
                                        contextData.overrideCriteriaSetId ==
                                                null
                                            ? null
                                            : () => _clearOverride(
                                              contextData.propertyId!,
                                            ),
                                    child: const Text('Clear override'),
                                  ),
                                ],
                              ),
                            if (_sourceMode == 'override' &&
                                contextData.sets.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'No criteria sets available. Create one in Criteria Sets first.',
                                ),
                              ),
                            if (_sourceMode == 'default' &&
                                contextData.overrideCriteriaSetId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: ElevatedButton(
                                  onPressed:
                                      () => _clearOverride(
                                        contextData.propertyId!,
                                      ),
                                  child: const Text('Apply global default now'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.component),
                  Expanded(
                    child:
                        criteria == null
                            ? const SizedBox.shrink()
                            : ListView.builder(
                              itemCount: criteria.evaluations.length,
                              itemBuilder: (context, index) {
                                final rule = criteria.evaluations[index];
                                final status =
                                    rule.unknown
                                        ? 'unknown'
                                        : (rule.pass ? 'pass' : 'fail');
                                final metricKey = rule.rule.fieldKey;
                                final statusColor = switch (status) {
                                  'pass' => AppColors.positive,
                                  'fail' =>
                                    rule.rule.severity == 'hard'
                                        ? AppColors.negative
                                        : AppColors.warning,
                                  _ => AppColors.textSecondary,
                                };
                                return Card(
                                  child: ListTile(
                                    dense: true,
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${rule.rule.fieldKey} ${rule.rule.operator} ${rule.rule.targetValue}',
                                          ),
                                        ),
                                        InfoTooltip(
                                          metricKey: metricKey,
                                          size: 14,
                                        ),
                                      ],
                                    ),
                                    subtitle: Row(
                                      children: [
                                        const Text('Actual: '),
                                        const Spacer(),
                                        Text(
                                          rule.actualValue?.toStringAsFixed(
                                                4,
                                              ) ??
                                              'N/A',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: StatusBadge(
                                      label:
                                          '${rule.rule.severity.toUpperCase()} | $status',
                                      color: statusColor,
                                    ),
                                  ),
                                );
                              },
                            ),
                  ),
                ],
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Future<void> _applyOverride({
    required String propertyId,
    required String criteriaSetId,
  }) async {
    await ref
        .read(criteriaRepositoryProvider)
        .setPropertyOverride(
          propertyId: propertyId,
          criteriaSetId: criteriaSetId,
        );
    await _reloadAfterChange();
  }

  Future<void> _clearOverride(String propertyId) async {
    await ref
        .read(criteriaRepositoryProvider)
        .clearPropertyOverride(propertyId);
    await _reloadAfterChange();
  }

  Future<void> _reloadAfterChange() async {
    await ref
        .read(scenarioAnalysisControllerProvider(widget.scenarioId).notifier)
        .reload();
    if (!mounted) {
      return;
    }
    setState(() {
      _contextFuture = _loadContext();
      _sourceMode = null;
      _selectedOverrideSetId = null;
    });
  }

  Future<_CriteriaContext> _loadContext() async {
    final scenario = await ref
        .read(scenarioRepositoryProvider)
        .getById(widget.scenarioId);
    final propertyId = scenario?.propertyId;
    final sets = await ref.read(criteriaRepositoryProvider).listSets();
    String? overrideId;
    if (propertyId != null) {
      overrideId = await ref
          .read(criteriaRepositoryProvider)
          .getPropertyOverride(propertyId);
    }

    return _CriteriaContext(
      propertyId: propertyId,
      sets: sets,
      overrideCriteriaSetId: overrideId,
    );
  }
}

class _CriteriaContext {
  const _CriteriaContext({
    required this.propertyId,
    required this.sets,
    required this.overrideCriteriaSetId,
  });

  final String? propertyId;
  final List<CriteriaSet> sets;
  final String? overrideCriteriaSetId;
}
