/// The rule editor (`COMPLIANCE-RULES-01`, V-4).
///
/// Four things it insists on, each because the alternative produces a legal
/// figure nobody can stand behind:
///
///   * **A source.** Required by the server and required here, so the refusal
///     arrives before the round trip. A legal figure without a source is a
///     number somebody remembered.
///   * **A start date.** A rule without one has no period, and a rule without
///     a period cannot answer "what did the law say in 2024".
///   * **A value that parses.** The field takes JSON, because the shapes
///     genuinely differ: a price is a number, the 70% rule is three booleans.
///     A malformed value is refused here rather than sent as a string that the
///     server would store as a string.
///   * **An explicit warning when editing a confirmed rule.** Saving drops it
///     back to unverified, and the reader has to be told that before they save,
///     not after.
///
/// The form owns its controllers: a dialog's exit animation keeps building the
/// subtree after the pop, and controllers freed by the caller are read after
/// disposal.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../features/compliance_rules/domain/compliance_rule_dto.dart';
import '../../theme/app_theme.dart';
import 'compliance_rule_proposals.dart';

/// What the form hands back. Null from the dialog means cancelled.
class ComplianceRuleFormResult {
  const ComplianceRuleFormResult({
    required this.ruleKey,
    required this.validFrom,
    required this.value,
    required this.sourceReference,
    this.validTo,
    this.unit,
    this.note,
    this.decisionSupport = false,
  });

  final String ruleKey;
  final DateTime validFrom;
  final DateTime? validTo;
  final Object value;
  final String sourceReference;
  final String? unit;
  final String? note;
  final bool decisionSupport;
}

Future<ComplianceRuleFormResult?> showComplianceRuleFormDialog(
  BuildContext context, {
  ComplianceRuleDto? existing,
  ComplianceRuleProposal? proposal,
}) {
  return showDialog<ComplianceRuleFormResult>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _ComplianceRuleFormDialog(existing: existing, proposal: proposal),
  );
}

/// Parses a date field. Returns null for empty, which the caller reads as
/// open-ended; throws nothing — an unparseable value is caught by the
/// validator first.
DateTime? parseComplianceDate(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : DateTime.tryParse(trimmed);
}

String formatComplianceDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

/// The value as the field shows it. Pretty-printed so a three-part rule is
/// legible rather than one long line.
String formatComplianceValue(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}

class _ComplianceRuleFormDialog extends StatefulWidget {
  const _ComplianceRuleFormDialog({this.existing, this.proposal});

  final ComplianceRuleDto? existing;
  final ComplianceRuleProposal? proposal;

  @override
  State<_ComplianceRuleFormDialog> createState() =>
      _ComplianceRuleFormDialogState();
}

class _ComplianceRuleFormDialogState extends State<_ComplianceRuleFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _ruleKey;
  late final TextEditingController _validFrom;
  late final TextEditingController _validTo;
  late final TextEditingController _value;
  late final TextEditingController _unit;
  late final TextEditingController _source;
  late final TextEditingController _note;
  late bool _decisionSupport;

  @override
  void initState() {
    super.initState();
    final ComplianceRuleDto? existing = widget.existing;
    final ComplianceRuleProposal? proposal = widget.proposal;
    _ruleKey = TextEditingController(
      text: existing?.ruleKey ?? proposal?.ruleKey ?? '',
    );
    _validFrom = TextEditingController(
      text: formatComplianceDate(existing?.validFrom ?? proposal?.validFrom),
    );
    _validTo = TextEditingController(
      text: formatComplianceDate(existing?.validTo ?? proposal?.validTo),
    );
    _value = TextEditingController(
      text: formatComplianceValue(existing?.value ?? proposal?.value),
    );
    _unit = TextEditingController(text: existing?.unit ?? proposal?.unit ?? '');
    _source = TextEditingController(
      text: existing?.sourceReference ?? proposal?.sourceReference ?? '',
    );
    _note = TextEditingController(text: existing?.note ?? proposal?.note ?? '');
    _decisionSupport =
        existing?.needsHumanDecision ?? proposal?.decisionSupport ?? false;
  }

  @override
  void dispose() {
    _ruleKey.dispose();
    _validFrom.dispose();
    _validTo.dispose();
    _value.dispose();
    _unit.dispose();
    _source.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final bool editingVerified = widget.existing?.isVerified ?? false;

    return AlertDialog(
      key: const Key('compliance-rule-form'),
      title: Text(
        widget.existing == null ? 'Regel anlegen' : 'Regel bearbeiten',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (editingVerified)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      key: const Key('compliance-rule-unverify-warning'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 18,
                          color: semantic.warning,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'Diese Regel ist bestätigt. Beim Speichern '
                            'erlischt die Bestätigung — wer sie geprüft hat, '
                            'hat den geänderten Text nicht gesehen.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                TextFormField(
                  key: const Key('compliance-rule-key'),
                  controller: _ruleKey,
                  decoration: const InputDecoration(
                    labelText: 'Schlüssel',
                    helperText: 'z. B. co2_price_eur_per_tonne',
                  ),
                  validator: (String? value) =>
                      (value == null || value.trim().isEmpty)
                      ? 'Pflichtfeld'
                      : null,
                ),
                TextFormField(
                  key: const Key('compliance-rule-valid-from'),
                  controller: _validFrom,
                  decoration: const InputDecoration(
                    labelText: 'Gilt ab (JJJJ-MM-TT)',
                  ),
                  validator: (String? value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'Pflichtfeld';
                    }
                    return DateTime.tryParse(trimmed) == null
                        ? 'Datum im Format JJJJ-MM-TT'
                        : null;
                  },
                ),
                TextFormField(
                  key: const Key('compliance-rule-valid-to'),
                  controller: _validTo,
                  decoration: const InputDecoration(
                    labelText: 'Gilt bis (JJJJ-MM-TT)',
                    helperText: 'Leer lassen heißt: gilt weiter.',
                  ),
                  validator: (String? value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return null;
                    }
                    final parsed = DateTime.tryParse(trimmed);
                    if (parsed == null) {
                      return 'Datum im Format JJJJ-MM-TT';
                    }
                    final from = parseComplianceDate(_validFrom.text);
                    if (from != null && parsed.isBefore(from)) {
                      return 'Das Ende liegt vor dem Beginn';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  key: const Key('compliance-rule-value'),
                  controller: _value,
                  decoration: const InputDecoration(
                    labelText: 'Wert (JSON)',
                    helperText:
                        'Eine Zahl, ein Text oder ein Objekt — je nachdem, '
                        'was die Regel sagt.',
                  ),
                  maxLines: 5,
                  minLines: 2,
                  validator: (String? value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'Pflichtfeld';
                    }
                    try {
                      jsonDecode(trimmed);
                      return null;
                    } on FormatException {
                      return 'Kein gültiges JSON';
                    }
                  },
                ),
                TextFormField(
                  key: const Key('compliance-rule-unit'),
                  controller: _unit,
                  decoration: const InputDecoration(
                    labelText: 'Einheit',
                    helperText: 'z. B. EUR/t oder %',
                  ),
                ),
                TextFormField(
                  key: const Key('compliance-rule-source'),
                  controller: _source,
                  decoration: const InputDecoration(
                    labelText: 'Quelle',
                    // Not a nicety. The server refuses a rule without one, and
                    // the reason is the whole package: a legal figure without
                    // a source is a number somebody remembered.
                    helperText: 'Fundstelle, Gesetz oder Entscheidung.',
                  ),
                  validator: (String? value) =>
                      (value == null || value.trim().isEmpty)
                      ? 'Pflichtfeld — ohne Quelle keine Regel'
                      : null,
                ),
                TextFormField(
                  key: const Key('compliance-rule-note'),
                  controller: _note,
                  decoration: const InputDecoration(labelText: 'Notiz'),
                  maxLines: 3,
                  minLines: 1,
                ),
                SwitchListTile(
                  key: const Key('compliance-rule-decision-support'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Verlangt eine menschliche Entscheidung'),
                  subtitle: const Text(
                    'Wird vorgeschlagen, nie automatisch angewendet — und '
                    'kann auch nicht bestätigt werden.',
                  ),
                  value: _decisionSupport,
                  onChanged: (bool value) =>
                      setState(() => _decisionSupport = value),
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
          key: const Key('compliance-rule-save'),
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
    final Object decoded = jsonDecode(_value.text.trim()) as Object;
    Navigator.of(context).pop(
      ComplianceRuleFormResult(
        ruleKey: _ruleKey.text.trim(),
        validFrom: DateTime.parse(_validFrom.text.trim()),
        validTo: parseComplianceDate(_validTo.text),
        value: decoded,
        sourceReference: _source.text.trim(),
        unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        decisionSupport: _decisionSupport,
      ),
    );
  }
}
