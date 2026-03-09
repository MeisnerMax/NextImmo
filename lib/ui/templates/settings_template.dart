import 'package:flutter/material.dart';

import '../components/nx_card.dart';
import '../components/nx_page_header.dart';
import '../theme/app_theme.dart';

class SettingsNavigationItem {
  const SettingsNavigationItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.description,
  });

  final String id;
  final String label;
  final IconData icon;
  final String description;
}

class SettingsTemplate extends StatelessWidget {
  const SettingsTemplate({
    super.key,
    required this.title,
    required this.breadcrumbs,
    this.subtitle,
    required this.navigationItems,
    required this.selectedId,
    required this.onSelect,
    required this.content,
    this.primaryAction,
    this.secondaryActions = const <Widget>[],
    this.saveStatus,
  });

  final String title;
  final List<String> breadcrumbs;
  final String? subtitle;
  final List<SettingsNavigationItem> navigationItems;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final Widget content;
  final Widget? primaryAction;
  final List<Widget> secondaryActions;
  final Widget? saveStatus;

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
            trailing: saveStatus,
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 1060;
                final nav = NxCard(
                  padding: const EdgeInsets.all(AppSpacing.component),
                  child: ListView.separated(
                    itemCount: navigationItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = navigationItems[index];
                      final selected = item.id == selectedId;
                      return ListTile(
                        dense: true,
                        leading: Icon(item.icon),
                        selected: selected,
                        selectedTileColor: context.semanticColors.surfaceAlt,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadiusTokens.md,
                          ),
                        ),
                        title: Text(item.label),
                        subtitle: Text(item.description),
                        onTap: () => onSelect(item.id),
                      );
                    },
                  ),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 220, child: nav),
                      const SizedBox(height: AppSpacing.component),
                      Expanded(child: content),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 300, child: nav),
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

class SaveStatusBadge extends StatelessWidget {
  const SaveStatusBadge({
    super.key,
    required this.label,
    this.kind = SaveStatusKind.neutral,
  });

  final String label;
  final SaveStatusKind kind;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final Color background;
    final Color foreground;
    switch (kind) {
      case SaveStatusKind.success:
        background = semantic.success.withValues(alpha: 0.12);
        foreground = semantic.success;
        break;
      case SaveStatusKind.error:
        background = semantic.error.withValues(alpha: 0.12);
        foreground = semantic.error;
        break;
      case SaveStatusKind.working:
        background = semantic.info.withValues(alpha: 0.12);
        foreground = semantic.info;
        break;
      case SaveStatusKind.neutral:
        background = semantic.surfaceAlt;
        foreground = semantic.textSecondary;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: foreground),
      ),
    );
  }
}

enum SaveStatusKind { neutral, success, error, working }
