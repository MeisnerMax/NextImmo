/// Booking one actual cost (`FINANCE-BOOKINGS-01`).
///
/// **This cannot be undone, and the form says so before it is submitted.**
/// There is no update, no delete and no reversal command on the server. A
/// mistake is answered by a second, negative booking — which is why the amount
/// accepts a sign and why the dialog explains that rather than pretending an
/// edit will be available later.
///
/// **The date must fall inside the chosen period.** The server refuses
/// otherwise, and so does this form, because a booking in the wrong period is
/// a wrong number in every figure downstream and nothing else would notice.
///
/// **A cost type nobody has classified can still be booked**, and the form
/// says what that costs: the amount lands in the ledger and stays out of every
/// service-charge statement until somebody decides whether it may be passed
/// on. Refusing it here would be worse — it would make the ledger wait on a
/// classification decision that belongs to a different person and a different
/// day.
library;

import 'package:flutter/material.dart';

import '../../../features/finance_ledger/application/cost_pool_controller.dart'
    show CostPoolActionFailure;
import '../../../features/finance_ledger/domain/cost_allocation_dto.dart';
import '../../../features/finance_ledger/domain/cost_pool_dto.dart';
import '../../../features/finance_ledger/domain/finance_booking_dto.dart';
import '../../components/nx_notice.dart';
import '../../theme/app_theme.dart';

class FinanceBookingFormResult {
  const FinanceBookingFormResult({
    required this.accountId,
    required this.bookedOn,
    required this.amount,
    required this.currencyCode,
    this.description,
  });

  final String accountId;
  final DateTime bookedOn;

  /// Signed: negative is a counter-booking.
  final num amount;
  final String currencyCode;
  final String? description;
}

typedef FinanceBookingSubmit =
    Future<CostPoolActionFailure?> Function(FinanceBookingFormResult result);

Future<bool?> showFinanceBookingDialog(
  BuildContext context, {
  required FinancePeriodDto period,
  required String propertyName,
  required List<CostAccountAllocationDto> accounts,
  required FinanceBookingSubmit onSubmit,
  String defaultCurrency = 'EUR',
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => _FinanceBookingDialog(
      period: period,
      propertyName: propertyName,
      accounts: accounts,
      onSubmit: onSubmit,
      defaultCurrency: defaultCurrency,
    ),
  );
}

class _FinanceBookingDialog extends StatefulWidget {
  const _FinanceBookingDialog({
    required this.period,
    required this.propertyName,
    required this.accounts,
    required this.onSubmit,
    required this.defaultCurrency,
  });

  final FinancePeriodDto period;
  final String propertyName;
  final List<CostAccountAllocationDto> accounts;
  final FinanceBookingSubmit onSubmit;
  final String defaultCurrency;

  @override
  State<_FinanceBookingDialog> createState() => _FinanceBookingDialogState();
}

class _FinanceBookingDialogState extends State<_FinanceBookingDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _description;
  String? _accountId;
  late DateTime _bookedOn;

  bool _submitting = false;
  String? _failureMessage;
  String? _failureField;

  /// Only the cost types a booking can actually name. The server refuses a
  /// retired account, so offering one would be offering a refusal.
  List<CostAccountAllocationDto> get _bookable => widget.accounts
      .where((CostAccountAllocationDto account) => account.isActive)
      .toList(growable: false);

  CostAccountAllocationDto? get _selected {
    for (final CostAccountAllocationDto account in _bookable) {
      if (account.financeAccountId == _accountId) {
        return account;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _currency = TextEditingController(text: widget.defaultCurrency);
    _description = TextEditingController();
    // The first day of the period the booking is going into: always inside
    // it, and the commonest correction is a day or two rather than a month.
    _bookedOn = DateTime(widget.period.fiscalYear, widget.period.periodMonth, 1);
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final CostAccountAllocationDto? selected = _selected;

    return AlertDialog(
      key: const Key('finance-booking-dialog'),
      title: Text('Buchung ${widget.period.label}'),
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
                    key: const Key('finance-booking-dialog-failure'),
                    message: _failureMessage!,
                    kind: NxNoticeKind.error,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Text(
                  '${widget.propertyName} · Periode ${widget.period.label}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  key: const Key('finance-booking-account'),
                  value: _bookable.any(
                    (CostAccountAllocationDto a) =>
                        a.financeAccountId == _accountId,
                  )
                      ? _accountId
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Kostenart',
                    helperText: _bookable.isEmpty
                        ? 'Es sind keine aktiven Kostenarten angelegt.'
                        : null,
                    errorText: _errorFor('account_id'),
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final CostAccountAllocationDto account in _bookable)
                      DropdownMenuItem<String>(
                        value: account.financeAccountId,
                        child: Text('${account.code} · ${account.name}'),
                      ),
                  ],
                  validator: (String? value) =>
                      value == null ? 'Eine Kostenart ist erforderlich.' : null,
                  onChanged: _submitting
                      ? null
                      : (String? value) => setState(() => _accountId = value),
                ),
                // Said at the moment of choosing, not after the settlement
                // fails to include the cost.
                if (selected != null && selected.rule == null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  const NxNotice(
                    key: Key('finance-booking-unclassified'),
                    message:
                        'Diese Kostenart ist noch nicht eingeordnet. Die '
                        'Buchung wird erfasst, bleibt aber aus jeder '
                        'Betriebskostenabrechnung heraus, bis entschieden ist, '
                        'ob sie umgelegt werden darf.',
                    kind: NxNoticeKind.warning,
                  ),
                ] else if (selected?.rule?.allocatable == false) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  const NxNotice(
                    key: Key('finance-booking-not-allocatable'),
                    message:
                        'Diese Kostenart ist als nicht umlagefähig eingeordnet '
                        '— die Buchung zählt zum Objektergebnis, nicht zur '
                        'Abrechnung.',
                    kind: NxNoticeKind.info,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        key: const Key('finance-booking-amount'),
                        controller: _amount,
                        enabled: !_submitting,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Betrag',
                          helperText:
                              'Komma als Dezimaltrennzeichen. Ein negativer '
                              'Betrag ist eine Gegenbuchung — die einzige '
                              'Korrektur, die es gibt.',
                          helperMaxLines: 3,
                          errorText: _errorFor('amount'),
                        ),
                        validator: (String? raw) => switch (parseGermanFigure(
                          raw ?? '',
                          allowNegative: true,
                        )) {
                          ParsedFigureValue(value: final v) when v == 0 =>
                            'Eine Buchung über null verändert nichts und lässt '
                                'sich anschließend nicht entfernen.',
                          ParsedFigureValue() => null,
                          ParsedFigureProblem(
                            kind: ParsedFigureProblemKind.empty,
                          ) =>
                            'Ein Betrag ist erforderlich.',
                          ParsedFigureProblem(
                            kind: ParsedFigureProblemKind.ambiguousSeparator,
                          ) =>
                            'Mehrdeutig: „1.000" kann tausend oder eins '
                                'bedeuten. Bitte „1000" oder „1000,00".',
                          ParsedFigureProblem(
                            kind: ParsedFigureProblemKind.notFinite,
                          ) =>
                            'Das ist keine Zahl, mit der gebucht werden kann.',
                          ParsedFigureProblem() => 'Bitte eine Zahl eingeben.',
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextFormField(
                        key: const Key('finance-booking-currency'),
                        controller: _currency,
                        enabled: !_submitting,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Währung',
                          // There is no workspace default anywhere on the
                          // server, so every booking states its own.
                          helperText: 'ISO, z. B. EUR',
                          errorText: _errorFor('currency_code'),
                        ),
                        validator: (String? raw) =>
                            RegExp(r'^[A-Za-z]{3}$').hasMatch((raw ?? '').trim())
                            ? null
                            : 'Drei Buchstaben, z. B. EUR.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Buchungsdatum',
                    helperText:
                        'Muss in die Periode ${widget.period.label} fallen — '
                        'jede Auswertung gruppiert danach.',
                    helperMaxLines: 2,
                    errorText: _errorFor('booked_on'),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _formatDate(_bookedOn),
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        key: const Key('finance-booking-date'),
                        onPressed: _submitting ? null : _pickDate,
                        child: const Text('Wählen'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('finance-booking-description'),
                  controller: _description,
                  enabled: !_submitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Beschreibung',
                    helperText:
                        'Rechnungsnummer, Lieferant, Zeitraum — was die '
                        'Buchung später wiedererkennbar macht.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const NxNotice(
                  key: Key('finance-booking-permanence'),
                  message:
                      'Eine Buchung lässt sich weder ändern noch löschen. Ein '
                      'Fehler wird durch eine Gegenbuchung mit negativem '
                      'Betrag ausgeglichen; beide Zeilen bleiben sichtbar.',
                  kind: NxNoticeKind.info,
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
          key: const Key('finance-booking-submit'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Buchen'),
        ),
      ],
    );
  }

  String? _errorFor(String field) =>
      _failureField == field ? _failureMessage : null;

  Future<void> _pickDate() async {
    // Bounded to the period, because the server refuses anything else and a
    // picker that offered the whole calendar would be offering a refusal.
    final DateTime first = DateTime(
      widget.period.fiscalYear,
      widget.period.periodMonth,
      1,
    );
    final DateTime last = DateTime(
      widget.period.fiscalYear,
      widget.period.periodMonth + 1,
      0,
    );
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _bookedOn,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      setState(
        () => _bookedOn = DateTime(picked.year, picked.month, picked.day),
      );
    }
  }

  Future<void> _submit() async {
    setState(() {
      _failureMessage = null;
      _failureField = null;
    });
    if (!(_form.currentState?.validate() ?? false)) {
      return;
    }
    final ParsedFigure parsed = parseGermanFigure(
      _amount.text,
      allowNegative: true,
    );
    if (parsed is! ParsedFigureValue) {
      setState(() {});
      return;
    }

    setState(() => _submitting = true);
    final CostPoolActionFailure? failure = await widget.onSubmit(
      FinanceBookingFormResult(
        accountId: _accountId!,
        bookedOn: _bookedOn,
        amount: parsed.value,
        currencyCode: _currency.text.trim().toUpperCase(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
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

String _formatDate(DateTime value) {
  final String day = value.day.toString().padLeft(2, '0');
  final String month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}
