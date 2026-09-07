/// Recording one unit's basis figure (`UNIT-BASIS-VALUES-01`, P-2c).
///
/// **The convention is a required field and the form says why.** No counting
/// rule is agreed for any of the three bases this store holds — `DEC-014`
/// decides none of them and lists none as contested — so a figure that does
/// not say how it was measured is one nobody can check, and two figures
/// measured differently cannot be added. The field is prefilled from what the
/// other units already state, so the ordinary case converges on one wording
/// instead of several typed slightly differently.
///
/// **Zero is offered plainly.** A unit with nobody in it is a real answer and
/// must not be entered as "leave it blank" — blank means unrecorded, which is
/// what makes the whole basis unresolvable.
///
/// **The dialog owns the submit.** It stays open while the command runs and
/// while it is refused, keeps what was typed, and puts the server's message on
/// the field the server named.
library;

import 'package:flutter/material.dart';

import '../../../features/finance_ledger/application/cost_pool_controller.dart'
    show CostPoolActionFailure;
import '../../../features/finance_ledger/domain/cost_pool_dto.dart';
import '../../components/nx_notice.dart';
import '../../theme/app_theme.dart';

class UnitBasisValueFormResult {
  const UnitBasisValueFormResult({
    required this.value,
    required this.convention,
    required this.validFrom,
    this.validTo,
    this.note,
  });

  final num value;
  final String convention;
  final DateTime validFrom;
  final DateTime? validTo;
  final String? note;
}

typedef UnitBasisValueSubmit =
    Future<CostPoolActionFailure?> Function(UnitBasisValueFormResult result);

/// What the figure means, per basis. Shown as the field's helper text so the
/// person typing knows what unit they are in.
String unitBasisValueHint(AllocationBasis basis) => switch (basis) {
  AllocationBasis.persons =>
    'Anzahl Personen. Wie gezählt wird, steht in der Konvention.',
  AllocationBasis.coOwnershipShare =>
    'Miteigentumsanteil, so wie er in der Teilungserklärung steht — z. B. '
        '235 von 1000. Der Nenner ergibt sich aus der Summe aller Einheiten.',
  AllocationBasis.fixedShare =>
    'Fester Anteil oder Gewicht. Wird nicht normiert: die Summe aller '
        'Einheiten bildet den Nenner.',
  _ => 'Zahlenwert.',
};

Future<bool?> showUnitBasisValueDialog(
  BuildContext context, {
  required UnitBasisRowDto row,
  required AllocationBasis basis,
  required UnitBasisValueSubmit onSubmit,
  String? suggestedConvention,
  DateTime? defaultValidFrom,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => _UnitBasisValueDialog(
      row: row,
      basis: basis,
      onSubmit: onSubmit,
      suggestedConvention: suggestedConvention,
      defaultValidFrom: defaultValidFrom,
    ),
  );
}

class _UnitBasisValueDialog extends StatefulWidget {
  const _UnitBasisValueDialog({
    required this.row,
    required this.basis,
    required this.onSubmit,
    required this.suggestedConvention,
    required this.defaultValidFrom,
  });

  final UnitBasisRowDto row;
  final AllocationBasis basis;
  final UnitBasisValueSubmit onSubmit;
  final String? suggestedConvention;
  final DateTime? defaultValidFrom;

  @override
  State<_UnitBasisValueDialog> createState() => _UnitBasisValueDialogState();
}

class _UnitBasisValueDialogState extends State<_UnitBasisValueDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _value;
  late final TextEditingController _convention;
  late final TextEditingController _note;
  DateTime? _validFrom;
  DateTime? _validTo;

  bool _submitting = false;
  String? _failureMessage;
  String? _failureField;

  @override
  void initState() {
    super.initState();
    final UnitBasisValueDto? existing = widget.row.value;
    _value = TextEditingController(
      text: existing == null ? '' : _plain(existing.value),
    );
    _convention = TextEditingController(
      text: existing?.convention ?? widget.suggestedConvention ?? '',
    );
    _note = TextEditingController(text: existing?.note ?? '');
    _validFrom =
        existing?.validFrom ??
        widget.defaultValidFrom ??
        _today();
    _validTo = existing?.validTo;
  }

  @override
  void dispose() {
    _value.dispose();
    _convention.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('unit-basis-value-dialog'),
      title: Text('${widget.row.unitCode} — Basiswert'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_failureMessage != null) ...<Widget>[
                  NxNotice(
                    key: const Key('unit-basis-value-dialog-failure'),
                    message: _failureMessage!,
                    kind: NxNoticeKind.error,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (widget.row.areaSqm != null) ...<Widget>[
                  Text(
                    'Wohnfläche dieser Einheit: '
                    '${_plain(widget.row.areaSqm!)} m²',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TextFormField(
                  key: const Key('unit-basis-value-amount'),
                  controller: _value,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Wert',
                    helperText: unitBasisValueHint(widget.basis),
                    helperMaxLines: 3,
                    errorText: _errorFor('value'),
                  ),
                  validator: (String? raw) {
                    final String text = (raw ?? '').trim().replaceAll(',', '.');
                    if (text.isEmpty) {
                      return 'Ein Wert ist erforderlich. Leer heißt nicht '
                          'erfasst, und das blockiert den Maßstab.';
                    }
                    final num? parsed = num.tryParse(text);
                    if (parsed == null) {
                      return 'Bitte eine Zahl eingeben.';
                    }
                    if (parsed < 0) {
                      return 'Ein negativer Wert ist keine kleinere Zahl, '
                          'sondern eine falsche. Null ist erlaubt.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('unit-basis-value-convention'),
                  controller: _convention,
                  enabled: !_submitting,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Konvention',
                    helperText:
                        'Pflicht. Für diesen Maßstab ist keine Zählregel '
                        'vereinbart — z. B. „Stichtag 1. Januar, gemeldete '
                        'Bewohner“ oder „Personenmonate über den '
                        'Abrechnungszeitraum“. Alle Einheiten müssen dieselbe '
                        'nennen, sonst ergibt ihre Summe keinen Nenner.',
                    helperMaxLines: 5,
                    errorText: _errorFor('convention'),
                  ),
                  validator: (String? raw) => (raw ?? '').trim().isEmpty
                      ? 'Ohne Konvention lässt sich die Zahl nicht prüfen.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _DateRow(
                  validFrom: _validFrom,
                  validTo: _validTo,
                  enabled: !_submitting,
                  fromError:
                      _errorFor('validFrom') ??
                      (_validFrom == null
                          ? 'Ein Beginn ist erforderlich.'
                          : null),
                  toError:
                      _errorFor('validTo') ??
                      (_validFrom != null &&
                              _validTo != null &&
                              _validTo!.isBefore(_validFrom!)
                          ? 'Das Ende liegt vor dem Beginn.'
                          : null),
                  onFrom: (DateTime picked) =>
                      setState(() => _validFrom = picked),
                  onTo: (DateTime picked) => setState(() => _validTo = picked),
                  onClearTo: () => setState(() => _validTo = null),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('unit-basis-value-note'),
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
          key: const Key('unit-basis-value-submit'),
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

  Future<void> _submit() async {
    setState(() {
      _failureMessage = null;
      _failureField = null;
    });
    final bool formValid = _form.currentState?.validate() ?? false;
    final bool datesValid =
        _validFrom != null &&
        (_validTo == null || !_validTo!.isBefore(_validFrom!));
    if (!formValid || !datesValid) {
      // The dates live outside the Form, so their errors are surfaced by
      // re-rendering rather than by validate().
      setState(() {});
      return;
    }

    setState(() => _submitting = true);
    final CostPoolActionFailure? failure = await widget.onSubmit(
      UnitBasisValueFormResult(
        value: num.parse(_value.text.trim().replaceAll(',', '.')),
        convention: _convention.text.trim(),
        validFrom: _validFrom!,
        validTo: _validTo,
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

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.validFrom,
    required this.validTo,
    required this.enabled,
    required this.onFrom,
    required this.onTo,
    required this.onClearTo,
    this.fromError,
    this.toError,
  });

  final DateTime? validFrom;
  final DateTime? validTo;
  final bool enabled;
  final String? fromError;
  final String? toError;
  final ValueChanged<DateTime> onFrom;
  final ValueChanged<DateTime> onTo;
  final VoidCallback onClearTo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget from = _DateField(
          fieldKey: const Key('unit-basis-value-valid-from'),
          label: 'Gültig ab',
          value: validFrom,
          enabled: enabled,
          errorText: fromError,
          onPick: onFrom,
        );
        final Widget to = _DateField(
          fieldKey: const Key('unit-basis-value-valid-to'),
          label: 'Gültig bis',
          value: validTo,
          enabled: enabled,
          emptyLabel: 'Offen',
          errorText: toError,
          onPick: onTo,
          onClear: onClearTo,
        );
        // Stacked below the tablet breakpoint: two date fields side by side
        // leave a phone roughly 86 px per column, which is less than the
        // controls inside them need.
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[from, const SizedBox(height: AppSpacing.sm), to],
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
    );
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
    // Anchored on the value, not on today: a figure backdated more than twenty
    // years would otherwise open a picker whose firstDate is after its
    // initialDate, which is an assertion rather than a message.
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

DateTime _today() {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _formatDate(DateTime value) {
  final String day = value.day.toString().padLeft(2, '0');
  final String month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

String _plain(num value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toString();
}
