import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_providers.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';
import 'package:neximmo_app/ui/screens/portfolio/rental_overview_panel.dart';

const String _workspace = 'workspace-a';

void main() {
  testWidgets('lists every property with its occupancy', (tester) async {
    await _pump(
      tester,
      properties: <PropertySummaryDto>[
        _property('p1', 'Nordhaus', 'Hamburg'),
        _property('p2', 'Südhaus', 'München'),
      ],
      units: <UnitSummaryDto>[
        _unit('u1', 'p1', UnitStatus.occupied),
        _unit('u2', 'p1', UnitStatus.vacant),
        _unit('u3', 'p2', UnitStatus.occupied),
      ],
      leases: <LeaseSummaryDto>[_lease('l1', 'p1', 'u1')],
    );

    expect(find.text('Vermietung'), findsWidgets);
    expect(find.text('Nordhaus'), findsOneWidget);
    expect(find.text('Südhaus'), findsOneWidget);
    expect(find.text('50.0 %'), findsOneWidget);
    expect(find.text('100.0 %'), findsOneWidget);
  });

  testWidgets('an empty portfolio says so instead of showing zeros', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Noch keine Einheit im Portfolio'), findsOneWidget);
  });

  testWidgets('forbidden is its own state', (tester) async {
    await _pump(tester, unitFailure: LeasingRepositoryFailureKind.forbidden);

    expect(
      find.text('Kein Zugriff auf die Vermietungssicht'),
      findsOneWidget,
    );
  });

  testWidgets('an error offers a retry, not a raw exception', (tester) async {
    await _pump(
      tester,
      unitFailure: LeasingRepositoryFailureKind.infrastructureFailure,
    );

    expect(
      find.text('Vermietungssicht konnte nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('mixed currencies are named instead of summed', (tester) async {
    await _pump(
      tester,
      properties: <PropertySummaryDto>[
        _property('p1', 'Nordhaus', 'Hamburg'),
        _property('p2', 'Zürichhaus', 'Zürich'),
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

    expect(find.textContaining('CHF und EUR'), findsOneWidget);
  });

  for (final size in const <Size>[
    Size(390, 844),
    Size(1024, 768),
    Size(1440, 900),
  ]) {
    testWidgets('renders without overflow at ${size.width.toInt()} px', (
      tester,
    ) async {
      await _pump(
        tester,
        size: size,
        properties: <PropertySummaryDto>[_property('p1', 'Nordhaus', 'Hamburg')],
        units: <UnitSummaryDto>[_unit('u1', 'p1', UnitStatus.occupied)],
        leases: <LeaseSummaryDto>[_lease('l1', 'p1', 'u1')],
      );

      expect(find.text('Nordhaus'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  List<PropertySummaryDto> properties = const <PropertySummaryDto>[],
  List<UnitSummaryDto> units = const <UnitSummaryDto>[],
  List<LeaseSummaryDto> leases = const <LeaseSummaryDto>[],
  LeasingRepositoryFailureKind? unitFailure,
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: _workspace,
            actorId: 'actor-1',
            permissions: const <String>{'lease.read', 'property.read'},
            mutationsSupported: true,
          ),
        ),
        referencePropertyRepositoryProvider.overrideWithValue(
          _FakeProperties(properties),
        ),
        unitSearchProvider.overrideWithValue(
          _FakeUnitSearch(units: units, failure: unitFailure),
        ),
        leaseSearchProvider.overrideWithValue(_FakeLeaseSearch(leases)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: RentalOverviewPanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
  String currency = 'EUR',
}) => LeaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: propertyId,
  unitId: unitId,
  leaseName: id.toUpperCase(),
  status: LeaseStatus.active,
  startDate: DateTime.utc(2020, 1, 1),
  baseRentMonthly: 1000,
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
  Future<PropertyRepositoryResult<PropertyDto>> create(
    PropertyCreateCommand command,
  ) async => const PropertyRepositoryFailure<PropertyDto>(
    kind: PropertyRepositoryFailureKind.forbidden,
    message: 'not used by this screen',
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
  _FakeUnitSearch({required this.units, this.failure});

  final List<UnitSummaryDto> units;
  final LeasingRepositoryFailureKind? failure;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<UnitSummaryDto>>> search(
    UnitListQuery query,
  ) async {
    final kind = failure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeasingPageResult<UnitSummaryDto>>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
      LeasingPageResult<UnitSummaryDto>(items: units),
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
