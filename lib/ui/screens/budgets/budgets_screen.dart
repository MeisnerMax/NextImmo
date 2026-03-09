import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/budget.dart';
import '../../../core/models/ledger.dart';
import '../../components/responsive_constraints.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  String _entityType = 'asset_property';
  String _entityId = '';
  List<BudgetRecord> _budgets = const [];
  BudgetRecord? _selected;
  List<BudgetLineRecord> _lines = const [];
  List<BudgetVarianceRecord> _variance = const [];
  List<LedgerAccountRecord> _accounts = const [];
  String _fromPeriod = '';
  String _toPeriod = '';
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: ResponsiveConstraints.itemWidth(
                  context,
                  idealWidth: 190,
                ),
                child: DropdownButtonFormField<String>(
                  value: _entityType,
                  items: const [
                    DropdownMenuItem(
                      value: 'asset_property',
                      child: Text('asset_property'),
                    ),
                    DropdownMenuItem(
                      value: 'property',
                      child: Text('property'),
                    ),
                    DropdownMenuItem(
                      value: 'portfolio',
                      child: Text('portfolio'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _entityType = value);
                    _reload();
                  },
                  decoration: const InputDecoration(labelText: 'Entity Type'),
                ),
              ),
              SizedBox(
                width: ResponsiveConstraints.itemWidth(
                  context,
                  idealWidth: 220,
                ),
                child: TextFormField(
                  initialValue: _entityId,
                  decoration: const InputDecoration(labelText: 'Entity ID'),
                  onChanged: (value) => _entityId = value.trim(),
                  onFieldSubmitted: (_) => _reload(),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _createBudgetDialog,
                icon: const Icon(Icons.add),
                label: const Text('New Budget'),
              ),
              OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
            ],
          ),
          if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 1120;
                final listPane = Card(
                  child:
                      _budgets.isEmpty
                          ? const Center(
                            child: Text('No budgets for current entity.'),
                          )
                          : ListView.builder(
                            itemCount: _budgets.length,
                            itemBuilder: (context, index) {
                              final budget = _budgets[index];
                              final selected = _selected?.id == budget.id;
                              return ListTile(
                                selected: selected,
                                title: Text(
                                  '${budget.fiscalYear} - ${budget.versionName}',
                                ),
                                subtitle: Text('Status: ${budget.status}'),
                                onTap: () => _loadBudget(budget),
                                trailing: Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed:
                                          () => _renameBudgetDialog(budget),
                                      child: const Text('Rename'),
                                    ),
                                    TextButton(
                                      onPressed: () => _setStatusDialog(budget),
                                      child: const Text('Status'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                );

                final detailPane = Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child:
                        _selected == null
                            ? const Center(child: Text('Select a budget'))
                            : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Lines - ${_selected!.versionName}',
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                    ),
                                    const Spacer(),
                                    OutlinedButton(
                                      onPressed: _addLineDialog,
                                      child: const Text('Add / Update Line'),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: _computeVariance,
                                      child: const Text('Compute Variance'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    SizedBox(
                                      width: ResponsiveConstraints.itemWidth(
                                        context,
                                        idealWidth: 140,
                                      ),
                                      child: TextFormField(
                                        initialValue: _fromPeriod,
                                        decoration: const InputDecoration(
                                          labelText: 'From (YYYY-MM)',
                                        ),
                                        onChanged:
                                            (value) =>
                                                _fromPeriod = value.trim(),
                                      ),
                                    ),
                                    SizedBox(
                                      width: ResponsiveConstraints.itemWidth(
                                        context,
                                        idealWidth: 140,
                                      ),
                                      child: TextFormField(
                                        initialValue: _toPeriod,
                                        decoration: const InputDecoration(
                                          labelText: 'To (YYYY-MM)',
                                        ),
                                        onChanged:
                                            (value) => _toPeriod = value.trim(),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: ListView(
                                    children: [
                                      if (_lines.isNotEmpty)
                                        _tableFromLines(_lines),
                                      const SizedBox(height: 12),
                                      if (_variance.isNotEmpty)
                                        _tableFromVariance(_variance),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                  ),
                );

                if (stacked) {
                  return Column(
                    children: [
                      Expanded(child: listPane),
                      const SizedBox(height: AppSpacing.component),
                      Expanded(child: detailPane),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: listPane),
                    const SizedBox(width: AppSpacing.component),
                    Expanded(flex: 2, child: detailPane),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableFromLines(List<BudgetLineRecord> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Account')),
          DataColumn(label: Text('Period')),
          DataColumn(label: Text('Dir')),
          DataColumn(label: Text('Amount')),
        ],
        rows:
            rows
                .map(
                  (line) => DataRow(
                    cells: [
                      DataCell(
                        Text(
                          _accounts
                                  .where((a) => a.id == line.accountId)
                                  .map((a) => a.name)
                                  .firstOrNull ??
                              line.accountId,
                        ),
                      ),
                      DataCell(Text(line.periodKey)),
                      DataCell(Text(line.direction)),
                      DataCell(Text(line.amount.toStringAsFixed(2))),
                    ],
                  ),
                )
                .toList(),
      ),
    );
  }

  Widget _tableFromVariance(List<BudgetVarianceRecord> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Account')),
          DataColumn(label: Text('Period')),
          DataColumn(label: Text('Budget')),
          DataColumn(label: Text('Actual')),
          DataColumn(label: Text('Variance')),
          DataColumn(label: Text('Var %')),
        ],
        rows:
            rows
                .map(
                  (line) => DataRow(
                    cells: [
                      DataCell(
                        Text(
                          _accounts
                                  .where((a) => a.id == line.accountId)
                                  .map((a) => a.name)
                                  .firstOrNull ??
                              line.accountId,
                        ),
                      ),
                      DataCell(Text(line.periodKey)),
                      DataCell(Text(line.budgetAmount.toStringAsFixed(2))),
                      DataCell(Text(line.actualAmount.toStringAsFixed(2))),
                      DataCell(Text(line.varianceAmount.toStringAsFixed(2))),
                      DataCell(
                        Text(
                          line.variancePercent == null
                              ? '-'
                              : '${(line.variancePercent! * 100).toStringAsFixed(1)}%',
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
      ),
    );
  }

  Future<void> _reload() async {
    if (!mounted) {
      return;
    }
    final budgetRepo = ref.read(budgetRepositoryProvider);
    final ledgerRepo = ref.read(ledgerRepositoryProvider);
    final budgets =
        _entityId.isEmpty
            ? const <BudgetRecord>[]
            : await budgetRepo.listBudgets(
              entityType: _entityType,
              entityId: _entityId,
            );
    if (!mounted) {
      return;
    }
    final accounts = await ledgerRepo.listAccounts();

    if (!mounted) {
      return;
    }
    setState(() {
      _budgets = budgets;
      _accounts = accounts;
      if (_selected != null) {
        _selected =
            budgets.where((item) => item.id == _selected!.id).firstOrNull;
      }
    });
    if (_selected != null) {
      await _loadBudget(_selected!);
    }
  }

  Future<void> _loadBudget(BudgetRecord budget) async {
    final detail = await ref
        .read(budgetRepositoryProvider)
        .getBudgetDetail(budget.id);
    if (!mounted || detail == null) {
      return;
    }
    setState(() {
      _selected = budget;
      _lines = detail.lines;
      _variance = const [];
    });
  }

  Future<void> _createBudgetDialog() async {
    final yearCtrl = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    final versionCtrl = TextEditingController(text: 'Base');
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Create Budget'),
            content: SizedBox(
              width: ResponsiveConstraints.dialogWidth(context, maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: yearCtrl,
                    decoration: const InputDecoration(labelText: 'Fiscal Year'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: versionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Version Name',
                    ),
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
                  if (_entityId.isEmpty) {
                    setState(() => _status = 'Entity ID required.');
                    return;
                  }
                  final fiscalYear =
                      int.tryParse(yearCtrl.text.trim()) ?? DateTime.now().year;
                  await ref
                      .read(budgetRepositoryProvider)
                      .createBudget(
                        entityType: _entityType,
                        entityId: _entityId,
                        fiscalYear: fiscalYear,
                        versionName:
                            versionCtrl.text.trim().isEmpty
                                ? 'Base'
                                : versionCtrl.text.trim(),
                      );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  await _reload();
                },
                child: const Text('Create'),
              ),
            ],
          ),
    );
    yearCtrl.dispose();
    versionCtrl.dispose();
  }

  Future<void> _renameBudgetDialog(BudgetRecord budget) async {
    final ctrl = TextEditingController(text: budget.versionName);
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Rename Budget'),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Version Name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await ref
                      .read(budgetRepositoryProvider)
                      .renameBudget(
                        budgetId: budget.id,
                        versionName: ctrl.text.trim(),
                      );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  await _reload();
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
    ctrl.dispose();
  }

  Future<void> _setStatusDialog(BudgetRecord budget) async {
    var status = budget.status;
    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Set Budget Status'),
                  content: DropdownButtonFormField<String>(
                    value: status,
                    items: const [
                      DropdownMenuItem(value: 'draft', child: Text('draft')),
                      DropdownMenuItem(
                        value: 'approved',
                        child: Text('approved'),
                      ),
                      DropdownMenuItem(
                        value: 'archived',
                        child: Text('archived'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() => status = value);
                    },
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await ref
                            .read(budgetRepositoryProvider)
                            .setStatus(budgetId: budget.id, status: status);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                        await _reload();
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _addLineDialog() async {
    final selected = _selected;
    if (selected == null || _accounts.isEmpty) {
      setState(
        () =>
            _status =
                'Select a budget and ensure at least one ledger account exists.',
      );
      return;
    }

    var accountId = _accounts.first.id;
    var direction = 'out';
    final periodCtrl = TextEditingController(
      text: _fromPeriod.isEmpty ? '${selected.fiscalYear}-01' : _fromPeriod,
    );
    final amountCtrl = TextEditingController(text: '0');
    final notesCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Add / Update Budget Line'),
                  content: SizedBox(
                    width: ResponsiveConstraints.dialogWidth(
                      context,
                      maxWidth: 460,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          value: accountId,
                          items:
                              _accounts
                                  .map(
                                    (account) => DropdownMenuItem(
                                      value: account.id,
                                      child: Text(account.name),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() => accountId = value);
                          },
                          decoration: const InputDecoration(
                            labelText: 'Account',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: periodCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Period (YYYY-MM)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: direction,
                          items: const [
                            DropdownMenuItem(value: 'in', child: Text('in')),
                            DropdownMenuItem(value: 'out', child: Text('out')),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() => direction = value);
                          },
                          decoration: const InputDecoration(
                            labelText: 'Direction',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: amountCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(labelText: 'Notes'),
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
                        final amount = double.tryParse(amountCtrl.text.trim());
                        if (amount == null) {
                          return;
                        }
                        await ref
                            .read(budgetRepositoryProvider)
                            .upsertBudgetLine(
                              budgetId: selected.id,
                              accountId: accountId,
                              periodKey: periodCtrl.text.trim(),
                              direction: direction,
                              amount: amount,
                              notes:
                                  notesCtrl.text.trim().isEmpty
                                      ? null
                                      : notesCtrl.text.trim(),
                            );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                        await _loadBudget(selected);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );

    periodCtrl.dispose();
    amountCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _computeVariance() async {
    final selected = _selected;
    if (selected == null) {
      return;
    }
    final variance = await ref
        .read(budgetRepositoryProvider)
        .computeBudgetVsActual(
          entityType: _entityType,
          entityId: _entityId,
          budgetId: selected.id,
          fromPeriod: _fromPeriod.isEmpty ? null : _fromPeriod,
          toPeriod: _toPeriod.isEmpty ? null : _toPeriod,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _variance = variance;
    });
  }
}
