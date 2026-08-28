import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one list skeleton (Foundation §11/§18).
///
/// Loading is a skeleton, not a spinner: n placeholder rows on the alt
/// surface, matching the table's row rhythm so the swap to real content does
/// not jump. Replaces the per-panel private `_*Skeleton` copies as screens
/// are rebuilt; do not fork it per feature.
class NxListSkeleton extends StatelessWidget {
  const NxListSkeleton({super.key, this.rows = 6, this.rowHeight = 44});

  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Semantics(
      label: 'Wird geladen',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) const SizedBox(height: AppSpacing.xs),
              Container(
                key: Key('nx-list-skeleton-row-$row'),
                height: rowHeight,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
