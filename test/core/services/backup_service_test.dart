import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/services/backup_service.dart';

void main() {
  const service = BackupService();

  test('creates backup manifest with checksum and file count', () async {
    final root = await Directory(
      '${Directory.systemTemp.path}/neximmo_backup_test_${DateTime.now().millisecondsSinceEpoch}',
    ).create(recursive: true);
    final dbFile = File('${root.path}/app_data.db');
    await dbFile.writeAsString('db-content');
    final docsDir = await Directory(
      '${root.path}/docs',
    ).create(recursive: true);
    await File('${docsDir.path}/a.txt').writeAsString('a');
    await File('${docsDir.path}/b.txt').writeAsString('b');
    final zipPath = '${root.path}/backup.zip';

    final manifest = await service.createBackup(
      dbPath: dbFile.path,
      docsDirectoryPath: docsDir.path,
      destinationZipPath: zipPath,
      dbSchemaVersion: 5,
      appVersion: '1.0.0+1',
      createdAt: 1234,
    );

    expect(File(zipPath).existsSync(), isTrue);
    expect(manifest.createdAt, 1234);
    expect(manifest.dbSchemaVersion, 5);
    expect(manifest.docsFileCount, 2);
    expect(manifest.dbSha256, isNotEmpty);

    final loaded = await service.readManifest(zipPath);
    expect(loaded.createdAt, 1234);
    expect(loaded.dbSchemaVersion, 5);
    expect(loaded.docsFileCount, 2);

    await root.delete(recursive: true);
  });
}
