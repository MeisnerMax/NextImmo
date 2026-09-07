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
/// **The dialog owns the submit.** It stays open while the command runs and
/// while it is refused, keeps everything the user typed, and puts the server's
/// message on the field the server named — an overlapping period, a pool that
/// has since been deactivated. A dialog that pops first and reports afterwards
/// has already thrown the input away.
///
/// The form owns its controllers: a dialog's exit animation keeps building the
/// subtree after the pop.
library;

import 'package:flutter/material.dart';

import '../../../features/finance_ledger/application/cost_pool_controller.dart';
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

/// Runs the command. Returns null on success, or why it was refused.
typedef AllocationKeySubmit =
    Future<CostPoolActionFailure?> Function(AllocationKeyFormResult result);

String allocationBasisLabel(AllocationBasis basis) => switch (basis) {
  AllocationBasis.areaSqm => 'Wohnfläche (Summe der Einheitsflächen)',
  AllocationBasis.unitCount => 'Anzahl Einheiten',
  AllocationBasis.direct => 'Direktzuordnung (keine Verteilung)',
  AllocationBasis.fixedShare => 'Fester Anteil (Werte je Einheit)',
  AllocationBasis.persons => 'Personenzahl (Werte je Einheit)',
  AllocationBasis.coOwnershipShare => 'Miteigentumsanteil (Werte je Einheit)',
  AllocationBasis.consumption => 'Verbrauch (Zähler folgen mit P-4)',
  AllocationBasis.unknown => 'Unbekannter Maßstab',
};

/// Whether this build knows of any store behind the basis.
///
/// `UNIT-BASIS-VALUES-01` (P-2c) gave the three per-unit bases one, so the
/// only basis left without any data behind it is consumption, whose meters
/// arrive with P-4. The three now warn about something different and weaker —
/// values exist as a concept and may not have been entered yet — which is
/// what [allocationBasisNeedsUnitValues] says. The server's answer, carried on
/// the saved key, remains the one that counts.
bool allocationBasisHasStore(AllocationBasis basis) =>
    basis != AllocationBasis.consumption &&
    basis != AllocationBasis.unknown;

/// Whether this basis is divided by figures somebody must enter per unit.
bool allocationBasisNeedsUnitValues(AllocationBasis basis) =>
    allocationBasisIsStoredPerUnit(basis);

Future<bool?> showAllocationKeyDialog(
  BuildContext context, {
  AllocationKeyDto? allocationKey,
  String? initialPropertyId,
  required List<CostPoolDto> pools,
  required List<CostAccountAllocationDto> accounts,
  required PropertyPicker pickProperty,
  required String Function(String propertyId) propertyLabel,
  required AllocationKeySubmit onSubmit,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => _AllocationKeyDialog(
      allocationKey: allocationKey,
      initialPropertyId: initialPropertyId,
      pools: pools,
      accounts: accounts,
      pickProperty: pickProperty,
      propertyLabel: propertyLabel,
      onSubmit: onSubmit,
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
    required this.onSubmit,
  });

  final AllocationKeyDto? allocationKey;
  final String? initialPropertyId;
  final List<CostPoolDto> pools;
  final List<CostAccountAllocationDto> accounts;
  final PropertyPicker pickProperty;
  final String Function(String propertyId) propertyLabel;
  final AllocationKeySubmit onSubmit;

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

  bool _submitting = false;
  String? _failureMessage;
  String? _failureField;

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
    // Only pools this key could actually name. A pool of another property is
    // refused by the server, and so is an inactive one — offering either is
    // offering a refusal. The pool the key already names stays in the list
    // even if it has since been deactivated, so editing something else about
    // the key does not silently drop it.
    final List<CostPoolDto> selectablePools = widget.pools
        .where(
          (CostPoolDto pool) =>
              pool.id == _poolId ||
              (pool.isActive &&
                  (pool.scope == CostPoolScope.portfolio ||
                      pool.propertyId == _propertyId)),
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
                if (_failureMessage != null) ...<Widget>[
                  NxNotice(
                    key: const Key('allocation-key-dialog-failure'),
                    message: _failureMessage!,
                    kind: NxNoticeKind.error,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Objekt',
                    errorText:
                        _errorFor('propertyId') ??
                        (_propertyId == null
                            ? 'Ein Umlageschlüssel gilt je Objekt.'
                            : null),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _propertyId == null
                              ? 'Kein Objekt gewählt'
                              : widget.propertyLabel(_propertyId!),
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        key: const Key('allocation-key-pick-property'),
                        onPressed: _submitting ? null : _pickProperty,
                        child: const Text('Wählen'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  key: const Key('allocation-key-account'),
                  // Guarded like the pool below. An id with no matching item
                  // trips DropdownButton's own assertion, which is how a form
                  // loses the value it was opened to show.
                  value:
                      widget.accounts.any(
                        (CostAccountAllocationDto account) =>
                            account.financeAccountId == _accountId,
                      )
                      ? _accountId
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Kostenart',
                    helperText: widget.accounts.isEmpty
                        ? 'Es sind noch keine Kostenarten angelegt.'
                        : 'Ohne Angabe gilt der Schlüssel für jede Kostenart, '
                              'die keinen eigenen hat.',
                    errorText: _errorFor('financeAccountId'),
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
                  onChanged: _submitting
                      ? null
                      : (String? value) => setState(() => _accountId = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  key: const Key('allocation-key-pool'),
                  value:
                      selectablePools.any(
                        (CostPoolDto pool) => pool.id == _poolId,
                      )
                      ? _poolId
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Kostenpool',
                    errorText: _errorFor('costPoolId'),
                  ),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(child: Text('Kein Pool')),
                    for (final CostPoolDto pool in selectablePools)
                      DropdownMenuItem<String?>(
                        value: pool.id,
                        child: Text(
                          pool.isActive
                              ? '${pool.poolKey} · ${pool.name}'
                              : '${pool.poolKey} · ${pool.name} (inaktiv)',
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (String? value) => setState(() => _poolId = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<AllocationBasis>(
                  key: const Key('allocation-key-basis'),
                  value: _basis,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Verteilungsmaßstab',
                    errorText: _errorFor('basis'),
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
                  onChanged: _submitting
                      ? null
                      : (AllocationBasis? value) {
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
                ] else if (allocationBasisNeedsUnitValues(_basis)) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  NxNotice(
                    key: const Key('allocation-key-needs-unit-values'),
                    message:
                        'Dieser Maßstab wird aus Werten je Einheit gebildet. '
                        'Solange nicht jede Einheit einen Wert hat — und alle '
                        'nach derselben Konvention ermittelt sind — weist der '
                        'Schlüssel sich als nicht auflösbar aus.',
                    kind: NxNoticeKind.info,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('allocation-key-explanation'),
                  controller: _explanation,
                  enabled: !_submitting,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Erläuterung',
                    helperText:
                        'Pflicht. Der Verteilerschlüssel mit Erläuterung '
                        'gehört zu den vier Mindestangaben, ohne die eine '
                        'Betriebskostenabrechnung formell unwirksam ist.',
                    errorText: _errorFor('explanation'),
                  ),
                  validator: (String? value) => (value ?? '').trim().isEmpty
                      ? 'Ohne Erläuterung ist die Abrechnung formell unwirksam.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                // Stacked below the tablet breakpoint rather than squeezed:
                // each date field carries a label, a value and two controls,
                // and two of them side by side leave a phone about 86 px per
                // column.
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final Widget from = _DateField(
                      fieldKey: const Key('allocation-key-valid-from'),
                      label: 'Gültig ab',
                      value: _validFrom,
                      enabled: !_submitting,
                      errorText:
                          _errorFor('validFrom') ??
                          (_validFrom == null
                              ? 'Ein Beginn ist erforderlich.'
                              : null),
                      onPick: (DateTime picked) =>
                          setState(() => _validFrom = picked),
                    );
                    final Widget to = _DateField(
                      fieldKey: const Key('allocation-key-valid-to'),
                      label: 'Gültig bis',
                      value: _validTo,
                      enabled: !_submitting,
                      emptyLabel: 'Offen',
                      errorText:
                          _errorFor('validTo') ??
                          (_validFrom != null &&
                                  _validTo != null &&
                                  _validTo!.isBefore(_validFrom!)
                              ? 'Das Ende liegt vor dem Beginn.'
                              : null),
                      onPick: (DateTime picked) =>
                          setState(() => _validTo = picked),
                      onClear: () => setState(() => _validTo = null),
                    );
                    if (constraints.maxWidth < 420) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          from,
                          const SizedBox(height: AppSpacing.sm),
                          to,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: from),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: to),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('allocation-key-note'),
                  controller: _note,
                  enabled: !_submitting,
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
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('allocation-key-submit'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Speichern'),
        ),
      ],
    );
  }

  String? _errorFor(String field) =>
      _failureField == field ? _failureMessage : null;

  Future<void> _pickProperty() async {
    final String? chosen = await widget.pickProperty(context);
    if (chosen == null || !mounted) {
      return;
    }
    setState(() {
      _propertyId = chosen;
      // A pool belonging to the property that was just replaced would be
      // refused by the server. Dropped here rather than carried invisibly.
      final Iterable<CostPoolDto> named = widget.pools.where(
        (CostPoolDto candidate) => candidate.id == _poolId,
      );
      final CostPoolDto? pool = named.isEmpty ? null : named.first;
      if (pool != null &&
          pool.scope != CostPoolScope.portfolio &&
          pool.propertyId != chosen) {
        _poolId = null;
      }
    });
  }

  Future<void> _submit() async {
    setState(() {
      _failureMessage = null;
      _failureField = null;
    });
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

    setState(() => _submitting = true);
    final CostPoolActionFailure? failure = await widget.onSubmit(
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
    if (!mounted) {
      return;
    }
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _failureMessage = failure.message;
      _failureField = failure.field;
    });
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onPick,
    this.enabled = true,
    this.emptyLabel = 'Nicht gewählt',
    this.errorText,
    this.onClear,
  });

  final Key fieldKey;
  final String label;
  final DateTime? value;
  final bool enabled;
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
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (value != null && onClear != null)
            Flexible(
              child: IconButton(
                tooltip: 'Zurücksetzen',
                visualDensity: VisualDensity.compact,
                onPressed: enabled ? onClear : null,
                icon: const Icon(Icons.clear, size: 18),
              ),
            ),
          Flexible(
            child: TextButton(
              key: fieldKey,
              onPressed: enabled ? () => _pick(context) : null,
              child: const Text('Wählen', overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime anchor = value ?? DateTime(now.year, now.month, now.day);
    // Anchored on the value, not on today. A key backdated to a lease start
    // more than twenty years ago would otherwise open a picker whose
    // firstDate is after its initialDate, which is an assertion, not a
    // validation message.
    final DateTime first = DateTime(
      (anchor.year < now.year ? anchor.year : now.year) - 20,
    );
    final DateTime last = DateTime(
      (anchor.year > now.year ? anchor.year : now.year) + 20,
    );
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: anchor,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      onPick(DateTime(picked.year, picked.month, picked.day));
    }
  }
}

String _formatDate(DateTime value) {
  final String day = value.day.toString().padLeft(2, '0');
  final String month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}
