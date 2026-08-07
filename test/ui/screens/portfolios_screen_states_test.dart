import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/asset_workbook.dart';
import 'package:neximmo_app/core/models/portfolio.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/data/repositories/asset_workbook_repo.dart';
import 'package:neximmo_app/data/repositories/covenant_repo.dart';
import 'package:neximmo_app/data/repositories/portfolio_repo.dart';
import 'package:neximmo_app/data/repositories/property_repo.dart';
import 'package:neximmo_app/ui/screens/portfolios_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for the redesigned `PortfoliosScreen` landing
/// (Phase 2, Wave 1, Arbeitspaket 6 — BIG-004 split): loading skeleton, empty,
/// error-with-retry, the two-tab structure (Übersicht/Eigenkapital) and the
/// responsive breakpoints. The screen loads via `FutureBuilder`, so fakes drive
/// the repositories `_loadLandingVm` reads. Properties are kept empty so the
/// covenant repository is never touched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const portfolio = PortfolioRecord(
    id: 'pf1',
    name: 'Alpha Portfolio',
    createdAt: 1,
    updatedAt: 1,
  );

  const row = PortfolioRentalOverviewRow(
    propertyId: 'p1',
    propertyName: 'Row Alpha',
    propertyType: 'multifamily',
    units: 10,
    occupiedUnits: 9,
    vacantUnits: 1,
    annualRent: 120000,
    monthlyRentRunRate: 10000,
    annualOperatingCosts: 30000,
    openDepositAmount: 0,
    serviceChargeBalance: 0,
    ownerLabels: <String>['Owner A'],
    sourceAreasComplete: 3,
    sourceAreasTotal: 3,
    missingSourceLabels: <String>[],
  );

  PortfolioRentalOverview overview({
    List<PortfolioRentalOverviewRow> rows = const [],
  }) {
    return PortfolioRentalOverview(
      rows: rows,
      assetsTotal: rows.length,
      assetsNotActive: 0,
      rentedUnits: 0,
      emptyUnits: 0,
      annualRent: 0,
      monthlyRentRunRate: 0,
      annualOperatingCosts: 0,
      openDepositAmount: 0,
      serviceChargeBalance: 0,
      sourceAreasComplete: 0,
      sourceAreasTotal: 0,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    _PortfolioLoad mode = _PortfolioLoad.ok,
    List<PortfolioRecord> portfolios = const [],
    List<PortfolioRentalOverviewRow> rows = const [],
    Size size = const Size(1280, 800),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioRepositoryProvider.overrideWithValue(
            _FakePortfolioRepo(portfolios: portfolios, mode: mode),
          ),
          propertyRepositoryProvider.overrideWithValue(_FakePropertyRepo()),
          assetWorkbookRepositoryProvider
              .overrideWithValue(_FakeAssetWorkbookRepo(overview(rows: rows))),
          covenantRepositoryProvider.overrideWithValue(_FakeCovenantRepo()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: PortfoliosScreen()),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('loading shows a skeleton, not a full-page spinner', (
    tester,
  ) async {
    await pumpScreen(tester, mode: _PortfolioLoad.pending, settle: false);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('portfolio_landing_skeleton')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty workspace shows the create-portfolio empty state', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Portfolio Asset Management'), findsOneWidget);
    expect(find.text('No portfolios yet'), findsOneWidget);
  });

  testWidgets('load failure shows retry state without raw exception text', (
    tester,
  ) async {
    await pumpScreen(tester, mode: _PortfolioLoad.error);

    expect(
      find.text('Portfolios konnten nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('seeded landing lists the portfolio and switches equity tab', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      portfolios: const [portfolio],
      rows: const [row],
    );

    expect(find.text('Managed Portfolios'), findsOneWidget);
    expect(find.text('Alpha Portfolio'), findsOneWidget);
    // Übersicht tab metrics.
    expect(find.text('GESAMTWERT'), findsOneWidget);

    await tester.tap(find.text('Eigenkapital-Dashboard'));
    await tester.pumpAndSettle();

    expect(find.text('EIGENKAPITAL'), findsOneWidget);
  });

  testWidgets('phone width renders the landing without overflow', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(390, 844),
      portfolios: const [portfolio],
      rows: const [row],
    );

    expect(find.text('Portfolio Asset Management'), findsOneWidget);
  });

  testWidgets('tablet width renders the landing without overflow', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(1024, 768),
      portfolios: const [portfolio],
      rows: const [row],
    );

    expect(find.text('Portfolio Asset Management'), findsOneWidget);
  });

  testWidgets('desktop width renders the landing without overflow', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(1440, 900),
      portfolios: const [portfolio],
      rows: const [row],
    );

    expect(find.text('Portfolio Asset Management'), findsOneWidget);
  });
}

enum _PortfolioLoad { ok, pending, error }

class _FakePortfolioRepo implements PortfolioRepository {
  _FakePortfolioRepo({this.portfolios = const [], this.mode = _PortfolioLoad.ok});

  final List<PortfolioRecord> portfolios;
  final _PortfolioLoad mode;

  @override
  Future<List<PortfolioRecord>> listPortfolios() {
    switch (mode) {
      case _PortfolioLoad.pending:
        return Completer<List<PortfolioRecord>>().future;
      case _PortfolioLoad.error:
        return Future<List<PortfolioRecord>>.error(Exception('boom'));
      case _PortfolioLoad.ok:
        return Future<List<PortfolioRecord>>.value(portfolios);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}

class _FakePropertyRepo implements PropertyRepository {
  @override
  Future<List<PropertyRecord>> list({bool includeArchived = false}) async =>
      const <PropertyRecord>[];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}

class _FakeAssetWorkbookRepo implements AssetWorkbookRepo {
  _FakeAssetWorkbookRepo(this.overview);

  final PortfolioRentalOverview overview;

  @override
  Future<PortfolioRentalOverview> loadPortfolioOverview({
    bool includeArchived = false,
  }) async =>
      overview;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}

class _FakeCovenantRepo implements CovenantRepo {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}
