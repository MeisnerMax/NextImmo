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
        label: 'Mitteilungen',
        title: 'Mitteilungen',
        routeKey: 'start.notifications',
        icon: Icons.notifications_none,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'Objekte & Portfolio',
    routeKey: 'assets_portfolio',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.properties,
        label: 'Objekte',
        title: 'Objekte',
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
    title: 'Tagesgeschaeft',
    routeKey: 'daily_business',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.tasks,
        label: 'Aufgaben',
        title: 'Aufgaben',
        routeKey: 'daily_business.tasks',
        icon: Icons.checklist_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.maintenance,
        label: 'Instandhaltung',
        title: 'Instandhaltung',
        routeKey: 'daily_business.maintenance',
        icon: Icons.build_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.contractors,
        label: 'Handwerker',
        title: 'Handwerker-Stammdaten',
        routeKey: 'daily_business.contractors',
        icon: Icons.engineering_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.budgets,
        label: 'Budget & Ist',
        title: 'Budget & Ist',
        routeKey: 'daily_business.budgets',
        icon: Icons.grid_view_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.ledger,
        label: 'Buchungen',
        title: 'Buchungen',
        routeKey: 'daily_business.ledger',
        icon: Icons.receipt_long_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.imports,
        label: 'Datenimporte',
        title: 'Datenimporte',
        routeKey: 'daily_business.imports',
        icon: Icons.upload_file_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.taskTemplates,
        label: 'Aufgabenvorlagen',
        title: 'Aufgabenvorlagen',
        routeKey: 'daily_business.task_templates',
        icon: Icons.checklist_rtl_outlined,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'Bewertung & Szenarien',
    routeKey: 'valuation_scenarios',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.quickScreening,
        label: 'Schnellbewertung',
        title: 'Schnellbewertung',
        routeKey: 'valuation_scenarios.quick_screening',
        icon: Icons.speed_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.criteriaSets,
        label: 'Kriterien',
        title: 'Kriterien',
        routeKey: 'valuation_scenarios.criteria',
        icon: Icons.rule_folder_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.compare,
        label: 'Szenariovergleich',
        title: 'Szenariovergleich',
        routeKey: 'valuation_scenarios.scenario_compare',
        icon: Icons.table_chart_outlined,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'Dokumente & Berichte',
    routeKey: 'documents_reporting',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.documents,
        label: 'Dokumente',
        title: 'Dokumente',
        routeKey: 'documents_reporting.documents',
        icon: Icons.folder_open_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.reportTemplates,
        label: 'Report-Vorlagen',
        title: 'Report-Vorlagen',
        routeKey: 'documents_reporting.report_templates',
        icon: Icons.description_outlined,
      ),
    ],
  ),
  AppNavigationGroup(
    title: 'Setup & Verwaltung',
    routeKey: 'setup_administration',
    items: <GlobalNavigationDestination>[
      GlobalNavigationDestination(
        page: GlobalPage.adminUsers,
        label: 'Benutzer',
        title: 'Benutzer',
        routeKey: 'setup_administration.users',
        icon: Icons.manage_accounts_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.settings,
        label: 'Einstellungen',
        title: 'Einstellungen',
        routeKey: 'setup_administration.settings',
        icon: Icons.settings_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.audit,
        label: 'Audit-Protokoll',
        title: 'Audit-Protokoll',
        routeKey: 'setup_administration.audit_log',
        icon: Icons.fact_check_outlined,
      ),
      GlobalNavigationDestination(
        page: GlobalPage.help,
        label: 'Hilfe',
        title: 'Hilfe',
        routeKey: 'setup_administration.help',
        icon: Icons.help_outline,
      ),
    ],
  ),
];

const List<PropertyNavigationSection> propertyNavigationSections =
    <PropertyNavigationSection>[
      PropertyNavigationSection(
        title: 'Ansicht',
        routeKey: 'properties.view',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.overview,
            label: 'Übersicht',
            routeKey: 'properties.view.overview',
            requiresScenario: true,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Tagesgeschaeft',
        routeKey: 'properties.daily_business',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.units,
            label: 'Einheiten & Mieter',
            routeKey: 'properties.daily_business.units',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.maintenance,
            label: 'Instandhaltung & CapEx',
            routeKey: 'properties.daily_business.maintenance',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.budgetVsActual,
            label: 'Finanzen & Budget',
            routeKey: 'properties.daily_business.budget_vs_actual',
            requiresScenario: false,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Bewertung & Szenarien',
        routeKey: 'properties.valuation_scenarios',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.scenarios,
            label: 'Bewertungen',
            routeKey: 'properties.valuation_scenarios.scenarios',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.inputs,
            label: 'Ankauf Intensivbewertung',
            routeKey: 'properties.valuation_scenarios.inputs',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.analysis,
            label: 'Underwriting',
            routeKey: 'properties.valuation_scenarios.analysis',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.offer,
            label: 'Angebotsrechner',
            routeKey: 'properties.valuation_scenarios.offer',
            requiresScenario: true,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Dokumente & Historie',
        routeKey: 'properties.documents_reporting',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.documents,
            label: 'Dokumente & Historie',
            routeKey: 'properties.documents_reporting.documents',
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

const List<PropertyNavigationSection> allPropertyNavigationSections =
    <PropertyNavigationSection>[
      PropertyNavigationSection(
        title: 'Ansicht',
        routeKey: 'properties.view',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.overview,
            label: 'Übersicht',
            routeKey: 'properties.view.overview',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.operationsOverview,
            label: 'Betriebsübersicht',
            routeKey: 'properties.view.operations_overview',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.alerts,
            label: 'Warnungen',
            routeKey: 'properties.view.alerts',
            requiresScenario: false,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Tagesgeschaeft',
        routeKey: 'properties.daily_business',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.units,
            label: 'Einheiten & Mieter',
            routeKey: 'properties.daily_business.units',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.tenants,
            label: 'Mieter',
            routeKey: 'properties.daily_business.tenants',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.leases,
            label: 'Mietverträge',
            routeKey: 'properties.daily_business.leases',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.rentRoll,
            label: 'Soll-Mieten',
            routeKey: 'properties.daily_business.rent_roll',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.tasks,
            label: 'Aufgaben',
            routeKey: 'properties.daily_business.tasks',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.maintenance,
            label: 'Instandhaltung & CapEx',
            routeKey: 'properties.daily_business.maintenance',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.budgetVsActual,
            label: 'Finanzen & Budget',
            routeKey: 'properties.daily_business.budget_vs_actual',
            requiresScenario: false,
          ),
        ],
      ),
      PropertyNavigationSection(
        title: 'Bewertung & Szenarien',
        routeKey: 'properties.valuation_scenarios',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.scenarios,
            label: 'Bewertungen',
            routeKey: 'properties.valuation_scenarios.scenarios',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.inputs,
            label: 'Ankauf Intensivbewertung',
            routeKey: 'properties.valuation_scenarios.inputs',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.analysis,
            label: 'Underwriting',
            routeKey: 'properties.valuation_scenarios.analysis',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.comps,
            label: 'Vergleichsobjekte',
            routeKey: 'properties.valuation_scenarios.comps',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.criteria,
            label: 'Kriterienprüfung',
            routeKey: 'properties.valuation_scenarios.criteria',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.offer,
            label: 'Angebotsrechner',
            routeKey: 'properties.valuation_scenarios.offer',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.versions,
            label: 'Versionen',
            routeKey: 'properties.valuation_scenarios.versions',
            requiresScenario: true,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.assetWorkbook,
            label: 'Asset Workbook',
            routeKey: 'properties.valuation_scenarios.asset_workbook',
            requiresScenario: false,
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
        title: 'Dokumente & Historie',
        routeKey: 'properties.documents_reporting',
        items: <PropertyNavigationDestination>[
          PropertyNavigationDestination(
            page: PropertyDetailPage.documents,
            label: 'Dokumente & Historie',
            routeKey: 'properties.documents_reporting.documents',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.audit,
            label: 'Historie',
            routeKey: 'properties.documents_reporting.audit',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.reports,
            label: 'Berichte',
            routeKey: 'properties.documents_reporting.reports',
            requiresScenario: false,
          ),
        ],
      ),
    ];

PropertyNavigationDestination propertyDestinationForPage(
  PropertyDetailPage page,
) {
  for (final section in allPropertyNavigationSections) {
    for (final item in section.items) {
      if (item.page == page) {
        return item;
      }
    }
  }
  throw ArgumentError.value(page, 'page', 'Unknown property detail page');
}

PropertyNavigationSection propertySectionForPage(PropertyDetailPage page) {
  for (final section in allPropertyNavigationSections) {
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

bool isPageAllowedForRole(GlobalPage page, String role) {
  final normalizedRole = role.trim().toLowerCase();
  
  if (normalizedRole == 'admin' ||
      normalizedRole == 'administrator' ||
      normalizedRole == 'asset_manager' ||
      normalizedRole == 'manager') {
    return true;
  }

  switch (normalizedRole) {
    case 'hausmeister':
    case 'bauleiter':
    case 'bauarbeiter':
    case 'housekeeping':
    case 'externer_dienstleister':
      return page == GlobalPage.dashboard ||
          page == GlobalPage.notifications ||
          page == GlobalPage.properties ||
          page == GlobalPage.tasks ||
          page == GlobalPage.maintenance ||
          page == GlobalPage.help;

    case 'vermietung':
      return page == GlobalPage.dashboard ||
          page == GlobalPage.notifications ||
          page == GlobalPage.properties ||
          page == GlobalPage.tasks ||
          page == GlobalPage.help;

    case 'buerokraft':
      return page == GlobalPage.dashboard ||
          page == GlobalPage.notifications ||
          page == GlobalPage.properties ||
          page == GlobalPage.tasks ||
          page == GlobalPage.documents ||
          page == GlobalPage.help;

    case 'buchhaltung':
      return page != GlobalPage.adminUsers &&
          page != GlobalPage.settings &&
          page != GlobalPage.audit &&
          page != GlobalPage.criteriaSets &&
          page != GlobalPage.compare &&
          page != GlobalPage.quickScreening;

    case 'viewer':
      return page != GlobalPage.adminUsers &&
          page != GlobalPage.settings &&
          page != GlobalPage.audit &&
          page != GlobalPage.imports;

    default:
      return true;
  }
}
