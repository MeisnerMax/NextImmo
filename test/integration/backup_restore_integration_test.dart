import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/services/backup_service.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/data/sqlite/migrations.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('backup then restore returns db data and docs', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final root = await Directory(
      p.join(
        Directory.systemTemp.path,
        'neximmo_backup_restore_${DateTime.now().millisecondsSinceEpoch}',
      ),
    ).create(recursive: true);
    final dbPath = p.join(root.path, 'app_data.db');
    final docsPath = p.join(root.path, 'docs');
    await Directory(docsPath).create(recursive: true);
    await File(p.join(docsPath, 'a.txt')).writeAsString('original-doc');

    final appDatabase = AppDatabase(overridePath: dbPath);
    final db = await appDatabase.instance;
    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Restore Asset',
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

    const backupService = BackupService();
    final backupZip = p.join(root.path, 'backup.zip');
    await backupService.createBackup(
      dbPath: dbPath,
      docsDirectoryPath: docsPath,
      destinationZipPath: backupZip,
      dbSchemaVersion: DbMigrations.currentVersion,
      appVersion: '1.0.0+1',
    );

    await db.delete('properties');
    await File(p.join(docsPath, 'a.txt')).writeAsString('mutated-doc');
    await appDatabase.close();

    await backupService.restoreFromBackup(
      zipPath: backupZip,
      docsDirectoryPath: docsPath,
      tempDirectoryPath: p.join(root.path, 'tmp'),
      restoreDbFromFile: (extractedDbFile) async {
        await File(dbPath).writeAsBytes(await extractedDbFile.readAsBytes());
      },
    );

    final restoredDb = await appDatabase.instance;
    final properties = await restoredDb.query('properties');
    expect(properties.length, 1);
    expect(properties.first['name'], 'Restore Asset');
    final docText = await File(p.join(docsPath, 'a.txt')).readAsString();
    expect(docText, 'original-doc');

    await appDatabase.close();
    await root.delete(recursive: true);
  });
}
