/// Classifying one cost account (`COST-ALLOCATION-RULES-01`, P-2a).
///
/// **A HeizkostenV position offers only the performance principle.** Not a
/// warning after the fact and not a disabled option: turning the HeizkostenV
/// switch on replaces the choice, because BGH VIII ZR 156/11 leaves none and a
/// greyed-out alternative invites asking why it is greyed out.
///
/// **Turning off "apportionable" clears the principle.** A cost that is not
/// passed on has no settlement principle to state, and the server refuses the
/// pair — so the form does not let the reader assemble a refusal.
///
/// The form owns its controllers: a dialog's exit animation keeps building the
/// subtree after the pop.
library;

import 'package:flutter/material.dart';

import '../../../features/finance_ledger/domain/cost_allocation_dto.dart';
import '../../theme/app_theme.dart';

class CostAllocationFormResult {
  const CostAllocationFormResult({
    required this.allocatable,
    required this.underHeatingCostRegulation,
    this.settlementPrinciple,
    this.betrkvPosition,
    this.note,
  });

  final bool allocatable;
  final bool underHeatingCostRegulation;
  final CostSettlementPrinciple? settlementPrinciple;
  final String? betrkvPosition;
  final String? note;
}

Future<CostAllocationFormResult?> showCostAllocationDialog(
  BuildContext context, {
  required CostAccountAllocationDto account,
  String? initialBetrkvPosition,
  bool? initialUnderHeatingCostRegulation,
}) {
  return showDialog<CostAllocationFormResult>(
    context: context,
    builder: (BuildContext dialogContext) => _CostAllocationDialog(
      account: account,
      initialBetrkvPosition: initialBetrkvPosition,
      initialUnderHeatingCostRegulation: initialUnderHeatingCostRegulation,
    ),
  );
}

class _CostAllocationDialog extends StatefulWidget {
  const _CostAllocationDialog({
    required this.account,
    this.initialBetrkvPosition,
    this.initialUnderHeatingCostRegulation,
  });

  final CostAccountAllocationDto account;

  /// Pre-filled when the account was just adopted from the § 2 BetrKV
  /// catalogue. This is the step that records *which* position it is — the
  /// creation before it wrote only the account row.
  final String? initialBetrkvPosition;
  final bool? initialUnderHeatingCostRegulation;

  @override
  State<_CostAllocationDialog> createState() => _CostAllocationDialogState();
}

class _CostAllocationDialogState extends State<_CostAllocationDialog> {
  late final TextEditingController _betrkv;
  late final TextEditingController _note;
  late bool _allocatable;
  late bool _heating;
  CostSettlementPrinciple? _principle;

  @override
  void initState() {
    super.initState();
    final CostAllocationRuleDto? rule = widget.account.rule;
    _betrkv = TextEditingController(
      text: rule?.betrkvPosition ?? widget.initialBetrkvPosition ?? '',
    );
    _note = TextEditingController(text: rule?.note ?? '');
    // A BetrKV position is by definition a cost the tenant may be charged, so
    // an adoption starts from "apportionable" — and the reader confirms it
    // like everything else on this form.
    _allocatable =
        rule?.allocatable ?? (widget.initialBetrkvPosition != null);
    _heating =
        rule?.underHeatingCostRegulation ??
        widget.initialUnderHeatingCostRegulation ??
        false;
    // An unrecognised principle from a newer server is not carried into the
    // form: the command layer refuses to write it back, so offering it here
    // would build a submission that cannot succeed.
    _principle = rule?.settlementPrinciple == CostSettlementPrinciple.unknown
        ? null
        : rule?.settlementPrinciple;
  }

  @override
  void dispose() {
    _betrkv.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      key: const Key('cost-allocation-dialog'),
      title: Text('${widget.account.code} · ${widget.account.name}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SwitchListTile(
                key: const Key('cost-allocation-allocatable'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Auf Mieter umlagefähig'),
                value: _allocatable,
                onChanged: (bool value) => setState(() {
                  _allocatable = value;
                  if (!value) {
                    // A cost that is not passed on has no principle, and the
                    // HeizkostenV is about apportioning. Cleared here so the
                    // form cannot assemble a state the server refuses.
                    _principle = null;
                    _heating = false;
                  }
                }),
              ),
              if (_allocatable) ...<Widget>[
                SwitchListTile(
                  key: const Key('cost-allocation-heating'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Position nach HeizkostenV'),
                  subtitle: const Text(
                    'Dann gilt zwingend das Leistungsprinzip '
                    '(BGH VIII ZR 156/11).',
                  ),
                  value: _heating,
                  onChanged: (bool value) => setState(() {
                    _heating = value;
                    if (value) {
                      _principle = CostSettlementPrinciple.performance;
                    }
                  }),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (_heating)
                  // No choice offered, because there is none. A disabled
                  // dropdown would invite asking why it is disabled.
                  Text(
                    'Abrechnungsprinzip: Leistungsprinzip',
                    key: const Key('cost-allocation-principle-fixed'),
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  DropdownButtonFormField<CostSettlementPrinciple>(
                    key: const Key('cost-allocation-principle'),
                    value: _principle,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Abrechnungsprinzip',
                    ),
                    items: const <DropdownMenuItem<CostSettlementPrinciple>>[
                      DropdownMenuItem<CostSettlementPrinciple>(
                        value: CostSettlementPrinciple.performance,
                        child: Text('Leistungsprinzip'),
                      ),
                      DropdownMenuItem<CostSettlementPrinciple>(
                        value: CostSettlementPrinciple.outflow,
                        child: Text('Abflussprinzip'),
                      ),
                    ],
                    onChanged: (CostSettlementPrinciple? value) =>
                        setState(() => _principle = value),
                  ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  key: const Key('cost-allocation-betrkv'),
                  controller: _betrkv,
                  decoration: const InputDecoration(
                    labelText: 'BetrKV-Position',
                    // Free text on purpose: the § 2 catalogue is one of the
                    // seven points DEC-014 records as source-contradictory.
                    helperText: 'Freitext — z. B. § 2 Nr. 4 BetrKV.',
                  ),
                ),
              ],
              TextFormField(
                key: const Key('cost-allocation-note'),
                controller: _note,
                decoration: const InputDecoration(labelText: 'Notiz'),
                maxLines: 3,
                minLines: 1,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('cost-allocation-save'),
          // Disabled rather than refused: an apportionable cost needs a
          // principle, and there is nothing to explain about a save that
          // cannot be made yet.
          onPressed: _allocatable && _principle == null ? null : _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      CostAllocationFormResult(
        allocatable: _allocatable,
        underHeatingCostRegulation: _heating,
        settlementPrinciple: _allocatable ? _principle : null,
        betrkvPosition: _allocatable && _betrkv.text.trim().isNotEmpty
            ? _betrkv.text.trim()
            : null,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
  }
}
