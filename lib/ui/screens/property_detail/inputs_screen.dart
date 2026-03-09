import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/inputs.dart';
import '../../../core/models/scenario_valuation.dart';
import '../../components/responsive_constraints.dart';
import '../../components/save_status_indicator.dart';
import '../../state/analysis_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_parse.dart';
import '../../widgets/info_tooltip.dart';

enum _InputsMode { basic, advanced }

class InputsScreen extends ConsumerStatefulWidget {
  const InputsScreen({super.key, required this.scenarioId});

  final String scenarioId;

  @override
  ConsumerState<InputsScreen> createState() => _InputsScreenState();
}

class _InputsScreenState extends ConsumerState<InputsScreen> {
  _InputsMode _mode = _InputsMode.basic;

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(
      scenarioAnalysisControllerProvider(widget.scenarioId),
    );
    final controller = ref.read(
      scenarioAnalysisControllerProvider(widget.scenarioId).notifier,
    );

    void patchInput(
      String fieldKey,
      ScenarioInputs Function(ScenarioInputs current) updateFn,
    ) {
      controller.patchInputs(updateFn, dirtyFields: <String>[fieldKey]);
    }

    void patchValuation(fieldKey, updateFn) {
      controller.patchValuation(updateFn, dirtyFields: <String>[fieldKey]);
    }

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
                _buildModeCard(context, state, controller),
                const SizedBox(height: AppSpacing.component),
                ...(_mode == _InputsMode.basic
                    ? _buildBasicSections(
                      context: context,
                      state: state,
                      inputs: inputs,
                      patchInput: patchInput,
                      controller: controller,
                    )
                    : _buildAdvancedSections(
                      context: context,
                      state: state,
                      inputs: inputs,
                      valuation: valuation,
                      patchInput: patchInput,
                      patchValuation: patchValuation,
                    )),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  List<Widget> _buildBasicSections({
    required BuildContext context,
    required ScenarioAnalysisState state,
    required ScenarioInputs inputs,
    required void Function(
      String fieldKey,
      ScenarioInputs Function(ScenarioInputs current) updateFn,
    )
    patchInput,
    required ScenarioAnalysisController controller,
  }) {
    return <Widget>[
      _section(
        context,
        title: 'Acquisition',
        description:
            'Start with the purchase economics that drive nearly every deal review.',
        metricKey: 'mao',
        status: _sectionStatus(
          fieldKeys: const <String>[
            _FieldKeys.purchasePrice,
            _FieldKeys.rehabBudget,
            _FieldKeys.closingCostBuyPercent,
          ],
          state: state,
        ),
        children: [
          _currencyField(
            context: context,
            label: 'Purchase Price',
            initial: inputs.purchasePrice,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.purchasePrice,
                  (current) => current.copyWith(purchasePrice: value),
                ),
          ),
          _currencyField(
            context: context,
            label: 'Renovation Budget',
            initial: inputs.rehabBudget,
            helper:
                'Planned upfront capital improvements before stabilization.',
            onChanged:
                (value) => patchInput(
                  _FieldKeys.rehabBudget,
                  (current) => current.copyWith(rehabBudget: value),
                ),
          ),
          _percentField(
            context: context,
            label: 'Acquisition Costs',
            initial: inputs.closingCostBuyPercent,
            helper: 'Estimated legal, transfer, and due diligence costs.',
            onChanged:
                (value) => patchInput(
                  _FieldKeys.closingCostBuyPercent,
                  (current) => current.copyWith(closingCostBuyPercent: value),
                ),
          ),
        ],
      ),
      _section(
        context,
        title: 'Financing Basics',
        description:
            'Keep the capital structure simple here. Expert debt assumptions live in Advanced.',
        metricKey: 'dscr',
        status: _sectionStatus(
          fieldKeys: const <String>[
            _FieldKeys.financingMode,
            _FieldKeys.downPaymentPercent,
            _FieldKeys.loanAmount,
            _FieldKeys.interestRatePercent,
            _FieldKeys.termYears,
          ],
          state: state,
        ),
        children: [
          _fieldContainer(
            context,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              value: inputs.financingMode,
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('All cash')),
                DropdownMenuItem(value: 'loan', child: Text('Debt financing')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                patchInput(
                  _FieldKeys.financingMode,
                  (current) => current.copyWith(financingMode: value),
                );
              },
              decoration: const InputDecoration(labelText: 'Financing Type'),
            ),
          ),
          _percentField(
            context: context,
            label: 'Equity Share',
            initial: inputs.downPaymentPercent,
            helper: 'Percentage of total acquisition funded with equity.',
            onChanged:
                (value) => patchInput(
                  _FieldKeys.downPaymentPercent,
                  (current) => current.copyWith(downPaymentPercent: value),
                ),
          ),
          _optionalCurrencyField(
            context: context,
            label: 'Loan Amount',
            initial: inputs.loanAmount,
            helper:
                'Leave empty to derive debt from purchase cost and equity share.',
            onChanged:
                (value) => patchInput(
                  _FieldKeys.loanAmount,
                  (current) => current.copyWith(loanAmount: value),
                ),
          ),
          _percentField(
            context: context,
            label: 'Interest Rate',
            initial: inputs.interestRatePercent,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.interestRatePercent,
                  (current) => current.copyWith(interestRatePercent: value),
                ),
          ),
          _intField(
            context: context,
            label: 'Loan Term',
            initial: inputs.termYears,
            suffixText: 'years',
            minValue: 1,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.termYears,
                  (current) => current.copyWith(termYears: value),
                ),
          ),
        ],
      ),
      _section(
        context,
        title: 'Income',
        description:
            'Use the base rent and recurring ancillary income that define the stabilized revenue run rate.',
        metricKey: 'gsi',
        status: _sectionStatus(
          fieldKeys: const <String>[
            _FieldKeys.rentMonthlyTotal,
            _FieldKeys.otherIncomeMonthly,
          ],
          state: state,
        ),
        children: [
          _currencyField(
            context: context,
            label: 'Monthly Gross Rent',
            initial: inputs.rentMonthlyTotal,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.rentMonthlyTotal,
                  (current) => current.copyWith(rentMonthlyTotal: value),
                ),
          ),
          _currencyField(
            context: context,
            label: 'Other Monthly Income',
            initial: inputs.otherIncomeMonthly,
            helper: 'Recurring parking, storage, laundry, or service income.',
            onChanged:
                (value) => patchInput(
                  _FieldKeys.otherIncomeMonthly,
                  (current) => current.copyWith(otherIncomeMonthly: value),
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
                  '${_formatCurrency(line.amountMonthly)} / month',
                ),
                onTap: () => _editIncomeLineDialog(context, controller, line),
                leading: Switch(
                  value: line.enabled,
                  onChanged:
                      (value) =>
                          controller.setIncomeLineEnabled(line.id, value),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => controller.deleteIncomeLine(line.id),
                ),
              ),
            ),
          ),
        ],
      ),
      _section(
        context,
        title: 'Operating Costs',
        description:
            'These costs and reserve rates shape stabilized NOI. Keep them close to how the asset is actually operated.',
        metricKey: 'vacancy',
        status: _sectionStatus(
          fieldKeys: const <String>[
            _FieldKeys.vacancyPercent,
            _FieldKeys.propertyTaxMonthly,
            _FieldKeys.insuranceMonthly,
            _FieldKeys.utilitiesMonthly,
            _FieldKeys.hoaMonthly,
            _FieldKeys.otherExpensesMonthly,
            _FieldKeys.managementPercent,
            _FieldKeys.maintenancePercent,
            _FieldKeys.capexPercent,
          ],
          state: state,
        ),
        children: [
          _percentField(
            context: context,
            label: 'Vacancy Rate',
            initial: inputs.vacancyPercent,
            helper: 'Expected long-run economic vacancy and collection loss.',
            onChanged:
                (value) => patchInput(
                  _FieldKeys.vacancyPercent,
                  (current) => current.copyWith(vacancyPercent: value),
                ),
          ),
          _currencyField(
            context: context,
            label: 'Property Tax',
            initial: inputs.propertyTaxMonthly,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.propertyTaxMonthly,
                  (current) => current.copyWith(propertyTaxMonthly: value),
                ),
          ),
          _currencyField(
            context: context,
            label: 'Insurance',
            initial: inputs.insuranceMonthly,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.insuranceMonthly,
                  (current) => current.copyWith(insuranceMonthly: value),
                ),
          ),
          _currencyField(
            context: context,
            label: 'Utilities',
            initial: inputs.utilitiesMonthly,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.utilitiesMonthly,
                  (current) => current.copyWith(utilitiesMonthly: value),
                ),
          ),
          _currencyField(
            context: context,
            label: 'HOA Fees',
            initial: inputs.hoaMonthly,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.hoaMonthly,
                  (current) => current.copyWith(hoaMonthly: value),
                ),
          ),
          _currencyField(
            context: context,
            label: 'Other Operating Costs',
            initial: inputs.otherExpensesMonthly,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.otherExpensesMonthly,
                  (current) => current.copyWith(otherExpensesMonthly: value),
                ),
          ),
          _percentField(
            context: context,
            label: 'Property Management',
            initial: inputs.managementPercent,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.managementPercent,
                  (current) => current.copyWith(managementPercent: value),
                ),
          ),
          _percentField(
            context: context,
            label: 'Maintenance Reserve',
            initial: inputs.maintenancePercent,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.maintenancePercent,
                  (current) => current.copyWith(maintenancePercent: value),
                ),
          ),
          _percentField(
            context: context,
            label: 'Capital Reserve',
            initial: inputs.capexPercent,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.capexPercent,
                  (current) => current.copyWith(capexPercent: value),
                ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => _showExpenseDialog(context, controller),
              child: const Text('Add Cost Line'),
            ),
          ),
          ...state.expenseLines.map(
            (line) => Card(
              child: ListTile(
                title: Text(
                  line.kind == 'fixed'
                      ? line.name
                      : '${line.name} (Share of Rent)',
                ),
                subtitle: Text(
                  line.kind == 'fixed'
                      ? '${_formatCurrency(line.amountMonthly)} / month'
                      : '${_formatPercent(line.percent)} of gross rent',
                ),
                onTap: () => _editExpenseLineDialog(context, controller, line),
                leading: Switch(
                  value: line.enabled,
                  onChanged:
                      (value) =>
                          controller.setExpenseLineEnabled(line.id, value),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => controller.deleteExpenseLine(line.id),
                ),
              ),
            ),
          ),
        ],
      ),
      _section(
        context,
        title: 'Growth & Exit',
        description:
            'These assumptions drive the forward cash flow view and the high-level exit story.',
        metricKey: 'irr',
        status: _sectionStatus(
          fieldKeys: const <String>[
            _FieldKeys.appreciationPercent,
            _FieldKeys.rentGrowthPercent,
            _FieldKeys.expenseGrowthPercent,
            _FieldKeys.sellAfterYears,
          ],
          state: state,
        ),
        children: [
          _percentField(
            context: context,
            label: 'Value Growth',
            initial: inputs.appreciationPercent,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.appreciationPercent,
                  (current) => current.copyWith(appreciationPercent: value),
                ),
          ),
          _percentField(
            context: context,
            label: 'Rent Growth',
            initial: inputs.rentGrowthPercent,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.rentGrowthPercent,
                  (current) => current.copyWith(rentGrowthPercent: value),
                ),
          ),
          _percentField(
            context: context,
            label: 'Operating Cost Growth',
            initial: inputs.expenseGrowthPercent,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.expenseGrowthPercent,
                  (current) => current.copyWith(expenseGrowthPercent: value),
                ),
          ),
          _intField(
            context: context,
            label: 'Exit After',
            initial: inputs.sellAfterYears,
            suffixText: 'years',
            minValue: 1,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.sellAfterYears,
                  (current) => current.copyWith(sellAfterYears: value),
                ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildAdvancedSections({
    required BuildContext context,
    required ScenarioAnalysisState state,
    required ScenarioInputs inputs,
    required ScenarioValuationRecord valuation,
    required void Function(
      String fieldKey,
      ScenarioInputs Function(ScenarioInputs current) updateFn,
    )
    patchInput,
    required void Function(
      String fieldKey,
      ScenarioValuationRecord Function(ScenarioValuationRecord current)
      updateFn,
    )
    patchValuation,
  }) {
    return <Widget>[
      _section(
        context,
        title: 'Closing & Timing',
        description:
            'Use these fields when you need more precise transaction timing and one-off closing adjustments.',
        metricKey: 'mao',
        status: _sectionStatus(
          fieldKeys: const <String>[
            _FieldKeys.closingCostBuyFixed,
            _FieldKeys.holdMonths,
            _FieldKeys.saleCostPercent,
            _FieldKeys.closingCostSellPercent,
          ],
          state: state,
        ),
        children: [
          _currencyField(
            context: context,
            label: 'Fixed Acquisition Costs',
            initial: inputs.closingCostBuyFixed,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.closingCostBuyFixed,
                  (current) => current.copyWith(closingCostBuyFixed: value),
                ),
          ),
          _intField(
            context: context,
            label: 'Hold Period',
            initial: inputs.holdMonths,
            suffixText: 'months',
            minValue: 1,
            helper:
                'Used for short-hold underwriting views alongside the exit year horizon.',
            onChanged:
                (value) => patchInput(
                  _FieldKeys.holdMonths,
                  (current) => current.copyWith(holdMonths: value),
                ),
          ),
          _percentField(
            context: context,
            label: 'Selling Costs',
            initial: inputs.saleCostPercent,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.saleCostPercent,
                  (current) => current.copyWith(saleCostPercent: value),
                ),
          ),
          _percentField(
            context: context,
            label: 'Exit Closing Costs',
            initial: inputs.closingCostSellPercent,
            onChanged:
                (value) => patchInput(
                  _FieldKeys.closingCostSellPercent,
                  (current) => current.copyWith(closingCostSellPercent: value),
                ),
          ),
        ],
      ),
      _section(
        context,
        title: 'Overrides',
        description:
            'Only use overrides when the scenario should ignore the calculated rent or exit value.',
        metricKey: 'irr',
        status: _sectionStatus(
          fieldKeys: const <String>[
            _FieldKeys.arvOverride,
            _FieldKeys.rentOverride,
          ],
          state: state,
        ),
        children: [
          _nullableCurrencyField(
            context: context,
            label: 'Value Override',
            initial: inputs.arvOverride,
            helper: 'Leave empty to use the model-driven exit value.',
            onChanged: (value) {
              patchInput(
                _FieldKeys.arvOverride,
                (current) =>
                    value == null
                        ? current.copyWith(clearArvOverride: true)
                        : current.copyWith(arvOverride: value),
              );
            },
          ),
          _nullableCurrencyField(
            context: context,
            label: 'Rent Override',
            initial: inputs.rentOverride,
            helper: 'Leave empty to use Monthly Gross Rent from Basic.',
            onChanged: (value) {
              patchInput(
                _FieldKeys.rentOverride,
                (current) =>
                    value == null
                        ? current.copyWith(clearRentOverride: true)
                        : current.copyWith(rentOverride: value),
              );
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed:
                    () => patchInput(
                      _FieldKeys.arvOverride,
                      (current) => current.copyWith(clearArvOverride: true),
                    ),
                child: const Text('Clear Value Override'),
              ),
              OutlinedButton(
                onPressed:
                    () => patchInput(
                      _FieldKeys.rentOverride,
                      (current) => current.copyWith(clearRentOverride: true),
                    ),
                child: const Text('Clear Rent Override'),
              ),
            ],
          ),
        ],
      ),
      _section(
        context,
        title: 'Exit Valuation',
        description:
            'Switch to exit cap only when you want sale pricing to follow a cap rate and stabilized NOI method.',
        metricKey: 'cap_rate',
        status: _sectionStatus(
          fieldKeys: const <String>[
            _FieldKeys.valuationMode,
            _FieldKeys.exitCapRatePercent,
            _FieldKeys.stabilizedNoiMode,
            _FieldKeys.stabilizedNoiManual,
            _FieldKeys.stabilizedNoiAvgYears,
          ],
          state: state,
        ),
        children: [
          _fieldContainer(
            context,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              value: valuation.valuationMode,
              items: const [
                DropdownMenuItem(
                  value: 'appreciation',
                  child: Text('Growth-based value'),
                ),
                DropdownMenuItem(
                  value: 'exit_cap',
                  child: Text('Exit cap value'),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                patchValuation(
                  _FieldKeys.valuationMode,
                  (current) => current.copyWith(valuationMode: value),
                );
              },
              decoration: const InputDecoration(labelText: 'Valuation Method'),
            ),
          ),
          if (valuation.valuationMode == 'exit_cap') ...[
            _percentField(
              context: context,
              label: 'Exit Cap Rate',
              initial: valuation.exitCapRatePercent,
              allowEmpty: false,
              helper: 'Required when sale pricing is based on stabilized NOI.',
              onChanged:
                  (value) => patchValuation(
                    _FieldKeys.exitCapRatePercent,
                    (current) => current.copyWith(exitCapRatePercent: value),
                  ),
            ),
            _fieldContainer(
              context,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: valuation.stabilizedNoiMode ?? 'use_year1_noi',
                items: const [
                  DropdownMenuItem(
                    value: 'use_year1_noi',
                    child: Text('Use Year 1 NOI'),
                  ),
                  DropdownMenuItem(
                    value: 'manual_noi',
                    child: Text('Manual NOI'),
                  ),
                  DropdownMenuItem(
                    value: 'average_years',
                    child: Text('Average NOI'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  patchValuation(
                    _FieldKeys.stabilizedNoiMode,
                    (current) => current.copyWith(stabilizedNoiMode: value),
                  );
                },
                decoration: const InputDecoration(
                  labelText: 'Stabilized NOI Basis',
                ),
              ),
            ),
            if (valuation.stabilizedNoiMode == 'manual_noi')
              _currencyField(
                context: context,
                label: 'Manual Stabilized NOI',
                initial: valuation.stabilizedNoiManual ?? 0,
                helper: 'Annual stabilized NOI used for exit valuation.',
                onChanged:
                    (value) => patchValuation(
                      _FieldKeys.stabilizedNoiManual,
                      (current) => current.copyWith(stabilizedNoiManual: value),
                    ),
              ),
            if (valuation.stabilizedNoiMode == 'average_years')
              _intField(
                context: context,
                label: 'NOI Averaging Window',
                initial: valuation.stabilizedNoiAvgYears ?? 3,
                suffixText: 'years',
                minValue: 1,
                onChanged:
                    (value) => patchValuation(
                      _FieldKeys.stabilizedNoiAvgYears,
                      (current) =>
                          current.copyWith(stabilizedNoiAvgYears: value),
                    ),
              ),
            _fieldContainer(
              context,
              idealWidth: 360,
              maxWidth: 560,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                decoration: BoxDecoration(
                  color: context.semanticColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadiusTokens.md),
                  border: Border.all(color: context.semanticColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Computed Stabilized NOI',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.analysis.metrics.exitStabilizedNoi == null
                          ? 'Not available yet'
                          : _formatCurrency(
                            state.analysis.metrics.exitStabilizedNoi!,
                          ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ];
  }

  Widget _buildModeCard(
    BuildContext context,
    ScenarioAnalysisState state,
    ScenarioAnalysisController controller,
  ) {
    final savePresentation = _savePresentation(context, state);
    final modeDescription =
        _mode == _InputsMode.basic
            ? 'Basic keeps the core underwriting assumptions within easy reach.'
            : 'Advanced exposes transaction details, overrides, and exit valuation controls.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.component,
              runSpacing: AppSpacing.component,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: ResponsiveConstraints.itemWidth(
                      context,
                      idealWidth: 340,
                      maxWidth: 420,
                    ),
                  ),
                  child: SaveStatusIndicator(
                    label: savePresentation.label,
                    detail: savePresentation.detail,
                    tone: savePresentation.tone,
                  ),
                ),
                SegmentedButton<_InputsMode>(
                  segments: const [
                    ButtonSegment<_InputsMode>(
                      value: _InputsMode.basic,
                      label: Text('Basic'),
                    ),
                    ButtonSegment<_InputsMode>(
                      value: _InputsMode.advanced,
                      label: Text('Advanced'),
                    ),
                  ],
                  selected: <_InputsMode>{_mode},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) {
                      return;
                    }
                    setState(() {
                      _mode = selection.first;
                    });
                  },
                ),
                OutlinedButton(
                  onPressed: () => _confirmApplySettings(context, controller),
                  child: const Text('Apply Default Assumptions'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            Text(
              modeDescription,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  _SavePresentation _savePresentation(
    BuildContext context,
    ScenarioAnalysisState state,
  ) {
    if (state.saveError != null) {
      return _SavePresentation(
        label: 'Save failed',
        detail: state.saveError,
        tone: SaveStatusTone.error,
      );
    }
    if (state.isSaving) {
      return const _SavePresentation(
        label: 'Saving changes...',
        detail: 'The current assumptions are being synchronized.',
        tone: SaveStatusTone.working,
      );
    }
    if (state.hasUnsavedChanges) {
      return const _SavePresentation(
        label: 'Unsaved changes',
        detail: 'You have local edits that are not persisted yet.',
        tone: SaveStatusTone.warning,
      );
    }
    if (state.lastSavedAt != null) {
      return _SavePresentation(
        label: 'All changes saved',
        detail: 'Last saved at ${_formatTime(context, state.lastSavedAt!)}.',
        tone: SaveStatusTone.success,
      );
    }
    return const _SavePresentation(
      label: 'Ready for changes',
      detail: 'Update the key assumptions for this scenario.',
      tone: SaveStatusTone.neutral,
    );
  }

  _SectionStatus? _sectionStatus({
    required List<String> fieldKeys,
    required ScenarioAnalysisState state,
  }) {
    final dirty = fieldKeys.any(state.dirtyFields.contains);
    if (!dirty) {
      return null;
    }
    if (state.saveError != null) {
      return const _SectionStatus('Retry pending', SaveStatusTone.error);
    }
    if (state.isSaving) {
      return const _SectionStatus('Saving', SaveStatusTone.working);
    }
    return const _SectionStatus('Unsaved', SaveStatusTone.warning);
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required String description,
    required String metricKey,
    required List<Widget> children,
    _SectionStatus? status,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (status != null) ...[
              const SizedBox(width: 8),
              SaveStatusIndicator(
                label: status.label,
                tone: status.tone,
                compact: true,
              ),
            ],
            const SizedBox(width: 8),
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

  Widget _fieldContainer(
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

  Widget _currencyField({
    required BuildContext context,
    required String label,
    required double initial,
    required ValueChanged<double> onChanged,
    String? helper,
  }) {
    return _fieldContainer(
      context,
      child: _ControlledDecimalField(
        label: label,
        textValue: _formatCurrencyInput(initial),
        helper: helper,
        prefixText: 'EUR ',
        minValue: 0,
        minErrorText: 'Amount cannot be negative.',
        onChanged: (value) => onChanged(value ?? 0),
      ),
    );
  }

  Widget _optionalCurrencyField({
    required BuildContext context,
    required String label,
    required double initial,
    required ValueChanged<double> onChanged,
    String? helper,
  }) {
    return _fieldContainer(
      context,
      child: _ControlledDecimalField(
        label: label,
        textValue: initial <= 0 ? '' : _formatCurrencyInput(initial),
        helper: helper,
        prefixText: 'EUR ',
        allowEmpty: true,
        minValue: 0,
        minErrorText: 'Amount cannot be negative.',
        onChanged: (value) => onChanged(value ?? 0),
      ),
    );
  }

  Widget _nullableCurrencyField({
    required BuildContext context,
    required String label,
    required double? initial,
    required ValueChanged<double?> onChanged,
    String? helper,
  }) {
    return _fieldContainer(
      context,
      child: _ControlledDecimalField(
        label: label,
        textValue: initial == null ? '' : _formatCurrencyInput(initial),
        helper: helper,
        prefixText: 'EUR ',
        allowEmpty: true,
        minValue: 0,
        minErrorText: 'Amount cannot be negative.',
        onChanged: onChanged,
      ),
    );
  }

  Widget _percentField({
    required BuildContext context,
    required String label,
    required double? initial,
    required ValueChanged<double> onChanged,
    String? helper,
    bool allowEmpty = false,
  }) {
    return _fieldContainer(
      context,
      child: _ControlledDecimalField(
        label: label,
        textValue: initial == null ? '' : _formatPercentInput(initial),
        helper: helper,
        allowEmpty: allowEmpty,
        suffixText: '%',
        minValue: 0,
        maxValue: 100,
        minErrorText: 'Enter a value between 0% and 100%.',
        maxErrorText: 'Enter a value between 0% and 100%.',
        onChanged: (value) => onChanged((value ?? 0) / 100),
      ),
    );
  }

  Widget _intField({
    required BuildContext context,
    required String label,
    required int initial,
    required ValueChanged<int> onChanged,
    String? helper,
    String? suffixText,
    int minValue = 0,
  }) {
    return _fieldContainer(
      context,
      child: _ControlledIntField(
        label: label,
        textValue: initial.toString(),
        helper: helper,
        suffixText: suffixText,
        minValue: minValue,
        minErrorText:
            minValue <= 0
                ? 'Value cannot be negative.'
                : 'Enter at least $minValue.',
        onChanged: (value) => onChanged(value ?? 0),
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

  String _formatCurrencyInput(double value) {
    return value.toStringAsFixed(2);
  }

  static String _formatCurrency(double value) {
    return 'EUR ${value.toStringAsFixed(2)}';
  }

  static String _formatPercent(double value) {
    return '${(value * 100).toStringAsFixed(1)}%';
  }

  String _formatPercentInput(double value) {
    return (value * 100).toStringAsFixed(1);
  }

  static String _formatTime(BuildContext context, int timestamp) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(timestamp)),
      alwaysUse24HourFormat: true,
    );
  }

  Future<void> _showIncomeDialog(
    BuildContext context,
    ScenarioAnalysisController controller,
  ) async {
    final nameController = TextEditingController();
    final amountController = TextEditingController(text: '0.00');

    await showDialog<void>(
      context: context,
      builder: (context) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Income Line'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Line Item Name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Monthly Amount',
                      prefixText: 'EUR ',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: TextStyle(color: context.semanticColors.error),
                    ),
                  ],
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
                    if (name.isEmpty || amount == null || amount < 0) {
                      setDialogState(() {
                        errorText = 'Enter a name and a valid monthly amount.';
                      });
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
            title: const Text('Apply Default Assumptions'),
            content: SizedBox(
              width: ResponsiveConstraints.dialogWidth(context, maxWidth: 520),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This replaces the current scenario assumptions with the defaults from Settings.',
                  ),
                  SizedBox(height: 8),
                  Text('Included: vacancy, reserves, growth, and financing.'),
                  Text(
                    'Also updated: horizon, acquisition costs, and exit costs.',
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

    if (confirmed == true) {
      await controller.applyCurrentSettingsDefaults();
    }
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
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Income Line'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Line Item Name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Monthly Amount',
                      prefixText: 'EUR ',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: TextStyle(color: context.semanticColors.error),
                    ),
                  ],
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
                    if (name.isEmpty || amount == null || amount < 0) {
                      setDialogState(() {
                        errorText = 'Enter a name and a valid monthly amount.';
                      });
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
    final amountController = TextEditingController(text: '0.00');
    String kind = 'fixed';

    await showDialog<void>(
      context: context,
      builder: (context) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Cost Line'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Line Item Name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: kind,
                    items: const [
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text('Fixed monthly cost'),
                      ),
                      DropdownMenuItem(
                        value: 'percent_of_rent',
                        child: Text('Share of gross rent'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        kind = value;
                        errorText = null;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Cost Type'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText:
                          kind == 'fixed'
                              ? 'Monthly Amount'
                              : 'Share of Gross Rent',
                      prefixText: kind == 'fixed' ? 'EUR ' : null,
                      suffixText: kind == 'fixed' ? null : '%',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: TextStyle(color: context.semanticColors.error),
                    ),
                  ],
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
                    final validPercent =
                        kind != 'percent_of_rent' ||
                        (amount != null && amount >= 0 && amount <= 100);
                    if (name.isEmpty ||
                        amount == null ||
                        amount < 0 ||
                        !validPercent) {
                      setDialogState(() {
                        errorText =
                            kind == 'fixed'
                                ? 'Enter a name and a valid monthly amount.'
                                : 'Enter a name and a percentage between 0 and 100.';
                      });
                      return;
                    }
                    await controller.addExpenseLine(
                      name: name,
                      kind: kind,
                      amountMonthly: kind == 'fixed' ? amount : 0,
                      percent: kind == 'percent_of_rent' ? amount / 100 : 0,
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
              : (line.percent * 100).toStringAsFixed(1),
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Cost Line'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Line Item Name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText:
                          line.kind == 'fixed'
                              ? 'Monthly Amount'
                              : 'Share of Gross Rent',
                      prefixText: line.kind == 'fixed' ? 'EUR ' : null,
                      suffixText: line.kind == 'fixed' ? null : '%',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: TextStyle(color: context.semanticColors.error),
                    ),
                  ],
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
                    final validPercent =
                        line.kind != 'percent_of_rent' ||
                        (amount != null && amount >= 0 && amount <= 100);
                    if (name.isEmpty ||
                        amount == null ||
                        amount < 0 ||
                        !validPercent) {
                      setDialogState(() {
                        errorText =
                            line.kind == 'fixed'
                                ? 'Enter a name and a valid monthly amount.'
                                : 'Enter a name and a percentage between 0 and 100.';
                      });
                      return;
                    }
                    await controller.updateExpenseLine(
                      ExpenseLine(
                        id: line.id,
                        scenarioId: line.scenarioId,
                        name: name,
                        kind: line.kind,
                        amountMonthly: line.kind == 'fixed' ? amount : 0,
                        percent:
                            line.kind == 'percent_of_rent' ? amount / 100 : 0,
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

class _ControlledDecimalField extends StatefulWidget {
  const _ControlledDecimalField({
    required this.label,
    required this.textValue,
    required this.onChanged,
    this.helper,
    this.prefixText,
    this.suffixText,
    this.allowEmpty = false,
    this.minValue,
    this.maxValue,
    this.minErrorText,
    this.maxErrorText,
  });

  final String label;
  final String textValue;
  final String? helper;
  final String? prefixText;
  final String? suffixText;
  final bool allowEmpty;
  final double? minValue;
  final double? maxValue;
  final String? minErrorText;
  final String? maxErrorText;
  final ValueChanged<double?> onChanged;

  @override
  State<_ControlledDecimalField> createState() =>
      _ControlledDecimalFieldState();
}

class _ControlledDecimalFieldState extends State<_ControlledDecimalField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _lastSyncedText;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _lastSyncedText = widget.textValue;
    _controller = TextEditingController(text: widget.textValue);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _ControlledDecimalField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasLocalEdits = _controller.text != _lastSyncedText;
    if (_focusNode.hasFocus ||
        hasLocalEdits ||
        widget.textValue == _lastSyncedText) {
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
        prefixText: widget.prefixText,
        suffixText: widget.suffixText,
        errorText: _errorText,
      ),
      onChanged: (value) {
        final validation = _validate(value);
        setState(() {
          _errorText = validation;
        });
        if (validation != null) {
          return;
        }
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

  String? _validate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return widget.allowEmpty ? null : 'This field is required.';
    }
    final parsed = parseDoubleFlexible(text);
    if (parsed == null) {
      return 'Enter a valid number.';
    }
    if (widget.minValue != null && parsed < widget.minValue!) {
      return widget.minErrorText ??
          'Value cannot be lower than ${widget.minValue}.';
    }
    if (widget.maxValue != null && parsed > widget.maxValue!) {
      return widget.maxErrorText ??
          'Value cannot be higher than ${widget.maxValue}.';
    }
    return null;
  }
}

class _ControlledIntField extends StatefulWidget {
  const _ControlledIntField({
    required this.label,
    required this.textValue,
    required this.onChanged,
    this.helper,
    this.suffixText,
    this.minValue = 0,
    this.minErrorText,
  });

  final String label;
  final String textValue;
  final String? helper;
  final String? suffixText;
  final int minValue;
  final String? minErrorText;
  final ValueChanged<int?> onChanged;

  @override
  State<_ControlledIntField> createState() => _ControlledIntFieldState();
}

class _ControlledIntFieldState extends State<_ControlledIntField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _lastSyncedText;
  String? _errorText;

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
    final hasLocalEdits = _controller.text != _lastSyncedText;
    if (_focusNode.hasFocus ||
        hasLocalEdits ||
        widget.textValue == _lastSyncedText) {
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
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        suffixText: widget.suffixText,
        errorText: _errorText,
      ),
      onChanged: (value) {
        final validation = _validate(value);
        setState(() {
          _errorText = validation;
        });
        if (validation != null) {
          return;
        }
        final parsed = parseIntFlexible(value);
        if (parsed != null) {
          widget.onChanged(parsed);
        }
      },
    );
  }

  String? _validate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return 'This field is required.';
    }
    final parsed = parseIntFlexible(text);
    if (parsed == null) {
      return 'Enter a whole number.';
    }
    if (parsed < widget.minValue) {
      return widget.minErrorText ?? 'Enter at least ${widget.minValue}.';
    }
    return null;
  }
}

class _SavePresentation {
  const _SavePresentation({
    required this.label,
    required this.detail,
    required this.tone,
  });

  final String label;
  final String? detail;
  final SaveStatusTone tone;
}

class _SectionStatus {
  const _SectionStatus(this.label, this.tone);

  final String label;
  final SaveStatusTone tone;
}

class _FieldKeys {
  static const purchasePrice = 'purchasePrice';
  static const rehabBudget = 'rehabBudget';
  static const closingCostBuyPercent = 'closingCostBuyPercent';
  static const closingCostBuyFixed = 'closingCostBuyFixed';
  static const holdMonths = 'holdMonths';
  static const rentMonthlyTotal = 'rentMonthlyTotal';
  static const otherIncomeMonthly = 'otherIncomeMonthly';
  static const vacancyPercent = 'vacancyPercent';
  static const propertyTaxMonthly = 'propertyTaxMonthly';
  static const insuranceMonthly = 'insuranceMonthly';
  static const utilitiesMonthly = 'utilitiesMonthly';
  static const hoaMonthly = 'hoaMonthly';
  static const managementPercent = 'managementPercent';
  static const maintenancePercent = 'maintenancePercent';
  static const capexPercent = 'capexPercent';
  static const otherExpensesMonthly = 'otherExpensesMonthly';
  static const financingMode = 'financingMode';
  static const downPaymentPercent = 'downPaymentPercent';
  static const loanAmount = 'loanAmount';
  static const interestRatePercent = 'interestRatePercent';
  static const termYears = 'termYears';
  static const appreciationPercent = 'appreciationPercent';
  static const rentGrowthPercent = 'rentGrowthPercent';
  static const expenseGrowthPercent = 'expenseGrowthPercent';
  static const saleCostPercent = 'saleCostPercent';
  static const closingCostSellPercent = 'closingCostSellPercent';
  static const sellAfterYears = 'sellAfterYears';
  static const arvOverride = 'arvOverride';
  static const rentOverride = 'rentOverride';
  static const valuationMode = 'valuationMode';
  static const exitCapRatePercent = 'exitCapRatePercent';
  static const stabilizedNoiMode = 'stabilizedNoiMode';
  static const stabilizedNoiManual = 'stabilizedNoiManual';
  static const stabilizedNoiAvgYears = 'stabilizedNoiAvgYears';
}
