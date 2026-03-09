import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/inputs.dart';
import '../../components/responsive_constraints.dart';
import '../../state/analysis_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_parse.dart';
import '../../widgets/info_tooltip.dart';

class InputsScreen extends ConsumerWidget {
  const InputsScreen({super.key, required this.scenarioId});

  final String scenarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(
      scenarioAnalysisControllerProvider(scenarioId),
    );
    final controller = ref.read(
      scenarioAnalysisControllerProvider(scenarioId).notifier,
    );

    return stateAsync.when(
      data: (state) {
        final inputs = state.inputs;
        final valuation = state.valuation;

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Autosave: ${state.isSaving ? 'saving...' : 'saved'}'),
                    OutlinedButton(
                      onPressed:
                          () => _confirmApplySettings(context, controller),
                      child: const Text('Apply Current Settings'),
                    ),
                    if (state.saveError != null) ...[
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: ResponsiveConstraints.itemWidth(
                            context,
                            idealWidth: 520,
                            maxWidth: 720,
                          ),
                        ),
                        child: Text(
                          state.saveError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.component),
                _section(
                  context,
                  title: 'Acquisition',
                  metricKey: 'mao',
                  children: [
                    _numberField(
                      context: context,
                      label: 'Purchase Price',
                      initial: inputs.purchasePrice,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) => current.copyWith(purchasePrice: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Rehab Budget',
                      initial: inputs.rehabBudget,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) => current.copyWith(rehabBudget: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Closing Cost Buy % (0-1)',
                      initial: inputs.closingCostBuyPercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(closingCostBuyPercent: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Closing Cost Buy Fixed',
                      initial: inputs.closingCostBuyFixed,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(closingCostBuyFixed: value),
                          ),
                    ),
                    _intField(
                      context: context,
                      label: 'Hold Months',
                      initial: inputs.holdMonths,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) => current.copyWith(holdMonths: value),
                          ),
                    ),
                  ],
                ),
                _section(
                  context,
                  title: 'Financing',
                  metricKey: 'dscr',
                  children: [
                    _fieldContainer(
                      context,
                      idealWidth: 260,
                      child: DropdownButtonFormField<String>(
                        value: inputs.financingMode,
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('cash')),
                          DropdownMenuItem(value: 'loan', child: Text('loan')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            controller.patchInputs(
                              (current) =>
                                  current.copyWith(financingMode: value),
                            );
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Financing Mode',
                        ),
                      ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Down Payment % (0-1)',
                      initial: inputs.downPaymentPercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(downPaymentPercent: value),
                          ),
                    ),
                    _optionalNumberField(
                      context: context,
                      label: 'Loan Amount (optional)',
                      initial: inputs.loanAmount,
                      helper:
                          'Leave empty or 0 for auto mode (derived from total acquisition cost).',
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) => current.copyWith(loanAmount: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Interest Rate % (0-1)',
                      initial: inputs.interestRatePercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(interestRatePercent: value),
                          ),
                    ),
                    _intField(
                      context: context,
                      label: 'Term Years',
                      initial: inputs.termYears,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) => current.copyWith(termYears: value),
                          ),
                    ),
                  ],
                ),
                _section(
                  context,
                  title: 'Income',
                  metricKey: 'gsi',
                  children: [
                    _numberField(
                      context: context,
                      label: 'Rent Monthly Total',
                      initial: inputs.rentMonthlyTotal,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(rentMonthlyTotal: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Other Income Monthly',
                      initial: inputs.otherIncomeMonthly,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(otherIncomeMonthly: value),
                          ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: () => _showIncomeDialog(context, controller),
                        child: const Text('Add Income Line'),
                      ),
                    ),
                    ...state.incomeLines.map(
                      (line) => Card(
                        child: ListTile(
                          title: Text(line.name),
                          subtitle: Text(
                            'Monthly: ${line.amountMonthly.toStringAsFixed(2)}',
                          ),
                          onTap:
                              () => _editIncomeLineDialog(
                                context,
                                controller,
                                line,
                              ),
                          leading: Switch(
                            value: line.enabled,
                            onChanged:
                                (value) => controller.setIncomeLineEnabled(
                                  line.id,
                                  value,
                                ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed:
                                () => controller.deleteIncomeLine(line.id),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                _section(
                  context,
                  title: 'Expenses',
                  metricKey: 'vacancy',
                  children: [
                    _numberField(
                      context: context,
                      label: 'Vacancy % (0-1)',
                      initial: inputs.vacancyPercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(vacancyPercent: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Property Tax Monthly',
                      initial: inputs.propertyTaxMonthly,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(propertyTaxMonthly: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Insurance Monthly',
                      initial: inputs.insuranceMonthly,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(insuranceMonthly: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Utilities Monthly',
                      initial: inputs.utilitiesMonthly,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(utilitiesMonthly: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'HOA Monthly',
                      initial: inputs.hoaMonthly,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) => current.copyWith(hoaMonthly: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Other Expenses Monthly',
                      initial: inputs.otherExpensesMonthly,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(otherExpensesMonthly: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Management % (0-1)',
                      initial: inputs.managementPercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(managementPercent: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Maintenance % (0-1)',
                      initial: inputs.maintenancePercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(maintenancePercent: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'CapEx % (0-1)',
                      initial: inputs.capexPercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) => current.copyWith(capexPercent: value),
                          ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed:
                            () => _showExpenseDialog(context, controller),
                        child: const Text('Add Expense Line'),
                      ),
                    ),
                    ...state.expenseLines.map(
                      (line) => Card(
                        child: ListTile(
                          title: Text('${line.name} (${line.kind})'),
                          subtitle: Text(
                            line.kind == 'fixed'
                                ? 'Monthly: ${line.amountMonthly.toStringAsFixed(2)}'
                                : 'Percent: ${(line.percent * 100).toStringAsFixed(2)}%',
                          ),
                          onTap:
                              () => _editExpenseLineDialog(
                                context,
                                controller,
                                line,
                              ),
                          leading: Switch(
                            value: line.enabled,
                            onChanged:
                                (value) => controller.setExpenseLineEnabled(
                                  line.id,
                                  value,
                                ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed:
                                () => controller.deleteExpenseLine(line.id),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                _section(
                  context,
                  title: 'Projections & Exit',
                  metricKey: 'irr',
                  children: [
                    _numberField(
                      context: context,
                      label: 'Appreciation % (0-1)',
                      initial: inputs.appreciationPercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(appreciationPercent: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Rent Growth % (0-1)',
                      initial: inputs.rentGrowthPercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(rentGrowthPercent: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Expense Growth % (0-1)',
                      initial: inputs.expenseGrowthPercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(expenseGrowthPercent: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Sale Cost % (0-1)',
                      initial: inputs.saleCostPercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(saleCostPercent: value),
                          ),
                    ),
                    _numberField(
                      context: context,
                      label: 'Closing Cost Sell % (0-1)',
                      initial: inputs.closingCostSellPercent,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(closingCostSellPercent: value),
                          ),
                    ),
                    _intField(
                      context: context,
                      label: 'Sell After Years',
                      initial: inputs.sellAfterYears,
                      onChanged:
                          (value) => controller.patchInputs(
                            (current) =>
                                current.copyWith(sellAfterYears: value),
                          ),
                    ),
                    _nullableNumberField(
                      context: context,
                      label: 'ARV Override (empty = none)',
                      initial: inputs.arvOverride,
                      onChanged: (value) {
                        controller.patchInputs(
                          (current) =>
                              value == null
                                  ? current.copyWith(clearArvOverride: true)
                                  : current.copyWith(arvOverride: value),
                        );
                      },
                    ),
                    _nullableNumberField(
                      context: context,
                      label: 'Rent Override (empty = none)',
                      initial: inputs.rentOverride,
                      onChanged: (value) {
                        controller.patchInputs(
                          (current) =>
                              value == null
                                  ? current.copyWith(clearRentOverride: true)
                                  : current.copyWith(rentOverride: value),
                        );
                      },
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed:
                              () => controller.patchInputs(
                                (current) =>
                                    current.copyWith(clearArvOverride: true),
                              ),
                          child: const Text('Clear ARV Override'),
                        ),
                        OutlinedButton(
                          onPressed:
                              () => controller.patchInputs(
                                (current) =>
                                    current.copyWith(clearRentOverride: true),
                              ),
                          child: const Text('Clear Rent Override'),
                        ),
                      ],
                    ),
                  ],
                ),
                _section(
                  context,
                  title: 'Valuation / Exit',
                  metricKey: 'cap_rate',
                  children: [
                    _fieldContainer(
                      context,
                      idealWidth: 260,
                      child: DropdownButtonFormField<String>(
                        value: valuation.valuationMode,
                        items: const [
                          DropdownMenuItem(
                            value: 'appreciation',
                            child: Text('Appreciation'),
                          ),
                          DropdownMenuItem(
                            value: 'exit_cap',
                            child: Text('Exit Cap'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          controller.patchValuation(
                            (current) => current.copyWith(valuationMode: value),
                          );
                        },
                        decoration: const InputDecoration(
                          labelText: 'Valuation Mode',
                        ),
                      ),
                    ),
                    if (valuation.valuationMode == 'exit_cap') ...[
                      _numberField(
                        context: context,
                        label: 'Exit Cap Rate % (0-1)',
                        initial: valuation.exitCapRatePercent ?? 0,
                        onChanged:
                            (value) => controller.patchValuation(
                              (current) =>
                                  current.copyWith(exitCapRatePercent: value),
                            ),
                      ),
                      _fieldContainer(
                        context,
                        idealWidth: 260,
                        child: DropdownButtonFormField<String>(
                          value: valuation.stabilizedNoiMode ?? 'use_year1_noi',
                          items: const [
                            DropdownMenuItem(
                              value: 'use_year1_noi',
                              child: Text('Use NOI year 1'),
                            ),
                            DropdownMenuItem(
                              value: 'manual_noi',
                              child: Text('Manual NOI'),
                            ),
                            DropdownMenuItem(
                              value: 'average_years',
                              child: Text('Average NOI years'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            controller.patchValuation(
                              (current) =>
                                  current.copyWith(stabilizedNoiMode: value),
                            );
                          },
                          decoration: const InputDecoration(
                            labelText: 'Stabilized NOI Mode',
                          ),
                        ),
                      ),
                      if (valuation.stabilizedNoiMode == 'manual_noi')
                        _numberField(
                          context: context,
                          label: 'Manual Stabilized NOI',
                          initial: valuation.stabilizedNoiManual ?? 0,
                          onChanged:
                              (value) => controller.patchValuation(
                                (current) => current.copyWith(
                                  stabilizedNoiManual: value,
                                ),
                              ),
                        ),
                      if (valuation.stabilizedNoiMode == 'average_years')
                        _intField(
                          context: context,
                          label: 'Average NOI Years',
                          initial: valuation.stabilizedNoiAvgYears ?? 3,
                          onChanged:
                              (value) => controller.patchValuation(
                                (current) => current.copyWith(
                                  stabilizedNoiAvgYears: value,
                                ),
                              ),
                        ),
                      _fieldContainer(
                        context,
                        idealWidth: 360,
                        maxWidth: 560,
                        child: Text(
                          'Computed stabilized NOI: '
                          '${state.analysis.metrics.exitStabilizedNoi?.toStringAsFixed(2) ?? 'n/a'}',
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  static Widget _section(
    BuildContext context, {
    required String title,
    required String metricKey,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.component),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.component,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            InfoTooltip(metricKey: metricKey, size: 14),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.component),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sectionFieldWidth = _sectionFieldWidth(
                  constraints.maxWidth,
                );
                return _SectionFieldWidthScope(
                  fieldWidth: sectionFieldWidth,
                  child: Wrap(
                    spacing: AppSpacing.component,
                    runSpacing: AppSpacing.component,
                    children: children,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static double _sectionFieldWidth(double maxWidth) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return 260;
    }

    const spacing = AppSpacing.component;
    final columns =
        maxWidth >= 1240
            ? 4
            : maxWidth >= 920
            ? 3
            : maxWidth >= 560
            ? 2
            : 1;
    final usable = maxWidth - ((columns - 1) * spacing);
    return (usable / columns).clamp(220, 420).toDouble();
  }

  static Widget _fieldContainer(
    BuildContext context, {
    required Widget child,
    double idealWidth = 260,
    double minWidth = 140,
    double maxWidth = 560,
  }) {
    final scopedWidth = _SectionFieldWidthScope.maybeOf(context)?.fieldWidth;
    final fallback = ResponsiveConstraints.itemWidth(
      context,
      idealWidth: idealWidth,
      minWidth: minWidth,
      maxWidth: maxWidth,
    );
    final targetWidth = (scopedWidth ?? fallback).clamp(minWidth, maxWidth);
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: targetWidth),
      child: SizedBox(width: targetWidth, child: child),
    );
  }

  static Widget _numberField({
    required BuildContext context,
    required String label,
    required double initial,
    required ValueChanged<double> onChanged,
    String? helper,
  }) {
    return _fieldContainer(
      context,
      child: _ControlledNumberField(
        label: label,
        textValue: initial.toStringAsFixed(4),
        helper: helper,
        onChanged: (value) => onChanged(value ?? 0),
      ),
    );
  }

  static Widget _nullableNumberField({
    required BuildContext context,
    required String label,
    required double? initial,
    required ValueChanged<double?> onChanged,
    String? helper,
  }) {
    return _fieldContainer(
      context,
      child: _ControlledNumberField(
        label: label,
        textValue: initial == null ? '' : initial.toStringAsFixed(4),
        helper: helper,
        onChanged: onChanged,
      ),
    );
  }

  static Widget _optionalNumberField({
    required BuildContext context,
    required String label,
    required double initial,
    required ValueChanged<double> onChanged,
    String? helper,
  }) {
    return _fieldContainer(
      context,
      child: _ControlledNumberField(
        label: label,
        textValue: initial <= 0 ? '' : initial.toStringAsFixed(4),
        helper: helper,
        onChanged: (value) => onChanged(value ?? 0),
      ),
    );
  }

  static Widget _intField({
    required BuildContext context,
    required String label,
    required int initial,
    required ValueChanged<int> onChanged,
  }) {
    return _fieldContainer(
      context,
      child: _ControlledIntField(
        label: label,
        textValue: initial.toString(),
        onChanged: (value) => onChanged(value ?? 0),
      ),
    );
  }

  Future<void> _showIncomeDialog(
    BuildContext context,
    ScenarioAnalysisController controller,
  ) async {
    final nameController = TextEditingController();
    final amountController = TextEditingController(text: '0');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Income Line'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Amount Monthly'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final amount = parseDoubleFlexible(amountController.text);
                if (name.isEmpty || amount == null) {
                  return;
                }
                await controller.addIncomeLine(
                  name: name,
                  amountMonthly: amount,
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    amountController.dispose();
  }

  Future<void> _confirmApplySettings(
    BuildContext context,
    ScenarioAnalysisController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Apply Current Settings'),
            content: SizedBox(
              width: ResponsiveConstraints.dialogWidth(context, maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This overwrites the following scenario fields:'),
                  SizedBox(height: 8),
                  Text('- sell after years (horizon)'),
                  Text('- vacancy, management, maintenance, capex'),
                  Text('- appreciation, rent growth, expense growth'),
                  Text('- down payment, interest rate, term years'),
                  Text(
                    '- closing cost buy %, closing cost sell %, sale cost %',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Apply'),
              ),
            ],
          ),
    );

    if (confirmed != true) {
      return;
    }
    await controller.applyCurrentSettingsDefaults();
  }

  Future<void> _editIncomeLineDialog(
    BuildContext context,
    ScenarioAnalysisController controller,
    IncomeLine line,
  ) async {
    final nameController = TextEditingController(text: line.name);
    final amountController = TextEditingController(
      text: line.amountMonthly.toStringAsFixed(2),
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Income Line'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Amount Monthly'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final amount = parseDoubleFlexible(amountController.text);
                if (name.isEmpty || amount == null) {
                  return;
                }
                await controller.updateIncomeLine(
                  IncomeLine(
                    id: line.id,
                    scenarioId: line.scenarioId,
                    name: name,
                    amountMonthly: amount,
                    enabled: line.enabled,
                  ),
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    amountController.dispose();
  }

  Future<void> _showExpenseDialog(
    BuildContext context,
    ScenarioAnalysisController controller,
  ) async {
    final nameController = TextEditingController();
    final amountController = TextEditingController(text: '0');
    String kind = 'fixed';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Expense Line'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  DropdownButtonFormField<String>(
                    value: kind,
                    items: const [
                      DropdownMenuItem(value: 'fixed', child: Text('fixed')),
                      DropdownMenuItem(
                        value: 'percent_of_rent',
                        child: Text('percent_of_rent'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          kind = value;
                        });
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Kind'),
                  ),
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText:
                          kind == 'fixed' ? 'Amount Monthly' : 'Percent (0-1)',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final amount = parseDoubleFlexible(amountController.text);
                    if (name.isEmpty || amount == null) {
                      return;
                    }
                    await controller.addExpenseLine(
                      name: name,
                      kind: kind,
                      amountMonthly: kind == 'fixed' ? amount : 0,
                      percent: kind == 'percent_of_rent' ? amount : 0,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    amountController.dispose();
  }

  Future<void> _editExpenseLineDialog(
    BuildContext context,
    ScenarioAnalysisController controller,
    ExpenseLine line,
  ) async {
    final nameController = TextEditingController(text: line.name);
    final amountController = TextEditingController(
      text:
          line.kind == 'fixed'
              ? line.amountMonthly.toStringAsFixed(2)
              : line.percent.toStringAsFixed(4),
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Expense Line'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: amountController,
                decoration: InputDecoration(
                  labelText:
                      line.kind == 'fixed' ? 'Amount Monthly' : 'Percent (0-1)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final amount = parseDoubleFlexible(amountController.text);
                if (name.isEmpty || amount == null) {
                  return;
                }

                await controller.updateExpenseLine(
                  ExpenseLine(
                    id: line.id,
                    scenarioId: line.scenarioId,
                    name: name,
                    kind: line.kind,
                    amountMonthly: line.kind == 'fixed' ? amount : 0,
                    percent: line.kind == 'percent_of_rent' ? amount : 0,
                    enabled: line.enabled,
                  ),
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    amountController.dispose();
  }
}

class _SectionFieldWidthScope extends InheritedWidget {
  const _SectionFieldWidthScope({
    required super.child,
    required this.fieldWidth,
  });

  final double fieldWidth;

  static _SectionFieldWidthScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_SectionFieldWidthScope>();
  }

  @override
  bool updateShouldNotify(covariant _SectionFieldWidthScope oldWidget) {
    return oldWidget.fieldWidth != fieldWidth;
  }
}

class _ControlledNumberField extends StatefulWidget {
  const _ControlledNumberField({
    required this.label,
    required this.textValue,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final String textValue;
  final String? helper;
  final ValueChanged<double?> onChanged;

  @override
  State<_ControlledNumberField> createState() => _ControlledNumberFieldState();
}

class _ControlledNumberFieldState extends State<_ControlledNumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _lastSyncedText;

  @override
  void initState() {
    super.initState();
    _lastSyncedText = widget.textValue;
    _controller = TextEditingController(text: widget.textValue);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _ControlledNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.textValue == _lastSyncedText || _focusNode.hasFocus) {
      return;
    }
    _lastSyncedText = widget.textValue;
    _controller.value = TextEditingValue(
      text: widget.textValue,
      selection: TextSelection.collapsed(offset: widget.textValue.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
      ),
      onChanged: (value) {
        if (value.trim().isEmpty) {
          widget.onChanged(null);
          return;
        }
        final parsed = parseDoubleFlexible(value);
        if (parsed != null) {
          widget.onChanged(parsed);
        }
      },
    );
  }
}

class _ControlledIntField extends StatefulWidget {
  const _ControlledIntField({
    required this.label,
    required this.textValue,
    required this.onChanged,
  });

  final String label;
  final String textValue;
  final ValueChanged<int?> onChanged;

  @override
  State<_ControlledIntField> createState() => _ControlledIntFieldState();
}

class _ControlledIntFieldState extends State<_ControlledIntField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _lastSyncedText;

  @override
  void initState() {
    super.initState();
    _lastSyncedText = widget.textValue;
    _controller = TextEditingController(text: widget.textValue);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _ControlledIntField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.textValue == _lastSyncedText || _focusNode.hasFocus) {
      return;
    }
    _lastSyncedText = widget.textValue;
    _controller.value = TextEditingValue(
      text: widget.textValue,
      selection: TextSelection.collapsed(offset: widget.textValue.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: widget.label),
      onChanged: (value) {
        if (value.trim().isEmpty) {
          widget.onChanged(null);
          return;
        }
        final parsed = parseIntFlexible(value);
        if (parsed != null) {
          widget.onChanged(parsed);
        }
      },
    );
  }
}
