import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'nx_card.dart';

class NxEmptyState extends StatelessWidget {
  const NxEmptyState({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.inbox_outlined,
    this.primaryAction,
  });

  /// The one error/retry state (Foundation §11): `cloud_off` plus a filled
  /// refresh action. Screens use this instead of hand-picking icons and
  /// button styles — the four divergent retry styles converge here.
  factory NxEmptyState.error({
    Key? key,
    String title = 'Daten konnten nicht geladen werden',
    required String description,
    VoidCallback? onRetry,
    String retryLabel = 'Erneut versuchen',
  }) {
    return NxEmptyState(
      key: key,
      title: title,
      description: description,
      icon: Icons.cloud_off_outlined,
      primaryAction:
          onRetry == null
              ? null
              : FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
    );
  }

  final String title;
  final String description;
  final IconData icon;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return NxCard(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.compactLayout ? 16 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: semantic.textSecondary),
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (primaryAction != null) ...[
                const SizedBox(height: 12),
                primaryAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
