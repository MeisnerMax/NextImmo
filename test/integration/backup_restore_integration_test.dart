import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/core/services/backup_restore_service.dart';
import 'package:neximmo_app/core/services/backup_service.dart';
import 'package:neximmo_app/data/repositories/inputs_repo.dart';
import 'package:neximmo_app/data/repositories/search_repo.dart';
import 'package:neximmo_app/data/repositories/workspace_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/data/sqlite/migrations.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('GM-BKP-001 restores identical rows and document bytes', () async {
    final fixture = await _Fixture.create('gm_bkp_001');
    try {
      await _insertProperty(fixture.db, id: 'p1', name: 'Backup Asset');
      await File(
        p.join(fixture.docsPath, 'nested', 'binary.dat'),
      ).create(recursive: true);
      await File(
        p.join(fixture.docsPath, 'nested', 'binary.dat'),
      ).writeAsBytes(<int>[0, 1, 2, 127, 128, 255]);
      await File(
        p.join(fixture.docsPath, 'a.txt'),
      ).writeAsString('original-doc');
      final expectedRows = await fixture.db.query('properties', orderBy: 'id');
      final expectedDocs = await _readDocuments(fixture.docsPath);

      final backupZip = p.join(fixture.root.path, 'backup.zip');
      await fixture.backupService.createBackup(
        dbPath: fixture.dbPath,
        docsDirectoryPath: fixture.docsPath,
        destinationZipPath: backupZip,
        dbSchemaVersion: DbMigrations.currentVersion,
        appVersion: '1.0.0+1',
      );

      await fixture.db.delete('properties');
      await _insertProperty(fixture.db, id: 'p2', name: 'Mutated Asset');
      await Directory(fixture.docsPath).delete(recursive: true);
      await Directory(fixture.docsPath).create(recursive: true);
      await File(p.join(fixture.docsPath, 'mutated.txt')).writeAsString('x');

      await fixture.service().restoreBackup(
        settings: fixture.settings,
        workspaceRootPath: fixture.workspacePath,
        sourceZipPath: backupZip,
        newerSchemaMessage: _schemaMessage,
      );

      expect(await fixture.db.query('properties', orderBy: 'id'), expectedRows);
      final restoredDocs = await _readDocuments(fixture.docsPath);
      expect(restoredDocs.keys, unorderedEquals(expectedDocs.keys));
      for (final path in expectedDocs.keys) {
        expect(restoredDocs[path], orderedEquals(expectedDocs[path]!));
      }
    } finally {
      await fixture.dispose();
    }
  });

  test(
    'GM-BKP-002 rejects incompatible sources and rolls back after mutation',
    () async {
      final fixture = await _Fixture.create('gm_bkp_002');
      try {
        await _insertProperty(fixture.db, id: 'source', name: 'Source Asset');
        await File(
          p.join(fixture.docsPath, 'source.bin'),
        ).writeAsBytes(<int>[10, 20, 30]);
        final validBackup = p.join(fixture.root.path, 'valid.zip');
        await fixture.backupService.createBackup(
          dbPath: fixture.dbPath,
          docsDirectoryPath: fixture.docsPath,
          destinationZipPath: validBackup,
          dbSchemaVersion: DbMigrations.currentVersion,
          appVersion: '1.0.0+1',
        );

        await fixture.db.delete('properties');
        await _insertProperty(fixture.db, id: 'current', name: 'Current Asset');
        await Directory(fixture.docsPath).delete(recursive: true);
        await Directory(fixture.docsPath).create(recursive: true);
        await File(
          p.join(fixture.docsPath, 'current.bin'),
        ).writeAsBytes(<int>[255, 0, 127, 64]);
        await fixture.db.insert('search_index', <String, Object?>{
          'id': 'rollback-marker',
          'entity_type': 'test',
          'entity_id': 'current',
          'title': 'Rollback marker',
          'subtitle': null,
          'body': 'must survive rollback',
          'updated_at': 2,
        });
        final expectedRows = await fixture.db.query(
          'properties',
          orderBy: 'id',
        );
        final expectedSearchRows = await fixture.db.query(
          'search_index',
          orderBy: 'id',
        );
        final expectedDocs = await _readDocuments(fixture.docsPath);

        final wrongVersionBackup = p.join(
          fixture.root.path,
          'wrong_version.zip',
        );
        await fixture.backupService.createBackup(
          dbPath: fixture.dbPath,
          docsDirectoryPath: fixture.docsPath,
          destinationZipPath: wrongVersionBackup,
          dbSchemaVersion: DbMigrations.currentVersion - 1,
          appVersion: '1.0.0+1',
        );
        await expectLater(
          fixture.service().restoreBackup(
            settings: fixture.settings,
            workspaceRootPath: fixture.workspacePath,
            sourceZipPath: wrongVersionBackup,
            newerSchemaMessage: _schemaMessage,
          ),
          throwsA(isA<StateError>()),
        );
        await _expectState(
          fixture,
          expectedRows,
          expectedSearchRows,
          expectedDocs,
        );

        final malformedDbPath = p.join(fixture.root.path, 'malformed.db');
        final malformedDb = await databaseFactoryFfi.openDatabase(
          malformedDbPath,
          options: OpenDatabaseOptions(
            version: DbMigrations.currentVersion,
            onCreate: (db, _) async {
              await db.execute('CREATE TABLE properties (id TEXT PRIMARY KEY)');
            },
          ),
        );
        await malformedDb.close();
        final malformedBackup = p.join(fixture.root.path, 'malformed.zip');
        await fixture.backupService.createBackup(
          dbPath: malformedDbPath,
          docsDirectoryPath: fixture.docsPath,
          destinationZipPath: malformedBackup,
          dbSchemaVersion: DbMigrations.currentVersion,
          appVersion: '1.0.0+1',
        );
        await expectLater(
          fixture.service().restoreBackup(
            settings: fixture.settings,
            workspaceRootPath: fixture.workspacePath,
            sourceZipPath: malformedBackup,
            newerSchemaMessage: _schemaMessage,
          ),
          throwsA(isA<FormatException>()),
        );
        await _expectState(
          fixture,
          expectedRows,
          expectedSearchRows,
          expectedDocs,
        );

        await expectLater(
          fixture
              .service(searchRepository: _FailingSearchRepo(fixture.db))
              .restoreBackup(
                settings: fixture.settings,
                workspaceRootPath: fixture.workspacePath,
                sourceZipPath: validBackup,
                newerSchemaMessage: _schemaMessage,
              ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'forced index rebuild failure',
            ),
          ),
        );
        await _expectState(
          fixture,
          expectedRows,
          expectedSearchRows,
          expectedDocs,
        );
      } finally {
        await fixture.dispose();
      }
    },
  );
}

String _schemaMessage(int backupVersion, int currentVersion) {
  return 'Schema $backupVersion is newer than $currentVersion.';
}

Future<void> _insertProperty(
  Database db, {
  required String id,
  required String name,
}) {
  return db.insert('properties', <String, Object?>{
    'id': id,
    'name': name,
    'address_line1': 'Street',
    'address_line2': null,
    'zip': '10115',
    'city': 'Berlin',
    'country': 'DE',
    'property_type': 'single_family',
    'units': 1,
    'sqft': null,
    'year_built': null,
    'notes': null,
    'created_at': 1,
    'updated_at': 1,
    'archived': 0,
  });
}

Future<Map<String, List<int>>> _readDocuments(String docsPath) async {
  final result = <String, List<int>>{};
  final directory = Directory(docsPath);
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File) {
      result[p.relative(entity.path, from: docsPath)] =
          await entity.readAsBytes();
    }
  }
  return result;
}

Future<void> _expectState(
  _Fixture fixture,
  List<Map<String, Object?>> expectedRows,
  List<Map<String, Object?>> expectedSearchRows,
  Map<String, List<int>> expectedDocs,
) async {
  expect(await fixture.db.query('properties', orderBy: 'id'), expectedRows);
  expect(
    await fixture.db.query('search_index', orderBy: 'id'),
    expectedSearchRows,
  );
  final actualDocs = await _readDocuments(fixture.docsPath);
  expect(actualDocs.keys, unorderedEquals(expectedDocs.keys));
  for (final path in expectedDocs.keys) {
    expect(actualDocs[path], orderedEquals(expectedDocs[path]!));
  }
}

class _Fixture {
  _Fixture({required this.root, required this.appDatabase, required this.db});

  final Directory root;
  final AppDatabase appDatabase;
  final Database db;
  final BackupService backupService = const BackupService();

  String get dbPath => p.join(root.path, 'app_data.db');
  String get workspacePath => p.join(root.path, 'workspace');
  String get docsPath => p.join(workspacePath, 'docs');
  AppSettingsRecord get settings =>
      AppSettingsRecord(workspaceRootPath: workspacePath, updatedAt: 1);

  static Future<_Fixture> create(String name) async {
    final root = await Directory(
      p.join(
        Directory.systemTemp.path,
        'neximmo_${name}_${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create(recursive: true);
    final appDatabase = AppDatabase(
      overridePath: p.join(root.path, 'app_data.db'),
    );
    final db = await appDatabase.instance;
    await Directory(
      p.join(root.path, 'workspace', 'docs'),
    ).create(recursive: true);
    return _Fixture(root: root, appDatabase: appDatabase, db: db);
  }

  BackupRestoreService service({SearchRepo? searchRepository}) {
    return BackupRestoreService(
      backupService: backupService,
      workspaceRepository: WorkspaceRepository(appDatabase),
      inputsRepository: InputsRepository(db),
      searchRepository: searchRepository ?? SearchRepo(db),
      database: db,
      dbSchemaVersion: DbMigrations.currentVersion,
      appVersion: '1.0.0+1',
    );
  }

  Future<void> dispose() async {
    await appDatabase.close();
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  }
}

class _FailingSearchRepo extends SearchRepo {
  _FailingSearchRepo(super.db);

  @override
  Future<void> rebuildIndex() {
    throw StateError('forced index rebuild failure');
  }
}
