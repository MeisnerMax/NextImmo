import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/search.dart';
import 'package:neximmo_app/data/repositories/search_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/search_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late _FakeSearchRepo fakeRepo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    fakeRepo = _FakeSearchRepo(db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  testWidgets('live search uses search without rebuildIndex', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'berlin');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(fakeRepo.rebuildCount, 0);
    expect(fakeRepo.ensureCount, 1);
    expect(fakeRepo.searchCount, 1);
    expect(find.text('Berlin Asset'), findsOneWidget);
  });
}

class _FakeSearchRepo extends SearchRepo {
  _FakeSearchRepo(super.db);

  int rebuildCount = 0;
  int ensureCount = 0;
  int searchCount = 0;

  @override
  Future<void> rebuildIndex() async {
    rebuildCount += 1;
  }

  @override
  Future<void> ensureIndexInitialized() async {
    ensureCount += 1;
  }

  @override
  Future<List<SearchIndexRecord>> search({
    required String query,
    List<String>? entityTypes,
    int limit = 30,
  }) async {
    searchCount += 1;
    return <SearchIndexRecord>[
      SearchIndexRecord(
        id: 'result-1',
        entityType: 'property',
        entityId: 'property-1',
        title: 'Berlin Asset',
        subtitle: 'property',
        body: null,
        updatedAt: 1,
      ),
    ];
  }
}
