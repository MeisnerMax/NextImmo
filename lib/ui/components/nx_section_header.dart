import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NxSectionHeader extends StatelessWidget {
  const NxSectionHeader({
    super.key,
    required this.title,
    this.description,
    this.leading,
    this.trailing,
    this.actions = const <Widget>[],
    this.compact = false,
  });

  final String title;
  final String? description;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final descriptionText = description?.trim();
    return Wrap(
      spacing: AppSpacing.component,
      runSpacing: AppSpacing.component,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (leading != null) leading!,
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 180, maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    compact
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.titleLarge,
              ),
              if (descriptionText != null && descriptionText.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  descriptionText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.semanticColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (actions.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
      ],
    );
  }
}
