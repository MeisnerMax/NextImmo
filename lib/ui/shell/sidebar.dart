import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_strings.dart';
import '../navigation/app_navigation.dart';
import '../state/app_state.dart';
import '../state/security_state.dart';
import '../theme/app_theme.dart';

class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key});

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  static const Color _menuBlue = Color(0xFF030C28);
  static const Color _menuSelected = Color(0xFF17417D);
  static const Color _menuText = Color(0xFFEAF2FF);
  static const Color _menuMuted = Color(0xFFBFD0EA);

  final Map<String, bool> _expanded = <String, bool>{
    'Start': true,
    'Assets & Portfolio': true,
    'Daily Business': true,
    'Valuation & Scenarios': true,
    'Documents & Reporting': true,
    'Setup & Administration': true,
  };

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(globalPageProvider);
    final role = ref.watch(activeUserRoleProvider);
    final semantic = context.semanticColors;
    final zone = context.desktopLayoutZone;
    final collapsed = zone == AppDesktopLayoutZone.narrow;
    final width =
        zone == AppDesktopLayoutZone.large
            ? 254.0
            : zone == AppDesktopLayoutZone.medium
            ? 214.0
            : 86.0;

    final groups = appNavigationGroups
        .map(
          (group) => _SidebarGroup(
            title: group.title,
            items: group.items
                .where(
                  (item) =>
                      role == 'admin' || item.page != GlobalPage.adminUsers,
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

    return Container(
      width: width,
      color: _menuBlue,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: AnimatedOpacity(
                  opacity: collapsed ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 140),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Text(
                      'NexImmo',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _menuText,
                      ),
                    ),
                  ),
                ),
              ),
              if (!collapsed && zone == AppDesktopLayoutZone.medium)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.view_sidebar_outlined,
                    size: 18,
                    color: _menuMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final group in groups) ...[
            if (!collapsed) _buildGroupHeader(context, group.title, semantic),
            if (collapsed)
              const SizedBox(height: 10)
            else
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
                duration: const Duration(milliseconds: 150),
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
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupHeader(
    BuildContext context,
    String title,
    AppSemanticColors semantic,
  ) {
    final expanded = _expanded[title] ?? true;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _expanded[title] = !expanded;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.strings.text(title),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _menuMuted,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: _menuMuted,
              ),
            ],
          ),
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
    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        selected: isSelected,
        selectedTileColor: _menuSelected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(
          item.icon,
          color: isSelected ? Colors.white : _menuMuted,
        ),
        title:
            collapsed
                ? null
                : Text(
                  context.strings.text(item.label),
                  style: TextStyle(
                    color: isSelected ? Colors.white : _menuMuted,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
        onTap: () {
          ref.read(selectedPropertyIdProvider.notifier).state = null;
          ref.read(selectedScenarioIdProvider.notifier).state = null;
          ref.read(propertyDetailPageProvider.notifier).state =
              PropertyDetailPage.overview;
          ref.read(globalPageProvider.notifier).state = item.page;
        },
      ),
    );
    return collapsed
        ? Tooltip(message: context.strings.text(item.label), child: tile)
        : tile;
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
