import 'package:flutter/material.dart';

import '../components/nx_action_toolbar.dart';
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
    this.scrollable = false,
    this.expandContent = true,
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
  final bool scrollable;
  final bool expandContent;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
        if (scrollable)
          content
        else if (expandContent)
          Expanded(child: content)
        else
          content,
        if (footer != null) ...[
          const SizedBox(height: AppSpacing.component),
          footer!,
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: scrollable ? SingleChildScrollView(child: body) : body,
    );
  }
}

class ListFilterBar extends StatelessWidget {
  const ListFilterBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return NxActionToolbar(children: children);
  }
}
