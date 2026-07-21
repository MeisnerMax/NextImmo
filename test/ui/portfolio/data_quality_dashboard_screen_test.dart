import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/data/repositories/data_quality_repo.dart';
import 'package:neximmo_app/data/repositories/inputs_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/portfolio/data_quality_dashboard_screen.dart';
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
      await db.insert('properties', <String, Object?>{
        'id': 'a1',
        'name': 'Asset 1',
        'address_line1': '',
        'address_line2': null,
        'zip': '',
        'city': '',
        'country': 'DE',
        'property_type': '',
        'units': 0,
        'sqft': null,
        'year_built': null,
        'notes': null,
        'created_at': 1,
        'updated_at': 1,
        'archived': 0,
      });
      await db.insert('portfolio_properties', <String, Object?>{
        'portfolio_id': 'p1',
        'property_id': 'a1',
        'created_at': 1,
      });
    });

    tearDown(() async {
      await appDatabase.close();
    });

    testWidgets('shows quality score and issues container', (tester) async {
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
                body: DataQualityDashboardScreen(
                  portfolioId: 'p1',
                  portfolioName: 'Fund',
                ),
              ),
            ),
          ),
        );

        for (int i = 0; i < 40; i++) {
          await tester.pump();
          if (find.text('Portfolio Score').evaluate().isNotEmpty) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
      });

      expect(find.textContaining('Datenqualität'), findsOneWidget);
      expect(find.text('Portfolio Score'), findsOneWidget);

      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
    });
  });

  group('mandatory states (fake providers)', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required _QualityLoad mode,
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
            inputsRepositoryProvider.overrideWithValue(_FakeInputsRepo()),
            dataQualityRepositoryProvider
                .overrideWithValue(_FakeDataQualityRepo(mode)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: DataQualityDashboardScreen(
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
      await pumpScreen(tester, mode: _QualityLoad.pending, settle: false);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('data_quality_skeleton')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('no findings shows the positive all-clear empty state', (
      tester,
    ) async {
      await pumpScreen(tester, mode: _QualityLoad.empty);

      expect(find.text('Alles im grünen Bereich'), findsOneWidget);
      expect(find.text('Portfolio Score'), findsOneWidget);
    });

    testWidgets('load failure shows retry state without raw exception text', (
      tester,
    ) async {
      await pumpScreen(tester, mode: _QualityLoad.error);

      expect(
        find.text('Datenqualität konnte nicht geladen werden'),
        findsOneWidget,
      );
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('phone width renders without overflow', (tester) async {
      await pumpScreen(tester, mode: _QualityLoad.empty, size: const Size(390, 844));
      expect(find.textContaining('Datenqualität'), findsWidgets);
    });

    testWidgets('tablet width renders without overflow', (tester) async {
      await pumpScreen(tester, mode: _QualityLoad.empty, size: const Size(1024, 768));
      expect(find.textContaining('Datenqualität'), findsWidgets);
    });

    testWidgets('desktop width renders without overflow', (tester) async {
      await pumpScreen(tester, mode: _QualityLoad.empty, size: const Size(1440, 900));
      expect(find.textContaining('Datenqualität'), findsWidgets);
    });
  });
}

enum _QualityLoad { empty, error, pending }

class _FakeInputsRepo implements InputsRepository {
  @override
  Future<AppSettingsRecord> getSettings() async =>
      const AppSettingsRecord(updatedAt: 1);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}

class _FakeDataQualityRepo implements DataQualityRepo {
  _FakeDataQualityRepo(this.mode);

  final _QualityLoad mode;

  @override
  Future<PortfolioQualitySnapshot> loadPortfolioSnapshot({
    required String portfolioId,
  }) {
    switch (mode) {
      case _QualityLoad.pending:
        return Completer<PortfolioQualitySnapshot>().future;
      case _QualityLoad.error:
        return Future<PortfolioQualitySnapshot>.error(Exception('boom'));
      case _QualityLoad.empty:
        return Future<PortfolioQualitySnapshot>.value(
          PortfolioQualitySnapshot(
            portfolioId: portfolioId,
            assets: const [],
          ),
        );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}
