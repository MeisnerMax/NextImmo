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
    this.headerActions,
    this.plainHeader = false,
    this.fullPageScroll = false,
    this.pagePadding,
    required this.navigation,
    required this.content,
    this.navigationWidth = 288,
    this.compactNavigationMinHeight = 160,
    this.compactNavigationMaxHeight = 280,
    this.topNavigation = false,
  });

  final String title;
  final List<String> breadcrumbs;
  final String? subtitle;
  final Widget? contextBar;
  final Widget? headerActions;
  final bool plainHeader;
  final bool fullPageScroll;
  final double? pagePadding;
  final Widget navigation;
  final Widget content;
  final double navigationWidth;
  final double compactNavigationMinHeight;
  final double compactNavigationMaxHeight;
  final bool topNavigation;

  @override
  Widget build(BuildContext context) {
    final padding = pagePadding ?? context.adaptivePagePadding;
    if (fullPageScroll) {
      return SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (topNavigation) ...[
                navigation,
                const SizedBox(height: AppSpacing.component),
              ],
              _buildHeader(context),
              if (headerActions != null) ...[
                const SizedBox(height: AppSpacing.sm),
                headerActions!,
              ],
              const SizedBox(height: AppSpacing.component),
              if (topNavigation)
                content
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final zone = AppLayout.desktopZoneForWidth(
                      constraints.maxWidth,
                    );
                    if (zone == AppDesktopLayoutZone.narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: compactNavigationMaxHeight,
                            child: navigation,
                          ),
                          const SizedBox(height: AppSpacing.component),
                          content,
                        ],
                      );
                    }
                    final adaptiveNavigationWidth =
                        zone == AppDesktopLayoutZone.medium
                            ? (navigationWidth - 40).clamp(220, navigationWidth)
                            : navigationWidth;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: adaptiveNavigationWidth.toDouble(),
                          height: 520,
                          child: navigation,
                        ),
                        const SizedBox(width: AppSpacing.component),
                        Expanded(child: content),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topNavigation) ...[
            navigation,
            const SizedBox(height: AppSpacing.component),
          ],
          _buildHeader(context),
          if (headerActions != null) ...[
            const SizedBox(height: AppSpacing.sm),
            headerActions!,
          ],
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: topNavigation
                ? content
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final zone = AppLayout.desktopZoneForWidth(
                        constraints.maxWidth,
                      );
                      if (zone == AppDesktopLayoutZone.narrow) {
                        final navigationHeight =
                            (constraints.maxHeight * 0.26).clamp(
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

  Widget _buildHeader(BuildContext context) {
    if (plainHeader) {
      return _PlainDetailHeader(
        title: title,
        breadcrumbs: breadcrumbs,
        subtitle: subtitle,
        trailing: contextBar,
      );
    }
    return NxPageHeader(
      title: title,
      breadcrumbs: breadcrumbs,
      subtitle: subtitle,
      trailing: contextBar,
    );
  }
}

class _PlainDetailHeader extends StatelessWidget {
  const _PlainDetailHeader({
    required this.title,
    required this.breadcrumbs,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final List<String> breadcrumbs;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final titleBlock = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (breadcrumbs.isNotEmpty)
                Text(
                  breadcrumbs.join(' / '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.semanticColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
            ],
          ),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              if (trailing != null) ...[
                const SizedBox(height: AppSpacing.component),
                trailing!,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            if (trailing != null) trailing!,
          ],
        );
      },
    );
  }
}
