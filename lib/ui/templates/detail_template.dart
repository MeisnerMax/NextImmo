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
                final compact = constraints.maxWidth < 980;
                if (compact) {
                  final navigationHeight = (constraints.maxHeight * 0.34).clamp(
                    compactNavigationMinHeight,
                    compactNavigationMaxHeight,
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
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: navigationWidth, child: navigation),
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
