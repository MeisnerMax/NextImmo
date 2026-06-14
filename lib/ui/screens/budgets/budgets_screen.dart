import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/budget.dart';
import '../../../core/models/ledger.dart';
import '../../../core/models/portfolio.dart';
import '../../../core/models/property.dart';
import '../../../core/models/operations.dart';
import '../../../core/models/maintenance.dart';
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
  List<PropertyRecord> _properties = const [];
  List<PortfolioRecord> _portfolios = const [];
  String _fromPeriod = '';
  String _toPeriod = '';
  String? _status;

  bool get _usesEntityDropdown =>
      _entityType == 'asset_property' || _entityType == 'portfolio';

  String get _entityInputLabel {
    switch (_entityType) {
      case 'unit':
        return 'Einheit / Wohnungs-ID';
      case 'maintenance':
        return 'Instandhaltungs- oder Ticket-ID';
      case 'renovation':
        return 'Sanierungs-ID';
      case 'project':
        return 'Projekt-ID';
      default:
        return 'Zuordnung';
    }
  }

  double get _plannedTotal => _lines.fold<double>(
    0,
    (sum, line) => sum + (line.direction == 'in' ? line.amount : -line.amount),
  );

  double get _actualTotal => _variance.fold<double>(
    0,
    (sum, line) => sum + line.actualAmount,
  );

  double get _varianceTotal => _variance.fold<double>(
    0,
    (sum, line) => sum + line.varianceAmount,
  );

  double get _forecastTotal {
    if (_variance.isEmpty) {
      return _plannedTotal;
    }
    final plannedMatched = _variance.fold<double>(
      0,
      (sum, line) => sum + line.budgetAmount,
    );
    final remainingPlan = _plannedTotal - plannedMatched;
    return _actualTotal + remainingPlan;
  }

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
                      child: Text('Objekt'),
                    ),
                    DropdownMenuItem(
                      value: 'unit',
                      child: Text('Einheit'),
                    ),
                    DropdownMenuItem(
                      value: 'maintenance',
                      child: Text('Instandhaltung'),
                    ),
                    DropdownMenuItem(
                      value: 'renovation',
                      child: Text('Sanierung'),
                    ),
                    DropdownMenuItem(
                      value: 'project',
                      child: Text('Projekt'),
                    ),
                    DropdownMenuItem(
                      value: 'portfolio',
                      child: Text('Portfolio'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _entityType = value;
                      _entityId = '';
                      _selected = null;
                      _lines = const [];
                      _variance = const [];
                    });
                    _reload();
                  },
                  decoration: const InputDecoration(labelText: 'Entity Type'),
                ),
              ),
              SizedBox(
                width: ResponsiveConstraints.itemWidth(
                  context,
                  idealWidth: 280,
                ),
                child:
                    _usesEntityDropdown
                        ? DropdownButtonFormField<String>(
                          value: _entityId.isEmpty ? null : _entityId,
                          isExpanded: true,
                          items: _entityItems(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _entityId = value;
                              _selected = null;
                              _lines = const [];
                              _variance = const [];
                            });
                            _reload();
                          },
                          decoration: InputDecoration(
                            labelText:
                                _entityType == 'portfolio'
                                    ? 'Portfolio'
                                    : 'Objekt',
                          ),
                        )
                        : TextFormField(
                          initialValue: _entityId,
                          decoration: InputDecoration(
                            labelText: _entityInputLabel,
                            prefixIcon: const Icon(Icons.tag_outlined),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _entityId = value.trim();
                              _selected = null;
                              _lines = const [];
                              _variance = const [];
                            });
                          },
                        ),
              ),
              ElevatedButton.icon(
                onPressed: _createBudgetDialog,
                icon: const Icon(Icons.add),
                label: const Text('Neues Budget'),
              ),
              OutlinedButton(
                onPressed: _reload,
                child: const Text('Aktualisieren'),
              ),
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
                                subtitle: Text(
                                  '${_selectedEntityLabel()} · Status: ${budget.status}',
                                ),
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
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                  'Budgetplanung - ${_selected!.versionName}',
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                    ),
                                    OutlinedButton(
                                      onPressed: _addLineDialog,
                                      child: const Text('Position erfassen'),
                                    ),
                                    OutlinedButton(
                                      onPressed: _computeVariance,
                                      child: const Text('Ist-Abgleich'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _BudgetManagementSummary(
                                  planned: _plannedTotal,
                                  actual: _actualTotal,
                                  variance: _varianceTotal,
                                  forecast: _forecastTotal,
                                ),
                                const SizedBox(height: 8),
                                _BudgetVisualDashboard(
                                  lines: _lines,
                                  variance: _variance,
                                  accounts: _accounts,
                                  plannedTotal: _plannedTotal,
                                  actualTotal: _actualTotal,
                                  forecastTotal: _forecastTotal,
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
    final properties = await ref.read(propertyRepositoryProvider).list();
    final portfolios = await ref.read(portfolioRepositoryProvider).listPortfolios();
    var entityId = _entityId;
    if (entityId.isEmpty) {
      if (_entityType == 'portfolio' && portfolios.isNotEmpty) {
        entityId = portfolios.first.id;
      } else if (_entityType == 'asset_property' && properties.isNotEmpty) {
        entityId = properties.first.id;
      }
    }
    final budgets =
        entityId.isEmpty
            ? const <BudgetRecord>[]
            : await budgetRepo.listBudgets(
              entityType: _entityType,
              entityId: entityId,
            );
    if (!mounted) {
      return;
    }
    final accounts = await ledgerRepo.listAccounts();

    if (!mounted) {
      return;
    }
    setState(() {
      _properties = properties;
      _portfolios = portfolios;
      _entityId = entityId;
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
    if (_entityId.isEmpty) {
      setState(() => _status = 'Select a property or portfolio first.');
      return;
    }

    final yearCtrl = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    final versionCtrl = TextEditingController(text: 'Base');
    final projectCtrl = TextEditingController();

    List<UnitRecord> dialogUnits = [];
    List<MaintenanceTicketRecord> dialogTickets = [];
    List<MaintenanceTicketRecord> dialogRenovations = [];
    String? selectedUnitId;
    String? selectedTicketId;
    String? selectedRenovationId;
    bool isLoading = true;

    if (_entityType == 'asset_property') {
      try {
        dialogUnits = await ref.read(rentRollRepositoryProvider).listUnitsByAsset(_entityId);
        final tickets = await ref.read(maintenanceRepositoryProvider).listTickets(assetPropertyId: _entityId);
        dialogTickets = tickets.where((t) => t.category != 'renovation').toList();
        dialogRenovations = tickets.where((t) => t.category == 'renovation').toList();
        isLoading = false;
      } catch (_) {
        isLoading = false;
      }
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Create Budget'),
                  content: SizedBox(
                    width: ResponsiveConstraints.dialogWidth(context, maxWidth: 460),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: yearCtrl,
                            decoration: const InputDecoration(labelText: 'Fiscal Year *'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: versionCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Version Name *',
                            ),
                          ),
                          if (_entityType == 'asset_property') ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String?>(
                              value: selectedUnitId,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Keine Einheit (Gesamtobjekt)')),
                                ...dialogUnits.map(
                                  (unit) => DropdownMenuItem(
                                    value: unit.id,
                                    child: Text(unit.unitCode),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setDialogState(() => selectedUnitId = value);
                              },
                              decoration: const InputDecoration(labelText: 'Zugeordnete Einheit'),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String?>(
                              value: selectedTicketId,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Kein Ticket (Gesamtobjekt)')),
                                ...dialogTickets.map(
                                  (ticket) => DropdownMenuItem(
                                    value: ticket.id,
                                    child: Text(ticket.title),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setDialogState(() => selectedTicketId = value);
                              },
                              decoration: const InputDecoration(labelText: 'Zugeordnetes Wartungsticket'),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String?>(
                              value: selectedRenovationId,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Keine Sanierung (Gesamtobjekt)')),
                                ...dialogRenovations.map(
                                  (ticket) => DropdownMenuItem(
                                    value: ticket.id,
                                    child: Text(ticket.title),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setDialogState(() => selectedRenovationId = value);
                              },
                              decoration: const InputDecoration(labelText: 'Zugeordnete Sanierungsmaßnahme'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: projectCtrl,
                              decoration: const InputDecoration(labelText: 'Projekt-ID / Name (optional)'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final fiscalYear =
                            int.tryParse(yearCtrl.text.trim()) ?? DateTime.now().year;
                        await ref
                            .read(budgetRepositoryProvider)
                            .createBudget(
                              entityType: _entityType,
                              entityId: _entityId,
                              fiscalYear: fiscalYear,
                              versionName: versionCtrl.text.trim().isEmpty ? 'Base' : versionCtrl.text.trim(),
                              unitId: selectedUnitId,
                              ticketId: selectedTicketId,
                              renovationId: selectedRenovationId,
                              projectId: projectCtrl.text.trim().isEmpty ? null : projectCtrl.text.trim(),
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
          ),
    );
    yearCtrl.dispose();
    versionCtrl.dispose();
    projectCtrl.dispose();
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

  List<DropdownMenuItem<String>> _entityItems() {
    if (_entityType == 'portfolio') {
      return _portfolios
          .map(
            (portfolio) => DropdownMenuItem<String>(
              value: portfolio.id,
              child: Text(portfolio.name),
            ),
          )
          .toList(growable: false);
    }
    return _properties
        .map(
          (property) => DropdownMenuItem<String>(
            value: property.id,
            child: Text('${property.name} · ${property.city}'),
          ),
        )
        .toList(growable: false);
  }

  String _selectedEntityLabel() {
    if (_entityType == 'portfolio') {
      for (final portfolio in _portfolios) {
        if (portfolio.id == _entityId) {
          return portfolio.name;
        }
      }
      return _entityId.isEmpty ? 'No portfolio selected' : _entityId;
    }
    if (_entityType != 'asset_property') {
      return _entityId.isEmpty ? _entityInputLabel : _entityId;
    }
    for (final property in _properties) {
      if (property.id == _entityId) {
        return property.name;
      }
    }
    return _entityId.isEmpty ? 'No property selected' : _entityId;
  }
}

class _BudgetManagementSummary extends StatelessWidget {
  const _BudgetManagementSummary({
    required this.planned,
    required this.actual,
    required this.variance,
    required this.forecast,
  });

  final double planned;
  final double actual;
  final double variance;
  final double forecast;

  @override
  Widget build(BuildContext context) {
    final varianceTone =
        variance.abs() < 0.01
            ? context.semanticColors.success
            : variance < 0
                ? context.semanticColors.warning
                : Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _BudgetSummaryTile(
          label: 'Geplant',
          value: _formatBudgetCurrency(planned),
          icon: Icons.account_balance_wallet_outlined,
        ),
        _BudgetSummaryTile(
          label: 'Ist',
          value: _formatBudgetCurrency(actual),
          icon: Icons.receipt_long_outlined,
        ),
        _BudgetSummaryTile(
          label: 'Abweichung',
          value: _formatBudgetCurrency(variance),
          icon: Icons.compare_arrows_outlined,
          tone: varianceTone,
        ),
        _BudgetSummaryTile(
          label: 'Forecast',
          value: _formatBudgetCurrency(forecast),
          icon: Icons.trending_up_outlined,
        ),
      ],
    );
  }
}

class _BudgetSummaryTile extends StatelessWidget {
  const _BudgetSummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.onSurface;
    return Container(
      width: context.viewport == AppViewport.mobile ? double.infinity : 180,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetVisualDashboard extends StatelessWidget {
  const _BudgetVisualDashboard({
    required this.lines,
    required this.variance,
    required this.accounts,
    required this.plannedTotal,
    required this.actualTotal,
    required this.forecastTotal,
  });

  final List<BudgetLineRecord> lines;
  final List<BudgetVarianceRecord> variance;
  final List<LedgerAccountRecord> accounts;
  final double plannedTotal;
  final double actualTotal;
  final double forecastTotal;

  @override
  Widget build(BuildContext context) {
    final varianceTotal = variance.isEmpty ? 0.0 : actualTotal - plannedTotal;
    final varianceRate =
        variance.isEmpty || plannedTotal == 0 ? null : varianceTotal / plannedTotal;
    final periodData = variance.isNotEmpty
        ? _periodDataFromVariance(variance)
        : _periodDataFromLines(lines);
    final topVariance = [...variance]
      ..sort(
        (a, b) => b.varianceAmount.abs().compareTo(a.varianceAmount.abs()),
      );
    final overviewData = <_BudgetBarDatum>[
      _BudgetBarDatum('Plan', plannedTotal),
      _BudgetBarDatum('Ist', actualTotal),
      _BudgetBarDatum('Forecast', forecastTotal),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 820;
        final panelWidth =
            stacked ? constraints.maxWidth : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _BudgetMiniPanel(
              width: panelWidth,
              title: 'Budgetsteuerung',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BudgetStatusStrip(
                    varianceTotal: varianceTotal,
                    varianceRate: varianceRate,
                  ),
                  const SizedBox(height: 10),
                  _BudgetBarList(data: overviewData),
                ],
              ),
            ),
            _BudgetMiniPanel(
              width: panelWidth,
              title: 'Top-Abweichungen',
              child: _BudgetBarList(
                data: topVariance
                    .take(4)
                    .map(
                      (item) => _BudgetBarDatum(
                        _budgetAccountName(accounts, item.accountId),
                        item.varianceAmount,
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            _BudgetMiniPanel(
              width: panelWidth,
              title: 'Periodentrend',
              child: _BudgetBarList(data: periodData.take(6).toList()),
            ),
            _BudgetMiniPanel(
              width: panelWidth,
              title: 'Planstruktur',
              child: _BudgetBarList(
                data: _budgetPlanByAccount(lines, accounts).take(6).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BudgetMiniPanel extends StatelessWidget {
  const _BudgetMiniPanel({
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
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _BudgetStatusStrip extends StatelessWidget {
  const _BudgetStatusStrip({
    required this.varianceTotal,
    required this.varianceRate,
  });

  final double varianceTotal;
  final double? varianceRate;

  @override
  Widget build(BuildContext context) {
    final absRate = varianceRate?.abs() ?? 0;
    final color = varianceRate == null
        ? Theme.of(context).colorScheme.primary
        : absRate <= 0.05
        ? context.semanticColors.success
        : absRate <= 0.15
            ? context.semanticColors.warning
            : Theme.of(context).colorScheme.error;
    final label = varianceRate == null
        ? 'Ist-Abgleich offen'
        : absRate <= 0.05
        ? 'Im Rahmen'
        : absRate <= 0.15
            ? 'Beobachten'
            : 'Eskalieren';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_outlined, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Text(
            varianceRate == null
                ? _formatBudgetCurrency(varianceTotal)
                : '${(varianceRate! * 100).toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _BudgetBarList extends StatelessWidget {
  const _BudgetBarList({required this.data});

  final List<_BudgetBarDatum> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: 128,
        child: Center(
          child: Text(
            'Keine Daten',
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
                width: 96,
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
                    minHeight: 9,
                    value:
                        (item.value.abs() / denominator).clamp(0.0, 1.0).toDouble(),
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
                width: 78,
                child: Text(
                  _formatBudgetCurrency(item.value),
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

class _BudgetBarDatum {
  const _BudgetBarDatum(this.label, this.value);

  final String label;
  final double value;
}

List<_BudgetBarDatum> _periodDataFromVariance(
  List<BudgetVarianceRecord> variance,
) {
  final totals = <String, double>{};
  for (final row in variance) {
    totals[row.periodKey] = (totals[row.periodKey] ?? 0) + row.varianceAmount;
  }
  return _budgetDataFromTotals(totals);
}

List<_BudgetBarDatum> _periodDataFromLines(List<BudgetLineRecord> lines) {
  final totals = <String, double>{};
  for (final line in lines) {
    final signed = line.direction == 'in' ? line.amount : -line.amount;
    totals[line.periodKey] = (totals[line.periodKey] ?? 0) + signed;
  }
  return _budgetDataFromTotals(totals);
}

List<_BudgetBarDatum> _budgetPlanByAccount(
  List<BudgetLineRecord> lines,
  List<LedgerAccountRecord> accounts,
) {
  final totals = <String, double>{};
  for (final line in lines) {
    final signed = line.direction == 'in' ? line.amount : -line.amount;
    final label = _budgetAccountName(accounts, line.accountId);
    totals[label] = (totals[label] ?? 0) + signed;
  }
  return _budgetDataFromTotals(totals, sortByAbsolute: true);
}

List<_BudgetBarDatum> _budgetDataFromTotals(
  Map<String, double> totals, {
  bool sortByAbsolute = false,
}) {
  final data = totals.entries
      .map((entry) => _BudgetBarDatum(entry.key, entry.value))
      .toList();
  data.sort((a, b) {
    if (sortByAbsolute) {
      return b.value.abs().compareTo(a.value.abs());
    }
    return a.label.compareTo(b.label);
  });
  return data;
}

String _budgetAccountName(List<LedgerAccountRecord> accounts, String accountId) {
  return accounts
          .where((account) => account.id == accountId)
          .map((account) => account.name)
          .firstOrNull ??
      accountId;
}

String _formatBudgetCurrency(double value) {
  final negative = value < 0;
  final absolute = value.abs();
  final formatted =
      absolute >= 1000000
          ? '${(absolute / 1000000).toStringAsFixed(1)} Mio. EUR'
          : absolute >= 1000
              ? '${(absolute / 1000).toStringAsFixed(1)} Tsd. EUR'
              : '${absolute.toStringAsFixed(0)} EUR';
  return negative ? '-$formatted' : formatted;
}
