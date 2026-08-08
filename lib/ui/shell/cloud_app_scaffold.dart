import 'package:flutter/material.dart';

import '../navigation/app_navigation.dart';
import '../theme/app_theme.dart';

class CloudAppScaffold extends StatelessWidget {
  const CloudAppScaffold({
    super.key,
    required this.activeRoute,
    required this.child,
  });

  final String? activeRoute;
  final Widget child;

  static const _destinations = <_CloudDestination>[
    _CloudDestination(
      label: 'Properties',
      icon: Icons.apartment_outlined,
      selectedIcon: Icons.apartment,
      route: referencePropertiesRoute,
    ),
    _CloudDestination(
      label: 'Parties',
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
      route: partiesRoute,
    ),
    _CloudDestination(
      label: 'Documents',
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder,
      route: documentsWorkspaceRoute,
    ),
    _CloudDestination(
      label: 'Compliance',
      icon: Icons.verified_user_outlined,
      selectedIcon: Icons.verified_user,
      route: complianceRoute,
    ),
    _CloudDestination(
      label: 'Members',
      icon: Icons.manage_accounts_outlined,
      selectedIcon: Icons.manage_accounts,
      route: referenceMembersRoute,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex(activeRoute);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= AppBreakpoints.mobileMax) {
          return Scaffold(
            key: const Key('cloud-shell-mobile'),
            appBar: AppBar(title: const Text('NexImmo')),
            drawer: NavigationDrawer(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                Navigator.of(context).pop();
                _open(context, index);
              },
              children: [
                const SizedBox(height: AppSpacing.sm),
                for (final destination in _destinations)
                  NavigationDrawerDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            body: child,
          );
        }

        return Scaffold(
          key: const Key('cloud-shell-wide'),
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  extended: constraints.maxWidth > AppBreakpoints.tabletMax,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) => _open(context, index),
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Icon(Icons.domain, semanticLabel: 'NexImmo'),
                  ),
                  destinations: [
                    for (final destination in _destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          ),
        );
      },
    );
  }

  int _selectedIndex(String? route) {
    if (propertyDocumentsPropertyIdFromRoute(route) != null) {
      return 2;
    }
    if (referencePropertyIdFromRoute(route) != null) {
      return 0;
    }
    final index = _destinations.indexWhere(
      (destination) => destination.route == route,
    );
    return index < 0 ? 0 : index;
  }

  void _open(BuildContext context, int index) {
    final destination = _destinations[index];
    if (destination.route == activeRoute) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(destination.route);
  }
}

class _CloudDestination {
  const _CloudDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
}
