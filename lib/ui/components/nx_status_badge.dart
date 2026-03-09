import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum NxBadgeKind { neutral, success, warning, error, info }

class NxStatusBadge extends StatelessWidget {
  const NxStatusBadge({
    super.key,
    required this.label,
    this.kind = NxBadgeKind.neutral,
  });

  final String label;
  final NxBadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final colorScheme = Theme.of(context).colorScheme;
    final colors = switch (kind) {
      NxBadgeKind.neutral => (
        colorScheme.surfaceContainerHighest,
        Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black,
      ),
      NxBadgeKind.success => (semantic.success.withValues(alpha: 0.14), semantic.success),
      NxBadgeKind.warning => (semantic.warning.withValues(alpha: 0.16), semantic.warning),
      NxBadgeKind.error => (semantic.error.withValues(alpha: 0.16), semantic.error),
      NxBadgeKind.info => (semantic.info.withValues(alpha: 0.16), semantic.info),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.$2.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.$2),
      ),
    );
  }
}
