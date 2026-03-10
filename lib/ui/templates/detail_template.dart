import 'package:flutter/material.dart';

import '../components/nx_page_header.dart';
import '../theme/app_theme.dart';

class DetailTemplate extends StatelessWidget {
  const DetailTemplate({
    super.key,
    required this.title,
    required this.breadcrumbs,
    this.subtitle,
    this.contextBar,
    required this.navigation,
    required this.content,
    this.navigationWidth = 288,
    this.compactNavigationMinHeight = 160,
    this.compactNavigationMaxHeight = 280,
  });

  final String title;
  final List<String> breadcrumbs;
  final String? subtitle;
  final Widget? contextBar;
  final Widget navigation;
  final Widget content;
  final double navigationWidth;
  final double compactNavigationMinHeight;
  final double compactNavigationMaxHeight;

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
            trailing: contextBar,
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final zone = AppLayout.desktopZoneForWidth(
                  constraints.maxWidth,
                );
                if (zone == AppDesktopLayoutZone.narrow) {
                  final navigationHeight = (constraints.maxHeight * 0.26).clamp(
                    104.0,
                    compactNavigationMinHeight,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: navigationHeight, child: navigation),
                      const SizedBox(height: AppSpacing.component),
                      Expanded(child: content),
                    ],
                  );
                }
                final adaptiveNavigationWidth =
                    zone == AppDesktopLayoutZone.medium
                        ? (navigationWidth - 40).clamp(220, navigationWidth)
                        : navigationWidth;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: adaptiveNavigationWidth.toDouble(),
                      child: navigation,
                    ),
                    const SizedBox(width: AppSpacing.component),
                    Expanded(child: content),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
