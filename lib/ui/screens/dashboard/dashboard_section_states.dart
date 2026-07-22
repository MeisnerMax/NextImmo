import 'package:flutter/material.dart';

import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../theme/app_theme.dart';

/// Infrastructure-error treatment for the whole dashboard: no raw exception
/// text, always a retry action (design-system mandatory error state). Retry
/// re-runs the same invalidation the header refresh uses.
class DashboardErrorState extends StatelessWidget {
  const DashboardErrorState({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return NxEmptyState(
      title: 'Dashboard konnte nicht geladen werden',
      description:
          'Beim Laden der Portfolio-Übersicht ist ein Fehler aufgetreten. '
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

/// Zero-property empty state: names the concrete next action and leads into the
/// existing property creation flow via [onCreate].
class DashboardEmptyState extends StatelessWidget {
  const DashboardEmptyState({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return NxEmptyState(
      title: 'Lege dein erstes Objekt an',
      description:
          'Sobald ein Objekt erfasst ist, zeigt das Dashboard Portfolio-'
          'Gesundheit, Fälligkeiten und Auffälligkeiten auf einen Blick.',
      icon: Icons.home_work_outlined,
      primaryAction: ElevatedButton.icon(
        onPressed: onCreate,
        icon: const Icon(Icons.add),
        label: const Text('Objekt anlegen'),
      ),
    );
  }
}

/// Dashboard-shaped loading placeholder (never a full-page spinner): a KPI tile
/// row plus section-shaped blocks mirroring the eventual layout. The single
/// [dashboardOverviewProvider] resolves as one unit today, so the whole
/// dashboard shares one skeleton rather than per-tile spinners.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('dashboard_skeleton'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DashboardKpiRowSkeleton(),
        const SizedBox(height: AppSpacing.component),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1080;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Expanded(flex: 3, child: _DashboardBlockSkeleton(height: 240)),
                  SizedBox(width: AppSpacing.component),
                  Expanded(flex: 2, child: _DashboardBlockSkeleton(height: 240)),
                ],
              );
            }
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DashboardBlockSkeleton(height: 180),
                SizedBox(height: AppSpacing.component),
                _DashboardBlockSkeleton(height: 220),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.component),
        const _DashboardBlockSkeleton(height: 200),
      ],
    );
  }
}

class _DashboardKpiRowSkeleton extends StatelessWidget {
  const _DashboardKpiRowSkeleton();

  @override
  Widget build(BuildContext context) {
    final placeholderColor = context.semanticColors.surfaceAlt;
    Widget bar(double barWidth, double height) => Container(
          width: barWidth,
          height: height,
          decoration: BoxDecoration(
            color: placeholderColor,
            borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
          ),
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 600
            ? 1
            : (constraints.maxWidth < 1080 ? 2 : 3);
        final gap = AppSpacing.component;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(
            6,
            (_) => SizedBox(
              width: width,
              child: NxCard(
                variant: NxCardVariant.kpi,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(120, 10),
                    const SizedBox(height: 12),
                    bar(90, 20),
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

class _DashboardBlockSkeleton extends StatelessWidget {
  const _DashboardBlockSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholderColor = context.semanticColors.surfaceAlt;
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 180,
            height: 14,
            decoration: BoxDecoration(
              color: placeholderColor,
              borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
            ),
          ),
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
