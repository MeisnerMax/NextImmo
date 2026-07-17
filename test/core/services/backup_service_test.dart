import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/services/backup_service.dart';
import 'package:path/path.dart' as p;

void main() {
  const service = BackupService();
  late Directory root;
  late File dbFile;
  late Directory docsDir;
  late String zipPath;

  setUp(() async {
    root = await Directory(
      p.join(
        Directory.systemTemp.path,
        'neximmo_backup_test_${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create(recursive: true);
    dbFile = File(p.join(root.path, 'app.db'));
    await dbFile.writeAsString('db-content');
    docsDir = await Directory(
      p.join(root.path, 'docs'),
    ).create(recursive: true);
    await File(p.join(docsDir.path, 'a.txt')).writeAsString('document-a');
    await Directory(p.join(docsDir.path, 'nested')).create();
    await File(
      p.join(docsDir.path, 'nested', 'b.txt'),
    ).writeAsString('document-b');
    zipPath = p.join(root.path, 'backup.zip');
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test('creates and restores a valid format 2 archive', () async {
    final manifest = await _createBackup(service, dbFile, docsDir, zipPath);
    await _createBackup(service, dbFile, docsDir, zipPath);

    expect(manifest.formatVersion, BackupManifest.currentFormatVersion);
    expect(manifest.createdAt, 1234);
    expect(manifest.dbSchemaVersion, 5);
    expect(manifest.docsFileCount, 2);
    expect(
      manifest.payloadSha256.keys,
      containsAll(<String>[
        BackupManifest.databaseEntry,
        'docs/a.txt',
        'docs/nested/b.txt',
      ]),
    );
    expect(
      manifest.dbSha256,
      sha256.convert(utf8.encode('db-content')).toString(),
    );
    expect(
      Directory(root.path).listSync().whereType<File>().where(
        (file) => p.basename(file.path).startsWith('backup.zip.tmp.'),
      ),
      isEmpty,
    );

    final loaded = await service.readManifest(zipPath);
    expect(loaded.formatVersion, BackupManifest.currentFormatVersion);
    expect(loaded.payloadSha256, manifest.payloadSha256);

    await File(p.join(docsDir.path, 'a.txt')).writeAsString('changed');
    var callbackCount = 0;
    await service.restoreFromBackup(
      zipPath: zipPath,
      docsDirectoryPath: docsDir.path,
      tempDirectoryPath: p.join(root.path, 'restore-temp'),
      restoreDbFromFile: (extractedDbFile) async {
        callbackCount++;
        expect(await extractedDbFile.readAsString(), 'db-content');
      },
    );

    expect(callbackCount, 1);
    expect(
      await File(p.join(docsDir.path, 'a.txt')).readAsString(),
      'document-a',
    );
    expect(
      await File(p.join(docsDir.path, 'nested', 'b.txt')).readAsString(),
      'document-b',
    );
  });

  test('rejects a manipulated database hash before callback', () async {
    await _createBackup(service, dbFile, docsDir, zipPath);
    await _rewriteArchive(zipPath, (name, bytes) {
      return name == BackupManifest.databaseEntry
          ? utf8.encode('tampered-db')
          : bytes;
    });

    await _expectRejectedRestore(service, root, docsDir, zipPath);
  });

  test('rejects a manipulated document hash before callback', () async {
    await _createBackup(service, dbFile, docsDir, zipPath);
    await _rewriteArchive(zipPath, (name, bytes) {
      return name == 'docs/a.txt' ? utf8.encode('tampered-doc') : bytes;
    });

    await _expectRejectedRestore(service, root, docsDir, zipPath);
  });

  test('rejects a missing database entry before callback', () async {
    await _createBackup(service, dbFile, docsDir, zipPath);
    await _rewriteArchive(
      zipPath,
      (name, bytes) => bytes,
      include: (name) => name != BackupManifest.databaseEntry,
    );

    await _expectRejectedRestore(service, root, docsDir, zipPath);
  });

  test('rejects a mismatched document count before callback', () async {
    await _createBackup(service, dbFile, docsDir, zipPath);
    await _rewriteManifest(zipPath, (manifest) {
      manifest['docs_file_count'] = 99;
    });

    await _expectRejectedRestore(service, root, docsDir, zipPath);
  });

  test('rejects duplicate and unexpected entries before callback', () async {
    final manifest = await _createBackup(service, dbFile, docsDir, zipPath);
    final entries = await _readEntries(zipPath);

    await _writeRawEntries(zipPath, <MapEntry<String, List<int>>>[
      ...entries.entries,
      MapEntry<String, List<int>>(
        BackupManifest.databaseEntry,
        utf8.encode('duplicate'),
      ),
    ]);
    await _expectRejectedRestore(service, root, docsDir, zipPath);

    await _writeRawEntries(zipPath, <MapEntry<String, List<int>>>[
      MapEntry(BackupManifest.databaseEntry, utf8.encode('db-content')),
      MapEntry(
        BackupManifest.manifestEntry,
        utf8.encode(jsonEncode(manifest.toJson())),
      ),
      MapEntry('other/file.txt', utf8.encode('unexpected')),
    ]);
    await _expectRejectedRestore(service, root, docsDir, zipPath);
  });

  for (final unsafePath in <String>[
    r'docs\..\escape.txt',
    '/absolute.txt',
    r'C:\escape.txt',
    'docs//escape.txt',
    'docs/./escape.txt',
    'docs/../escape.txt',
    'docs/nested/../../{outside}',
  ]) {
    test(
      'rejects unsafe archive path "$unsafePath" before extraction',
      () async {
        final dbBytes = utf8.encode('db-content');
        final manifest = BackupManifest(
          formatVersion: BackupManifest.currentFormatVersion,
          createdAt: 1234,
          appVersion: '1.0.0+1',
          dbSchemaVersion: 5,
          workspaceRootRelativePaths: const <String, String>{
            'db': BackupManifest.databaseEntry,
            'docs': 'docs/',
          },
          payloadSha256: <String, String>{
            BackupManifest.databaseEntry: sha256.convert(dbBytes).toString(),
          },
          docsFileCount: 0,
        );
        final outsideName = '${p.basename(root.path)}_outside.txt';
        final effectivePath = unsafePath.replaceAll('{outside}', outsideName);
        await _writeRawEntries(zipPath, <MapEntry<String, List<int>>>[
          MapEntry(BackupManifest.databaseEntry, dbBytes),
          MapEntry(
            BackupManifest.manifestEntry,
            utf8.encode(jsonEncode(manifest.toJson())),
          ),
          MapEntry(effectivePath, utf8.encode('escape')),
        ]);

        final outsideFile = File(p.join(root.parent.path, outsideName));
        expect(outsideFile.existsSync(), isFalse);
        await _expectRejectedRestore(service, root, docsDir, zipPath);
        expect(outsideFile.existsSync(), isFalse);
      },
    );
  }
}

Future<BackupManifest> _createBackup(
  BackupService service,
  File dbFile,
  Directory docsDir,
  String zipPath,
) {
  return service.createBackup(
    dbPath: dbFile.path,
    docsDirectoryPath: docsDir.path,
    destinationZipPath: zipPath,
    dbSchemaVersion: 5,
    appVersion: '1.0.0+1',
    createdAt: 1234,
  );
}

Future<void> _expectRejectedRestore(
  BackupService service,
  Directory root,
  Directory docsDir,
  String zipPath,
) async {
  final sentinel = File(p.join(docsDir.path, 'sentinel.txt'));
  await sentinel.writeAsString('unchanged');
  final tempPath = p.join(root.path, 'restore-temp');
  var callbackCount = 0;

  await expectLater(
    service.restoreFromBackup(
      zipPath: zipPath,
      docsDirectoryPath: docsDir.path,
      tempDirectoryPath: tempPath,
      restoreDbFromFile: (_) async {
        callbackCount++;
      },
    ),
    throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
  );

  expect(callbackCount, 0);
  expect(await sentinel.readAsString(), 'unchanged');
  expect(Directory(tempPath).existsSync(), isFalse);
}

Future<Map<String, List<int>>> _readEntries(String zipPath) async {
  final archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
  return <String, List<int>>{
    for (final entry in archive.files)
      entry.name: List<int>.from(entry.content as List<int>),
  };
}

Future<void> _rewriteArchive(
  String zipPath,
  List<int> Function(String name, List<int> bytes) transform, {
  bool Function(String name)? include,
}) async {
  final entries = await _readEntries(zipPath);
  await _writeRawEntries(
    zipPath,
    entries.entries
        .where((entry) => include?.call(entry.key) ?? true)
        .map((entry) => MapEntry(entry.key, transform(entry.key, entry.value)))
        .toList(),
  );
}

Future<void> _rewriteManifest(
  String zipPath,
  void Function(Map<String, dynamic> manifest) mutate,
) async {
  await _rewriteArchive(zipPath, (name, bytes) {
    if (name != BackupManifest.manifestEntry) {
      return bytes;
    }
    final manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    mutate(manifest);
    return utf8.encode(jsonEncode(manifest));
  });
}

Future<void> _writeRawEntries(
  String zipPath,
  List<MapEntry<String, List<int>>> entries,
) async {
  final output = OutputStream();
  final encoder = ZipEncoder();
  encoder.startEncode(output);
  for (final entry in entries) {
    final archiveFile =
        ArchiveFile('', entry.value.length, entry.value)
          ..name = entry.key
          ..lastModTime = 0
          ..mode = 0x1A4;
    encoder.addFile(archiveFile, autoClose: false);
  }
  encoder.endEncode();
  await File(zipPath).writeAsBytes(output.getBytes(), flush: true);
}
