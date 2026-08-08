import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neximmo_app/ui/screens/dashboard_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/security_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for the redesigned `DashboardScreen`
/// (Phase 2, Wave 1, Arbeitspaket 4 / SCR-004, BIG-007 split): dashboard-shaped
/// loading skeleton (no full-page spinner), infrastructure error with retry and
/// no raw exception text, the zero-property empty state leading into creation,
/// role-based prioritization of the attention list, and a responsive smoke
/// check at the three golden widths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pumpDashboard(
    WidgetTester tester, {
    required List<Override> overrides,
    String role = 'admin',
    Size size = const Size(1280, 800),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        activeUserRoleProvider.overrideWithValue(role),
        activeSecurityContextProvider.overrideWithValue(null),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return container;
  }

  testWidgets('viewer prioritizes lease actions in the attention list', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      role: 'viewer',
      overrides: [
        dashboardOverviewProvider.overrideWith((ref) async => _sampleOverview()),
      ],
    );

    expect(find.text('Aktuelle Hinweise'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('dashboard-action-0')),
        matching: find.text('Lease follow-up'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('admin prioritizes task actions and renders the frame sections', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      overrides: [
        dashboardOverviewProvider.overrideWith((ref) async => _sampleOverview()),
      ],
    );

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Aktuelle Hinweise'), findsOneWidget);
    expect(find.text('Aktuelle Aktivität'), findsOneWidget);
    expect(find.text('Wertentwicklung'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('dashboard-action-0')),
        matching: find.text('Task escalation'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('loading shows a dashboard skeleton, not a full-page spinner', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      settle: false,
      overrides: [
        dashboardOverviewProvider.overrideWith(
          (ref) => Completer<DashboardOverviewData>().future,
        ),
      ],
    );

    expect(
      find.byKey(const ValueKey<String>('dashboard_skeleton')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('error shows a retry action without raw exception text', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      overrides: [
        dashboardOverviewProvider.overrideWith(
          (ref) async => throw Exception('dashboard aggregation failed'),
        ),
      ],
    );

    expect(find.text('Dashboard konnte nicht geladen werden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('failed'), findsNothing);
  });

  testWidgets('zero-property workspace shows the create-first-object state', (
    tester,
  ) async {
    final container = await pumpDashboard(
      tester,
      overrides: [
        dashboardOverviewProvider.overrideWith(
          (ref) async => DashboardOverviewData.empty(),
        ),
      ],
    );

    expect(find.text('Lege dein erstes Objekt an'), findsOneWidget);
    expect(find.text('Objekt anlegen'), findsOneWidget);

    await tester.tap(find.text('Objekt anlegen'));
    await tester.pumpAndSettle();

    expect(container.read(globalPageProvider), GlobalPage.properties);
  });

  testWidgets('desktop width renders the two-column body without overflow', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      size: const Size(1440, 900),
      overrides: [
        dashboardOverviewProvider.overrideWith((ref) async => _sampleOverview()),
      ],
    );

    expect(
      find.byKey(const ValueKey<String>('dashboard_wide_layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('dashboard_stacked_layout')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet width stacks the body without overflow', (tester) async {
    await pumpDashboard(
      tester,
      size: const Size(1024, 768),
      overrides: [
        dashboardOverviewProvider.overrideWith((ref) async => _sampleOverview()),
      ],
    );

    expect(
      find.byKey(const ValueKey<String>('dashboard_stacked_layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone width stacks the body without overflow', (tester) async {
    await pumpDashboard(
      tester,
      size: const Size(390, 844),
      overrides: [
        dashboardOverviewProvider.overrideWith((ref) async => _sampleOverview()),
      ],
    );

    expect(
      find.byKey(const ValueKey<String>('dashboard_stacked_layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('dashboard_wide_layout')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

DashboardOverviewData _sampleOverview() {
  return DashboardOverviewData(
    activeProperties: 4,
    totalUnits: 68,
    occupiedUnits: 50,
    vacantUnits: 18,
    annualRent: 120000.0,
    monthlyRentRunRate: 10000.0,
    annualOperatingCosts: 30000.0,
    openDepositAmount: 15000.0,
    serviceChargeBalance: 2000.0,
    sourceCoverageRate: 0.95,
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
        target: const DashboardNavigationTarget(
          globalPage: GlobalPage.properties,
          propertyId: 'p1',
          propertyDetailPage: PropertyDetailPage.overview,
        ),
        icon: Icons.home_work_outlined,
      ),
    ],
  );
}
