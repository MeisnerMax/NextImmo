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
    final hoveredColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: resolvedPadding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(
          variant == NxCardVariant.kpi ? AppRadiusTokens.md : AppRadiusTokens.lg,
        ),
        border: Border.all(color: semantic.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: variant == NxCardVariant.kpi ? 8 : 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    if (variant != NxCardVariant.interactive || onTap == null) {
      return card;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        hoverColor: hoveredColor.withValues(alpha: 0.32),
        child: card,
      ),
    );
  }
}
