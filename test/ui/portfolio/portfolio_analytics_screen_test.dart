import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/portfolio_analytics.dart';
import 'package:neximmo_app/data/repositories/portfolio_analytics_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/portfolio/portfolio_analytics_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('real database smoke test', () {
    late AppDatabase appDatabase;
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
      db = await appDatabase.instance;

      await db.insert('portfolios', <String, Object?>{
        'id': 'p1',
        'name': 'Fund',
        'description': null,
        'created_at': 1,
        'updated_at': 1,
      });
    });

    tearDown(() async {
      await appDatabase.close();
    });

    testWidgets('renders analytics screen and computes baseline state', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              appDatabaseProvider.overrideWithValue(appDatabase),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: PortfolioAnalyticsScreen(
                  portfolioId: 'p1',
                  portfolioName: 'Fund',
                ),
              ),
            ),
          ),
        );

        for (int i = 0; i < 40; i++) {
          await tester.pump();
          if (find.text('Portfolio IRR').evaluate().isNotEmpty) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
      });

      expect(find.textContaining('Portfolio Analytics'), findsOneWidget);
      expect(find.text('Portfolio IRR'), findsOneWidget);

      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
    });
  });

  group('mandatory states (fake providers)', () {
    const emptyResult = PortfolioIrrResult(
      irr: 0.05,
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
      required _AnalyticsLoad mode,
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
            portfolioAnalyticsRepositoryProvider
                .overrideWithValue(_FakeAnalyticsRepo(mode, emptyResult)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: PortfolioAnalyticsScreen(
                portfolioId: 'p1',
                portfolioName: 'Fund',
              ),
            ),
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      }
    }

    testWidgets('loading shows a skeleton, not a full-surface spinner', (
      tester,
    ) async {
      await pumpScreen(tester, mode: _AnalyticsLoad.pending, settle: false);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('analytics_skeleton')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('result renders metric tiles and the cashflow chart', (
      tester,
    ) async {
      await pumpScreen(tester, mode: _AnalyticsLoad.ok);

      expect(find.text('Portfolio IRR'), findsOneWidget);
      expect(find.text('Cashflow Verlauf'), findsOneWidget);
    });

    testWidgets('compute failure shows retry state without raw exception text', (
      tester,
    ) async {
      await pumpScreen(tester, mode: _AnalyticsLoad.error);

      expect(
        find.text('Analytics konnte nicht berechnet werden'),
        findsOneWidget,
      );
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('phone width renders without overflow', (tester) async {
      await pumpScreen(tester, mode: _AnalyticsLoad.ok, size: const Size(390, 844));
      expect(find.textContaining('Portfolio Analytics'), findsWidgets);
    });

    testWidgets('tablet width renders without overflow', (tester) async {
      await pumpScreen(tester, mode: _AnalyticsLoad.ok, size: const Size(1024, 768));
      expect(find.textContaining('Portfolio Analytics'), findsWidgets);
    });

    testWidgets('desktop width renders without overflow', (tester) async {
      await pumpScreen(tester, mode: _AnalyticsLoad.ok, size: const Size(1440, 900));
      expect(find.textContaining('Portfolio Analytics'), findsWidgets);
    });
  });
}

enum _AnalyticsLoad { ok, error, pending }

class _FakeAnalyticsRepo implements PortfolioAnalyticsRepo {
  _FakeAnalyticsRepo(this.mode, this.result);

  final _AnalyticsLoad mode;
  final PortfolioIrrResult result;

  @override
  Future<PortfolioIrrResult> computePortfolioIRR({
    required String portfolioId,
    required String fromPeriodKey,
    required String toPeriodKey,
  }) {
    switch (mode) {
      case _AnalyticsLoad.pending:
        return Completer<PortfolioIrrResult>().future;
      case _AnalyticsLoad.error:
        return Future<PortfolioIrrResult>.error(Exception('boom'));
      case _AnalyticsLoad.ok:
        return Future<PortfolioIrrResult>.value(result);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}
