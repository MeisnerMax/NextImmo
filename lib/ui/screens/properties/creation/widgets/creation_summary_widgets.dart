import 'package:flutter/material.dart';

import 'package:neximmo_app/ui/components/nx_form_section_card.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// A single labelled figure in a [CreationMetricStrip].
class CreationMetricItem {
  const CreationMetricItem(this.label, this.value);

  final String label;
  final String value;
}

/// Horizontal strip of derived-metric tiles shown below the form sections
/// (former private `_MetricStrip`).
class CreationMetricStrip extends StatelessWidget {
  const CreationMetricStrip({super.key, required this.items});

  final List<CreationMetricItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return Wrap(
      spacing: AppSpacing.component,
      runSpacing: AppSpacing.component,
      children: [
        for (final item in items)
          Container(
            width: 170,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: semantic.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
              border: Border.all(color: semantic.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: semantic.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A titled block of summary lines in the review step (former private
/// `_SummaryBlock`). The former raw `TextStyle` on the title now flows from the
/// theme's `textTheme` (DEBT-TOKEN-001).
class CreationSummaryBlock extends StatelessWidget {
  const CreationSummaryBlock({
    super.key,
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: semantic.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: semantic.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final line in lines.where((line) => line.trim().isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line),
            ),
        ],
      ),
    );
  }
}

/// A titled checklist section (missing/recommended/critical) rendered as an
/// [NxFormSectionCard] (former private `_ChecklistPanel`).
class CreationChecklistPanel extends StatelessWidget {
  const CreationChecklistPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyText,
    required this.color,
  });

  final String title;
  final IconData icon;
  final List<String> items;
  final String emptyText;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return NxFormSectionCard(
      title: title,
      margin: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isEmpty)
            Text(emptyText)
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
