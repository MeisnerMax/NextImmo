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

/// Full-width filter strip: controls left, result context right.
///
/// Deliberately not an [NxActionToolbar] — that shrink-wraps to its content,
/// which is right for an action group but left this bar stranded in the
/// left third of the page with two thirds dead space. A filter bar spans the
/// content it filters.
class ListFilterBar extends StatelessWidget {
  const ListFilterBar({super.key, required this.children, this.trailing});

  final List<Widget> children;

  /// Right-aligned context — typically the result count. Wraps below the
  /// filters on narrow viewports rather than squeezing them.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(semantic.innerHighlight, semantic.glassFill),
            semantic.glassFill,
          ],
          stops: const [0, 0.5],
        ),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        border: Border.all(color: semantic.glassStroke),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.component),
            trailing!,
          ],
        ],
      ),
    );
  }
}
