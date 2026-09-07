/// Creating or renaming a cost type (`FINANCE-COST-TYPES-01`).
///
/// **The code is set once.** `update_finance_account` accepts no code, and
/// deliberately: a code is what a booking, a report and an export cite, so
/// renaming one silently re-points every line that quoted it. The form says so
/// while it is being chosen, and shows the field disabled afterwards rather
/// than hiding it — a reader looking for the code should find it where they
/// left it.
///
/// **The dialog owns the submit.** It stays open while the command runs and
/// while it is refused, keeps what was typed, and puts the server's message on
/// the field the server named — a code already taken, most often.
///
/// The form owns its controllers: a dialog's exit animation keeps building the
/// subtree after the pop.
library;

import 'package:flutter/material.dart';

import '../../../features/finance_ledger/application/cost_allocation_controller.dart'
    show CostAllocationActionFailure;
import '../../../features/finance_ledger/domain/betrkv_catalogue.dart';
import '../../../features/finance_ledger/domain/cost_allocation_dto.dart';
import '../../../features/finance_ledger/domain/finance_actuals_dto.dart';
import '../../components/nx_notice.dart';
import '../../theme/app_theme.dart';

class FinanceAccountFormResult {
  const FinanceAccountFormResult({
    required this.code,
    required this.name,
    required this.accountType,
    required this.isActive,
    this.expectedVersion,
  });

  final String code;
  final String name;
  final FinanceAccountType accountType;
  final bool isActive;

  /// The version of the row this form was filled against. Null for a create.
  /// Carried explicitly so a refusal cannot be retried with fresh version and
  /// stale values — which would overwrite whatever the other writer did.
  final int? expectedVersion;
}

typedef FinanceAccountSubmit =
    Future<CostAllocationActionFailure?> Function(
      FinanceAccountFormResult result,
    );

String financeAccountTypeLabel(FinanceAccountType type) => switch (type) {
  FinanceAccountType.expense => 'Aufwand',
  FinanceAccountType.income => 'Ertrag',
  FinanceAccountType.asset => 'Aktiva',
  FinanceAccountType.liability => 'Passiva',
  FinanceAccountType.equity => 'Eigenkapital',
  FinanceAccountType.unknown => 'Unbekannt',
};

Future<bool?> showFinanceAccountDialog(
  BuildContext context, {
  CostAccountAllocationDto? account,
  BetrkvSuggestion? suggestion,
  required FinanceAccountSubmit onSubmit,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => _FinanceAccountDialog(
      account: account,
      suggestion: suggestion,
      onSubmit: onSubmit,
    ),
  );
}

class _FinanceAccountDialog extends StatefulWidget {
  const _FinanceAccountDialog({
    required this.account,
    required this.suggestion,
    required this.onSubmit,
  });

  final CostAccountAllocationDto? account;
  final BetrkvSuggestion? suggestion;
  final FinanceAccountSubmit onSubmit;

  @override
  State<_FinanceAccountDialog> createState() => _FinanceAccountDialogState();
}

class _FinanceAccountDialogState extends State<_FinanceAccountDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late FinanceAccountType _type;
  late bool _active;

  bool _submitting = false;
  String? _failureMessage;
  String? _failureField;

  /// The row's version as this form was filled. Not refreshed behind the
  /// reader's back: if the account changed underneath, the retry must fail
  /// again rather than silently win.
  int? _version;

  bool get _isNew => widget.account == null;

  /// Nothing typed differs from what is stored. The server would still bump
  /// the version and append an audit record, so the save is not offered.
  bool get _unchanged {
    final CostAccountAllocationDto? account = widget.account;
    if (account == null) {
      return false;
    }
    return _name.text.trim() == account.name && _active == account.isActive;
  }

  @override
  void initState() {
    super.initState();
    final CostAccountAllocationDto? account = widget.account;
    final BetrkvSuggestion? suggestion = widget.suggestion;
    _code = TextEditingController(
      text: account?.code ?? suggestion?.suggestedCode ?? '',
    );
    _name = TextEditingController(
      text: account?.name ?? suggestion?.name ?? '',
    );
    // An account kind this build does not recognise is not carried into the
    // form: the command layer refuses to write it back, so offering it would
    // build a submission that cannot succeed.
    _type = account == null || account.kind == FinanceAccountType.unknown
        ? FinanceAccountType.expense
        : account.kind;
    _active = account?.isActive ?? true;
    _version = account?.version;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final BetrkvSuggestion? suggestion = widget.suggestion;

    return AlertDialog(
      key: const Key('finance-account-dialog'),
      title: Text(_isNew ? 'Kostenart anlegen' : 'Kostenart ändern'),
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
                    key: const Key('finance-account-dialog-failure'),
                    message: _failureMessage!,
                    kind: NxNoticeKind.error,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (suggestion != null) ...<Widget>[
                  NxNotice(
                    key: const Key('finance-account-suggestion'),
                    message:
                        'Vorschlag nach § 2 Nr. ${suggestion.position} BetrKV: '
                        '„${suggestion.positionText}". '
                        '${suggestion.note ?? ''} '
                        'Bezeichnung und Schlüssel sind frei änderbar — die '
                        'Liste ist ein Ausgangspunkt, keine im System '
                        'festgelegte Vorgabe.',
                    kind: NxNoticeKind.info,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TextFormField(
                  key: const Key('finance-account-code'),
                  controller: _code,
                  // Set once. The server takes no code on the update, so a
                  // field that looked editable would promise something the
                  // contract refuses.
                  enabled: _isNew && !_submitting,
                  decoration: InputDecoration(
                    labelText: 'Schlüssel',
                    helperText: _isNew
                        ? 'Buchstaben, Ziffern, Punkt, Bindestrich oder '
                              'Unterstrich. Lässt sich später nicht mehr '
                              'ändern: Buchungen und Berichte zitieren ihn.'
                        : 'Nicht änderbar — Buchungen und Berichte zitieren '
                              'ihn.',
                    helperMaxLines: 3,
                    errorText: _errorFor('code'),
                  ),
                  validator: (String? value) {
                    if (!_isNew) {
                      return null;
                    }
                    final String text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return 'Ein Schlüssel ist erforderlich.';
                    }
                    if (!RegExp(
                      r'^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$',
                    ).hasMatch(text)) {
                      return 'Nur Buchstaben, Ziffern, . _ - (max. 50), '
                          'beginnend mit Buchstabe oder Ziffer.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('finance-account-name'),
                  controller: _name,
                  enabled: !_submitting,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Bezeichnung',
                    helperText: 'Was auf einer Abrechnungszeile steht.',
                    errorText: _errorFor('name'),
                  ),
                  validator: (String? value) => (value ?? '').trim().isEmpty
                      ? 'Eine Bezeichnung ist erforderlich.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                // An account kind this build does not recognise is stated as
                // what it is. Rendering the fallback with "Nicht änderbar"
                // would assert as stored fact that the account is an expense
                // account, on the only screen that shows its kind at all.
                if (!_isNew &&
                    widget.account!.kind == FinanceAccountType.unknown)
                  TextFormField(
                    key: const Key('finance-account-type-unknown'),
                    initialValue: widget.account!.accountType,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Kontoart',
                      helperText:
                          'Diesen Kontotyp kennt dieser Stand nicht — er kann '
                          'nur von einem neueren Server stammen. Nicht '
                          'änderbar.',
                      helperMaxLines: 3,
                    ),
                  )
                else
                DropdownButtonFormField<FinanceAccountType>(
                  key: const Key('finance-account-type'),
                  value: _type,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Kontoart',
                    helperText: _isNew
                        ? 'Betriebskosten sind Aufwand.'
                        : 'Nicht änderbar.',
                    errorText: _errorFor('accountType'),
                  ),
                  items: const <DropdownMenuItem<FinanceAccountType>>[
                    DropdownMenuItem<FinanceAccountType>(
                      value: FinanceAccountType.expense,
                      child: Text('Aufwand'),
                    ),
                    DropdownMenuItem<FinanceAccountType>(
                      value: FinanceAccountType.income,
                      child: Text('Ertrag'),
                    ),
                    DropdownMenuItem<FinanceAccountType>(
                      value: FinanceAccountType.asset,
                      child: Text('Aktiva'),
                    ),
                    DropdownMenuItem<FinanceAccountType>(
                      value: FinanceAccountType.liability,
                      child: Text('Passiva'),
                    ),
                    DropdownMenuItem<FinanceAccountType>(
                      value: FinanceAccountType.equity,
                      child: Text('Eigenkapital'),
                    ),
                  ],
                  // The server's update takes no account type either, so it is
                  // frozen after creation for the same reason as the code.
                  onChanged: _isNew && !_submitting
                      ? (FinanceAccountType? value) {
                          if (value == null) {
                            return;
                          }
                          setState(() => _type = value);
                        }
                      : null,
                ),
                const SizedBox(height: AppSpacing.xs),
                SwitchListTile(
                  key: const Key('finance-account-active'),
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: _submitting || _isNew
                      ? null
                      : (bool value) => setState(() => _active = value),
                  // Rebuilt on every change so the save button can go quiet
                  // once nothing differs from what is stored.
                  title: const Text('Aktiv'),
                  subtitle: Text(
                    _isNew
                        ? 'Eine neue Kostenart ist aktiv.'
                        : 'Eine inaktive Kostenart bleibt in der Liste und in '
                              'allen Buchungen, die sie zitieren.',
                    style: theme.textTheme.bodySmall,
                  ),
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
          key: const Key('finance-account-submit'),
          onPressed: _submitting || _unchanged ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isNew ? 'Anlegen' : 'Speichern'),
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
    if (!(_form.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _submitting = true);
    final CostAllocationActionFailure? failure = await widget.onSubmit(
      FinanceAccountFormResult(
        code: _code.text.trim(),
        name: _name.text.trim(),
        accountType: _type,
        isActive: _active,
        expectedVersion: _version,
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
