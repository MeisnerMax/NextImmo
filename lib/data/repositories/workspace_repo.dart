import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/models/settings.dart';
import '../sqlite/db.dart';

class WorkspacePaths {
  const WorkspacePaths({
    required this.rootPath,
    required this.docsPath,
    required this.exportsPath,
    required this.backupsPath,
    required this.tempPath,
    required this.dbPath,
  });

  final String rootPath;
  final String docsPath;
  final String exportsPath;
  final String backupsPath;
  final String tempPath;
  final String dbPath;
}

class WorkspaceRepository {
  const WorkspaceRepository(this._database);

  final AppDatabase _database;

  Future<WorkspacePaths> resolvePaths(AppSettingsRecord settings) async {
    final dbPath = await _database.resolvePath();
    final defaultRoot = p.join(p.dirname(dbPath), 'workspace');
    final root =
        (settings.workspaceRootPath ?? '').trim().isEmpty
            ? defaultRoot
            : settings.workspaceRootPath!.trim();
    final docs = p.join(root, 'docs');
    final exports = p.join(docs, 'exports');
    final backups = p.join(root, 'backups');
    final temp = p.join(root, 'tmp');
    await Directory(docs).create(recursive: true);
    await Directory(exports).create(recursive: true);
    await Directory(backups).create(recursive: true);
    await Directory(temp).create(recursive: true);
    return WorkspacePaths(
      rootPath: root,
      docsPath: docs,
      exportsPath: exports,
      backupsPath: backups,
      tempPath: temp,
      dbPath: dbPath,
    );
  }
}
