import 'package:flutter/material.dart';

import '../../../components/nx_card.dart';
import '../../../components/nx_empty_state.dart';
import '../../../theme/app_theme.dart';

/// Scoped error treatment for one overview section: no raw exception text,
/// always a retry action (design-system mandatory error state).
class OverviewSectionError extends StatelessWidget {
  const OverviewSectionError({
    super.key,
    required this.title,
    required this.onRetry,
  });

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return NxEmptyState(
      title: title,
      description:
          'Beim Laden dieser Sektion ist ein Fehler aufgetreten. '
          'Bitte versuchen Sie es erneut.',
      icon: Icons.error_outline,
      primaryAction: ElevatedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Erneut versuchen'),
      ),
    );
  }
}

/// Layout-shaped loading placeholder for a card section (no full-page
/// spinner): a titled bar plus a content block, mirroring the section shape.
class OverviewSectionSkeleton extends StatelessWidget {
  const OverviewSectionSkeleton({super.key, this.height = 160});

  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholderColor = context.semanticColors.surfaceAlt;
    Widget bar(double width, double barHeight) => Container(
          width: width,
          height: barHeight,
          decoration: BoxDecoration(
            color: placeholderColor,
            borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
          ),
        );
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(180, 14),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              color: placeholderColor,
              borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder matching the metric tile grid layout.
class OverviewMetricGridSkeleton extends StatelessWidget {
  const OverviewMetricGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final placeholderColor = context.semanticColors.surfaceAlt;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: placeholderColor,
            borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
          ),
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final tileWidth = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.component) / 2;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: List.generate(
            4,
            (_) => SizedBox(
              width: tileWidth,
              child: NxCard(
                variant: NxCardVariant.kpi,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(110, 10),
                    const SizedBox(height: 12),
                    bar(70, 18),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
