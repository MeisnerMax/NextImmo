import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_strings.dart';
import '../../navigation/app_navigation.dart';
import '../../state/app_state.dart';
import '../../state/security_state.dart';
import '../../theme/app_theme.dart';

class SidebarV2 extends ConsumerStatefulWidget {
  const SidebarV2({super.key});

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
    final colorScheme = Theme.of(context).colorScheme;
    final zone = context.desktopLayoutZone;
    final collapsed = zone == AppDesktopLayoutZone.narrow || _manualCollapsed;
    final width =
        collapsed
            ? 86.0
            : zone == AppDesktopLayoutZone.medium
            ? 232.0
            : 276.0;

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

    return AnimatedContainer(
      width: width,
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(right: BorderSide(color: semantic.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: AnimatedOpacity(
                  opacity: collapsed ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 120),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Text(
                      'NexImmo',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip:
                    collapsed
                        ? context.strings.text('Expand navigation')
                        : context.strings.text('Collapse navigation'),
                onPressed:
                    zone == AppDesktopLayoutZone.narrow
                        ? null
                        : () => setState(
                          () => _manualCollapsed = !_manualCollapsed,
                        ),
                icon: Icon(
                  collapsed ? Icons.chevron_right : Icons.chevron_left,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final group in groups) ...[
            if (!collapsed) _buildGroupHeader(context, group.title, semantic),
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
                    color: semantic.textSecondary,
                    letterSpacing: 0.4,
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
    final primary = Theme.of(context).colorScheme.primary;
    final tile = ListTile(
      visualDensity: VisualDensity.compact,
      selected: isSelected,
      selectedTileColor: semantic.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                  color: isSelected ? primary : null,
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
    );
    if (collapsed) {
      return Tooltip(message: context.strings.text(item.label), child: tile);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: tile,
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
