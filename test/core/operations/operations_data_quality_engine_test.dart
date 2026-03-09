import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/operations.dart';
import 'package:neximmo_app/core/operations/operations_data_quality_engine.dart';

void main() {
  const engine = OperationsDataQualityEngine();

  test('flags invalid operational states', () {
    final now = DateTime(2026, 3, 15);
    final issues = engine.evaluate(
      propertyId: 'p1',
      units: [
        _unit(id: 'u1', code: 'A1', status: 'occupied', sqft: 70),
        _unit(id: 'u2', code: 'A2', status: 'vacant', sqft: 55),
        _unit(
          id: 'u3',
          code: 'A3',
          status: 'offline',
          sqft: 60,
        ),
        _unit(
          id: 'u4',
          code: 'A4',
          status: 'vacant',
          vacancySince: DateTime(2025, 12, 1).millisecondsSinceEpoch,
          sqft: 52,
        ),
      ],
      leases: [
        _lease(
          id: 'l1',
          unitId: 'u2',
          tenantId: 't1',
          leaseName: 'Lease 1',
          startDate: DateTime(2026, 1, 1).millisecondsSinceEpoch,
          endDate: DateTime(2026, 6, 1).millisecondsSinceEpoch,
          paymentDayOfMonth: 40,
        ),
        _lease(
          id: 'l2',
          unitId: 'u2',
          tenantId: 'missing-tenant',
          leaseName: 'Lease 2',
          startDate: DateTime(2026, 3, 1).millisecondsSinceEpoch,
          endDate: DateTime(2026, 7, 1).millisecondsSinceEpoch,
          securityDeposit: -10,
        ),
        _lease(
          id: 'l3',
          unitId: 'missing-unit',
          tenantId: 't2',
          leaseName: 'Broken Lease',
          startDate: DateTime(2026, 5, 1).millisecondsSinceEpoch,
          endDate: DateTime(2026, 4, 1).millisecondsSinceEpoch,
          status: 'future',
          securityDeposit: 1000,
        ),
      ],
      tenantsById: {
        't1': _tenant(id: 't1', displayName: 'Alice', email: null, phone: null),
        't2': _tenant(id: 't2', displayName: '', email: 'a@example.com', phone: '123'),
      },
      snapshots: [
        _snapshot(periodKey: '2025-10'),
      ],
      now: now,
    );

    final issueTypes = issues.map((issue) => issue.type).toSet();
    expect(issueTypes, contains('occupied_without_active_lease'));
    expect(issueTypes, contains('vacancy_missing_since'));
    expect(issueTypes, contains('vacancy_aged'));
    expect(issueTypes, contains('offline_missing_reason'));
    expect(issueTypes, contains('vacant_with_active_lease'));
    expect(issueTypes, contains('missing_tenant_contact'));
    expect(issueTypes, contains('overlapping_leases'));
    expect(issueTypes, contains('orphan_lease_unit'));
    expect(issueTypes, contains('orphan_lease_tenant'));
    expect(issueTypes, contains('lease_end_before_start'));
    expect(issueTypes, contains('deposit_below_zero'));
    expect(issueTypes, contains('invalid_payment_day'));
    expect(issueTypes, contains('missing_deposit'));
    expect(issueTypes, contains('missing_tenant_display_name'));
    expect(issueTypes, contains('stale_rent_roll'));
  });

  test('keeps healthy operations data clean', () {
    final now = DateTime(2026, 3, 15);
    final unit = _unit(
      id: 'u1',
      code: 'A1',
      status: 'occupied',
      sqft: 70,
    );
    final lease = _lease(
      id: 'l1',
      unitId: 'u1',
      tenantId: 't1',
      leaseName: 'Lease 1',
      startDate: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      endDate: DateTime(2026, 12, 31).millisecondsSinceEpoch,
      securityDeposit: 1200,
      paymentDayOfMonth: 3,
    );
    final issues = engine.evaluate(
      propertyId: 'p1',
      units: [unit],
      leases: [lease],
      tenantsById: {
        't1': _tenant(
          id: 't1',
          displayName: 'Alice',
          email: 'alice@example.com',
          phone: '1234',
        ),
      },
      snapshots: [_snapshot(periodKey: '2026-03')],
      now: now,
    );

    expect(issues, isEmpty);
  });
}

UnitRecord _unit({
  required String id,
  required String code,
  required String status,
  required double sqft,
  int? vacancySince,
}) {
  return UnitRecord(
    id: id,
    assetPropertyId: 'p1',
    unitCode: code,
    unitType: 'apartment',
    beds: 2,
    baths: 1,
    sqft: sqft,
    floor: '1',
    status: status,
    targetRentMonthly: 1000,
    marketRentMonthly: 1100,
    offlineReason: null,
    vacancySince: vacancySince,
    vacancyReason: null,
    marketingStatus: null,
    renovationStatus: null,
    expectedReadyDate: null,
    nextAction: null,
    notes: null,
    createdAt: 1,
    updatedAt: 1,
  );
}

TenantRecord _tenant({
  required String id,
  required String displayName,
  required String? email,
  required String? phone,
}) {
  return TenantRecord(
    id: id,
    displayName: displayName,
    legalName: null,
    email: email,
    phone: phone,
    alternativeContact: null,
    billingContact: null,
    status: 'active',
    moveInReference: null,
    notes: null,
    createdAt: 1,
    updatedAt: 1,
  );
}

LeaseRecord _lease({
  required String id,
  required String unitId,
  required String? tenantId,
  required String leaseName,
  required int startDate,
  required int? endDate,
  String status = 'active',
  double? securityDeposit,
  int? paymentDayOfMonth,
}) {
  return LeaseRecord(
    id: id,
    assetPropertyId: 'p1',
    unitId: unitId,
    tenantId: tenantId,
    leaseName: leaseName,
    startDate: startDate,
    endDate: endDate,
    moveInDate: null,
    moveOutDate: null,
    status: status,
    baseRentMonthly: 1000,
    currencyCode: 'EUR',
    securityDeposit: securityDeposit,
    paymentDayOfMonth: paymentDayOfMonth,
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
    createdAt: 1,
    updatedAt: 1,
  );
}

RentRollSnapshotRecord _snapshot({required String periodKey}) {
  return RentRollSnapshotRecord(
    id: 'rr-$periodKey',
    assetPropertyId: 'p1',
    periodKey: periodKey,
    snapshotAt: 1,
    occupancyRate: 1,
    gprMonthly: 1000,
    vacancyLossMonthly: 0,
    egiMonthly: 1000,
    inPlaceRentMonthly: 1000,
    marketRentMonthly: 1000,
    notes: null,
  );
}
