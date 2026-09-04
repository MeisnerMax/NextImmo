import 'package:flutter/material.dart';
import '../../core/security/rbac.dart';

import '../state/app_state.dart';

const referencePropertiesRoute = '/properties';
const referenceMembersRoute = '/members';

/// Wave 2 screens live in `AppScaffold`, which only mounts in local mode. So
/// that their mutation paths can be exercised against the real backend, cloud
/// mode reaches them through additive routes alongside the reference slice.
const partiesRoute = '/parties';

/// The property-scoped documents panel is the one Wave 2 surface that needs an
/// object, and in cloud mode there is no `PropertyShell` to take it from — so
/// the id travels in the route, the same shape the reference slice already uses
/// for a property detail.
const propertyDocumentsRoute = '/property-documents';

/// The workspace-wide documents workplace (SCR-051). Needs no parameter: its
/// scope is the workspace of the authenticated session. Mounts the panel, not
/// the local four-tab host, whose remaining tabs read legacy repositories that
/// do not exist in cloud mode.
const documentsWorkspaceRoute = '/documents';

/// The workspace compliance dashboard (SCR-052). Workspace-scoped like the
/// documents workplace, so it needs no parameter; its finding rows jump to
/// [propertyDocumentsRoute].
const complianceRoute = '/compliance';

/// Welle 3 surfaces, same reasoning as the Welle-2 routes above: the leasing
/// panels live in `PropertyShell`, which only mounts in local mode, so cloud
/// mode reaches each of them through an additive route. The property-scoped
/// ones carry the id in the route because there is no shell to take it from.
const unitsRoute = '/units';
const leasesRoute = '/leases';
const leasingPipelineRoute = '/leasing-pipeline';
const rentRollRoute = '/rent-roll';

/// AP9/AP10: the operations overview and alerts panels, added after the
/// original six-surface Welle-3 batch — same reasoning, so they get the same
/// shape (property-scoped, id in the route, no shell to take it from).
const operationsOverviewRoute = '/operations-overview';
const operationsAlertsRoute = '/operations-alerts';

/// Workspace-wide: the tenant list is the party directory scoped to a role, and
/// the rental view spans every property. Neither needs a parameter.
const tenantsRoute = '/tenants';
const rentalOverviewRoute = '/rental-overview';

/// Welle 4: the one property-scoped `maintenance_capex` surface (tickets +
/// CapEx, merged from the SCR-034/SCR-031 audit — see `04d_wave4_
/// maintenance_capex.md`). Same reasoning as the Welle-3 property routes
/// above: no `PropertyShell` in cloud mode, so the id travels in the route.
/// `GlobalPage.maintenance`/`GlobalPage.contractors` themselves need no route
/// — they are ordinary workspace-wide sidebar destinations already in
/// [appNavigationGroups], reached through `globalPageProvider` like `parties`
/// or `rentalOverview`, not through a URL.
const propertyMaintenanceRoute = '/property-maintenance';

/// TASKS-NOTIFICATIONS-CORE-01 (A15): the three minimal routes riding ahead of
/// `SHELL-ROUTING-01`, because without them no notification has a deep-link
/// target. Both pages are workspace-wide like `/documents`; the task detail
/// carries its id in the route, the same shape as the property routes.
const tasksRoute = '/tasks';
const notificationsRoute = '/notifications';

String taskRouteFor(String taskId) {
  final normalized = taskId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(taskId, 'taskId', 'must not be empty');
  }
  return '$tasksRoute/${Uri.encodeComponent(normalized)}';
}

String? taskIdFromRoute(String? routeName) {
  if (routeName == null) {
    return null;
  }
  return _idFromRoute(routeName, tasksRoute);
}

String unitsRouteFor(String propertyId) => '$unitsRoute/$propertyId';
String leasesRouteFor(String propertyId) => '$leasesRoute/$propertyId';
String leasingPipelineRouteFor(String propertyId) =>
    '$leasingPipelineRoute/$propertyId';
String rentRollRouteFor(String propertyId) => '$rentRollRoute/$propertyId';
String operationsOverviewRouteFor(String propertyId) =>
    '$operationsOverviewRoute/$propertyId';
String operationsAlertsRouteFor(String propertyId) =>
    '$operationsAlertsRoute/$propertyId';
String propertyMaintenanceRouteFor(String propertyId) =>
    '$propertyMaintenanceRoute/$propertyId';

/// `/<prefix>/<id>` → id. Returns null for anything else, so an unknown route
/// falls through to the next matcher rather than being claimed by this one.
String? _idFromRoute(String routeName, String prefix) {
  final segments = Uri.tryParse(routeName)?.pathSegments;
  if (segments == null ||
      segments.length != 2 ||
      segments.first != prefix.substring(1) ||
      segments.last.trim().isEmpty) {
    return null;
  }
  return segments.last;
}

enum CloudRouteSurface {
  page,
  propertyDetail,
  members,
  documentsWorkspace,
  propertyDocuments,
  compliance,
  units,
  leases,
  leasingPipeline,
  rentRoll,
  operationsOverview,
  operationsAlerts,
  tenants,
  rentalOverview,
  maintenance,
  tasks,
  taskDetail,
  notifications,
}

class CloudRouteTarget {
  const CloudRouteTarget({
    required this.page,
    this.surface = CloudRouteSurface.page,
    this.propertyId,
    this.taskId,
  });

  static const dashboard = CloudRouteTarget(page: GlobalPage.dashboard);

  /// The post-login landing target (Foundation §2): the working properties
  /// page, not the dashboard, until the dashboard is cloud-ready (P2-D09).
  static const landing = CloudRouteTarget(page: GlobalPage.properties);

  final GlobalPage page;
  final CloudRouteSurface surface;
  final String? propertyId;

  /// Set only for [CloudRouteSurface.taskDetail] (`/tasks/:taskId`).
  final String? taskId;
}

CloudRouteTarget? cloudRouteTargetFromName(String? routeName) {
  if (routeName == null || routeName == '/' || routeName.isEmpty) {
    // Foundation §2: the dashboard is not cloud-ready yet, so landing there
    // would greet every sign-in with a migrationRequired empty state.
    return CloudRouteTarget.landing;
  }
  if (routeName == referencePropertiesRoute) {
    return const CloudRouteTarget(page: GlobalPage.properties);
  }
  final propertyId = referencePropertyIdFromRoute(routeName);
  if (propertyId != null) {
    return CloudRouteTarget(
      page: GlobalPage.properties,
      surface: CloudRouteSurface.propertyDetail,
      propertyId: propertyId,
    );
  }
  if (routeName == referenceMembersRoute) {
    return const CloudRouteTarget(
      page: GlobalPage.adminUsers,
      surface: CloudRouteSurface.members,
    );
  }
  if (routeName == partiesRoute) {
    return const CloudRouteTarget(page: GlobalPage.parties);
  }
  if (routeName == tenantsRoute) {
    return const CloudRouteTarget(
      page: GlobalPage.parties,
      surface: CloudRouteSurface.tenants,
    );
  }
  if (routeName == rentalOverviewRoute) {
    return const CloudRouteTarget(
      page: GlobalPage.rentalOverview,
      surface: CloudRouteSurface.rentalOverview,
    );
  }
  final unitsPropertyId = _idFromRoute(routeName, unitsRoute);
  if (unitsPropertyId != null) {
    return CloudRouteTarget(
      page: GlobalPage.properties,
      surface: CloudRouteSurface.units,
      propertyId: unitsPropertyId,
    );
  }
  final leasesPropertyId = _idFromRoute(routeName, leasesRoute);
  if (leasesPropertyId != null) {
    return CloudRouteTarget(
      page: GlobalPage.properties,
      surface: CloudRouteSurface.leases,
      propertyId: leasesPropertyId,
    );
  }
  final pipelinePropertyId = _idFromRoute(routeName, leasingPipelineRoute);
  if (pipelinePropertyId != null) {
    return CloudRouteTarget(
      page: GlobalPage.properties,
      surface: CloudRouteSurface.leasingPipeline,
      propertyId: pipelinePropertyId,
    );
  }
  final rentRollPropertyId = _idFromRoute(routeName, rentRollRoute);
  if (rentRollPropertyId != null) {
    return CloudRouteTarget(
      page: GlobalPage.properties,
      surface: CloudRouteSurface.rentRoll,
      propertyId: rentRollPropertyId,
    );
  }
  final operationsOverviewPropertyId = _idFromRoute(
    routeName,
    operationsOverviewRoute,
  );
  if (operationsOverviewPropertyId != null) {
    return CloudRouteTarget(
      page: GlobalPage.properties,
      surface: CloudRouteSurface.operationsOverview,
      propertyId: operationsOverviewPropertyId,
    );
  }
  final operationsAlertsPropertyId = _idFromRoute(
    routeName,
    operationsAlertsRoute,
  );
  if (operationsAlertsPropertyId != null) {
    return CloudRouteTarget(
      page: GlobalPage.properties,
      surface: CloudRouteSurface.operationsAlerts,
      propertyId: operationsAlertsPropertyId,
    );
  }
  final maintenancePropertyId = _idFromRoute(
    routeName,
    propertyMaintenanceRoute,
  );
  if (maintenancePropertyId != null) {
    return CloudRouteTarget(
      page: GlobalPage.properties,
      surface: CloudRouteSurface.maintenance,
      propertyId: maintenancePropertyId,
    );
  }
  if (routeName == tasksRoute) {
    return const CloudRouteTarget(
      page: GlobalPage.tasks,
      surface: CloudRouteSurface.tasks,
    );
  }
  final taskId = taskIdFromRoute(routeName);
  if (taskId != null) {
    return CloudRouteTarget(
      page: GlobalPage.tasks,
      surface: CloudRouteSurface.taskDetail,
      taskId: taskId,
    );
  }
  if (routeName == notificationsRoute) {
    return const CloudRouteTarget(
      page: GlobalPage.notifications,
      surface: CloudRouteSurface.notifications,
    );
  }
  if (routeName == documentsWorkspaceRoute) {
    return const CloudRouteTarget(
      page: GlobalPage.documents,
      surface: CloudRouteSurface.documentsWorkspace,
    );
  }
  if (routeName == complianceRoute) {
    return const CloudRouteTarget(
      page: GlobalPage.documents,
      surface: CloudRouteSurface.compliance,
    );
  }
  final documentsPropertyId = propertyDocumentsPropertyIdFromRoute(routeName);
  if (documentsPropertyId != null) {
    return CloudRouteTarget(
      page: GlobalPage.documents,
      surface: CloudRouteSurface.propertyDocuments,
      propertyId: documentsPropertyId,
    );
  }
  return null;
}

enum CloudDestinationReadiness { ready, migrationRequired }

CloudDestinationReadiness cloudReadinessForPage(GlobalPage page) {
  return switch (page) {
    GlobalPage.properties ||
    GlobalPage.parties ||
    GlobalPage.documents ||
    GlobalPage.valuations ||
    // Welle 3: reads units, leases and properties through their contracts only.
    GlobalPage.rentalOverview ||
    // Welle 4: reads maintenance_capex/contacts_parties through their
    // contracts only — see `04d_wave4_maintenance_capex.md`.
    GlobalPage.maintenance ||
    GlobalPage.contractors ||
    // TASK-CENTER-01 / NOTIFICATION-INBOX-01: both surfaces read
    // platform_audit_jobs through its contract only; each wave flipped its
    // own page independently. `taskTemplates` stays migrationRequired until
    // TASK-SCHEDULER-01 delivers a real templates surface (B9).
    GlobalPage.tasks ||
    GlobalPage.notifications ||
    GlobalPage.adminUsers ||
    GlobalPage.help => CloudDestinationReadiness.ready,
    _ => CloudDestinationReadiness.migrationRequired,
  };
}

String? cloudReadPermissionForPage(GlobalPage page) {
  return switch (page) {
    GlobalPage.dashboard || GlobalPage.help => null,
    GlobalPage.properties ||
    GlobalPage.portfolios ||
    GlobalPage.esg ||
    GlobalPage.maintenance ||
    GlobalPage.budgets ||
    GlobalPage.ledger => Permission.propertyRead,
    // The rental view is a leasing read, not a property one: it lists units and
    // leases and only borrows the property name.
    GlobalPage.rentalOverview => Permission.leaseRead,
    GlobalPage.parties || GlobalPage.contractors => Permission.partyRead,
    GlobalPage.documents => Permission.documentRead,
    GlobalPage.tasks || GlobalPage.taskTemplates => Permission.taskRead,
    // PERMISSION-CATALOG-02: the inbox is the member's OWN feed and the server
    // serves it recipient-scoped without any permission
    // (notifications_select_own_or_read). notification.read is the
    // workspace-wide oversight capability and stays admin-only; gating the
    // page on it would hide members' own notifications for no server reason.
    GlobalPage.notifications => null,
    GlobalPage.imports => Permission.importRead,
    GlobalPage.valuations ||
    GlobalPage.criteriaSets ||
    GlobalPage.compare => Permission.valuationRead,
    GlobalPage.reportTemplates => Permission.reportingGenerate,
    GlobalPage.adminUsers || GlobalPage.settings => Permission.securityManage,
    GlobalPage.audit => Permission.auditRead,
  };
}

bool isPageAllowedForPermissions(GlobalPage page, Set<String> permissions) {
  final permission = cloudReadPermissionForPage(page);
  return permission == null || permissions.contains(permission);
}

String propertyDocumentsRouteFor(String propertyId) {
  final normalized = propertyId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(propertyId, 'propertyId', 'must not be empty');
  }
  return '$propertyDocumentsRoute/${Uri.encodeComponent(normalized)}';
}

String? propertyDocumentsPropertyIdFromRoute(String? routeName) {
  if (routeName == null) {
    return null;
  }
  final segments = Uri.tryParse(routeName)?.pathSegments;
  if (segments == null ||
      segments.length != 2 ||
      segments.first != 'property-documents' ||
      segments.last.trim().isEmpty) {
    return null;
  }
  return segments.last;
}

String referencePropertyRoute(String propertyId) {
  final normalized = propertyId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(propertyId, 'propertyId', 'must not be empty');
  }
  return '$referencePropertiesRoute/${Uri.encodeComponent(normalized)}';
}

String? referencePropertyIdFromRoute(String? routeName) {
  if (routeName == null) {
    return null;
  }
  final segments = Uri.tryParse(routeName)?.pathSegments;
  if (segments == null ||
      segments.length != 2 ||
      segments.first != 'properties' ||
      segments.last.trim().isEmpty) {
    return null;
  }
  return segments.last;
}

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
        page: GlobalPage.rentalOverview,
        label: 'Vermietung',
        title: 'Vermietung',
        routeKey: 'assets_portfolio.rental_overview',
        icon: Icons.holiday_village_outlined,
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
        page: GlobalPage.parties,
        label: 'Parteien',
        title: 'Parteien',
        routeKey: 'daily_business.parties',
        icon: Icons.groups_outlined,
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
      // The work queue is the single entry point for valuation cases. The
      // former quick-screening, renovation and disposition tools were folded
      // into case-kind templates during the Welle-5 cutover.
      GlobalNavigationDestination(
        page: GlobalPage.valuations,
        label: 'Bewertungen',
        title: 'Bewertungen',
        routeKey: 'valuation_scenarios.valuations',
        icon: Icons.calculate_outlined,
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
        // AMD-001: renamed from "Benutzer"; routeKey and permission mapping
        // stay stable.
        label: 'Mitglieder',
        title: 'Mitglieder',
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
          PropertyNavigationDestination(
            page: PropertyDetailPage.saleData,
            label: 'Verkaufsdaten',
            routeKey: 'properties.view.sale_data',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.unitSaleStatus,
            label: 'Kaufpreise',
            routeKey: 'properties.view.unit_sale_status',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.hotelRevenue,
            label: 'Umsatz/Reporting',
            routeKey: 'properties.view.hotel_revenue',
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
            page: PropertyDetailPage.buyerInterests,
            label: 'Käufer/Interessenten',
            routeKey: 'properties.daily_business.buyer_interests',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.guests,
            label: 'Gäste',
            routeKey: 'properties.daily_business.guests',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.leases,
            label: 'Mietverträge',
            routeKey: 'properties.daily_business.leases',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.reservations,
            label: 'Reservierungen',
            routeKey: 'properties.daily_business.reservations',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.viewings,
            label: 'Besichtigungen',
            routeKey: 'properties.daily_business.viewings',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.saleOffers,
            label: 'Angebote',
            routeKey: 'properties.daily_business.sale_offers',
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
            page: PropertyDetailPage.housekeeping,
            label: 'Housekeeping',
            routeKey: 'properties.daily_business.housekeeping',
            requiresScenario: false,
          ),
          PropertyNavigationDestination(
            page: PropertyDetailPage.parkingStorage,
            label: 'Stellplätze/Keller',
            routeKey: 'properties.daily_business.parking_storage',
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
  return <String>[propertyName, section.title, destination.label];
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
          page != GlobalPage.compare;

    case 'viewer':
      return page != GlobalPage.adminUsers &&
          page != GlobalPage.settings &&
          page != GlobalPage.audit &&
          page != GlobalPage.imports;

    default:
      return false;
  }
}
