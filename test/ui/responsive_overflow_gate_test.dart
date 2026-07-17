import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/components/nx_data_table_shell.dart';
import 'package:neximmo_app/ui/screens/properties/create_property_dialog.dart';
import 'package:neximmo_app/ui/screens/v2/dashboard_screen_v2.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/security_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

void main() {
  const viewports = <Size>[Size(390, 844), Size(1024, 768), Size(1440, 900)];

  for (final viewport in viewports) {
    testWidgets('DashboardScreenV2 has no overflow at $viewport', (
      tester,
    ) async {
      _setViewport(tester, viewport);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeUserRoleProvider.overrideWithValue('admin'),
            activeSecurityContextProvider.overrideWithValue(null),
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

      expect(tester.takeException(), isNull);
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('CreatePropertyDialog has no overflow at $viewport', (
      tester,
    ) async {
      _setViewport(tester, viewport);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder:
                              (_) => CreatePropertyDialog(
                                onCreateProperty: (draft) async => null,
                              ),
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Basic Information'), findsOneWidget);
    });

    testWidgets('NxDataTableShell has no overflow at $viewport', (
      tester,
    ) async {
      _setViewport(tester, viewport);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: NxDataTableShell(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Property')),
                  DataColumn(label: Text('Address')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Annual rent')),
                ],
                rows: const [
                  DataRow(
                    cells: [
                      DataCell(Text('Asset Alpha')),
                      DataCell(Text('Long Street 123, Berlin')),
                      DataCell(Text('Active')),
                      DataCell(Text('120,000 EUR')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Asset Alpha'), findsOneWidget);
    });
  }
}

void _setViewport(WidgetTester tester, Size viewport) {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
