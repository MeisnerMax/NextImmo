import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/operations.dart';
import 'package:neximmo_app/data/repositories/operations_repo.dart';
import 'package:neximmo_app/ui/screens/property_detail/operations_alerts_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';

void main() {
  testWidgets('renders alert severity and action hint', (tester) async {
    const fakeRepo = _FakeOperationsRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OperationsAlertsScreen(propertyId: 'p1')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Unit A2 has overlapping leases.'), findsOneWidget);
    expect(find.textContaining('Lease L1 is missing tenant contact data.'), findsOneWidget);
    expect(find.textContaining('Resolve the overlap immediately.'), findsOneWidget);
    expect(find.textContaining('open'), findsWidgets);
  });
}

class _FakeOperationsRepo extends OperationsRepo {
  const _FakeOperationsRepo();

  @override
  Future<OperationsOverviewBundle> loadOverview(String propertyId) async =>
      OperationsOverviewBundle(
        unitsTotal: 4,
        occupiedUnits: 3,
        vacantUnits: 1,
        offlineUnits: 0,
        occupiedAreaSqft: 210,
        leasedAreaSqft: 210,
        activeLeases: 3,
        expiringIn30Days: 1,
        expiringIn60Days: 1,
        expiringIn90Days: 2,
        expiringIn180Days: 3,
        unitsWithoutActiveLease: 1,
        unitsWithMissingTenantMasterData: 1,
        dataConflicts: 1,
        latestRentRollPeriod: '2026-02',
        rentRollDelta: const RentRollDeltaRecord(
          inPlaceRentDelta: 120,
          occupancyRateDelta: 0.1,
        ),
        openOperationalAlerts: 2,
        alerts: await loadAlerts(propertyId),
      );

  @override
  Future<List<OperationsAlertRecord>> loadAlerts(
    String propertyId, {
    String? status,
  }) async {
    return const [
      OperationsAlertRecord(
        id: 'alert-1',
        type: 'overlapping_leases',
        severity: 'critical',
        message: 'Unit A2 has overlapping leases.',
        unitId: 'u2',
        recommendedAction: 'Resolve the overlap immediately.',
      ),
      OperationsAlertRecord(
        id: 'alert-2',
        type: 'missing_tenant_contact',
        severity: 'warning',
        message: 'Lease L1 is missing tenant contact data.',
        leaseId: 'l1',
        recommendedAction: 'Complete tenant email and phone.',
      ),
    ];
  }
}
