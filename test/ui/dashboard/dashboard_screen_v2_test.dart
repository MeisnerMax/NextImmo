import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neximmo_app/ui/screens/v2/dashboard_screen_v2.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/security_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

void main() {
  testWidgets('viewer dashboard prioritizes lease actions and browse entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeUserRoleProvider.overrideWithValue('viewer'),
          dashboardOverviewProvider.overrideWith(
            (ref) async => _sampleOverview(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: DashboardScreenV2()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Browse Properties'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('dashboard-action-0')),
        matching: find.text('Lease follow-up'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('admin dashboard prioritizes task actions and settings entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeUserRoleProvider.overrideWithValue('admin'),
          dashboardOverviewProvider.overrideWith(
            (ref) async => _sampleOverview(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: DashboardScreenV2()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Open Settings'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('dashboard-action-0')),
        matching: find.text('Task escalation'),
      ),
      findsOneWidget,
    );
    expect(find.text('Action Center'), findsOneWidget);
    expect(find.text('Recent Activity'), findsOneWidget);
  });
}

DashboardOverviewData _sampleOverview() {
  return DashboardOverviewData(
    activeProperties: 4,
    totalUnits: 68,
    criticalActions: 3,
    atRiskAssets: 2,
    propertyTypeMix: const [
      DashboardCategoryValue(label: 'multifamily', value: 2),
      DashboardCategoryValue(label: 'office', value: 2),
    ],
    intakeTrend: [
      DashboardMonthValue(date: DateTime(2025, 10), value: 1),
      DashboardMonthValue(date: DateTime(2025, 11), value: 2),
      DashboardMonthValue(date: DateTime(2025, 12), value: 0),
      DashboardMonthValue(date: DateTime(2026, 1), value: 1),
      DashboardMonthValue(date: DateTime(2026, 2), value: 0),
      DashboardMonthValue(date: DateTime(2026, 3), value: 1),
    ],
    signalMetrics: const [
      DashboardSignalMetric(
        label: 'Lease Expiries 30d',
        value: 2,
        detail: 'Immediate lease follow-up required.',
        severity: DashboardSeverity.critical,
      ),
      DashboardSignalMetric(
        label: 'Critical Tasks',
        value: 3,
        detail: 'High-priority tasks still open.',
        severity: DashboardSeverity.critical,
      ),
    ],
    actionItems: const [
      DashboardActionItem(
        category: DashboardActionCategory.task,
        severity: DashboardSeverity.critical,
        title: 'Task escalation',
        detail: 'Three high-priority tasks are still open.',
        nextStep: 'Open task board',
        target: DashboardNavigationTarget(globalPage: GlobalPage.tasks),
        count: 3,
      ),
      DashboardActionItem(
        category: DashboardActionCategory.leaseExpiry,
        severity: DashboardSeverity.critical,
        title: 'Lease follow-up',
        detail: 'Two leases expire within 30 days.',
        nextStep: 'Review leases',
        target: DashboardNavigationTarget(
          globalPage: GlobalPage.properties,
          propertyId: 'p1',
          propertyDetailPage: PropertyDetailPage.leases,
        ),
        count: 2,
      ),
      DashboardActionItem(
        category: DashboardActionCategory.documentGap,
        severity: DashboardSeverity.warning,
        title: 'Document gap',
        detail: 'One compliance document is missing.',
        nextStep: 'Open documents',
        target: DashboardNavigationTarget(
          globalPage: GlobalPage.properties,
          propertyId: 'p1',
          propertyDetailPage: PropertyDetailPage.documents,
        ),
        count: 1,
      ),
    ],
    activityItems: [
      DashboardActivityItem(
        title: 'Property updated',
        detail: 'Atlas House in Berlin',
        timestamp: DateTime(2026, 3, 8),
        target: DashboardNavigationTarget(
          globalPage: GlobalPage.properties,
          propertyId: 'p1',
          propertyDetailPage: PropertyDetailPage.overview,
        ),
        icon: Icons.home_work_outlined,
      ),
    ],
  );
}
