import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NxPageHeader extends StatelessWidget {
  const NxPageHeader({
    super.key,
    required this.title,
    this.breadcrumbs = const <String>[],
    this.primaryAction,
    this.secondaryActions = const <Widget>[],
    this.trailing,
    this.subtitle,
  });

  final String title;
  final List<String> breadcrumbs;
  final Widget? primaryAction;
  final List<Widget> secondaryActions;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final crumbs = breadcrumbs.where((item) => item.trim().isNotEmpty).toList();
    return Container(
      padding: EdgeInsets.all(context.compactLayout ? 12 : 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        border: Border.all(color: semantic.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (crumbs.isNotEmpty) ...[
                  Text(
                    crumbs.join(' / '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                ],
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
          if (secondaryActions.isNotEmpty || primaryAction != null) ...[
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...secondaryActions,
                if (primaryAction != null) primaryAction!,
              ],
            ),
          ],
        ],
      ),
    );
  }
}
