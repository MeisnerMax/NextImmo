import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/operations.dart';
import 'package:neximmo_app/core/operations/lease_indexation_engine.dart';

void main() {
  test('generates indexed schedule and keeps manual override precedence', () {
    final engine = const LeaseIndexationEngine();
    final lease = LeaseRecord(
      id: 'lease_1',
      assetPropertyId: 'p1',
      unitId: 'u1',
      tenantId: null,
      leaseName: 'L1',
      startDate: DateTime(2024, 1, 1).millisecondsSinceEpoch,
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
      createdAt: 0,
      updatedAt: 0,
    );
    final rules = [
      LeaseIndexationRuleRecord(
        id: 'r1',
        leaseId: 'lease_1',
        kind: 'cpi',
        effectiveFromPeriodKey: '2025-01',
        annualPercent: 0.10,
        fixedStepAmount: null,
        capPercent: 0.05,
        floorPercent: 0.01,
        notes: null,
        createdAt: 0,
      ),
    ];

    final schedule = engine.buildRentSchedule(
      lease: lease,
      indexationRules: rules,
      fromPeriodKey: '2025-01',
      toPeriodKey: '2025-03',
      manualOverrides: {
        '2025-02': LeaseRentScheduleRecord(
          id: 'm1',
          leaseId: 'lease_1',
          periodKey: '2025-02',
          rentMonthly: 2000,
          source: 'manual_override',
          createdAt: 0,
        ),
      },
    );

    expect(schedule.length, 3);
    expect(schedule[0].rentMonthly, 1000);
    expect(schedule[1].source, 'manual_override');
    expect(schedule[1].rentMonthly, 2000);
    expect(schedule[2].rentMonthly, 1000);
  });
}
