import 'package:flutter/material.dart';

import '../state/app_state.dart';

class AppNavigationGroup {
  const AppNavigationGroup({
    required this.title,
    required this.routeKey,
    required this.items,
  });

  final String title;
  final String routeKey;
  final List<GlobalNavigationDestination> items;
}

class GlobalNavigationDestination {
  const GlobalNavigationDestination({
    required this.page,
    required this.label,
    required this.title,
    required this.routeKey,
    required this.icon,
  });

  final GlobalPage page;
  final String label;
  final String title;
  final String routeKey;
  final IconData icon;
}

class PropertyNavigationSection {
  const PropertyNavigationSection({
    required this.title,
    required this.routeKey,
    required this.items,
  });

  final String title;
  final String routeKey;
  final List<PropertyNavigationDestination> items;
}

class PropertyNavigationDestination {
  const PropertyNavigationDestination({
    required this.page,
    required this.label,
    required this.routeKey,
    required this.requiresScenario,
  });

  final PropertyDetailPage page;
  final String label;
  final String routeKey;
  final bool requiresScenario;
}

const List<AppNavigationGroup> appNavigationGroups = <AppNavigationGroup>[
  AppNavigationGroup(
    title: 'Portfolio',
    routeKey: 'portfolio',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.dashboard,
        label: 'Dashboard',
        title: 'Dashboard',
        routeKey: 'portfolio.dashboard',
        icon: Icons.dashboard_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.properties,
        label: 'Properties',
        title: 'Properties',
        routeKey: 'portfolio.properties',
        icon: Icons.home_work_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.portfolios,
        label: 'Portfolios',
        title: 'Portfolios',
        routeKey: 'portfolio.portfolios',
        icon: Icons.account_tree_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.compare,
        label: 'Scenario Compare',
        title: 'Scenario Compare',
        routeKey: 'portfolio.scenario_compare',
        icon: Icons.table_chart_outlined,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'Operations',
    routeKey: 'operations',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.tasks,
        label: 'Tasks',
        title: 'Tasks',
        routeKey: 'operations.tasks',
        icon: Icons.checklist_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.taskTemplates,
        label: 'Task Templates',
        title: 'Task Templates',
        routeKey: 'operations.task_templates',
        icon: Icons.checklist_rtl_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.maintenance,
        label: 'Maintenance',
        title: 'Maintenance',
        routeKey: 'operations.maintenance',
        icon: Icons.build_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.ledger,
        label: 'Ledger',
        title: 'Ledger',
        routeKey: 'operations.ledger',
        icon: Icons.receipt_long_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.budgets,
        label: 'Budgets',
        title: 'Budgets',
        routeKey: 'operations.budgets',
        icon: Icons.grid_view_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.imports,
        label: 'Data Imports',
        title: 'Data Imports',
        routeKey: 'operations.imports',
        icon: Icons.upload_file_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.notifications,
        label: 'Notifications',
        title: 'Notifications',
        routeKey: 'operations.notifications',
        icon: Icons.notifications_none,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'Governance',
    routeKey: 'governance',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.documents,
        label: 'Documents',
        title: 'Documents',
        routeKey: 'governance.documents',
        icon: Icons.folder_open_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.audit,
        label: 'Audit Log',
        title: 'Audit Log',
        routeKey: 'governance.audit_log',
        icon: Icons.fact_check_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.esg,
        label: 'ESG',
        title: 'ESG',
        routeKey: 'governance.esg',
        icon: Icons.eco_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.criteriaSets,
        label: 'Criteria',
        title: 'Criteria',
        routeKey: 'governance.criteria',
        icon: Icons.rule_folder_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.reportTemplates,
        label: 'Templates',
        title: 'Templates',
        routeKey: 'governance.templates',
        icon: Icons.description_outlined,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'System',
    routeKey: 'system',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.adminUsers,
        label: 'Users',
        title: 'Users',
        routeKey: 'system.users',
        icon: Icons.manage_accounts_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.settings,
        label: 'Settings',
        title: 'Settings',
        routeKey: 'system.settings',
        icon: Icons.settings_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.help,
        label: 'Help',
        title: 'Help',
        routeKey: 'system.help',
        icon: Icons.help_outline,
      ),
    ],
  ),
];

const List<PropertyNavigationSection> propertyNavigationSections =
    <PropertyNavigationSection>[
      PropertyNavigationSection(
        title: 'Summary',
        routeKey: 'properties.summary',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.overview,
            label: 'Overview',
            routeKey: 'properties.summary.overview',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.inputs,
            label: 'Inputs',
            routeKey: 'properties.summary.inputs',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.analysis,
            label: 'Analysis',
            routeKey: 'properties.summary.analysis',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.comps,
            label: 'Market Comps',
            routeKey: 'properties.summary.market_comps',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.offer,
            label: 'Offer',
            routeKey: 'properties.summary.offer',
            requiresScenario: true,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Commercial',
        routeKey: 'properties.commercial',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.units,
            label: 'Units',
            routeKey: 'properties.commercial.units',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.tenants,
            label: 'Tenants',
            routeKey: 'properties.commercial.tenants',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.leases,
            label: 'Leases',
            routeKey: 'properties.commercial.leases',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.rentRoll,
            label: 'Rent Roll',
            routeKey: 'properties.commercial.rent_roll',
            requiresScenario: false,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Operations',
        routeKey: 'properties.operations',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.operationsOverview,
            label: 'Operations Center',
            routeKey: 'properties.operations.center',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.tasks,
            label: 'Tasks',
            routeKey: 'properties.operations.tasks',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.maintenance,
            label: 'Maintenance',
            routeKey: 'properties.operations.maintenance',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.budgetVsActual,
            label: 'Budget vs Actual',
            routeKey: 'properties.operations.budget_vs_actual',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.alerts,
            label: 'Alerts',
            routeKey: 'properties.operations.alerts',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.covenants,
            label: 'Covenants',
            routeKey: 'properties.operations.covenants',
            requiresScenario: false,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Governance',
        routeKey: 'properties.governance',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.documents,
            label: 'Documents',
            routeKey: 'properties.governance.documents',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.audit,
            label: 'Audit',
            routeKey: 'properties.governance.audit',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.criteria,
            label: 'Criteria',
            routeKey: 'properties.governance.criteria',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.reports,
            label: 'Reports',
            routeKey: 'properties.governance.reports',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.versions,
            label: 'Versions',
            routeKey: 'properties.governance.versions',
            requiresScenario: true,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Scenario',
        routeKey: 'properties.scenario',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.scenarios,
            label: 'Scenarios',
            routeKey: 'properties.scenario.scenarios',
            requiresScenario: false,
          ),
        ],
      ),
    ];

GlobalNavigationDestination navigationDestinationForPage(GlobalPage page) {
  for (final group in appNavigationGroups) {
    for (final item in group.items) {
      if (item.page == page) {
        return item;
      }
    }
  }
  throw ArgumentError.value(page, 'page', 'Unknown global page');
}

AppNavigationGroup navigationGroupForPage(GlobalPage page) {
  for (final group in appNavigationGroups) {
    for (final item in group.items) {
      if (item.page == page) {
        return group;
      }
    }
  }
  throw ArgumentError.value(page, 'page', 'Unknown global page');
}

PropertyNavigationDestination propertyDestinationForPage(
  PropertyDetailPage page,
) {
  for (final section in propertyNavigationSections) {
    for (final item in section.items) {
      if (item.page == page) {
        return item;
      }
    }
  }
  throw ArgumentError.value(page, 'page', 'Unknown property detail page');
}

PropertyNavigationSection propertySectionForPage(PropertyDetailPage page) {
  for (final section in propertyNavigationSections) {
    for (final item in section.items) {
      if (item.page == page) {
        return section;
      }
    }
  }
  throw ArgumentError.value(page, 'page', 'Unknown property detail page');
}

bool propertyPageRequiresScenario(PropertyDetailPage page) {
  return propertyDestinationForPage(page).requiresScenario;
}

List<String> propertyBreadcrumbs({
  required String propertyName,
  required PropertyDetailPage page,
}) {
  final section = propertySectionForPage(page);
  final destination = propertyDestinationForPage(page);
  return <String>[
    'Portfolio',
    'Properties',
    propertyName,
    section.title,
    destination.label,
  ];
}
