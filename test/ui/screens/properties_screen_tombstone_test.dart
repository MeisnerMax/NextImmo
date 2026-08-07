import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/portfolio_analytics.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/data/repositories/portfolio_analytics_repo.dart';
import 'package:neximmo_app/ui/screens/properties_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/property_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Tombstone/restore UI coverage for the redesigned `PropertiesScreen`
/// (Phase 2, Wave 1, DEBT-012/STM-002). The data layer is exercised by
/// `test/data/repositories/property_repo_tombstone_test.dart`; this closes the
/// thin UI branch: the "Gelöscht" status, the restore-only action menu, the
/// delete confirmation, and that both wire through to the controller.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _seed = const <PropertyRecord>[];
    _tombstoneCalls.clear();
    _restoreCalls.clear();
    _archiveCalls.clear();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioAnalyticsRepositoryProvider.overrideWithValue(
            _FakeAnalyticsRepo(),
          ),
          propertyTitleImageProvider.overrideWith(
            (ref, propertyId) async => null,
          ),
          propertiesControllerProvider.overrideWith(_SpyController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: PropertiesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openRowActionsMenu(WidgetTester tester) async {
    // The actions menu sits in the table's trailing column; scroll it into view
    // (the shell scrolls the table horizontally) before opening it.
    final menuButton = find.byType(PopupMenuButton<String>).first;
    await tester.ensureVisible(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
  }

  testWidgets('tombstoned property renders the Gelöscht status badge', (
    tester,
  ) async {
    _seed = <PropertyRecord>[_tombstoned()];
    await pumpScreen(tester);

    expect(find.text('Gelöscht'), findsWidgets);
    expect(find.text('Archiviert'), findsNothing);
    expect(find.text('Aktiv'), findsNothing);
  });

  testWidgets('tombstoned property offers only restore in its actions menu', (
    tester,
  ) async {
    _seed = <PropertyRecord>[_tombstoned()];
    await pumpScreen(tester);
    await openRowActionsMenu(tester);

    expect(find.text('Wiederherstellen'), findsOneWidget);
    // Never archive/delete a tombstoned row: no inconsistent live-but-deleted.
    expect(find.text('Löschen'), findsNothing);
    expect(find.text('Archivieren'), findsNothing);
    expect(find.text('Aus Archiv holen'), findsNothing);
  });

  testWidgets('restore action invokes the controller restore', (tester) async {
    _seed = <PropertyRecord>[_tombstoned()];
    await pumpScreen(tester);
    await openRowActionsMenu(tester);

    await tester.tap(find.text('Wiederherstellen'));
    await tester.pumpAndSettle();

    expect(_restoreCalls, <String>['p-del']);
    expect(_tombstoneCalls, isEmpty);
  });

  testWidgets('delete confirmation tombstones the property', (tester) async {
    _seed = <PropertyRecord>[_active()];
    await pumpScreen(tester);
    await openRowActionsMenu(tester);

    // The redesigned delete is a reversible tombstone, not a hard delete.
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Objekt löschen'), findsOneWidget);
    expect(_tombstoneCalls, isEmpty, reason: 'confirmation is required first');

    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await tester.pumpAndSettle();

    expect(_tombstoneCalls, <String>['p-act']);
    expect(_restoreCalls, isEmpty);
  });
}

List<PropertyRecord> _seed = const <PropertyRecord>[];
final List<String> _tombstoneCalls = <String>[];
final List<String> _restoreCalls = <String>[];
final List<(String, bool)> _archiveCalls = <(String, bool)>[];

PropertyRecord _active({String id = 'p-act'}) {
  return PropertyRecord(
    id: id,
    name: 'Aktiv Alpha',
    addressLine1: 'Main Street 1',
    zip: '10115',
    city: 'Berlin',
    country: 'DE',
    propertyType: 'multifamily',
    units: 6,
    createdAt: 1,
    updatedAt: 1,
  );
}

PropertyRecord _tombstoned({String id = 'p-del'}) {
  return PropertyRecord(
    id: id,
    name: 'Gelöscht Beta',
    addressLine1: 'Side Street 2',
    zip: '20095',
    city: 'Hamburg',
    country: 'DE',
    propertyType: 'commercial',
    units: 3,
    archived: true,
    createdAt: 1,
    updatedAt: 1,
    deletedAt: 1720000000000,
    deletedBy: 'actor-x',
  );
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

class _SpyController extends PropertiesController {
  @override
  Future<List<PropertyRecord>> build() async => _seed;

  @override
  Future<void> tombstone(String propertyId) async {
    _tombstoneCalls.add(propertyId);
  }

  @override
  Future<void> restore(String propertyId) async {
    _restoreCalls.add(propertyId);
  }

  @override
  Future<void> archive(String propertyId, bool archived) async {
    _archiveCalls.add((propertyId, archived));
  }
}
