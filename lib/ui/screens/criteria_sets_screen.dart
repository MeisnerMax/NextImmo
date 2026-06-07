import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/criteria.dart';
import '../components/nx_card.dart';
import '../components/nx_empty_state.dart';
import '../components/nx_status_badge.dart';
import '../docs/metric_definitions.dart';
import '../state/criteria_state.dart';
import '../templates/list_filter_template.dart';
import '../theme/app_theme.dart';
import '../widgets/info_tooltip.dart';

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

    return setsAsync.when(
      data: (sets) {
        final defaultCount = sets.where((set) => set.isDefault).length;
        return ListFilterTemplate(
          title: 'Kriterien',
          breadcrumbs: const ['Analyse', 'Kriterien'],
          subtitle:
              'Grenzwerte fuer Bewertungen zentral pflegen und als Standard fuer neue Auswertungen nutzen.',
          primaryAction: ElevatedButton.icon(
            onPressed: () => _showCreateSetDialog(controller),
            icon: const Icon(Icons.add),
            label: const Text('Kriterienset anlegen'),
          ),
          secondaryActions: [
            OutlinedButton.icon(
              onPressed: controller.reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Aktualisieren'),
            ),
          ],
          contextBar: ListFilterBar(
            children: [
              _OverviewPill(label: 'Sets', value: '${sets.length}'),
              _OverviewPill(label: 'Standard', value: '$defaultCount'),
              _OverviewPill(
                label: 'Optional',
                value: '${sets.length - defaultCount}',
              ),
            ],
          ),
          content:
              sets.isEmpty
                  ? NxEmptyState(
                    title: 'Noch keine Kriterien hinterlegt',
                    description:
                        'Lege ein Set an, um Rendite-, Cashflow- und Risiko-Grenzwerte zu pruefen.',
                    icon: Icons.rule_folder_outlined,
                    primaryAction: ElevatedButton.icon(
                      onPressed: () => _showCreateSetDialog(controller),
                      icon: const Icon(Icons.add),
                      label: const Text('Erstes Set anlegen'),
                    ),
                  )
                  : ListView.separated(
                    itemCount: sets.length,
                    separatorBuilder:
                        (_, __) =>
                            const SizedBox(height: AppSpacing.component),
                    itemBuilder: (context, index) {
                      final set = sets[index];
                      return _CriteriaSetTile(
                        set: set,
                        onOpen: () => _openEditor(set),
                        onRename: () => _showRenameSetDialog(set),
                        onSetDefault:
                            set.isDefault
                                ? null
                                : () => controller.setDefault(set.id),
                        onDelete:
                            set.isDefault
                                ? null
                                : () => _confirmDeleteSet(set),
                      );
                    },
                  ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (error, _) => ListFilterTemplate(
            title: 'Kriterien',
            breadcrumbs: const ['Analyse', 'Kriterien'],
            content: NxEmptyState(
              title: 'Kriterien konnten nicht geladen werden',
              description: '$error',
              icon: Icons.error_outline,
            ),
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
              title: const Text('Kriterienset anlegen'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: 'z. B. Standard Ankauf',
                        errorText: errorText,
                        prefixIcon: const Icon(Icons.drive_file_rename_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: makeDefault,
                      onChanged:
                          (value) =>
                              setDialogState(() => makeDefault = value),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Als Standard verwenden'),
                      subtitle: const Text(
                        'Neue Auswertungen koennen dieses Set direkt nutzen.',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = 'Bitte einen Namen eingeben.';
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
                  child: const Text('Anlegen'),
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
              title: const Text('Kriterienset umbenennen'),
              content: TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: errorText,
                  prefixIcon: const Icon(Icons.drive_file_rename_outline),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = 'Bitte einen Namen eingeben.';
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
                  child: const Text('Speichern'),
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
            title: const Text('Kriterienset loeschen'),
            content: Text(
              '"${set.name}" wirklich loeschen? Die zugehoerigen Regeln werden ebenfalls entfernt.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.semanticColors.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Loeschen'),
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

  static const _unitOptions = <String>['percent', 'currency', 'ratio', 'amount'];

  @override
  void initState() {
    super.initState();
    _rulesFuture = _loadRules();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(widget.set.name)),
      body: FutureBuilder<List<CriteriaRule>>(
        future: _rulesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return ListFilterTemplate(
                title: 'Regeln',
                breadcrumbs: const ['Analyse', 'Kriterien', 'Regeln'],
                content: NxEmptyState(
                  title: 'Regeln konnten nicht geladen werden',
                  description: '${snapshot.error}',
                  icon: Icons.error_outline,
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          final rules = snapshot.data!;
          final activeCount = rules.where((rule) => rule.enabled).length;
          final hardCount =
              rules.where((rule) => rule.severity == 'hard').length;
          return ListFilterTemplate(
            title: widget.set.name,
            breadcrumbs: const ['Analyse', 'Kriterien', 'Regeln'],
            subtitle:
                'Aktive Regeln pruefen Kennzahlen automatisch gegen definierte Zielwerte.',
            primaryAction: ElevatedButton.icon(
              onPressed: () => _showRuleDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Regel anlegen'),
            ),
            secondaryActions: [
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Aktualisieren'),
              ),
            ],
            contextBar: ListFilterBar(
              children: [
                _OverviewPill(label: 'Regeln', value: '${rules.length}'),
                _OverviewPill(label: 'Aktiv', value: '$activeCount'),
                _OverviewPill(label: 'Harte Grenzen', value: '$hardCount'),
              ],
            ),
            content:
                rules.isEmpty
                    ? NxEmptyState(
                      title: 'Noch keine Regeln hinterlegt',
                      description:
                          'Lege Grenzwerte an, damit Szenarien automatisch bewertet werden.',
                      icon: Icons.rule_outlined,
                      primaryAction: ElevatedButton.icon(
                        onPressed: () => _showRuleDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Erste Regel anlegen'),
                      ),
                    )
                    : ListView.separated(
                      itemCount: rules.length,
                      separatorBuilder:
                          (_, __) =>
                              const SizedBox(height: AppSpacing.component),
                      itemBuilder: (context, index) {
                        final rule = rules[index];
                        return _CriteriaRuleTile(
                          rule: rule,
                          metricLabel: _metricLabel(rule.fieldKey),
                          operatorLabel: _operatorLabel(rule.operator),
                          unitLabel: _unitLabel(rule.unit),
                          onEdit: () => _showRuleDialog(existing: rule),
                          onDelete: () => _confirmDeleteRule(rule),
                        );
                      },
                    ),
          );
        },
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
    var unit = _normalizeUnit(existing?.unit ?? _defaultUnitFor(fieldKey));
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'Regel bearbeiten' : 'Regel anlegen'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
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
                                    child: Text(_metricLabel(field)),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            fieldKey = value;
                            unit = _normalizeUnit(_defaultUnitFor(value));
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Kennzahl',
                          prefixIcon: Icon(Icons.analytics_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _MetricHelpBox(
                        fieldKey: fieldKey,
                        text: _metricHelpText(fieldKey),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: op,
                              items: const [
                                DropdownMenuItem(
                                  value: 'gte',
                                  child: Text('Mindestens'),
                                ),
                                DropdownMenuItem(
                                  value: 'lte',
                                  child: Text('Hoechstens'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setDialogState(() {
                                  op = value;
                                });
                              },
                              decoration: const InputDecoration(
                                labelText: 'Vergleich',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: targetController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Zielwert',
                                errorText: errorText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: unit,
                              items:
                                  _unitOptions
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(_unitLabel(value)),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setDialogState(() {
                                  unit = value;
                                });
                              },
                              decoration: const InputDecoration(
                                labelText: 'Einheit',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: severity,
                              items: const [
                                DropdownMenuItem(
                                  value: 'hard',
                                  child: Text('Harte Grenze'),
                                ),
                                DropdownMenuItem(
                                  value: 'soft',
                                  child: Text('Hinweis'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setDialogState(() {
                                  severity = value;
                                });
                              },
                              decoration: const InputDecoration(
                                labelText: 'Schweregrad',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: enabled,
                        onChanged:
                            (value) =>
                                setDialogState(() => enabled = value),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Regel aktiv'),
                        subtitle: const Text(
                          'Inaktive Regeln bleiben gespeichert, werden aber nicht bewertet.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final target = double.tryParse(
                      targetController.text.trim().replaceAll(',', '.'),
                    );
                    if (target == null) {
                      setDialogState(() {
                        errorText = 'Bitte einen gueltigen Zahlenwert eingeben.';
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
                  child: Text(isEdit ? 'Speichern' : 'Anlegen'),
                ),
              ],
            );
          },
        );
      },
    );

    targetController.dispose();
  }

  Future<void> _confirmDeleteRule(CriteriaRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Regel loeschen'),
            content: Text(
              '"${_metricLabel(rule.fieldKey)} ${_operatorLabel(rule.operator)}" wirklich loeschen?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.semanticColors.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Loeschen'),
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
        MetricDefinitions.byKey(context, metricKey) ??
        MetricDefinitions.fallback(context, metricKey);
    return definition.description;
  }
}

class _CriteriaSetTile extends StatelessWidget {
  const _CriteriaSetTile({
    required this.set,
    required this.onOpen,
    required this.onRename,
    required this.onSetDefault,
    required this.onDelete,
  });

  final CriteriaSet set;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback? onSetDefault;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      variant: NxCardVariant.interactive,
      onTap: onOpen,
      child: Wrap(
        spacing: AppSpacing.component,
        runSpacing: AppSpacing.component,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(set.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  set.isDefault
                      ? 'Wird als Standard fuer neue Pruefungen genutzt.'
                      : 'Kann fuer einzelne Bewertungen ausgewaehlt werden.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          NxStatusBadge(
            label: set.isDefault ? 'Standard' : 'Optional',
            kind: set.isDefault ? NxBadgeKind.success : NxBadgeKind.neutral,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.edit_note),
                label: const Text('Regeln'),
              ),
              OutlinedButton.icon(
                onPressed: onRename,
                icon: const Icon(Icons.drive_file_rename_outline),
                label: const Text('Umbenennen'),
              ),
              OutlinedButton.icon(
                onPressed: onSetDefault,
                icon: const Icon(Icons.star_border),
                label: const Text('Standard'),
              ),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Loeschen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CriteriaRuleTile extends StatelessWidget {
  const _CriteriaRuleTile({
    required this.rule,
    required this.metricLabel,
    required this.operatorLabel,
    required this.unitLabel,
    required this.onEdit,
    required this.onDelete,
  });

  final CriteriaRule rule;
  final String metricLabel;
  final String operatorLabel;
  final String unitLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final badgeKind =
        rule.severity == 'hard' ? NxBadgeKind.error : NxBadgeKind.warning;
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 260,
                  maxWidth: 560,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.titleMedium,
                          children: [
                            TextSpan(text: '$metricLabel $operatorLabel '),
                            TextSpan(
                              text: '${rule.targetValue}',
                              style: context.tabularNumericStyle.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InfoTooltip(metricKey: rule.fieldKey, size: 14),
                  ],
                ),
              ),
              NxStatusBadge(
                label: rule.severity == 'hard' ? 'Harte Grenze' : 'Hinweis',
                kind: badgeKind,
              ),
              NxStatusBadge(
                label: rule.enabled ? 'Aktiv' : 'Inaktiv',
                kind: rule.enabled ? NxBadgeKind.success : NxBadgeKind.neutral,
              ),
              NxStatusBadge(label: unitLabel, kind: NxBadgeKind.info),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Bearbeiten'),
              ),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Loeschen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewPill extends StatelessWidget {
  const _OverviewPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.merge(context.tabularNumericStyle),
      ),
    );
  }
}

class _MetricHelpBox extends StatelessWidget {
  const _MetricHelpBox({required this.fieldKey, required this.text});

  final String fieldKey;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoTooltip(metricKey: fieldKey, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

String _metricLabel(String key) {
  switch (key) {
    case 'cash_on_cash':
      return 'Cash-on-Cash Rendite';
    case 'cap_rate':
      return 'Kapitalisierungsrate';
    case 'irr':
      return 'IRR';
    case 'monthly_cashflow':
      return 'Monatlicher Cashflow';
    case 'dscr':
      return 'DSCR';
    case 'noi':
      return 'NOI';
    case 'purchase_price':
      return 'Kaufpreis';
    case 'rehab_budget':
      return 'Sanierungsbudget';
    case 'total_cash_invested':
      return 'Eigenkapitalbindung';
    default:
      return key;
  }
}

String _operatorLabel(String op) {
  switch (op) {
    case 'gte':
      return 'mindestens';
    case 'lte':
      return 'hoechstens';
    default:
      return op;
  }
}

String _unitLabel(String unit) {
  switch (unit) {
    case 'percent':
      return 'Prozent';
    case 'currency':
      return 'Waehrung';
    case 'ratio':
      return 'Faktor';
    case 'amount':
      return 'Betrag';
    default:
      return unit;
  }
}

String _defaultUnitFor(String fieldKey) {
  switch (fieldKey) {
    case 'cash_on_cash':
    case 'cap_rate':
    case 'irr':
      return 'percent';
    case 'dscr':
      return 'ratio';
    case 'purchase_price':
    case 'rehab_budget':
    case 'total_cash_invested':
    case 'monthly_cashflow':
    case 'noi':
      return 'currency';
    default:
      return 'amount';
  }
}

String _normalizeUnit(String unit) {
  return _CriteriaSetEditorScreenState._unitOptions.contains(unit)
      ? unit
      : 'amount';
}
