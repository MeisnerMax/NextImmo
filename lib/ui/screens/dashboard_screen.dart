import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/nx_page_header.dart';
import '../state/app_state.dart';
import '../state/property_state.dart';
import '../state/security_state.dart';
import '../theme/app_theme.dart';
import 'dashboard/dashboard_activity_table.dart';
import 'dashboard/dashboard_attention_list.dart';
import 'dashboard/dashboard_charts.dart';
import 'dashboard/dashboard_kpi_row.dart';
import 'dashboard/dashboard_section_states.dart';
import 'dashboard/dashboard_view_model.dart';

// Re-export the dashboard data model and provider so existing imports of
// `dashboard_screen.dart` keep resolving after the BIG-007 split.
export 'dashboard/dashboard_view_model.dart';

/// Executive summary dashboard (SCR-004, BIG-007 split): slim orchestration
/// over the section widgets in `dashboard/`. A single
/// [dashboardOverviewProvider] `AsyncValue` drives the screen — loading shows a
/// dashboard-shaped skeleton (never a full-page spinner), infrastructure error
/// shows a retry, and a workspace with zero properties shows an
/// `NxEmptyState` leading into property creation. Role-based content filtering
/// (`activeUserRoleProvider`) is unchanged.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(dashboardOverviewProvider);
    final roleConfig = roleConfigFor(ref.watch(activeUserRoleProvider));
    final securityContext = ref.watch(activeSecurityContextProvider);
    final subtitle = buildDashboardSubtitle(roleConfig, securityContext);

    void refresh() {
      ref.invalidate(propertiesControllerProvider);
      ref.invalidate(dashboardOverviewProvider);
    }

    final body = overviewAsync.when(
      data: (overview) {
        if (overview.activeProperties == 0) {
          return DashboardEmptyState(
            onCreate: () => openDashboardTarget(
              ref,
              const DashboardNavigationTarget(globalPage: GlobalPage.properties),
            ),
          );
        }
        return _DashboardBody(
          overview: overview,
          actionItems: sortActionsForRole(overview.actionItems, roleConfig),
          onOpenTarget: (target) => openDashboardTarget(ref, target),
        );
      },
      loading: () => const DashboardSkeleton(),
      error: (_, __) => DashboardErrorState(onRetry: refresh),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final pagePadding = context.adaptivePagePadding;
        return SingleChildScrollView(
          padding: EdgeInsets.all(pagePadding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.desktopMaxContentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NxPageHeader(
                    title: 'Dashboard',
                    subtitle: subtitle,
                    secondaryActions: [
                      OutlinedButton.icon(
                        onPressed: refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Aktualisieren'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.component),
                  body,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.overview,
    required this.actionItems,
    required this.onOpenTarget,
  });

  final DashboardOverviewData overview;
  final List<DashboardActionItem> actionItems;
  final ValueChanged<DashboardNavigationTarget> onOpenTarget;

  @override
  Widget build(BuildContext context) {
    final attention = DashboardAttentionList(
      items: actionItems,
      onOpenTarget: onOpenTarget,
    );
    final charts = DashboardCharts(overview: overview);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardKpiRow(overview: overview),
        const SizedBox(height: AppSpacing.component),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1080;
            if (wide) {
              return Row(
                key: const ValueKey<String>('dashboard_wide_layout'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: attention),
                  const SizedBox(width: AppSpacing.component),
                  Expanded(flex: 2, child: charts),
                ],
              );
            }
            return Column(
              key: const ValueKey<String>('dashboard_stacked_layout'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                attention,
                const SizedBox(height: AppSpacing.component),
                charts,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.component),
        DashboardActivityTable(
          items: overview.activityItems,
          onOpenTarget: onOpenTarget,
        ),
      ],
    );
  }
}
