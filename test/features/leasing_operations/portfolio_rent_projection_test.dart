import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/leasing_operations/application/portfolio_rent_projection.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';

const String _workspace = 'workspace-a';
const String _property = 'property-a';
final DateTime _today = DateTime.utc(2026, 3, 31);

void main() {
  group('the live computation', () {
    test('sums the leases that are effective and cover the reporting date', () {
      final live = computeLiveRentRoll(
        units: <UnitSummaryDto>[_unit('u1', 'A-01', UnitStatus.occupied)],
        effectiveLeases: <LeaseSummaryDto>[
          _lease('l1', 'u1', baseRent: 1000),
          // OPN-DOM-001: a unit may hold several concurrent leases, so the row
          // is a sum, not a single value.
          _lease('l2', 'u1', baseRent: 250),
        ],
        asOfDate: _today,
      );

      expect(live.rows.single.effectiveLeaseCount, 2);
      expect(live.rows.single.baseRentMonthly, 1250);
      expect(live.summary.totalBaseRentMonthly, 1250);
    });

    test('excludes a lease whose term does not cover the reporting date', () {
      final live = computeLiveRentRoll(
        units: <UnitSummaryDto>[_unit('u1', 'A-01', UnitStatus.occupied)],
        effectiveLeases: <LeaseSummaryDto>[
          _lease('l1', 'u1', start: DateTime.utc(2026, 7, 1)),
        ],
        asOfDate: _today,
      );

      // The row that looks like a bug and is not: occupied by status, zero by
      // term window.
      expect(live.rows.single.effectiveLeaseCount, 0);
      expect(live.rows.single.baseRentMonthly, 0);
      expect(live.rows.single.isOccupiedButOutsideTerm, isTrue);
    });

    test('a non-effective lease never contributes, whatever its term', () {
      final live = computeLiveRentRoll(
        units: <UnitSummaryDto>[_unit('u1', 'A-01', UnitStatus.vacant)],
        effectiveLeases: <LeaseSummaryDto>[
          _lease('l1', 'u1', status: LeaseStatus.draft),
        ],
        asOfDate: _today,
      );

      expect(live.rows.single.effectiveLeaseCount, 0);
      expect(live.rows.single.isOccupiedButOutsideTerm, isFalse);
    });

    test('never sums across currencies — it names them (DEC-011)', () {
      final live = computeLiveRentRoll(
        units: <UnitSummaryDto>[
          _unit('u1', 'A-01', UnitStatus.occupied),
          _unit('u2', 'A-02', UnitStatus.occupied),
        ],
        effectiveLeases: <LeaseSummaryDto>[
          _lease('l1', 'u1', currency: 'EUR'),
          _lease('l2', 'u2', currency: 'CHF'),
        ],
        asOfDate: _today,
      );

      expect(live.summary.hasMixedCurrencies, isTrue);
      expect(live.summary.currencies, <String>['CHF', 'EUR']);
      expect(live.summary.currencyCode, isNull);
      // Per row the currency is unambiguous, so each row still reports one.
      expect(live.rows.first.currencyCode, 'EUR');
      expect(live.rows.first.hasMixedCurrencies, isFalse);
    });

    test('two currencies on one unit make that row ambiguous too', () {
      final live = computeLiveRentRoll(
        units: <UnitSummaryDto>[_unit('u1', 'A-01', UnitStatus.occupied)],
        effectiveLeases: <LeaseSummaryDto>[
          _lease('l1', 'u1', currency: 'EUR'),
          _lease('l2', 'u1', currency: 'CHF'),
        ],
        asOfDate: _today,
      );

      expect(live.rows.single.hasMixedCurrencies, isTrue);
      expect(live.rows.single.currencyCode, isNull);
    });

    test('partitions the units by status and reports the occupancy rate', () {
      final live = computeLiveRentRoll(
        units: <UnitSummaryDto>[
          _unit('u1', 'A-01', UnitStatus.occupied),
          _unit('u2', 'A-02', UnitStatus.vacant),
          _unit('u3', 'A-03', UnitStatus.offline),
          _unit('u4', 'A-04', UnitStatus.occupied),
        ],
        effectiveLeases: const <LeaseSummaryDto>[],
        asOfDate: _today,
      );

      expect(live.summary.occupiedUnitCount, 2);
      expect(live.summary.vacantUnitCount, 1);
      expect(live.summary.offlineUnitCount, 1);
      expect(live.summary.occupancyRate, 0.5);
    });

    test('an occupancy rate at zero units is null, not a misleading 0', () {
      final live = computeLiveRentRoll(
        units: const <UnitSummaryDto>[],
        effectiveLeases: const <LeaseSummaryDto>[],
        asOfDate: _today,
      );

      expect(live.summary.occupancyRate, isNull);
    });
  });
}

UnitSummaryDto _unit(String id, String code, UnitStatus status) =>
    UnitSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitCode: code,
  status: status,
  version: 1,
  areaSqm: 60,
);

LeaseSummaryDto _lease(
  String id,
  String unitId, {
  LeaseStatus status = LeaseStatus.active,
  double baseRent = 1000,
  String currency = 'EUR',
  DateTime? start,
  DateTime? end,
}) => LeaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitId: unitId,
  leaseName: id.toUpperCase(),
  status: status,
  startDate: start ?? DateTime.utc(2026, 1, 1),
  endDate: end,
  baseRentMonthly: baseRent,
  currencyCode: currency,
  version: 1,
);
