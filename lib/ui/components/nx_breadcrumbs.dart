import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The single breadcrumb rendering for the whole app.
///
/// Uppercase with tracking is how this design system separates "metadata"
/// from content, chevrons replace slash separators, and the trailing crumb
/// carries full text contrast so the current location reads at a glance.
///
/// Lives in its own component because two headers need it ([NxPageHeader] and
/// the plain header variant in `detail_template.dart`); duplicating the
/// rendering is what let them drift apart in the first place.
class NxBreadcrumbs extends StatelessWidget {
  const NxBreadcrumbs({super.key, required this.crumbs});

  final List<String> crumbs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium;
    final current = muted?.copyWith(color: theme.colorScheme.onSurface);

    // Wraps rather than overflowing: breadcrumb trails get long on narrow
    // viewports and this app has to work down to 390px.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 2,
      children: [
        for (var i = 0; i < crumbs.length; i++) ...[
          if (i > 0)
            Icon(
              Icons.chevron_right,
              size: 14,
              color: context.semanticColors.textSecondary,
            ),
          Text(
            crumbs[i].toUpperCase(),
            style: i == crumbs.length - 1 ? current : muted,
          ),
        ],
      ],
    );
  }
}
