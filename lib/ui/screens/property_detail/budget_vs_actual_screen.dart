import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/budget.dart';
import '../../../core/models/ledger.dart';
import '../../components/responsive_constraints.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class BudgetVsActualScreen extends ConsumerStatefulWidget {
  const BudgetVsActualScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<BudgetVsActualScreen> createState() =>
      _BudgetVsActualScreenState();
}

class _BudgetVsActualScreenState extends ConsumerState<BudgetVsActualScreen> {
  List<BudgetRecord> _budgets = const [];
  BudgetRecord? _selected;
  List<BudgetVarianceRecord> _variance = const [];
  List<LedgerAccountRecord> _accounts = const [];
  String _fromPeriod = '';
  String _toPeriod = '';

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
              ElevatedButton.icon(
                onPressed: _createBudgetDialog,
                icon: const Icon(Icons.add),
                label: const Text('Create Budget'),
              ),
              OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
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
                  onChanged: (value) => _fromPeriod = value.trim(),
                ),
              ),
              SizedBox(
                width: ResponsiveConstraints.itemWidth(
                  context,
                  idealWidth: 140,
                ),
                child: TextFormField(
                  initialValue: _toPeriod,
                  decoration: const InputDecoration(labelText: 'To (YYYY-MM)'),
                  onChanged: (value) => _toPeriod = value.trim(),
                ),
              ),
              OutlinedButton(onPressed: _compute, child: const Text('Compute')),
              OutlinedButton(
                onPressed: _addLineDialog,
                child: const Text('Add Budget Line'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 1080;
                final listPane = Card(
                  child:
                      _budgets.isEmpty
                          ? const Center(child: Text('No budgets yet.'))
                          : ListView.builder(
                            itemCount: _budgets.length,
                            itemBuilder: (context, index) {
                              final budget = _budgets[index];
                              return ListTile(
                                selected: _selected?.id == budget.id,
                                title: Text(
                                  '${budget.fiscalYear} - ${budget.versionName}',
                                ),
                                subtitle: Text(budget.status),
                                onTap: () => setState(() => _selected = budget),
                              );
                            },
                          ),
                );
                final detailPane = Card(
                  child:
                      _selected == null
                          ? const Center(child: Text('Select a budget'))
                          : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Account')),
                                DataColumn(label: Text('Period')),
                                DataColumn(label: Text('Budget')),
                                DataColumn(label: Text('Actual')),
                                DataColumn(label: Text('Variance')),
                              ],
                              rows:
                                  _variance
                                      .map(
                                        (row) => DataRow(
                                          cells: [
                                            DataCell(
                                              Text(_accountName(row.accountId)),
                                            ),
                                            DataCell(Text(row.periodKey)),
                                            DataCell(
                                              Text(
                                                row.budgetAmount
                                                    .toStringAsFixed(2),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                row.actualAmount
                                                    .toStringAsFixed(2),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                row.varianceAmount
                                                    .toStringAsFixed(2),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                      .toList(),
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

  String _accountName(String accountId) {
    for (final account in _accounts) {
      if (account.id == accountId) {
        return account.name;
      }
    }
    return accountId;
  }

  Future<void> _reload() async {
    if (!mounted) {
      return;
    }
    final budgetRepo = ref.read(budgetRepositoryProvider);
    final ledgerRepo = ref.read(ledgerRepositoryProvider);
    final budgets = await budgetRepo.listBudgets(
      entityType: 'asset_property',
      entityId: widget.propertyId,
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
        for (final budget in budgets) {
          if (budget.id == _selected!.id) {
            _selected = budget;
            break;
          }
        }
      }
    });
  }

  Future<void> _createBudgetDialog() async {
    final yearCtrl = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    final nameCtrl = TextEditingController(text: 'Base');
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Create Budget'),
            content: SizedBox(
              width: ResponsiveConstraints.dialogWidth(context, maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: yearCtrl,
                    decoration: const InputDecoration(labelText: 'Fiscal Year'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
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
                  await ref
                      .read(budgetRepositoryProvider)
                      .createBudget(
                        entityType: 'asset_property',
                        entityId: widget.propertyId,
                        fiscalYear:
                            int.tryParse(yearCtrl.text.trim()) ??
                            DateTime.now().year,
                        versionName:
                            nameCtrl.text.trim().isEmpty
                                ? 'Base'
                                : nameCtrl.text.trim(),
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
    nameCtrl.dispose();
  }

  Future<void> _addLineDialog() async {
    final selected = _selected;
    if (selected == null || _accounts.isEmpty) {
      return;
    }

    var accountId = _accounts.first.id;
    var direction = 'out';
    final periodCtrl = TextEditingController(
      text: _fromPeriod.isEmpty ? '${selected.fiscalYear}-01' : _fromPeriod,
    );
    final amountCtrl = TextEditingController(text: '0');

    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Add Budget Line'),
                  content: SizedBox(
                    width: ResponsiveConstraints.dialogWidth(
                      context,
                      maxWidth: 380,
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
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: amountCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
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
                            );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                        await _compute();
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );

    periodCtrl.dispose();
    amountCtrl.dispose();
  }

  Future<void> _compute() async {
    final selected = _selected;
    if (selected == null) {
      return;
    }
    final values = await ref
        .read(budgetRepositoryProvider)
        .computeBudgetVsActual(
          entityType: 'asset_property',
          entityId: widget.propertyId,
          budgetId: selected.id,
          fromPeriod: _fromPeriod.isEmpty ? null : _fromPeriod,
          toPeriod: _toPeriod.isEmpty ? null : _toPeriod,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _variance = values;
    });
  }
}
