/// Creating or changing an allocation key (`COST-POOLS-ALLOCATION-KEYS-01`,
/// P-2b).
///
/// **The explanation is a required field with no default.** `DEC-014` model
/// consequence 2: the Verteilerschlüssel with its explanation is one of the
/// four Mindestangaben an operating-cost statement is formally void without —
/// which costs the whole claim rather than a correction. So the form says why
/// it is asking, rather than presenting an empty box that could be skipped.
///
/// **A basis with no data says so while it is being chosen**, not after the
/// key is saved. Four of the seven have no store in this schema; the dropdown
/// labels them and the form shows what will happen — the key records the
/// intent and will report itself unresolvable until the data exists. The
/// alternative, which the legacy implementation took, was to fall through to
/// area and produce a plausible number.
///
/// The form owns its controllers: a dialog's exit animation keeps building the
/// subtree after the pop.
library;

import 'package:flutter/material.dart';

import '../../../features/finance_ledger/domain/cost_allocation_dto.dart';
import '../../../features/finance_ledger/domain/cost_pool_dto.dart';
import '../../components/nx_notice.dart';
import '../../theme/app_theme.dart';
import 'cost_pool_dialog.dart' show PropertyPicker;

class AllocationKeyFormResult {
  const AllocationKeyFormResult({
    required this.propertyId,
    required this.basis,
    required this.explanation,
    required this.validFrom,
    this.financeAccountId,
    this.costPoolId,
    this.validTo,
    this.note,
  });

  final String propertyId;
  final AllocationBasis basis;
  final String explanation;
  final DateTime validFrom;
  final DateTime? validTo;
  final String? financeAccountId;
  final String? costPoolId;
  final String? note;
}

String allocationBasisLabel(AllocationBasis basis) => switch (basis) {
  AllocationBasis.areaSqm => 'Wohnfläche (Summe der Einheitsflächen)',
  AllocationBasis.unitCount => 'Anzahl Einheiten',
  AllocationBasis.direct => 'Direktzuordnung (keine Verteilung)',
  AllocationBasis.fixedShare => 'Fester Anteil (noch keine Datenbasis)',
  AllocationBasis.persons => 'Personenzahl (noch keine Datenbasis)',
  AllocationBasis.coOwnershipShare =>
    'Miteigentumsanteil (noch keine Datenbasis)',
  AllocationBasis.consumption => 'Verbrauch (Zähler folgen mit P-4)',
  AllocationBasis.unknown => 'Unbekannter Maßstab',
};

/// Whether this build knows of any store behind the basis. Stated here as well
/// as on the server so the form can warn before the round trip; the server's
/// answer, carried on the saved key, is the one that counts.
bool allocationBasisHasStore(AllocationBasis basis) =>
    basis == AllocationBasis.areaSqm ||
    basis == AllocationBasis.unitCount ||
    basis == AllocationBasis.direct;

Future<AllocationKeyFormResult?> showAllocationKeyDialog(
  BuildContext context, {
  AllocationKeyDto? allocationKey,
  String? initialPropertyId,
  required List<CostPoolDto> pools,
  required List<CostAccountAllocationDto> accounts,
  required PropertyPicker pickProperty,
  required String Function(String propertyId) propertyLabel,
}) {
  return showDialog<AllocationKeyFormResult>(
    context: context,
    builder: (BuildContext dialogContext) => _AllocationKeyDialog(
      allocationKey: allocationKey,
      initialPropertyId: initialPropertyId,
      pools: pools,
      accounts: accounts,
      pickProperty: pickProperty,
      propertyLabel: propertyLabel,
    ),
  );
}

class _AllocationKeyDialog extends StatefulWidget {
  const _AllocationKeyDialog({
    required this.allocationKey,
    required this.initialPropertyId,
    required this.pools,
    required this.accounts,
    required this.pickProperty,
    required this.propertyLabel,
  });

  final AllocationKeyDto? allocationKey;
  final String? initialPropertyId;
  final List<CostPoolDto> pools;
  final List<CostAccountAllocationDto> accounts;
  final PropertyPicker pickProperty;
  final String Function(String propertyId) propertyLabel;

  @override
  State<_AllocationKeyDialog> createState() => _AllocationKeyDialogState();
}

class _AllocationKeyDialogState extends State<_AllocationKeyDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _explanation;
  late final TextEditingController _note;
  late AllocationBasis _basis;
  String? _propertyId;
  String? _accountId;
  String? _poolId;
  DateTime? _validFrom;
  DateTime? _validTo;

  @override
  void initState() {
    super.initState();
    final AllocationKeyDto? key = widget.allocationKey;
    _explanation = TextEditingController(text: key?.explanation ?? '');
    _note = TextEditingController(text: key?.note ?? '');
    _basis = key == null || key.basis == AllocationBasis.unknown
        ? AllocationBasis.areaSqm
        : key.basis;
    _propertyId = key?.propertyId ?? widget.initialPropertyId;
    _accountId = key?.financeAccountId;
    _poolId = key?.costPoolId;
    _validFrom = key?.validFrom;
    _validTo = key?.validTo;
  }

  @override
  void dispose() {
    _explanation.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only pools this key could actually name: a pool belonging to another
    // property would be refused, and offering it is offering a refusal.
    final List<CostPoolDto> selectablePools = widget.pools
        .where(
          (CostPoolDto pool) =>
              pool.propertyId == null || pool.propertyId == _propertyId,
        )
        .toList(growable: false);

    return AlertDialog(
      key: const Key('allocation-key-dialog'),
      title: Text(
        widget.allocationKey == null
            ? 'Umlageschlüssel anlegen'
            : 'Umlageschlüssel ändern',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Objekt',
                    errorText: _propertyId == null
                        ? 'Ein Umlageschlüssel gilt je Objekt.'
                        : null,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _propertyId == null
                              ? 'Kein Objekt gewählt'
                              : widget.propertyLabel(_propertyId!),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(
                        key: const Key('allocation-key-pick-property'),
                        onPressed: _pickProperty,
                        child: const Text('Wählen'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  key: const Key('allocation-key-account'),
                  value: _accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kostenart',
                    helperText:
                        'Ohne Angabe gilt der Schlüssel für jede Kostenart, '
                        'die keinen eigenen hat.',
                  ),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      child: Text('Alle übrigen Kostenarten'),
                    ),
                    for (final CostAccountAllocationDto account
                        in widget.accounts)
                      DropdownMenuItem<String?>(
                        value: account.financeAccountId,
                        child: Text('${account.code} · ${account.name}'),
                      ),
                  ],
                  onChanged: (String? value) =>
                      setState(() => _accountId = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  key: const Key('allocation-key-pool'),
                  value: selectablePools.any(
                    (CostPoolDto pool) => pool.id == _poolId,
                  )
                      ? _poolId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kostenpool'),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(child: Text('Kein Pool')),
                    for (final CostPoolDto pool in selectablePools)
                      DropdownMenuItem<String?>(
                        value: pool.id,
                        child: Text('${pool.poolKey} · ${pool.name}'),
                      ),
                  ],
                  onChanged: (String? value) => setState(() => _poolId = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<AllocationBasis>(
                  key: const Key('allocation-key-basis'),
                  value: _basis,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Verteilungsmaßstab',
                  ),
                  items: <DropdownMenuItem<AllocationBasis>>[
                    for (final AllocationBasis basis in <AllocationBasis>[
                      AllocationBasis.areaSqm,
                      AllocationBasis.unitCount,
                      AllocationBasis.direct,
                      AllocationBasis.fixedShare,
                      AllocationBasis.persons,
                      AllocationBasis.coOwnershipShare,
                      AllocationBasis.consumption,
                    ])
                      DropdownMenuItem<AllocationBasis>(
                        value: basis,
                        child: Text(allocationBasisLabel(basis)),
                      ),
                  ],
                  onChanged: (AllocationBasis? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _basis = value);
                  },
                ),
                // Said while the choice is being made, not after the save.
                if (!allocationBasisHasStore(_basis)) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  NxNotice(
                    key: const Key('allocation-key-no-basis'),
                    message:
                        'Für diesen Maßstab gibt es in diesem Stand noch keine '
                        'Datenbasis. Der Schlüssel wird gespeichert und als '
                        'nicht auflösbar ausgewiesen — er rechnet nichts aus, '
                        'statt eine Zahl zu erfinden.',
                    kind: NxNoticeKind.warning,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('allocation-key-explanation'),
                  controller: _explanation,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Erläuterung',
                    helperText:
                        'Pflicht. Der Verteilerschlüssel mit Erläuterung '
                        'gehört zu den vier Mindestangaben, ohne die eine '
                        'Betriebskostenabrechnung formell unwirksam ist.',
                  ),
                  validator: (String? value) =>
                      (value ?? '').trim().isEmpty
                          ? 'Ohne Erläuterung ist die Abrechnung formell '
                                'unwirksam.'
                          : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _DateField(
                        fieldKey: const Key('allocation-key-valid-from'),
                        label: 'Gültig ab',
                        value: _validFrom,
                        errorText: _validFrom == null
                            ? 'Ein Beginn ist erforderlich.'
                            : null,
                        onPick: (DateTime picked) =>
                            setState(() => _validFrom = picked),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _DateField(
                        fieldKey: const Key('allocation-key-valid-to'),
                        label: 'Gültig bis',
                        value: _validTo,
                        emptyLabel: 'Offen',
                        errorText:
                            _validFrom != null &&
                                _validTo != null &&
                                _validTo!.isBefore(_validFrom!)
                            ? 'Das Ende liegt vor dem Beginn.'
                            : null,
                        onPick: (DateTime picked) =>
                            setState(() => _validTo = picked),
                        onClear: () => setState(() => _validTo = null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('allocation-key-note'),
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notiz'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('allocation-key-submit'),
          onPressed: _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  Future<void> _pickProperty() async {
    final String? chosen = await widget.pickProperty(context);
    if (chosen == null || !mounted) {
      return;
    }
    setState(() {
      _propertyId = chosen;
      // A pool belonging to the property that was just replaced would be
      // refused by the server. Dropped here rather than carried invisibly.
      final CostPoolDto? pool = widget.pools
          .where((CostPoolDto candidate) => candidate.id == _poolId)
          .cast<CostPoolDto?>()
          .firstWhere((CostPoolDto? candidate) => true, orElse: () => null);
      if (pool != null &&
          pool.propertyId != null &&
          pool.propertyId != chosen) {
        _poolId = null;
      }
    });
  }

  void _submit() {
    final bool formValid = _form.currentState?.validate() ?? false;
    final bool datesValid =
        _validFrom != null &&
        (_validTo == null || !_validTo!.isBefore(_validFrom!));
    if (!formValid || _propertyId == null || !datesValid) {
      // The property and the dates live outside the Form, so their errors are
      // surfaced by re-rendering rather than by validate().
      setState(() {});
      return;
    }
    Navigator.of(context).pop(
      AllocationKeyFormResult(
        propertyId: _propertyId!,
        basis: _basis,
        explanation: _explanation.text.trim(),
        validFrom: _validFrom!,
        validTo: _validTo,
        financeAccountId: _accountId,
        costPoolId: _poolId,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onPick,
    this.emptyLabel = 'Nicht gewählt',
    this.errorText,
    this.onClear,
  });

  final Key fieldKey;
  final String label;
  final DateTime? value;
  final String emptyLabel;
  final String? errorText;
  final ValueChanged<DateTime> onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(labelText: label, errorText: errorText),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              value == null ? emptyLabel : _formatDate(value!),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (value != null && onClear != null)
            IconButton(
              tooltip: 'Zurücksetzen',
              onPressed: onClear,
              icon: const Icon(Icons.clear, size: 18),
            ),
          TextButton(
            key: fieldKey,
            onPressed: () async {
              final DateTime now = DateTime.now();
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime(now.year, now.month, now.day),
                firstDate: DateTime(now.year - 20),
                lastDate: DateTime(now.year + 20),
              );
              if (picked != null) {
                onPick(DateTime(picked.year, picked.month, picked.day));
              }
            },
            child: const Text('Wählen'),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final String day = value.day.toString().padLeft(2, '0');
  final String month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}
