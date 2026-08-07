import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/portfolio_analytics.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/data/repositories/portfolio_analytics_repo.dart';
import 'package:neximmo_app/ui/screens/properties/widgets/property_card.dart';
import 'package:neximmo_app/ui/screens/properties_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/property_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for the redesigned `PropertiesScreen`
/// (Phase 2, Wave 1, Arbeitspaket 1): empty, error, and the
/// table/cards view toggle. The golden path lives in
/// `properties_screen_parity_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<Override> overrides,
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioAnalyticsRepositoryProvider
              .overrideWithValue(_FakeAnalyticsRepo()),
          propertyTitleImageProvider.overrideWith(
            (ref, propertyId) async => null,
          ),
          ...overrides,
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: PropertiesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty portfolio shows NxEmptyState with create action', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      overrides: [
        propertiesControllerProvider.overrideWith(_EmptyController.new),
      ],
    );

    expect(find.text('Keine Objekte vorhanden'), findsOneWidget);
    expect(find.text('Objekt erstellen'), findsOneWidget);
  });

  testWidgets('load failure shows retry state without raw exception text', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      overrides: [
        propertiesControllerProvider.overrideWith(_ThrowingController.new),
      ],
    );

    expect(
      find.text('Objekte konnten nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('table is the default view and the toggle switches to cards', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      overrides: [
        propertiesControllerProvider.overrideWith(_SeededController.new),
      ],
    );

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Asset Alpha'), findsWidgets);
    expect(find.text('Asset Beta'), findsWidgets);
    expect(find.text('Aktiv'), findsOneWidget);
    expect(find.text('Archiviert'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsNothing);
    expect(find.byType(PropertyCard), findsNWidgets(2));
    expect(find.text('Aktive Objekte'), findsOneWidget);
    expect(find.text('Archivierte Objekte'), findsOneWidget);
  });

  testWidgets('phone width falls back to the compact list without overflow', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(390, 844),
      overrides: [
        propertiesControllerProvider.overrideWith(_SeededController.new),
      ],
    );

    // Below the shell's mobile breakpoint the table renders as tiles.
    expect(find.byType(DataTable), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.text('Asset Alpha'), findsWidgets);
  });

  testWidgets('tablet width keeps the table view without overflow', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(1024, 768),
      overrides: [
        propertiesControllerProvider.overrideWith(_SeededController.new),
      ],
    );

    expect(find.byType(DataTable), findsOneWidget);
  });
}

class _FakeAnalyticsRepo implements PortfolioAnalyticsRepo {
  static const PortfolioMetricsSnapshot _emptySnapshot =
      PortfolioMetricsSnapshot(
    totalValue: 0,
    totalAcquisitionCosts: 0,
    netYield: 0,
    vacancyRate: 0,
    ltv: 0,
    totalLoanPrincipal: 0,
    propertyKpis: {},
  );

  @override
  Future<PortfolioMetricsSnapshot> loadOverviewMetrics({
    required Set<String> activePropertyIds,
  }) async {
    return _emptySnapshot;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}

class _EmptyController extends PropertiesController {
  @override
  Future<List<PropertyRecord>> build() async => const <PropertyRecord>[];
}

class _ThrowingController extends PropertiesController {
  @override
  Future<List<PropertyRecord>> build() async {
    throw Exception('boom');
  }
}

class _SeededController extends PropertiesController {
  @override
  Future<List<PropertyRecord>> build() async {
    return const <PropertyRecord>[
      PropertyRecord(
        id: 'p1',
        name: 'Asset Alpha',
        addressLine1: 'Main Street 1',
        zip: '10115',
        city: 'Berlin',
        country: 'DE',
        propertyType: 'multifamily',
        units: 12,
        createdAt: 1,
        updatedAt: 1,
      ),
      PropertyRecord(
        id: 'p2',
        name: 'Asset Beta',
        addressLine1: 'Side Street 2',
        zip: '20095',
        city: 'Hamburg',
        country: 'DE',
        propertyType: 'commercial',
        units: 3,
        archived: true,
        createdAt: 1,
        updatedAt: 1,
      ),
    ];
  }
}
