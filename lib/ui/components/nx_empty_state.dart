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
