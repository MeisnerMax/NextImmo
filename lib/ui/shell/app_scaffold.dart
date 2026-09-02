import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../features/identity_access/presentation/admin_members_screen.dart';
import '../../features/portfolio_property/presentation/property_workspace_screen.dart';
import '../../features/reference_slice/application/reference_slice_controller.dart';
import '../components/command_palette.dart';
import '../components/nx_content_frame.dart';
import '../components/nx_empty_state.dart';
import '../navigation/app_navigation.dart';
import '../screens/compare_screen.dart';
import '../screens/criteria_sets_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/esg_dashboard_screen.dart';
import '../screens/help_screen.dart';
import '../screens/imports_screen.dart';
import '../screens/audit/audit_screen.dart';
import '../screens/maintenance/maintenance_screen.dart';
import '../screens/maintenance/contractors_screen.dart';
import '../screens/maintenance/contractors_panel.dart';
import '../screens/maintenance/maintenance_tickets_panel.dart';
import '../screens/property_detail/property_maintenance_capex_panel.dart';
import '../screens/budgets/budgets_screen.dart';
import '../screens/docs/documents_screen.dart';
import '../screens/docs/compliance_dashboard_screen.dart';
import '../screens/docs/documents_workspace_panel.dart';
import '../screens/ledger/ledger_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/parties/parties_screen.dart';
import '../screens/property_detail/property_documents_panel.dart';
import '../screens/portfolio/rental_overview_panel.dart';
import '../screens/property_detail/leasing/leases_panel.dart';
import '../screens/property_detail/leasing/leasing_pipeline_panel.dart';
import '../screens/property_detail/leasing/operations_alerts_panel.dart';
import '../screens/property_detail/leasing/operations_overview_panel.dart';
import '../screens/property_detail/leasing/rent_roll_panel.dart';
import '../screens/property_detail/leasing/tenants_panel.dart';
import '../screens/property_detail/leasing/units_panel.dart';
import '../screens/portfolios_screen.dart';
import '../screens/properties_screen.dart';
import '../screens/valuations/valuations_screen.dart';
import '../screens/report_templates_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/tasks/task_templates_screen.dart';
import '../screens/tasks/tasks_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'cloud_topbar.dart';
import 'sidebar.dart';
import 'topbar.dart';

class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key}) : cloudMode = false, routeTarget = null;

  const AppScaffold.cloud({super.key, required this.routeTarget})
    : cloudMode = true;

  final bool cloudMode;
  final CloudRouteTarget? routeTarget;

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  Timer? _dailyTimer;
  late CloudRouteTarget _activeCloudRouteTarget;
  late GlobalPage _lastPage;
  bool _initialCloudRoutePending = false;

  @override
  void initState() {
    super.initState();
    _activeCloudRouteTarget = widget.routeTarget ?? CloudRouteTarget.dashboard;
    _lastPage = _activeCloudRouteTarget.page;
    if (widget.cloudMode) {
      _initialCloudRoutePending = true;
      scheduleMicrotask(() {
        if (!mounted) {
          return;
        }
        ref.read(globalPageProvider.notifier).state =
            _activeCloudRouteTarget.page;
        _initialCloudRoutePending = false;
      });
    } else {
      _dailyTimer = Timer.periodic(const Duration(hours: 1), (_) {
        _runDailyTaskGeneration();
      });
    }
  }

  @override
  void dispose() {
    _dailyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providerPage = ref.watch(globalPageProvider);
    final page =
        widget.cloudMode && _initialCloudRoutePending
            ? _activeCloudRouteTarget.page
            : providerPage;
    if (widget.cloudMode && page != _lastPage) {
      _lastPage = page;
      _activeCloudRouteTarget = CloudRouteTarget(page: page);
    }
    return _buildScaffold(context, page);
  }

  Widget _buildScaffold(BuildContext context, GlobalPage page) {
    final cloudState =
        widget.cloudMode ? ref.watch(referenceSliceControllerProvider) : null;
    final cloudPermissions = cloudState?.selectedWorkspace?.permissions;
    final cloudWorkspaceName = cloudState?.selectedWorkspace?.workspace.name;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            () =>
                widget.cloudMode
                    ? _showCloudSearchState(context)
                    : showCommandPalette(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            () =>
                widget.cloudMode
                    ? _showCloudSearchState(context)
                    : showCommandPalette(context),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mobile = constraints.maxWidth <= AppBreakpoints.mobileMax;
            if (mobile) {
              return Scaffold(
                drawer: Drawer(
                  width: 320,
                  shape: const RoundedRectangleBorder(),
                  child: Sidebar(
                    forceExpanded: true,
                    drawerMode: true,
                    cloudPermissions: cloudPermissions,
                    workspaceName: cloudWorkspaceName,
                    onDestinationSelected:
                        () => Navigator.of(context).maybePop(),
                  ),
                ),
                body: SafeArea(
                  child: Column(
                    children: [
                      widget.cloudMode
                          ? const CloudTopBar(showMenuButton: true)
                          : const TopBar(showMenuButton: true),
                      Expanded(
                        child: Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: _buildPage(page),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Scaffold(
              body: SafeArea(
                child: Row(
                  children: [
                    Sidebar(
                      cloudPermissions: cloudPermissions,
                      workspaceName: cloudWorkspaceName,
                    ),
                    Expanded(
                      child: NxContentFrame(
                        child: Column(
                          children: [
                            widget.cloudMode
                                ? const CloudTopBar()
                                : const TopBar(),
                            Expanded(
                              child: Container(
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
                                child: _buildPage(page),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _runDailyTaskGeneration() async {
    final settings = await ref.read(inputsRepositoryProvider).getSettings();
    final lastRun = settings.lastTaskGenerationAt;
    final now = DateTime.now().millisecondsSinceEpoch;
    final shouldRun =
        lastRun == null ||
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(lastRun))
                .inHours >=
            24;
    if (!shouldRun) {
      return;
    }
    await ref
        .read(taskGenerationServiceProvider)
        .generate(
          now: now,
          dueSoonDays: settings.taskDueSoonDays,
          enableNotifications: settings.enableTaskNotifications,
        );
    await ref
        .read(inputsRepositoryProvider)
        .updateSettings(
          settings.copyWith(
            lastTaskGenerationAt: now,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Widget _buildPage(GlobalPage page) {
    if (widget.cloudMode) {
      return _buildCloudPage(page);
    }
    switch (page) {
      case GlobalPage.dashboard:
        return const DashboardScreen();
      case GlobalPage.properties:
        return const PropertiesScreen();
      case GlobalPage.ledger:
        return const LedgerScreen();
      case GlobalPage.budgets:
        return const BudgetsScreen();
      case GlobalPage.maintenance:
        return const MaintenanceScreen();
      case GlobalPage.contractors:
        return const ContractorsScreen();
      case GlobalPage.parties:
        return const PartiesScreen();
      case GlobalPage.tasks:
        return const TasksScreen();
      case GlobalPage.taskTemplates:
        return const TaskTemplatesScreen();
      case GlobalPage.portfolios:
        return const PortfoliosScreen();
      case GlobalPage.rentalOverview:
        return const RentalOverviewPanel();
      case GlobalPage.imports:
        return const ImportsScreen();
      case GlobalPage.notifications:
        return const NotificationsScreen();
      case GlobalPage.esg:
        return const EsgDashboardScreen();
      case GlobalPage.documents:
        return const DocumentsScreen();
      case GlobalPage.audit:
        return const AuditScreen();
      case GlobalPage.compare:
        return const CompareScreen();
      case GlobalPage.valuations:
        return const ValuationsScreen();
      case GlobalPage.criteriaSets:
        return const CriteriaSetsScreen();
      case GlobalPage.reportTemplates:
        return const ReportTemplatesScreen();
      case GlobalPage.adminUsers:
        // Membership administration is cloud-only; the SQLite-era UsersScreen
        // is gone (ADMIN-AREA-01 A1) and this legacy shell branch is dead
        // under DEC-024.
        return const _CloudDestinationState(
          title: 'Mitglieder nur in der Cloud-Shell',
          description:
              'Die Mitgliederverwaltung ist ausschließlich über die '
              'Cloud-Anmeldung verfügbar.',
          icon: Icons.cloud_off_outlined,
        );
      case GlobalPage.settings:
        return const SettingsScreen();
      case GlobalPage.help:
        return const HelpScreen();
    }
  }

  Widget _buildCloudPage(GlobalPage page) {
    final session = ref.watch(referenceSliceControllerProvider);
    final permissions =
        session.selectedWorkspace?.permissions ?? const <String>{};
    if (!isPageAllowedForPermissions(page, permissions)) {
      return const _CloudDestinationState(
        key: Key('cloud-destination-forbidden'),
        title: 'Kein Zugriff',
        description:
            'Der aktuellen Workspace-Mitgliedschaft fehlt die erforderliche '
            'Berechtigung für dieses Ziel.',
        icon: Icons.block_outlined,
      );
    }
    if (cloudReadinessForPage(page) ==
        CloudDestinationReadiness.migrationRequired) {
      final destination = navigationDestinationForPage(page);
      return _CloudDestinationState(
        key: Key('cloud-destination-migration-${page.name}'),
        title: '${destination.title} ist noch nicht cloudfähig',
        description:
            kIsWeb
                ? 'Dieses Modul benötigt noch seinen Supabase-Adapter. Web '
                    'verwendet bewusst keinen SQLite-Fallback.'
                : 'Dieses Modul benötigt noch seinen Supabase-Adapter. Im '
                    'Cloud-Host wird keine unmarkierte SQLite-Projektion '
                    'eingeblendet.',
        icon: Icons.cloud_off_outlined,
      );
    }

    final target =
        _activeCloudRouteTarget.page == page
            ? _activeCloudRouteTarget
            : CloudRouteTarget(page: page);
    switch (page) {
      case GlobalPage.properties when target.surface == CloudRouteSurface.units:
        return UnitsPanel(propertyId: target.propertyId!);
      case GlobalPage.properties
          when target.surface == CloudRouteSurface.leases:
        return LeasesPanel(propertyId: target.propertyId!);
      case GlobalPage.properties
          when target.surface == CloudRouteSurface.leasingPipeline:
        return LeasingPipelinePanel(propertyId: target.propertyId!);
      case GlobalPage.properties
          when target.surface == CloudRouteSurface.rentRoll:
        return RentRollPanel(propertyId: target.propertyId!);
      case GlobalPage.properties
          when target.surface == CloudRouteSurface.operationsOverview:
        return OperationsOverviewPanel(propertyId: target.propertyId!);
      case GlobalPage.properties
          when target.surface == CloudRouteSurface.operationsAlerts:
        return OperationsAlertsPanel(propertyId: target.propertyId!);
      case GlobalPage.properties
          when target.surface == CloudRouteSurface.maintenance:
        return PropertyMaintenanceCapexPanel(propertyId: target.propertyId!);
      case GlobalPage.properties:
        // PROPERTY-WORKSPACE-01 A1: the properties destination is the
        // Property Workspace host (list → property context → `Objekt`). The
        // property-scoped Welle-3/4 surfaces above stay separate deep-link
        // targets until the host rehosts them.
        return PropertyWorkspaceScreen(initialPropertyId: target.propertyId);
      case GlobalPage.parties:
        // Welle 3: the tenant list is the same directory scoped to a role, so
        // it rides the same page with its own surface.
        return target.surface == CloudRouteSurface.tenants
            ? const TenantsPanel()
            : const PartiesScreen();
      case GlobalPage.rentalOverview:
        return const RentalOverviewPanel();
      case GlobalPage.maintenance:
        return const MaintenanceTicketsPanel();
      case GlobalPage.contractors:
        return const ContractorsPanel();
      case GlobalPage.documents:
        return _buildCloudDocuments(target);
      case GlobalPage.valuations:
        return const ValuationsScreen();
      case GlobalPage.adminUsers:
        return const AdminMembersScreen();
      case GlobalPage.help:
        return const HelpScreen();
      default:
        return const _CloudDestinationState(
          title: 'Cloud-Ziel nicht verfügbar',
          description: 'Für dieses Ziel ist noch keine Cloud-Fläche gebunden.',
          icon: Icons.cloud_off_outlined,
        );
    }
  }

  Widget _buildCloudDocuments(CloudRouteTarget target) {
    switch (target.surface) {
      case CloudRouteSurface.propertyDocuments:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: PropertyDocumentsPanel(propertyId: target.propertyId!),
        );
      case CloudRouteSurface.compliance:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ComplianceDashboardScreen(
            onOpenRequirement:
                (requirement) => Navigator.of(
                  context,
                ).pushNamed(propertyDocumentsRouteFor(requirement.entityId)),
          ),
        );
      case CloudRouteSurface.documentsWorkspace:
      case CloudRouteSurface.page:
      case CloudRouteSurface.propertyDetail:
      case CloudRouteSurface.members:
      case CloudRouteSurface.units:
      case CloudRouteSurface.leases:
      case CloudRouteSurface.leasingPipeline:
      case CloudRouteSurface.rentRoll:
      case CloudRouteSurface.operationsOverview:
      case CloudRouteSurface.operationsAlerts:
      case CloudRouteSurface.tenants:
      case CloudRouteSurface.rentalOverview:
      case CloudRouteSurface.maintenance:
        return const DocumentsWorkspacePanel();
    }
  }

  void _showCloudSearchState(BuildContext context) {
    showDialog<void>(
      context: context,
      builder:
          (context) => const AlertDialog(
            title: Text('Cloud-Suche noch nicht verfügbar'),
            content: Text(
              'Die globale Suche wird mit dem Supabase-Suchindex '
              'freigeschaltet. Es wird kein lokaler SQLite-Index verwendet.',
            ),
          ),
    );
  }
}

class _CloudDestinationState extends StatelessWidget {
  const _CloudDestinationState({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: NxEmptyState(title: title, description: description, icon: icon),
    );
  }
}
