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
  List<BudgetLineRecord> _lines = const [];
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
          if (_selected != null) ...[
            _VarianceSummary(rows: _variance),
            const SizedBox(height: AppSpacing.component),
            _ObjectBudgetDashboard(
              lines: _lines,
              rows: _variance,
              accountName: _accountName,
            ),
            const SizedBox(height: AppSpacing.component),
          ],
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
                                onTap: () {
                                  setState(() {
                                    _selected = budget;
                                    _lines = const [];
                                    _variance = const [];
                                  });
                                  _compute();
                                },
                              );
                            },
                          ),
                );
                final detailPane = Card(
                  child:
                      _selected == null
                          ? const Center(child: Text('Select a budget'))
                          : _variance.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(
                                  AppSpacing.cardPadding,
                                ),
                                child: Text(
                                  'No budget or actual lines found for the selected period.',
                                ),
                              ),
                            )
                          : ClipRect(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Account')),
                                DataColumn(label: Text('Period')),
                                DataColumn(label: Text('Budget')),
                                DataColumn(label: Text('Actual')),
                                DataColumn(label: Text('Variance')),
                                DataColumn(label: Text('Variance %')),
                                DataColumn(label: Text('Status')),
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
                                            DataCell(
                                              Text(
                                                row.variancePercent == null
                                                    ? '-'
                                                    : '${(row.variancePercent! * 100).toStringAsFixed(1)}%',
                                              ),
                                            ),
                                            DataCell(
                                              _VarianceStatusChip(row: row),
                                            ),
                                          ],
                                        ),
                                      )
                                      .toList(),
                              ),
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
      _selected ??= budgets.isEmpty ? null : budgets.first;
    });
    await _compute();
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
    final budgetRepo = ref.read(budgetRepositoryProvider);
    final detail = await budgetRepo.getBudgetDetail(selected.id);
    final values = await budgetRepo.computeBudgetVsActual(
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
      _lines = detail?.lines ?? const [];
      _variance = values;
    });
  }
}

class _ObjectBudgetDashboard extends StatelessWidget {
  const _ObjectBudgetDashboard({
    required this.lines,
    required this.rows,
    required this.accountName,
  });

  final List<BudgetLineRecord> lines;
  final List<BudgetVarianceRecord> rows;
  final String Function(String accountId) accountName;

  @override
  Widget build(BuildContext context) {
    final planned = lines.fold<double>(
      0,
      (sum, line) => sum + (line.direction == 'in' ? line.amount : -line.amount),
    );
    final actual = rows.fold<double>(0, (sum, row) => sum + row.actualAmount);
    final matchedPlan =
        rows.fold<double>(0, (sum, row) => sum + row.budgetAmount);
    final forecast = rows.isEmpty ? planned : actual + (planned - matchedPlan);
    final variance = rows.fold<double>(
      0,
      (sum, row) => sum + row.varianceAmount,
    );
    final varianceRate = matchedPlan == 0 ? null : variance / matchedPlan;
    final topRows = [...rows]
      ..sort((a, b) => b.varianceAmount.abs().compareTo(a.varianceAmount.abs()));
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 760;
        final panelWidth =
            stacked ? constraints.maxWidth : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ObjectBudgetPanel(
              width: panelWidth,
              title: 'Objekt-Budgetsteuerung',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ObjectBudgetSignal(rate: varianceRate, amount: variance),
                  const SizedBox(height: 8),
                  _ObjectBudgetBars(
                    data: [
                      _ObjectBudgetDatum('Plan', planned),
                      _ObjectBudgetDatum('Ist', actual),
                      _ObjectBudgetDatum('Forecast', forecast),
                    ],
                  ),
                ],
              ),
            ),
            _ObjectBudgetPanel(
              width: panelWidth,
              title: 'Größte Abweichungen',
              child: _ObjectBudgetBars(
                data: topRows
                    .take(4)
                    .map(
                      (row) => _ObjectBudgetDatum(
                        accountName(row.accountId),
                        row.varianceAmount,
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ObjectBudgetPanel extends StatelessWidget {
  const _ObjectBudgetPanel({
    required this.width,
    required this.title,
    required this.child,
  });

  final double width;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ObjectBudgetSignal extends StatelessWidget {
  const _ObjectBudgetSignal({required this.rate, required this.amount});

  final double? rate;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final absRate = rate?.abs() ?? 0;
    final color = rate == null
        ? Theme.of(context).colorScheme.primary
        : absRate <= 0.05
        ? context.semanticColors.success
        : absRate <= 0.15
            ? context.semanticColors.warning
            : Theme.of(context).colorScheme.error;
    final label = rate == null
        ? 'Ist-Abgleich offen'
        : absRate <= 0.05
        ? 'Im Rahmen'
        : absRate <= 0.15
            ? 'Beobachten'
            : 'Eskalieren';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_outlined, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            rate == null
                ? _formatObjectBudgetCurrency(amount)
                : '${(rate! * 100).toStringAsFixed(1)}%',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ObjectBudgetBars extends StatelessWidget {
  const _ObjectBudgetBars({required this.data});

  final List<_ObjectBudgetDatum> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: 96,
        child: Center(
          child: Text('Keine Daten', style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    final maxValue = data.fold<double>(
      0,
      (max, item) => item.value.abs() > max ? item.value.abs() : max,
    );
    final denominator = maxValue == 0 ? 1.0 : maxValue;
    return Column(
      children: [
        for (final item in data) ...[
          Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value:
                        (item.value.abs() / denominator).clamp(0.0, 1.0).toDouble(),
                    minHeight: 9,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    color: item.value < 0
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: Text(
                  _formatObjectBudgetCurrency(item.value),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ObjectBudgetDatum {
  const _ObjectBudgetDatum(this.label, this.value);

  final String label;
  final double value;
}

String _formatObjectBudgetCurrency(double value) {
  final sign = value < 0 ? '-' : '';
  final absolute = value.abs();
  if (absolute >= 1000000) {
    return '$sign${(absolute / 1000000).toStringAsFixed(1)} Mio.';
  }
  if (absolute >= 1000) {
    return '$sign${(absolute / 1000).toStringAsFixed(1)} Tsd.';
  }
  return '$sign${absolute.toStringAsFixed(0)}';
}

class _VarianceSummary extends StatelessWidget {
  const _VarianceSummary({required this.rows});

  final List<BudgetVarianceRecord> rows;

  @override
  Widget build(BuildContext context) {
    final budget = rows.fold<double>(0, (sum, row) => sum + row.budgetAmount);
    final actual = rows.fold<double>(0, (sum, row) => sum + row.actualAmount);
    final variance =
        rows.fold<double>(0, (sum, row) => sum + row.varianceAmount);
    final percent = budget == 0 ? null : variance / budget;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SummaryTile(label: 'Budget', value: budget.toStringAsFixed(0)),
        _SummaryTile(label: 'Actual', value: actual.toStringAsFixed(0)),
        _SummaryTile(label: 'Variance', value: variance.toStringAsFixed(0)),
        _SummaryTile(
          label: 'Variance %',
          value: percent == null
              ? '-'
              : '${(percent * 100).toStringAsFixed(1)}%',
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VarianceStatusChip extends StatelessWidget {
  const _VarianceStatusChip({required this.row});

  final BudgetVarianceRecord row;

  @override
  Widget build(BuildContext context) {
    final percent = row.variancePercent?.abs();
    final isMaterial = percent != null && percent >= 0.1;
    final label =
        isMaterial
            ? (row.varianceAmount > 0 ? 'Over' : 'Under')
            : 'On track';
    final color =
        isMaterial
            ? (row.varianceAmount > 0 ? Colors.orange : Colors.green)
            : Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
