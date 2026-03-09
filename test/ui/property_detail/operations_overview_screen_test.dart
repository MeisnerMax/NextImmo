import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/operations.dart';
import 'package:neximmo_app/data/repositories/operations_repo.dart';
import 'package:neximmo_app/ui/screens/property_detail/operations_overview_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';

void main() {
  testWidgets('shows counts and quick actions', (tester) async {
    const fakeRepo = _FakeOperationsRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OperationsOverviewScreen(propertyId: 'p1')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Units Total'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('New Unit'), findsOneWidget);
    expect(find.text('Review Data Issues'), findsOneWidget);
  });
}

class _FakeOperationsRepo extends OperationsRepo {
  const _FakeOperationsRepo();

  @override
  Future<OperationsOverviewBundle> loadOverview(String propertyId) async {
    return const OperationsOverviewBundle(
      unitsTotal: 4,
      occupiedUnits: 3,
      vacantUnits: 1,
      offlineUnits: 0,
      activeLeases: 3,
      expiringIn30Days: 1,
      expiringIn60Days: 1,
      expiringIn90Days: 2,
      expiringIn180Days: 3,
      unitsWithoutActiveLease: 1,
      unitsWithMissingTenantMasterData: 1,
      dataConflicts: 1,
      latestRentRollPeriod: '2026-02',
      rentRollDelta: RentRollDeltaRecord(
        inPlaceRentDelta: 120,
        occupancyRateDelta: 0.1,
      ),
      openOperationalAlerts: 2,
      alerts: [
        OperationsAlertRecord(
          type: 'lease_expiry',
          severity: 'warning',
          message: 'Lease expires soon.',
        ),
      ],
    );
  }
}
