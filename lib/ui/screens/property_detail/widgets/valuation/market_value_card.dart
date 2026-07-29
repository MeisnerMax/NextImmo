import 'package:flutter/material.dart';

import '../../../../../features/valuation/domain/valuation_method.dart';
import '../../../../../features/valuation/domain/valuation_report.dart';
import '../../../../components/nx_card.dart';
import '../../../../components/nx_status_badge.dart';
import 'valuation_badges.dart';
import 'valuation_formatting.dart';

/// The reconciled Verkehrswert: amount, confidence, the weighting that produced
/// it and the reasoning — or the recorded statement that no value could be
/// concluded, with the same prominence.
///
/// [isStale] renders the case the versioning decision deliberately leaves
/// visible: a published report computed from an older factor set. The number
/// stays on screen (it is a real, published stand) but is labelled, instead of
/// being silently refreshed or silently trusted.
class MarketValueCard extends StatelessWidget {
  const MarketValueCard({
    super.key,
    required this.opinion,
    this.isStale = false,
    this.onRecompute,
  });

  final MarketValueOpinion opinion;
  final bool isStale;
  final VoidCallback? onRecompute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text('Verkehrswert', style: theme.textTheme.titleMedium),
              ),
              if (opinion case MarketValue(:final confidence))
                ConfidenceBadge(confidence: confidence)
              else
                const NxStatusBadge(
                  label: notDeterminable,
                  kind: NxBadgeKind.warning,
                ),
            ],
          ),
          const SizedBox(height: 8),
          switch (opinion) {
            MarketValue(:final amount) => Text(
              formatEuro(amount),
              style: theme.textTheme.headlineMedium,
            ),
            MarketValueUnavailable() => Text(
              notDeterminable,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          },
          if (isStale) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                const NxStatusBadge(
                  label: 'Bericht veraltet',
                  kind: NxBadgeKind.warning,
                ),
                Text(
                  'Der veröffentlichte Bericht beruht auf einem älteren '
                  'Faktorstand.',
                  style: theme.textTheme.bodySmall,
                ),
                if (onRecompute != null)
                  TextButton(
                    onPressed: onRecompute,
                    child: const Text('Neu veröffentlichen'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (opinion case MarketValue(:final weights) when weights.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final entry in weights.entries)
                  NxStatusBadge(
                    label:
                        '${entry.key.labelDe} ${formatPercent(entry.value, decimals: 0)}',
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            switch (opinion) {
              MarketValue(:final rationale) => rationale,
              MarketValueUnavailable(:final reason) => reason,
            },
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
