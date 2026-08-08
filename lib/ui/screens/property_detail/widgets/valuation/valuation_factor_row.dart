import 'package:flutter/material.dart';

import '../../../../../features/valuation/domain/valuation_factor.dart';
import '../../../../../features/valuation/domain/valuation_factor_catalog.dart';
import '../../../../components/nx_status_badge.dart';
import '../../../../utils/number_parse.dart';
import 'valuation_badges.dart';
import 'valuation_formatting.dart';

/// One factor of the entry form: its value, where that value came from, and —
/// for an unconfirmed suggestion — the source plus the action that makes it
/// count.
///
/// The provenance is never implicit. A field the user typed into becomes
/// `userProvided` on save; a suggestion stays visibly unconfirmed until
/// somebody takes responsibility for it, which is the whole point of the
/// rewrite and therefore the point of this row.
class ValuationFactorRow extends StatelessWidget {
  const ValuationFactorRow({
    super.key,
    required this.spec,
    required this.provenance,
    required this.draftText,
    required this.onChanged,
    this.source,
    this.onAcceptSuggestion,
    this.onClear,
    this.enabled = true,
  });

  final ValuationFactorSpec spec;

  /// Where the stored value came from, or null when nothing is stored yet.
  final FactorProvenance? provenance;

  /// Origin of a suggested value, shown with the confirmation prompt.
  final String? source;

  /// What is currently in the text field (may differ from [factor] while
  /// editing).
  final String draftText;

  final void Function(String raw) onChanged;
  final VoidCallback? onAcceptSuggestion;
  final VoidCallback? onClear;
  final bool enabled;

  bool get _isUnconfirmedSuggestion =>
      provenance == FactorProvenance.suggestedDefault;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  key: ValueKey<String>('factor-field-${spec.id}'),
                  initialValue: draftText,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: spec.label,
                    helperText: spec.hint,
                    suffixText: _suffixFor(spec),
                  ),
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: provenance == null
                    ? NxStatusBadge(
                        label: spec.isOptional ? 'optional' : 'fehlt',
                        kind: spec.isOptional
                            ? NxBadgeKind.neutral
                            : NxBadgeKind.error,
                      )
                    : FactorProvenanceBadge(provenance: provenance!),
              ),
            ],
          ),
          if (_isUnconfirmedSuggestion)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    source == null
                        ? 'Systemvorschlag — zählt erst nach Bestätigung.'
                        : 'Vorschlag aus $source — zählt erst nach '
                              'Bestätigung.',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (onAcceptSuggestion != null && enabled)
                    TextButton(
                      onPressed: onAcceptSuggestion,
                      child: const Text('Übernehmen'),
                    ),
                ],
              ),
            ),
          if (provenance != null && onClear != null && enabled)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onClear,
                child: const Text('Wert entfernen'),
              ),
            ),
        ],
      ),
    );
  }

  static String? _suffixFor(ValuationFactorSpec spec) => switch (spec.kind) {
    FactorInputKind.percent => '%',
    FactorInputKind.money => spec.unit ?? '€',
    FactorInputKind.area => spec.unit ?? 'm²',
    FactorInputKind.years => 'Jahre',
    FactorInputKind.factor => null,
  };
}

/// Converts between what the user types and what the engine stores: a rate is
/// entered as `3,5` and stored as `0.035`. Returns null for input that is not a
/// number — the caller then leaves the factor untouched rather than storing a
/// zero.
double? parseFactorInput(String raw, FactorInputKind kind) {
  final parsed = NumberParse.parseDoubleFlexible(raw);
  if (parsed == null) return null;
  return kind == FactorInputKind.percent ? parsed / 100 : parsed;
}

/// The inverse, for pre-filling the field from a stored value.
String formatFactorInput(double? value, FactorInputKind kind) {
  if (value == null) return '';
  if (kind == FactorInputKind.percent) {
    return formatPercent(value, decimals: 3).replaceAll(' %', '');
  }
  return formatBreakdownAmount(value, null);
}
