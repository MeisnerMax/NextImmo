import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/note.dart';
import 'package:neximmo_app/core/models/portfolio.dart';
import 'package:neximmo_app/core/models/portfolio_analytics.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/data/repositories/inputs_repo.dart';
import 'package:neximmo_app/data/repositories/notes_repo.dart';
import 'package:neximmo_app/data/repositories/portfolio_analytics_repo.dart';
import 'package:neximmo_app/data/repositories/portfolio_repo.dart';
import 'package:neximmo_app/ui/screens/portfolio/portfolio_detail_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for `PortfolioDetailScreen` (Phase 2, Wave 1,
/// Arbeitspaket 6 — SCR-044, extracted from the BIG-004 split). The screen loads
/// via `FutureBuilder`; fakes drive the repositories `_loadVm` reads. Covers the
/// loading skeleton, the error-with-retry state, and a successful render that
/// proves the 4-tab structure and the PDF export action survived the split.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const portfolio = PortfolioRecord(
    id: 'pf1',
    name: 'Alpha Portfolio',
    createdAt: 1,
    updatedAt: 1,
  );

  const emptyIrr = PortfolioIrrResult(
    irr: null,
    warning: null,
    totalInflows: 0,
    totalOutflows: 0,
    netCashflow: 0,
    averageMonthlyNet: 0,
    datedCashflows: <PortfolioCashflowRecord>[],
    periodTable: <PortfolioCashflowPeriodAggregate>[],
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    _DetailLoad mode = _DetailLoad.ok,
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
            _FakePortfolioRepo(portfolio: portfolio, mode: mode),
          ),
          inputsRepositoryProvider.overrideWithValue(_FakeInputsRepo()),
          portfolioAnalyticsRepositoryProvider
              .overrideWithValue(_FakeAnalyticsRepo(emptyIrr)),
          notesRepositoryProvider.overrideWithValue(_FakeNotesRepo()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PortfolioDetailScreen(
              portfolioId: 'pf1',
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('loading shows a detail skeleton, not a full-page spinner', (
    tester,
  ) async {
    await pumpScreen(tester, mode: _DetailLoad.pending, settle: false);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('portfolio_detail_skeleton')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('load failure shows retry state without raw exception text', (
    tester,
  ) async {
    await pumpScreen(tester, mode: _DetailLoad.missing);

    expect(
      find.text('Portfolio konnte nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('successful load renders the 4 tabs and the PDF export action', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Alpha Portfolio'), findsOneWidget);
    expect(find.text('PDF Export'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Analyse'), findsOneWidget);
    expect(find.text('Objekte'), findsOneWidget);
    expect(find.text('Notizen'), findsOneWidget);
  });
}

enum _DetailLoad { ok, pending, missing }

class _FakePortfolioRepo implements PortfolioRepository {
  _FakePortfolioRepo({required this.portfolio, this.mode = _DetailLoad.ok});

  final PortfolioRecord portfolio;
  final _DetailLoad mode;

  @override
  Future<PortfolioRecord?> getById(String id) {
    switch (mode) {
      case _DetailLoad.pending:
        return Completer<PortfolioRecord?>().future;
      case _DetailLoad.missing:
        return Future<PortfolioRecord?>.value(null);
      case _DetailLoad.ok:
        return Future<PortfolioRecord?>.value(portfolio);
    }
  }

  @override
  Future<List<PropertyRecord>> listPortfolioProperties(String portfolioId) async =>
      const <PropertyRecord>[];

  @override
  Future<List<PropertyRecord>> listUnassignedProperties(String portfolioId) async =>
      const <PropertyRecord>[];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}

class _FakeInputsRepo implements InputsRepository {
  @override
  Future<AppSettingsRecord> getSettings() async =>
      const AppSettingsRecord(updatedAt: 1);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}

class _FakeAnalyticsRepo implements PortfolioAnalyticsRepo {
  _FakeAnalyticsRepo(this.result);

  final PortfolioIrrResult result;

  @override
  Future<PortfolioIrrResult> computePortfolioIRR({
    required String portfolioId,
    required String fromPeriodKey,
    required String toPeriodKey,
  }) async =>
      result;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}

class _FakeNotesRepo implements NotesRepository {
  @override
  Future<List<NoteRecord>> listNotes({
    required String entityType,
    required String entityId,
  }) async =>
      const <NoteRecord>[];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}
