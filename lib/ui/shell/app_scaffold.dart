import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../components/command_palette.dart';
import '../components/nx_content_frame.dart';
import '../screens/compare_screen.dart';
import '../screens/criteria_sets_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/esg_dashboard_screen.dart';
import '../screens/help_screen.dart';
import '../screens/imports_screen.dart';
import '../screens/audit/audit_screen.dart';
import '../screens/maintenance/maintenance_screen.dart';
import '../screens/budgets/budgets_screen.dart';
import '../screens/docs/documents_screen.dart';
import '../screens/ledger/ledger_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/portfolios_screen.dart';
import '../screens/properties_screen.dart';
import '../screens/report_templates_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/v2/dashboard_screen_v2.dart';
import '../screens/v2/properties_screen_v2.dart';
import '../screens/admin/users_screen.dart';
import '../screens/tasks/task_templates_screen.dart';
import '../screens/tasks/tasks_screen.dart';
import '../state/app_state.dart';
import '../state/ui_feature_flags.dart';
import '../theme/app_theme.dart';
import 'sidebar.dart';
import 'topbar.dart';
import 'v2/sidebar_v2.dart';
import 'v2/topbar_v2.dart';

class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  Timer? _dailyTimer;

  @override
  void initState() {
    super.initState();
    _dailyTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _runDailyTaskGeneration();
    });
  }

  @override
  void dispose() {
    _dailyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(globalPageProvider);
    final shellV2Enabled = ref.watch(
      uiScreenFlagProvider(UiScreenFlag.appShellV2),
    );
    if (!shellV2Enabled) {
      return _buildLegacyScaffold(context, page);
    }
    return _buildV2Scaffold(context, page);
  }

  Widget _buildLegacyScaffold(BuildContext context, GlobalPage page) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            () => showCommandPalette(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            () => showCommandPalette(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              const Sidebar(),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    const TopBar(),
                    const Divider(height: 1),
                    Expanded(
                      child: Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: _buildPage(page),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildV2Scaffold(BuildContext context, GlobalPage page) {
    final semantic = context.semanticColors;
    final zone = context.desktopLayoutZone;
    final shellPadding = zone == AppDesktopLayoutZone.narrow ? 6.0 : 10.0;
    final shellGap = zone == AppDesktopLayoutZone.narrow ? 6.0 : 10.0;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            () => showCommandPalette(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            () => showCommandPalette(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).scaffoldBackgroundColor,
                  Theme.of(context).colorScheme.surfaceContainerLowest,
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(shellPadding),
                child: Row(
                  children: [
                    const SidebarV2(),
                    SizedBox(width: shellGap),
                    Expanded(
                      child: NxContentFrame(
                        child: Column(
                          children: [
                            const TopBarV2(),
                            Divider(height: 1, color: semantic.border),
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
            ),
          ),
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
    final dashboardV2Enabled = ref.watch(
      uiScreenFlagProvider(UiScreenFlag.dashboardV2),
    );
    final propertiesV2Enabled = ref.watch(
      uiScreenFlagProvider(UiScreenFlag.propertiesV2),
    );
    switch (page) {
      case GlobalPage.dashboard:
        return dashboardV2Enabled
            ? const DashboardScreenV2()
            : const DashboardScreen();
      case GlobalPage.properties:
        return propertiesV2Enabled
            ? const PropertiesScreenV2()
            : const PropertiesScreen();
      case GlobalPage.ledger:
        return const LedgerScreen();
      case GlobalPage.budgets:
        return const BudgetsScreen();
      case GlobalPage.maintenance:
        return const MaintenanceScreen();
      case GlobalPage.tasks:
        return const TasksScreen();
      case GlobalPage.taskTemplates:
        return const TaskTemplatesScreen();
      case GlobalPage.portfolios:
        return const PortfoliosScreen();
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
      case GlobalPage.criteriaSets:
        return const CriteriaSetsScreen();
      case GlobalPage.reportTemplates:
        return const ReportTemplatesScreen();
      case GlobalPage.adminUsers:
        return const UsersScreen();
      case GlobalPage.settings:
        return const SettingsScreen();
      case GlobalPage.help:
        return const HelpScreen();
    }
  }
}
