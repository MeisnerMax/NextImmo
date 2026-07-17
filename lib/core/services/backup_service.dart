import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class BackupManifest {
  const BackupManifest({
    required this.formatVersion,
    required this.createdAt,
    required this.appVersion,
    required this.dbSchemaVersion,
    required this.workspaceRootRelativePaths,
    required this.payloadSha256,
    required this.docsFileCount,
  });

  static const int currentFormatVersion = 2;
  static const String databaseEntry = 'data/app.db';
  static const String manifestEntry = 'meta/manifest.json';

  final int formatVersion;
  final int createdAt;
  final String appVersion;
  final int dbSchemaVersion;
  final Map<String, String> workspaceRootRelativePaths;
  final Map<String, String> payloadSha256;
  final int docsFileCount;

  String get dbSha256 => payloadSha256[databaseEntry]!;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'format_version': formatVersion,
      'created_at': createdAt,
      'app_version': appVersion,
      'db_schema_version': dbSchemaVersion,
      'workspace_root_relative_paths': workspaceRootRelativePaths,
      'payload_sha256': payloadSha256,
      'docs_file_count': docsFileCount,
    };
  }

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    const expectedKeys = <String>{
      'format_version',
      'created_at',
      'app_version',
      'db_schema_version',
      'workspace_root_relative_paths',
      'payload_sha256',
      'docs_file_count',
    };
    if (json.length != expectedKeys.length ||
        !json.keys.every(expectedKeys.contains)) {
      throw const FormatException('Backup manifest has invalid fields.');
    }

    final formatVersion = _requiredInt(json, 'format_version');
    if (formatVersion != currentFormatVersion) {
      throw FormatException(
        'Unsupported backup format version: $formatVersion.',
      );
    }

    final appVersion = json['app_version'];
    if (appVersion is! String || appVersion.isEmpty) {
      throw const FormatException('Backup app version is invalid.');
    }

    final workspacePaths = _requiredStringMap(
      json,
      'workspace_root_relative_paths',
    );
    if (workspacePaths.length != 2 ||
        workspacePaths['db'] != databaseEntry ||
        workspacePaths['docs'] != 'docs/') {
      throw const FormatException('Backup workspace paths are invalid.');
    }

    final payloadHashes = _requiredStringMap(json, 'payload_sha256');
    final hashPattern = RegExp(r'^[0-9a-f]{64}$');
    if (payloadHashes.isEmpty ||
        !payloadHashes.values.every(hashPattern.hasMatch)) {
      throw const FormatException('Backup payload hashes are invalid.');
    }

    final createdAt = _requiredInt(json, 'created_at');
    final dbSchemaVersion = _requiredInt(json, 'db_schema_version');
    final docsFileCount = _requiredInt(json, 'docs_file_count');
    if (createdAt < 0 || dbSchemaVersion < 0 || docsFileCount < 0) {
      throw const FormatException('Backup manifest contains invalid numbers.');
    }

    return BackupManifest(
      formatVersion: formatVersion,
      createdAt: createdAt,
      appVersion: appVersion,
      dbSchemaVersion: dbSchemaVersion,
      workspaceRootRelativePaths: workspacePaths,
      payloadSha256: payloadHashes,
      docsFileCount: docsFileCount,
    );
  }

  static int _requiredInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('Backup manifest field "$key" is invalid.');
    }
    return value;
  }

  static Map<String, String> _requiredStringMap(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value is! Map<String, dynamic> ||
        !value.values.every((item) => item is String)) {
      throw FormatException('Backup manifest field "$key" is invalid.');
    }
    return value.map((mapKey, item) => MapEntry(mapKey, item as String));
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
    _validateDirectoryPath(File(dbPath).parent.path);
    _validateDirectoryPath(docsDirectoryPath);
    if (FileSystemEntity.typeSync(dbPath, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Database file must not be a symbolic link: $dbPath');
    }
    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      throw StateError('Database file not found: $dbPath');
    }

    final dbBytes = await dbFile.readAsBytes();
    final docsDirectory = Directory(docsDirectoryPath);
    if (!docsDirectory.existsSync()) {
      await docsDirectory.create(recursive: true);
    }

    final docsEntities = docsDirectory.listSync(
      recursive: true,
      followLinks: false,
    );
    if (docsEntities.any((entity) => entity is Link)) {
      throw StateError('Documents directory must not contain symbolic links.');
    }
    final docsFiles =
        docsEntities.whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final archive = Archive();
    final payloadHashes = <String, String>{
      BackupManifest.databaseEntry: sha256.convert(dbBytes).toString(),
    };
    archive.addFile(_archiveFile(BackupManifest.databaseEntry, dbBytes));

    for (final file in docsFiles) {
      final relativePath = p.relative(file.path, from: docsDirectory.path);
      final normalized = p.posix.joinAll(p.split(relativePath));
      final archivePath = 'docs/$normalized';
      _validateArchivePath(archivePath);
      final bytes = await file.readAsBytes();
      payloadHashes[archivePath] = sha256.convert(bytes).toString();
      archive.addFile(_archiveFile(archivePath, bytes));
    }

    final manifest = BackupManifest(
      formatVersion: BackupManifest.currentFormatVersion,
      createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
      appVersion: appVersion,
      dbSchemaVersion: dbSchemaVersion,
      workspaceRootRelativePaths: const <String, String>{
        'db': BackupManifest.databaseEntry,
        'docs': 'docs/',
      },
      payloadSha256: payloadHashes,
      docsFileCount: docsFiles.length,
    );

    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );
    archive.addFile(_archiveFile(BackupManifest.manifestEntry, manifestBytes));

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('Failed to encode backup archive.');
    }

    final destination = File(destinationZipPath);
    _validateDirectoryPath(destination.parent.path);
    if (FileSystemEntity.typeSync(destination.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Backup destination must not be a symbolic link.');
    }
    await destination.parent.create(recursive: true);
    final temporary = File(
      '$destinationZipPath.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsBytes(encoded, flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (temporary.existsSync()) {
        await temporary.delete();
      }
    }
    return manifest;
  }

  Future<BackupManifest> readManifest(String zipPath) async {
    final file = File(zipPath);
    if (!file.existsSync()) {
      throw StateError('Backup zip not found: $zipPath');
    }
    return _decodeAndValidate(await file.readAsBytes()).manifest;
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

    final validated = _decodeAndValidate(await file.readAsBytes());
    _validateDirectoryPath(tempDirectoryPath);
    _validateDirectoryPath(docsDirectoryPath);

    final tempRoot = Directory(p.normalize(p.absolute(tempDirectoryPath)));
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
    await tempRoot.create(recursive: true);

    final extractedFiles = <String, File>{};
    for (final entry in validated.payloadEntries.entries) {
      final outputPath = _containedPath(tempRoot.path, entry.key);
      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(entry.value, flush: true);
      extractedFiles[entry.key] = outputFile;
    }

    await restoreDbFromFile(extractedFiles[BackupManifest.databaseEntry]!);

    _validateDirectoryPath(docsDirectoryPath);
    final docsTarget = Directory(p.normalize(p.absolute(docsDirectoryPath)));
    if (docsTarget.existsSync()) {
      await docsTarget.delete(recursive: true);
    }
    await docsTarget.create(recursive: true);
    for (final entry in validated.payloadEntries.entries) {
      if (!entry.key.startsWith('docs/')) {
        continue;
      }
      final relativePath = entry.key.substring('docs/'.length);
      final destinationPath = _containedPath(docsTarget.path, relativePath);
      final destination = File(destinationPath);
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(entry.value, flush: true);
    }
  }

  static ArchiveFile _archiveFile(String name, List<int> bytes) {
    return ArchiveFile(name, bytes.length, bytes)
      ..lastModTime = 0
      ..mode = 0x1A4;
  }

  static _ValidatedBackup _decodeAndValidate(List<int> bytes) {
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(bytes, verify: true);
    final names = decoder.directory.fileHeaders
        .map((header) => header.filename)
        .toList(growable: false);

    final uniqueNames = <String>{};
    for (final name in names) {
      _validateArchivePath(name);
      if (!uniqueNames.add(name)) {
        throw FormatException('Duplicate backup entry: $name');
      }
    }
    if (archive.files.length != names.length) {
      throw const FormatException('Backup contains duplicate entries.');
    }

    final entries = <String, List<int>>{};
    for (final name in names) {
      final entry = archive.findFile(name);
      if (entry == null || !entry.isFile || entry.isSymbolicLink) {
        throw FormatException('Backup entry is not a regular file: $name');
      }
      final content = entry.content;
      if (content is! List<int>) {
        throw FormatException('Backup entry content is invalid: $name');
      }
      entries[name] = content;
    }

    final manifestBytes = entries[BackupManifest.manifestEntry];
    if (manifestBytes == null) {
      throw const FormatException('Backup manifest is missing.');
    }
    final decodedManifest = jsonDecode(utf8.decode(manifestBytes));
    if (decodedManifest is! Map<String, dynamic>) {
      throw const FormatException('Backup manifest is invalid.');
    }
    final manifest = BackupManifest.fromJson(decodedManifest);

    final payloadEntries = <String, List<int>>{
      for (final entry in entries.entries)
        if (entry.key != BackupManifest.manifestEntry) entry.key: entry.value,
    };
    if (!payloadEntries.containsKey(BackupManifest.databaseEntry)) {
      throw const FormatException('Backup database file is missing.');
    }
    final documentCount =
        payloadEntries.keys.where((name) => name.startsWith('docs/')).length;
    if (documentCount != manifest.docsFileCount) {
      throw const FormatException('Backup document count does not match.');
    }
    if (manifest.payloadSha256.length != payloadEntries.length ||
        !manifest.payloadSha256.keys.every(payloadEntries.containsKey)) {
      throw const FormatException('Backup payload manifest does not match.');
    }
    for (final entry in payloadEntries.entries) {
      final actualHash = sha256.convert(entry.value).toString();
      if (manifest.payloadSha256[entry.key] != actualHash) {
        throw FormatException(
          'Backup payload hash does not match: ${entry.key}',
        );
      }
    }

    return _ValidatedBackup(manifest, payloadEntries);
  }

  static void _validateArchivePath(String name) {
    if (name.isEmpty ||
        name.contains(r'\') ||
        name.contains('\u0000') ||
        name.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name) ||
        p.posix.isAbsolute(name) ||
        p.windows.isAbsolute(name)) {
      throw FormatException('Unsafe backup entry path: $name');
    }
    final segments = name.split('/');
    if (segments.any(
      (segment) =>
          segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.contains(':'),
    )) {
      throw FormatException('Unsafe backup entry path: $name');
    }
    if (name != BackupManifest.manifestEntry &&
        name != BackupManifest.databaseEntry &&
        !name.startsWith('docs/')) {
      throw FormatException('Unexpected backup entry: $name');
    }
  }

  static String _containedPath(String rootPath, String relativePath) {
    final root = p.normalize(p.absolute(rootPath));
    final candidate = p.normalize(
      p.join(root, p.joinAll(p.posix.split(relativePath))),
    );
    if (!p.isWithin(root, candidate)) {
      throw FormatException(
        'Backup entry escapes extraction root: $relativePath',
      );
    }
    return candidate;
  }

  static void _validateDirectoryPath(String path) {
    final absolute = p.normalize(p.absolute(path));
    final root = p.rootPrefix(absolute);
    final segments = p.split(p.relative(absolute, from: root));
    var current = root;
    for (var index = 0; index < segments.length; index++) {
      current = p.join(current, segments[index]);
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw StateError('Extraction path must not contain symbolic links.');
      }
      if (type == FileSystemEntityType.file ||
          (index < segments.length - 1 &&
              type != FileSystemEntityType.directory &&
              type != FileSystemEntityType.notFound)) {
        throw StateError('Extraction path is not a directory: $path');
      }
    }
  }
}

class _ValidatedBackup {
  const _ValidatedBackup(this.manifest, this.payloadEntries);

  final BackupManifest manifest;
  final Map<String, List<int>> payloadEntries;
}
