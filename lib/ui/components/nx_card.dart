import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum NxCardVariant { standard, interactive, kpi }

class NxCard extends StatelessWidget {
  const NxCard({
    super.key,
    required this.child,
    this.variant = NxCardVariant.standard,
    this.onTap,
    this.padding,
  });

  final Widget child;
  final NxCardVariant variant;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final compact = context.compactLayout;
    final resolvedPadding = padding ??
        EdgeInsets.all(
          variant == NxCardVariant.kpi
              ? (compact ? 12 : 16)
              : (compact ? 12 : AppSpacing.cardPadding),
        );
    final borderRadius = BorderRadius.circular(
      variant == NxCardVariant.kpi ? AppRadiusTokens.sm : AppRadiusTokens.lg,
    );

    if (variant != NxCardVariant.interactive || onTap == null) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: borderRadius,
          border: Border.all(color: semantic.border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: resolvedPadding,
            child: child,
          ),
        ),
      );
    }

    final hoveredColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: borderRadius,
        border: Border.all(color: semantic.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          hoverColor: hoveredColor.withValues(alpha: 0.12),
          child: Padding(
            padding: resolvedPadding,
            child: child,
          ),
        ),
      ),
    );
  }
}
