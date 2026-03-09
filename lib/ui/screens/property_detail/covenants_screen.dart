import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/covenant.dart';
import '../../components/responsive_constraints.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class CovenantsScreen extends ConsumerStatefulWidget {
  const CovenantsScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<CovenantsScreen> createState() => _CovenantsScreenState();
}

class _CovenantsScreenState extends ConsumerState<CovenantsScreen> {
  List<LoanRecord> _loans = const [];
  LoanRecord? _selectedLoan;
  List<CovenantRecord> _covenants = const [];
  List<CovenantCheckRecord> _checks = const [];
  String _fromPeriod = '${DateTime.now().year}-01';
  String _toPeriod = '${DateTime.now().year}-12';
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
              ElevatedButton.icon(
                onPressed: _createLoanDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Loan'),
              ),
              OutlinedButton(
                onPressed: _addLoanPeriodDialog,
                child: const Text('Add Loan Period'),
              ),
              OutlinedButton(
                onPressed: _createCovenantDialog,
                child: const Text('Add Covenant'),
              ),
              OutlinedButton(
                onPressed: _runChecks,
                child: const Text('Run Checks'),
              ),
              OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
              SizedBox(
                width: ResponsiveConstraints.itemWidth(
                  context,
                  idealWidth: 120,
                ),
                child: TextFormField(
                  initialValue: _fromPeriod,
                  decoration: const InputDecoration(labelText: 'From'),
                  onChanged: (value) => _fromPeriod = value.trim(),
                ),
              ),
              SizedBox(
                width: ResponsiveConstraints.itemWidth(
                  context,
                  idealWidth: 120,
                ),
                child: TextFormField(
                  initialValue: _toPeriod,
                  decoration: const InputDecoration(labelText: 'To'),
                  onChanged: (value) => _toPeriod = value.trim(),
                ),
              ),
            ],
          ),
          if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 1100;
                final listPane = Card(
                  child:
                      _loans.isEmpty
                          ? const Center(child: Text('No loans yet.'))
                          : ListView.builder(
                            itemCount: _loans.length,
                            itemBuilder: (context, index) {
                              final loan = _loans[index];
                              return ListTile(
                                selected: _selectedLoan?.id == loan.id,
                                title: Text(loan.lenderName ?? loan.id),
                                subtitle: Text(
                                  'Principal ${loan.principal.toStringAsFixed(2)} | ${loan.interestRatePercent.toStringAsFixed(2)}%',
                                ),
                                onTap: () => _selectLoan(loan),
                              );
                            },
                          ),
                );
                final detailPane = Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child:
                        _selectedLoan == null
                            ? const Center(child: Text('Select a loan'))
                            : SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Covenants',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  if (_covenants.isNotEmpty)
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: DataTable(
                                        columns: const [
                                          DataColumn(label: Text('Kind')),
                                          DataColumn(label: Text('Operator')),
                                          DataColumn(label: Text('Threshold')),
                                          DataColumn(label: Text('Severity')),
                                        ],
                                        rows:
                                            _covenants
                                                .map(
                                                  (c) => DataRow(
                                                    cells: [
                                                      DataCell(Text(c.kind)),
                                                      DataCell(
                                                        Text(c.operator),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          c.threshold
                                                              .toStringAsFixed(
                                                                3,
                                                              ),
                                                        ),
                                                      ),
                                                      DataCell(
                                                        Text(c.severity),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                                .toList(),
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Checks',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  if (_checks.isNotEmpty)
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: DataTable(
                                        columns: const [
                                          DataColumn(label: Text('Period')),
                                          DataColumn(label: Text('Actual')),
                                          DataColumn(label: Text('Pass')),
                                          DataColumn(label: Text('Notes')),
                                        ],
                                        rows:
                                            _checks
                                                .map(
                                                  (check) => DataRow(
                                                    cells: [
                                                      DataCell(
                                                        Text(check.periodKey),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          check.actualValue
                                                                  ?.toStringAsFixed(
                                                                    3,
                                                                  ) ??
                                                              'unknown',
                                                        ),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          check.pass
                                                              ? 'pass'
                                                              : 'fail/unknown',
                                                        ),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          check.notes ?? '-',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                                .toList(),
                                      ),
                                    ),
                                ],
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

  Future<void> _reload() async {
    final loans = await ref
        .read(covenantRepositoryProvider)
        .listLoansByAsset(widget.propertyId);
    if (!mounted) {
      return;
    }
    setState(() {
      _loans = loans;
      if (_selectedLoan != null) {
        for (final loan in loans) {
          if (loan.id == _selectedLoan!.id) {
            _selectedLoan = loan;
            break;
          }
        }
      }
    });
    if (_selectedLoan != null) {
      await _selectLoan(_selectedLoan!);
    }
  }

  Future<void> _selectLoan(LoanRecord loan) async {
    final covenants = await ref
        .read(covenantRepositoryProvider)
        .listCovenantsByLoan(loan.id);
    final checks = await ref
        .read(covenantRepositoryProvider)
        .listChecksByLoan(loan.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedLoan = loan;
      _covenants = covenants;
      _checks = checks;
    });
  }

  Future<void> _createLoanDialog() async {
    final lenderCtrl = TextEditingController();
    final principalCtrl = TextEditingController(text: '1000000');
    final rateCtrl = TextEditingController(text: '0.05');
    final termCtrl = TextEditingController(text: '20');
    final startCtrl = TextEditingController(
      text: DateTime.now().millisecondsSinceEpoch.toString(),
    );

    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Create Loan'),
            content: SizedBox(
              width: ResponsiveConstraints.dialogWidth(context, maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: lenderCtrl,
                    decoration: const InputDecoration(labelText: 'Lender Name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: principalCtrl,
                    decoration: const InputDecoration(labelText: 'Principal'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: rateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Interest Rate Percent (decimal)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: termCtrl,
                    decoration: const InputDecoration(labelText: 'Term Years'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: startCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Start Date (epoch ms)',
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
                  final principal = double.tryParse(principalCtrl.text.trim());
                  final rate = double.tryParse(rateCtrl.text.trim());
                  final term = int.tryParse(termCtrl.text.trim());
                  final start = int.tryParse(startCtrl.text.trim());
                  if (principal == null ||
                      rate == null ||
                      term == null ||
                      start == null) {
                    return;
                  }
                  await ref
                      .read(covenantRepositoryProvider)
                      .createLoan(
                        assetPropertyId: widget.propertyId,
                        lenderName:
                            lenderCtrl.text.trim().isEmpty
                                ? null
                                : lenderCtrl.text.trim(),
                        principal: principal,
                        interestRatePercent: rate,
                        termYears: term,
                        startDate: start,
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

    lenderCtrl.dispose();
    principalCtrl.dispose();
    rateCtrl.dispose();
    termCtrl.dispose();
    startCtrl.dispose();
  }

  Future<void> _addLoanPeriodDialog() async {
    final loan = _selectedLoan;
    if (loan == null) {
      setState(() => _status = 'Select a loan first.');
      return;
    }
    final periodCtrl = TextEditingController(text: _fromPeriod);
    final balanceCtrl = TextEditingController(
      text: loan.principal.toStringAsFixed(2),
    );
    final debtCtrl = TextEditingController(text: '0');

    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Loan Period'),
            content: SizedBox(
              width: ResponsiveConstraints.dialogWidth(context, maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: periodCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Period (YYYY-MM)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: balanceCtrl,
                    decoration: const InputDecoration(labelText: 'Balance End'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: debtCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Debt Service',
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
                  final balance = double.tryParse(balanceCtrl.text.trim());
                  final debt = double.tryParse(debtCtrl.text.trim());
                  if (balance == null || debt == null) {
                    return;
                  }
                  await ref
                      .read(covenantRepositoryProvider)
                      .upsertLoanPeriod(
                        loanId: loan.id,
                        periodKey: periodCtrl.text.trim(),
                        balanceEnd: balance,
                        debtService: debt,
                      );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );

    periodCtrl.dispose();
    balanceCtrl.dispose();
    debtCtrl.dispose();
  }

  Future<void> _createCovenantDialog() async {
    final loan = _selectedLoan;
    if (loan == null) {
      setState(() => _status = 'Select a loan first.');
      return;
    }
    String kind = 'dscr';
    String op = 'gte';
    String severity = 'hard';
    final thresholdCtrl = TextEditingController(text: '1.2');

    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Create Covenant'),
                  content: SizedBox(
                    width: ResponsiveConstraints.dialogWidth(
                      context,
                      maxWidth: 380,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          value: kind,
                          items: const [
                            DropdownMenuItem(
                              value: 'dscr',
                              child: Text('dscr'),
                            ),
                            DropdownMenuItem(value: 'ltv', child: Text('ltv')),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() => kind = value);
                          },
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
                            setDialogState(() => op = value);
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: thresholdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Threshold',
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: severity,
                          items: const [
                            DropdownMenuItem(
                              value: 'hard',
                              child: Text('hard'),
                            ),
                            DropdownMenuItem(
                              value: 'soft',
                              child: Text('soft'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() => severity = value);
                          },
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
                        final threshold = double.tryParse(
                          thresholdCtrl.text.trim(),
                        );
                        if (threshold == null) {
                          return;
                        }
                        await ref
                            .read(covenantRepositoryProvider)
                            .createCovenant(
                              loanId: loan.id,
                              kind: kind,
                              threshold: threshold,
                              operator: op,
                              severity: severity,
                            );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                        await _selectLoan(loan);
                      },
                      child: const Text('Create'),
                    ),
                  ],
                ),
          ),
    );

    thresholdCtrl.dispose();
  }

  Future<void> _runChecks() async {
    final checks = await ref
        .read(covenantRepositoryProvider)
        .runChecks(
          assetPropertyId: widget.propertyId,
          fromPeriod: _fromPeriod,
          toPeriod: _toPeriod,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'Computed ${checks.length} covenant checks.';
    });
    await _reload();
  }
}
