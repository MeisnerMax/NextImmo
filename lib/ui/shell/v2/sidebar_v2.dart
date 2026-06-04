import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_strings.dart';
import '../../navigation/app_navigation.dart';
import '../../state/app_state.dart';
import '../../state/security_state.dart';
import '../../theme/app_theme.dart';

class SidebarV2 extends ConsumerStatefulWidget {
  const SidebarV2({
    super.key,
    this.forceExpanded = false,
    this.drawerMode = false,
    this.onDestinationSelected,
  });

  final bool forceExpanded;
  final bool drawerMode;
  final VoidCallback? onDestinationSelected;

  @override
  ConsumerState<SidebarV2> createState() => _SidebarV2State();
}

class _SidebarV2State extends ConsumerState<SidebarV2> {
  final Map<String, bool> _expanded = <String, bool>{
    'Portfolio': true,
    'Operations': true,
    'Governance': true,
    'System': true,
  };
  bool _manualCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(globalPageProvider);
    final role = ref.watch(activeUserRoleProvider);
    final semantic = context.semanticColors;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final zone = context.desktopLayoutZone;
    final collapsed =
        !widget.forceExpanded &&
        (zone == AppDesktopLayoutZone.narrow || _manualCollapsed);
    final width =
        widget.drawerMode
            ? 320.0
            : collapsed
            ? 86.0
            : zone == AppDesktopLayoutZone.medium
            ? 232.0
            : 276.0;

    final groups =
        appNavigationGroups
            .map(
              (group) => _SidebarGroup(
                title: group.title,
                items:
                    group.items
                        .where(
                          (item) =>
                              role == 'admin' ||
                              item.page != GlobalPage.adminUsers,
                        )
                        .map(
                          (item) => _SidebarItem(
                            page: item.page,
                            icon: item.icon,
                            label: item.label,
                          ),
                        )
                        .toList(growable: false),
              ),
            )
            .toList(growable: false);

    return AnimatedContainer(
      width: width,
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: const Color(0xFF030C28),
        border: Border(right: BorderSide(color: semantic.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 36),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                    border: Border.all(color: semantic.border),
                  ),
                  child: Icon(
                    Icons.account_balance,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Capital Management',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Venture Fund III',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: semantic.textSecondary,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!widget.drawerMode && zone != AppDesktopLayoutZone.narrow)
                  IconButton(
                    tooltip:
                        collapsed
                            ? context.strings.text('Expand navigation')
                            : context.strings.text('Collapse navigation'),
                    onPressed:
                        () => setState(
                          () => _manualCollapsed = !_manualCollapsed,
                        ),
                    icon: Icon(
                      collapsed ? Icons.chevron_right : Icons.chevron_left,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final group in groups) ...[
                  if (!collapsed)
                    _buildGroupHeader(context, group.title, semantic),
                  if (!collapsed)
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        children: [
                          for (final item in group.items)
                            _buildItemTile(
                              context,
                              item,
                              selected == item.page,
                              semantic,
                              collapsed: collapsed,
                            ),
                        ],
                      ),
                      crossFadeState:
                          (_expanded[group.title] ?? true)
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 140),
                    ),
                  if (collapsed)
                    ...group.items.map(
                      (item) => _buildItemTile(
                        context,
                        item,
                        selected == item.page,
                        semantic,
                        collapsed: collapsed,
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 16, 30, 28),
            child:
                collapsed
                    ? IconButton.filled(
                      tooltip: context.strings.text('New Acquisition'),
                      onPressed: _openAcquisitionFlow,
                      icon: const Icon(Icons.add),
                    )
                    : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _openAcquisitionFlow,
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(context.strings.text('New Acquisition')),
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  void _openAcquisitionFlow() {
    ref.read(selectedPropertyIdProvider.notifier).state = null;
    ref.read(selectedScenarioIdProvider.notifier).state = null;
    ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
    widget.onDestinationSelected?.call();
  }

  Widget _buildGroupHeader(
    BuildContext context,
    String title,
    AppSemanticColors semantic,
  ) {
    final expanded = _expanded[title] ?? true;
    return InkWell(
      onTap: () {
        setState(() {
          _expanded[title] = !expanded;
        });
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 10, 24, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.strings.text(title).toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: semantic.textSecondary,
                  letterSpacing: 1.6,
                ),
              ),
            ),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: semantic.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(
    BuildContext context,
    _SidebarItem item,
    bool isSelected,
    AppSemanticColors semantic, {
    required bool collapsed,
  }) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final tile = ListTile(
      visualDensity: VisualDensity.compact,
      selected: isSelected,
      selectedTileColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.24,
      ),
      shape: const RoundedRectangleBorder(),
      leading: Icon(
        item.icon,
        color: isSelected ? primary : semantic.textSecondary,
      ),
      title:
          collapsed
              ? null
              : Text(
                context.strings.text(item.label),
                style: TextStyle(
                  color: isSelected ? primary : semantic.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
      onTap: () {
        ref.read(selectedPropertyIdProvider.notifier).state = null;
        ref.read(selectedScenarioIdProvider.notifier).state = null;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.overview;
        ref.read(globalPageProvider.notifier).state = item.page;
        widget.onDestinationSelected?.call();
      },
    );
    final wrapped = DecoratedBox(
      decoration: BoxDecoration(
        border:
            isSelected ? Border(right: BorderSide(color: primary, width: 2)) : null,
      ),
      child: tile,
    );
    if (collapsed) {
      return Tooltip(message: context.strings.text(item.label), child: wrapped);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: wrapped,
    );
  }
}

class _SidebarGroup {
  const _SidebarGroup({required this.title, required this.items});

  final String title;
  final List<_SidebarItem> items;
}

class _SidebarItem {
  const _SidebarItem({
    required this.page,
    required this.icon,
    required this.label,
  });

  final GlobalPage page;
  final IconData icon;
  final String label;
}
