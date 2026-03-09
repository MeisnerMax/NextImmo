import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/data/repositories/scenario_version_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late ScenarioVersionRepo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;
    repo = ScenarioVersionRepo(db);

    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Asset',
      'address_line1': 'Main',
      'address_line2': null,
      'zip': '10000',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'multifamily',
      'units': 8,
      'sqft': null,
      'year_built': null,
      'notes': null,
      'created_at': 1,
      'updated_at': 1,
      'archived': 0,
    });
    await db.insert('scenarios', <String, Object?>{
      'id': 's1',
      'property_id': 'p1',
      'name': 'Base',
      'strategy_type': 'hold',
      'is_base': 1,
      'created_at': 1,
      'updated_at': 1,
    });

    final settings = AppSettingsRecord(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final inputs = ScenarioInputs.defaults(
      scenarioId: 's1',
      settings: settings,
    );
    await db.insert('scenario_inputs', inputs.toMap());
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('archives and edits metadata without mutating snapshot blob', () async {
    final saved = await repo.saveVersion(
      scenarioId: 's1',
      label: 'Initial',
      notes: 'first note',
      createdBy: 'tester',
    );

    final detailBefore = await repo.getVersion(saved.id);
    expect(detailBefore, isNotNull);

    await repo.setArchived(versionId: saved.id, archived: true);
    await repo.updateVersionMetadata(
      versionId: saved.id,
      label: 'Renamed',
      notes: 'updated note',
    );

    final versions = await repo.listVersions('s1');
    expect(versions, hasLength(1));
    expect(versions.first.label, 'Renamed');
    expect(versions.first.notes, 'updated note');
    expect(versions.first.archived, isTrue);

    await repo.setArchived(versionId: saved.id, archived: false);
    final unarchived = (await repo.listVersions('s1')).first;
    expect(unarchived.archived, isFalse);
    expect(unarchived.notes, 'updated note');

    final detailAfter = await repo.getVersion(saved.id);
    expect(detailAfter, isNotNull);
    expect(detailAfter!.blob.snapshotJson, detailBefore!.blob.snapshotJson);
  });
}
