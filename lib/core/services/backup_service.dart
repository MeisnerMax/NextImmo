import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class BackupManifest {
  const BackupManifest({
    required this.createdAt,
    required this.appVersion,
    required this.dbSchemaVersion,
    required this.workspaceRootRelativePaths,
    required this.dbSha256,
    required this.docsFileCount,
  });

  final int createdAt;
  final String appVersion;
  final int dbSchemaVersion;
  final Map<String, String> workspaceRootRelativePaths;
  final String dbSha256;
  final int docsFileCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'created_at': createdAt,
      'app_version': appVersion,
      'db_schema_version': dbSchemaVersion,
      'workspace_root_relative_paths': workspaceRootRelativePaths,
      'db_sha256': dbSha256,
      'docs_file_count': docsFileCount,
    };
  }

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    return BackupManifest(
      createdAt: (json['created_at'] as num).toInt(),
      appVersion: json['app_version']! as String,
      dbSchemaVersion: (json['db_schema_version'] as num).toInt(),
      workspaceRootRelativePaths: (json['workspace_root_relative_paths']
              as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value.toString())),
      dbSha256: json['db_sha256']! as String,
      docsFileCount: (json['docs_file_count'] as num).toInt(),
    );
  }
}

class BackupService {
  const BackupService();

  Future<BackupManifest> createBackup({
    required String dbPath,
    required String docsDirectoryPath,
    required String destinationZipPath,
    required int dbSchemaVersion,
    required String appVersion,
    int? createdAt,
  }) async {
    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      throw StateError('Database file not found: $dbPath');
    }

    final dbBytes = await dbFile.readAsBytes();
    final docsDirectory = Directory(docsDirectoryPath);
    if (!docsDirectory.existsSync()) {
      await docsDirectory.create(recursive: true);
    }

    final docsFiles =
        docsDirectory.listSync(recursive: true).whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final manifest = BackupManifest(
      createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
      appVersion: appVersion,
      dbSchemaVersion: dbSchemaVersion,
      workspaceRootRelativePaths: const <String, String>{
        'db': 'db/app_data.db',
        'docs': 'docs/',
      },
      dbSha256: sha256.convert(dbBytes).toString(),
      docsFileCount: docsFiles.length,
    );

    final archive = Archive();
    archive.addFile(
      ArchiveFile('db/app_data.db', dbBytes.length, dbBytes)
        ..lastModTime = 0
        ..mode = 0x1A4,
    );

    for (final file in docsFiles) {
      final relativePath = p.relative(file.path, from: docsDirectory.path);
      final normalized = p.posix.joinAll(p.split(relativePath));
      final bytes = await file.readAsBytes();
      archive.addFile(
        ArchiveFile('docs/$normalized', bytes.length, bytes)
          ..lastModTime = 0
          ..mode = 0x1A4,
      );
    }

    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );
    archive.addFile(
      ArchiveFile('meta/manifest.json', manifestBytes.length, manifestBytes)
        ..lastModTime = 0
        ..mode = 0x1A4,
    );

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('Failed to encode backup archive.');
    }
    final destination = File(destinationZipPath);
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(encoded, flush: true);
    return manifest;
  }

  Future<BackupManifest> readManifest(String zipPath) async {
    final file = File(zipPath);
    if (!file.existsSync()) {
      throw StateError('Backup zip not found: $zipPath');
    }

    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final manifestEntry = archive.findFile('meta/manifest.json');
    if (manifestEntry == null) {
      throw StateError('Backup manifest is missing.');
    }
    final content = utf8.decode(manifestEntry.content as List<int>);
    final jsonMap = jsonDecode(content) as Map<String, Object?>;
    return BackupManifest.fromJson(jsonMap);
  }

  Future<void> restoreFromBackup({
    required String zipPath,
    required String docsDirectoryPath,
    required String tempDirectoryPath,
    required Future<void> Function(File extractedDbFile) restoreDbFromFile,
  }) async {
    final file = File(zipPath);
    if (!file.existsSync()) {
      throw StateError('Backup zip not found: $zipPath');
    }

    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final tempRoot = Directory(tempDirectoryPath);
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
    await tempRoot.create(recursive: true);

    File? extractedDb;
    for (final entry in archive.files) {
      if (!entry.isFile) {
        continue;
      }
      final outPath = p.join(tempRoot.path, entry.name);
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(entry.content as List<int>);
      if (entry.name == 'db/app_data.db') {
        extractedDb = outFile;
      }
    }

    if (extractedDb == null) {
      throw StateError('Backup db file is missing.');
    }

    await restoreDbFromFile(extractedDb);

    final docsTarget = Directory(docsDirectoryPath);
    if (docsTarget.existsSync()) {
      await docsTarget.delete(recursive: true);
    }
    await docsTarget.create(recursive: true);
    final extractedDocs = Directory(p.join(tempRoot.path, 'docs'));
    if (extractedDocs.existsSync()) {
      for (final entity in extractedDocs.listSync(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        final relativePath = p.relative(entity.path, from: extractedDocs.path);
        final destination = File(p.join(docsTarget.path, relativePath));
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(await entity.readAsBytes());
      }
    }
  }
}
