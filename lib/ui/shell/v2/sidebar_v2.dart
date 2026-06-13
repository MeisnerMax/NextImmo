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
  bool _manualCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(globalPageProvider);
    final role = ref.watch(activeUserRoleProvider);
    final semantic = context.semanticColors;
    final theme = Theme.of(context);
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
                          (item) => isPageAllowedForRole(item.page, role),
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
        color: _menuBlue,
        border: const Border(right: BorderSide(color: Color(0xFF17417D))),
      ),
      child: Column(
        children: [
          Padding(
            padding:
                collapsed
                    ? const EdgeInsets.fromLTRB(12, 48, 12, 24)
                    : const EdgeInsets.fromLTRB(24, 48, 24, 36),
            child:
                collapsed
                    ? Center(
                      child: IconButton(
                        tooltip: context.strings.text('Expand navigation'),
                        onPressed:
                            () => setState(() => _manualCollapsed = false),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    )
                    : Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _menuSelected,
                            borderRadius: BorderRadius.circular(
                              AppRadiusTokens.sm,
                            ),
                            border: Border.all(color: _menuSelected),
                          ),
                          child: Icon(
                            Icons.account_balance,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '613 Investment Group GmbH',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: _menuText,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Asset Management',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: _menuMuted,
                                  letterSpacing: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!widget.drawerMode &&
                            zone != AppDesktopLayoutZone.narrow)
                          IconButton(
                            tooltip: context.strings.text(
                              'Collapse navigation',
                            ),
                            onPressed:
                                () => setState(() => _manualCollapsed = true),
                            icon: const Icon(Icons.chevron_left),
                          ),
                      ],
                    ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final group in groups) ...[
                  if (group.items.isNotEmpty) ...[
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
              ],
            ),
          ),
          Padding(
            padding:
                collapsed
                    ? const EdgeInsets.fromLTRB(12, 16, 12, 28)
                    : const EdgeInsets.fromLTRB(30, 16, 30, 28),
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
                  color: _menuMuted,
                  letterSpacing: 1.6,
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
    const primary = Colors.white;
    final tile = ListTile(
      visualDensity: VisualDensity.compact,
      selected: isSelected,
      selectedTileColor: _menuSelected,
      shape: const RoundedRectangleBorder(),
      leading: Icon(
        item.icon,
        color: isSelected ? primary : _menuMuted,
      ),
      title:
          collapsed
              ? null
              : Text(
                context.strings.text(item.label),
                style: TextStyle(
                  color: isSelected ? primary : _menuMuted,
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
            isSelected ? const Border(right: BorderSide(color: primary, width: 2)) : null,
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
