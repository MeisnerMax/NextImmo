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
    title: 'Start',
    routeKey: 'start',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.dashboard,
        label: 'Dashboard',
        title: 'Dashboard',
        routeKey: 'start.dashboard',
        icon: Icons.dashboard_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.notifications,
        label: 'Notifications',
        title: 'Notifications',
        routeKey: 'start.notifications',
        icon: Icons.notifications_none,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'Assets & Portfolio',
    routeKey: 'assets_portfolio',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.properties,
        label: 'Properties',
        title: 'Properties',
        routeKey: 'assets_portfolio.properties',
        icon: Icons.home_work_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.portfolios,
        label: 'Portfolios',
        title: 'Portfolios',
        routeKey: 'assets_portfolio.portfolios',
        icon: Icons.account_tree_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.esg,
        label: 'ESG',
        title: 'ESG',
        routeKey: 'assets_portfolio.esg',
        icon: Icons.eco_outlined,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'Daily Business',
    routeKey: 'daily_business',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.tasks,
        label: 'Tasks',
        title: 'Tasks',
        routeKey: 'daily_business.tasks',
        icon: Icons.checklist_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.maintenance,
        label: 'Maintenance',
        title: 'Maintenance',
        routeKey: 'daily_business.maintenance',
        icon: Icons.build_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.budgets,
        label: 'Budgets & Actuals',
        title: 'Budgets & Actuals',
        routeKey: 'daily_business.budgets',
        icon: Icons.grid_view_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.ledger,
        label: 'Ledger',
        title: 'Ledger',
        routeKey: 'daily_business.ledger',
        icon: Icons.receipt_long_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.imports,
        label: 'Data Imports',
        title: 'Data Imports',
        routeKey: 'daily_business.imports',
        icon: Icons.upload_file_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.taskTemplates,
        label: 'Task Templates',
        title: 'Task Templates',
        routeKey: 'daily_business.task_templates',
        icon: Icons.checklist_rtl_outlined,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'Valuation & Scenarios',
    routeKey: 'valuation_scenarios',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.criteriaSets,
        label: 'Criteria',
        title: 'Criteria',
        routeKey: 'valuation_scenarios.criteria',
        icon: Icons.rule_folder_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.compare,
        label: 'Scenario Compare',
        title: 'Scenario Compare',
        routeKey: 'valuation_scenarios.scenario_compare',
        icon: Icons.table_chart_outlined,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'Documents & Reporting',
    routeKey: 'documents_reporting',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.documents,
        label: 'Documents',
        title: 'Documents',
        routeKey: 'documents_reporting.documents',
        icon: Icons.folder_open_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.reportTemplates,
        label: 'Report Templates',
        title: 'Report Templates',
        routeKey: 'documents_reporting.report_templates',
        icon: Icons.description_outlined,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'Setup & Administration',
    routeKey: 'setup_administration',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.adminUsers,
        label: 'Users',
        title: 'Users',
        routeKey: 'setup_administration.users',
        icon: Icons.manage_accounts_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.settings,
        label: 'Settings',
        title: 'Settings',
        routeKey: 'setup_administration.settings',
        icon: Icons.settings_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.audit,
        label: 'Audit Log',
        title: 'Audit Log',
        routeKey: 'setup_administration.audit_log',
        icon: Icons.fact_check_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.help,
        label: 'Help',
        title: 'Help',
        routeKey: 'setup_administration.help',
        icon: Icons.help_outline,
      ),
    ],
  ),
];

const List<PropertyNavigationSection> propertyNavigationSections =
    <PropertyNavigationSection>[
      PropertyNavigationSection(
        title: 'View',
        routeKey: 'properties.view',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.overview,
            label: 'Overview',
            routeKey: 'properties.view.overview',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.audit,
            label: 'Activity',
            routeKey: 'properties.view.activity',
            requiresScenario: false,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Daily Business',
        routeKey: 'properties.daily_business',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.operationsOverview,
            label: 'Daily Business',
            routeKey: 'properties.daily_business.center',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.units,
            label: 'Units',
            routeKey: 'properties.daily_business.units',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.tenants,
            label: 'Tenants',
            routeKey: 'properties.daily_business.tenants',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.leases,
            label: 'Leases',
            routeKey: 'properties.daily_business.leases',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.rentRoll,
            label: 'Rent Management',
            routeKey: 'properties.daily_business.rent_roll',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.tasks,
            label: 'Tasks',
            routeKey: 'properties.daily_business.tasks',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.maintenance,
            label: 'Maintenance',
            routeKey: 'properties.daily_business.maintenance',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.budgetVsActual,
            label: 'Budget vs Actual',
            routeKey: 'properties.daily_business.budget_vs_actual',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.alerts,
            label: 'Alerts',
            routeKey: 'properties.daily_business.alerts',
            requiresScenario: false,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Valuation & Scenarios',
        routeKey: 'properties.valuation_scenarios',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.scenarios,
            label: 'Scenarios',
            routeKey: 'properties.valuation_scenarios.scenarios',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.inputs,
            label: 'Valuation Inputs',
            routeKey: 'properties.valuation_scenarios.inputs',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.analysis,
            label: 'Analysis',
            routeKey: 'properties.valuation_scenarios.analysis',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.comps,
            label: 'Market Comps',
            routeKey: 'properties.valuation_scenarios.market_comps',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.offer,
            label: 'Offer',
            routeKey: 'properties.valuation_scenarios.offer',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.criteria,
            label: 'Criteria',
            routeKey: 'properties.valuation_scenarios.criteria',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.versions,
            label: 'Versions',
            routeKey: 'properties.valuation_scenarios.versions',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.covenants,
            label: 'Covenants',
            routeKey: 'properties.valuation_scenarios.covenants',
            requiresScenario: false,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Documents & Reporting',
        routeKey: 'properties.documents_reporting',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.documents,
            label: 'Documents',
            routeKey: 'properties.documents_reporting.documents',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.reports,
            label: 'Reports',
            routeKey: 'properties.documents_reporting.reports',
            requiresScenario: true,
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
    propertyName,
    section.title,
    destination.label,
  ];
}
