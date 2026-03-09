import 'package:flutter/material.dart';

import '../components/nx_page_header.dart';
import '../theme/app_theme.dart';

class ListFilterTemplate extends StatelessWidget {
  const ListFilterTemplate({
    super.key,
    required this.title,
    required this.breadcrumbs,
    this.subtitle,
    this.primaryAction,
    this.secondaryActions = const <Widget>[],
    this.filters,
    this.contextBar,
    required this.content,
    this.footer,
  });

  final String title;
  final List<String> breadcrumbs;
  final String? subtitle;
  final Widget? primaryAction;
  final List<Widget> secondaryActions;
  final Widget? filters;
  final Widget? contextBar;
  final Widget content;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NxPageHeader(
            title: title,
            breadcrumbs: breadcrumbs,
            subtitle: subtitle,
            primaryAction: primaryAction,
            secondaryActions: secondaryActions,
          ),
          if (contextBar != null) ...[
            const SizedBox(height: AppSpacing.component),
            contextBar!,
          ],
          if (filters != null) ...[
            const SizedBox(height: AppSpacing.component),
            filters!,
          ],
          const SizedBox(height: AppSpacing.component),
          Expanded(child: content),
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.component),
            footer!,
          ],
        ],
      ),
    );
  }
}

class ListFilterBar extends StatelessWidget {
  const ListFilterBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
