/// The forms behind the rent components (LEASING-COMPONENTS-01).
///
/// One dialog for creating and for editing, in the shape `lease_form_dialog`
/// already established, because the two differ in exactly one place — and that
/// difference is a contract fact rather than styling:
///
///   * **The component type is chosen once.** `component_type` is immutable on
///     the table (a trigger refuses the change), because relabelling a row
///     would silently move money between categories in every past reading. So
///     editing shows the type as a fact.
///
/// Deliberately absent: the currency. The server reads it from the lease, so a
/// caller cannot introduce a mismatch, and a field the form cannot honour would
/// only invite one.
///
/// Also deliberately absent: a delete. A component is closed on a date, never
/// removed — what a tenant paid until March is a fact about March.
///
/// The validation here mirrors the server's constraints rather than replacing
/// them. The server is still the authority; this exists so an impossible entry
/// is refused where the reader can see the field, instead of after a round trip
/// that comes back as a sentence under the form.
library;

import 'package:flutter/material.dart';

import '../../../../../features/leasing_operations/domain/lease_component_dto.dart';
import '../../../../components/responsive_constraints.dart';
import 'lease_lifecycle.dart';

/// What the form collected. Mapped by the caller onto the create or the update
/// command; the form itself knows nothing about mutation ids or versions.
class LeaseComponentFormResult {
  const LeaseComponentFormResult({
    required this.componentType,
    required this.validFrom,
    required this.amount,
    required this.vatMode,
    this.validTo,
    this.vatRatePercent,
    this.note,
  });

  final LeaseComponentType componentType;
  final DateTime validFrom;
  final DateTime? validTo;
  final double amount;
  final LeaseComponentVatMode vatMode;
  final double? vatRatePercent;
  final String? note;
}

/// The five types a client may write. [LeaseComponentType.unknown] is not
/// offered: it only ever comes back from a newer server, and writing it back
/// would claim a classification this build did not make.
const List<LeaseComponentType> writableComponentTypes = <LeaseComponentType>[
  LeaseComponentType.baseRent,
  LeaseComponentType.serviceChargeAdvance,
  LeaseComponentType.heatingAdvance,
  LeaseComponentType.parking,
  LeaseComponentType.other,
];

String leaseComponentTypeLabel(LeaseComponentType type) => switch (type) {
  LeaseComponentType.baseRent => 'Grundmiete',
  LeaseComponentType.serviceChargeAdvance => 'Betriebskostenvorauszahlung',
  LeaseComponentType.heatingAdvance => 'Heizkostenvorauszahlung',
  LeaseComponentType.parking => 'Stellplatz',
  LeaseComponentType.other => 'Sonstiges',
  LeaseComponentType.unknown => 'Unbekannter Bestandteil',
};

String leaseComponentVatModeLabel(LeaseComponentVatMode mode) => switch (mode) {
  LeaseComponentVatMode.exempt => 'Ohne Umsatzsteuer',
  LeaseComponentVatMode.net => 'Netto (Steuer kommt hinzu)',
  LeaseComponentVatMode.gross => 'Brutto (Steuer enthalten)',
  LeaseComponentVatMode.unknown => 'Unbekannt',
};

Future<LeaseComponentFormResult?> showLeaseComponentFormDialog({
  required BuildContext context,
  required String currencyCode,
  LeaseComponentDto? existing,
  LeaseComponentType? initialType,
}) {
  return showDialog<LeaseComponentFormResult>(
    context: context,
    builder: (dialogContext) => _LeaseComponentForm(
      currencyCode: currencyCode,
      existing: existing,
      initialType: initialType,
    ),
  );
}

/// A StatefulWidget rather than a `StatefulBuilder` whose controllers are
/// disposed after `showDialog` returns.
///
/// That shorter pattern — which `lease_form_dialog` still uses — disposes the
/// controllers the moment the future completes, while the route's exit
/// animation is still rebuilding the subtree that reads them. Flutter catches
/// it with "A TextEditingController was used after being disposed"; the only
/// reason it is rarely seen is that a test which never completes the dialog
/// never reaches it. Owning the controllers here ties their lifetime to the
/// widget that uses them, which is what `dispose` is for.
class _LeaseComponentForm extends StatefulWidget {
  const _LeaseComponentForm({
    required this.currencyCode,
    this.existing,
    this.initialType,
  });

  final String currencyCode;
  final LeaseComponentDto? existing;
  final LeaseComponentType? initialType;

  @override
  State<_LeaseComponentForm> createState() => _LeaseComponentFormState();
}

class _LeaseComponentFormState extends State<_LeaseComponentForm> {
  late final TextEditingController _amount;
  late final TextEditingController _rate;
  late final TextEditingController _note;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late LeaseComponentType _type;
  late LeaseComponentVatMode _vatMode;
  late DateTime _validFrom;
  DateTime? _validTo;
  bool _termError = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amount = TextEditingController(text: existing?.amount.toString() ?? '');
    _rate = TextEditingController(
      text: existing?.vatRatePercent?.toString() ?? '',
    );
    _note = TextEditingController();

    var type = existing?.componentType ??
        widget.initialType ??
        LeaseComponentType.baseRent;
    if (!writableComponentTypes.contains(type)) {
      type = LeaseComponentType.other;
    }
    _type = type;

    var vatMode = existing?.vatMode ?? LeaseComponentVatMode.exempt;
    if (vatMode == LeaseComponentVatMode.unknown) {
      vatMode = LeaseComponentVatMode.exempt;
    }
    _vatMode = vatMode;

    _validFrom = existing?.validFrom ?? DateTime.now();
    _validTo = existing?.validTo;
  }

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final validTo = _validTo;
    if (validTo != null && validTo.isBefore(_validFrom)) {
      setState(() => _termError = true);
      return;
    }
    Navigator.of(context).pop(
      LeaseComponentFormResult(
        componentType: _type,
        validFrom: _validFrom,
        validTo: validTo,
        amount: parseComponentAmount(_amount.text) ?? 0,
        vatMode: _vatMode,
        vatRatePercent: _vatMode == LeaseComponentVatMode.exempt
            ? null
            : parseComponentAmount(_rate.text),
        note: _trimToNull(_note.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.existing;
    final validTo = _validTo;
    final termInvalid =
        _termError || (validTo != null && validTo.isBefore(_validFrom));

    return AlertDialog(
      key: const Key('lease-component-form'),
      title: Text(
        existing == null
            ? 'Mietbestandteil anlegen'
            : 'Mietbestandteil bearbeiten',
      ),
      content: SizedBox(
        width: ResponsiveConstraints.dialogWidth(context, maxWidth: 520),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (existing == null)
                  DropdownButtonFormField<LeaseComponentType>(
                    key: const Key('lease-component-type'),
                    value: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Art *'),
                    items: <DropdownMenuItem<LeaseComponentType>>[
                      for (final option in writableComponentTypes)
                        DropdownMenuItem<LeaseComponentType>(
                          value: option,
                          child: Text(leaseComponentTypeLabel(option)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _type = value ?? _type),
                  )
                else
                  _Fact(
                    label: 'Art',
                    value: leaseComponentTypeLabel(_type),
                    // Not a disabled field: a greyed-out control invites the
                    // reader to look for the way to enable it.
                    hint: 'Die Art eines Bestandteils ist unveränderlich. '
                        'Ein anderer Bestandteil ist ein neuer Eintrag.',
                  ),
                const SizedBox(height: 8),
                _Fact(
                  label: 'Währung',
                  value: widget.currencyCode,
                  hint: 'Übernimmt der Vertrag.',
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('lease-component-amount'),
                  controller: _amount,
                  decoration: InputDecoration(
                    labelText: 'Betrag pro Monat *',
                    suffixText: widget.currencyCode,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    final parsed = parseComponentAmount(value ?? '');
                    if (parsed == null) {
                      return 'Bitte einen Betrag eingeben.';
                    }
                    if (parsed < 0) {
                      // Mirrors the CHECK. A reduction is a lower amount for a
                      // period, not a negative line — two rows that net out
                      // would make "the rent" depend on which ones you summed.
                      return 'Ein Bestandteil ist nie negativ. Eine Minderung '
                          'ist ein kleinerer Betrag für einen Zeitraum.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                LeaseDateField(
                  label: 'Gültig ab *',
                  value: _validFrom,
                  onChanged: (value) => setState(() {
                    _validFrom = value ?? _validFrom;
                    _termError = false;
                  }),
                ),
                const SizedBox(height: 8),
                LeaseDateField(
                  label: 'Gültig bis',
                  value: _validTo,
                  onChanged: (value) => setState(() {
                    _validTo = value;
                    _termError = false;
                  }),
                ),
                if (termInvalid)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Das Ende liegt vor dem Beginn.',
                      key: const Key('lease-component-term-error'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  )
                else if (_validTo == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Ohne Enddatum läuft der Bestandteil weiter. Das ist '
                      'der Normalfall.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<LeaseComponentVatMode>(
                  key: const Key('lease-component-vat-mode'),
                  value: _vatMode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Umsatzsteuer *'),
                  items: <DropdownMenuItem<LeaseComponentVatMode>>[
                    for (final option in const <LeaseComponentVatMode>[
                      LeaseComponentVatMode.exempt,
                      LeaseComponentVatMode.net,
                      LeaseComponentVatMode.gross,
                    ])
                      DropdownMenuItem<LeaseComponentVatMode>(
                        value: option,
                        child: Text(leaseComponentVatModeLabel(option)),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _vatMode = value ?? _vatMode),
                ),
                if (_vatMode != LeaseComponentVatMode.exempt) ...<Widget>[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('lease-component-vat-rate'),
                    controller: _rate,
                    decoration: const InputDecoration(
                      labelText: 'Steuersatz *',
                      suffixText: '%',
                      // The rate belongs to the period, not to the lease: an
                      // option under § 9 UStG, or a statutory change, starts a
                      // new period rather than editing an old one.
                      helperText: 'Gilt für diesen Zeitraum.',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      final parsed = parseComponentAmount(value ?? '');
                      if (parsed == null) {
                        // Mirrors the CHECK, and the reason it exists: a net
                        // amount without a rate cannot be turned into a gross
                        // figure, so storing it would only look like
                        // information.
                        return 'Ohne Steuersatz lässt sich der Betrag nicht '
                            'umrechnen.';
                      }
                      if (parsed < 0 || parsed > 100) {
                        return 'Zwischen 0 und 100.';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('lease-component-note'),
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Notiz',
                    helperText: 'Warum dieser Betrag, für den Nächsten.',
                  ),
                  maxLines: 2,
                  maxLength: 2000,
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
          key: const Key('lease-component-submit'),
          onPressed: _submit,
          child: Text(existing == null ? 'Anlegen' : 'Speichern'),
        ),
      ],
    );
  }
}

/// Ends a component on a date.
///
/// Its own dialog rather than "edit and set an end date", because the two are
/// different events and the audit trail records them differently — a year later
/// "beendet am 30. April" and "Enddatum geändert" read differently, and only
/// one of them is what happened.
Future<DateTime?> showLeaseComponentCloseDialog({
  required BuildContext context,
  required LeaseComponentDto component,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) => _LeaseComponentClose(component: component),
  );
}

class _LeaseComponentClose extends StatefulWidget {
  const _LeaseComponentClose({required this.component});

  final LeaseComponentDto component;

  @override
  State<_LeaseComponentClose> createState() => _LeaseComponentCloseState();
}

class _LeaseComponentCloseState extends State<_LeaseComponentClose> {
  DateTime _validTo = DateTime.now();
  bool _error = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('lease-component-close'),
      title: const Text('Bestandteil beenden'),
      content: SizedBox(
        width: ResponsiveConstraints.dialogWidth(context, maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Der Bestandteil bleibt erhalten und endet an diesem Tag. '
              'Gelöscht wird nichts — was bis dahin gezahlt wurde, ist eine '
              'Tatsache über diesen Zeitraum.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            LeaseDateField(
              label: 'Ende *',
              value: _validTo,
              onChanged: (value) => setState(() {
                _validTo = value ?? _validTo;
                _error = false;
              }),
            ),
            if (_error)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Das Ende liegt vor dem Beginn '
                  '(${formatLeaseDate(widget.component.validFrom)}).',
                  key: const Key('lease-component-close-error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('lease-component-close-submit'),
          onPressed: () {
            if (_validTo.isBefore(widget.component.validFrom)) {
              setState(() => _error = true);
              return;
            }
            Navigator.of(context).pop(_validTo);
          },
          child: const Text('Beenden'),
        ),
      ],
    );
  }
}

/// Accepts a comma as the decimal separator, because a German keyboard produces
/// one and a form that silently rejects it looks broken rather than strict.
double? parseComponentAmount(String value) {
  final trimmed = value.trim().replaceAll(',', '.');
  if (trimmed.isEmpty) {
    return null;
  }
  return double.tryParse(trimmed);
}

String? _trimToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// A value the form shows but cannot change, with the reason next to it.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(labelText: label, helperText: hint),
      child: Text(value, style: theme.textTheme.bodyMedium),
    );
  }
}
