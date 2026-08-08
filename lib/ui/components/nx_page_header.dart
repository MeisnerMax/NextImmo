import 'package:flutter/material.dart';

import 'nx_action_toolbar.dart';
import 'nx_breadcrumbs.dart';
import 'nx_section_header.dart';
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
      child: Wrap(
        spacing: AppSpacing.component,
        runSpacing: AppSpacing.component,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 760),
            child: NxSectionHeader(
              title: title,
              description: subtitle,
              compact: false,
              leading: crumbs.isEmpty ? null : NxBreadcrumbs(crumbs: crumbs),
            ),
          ),
          if (trailing != null) trailing!,
          if (secondaryActions.isNotEmpty || primaryAction != null)
            NxActionToolbar(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                ...secondaryActions,
                if (primaryAction != null) primaryAction!,
              ],
            ),
        ],
      ),
    );
  }
}
