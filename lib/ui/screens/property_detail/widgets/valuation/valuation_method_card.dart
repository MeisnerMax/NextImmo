import 'package:flutter/material.dart';

import '../../../../../features/valuation/domain/valuation_factor.dart';
import '../../../../../features/valuation/domain/valuation_method.dart';
import '../../../../components/nx_card.dart';
import '../../../../components/nx_status_badge.dart';
import 'valuation_badges.dart';
import 'valuation_formatting.dart';

/// One valuation method's outcome — a value with its calculation trail, or an
/// explicit "nicht ermittelbar" with the reasons.
///
/// The unavailable variant is deliberately as prominent as the value variant:
/// it names the method, states the outcome in words, lists every factor that is
/// still missing (with the reason: not entered vs. suggestion not confirmed)
/// and offers the jump into the input form. Hiding or greying out an
/// unavailable method would recreate exactly the silence this rewrite replaced.
class ValuationMethodCard extends StatefulWidget {
  const ValuationMethodCard({
    super.key,
    required this.method,
    required this.result,
    this.initiallyExpanded = false,
    this.onJumpToFactor,
    this.onAcceptSuggestion,
  });

  final ValuationMethodKind method;
  final MethodResult result;

  /// The leading method is expanded by default; the rest stay collapsed.
  final bool initiallyExpanded;

  /// Jump into the input form at the named factor.
  final void Function(String factorId)? onJumpToFactor;

  /// Confirm a system suggestion straight from the reason that blocks the
  /// method. Null when the caller may not mutate (read-only backend, missing
  /// permission, approved case) — the affordance then simply is not offered.
  final void Function(String factorId)? onAcceptSuggestion;

  @override
  State<ValuationMethodCard> createState() => _ValuationMethodCardState();
}

class _ValuationMethodCardState extends State<ValuationMethodCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.method.labelDe,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (result case MethodValue(:final confidence))
                ConfidenceBadge(confidence: confidence)
              else
                const NxStatusBadge(
                  label: notDeterminable,
                  kind: NxBadgeKind.warning,
                ),
            ],
          ),
          const SizedBox(height: 8),
          switch (result) {
            MethodValue(:final amount) => Text(
              formatEuro(amount),
              style: theme.textTheme.headlineSmall,
            ),
            MethodUnavailable() => Text(
              notDeterminable,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          },
          const SizedBox(height: 12),
          if (result case MethodUnavailable(
            :final missingFactors,
            :final reasons,
          ))
            _UnavailableReasons(
              missingFactors: missingFactors,
              reasons: reasons,
              onJumpToFactor: widget.onJumpToFactor,
              onAcceptSuggestion: widget.onAcceptSuggestion,
            ),
          if (result case MethodValue(:final breakdown)
              when breakdown.isNotEmpty) ...<Widget>[
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(_expanded ? 'Rechenweg ausblenden' : 'Rechenweg'),
            ),
            if (_expanded) _Breakdown(lines: breakdown),
          ],
        ],
      ),
    );
  }
}

class _UnavailableReasons extends StatelessWidget {
  const _UnavailableReasons({
    required this.missingFactors,
    required this.reasons,
    this.onJumpToFactor,
    this.onAcceptSuggestion,
  });

  final List<MissingFactor> missingFactors;
  final List<String> reasons;
  final void Function(String factorId)? onJumpToFactor;
  final void Function(String factorId)? onAcceptSuggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final missing in missingFactors)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(missing.message, style: theme.textTheme.bodyMedium),
                if (missing.reason ==
                        MissingFactorReason.suggestionNotConfirmed &&
                    onAcceptSuggestion != null)
                  TextButton(
                    onPressed: () => onAcceptSuggestion!(missing.factorId),
                    child: const Text('Vorschlag übernehmen'),
                  ),
                if (onJumpToFactor != null)
                  TextButton(
                    onPressed: () => onJumpToFactor!(missing.factorId),
                    child: const Text('Zur Eingabe'),
                  ),
              ],
            ),
          ),
        for (final reason in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(reason, style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.lines});

  final List<MethodBreakdownLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(line.label, style: theme.textTheme.bodyMedium),
                      if (line.formula != null)
                        Text(
                          line.formula!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatBreakdownAmount(line.amount, line.unit),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
