import 'package:flutter/material.dart';

import '../../../../../features/valuation/application/valuation_variant_group.dart';
import '../../../../../features/valuation/domain/valuation_case_dto.dart';
import '../../../../components/nx_card.dart';
import '../../../../components/nx_status_badge.dart';
import 'valuation_badges.dart';
import 'valuation_formatting.dart';

/// The variants of a case side by side (Welle 5, AP6).
///
/// Each variant shows what *it* concluded, not what the group concluded — there
/// is no combined number, because averaging a conservative and an optimistic
/// case would produce a value nobody assumed. A variant without a published
/// report says so instead of borrowing its sibling's.
class ValuationVariantBar extends StatelessWidget {
  const ValuationVariantBar({
    super.key,
    required this.entries,
    required this.activeCaseId,
    this.onSelect,
    this.onCreateVariant,
  });

  final List<ValuationVariantEntry> entries;
  final String activeCaseId;
  final void Function(ValuationCaseDto valuationCase)? onSelect;
  final VoidCallback? onCreateVariant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGrouped = entries.length > 1;

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  isGrouped ? 'Varianten' : 'Variante',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (onCreateVariant != null)
                TextButton.icon(
                  onPressed: onCreateVariant,
                  icon: const Icon(Icons.call_split),
                  label: const Text('Variante anlegen'),
                ),
            ],
          ),
          if (entries.isEmpty)
            Text(
              'Diese Bewertung steht für sich. Eine Variante kopiert Faktoren '
              'und Verfahren, damit du Annahmen nebeneinander prüfen kannst.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                for (final entry in entries)
                  _VariantTile(
                    entry: entry,
                    isActive: entry.valuationCase.id == activeCaseId,
                    onSelect: onSelect == null
                        ? null
                        : () => onSelect!(entry.valuationCase),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _VariantTile extends StatelessWidget {
  const _VariantTile({
    required this.entry,
    required this.isActive,
    this.onSelect,
  });

  final ValuationVariantEntry entry;
  final bool isActive;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 240,
      child: OutlinedButton(
        onPressed: onSelect,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(12),
          side: BorderSide(
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(entry.label, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              formatEuro(entry.marketValue),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                ValuationStatusBadge(status: entry.valuationCase.status),
                if (entry.isStale)
                  const NxStatusBadge(
                    label: 'Bericht veraltet',
                    kind: NxBadgeKind.warning,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
