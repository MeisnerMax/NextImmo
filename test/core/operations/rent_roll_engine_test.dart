import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/operations.dart';
import 'package:neximmo_app/core/operations/rent_roll_engine.dart';

void main() {
  test('computes occupancy and monthly sums', () {
    final engine = const RentRollEngine();
    final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;

    final units = [
      UnitRecord(
        id: 'u1',
        assetPropertyId: 'p1',
        unitCode: 'A-1',
        unitType: 'apartment',
        beds: null,
        baths: null,
        sqft: null,
        floor: null,
        status: 'occupied',
        targetRentMonthly: null,
        marketRentMonthly: 1200,
        offlineReason: null,
        vacancySince: null,
        vacancyReason: null,
        marketingStatus: null,
        renovationStatus: null,
        expectedReadyDate: null,
        nextAction: null,
        notes: null,
        createdAt: now,
        updatedAt: now,
      ),
      UnitRecord(
        id: 'u2',
        assetPropertyId: 'p1',
        unitCode: 'A-2',
        unitType: 'apartment',
        beds: null,
        baths: null,
        sqft: null,
        floor: null,
        status: 'vacant',
        targetRentMonthly: null,
        marketRentMonthly: 900,
        offlineReason: null,
        vacancySince: null,
        vacancyReason: null,
        marketingStatus: null,
        renovationStatus: null,
        expectedReadyDate: null,
        nextAction: null,
        notes: null,
        createdAt: now,
        updatedAt: now,
      ),
      UnitRecord(
        id: 'u3',
        assetPropertyId: 'p1',
        unitCode: 'A-3',
        unitType: 'apartment',
        beds: null,
        baths: null,
        sqft: null,
        floor: null,
        status: 'offline',
        targetRentMonthly: null,
        marketRentMonthly: 700,
        offlineReason: 'renovation',
        vacancySince: null,
        vacancyReason: null,
        marketingStatus: null,
        renovationStatus: null,
        expectedReadyDate: null,
        nextAction: null,
        notes: null,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final leases = [
      LeaseRecord(
        id: 'l1',
        assetPropertyId: 'p1',
        unitId: 'u1',
        tenantId: 't1',
        leaseName: 'Lease A1',
        startDate: DateTime(2025, 1, 1).millisecondsSinceEpoch,
        endDate: null,
        moveInDate: null,
        moveOutDate: null,
        status: 'active',
        baseRentMonthly: 1000,
        currencyCode: 'EUR',
        securityDeposit: null,
        paymentDayOfMonth: null,
        billingFrequency: 'monthly',
        leaseSignedDate: null,
        noticeDate: null,
        renewalOptionDate: null,
        breakOptionDate: null,
        executedDate: null,
        depositStatus: 'unknown',
        rentFreePeriodMonths: null,
        ancillaryChargesMonthly: null,
        parkingOtherChargesMonthly: null,
        notes: null,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final schedules = [
      LeaseRentScheduleRecord(
        id: 's1',
        leaseId: 'l1',
        periodKey: '2026-02',
        rentMonthly: 1100,
        source: 'indexation',
        createdAt: now,
      ),
    ];

    final result = engine.compute(
      periodKey: '2026-02',
      units: units,
      leases: leases,
      schedule: schedules,
      tenantsById: {
        't1': TenantRecord(
          id: 't1',
          displayName: 'Alice',
          legalName: null,
          email: null,
          phone: null,
          alternativeContact: null,
          billingContact: null,
          status: 'active',
          moveInReference: null,
          notes: null,
          createdAt: now,
          updatedAt: now,
        ),
      },
    );

    expect(result.occupancyRate, 0.5);
    expect(result.inPlaceRentMonthly, 1100);
    expect(result.gprMonthly, 2100);
    expect(result.vacancyLossMonthly, 1000);
    expect(result.egiMonthly, 1100);
    expect(result.lines.length, 3);
  });
}
