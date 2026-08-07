import 'package:flutter/material.dart';

import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../theme/app_theme.dart';

/// Settings-shaped loading placeholder (never a full-surface spinner): a header
/// bar plus the section-rail + form-card silhouette the loaded screen renders.
/// The whole screen hydrates from a single [`getSettings`] read, so one skeleton
/// stands in for the entire surface rather than per-field spinners.
class SettingsSkeleton extends StatelessWidget {
  const SettingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey<String>('settings_skeleton'),
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Expanded(child: _Bar(width: double.infinity, height: 26)),
              SizedBox(width: AppSpacing.component),
              _Bar(width: 120, height: 34, radius: AppRadiusTokens.lg),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 1060;
                const rail = _RailSkeleton();
                const body = _FormSkeleton();
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: const [
                      SizedBox(height: 220, child: rail),
                      SizedBox(height: AppSpacing.component),
                      Expanded(child: body),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    SizedBox(width: 300, child: rail),
                    SizedBox(width: AppSpacing.component),
                    Expanded(child: body),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        border: Border.all(color: context.semanticColors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List<Widget>.generate(
          5,
          (_) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: _Bar(width: double.infinity, height: 20),
          ),
        ),
      ),
    );
  }
}

class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _CardSkeleton(rows: 1),
        SizedBox(height: AppSpacing.component),
        _CardSkeleton(rows: 3),
      ],
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Bar(width: 180, height: 16),
          const SizedBox(height: AppSpacing.md),
          for (int i = 0; i < rows; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.component),
            const _Bar(width: double.infinity, height: 48),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.width,
    required this.height,
    this.radius = AppRadiusTokens.xs,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Infrastructure-error treatment for the initial settings load: no raw
/// exception text, always a retry action (design-system mandatory error state).
/// Retry re-runs the same `_load` the screen uses on mount.
class SettingsLoadError extends StatelessWidget {
  const SettingsLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: NxEmptyState(
            title: 'Einstellungen konnten nicht geladen werden',
            description:
                'Beim Laden der Einstellungen ist ein Fehler aufgetreten. '
                'Bitte versuchen Sie es erneut.',
            icon: Icons.error_outline,
            primaryAction: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          ),
        ),
      ),
    );
  }
}
