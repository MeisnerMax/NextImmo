import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(globalPageProvider);
    final role = ref.watch(activeUserRoleProvider);
    final semantic = context.semanticColors;
    final colorScheme = Theme.of(context).colorScheme;
    final width = _collapsed ? 86.0 : 276.0;

    final groups = <_SidebarGroup>[
      _SidebarGroup(
        title: 'Portfolio',
        items: const [
          _SidebarItem(
            page: GlobalPage.dashboard,
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
          ),
          _SidebarItem(
            page: GlobalPage.properties,
            icon: Icons.home_work_outlined,
            label: 'Properties',
          ),
          _SidebarItem(
            page: GlobalPage.portfolios,
            icon: Icons.account_tree_outlined,
            label: 'Portfolios',
          ),
          _SidebarItem(
            page: GlobalPage.compare,
            icon: Icons.table_chart_outlined,
            label: 'Compare',
          ),
        ],
      ),
      _SidebarGroup(
        title: 'Operations',
        items: const [
          _SidebarItem(
            page: GlobalPage.ledger,
            icon: Icons.receipt_long_outlined,
            label: 'Ledger',
          ),
          _SidebarItem(
            page: GlobalPage.budgets,
            icon: Icons.grid_view_outlined,
            label: 'Budgets',
          ),
          _SidebarItem(
            page: GlobalPage.maintenance,
            icon: Icons.build_outlined,
            label: 'Maintenance',
          ),
          _SidebarItem(
            page: GlobalPage.tasks,
            icon: Icons.checklist_outlined,
            label: 'Tasks',
          ),
          _SidebarItem(
            page: GlobalPage.taskTemplates,
            icon: Icons.checklist_rtl_outlined,
            label: 'Task Templates',
          ),
          _SidebarItem(
            page: GlobalPage.imports,
            icon: Icons.upload_file_outlined,
            label: 'Imports',
          ),
          _SidebarItem(
            page: GlobalPage.notifications,
            icon: Icons.notifications_none,
            label: 'Notifications',
          ),
        ],
      ),
      _SidebarGroup(
        title: 'Governance',
        items: const [
          _SidebarItem(
            page: GlobalPage.esg,
            icon: Icons.eco_outlined,
            label: 'ESG',
          ),
          _SidebarItem(
            page: GlobalPage.documents,
            icon: Icons.folder_open_outlined,
            label: 'Documents',
          ),
          _SidebarItem(
            page: GlobalPage.audit,
            icon: Icons.fact_check_outlined,
            label: 'Audit',
          ),
          _SidebarItem(
            page: GlobalPage.criteriaSets,
            icon: Icons.rule_folder_outlined,
            label: 'Criteria Sets',
          ),
          _SidebarItem(
            page: GlobalPage.reportTemplates,
            icon: Icons.description_outlined,
            label: 'Templates',
          ),
        ],
      ),
      _SidebarGroup(
        title: 'System',
        items: [
          if (role == 'admin')
            const _SidebarItem(
              page: GlobalPage.adminUsers,
              icon: Icons.manage_accounts_outlined,
              label: 'Users',
            ),
          const _SidebarItem(
            page: GlobalPage.settings,
            icon: Icons.settings_outlined,
            label: 'Settings',
          ),
          const _SidebarItem(
            page: GlobalPage.help,
            icon: Icons.help_outline,
            label: 'Help',
          ),
        ],
      ),
    ];

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
                  opacity: _collapsed ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 120),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Text('NexImmo', style: Theme.of(context).textTheme.titleLarge),
                  ),
                ),
              ),
              IconButton(
                tooltip: _collapsed ? 'Expand navigation' : 'Collapse navigation',
                onPressed: () => setState(() => _collapsed = !_collapsed),
                icon: Icon(_collapsed ? Icons.chevron_right : Icons.chevron_left),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
              crossFadeState: (!_collapsed && (_expanded[group.title] ?? true))
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 140),
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
    if (_collapsed) {
      return const SizedBox(height: 10);
    }
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
    final tile = ListTile(
      visualDensity: VisualDensity.compact,
      selected: isSelected,
      selectedTileColor: semantic.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(
        item.icon,
        color: isSelected ? primary : semantic.textSecondary,
      ),
      title: _collapsed
          ? null
          : Text(
              item.label,
              style: TextStyle(
                color: isSelected ? primary : null,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
      onTap: () {
        ref.read(selectedPropertyIdProvider.notifier).state = null;
        ref.read(globalPageProvider.notifier).state = item.page;
      },
    );
    if (_collapsed) {
      return Tooltip(message: item.label, child: tile);
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
