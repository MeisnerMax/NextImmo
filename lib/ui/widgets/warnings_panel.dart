import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WarningsPanel extends StatelessWidget {
  const WarningsPanel({super.key, required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) {
      return const SizedBox.shrink();
    }
    final semantic = context.semanticColors;

    return Card(
      color: semantic.warning.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: semantic.warning),
                const SizedBox(width: 8),
                Text(
                  'Warnings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            ...warnings.map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $warning'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
