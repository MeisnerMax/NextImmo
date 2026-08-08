import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/application/rental_overview_controller.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';

const String _workspace = 'workspace-a';
final DateTime _today = DateTime.utc(2026, 3, 31);

void main() {
  group('portfolio rows', () {
    test('groups units by property and names each one', () async {
      final controller = _controller(
        properties: <PropertySummaryDto>[
          _property('p1', 'Nordhaus', 'Hamburg'),
          _property('p2', 'Südhaus', 'München'),
        ],
        units: <UnitSummaryDto>[
          _unit('u1', 'p1', UnitStatus.occupied),
          _unit('u2', 'p1', UnitStatus.vacant),
          _unit('u3', 'p2', UnitStatus.occupied),
        ],
        leases: <LeaseSummaryDto>[
          _lease('l1', 'p1', 'u1'),
          _lease('l2', 'p2', 'u3', baseRent: 2000),
        ],
      );
      await controller.load();

      expect(controller.state.phase, RentalOverviewPhase.ready);
      expect(controller.state.rows, hasLength(2));
      final north = controller.state.rows.firstWhere(
        (row) => row.propertyId == 'p1',
      );
      expect(north.propertyName, 'Nordhaus');
      expect(north.city, 'Hamburg');
      expect(north.summary.unitCount, 2);
      expect(north.summary.occupancyRate, 0.5);
      expect(north.summary.totalBaseRentMonthly, 1000);
    });

    test('an unresolvable property is named as such, not dropped', () async {
      // Losing a property from a portfolio total would be worse than an ugly
      // label: the sum would silently shrink.
      final controller = _controller(
        properties: const <PropertySummaryDto>[],
        units: <UnitSummaryDto>[_unit('u1', 'p1', UnitStatus.vacant)],
      );
      await controller.load();

      expect(controller.state.rows, hasLength(1));
      expect(controller.state.rows.single.propertyName, contains('nicht'));
    });

    test('reads workspace-wide, without a property filter', () async {
      final units = _FakeUnitSearch(units: <UnitSummaryDto>[]);
      final controller = _controller(unitSearch: units);
      await controller.load();

      expect(units.lastQuery?.propertyId, isNull);
    });

    test('an empty portfolio is its own phase, not an error', () async {
      final controller = _controller();
      await controller.load();

      expect(controller.state.phase, RentalOverviewPhase.empty);
    });

    test('forbidden is distinct from error', () async {
      final controller = _controller(
        unitSearch: _FakeUnitSearch(
          units: const <UnitSummaryDto>[],
          failure: LeasingRepositoryFailureKind.forbidden,
        ),
      );
      await controller.load();

      expect(controller.state.phase, RentalOverviewPhase.forbidden);
    });
  });

  group('totals', () {
    test('sum the properties and report the portfolio occupancy', () async {
      final controller = _controller(
        properties: <PropertySummaryDto>[
          _property('p1', 'Nordhaus', 'Hamburg'),
          _property('p2', 'Südhaus', 'München'),
        ],
        units: <UnitSummaryDto>[
          _unit('u1', 'p1', UnitStatus.occupied),
          _unit('u2', 'p1', UnitStatus.vacant),
          _unit('u3', 'p2', UnitStatus.occupied),
          _unit('u4', 'p2', UnitStatus.offline),
        ],
        leases: <LeaseSummaryDto>[
          _lease('l1', 'p1', 'u1'),
          _lease('l2', 'p2', 'u3', baseRent: 2000),
        ],
      );
      await controller.load();

      final totals = controller.state.totals!;
      expect(totals.propertyCount, 2);
      expect(totals.unitCount, 4);
      expect(totals.occupiedUnitCount, 2);
      expect(totals.offlineUnitCount, 1);
      expect(totals.occupancyRate, 0.5);
      expect(totals.totalBaseRentMonthly, 3000);
      expect(totals.currencyCode, 'EUR');
    });

    test('never sum across currencies — they are named (DEC-011)', () async {
      final controller = _controller(
        properties: <PropertySummaryDto>[
          _property('p1', 'Nordhaus', 'Hamburg'),
          _property('p2', 'Südhaus', 'Zürich'),
        ],
        units: <UnitSummaryDto>[
          _unit('u1', 'p1', UnitStatus.occupied),
          _unit('u2', 'p2', UnitStatus.occupied),
        ],
        leases: <LeaseSummaryDto>[
          _lease('l1', 'p1', 'u1'),
          _lease('l2', 'p2', 'u2', currency: 'CHF'),
        ],
      );
      await controller.load();

      expect(controller.state.totals!.hasMixedCurrencies, isTrue);
      expect(controller.state.totals!.currencies, <String>['CHF', 'EUR']);
    });

    test('count leases whose term ends inside the horizon', () async {
      final controller = _controller(
        properties: <PropertySummaryDto>[_property('p1', 'Nordhaus', 'Hamburg')],
        units: <UnitSummaryDto>[
          _unit('u1', 'p1', UnitStatus.occupied),
          _unit('u2', 'p1', UnitStatus.occupied),
        ],
        leases: <LeaseSummaryDto>[
          // Ends in 30 days — inside the 90-day horizon.
          _lease('l1', 'p1', 'u1', end: DateTime.utc(2026, 4, 30)),
          // Ends in a year — outside it.
          _lease('l2', 'p1', 'u2', end: DateTime.utc(2027, 3, 31)),
        ],
      );
      await controller.load();

      expect(controller.state.totals!.expiringLeaseCount, 1);
    });
  });

  group('the bounded read', () {
    test('reports truncation instead of silently showing less', () async {
      // A silently truncated portfolio reads as a smaller portfolio.
      final controller = _controller(
        properties: <PropertySummaryDto>[_property('p1', 'Nordhaus', 'Hamburg')],
        unitSearch: _FakeUnitSearch(
          units: <UnitSummaryDto>[_unit('u1', 'p1', UnitStatus.vacant)],
          alwaysMore: true,
        ),
      );
      await controller.load();

      expect(controller.state.truncated, isTrue);
      expect(controller.state.phase, RentalOverviewPhase.ready);
    });

    test('is not truncated when the last page ends the keyset', () async {
      final controller = _controller(
        properties: <PropertySummaryDto>[_property('p1', 'Nordhaus', 'Hamburg')],
        units: <UnitSummaryDto>[_unit('u1', 'p1', UnitStatus.vacant)],
      );
      await controller.load();

      expect(controller.state.truncated, isFalse);
    });
  });
}

RentalOverviewController _controller({
  List<PropertySummaryDto> properties = const <PropertySummaryDto>[],
  List<UnitSummaryDto> units = const <UnitSummaryDto>[],
  List<LeaseSummaryDto> leases = const <LeaseSummaryDto>[],
  _FakeUnitSearch? unitSearch,
}) {
  final controller = RentalOverviewController(
    properties: _FakeProperties(properties),
    unitSearch: unitSearch ?? _FakeUnitSearch(units: units),
    leaseSearch: _FakeLeaseSearch(leases),
    scope: WorkspaceSessionScope(
      workspaceId: _workspace,
      actorId: 'actor-1',
      permissions: <String>{'lease.read', 'property.read'},
      mutationsSupported: true,
    ),
    clock: () => _today,
  );
  addTearDown(controller.dispose);
  return controller;
}

PropertySummaryDto _property(String id, String name, String city) =>
    PropertySummaryDto(
  id: id,
  workspaceId: _workspace,
  name: name,
  addressLine1: 'Musterweg 1',
  zip: '10115',
  city: city,
  status: PropertyStatus.active,
  version: 1,
);

UnitSummaryDto _unit(String id, String propertyId, UnitStatus status) =>
    UnitSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: propertyId,
  unitCode: id.toUpperCase(),
  status: status,
  version: 1,
);

LeaseSummaryDto _lease(
  String id,
  String propertyId,
  String unitId, {
  double baseRent = 1000,
  String currency = 'EUR',
  DateTime? end,
}) => LeaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: propertyId,
  unitId: unitId,
  leaseName: id.toUpperCase(),
  status: LeaseStatus.active,
  startDate: DateTime.utc(2020, 1, 1),
  endDate: end,
  baseRentMonthly: baseRent,
  currencyCode: currency,
  version: 1,
);

class _FakeProperties implements PropertyRepository {
  _FakeProperties(this.properties);

  final List<PropertySummaryDto> properties;

  @override
  Future<PropertyRepositoryResult<PropertyPageResult>> list(
    PropertyListQuery query,
  ) async => PropertyRepositorySuccess<PropertyPageResult>(
    PropertyPageResult(items: properties),
  );

  @override
  Future<PropertyRepositoryResult<PropertyDto>> getById({
    required String workspaceId,
    required String propertyId,
  }) async => const PropertyRepositoryFailure<PropertyDto>(
    kind: PropertyRepositoryFailureKind.notFound,
    message: 'not used',
  );

  @override
  Future<PropertyRepositoryResult<PropertyDto>> update(
    PropertyUpdateCommand command,
  ) async => const PropertyRepositoryFailure<PropertyDto>(
    kind: PropertyRepositoryFailureKind.dependencyConflict,
    message: 'not used',
  );
}

class _FakeUnitSearch implements UnitSearchPort {
  _FakeUnitSearch({required this.units, this.failure, this.alwaysMore = false});

  final List<UnitSummaryDto> units;
  final LeasingRepositoryFailureKind? failure;

  /// Never exhausts the keyset, which is how the page bound gets hit.
  final bool alwaysMore;

  UnitListQuery? lastQuery;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<UnitSummaryDto>>> search(
    UnitListQuery query,
  ) async {
    lastQuery = query;
    final kind = failure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeasingPageResult<UnitSummaryDto>>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
      LeasingPageResult<UnitSummaryDto>(
        items: query.page.cursor == null || alwaysMore
            ? units
            : const <UnitSummaryDto>[],
        nextCursor: alwaysMore ? 'next' : null,
      ),
    );
  }
}

class _FakeLeaseSearch implements LeaseSearchPort {
  _FakeLeaseSearch(this.leases);

  final List<LeaseSummaryDto> leases;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeaseSummaryDto>>> search(
    LeaseListQuery query,
  ) async {
    return LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
      LeasingPageResult<LeaseSummaryDto>(items: leases),
    );
  }
}
