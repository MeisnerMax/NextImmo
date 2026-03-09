import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final Map<String, bool> _expanded = <String, bool>{
    'Portfolio': true,
    'Operations': true,
    'Governance': true,
    'System': true,
  };

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(globalPageProvider);
    final role = ref.watch(activeUserRoleProvider);
    final semantic = context.semanticColors;
    final colorScheme = Theme.of(context).colorScheme;

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
      width: 254,
      color: colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              'NexImmo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 6),
          for (final group in groups) ...[
            _buildGroupHeader(context, group.title, semantic),
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
                    ),
                ],
              ),
              crossFadeState:
                  (_expanded[group.title] ?? true)
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 150),
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
                  title,
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
    AppSemanticColors semantic,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        selected: isSelected,
        selectedTileColor: semantic.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(
          item.icon,
          color: isSelected ? primary : semantic.textSecondary,
        ),
        title: Text(
          item.label,
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
      ),
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
