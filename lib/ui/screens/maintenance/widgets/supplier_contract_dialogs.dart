/// Creating, editing and ending a supplier contract
/// (`SUPPLIER-CONTRACTS-01`, P-3).
///
/// Three dialogs because there are three events, and the third is not a
/// variant of the second: ending a contract demands a reason and stamps a
/// date, and letting the terminal state be reached through a field edit is how
/// "why did we drop them" becomes unanswerable two years later.
///
/// **No deadline field anywhere.** The form takes the *terms* — end date,
/// notice period in days, renewal — and the deadline is computed by the server
/// against the date it is read for. Offering a deadline input would invite
/// somebody to type one that then disagrees with the arithmetic.
///
/// Each form owns its controllers: a dialog's exit animation keeps building
/// the subtree after the pop, and controllers freed by the caller are read
/// after disposal.
library;

import 'package:flutter/material.dart';

import '../../../../features/contacts_parties/application/contractors_controller.dart';
import '../../../../features/contacts_parties/domain/supplier_contract_dto.dart';
import '../../../theme/app_theme.dart';

/// Opens the create form. Null means cancelled.
Future<CreateSupplierContractDraft?> showSupplierContractCreateDialog(
  BuildContext context,
) {
  return showDialog<CreateSupplierContractDraft>(
    context: context,
    builder: (BuildContext dialogContext) => const _SupplierContractForm(),
  );
}

/// Opens the edit form. Returns a patch: a field not touched is absent, a
/// field emptied is present with a null. Null means cancelled or unchanged.
Future<Map<String, Object?>?> showSupplierContractEditDialog(
  BuildContext context, {
  required SupplierContractDto contract,
}) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _SupplierContractEditForm(contract: contract),
  );
}

/// Asks for the reason a contract ended. Null means cancelled — and there is
/// no way to confirm without a reason, which is the point.
Future<String?> showSupplierContractEndDialog(
  BuildContext context, {
  required SupplierContractDto contract,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _SupplierContractEndForm(contract: contract),
  );
}

DateTime? parseContractDate(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : DateTime.tryParse(trimmed);
}

String formatContractDateField(DateTime? value) {
  if (value == null) {
    return '';
  }
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

int? parseContractInt(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : int.tryParse(trimmed);
}

double? parseContractAmount(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return double.tryParse(trimmed.replaceAll(',', '.'));
}

class _SupplierContractForm extends StatefulWidget {
  const _SupplierContractForm();

  @override
  State<_SupplierContractForm> createState() => _SupplierContractFormState();
}

class _SupplierContractFormState extends State<_SupplierContractForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _type = TextEditingController();
  final TextEditingController _start = TextEditingController();
  final TextEditingController _end = TextEditingController();
  final TextEditingController _notice = TextEditingController();
  final TextEditingController _renewalMonths = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _currency = TextEditingController();
  final TextEditingController _scope = TextEditingController();
  bool _autoRenew = false;

  @override
  void dispose() {
    _title.dispose();
    _type.dispose();
    _start.dispose();
    _end.dispose();
    _notice.dispose();
    _renewalMonths.dispose();
    _value.dispose();
    _currency.dispose();
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('supplier-contract-form'),
      title: const Text('Vertrag anlegen'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  key: const Key('supplier-contract-title'),
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Bezeichnung'),
                  validator: _required,
                ),
                TextFormField(
                  key: const Key('supplier-contract-type'),
                  controller: _type,
                  decoration: const InputDecoration(
                    labelText: 'Art',
                    helperText: 'z. B. Wartung, Versorgung, Reinigung',
                  ),
                  validator: _required,
                ),
                TextFormField(
                  key: const Key('supplier-contract-start'),
                  controller: _start,
                  decoration: const InputDecoration(
                    labelText: 'Beginn (JJJJ-MM-TT)',
                  ),
                  validator: _requiredDate,
                ),
                TextFormField(
                  key: const Key('supplier-contract-end'),
                  controller: _end,
                  decoration: const InputDecoration(
                    labelText: 'Ende (JJJJ-MM-TT)',
                    helperText: 'Leer lassen heißt: unbefristet.',
                  ),
                  validator: _optionalDate,
                ),
                TextFormField(
                  key: const Key('supplier-contract-notice'),
                  controller: _notice,
                  decoration: const InputDecoration(
                    labelText: 'Kündigungsfrist (Tage)',
                    // The distinction the whole surface rests on.
                    helperText:
                        'Leer lassen heißt: keine Frist vereinbart — nicht '
                        'null Tage.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: _optionalInt,
                ),
                SwitchListTile(
                  key: const Key('supplier-contract-auto-renew'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Verlängert sich automatisch'),
                  value: _autoRenew,
                  onChanged: (bool value) => setState(() => _autoRenew = value),
                ),
                if (_autoRenew)
                  TextFormField(
                    key: const Key('supplier-contract-renewal-months'),
                    controller: _renewalMonths,
                    decoration: const InputDecoration(
                      labelText: 'Verlängerung um (Monate)',
                    ),
                    keyboardType: TextInputType.number,
                    // Required only while the switch is on: a renewal needs
                    // something to renew to, and the server refuses the pair
                    // without it.
                    validator: (String? value) {
                      final parsed = parseContractInt(value ?? '');
                      if (parsed == null || parsed <= 0) {
                        return 'Pflichtfeld bei automatischer Verlängerung';
                      }
                      return null;
                    },
                  ),
                TextFormField(
                  key: const Key('supplier-contract-value'),
                  controller: _value,
                  decoration: const InputDecoration(
                    labelText: 'Jahreswert',
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextFormField(
                  key: const Key('supplier-contract-currency'),
                  controller: _currency,
                  decoration: const InputDecoration(
                    labelText: 'Währung',
                    helperText: 'Pflicht, sobald ein Betrag erfasst ist.',
                  ),
                  validator: (String? value) {
                    final amount = parseContractAmount(_value.text);
                    final currency = value?.trim() ?? '';
                    if (amount != null && currency.length != 3) {
                      // An amount without a currency is not a figure. Refused
                      // here so the round trip is not spent on a certain
                      // refusal.
                      return 'Dreistelliger Code, z. B. EUR';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  key: const Key('supplier-contract-scope'),
                  controller: _scope,
                  decoration: const InputDecoration(labelText: 'Leistungsumfang'),
                  maxLines: 3,
                  minLines: 1,
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
          key: const Key('supplier-contract-save'),
          onPressed: _submit,
          child: const Text('Anlegen'),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      CreateSupplierContractDraft(
        title: _title.text.trim(),
        contractType: _type.text.trim(),
        startDate: DateTime.parse(_start.text.trim()),
        endDate: parseContractDate(_end.text),
        noticePeriodDays: parseContractInt(_notice.text),
        autoRenew: _autoRenew,
        renewalTermMonths: _autoRenew
            ? parseContractInt(_renewalMonths.text)
            : null,
        annualValue: parseContractAmount(_value.text),
        currencyCode: _currency.text.trim().isEmpty
            ? null
            : _currency.text.trim().toUpperCase(),
        scopeNote: _scope.text.trim().isEmpty ? null : _scope.text.trim(),
      ),
    );
  }
}

class _SupplierContractEditForm extends StatefulWidget {
  const _SupplierContractEditForm({required this.contract});

  final SupplierContractDto contract;

  @override
  State<_SupplierContractEditForm> createState() =>
      _SupplierContractEditFormState();
}

class _SupplierContractEditFormState extends State<_SupplierContractEditForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _end;
  late final TextEditingController _notice;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.contract.title);
    _end = TextEditingController(
      text: formatContractDateField(widget.contract.endDate),
    );
    _notice = TextEditingController(
      text: widget.contract.noticePeriodDays?.toString() ?? '',
    );
    _active = widget.contract.status == SupplierContractStatus.active;
  }

  @override
  void dispose() {
    _title.dispose();
    _end.dispose();
    _notice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('supplier-contract-edit-form'),
      title: const Text('Vertrag bearbeiten'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  key: const Key('supplier-contract-edit-title'),
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Bezeichnung'),
                  validator: _required,
                ),
                TextFormField(
                  key: const Key('supplier-contract-edit-end'),
                  controller: _end,
                  decoration: const InputDecoration(
                    labelText: 'Ende (JJJJ-MM-TT)',
                    helperText: 'Leer lassen heißt: unbefristet.',
                  ),
                  validator: _optionalDate,
                ),
                TextFormField(
                  key: const Key('supplier-contract-edit-notice'),
                  controller: _notice,
                  decoration: const InputDecoration(
                    labelText: 'Kündigungsfrist (Tage)',
                    helperText: 'Die Frist selbst rechnet der Server aus.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: _optionalInt,
                ),
                SwitchListTile(
                  key: const Key('supplier-contract-edit-active'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktiv'),
                  subtitle: const Text(
                    'Beenden ist eine eigene Handlung und verlangt einen '
                    'Grund.',
                  ),
                  value: _active,
                  onChanged: (bool value) => setState(() => _active = value),
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
          key: const Key('supplier-contract-edit-save'),
          onPressed: _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final changes = <String, Object?>{};
    void putIfChanged(String key, Object? current, Object? next) {
      if (current != next) {
        changes[key] = next;
      }
    }

    putIfChanged('title', widget.contract.title, _title.text.trim());
    putIfChanged(
      'end_date',
      formatContractDateField(widget.contract.endDate),
      _end.text.trim(),
    );
    if (changes.containsKey('end_date')) {
      changes['end_date'] = _end.text.trim().isEmpty ? null : _end.text.trim();
    }
    putIfChanged(
      'notice_period_days',
      widget.contract.noticePeriodDays,
      parseContractInt(_notice.text),
    );
    final wasActive = widget.contract.status == SupplierContractStatus.active;
    if (wasActive != _active) {
      // Only between draft and active. `ended` has its own command and the
      // server refuses it here.
      changes['status'] = _active ? 'active' : 'draft';
    }

    Navigator.of(context).pop(changes.isEmpty ? null : changes);
  }
}

class _SupplierContractEndForm extends StatefulWidget {
  const _SupplierContractEndForm({required this.contract});

  final SupplierContractDto contract;

  @override
  State<_SupplierContractEndForm> createState() =>
      _SupplierContractEndFormState();
}

class _SupplierContractEndFormState extends State<_SupplierContractEndForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('supplier-contract-end-form'),
      title: const Text('Vertrag beenden?'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '„${widget.contract.title}" wird beendet und bleibt in der '
                'Historie.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('supplier-contract-end-reason'),
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Grund',
                  helperText:
                      'Warum die Zusammenarbeit endet, will in zwei Jahren '
                      'jemand wissen.',
                ),
                maxLines: 3,
                minLines: 1,
                validator: _required,
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
          key: const Key('supplier-contract-end-confirm'),
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) {
              return;
            }
            Navigator.of(context).pop(_reason.text.trim());
          },
          child: const Text('Beenden'),
        ),
      ],
    );
  }
}

String? _required(String? value) =>
    (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null;

String? _requiredDate(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Pflichtfeld';
  }
  return DateTime.tryParse(trimmed) == null ? 'Datum im Format JJJJ-MM-TT' : null;
}

String? _optionalDate(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  return DateTime.tryParse(trimmed) == null ? 'Datum im Format JJJJ-MM-TT' : null;
}

String? _optionalInt(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  final parsed = int.tryParse(trimmed);
  if (parsed == null || parsed < 0) {
    return 'Ganze Zahl in Tagen';
  }
  if (parsed > 3650) {
    // The server's own typo guard, mirrored so the message arrives before the
    // round trip: a four-digit notice period is somebody who meant months.
    return 'Höchstens 3650 Tage — waren Monate gemeint?';
  }
  return null;
}
