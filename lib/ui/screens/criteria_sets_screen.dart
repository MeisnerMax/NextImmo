import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/criteria.dart';
import '../docs/metric_definitions.dart';
import '../state/criteria_state.dart';
import '../theme/app_theme.dart';
import '../widgets/info_tooltip.dart';
import '../widgets/status_badge.dart';

class CriteriaSetsScreen extends ConsumerStatefulWidget {
  const CriteriaSetsScreen({super.key});

  @override
  ConsumerState<CriteriaSetsScreen> createState() => _CriteriaSetsScreenState();
}

class _CriteriaSetsScreenState extends ConsumerState<CriteriaSetsScreen> {
  @override
  Widget build(BuildContext context) {
    final setsAsync = ref.watch(criteriaSetsControllerProvider);
    final controller = ref.read(criteriaSetsControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton(
                onPressed: () => _showCreateSetDialog(controller),
                child: const Text('New Criteria Set'),
              ),
              const SizedBox(width: AppSpacing.component),
              OutlinedButton(
                onPressed: controller.reload,
                child: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: setsAsync.when(
              data: (sets) {
                if (sets.isEmpty) {
                  return const Center(
                    child: Text(
                      'No criteria sets yet. Create one to get started.',
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: sets.length,
                  itemBuilder: (context, index) {
                    final set = sets[index];
                    return Card(
                      child: ListTile(
                        title: Text(set.name),
                        subtitle: Row(
                          children: [
                            StatusBadge(
                              label: set.isDefault ? 'Default' : 'Optional',
                              color:
                                  set.isDefault
                                      ? AppColors.positive
                                      : AppColors.textSecondary,
                            ),
                          ],
                        ),
                        onTap: () => _openEditor(set),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => _showRenameSetDialog(set),
                              child: const Text('Rename'),
                            ),
                            TextButton(
                              onPressed:
                                  set.isDefault
                                      ? null
                                      : () async {
                                        await controller.setDefault(set.id);
                                      },
                              child: const Text('Set default'),
                            ),
                            TextButton(
                              onPressed:
                                  set.isDefault
                                      ? null
                                      : () => _confirmDeleteSet(set),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateSetDialog(CriteriaSetsController controller) async {
    final nameController = TextEditingController();
    var makeDefault = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create Criteria Set'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        errorText: errorText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: makeDefault,
                      onChanged: (value) {
                        setDialogState(() {
                          makeDefault = value ?? false;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Set as default'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = 'Name is required.';
                      });
                      return;
                    }

                    try {
                      await controller.createSet(
                        name: name,
                        isDefault: makeDefault,
                      );
                      if (mounted && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    } catch (error) {
                      setDialogState(() {
                        errorText = '$error'.replaceFirst('Bad state: ', '');
                      });
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
  }

  Future<void> _showRenameSetDialog(CriteriaSet set) async {
    final controller = ref.read(criteriaSetsControllerProvider.notifier);
    final nameController = TextEditingController(text: set.name);
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Rename Criteria Set'),
              content: TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = 'Name is required.';
                      });
                      return;
                    }
                    try {
                      await controller.renameSet(setId: set.id, name: name);
                      if (mounted && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    } catch (error) {
                      setDialogState(() {
                        errorText = '$error'.replaceFirst('Bad state: ', '');
                      });
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
  }

  Future<void> _confirmDeleteSet(CriteriaSet set) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Criteria Set'),
            content: Text(
              'Delete "${set.name}"? This also deletes all its rules.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    final controller = ref.read(criteriaSetsControllerProvider.notifier);
    await controller.deleteSet(set.id);
  }

  Future<void> _openEditor(CriteriaSet set) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CriteriaSetEditorScreen(set: set),
      ),
    );
    if (!mounted) {
      return;
    }
    await ref.read(criteriaSetsControllerProvider.notifier).reload();
  }
}

class _CriteriaSetEditorScreen extends ConsumerStatefulWidget {
  const _CriteriaSetEditorScreen({required this.set});

  final CriteriaSet set;

  @override
  ConsumerState<_CriteriaSetEditorScreen> createState() =>
      _CriteriaSetEditorScreenState();
}

class _CriteriaSetEditorScreenState
    extends ConsumerState<_CriteriaSetEditorScreen> {
  late Future<List<CriteriaRule>> _rulesFuture;

  static const _fieldOptions = <String>[
    'cash_on_cash',
    'cap_rate',
    'irr',
    'monthly_cashflow',
    'dscr',
    'noi',
    'purchase_price',
    'rehab_budget',
    'total_cash_invested',
  ];

  @override
  void initState() {
    super.initState();
    _rulesFuture = _loadRules();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.set.name)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => _showRuleDialog(),
                  child: const Text('Add Rule'),
                ),
                const SizedBox(width: AppSpacing.component),
                OutlinedButton(
                  onPressed: _refresh,
                  child: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            Expanded(
              child: FutureBuilder<List<CriteriaRule>>(
                future: _rulesFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    }
                    return const Center(child: CircularProgressIndicator());
                  }

                  final rules = snapshot.data!;
                  if (rules.isEmpty) {
                    return const Center(
                      child: Text('No rules yet. Add your first rule.'),
                    );
                  }

                  return ListView.builder(
                    itemCount: rules.length,
                    itemBuilder: (context, index) {
                      final rule = rules[index];
                      return Card(
                        child: ListTile(
                          leading: StatusBadge(
                            label: rule.severity.toUpperCase(),
                            color:
                                rule.severity == 'hard'
                                    ? AppColors.negative
                                    : AppColors.warning,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${rule.fieldKey} ${rule.operator} ${rule.targetValue}',
                                ),
                              ),
                              InfoTooltip(metricKey: rule.fieldKey, size: 14),
                            ],
                          ),
                          subtitle: Text(
                            'Unit: ${rule.unit} | Enabled: ${rule.enabled ? 'yes' : 'no'}',
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed:
                                    () => _showRuleDialog(existing: rule),
                                child: const Text('Edit'),
                              ),
                              TextButton(
                                onPressed: () => _confirmDeleteRule(rule),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<CriteriaRule>> _loadRules() {
    return ref
        .read(criteriaSetsControllerProvider.notifier)
        .listRules(widget.set.id);
  }

  Future<void> _refresh() async {
    setState(() {
      _rulesFuture = _loadRules();
    });
  }

  Future<void> _showRuleDialog({CriteriaRule? existing}) async {
    final isEdit = existing != null;
    var fieldKey = existing?.fieldKey ?? _fieldOptions.first;
    var op = existing?.operator ?? 'gte';
    var severity = existing?.severity ?? 'hard';
    var enabled = existing?.enabled ?? true;
    final targetController = TextEditingController(
      text: existing?.targetValue.toString() ?? '',
    );
    final unitController = TextEditingController(
      text: existing?.unit ?? 'percent',
    );
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit Rule' : 'Add Rule'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: fieldKey,
                      items:
                          _fieldOptions
                              .map(
                                (field) => DropdownMenuItem(
                                  value: field,
                                  child: Text(field),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          fieldKey = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Metric key',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InfoTooltip(metricKey: fieldKey, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _metricHelpText(fieldKey),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: op,
                      items: const [
                        DropdownMenuItem(value: 'gte', child: Text('gte')),
                        DropdownMenuItem(value: 'lte', child: Text('lte')),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          op = value;
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Operator'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: targetController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Threshold',
                        errorText: errorText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: unitController,
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: severity,
                      items: const [
                        DropdownMenuItem(value: 'hard', child: Text('hard')),
                        DropdownMenuItem(value: 'soft', child: Text('soft')),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          severity = value;
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Severity'),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: enabled,
                      onChanged: (value) {
                        setDialogState(() {
                          enabled = value ?? true;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enabled'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final target = double.tryParse(
                      targetController.text.trim(),
                    );
                    if (target == null) {
                      setDialogState(() {
                        errorText = 'Threshold must be numeric.';
                      });
                      return;
                    }
                    final unit = unitController.text.trim();
                    if (unit.isEmpty) {
                      setDialogState(() {
                        errorText = 'Unit is required.';
                      });
                      return;
                    }

                    final controller = ref.read(
                      criteriaSetsControllerProvider.notifier,
                    );
                    if (isEdit) {
                      await controller.updateRule(
                        CriteriaRule(
                          id: existing.id,
                          criteriaSetId: existing.criteriaSetId,
                          fieldKey: fieldKey,
                          operator: op,
                          targetValue: target,
                          unit: unit,
                          severity: severity,
                          enabled: enabled,
                        ),
                      );
                    } else {
                      await controller.addRule(
                        criteriaSetId: widget.set.id,
                        fieldKey: fieldKey,
                        operator: op,
                        targetValue: target,
                        unit: unit,
                        severity: severity,
                        enabled: enabled,
                      );
                    }

                    if (mounted && context.mounted) {
                      Navigator.of(context).pop();
                    }
                    await _refresh();
                  },
                  child: Text(isEdit ? 'Save' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );

    targetController.dispose();
    unitController.dispose();
  }

  Future<void> _confirmDeleteRule(CriteriaRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Rule'),
            content: Text('Delete rule "${rule.fieldKey} ${rule.operator}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed != true) {
      return;
    }

    await ref.read(criteriaSetsControllerProvider.notifier).deleteRule(rule.id);
    await _refresh();
  }

  String _metricHelpText(String metricKey) {
    final definition =
        MetricDefinitions.byKey(metricKey) ??
        MetricDefinitions.fallback(metricKey);
    return definition.description;
  }
}
