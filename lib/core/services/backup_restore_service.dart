import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/repositories/inputs_repo.dart';
import '../../data/repositories/search_repo.dart';
import '../../data/repositories/workspace_repo.dart';
import '../models/settings.dart';
import 'backup_service.dart';

class BackupCreateResult {
  const BackupCreateResult({
    required this.updatedSettings,
    required this.destinationZipPath,
    required this.manifest,
  });

  final AppSettingsRecord updatedSettings;
  final String destinationZipPath;
  final BackupManifest manifest;
}

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.sourceZipPath,
    required this.preRestoreBackupPath,
  });

  final String sourceZipPath;
  final String preRestoreBackupPath;
}

class BackupRestoreService {
  const BackupRestoreService({
    required BackupService backupService,
    required WorkspaceRepository workspaceRepository,
    required InputsRepository inputsRepository,
    required SearchRepo searchRepository,
    required Database database,
    required int dbSchemaVersion,
    required String appVersion,
  }) : _backupService = backupService,
       _workspaceRepository = workspaceRepository,
       _inputsRepository = inputsRepository,
       _searchRepository = searchRepository,
       _database = database,
       _dbSchemaVersion = dbSchemaVersion,
       _appVersion = appVersion;

  final BackupService _backupService;
  final WorkspaceRepository _workspaceRepository;
  final InputsRepository _inputsRepository;
  final SearchRepo _searchRepository;
  final Database _database;
  final int _dbSchemaVersion;
  final String _appVersion;

  Future<BackupCreateResult> createBackup({
    required AppSettingsRecord settings,
    required String workspaceRootPath,
    required String destinationZipPath,
  }) async {
    final effectiveSettings = settings.copyWith(
      workspaceRootPath:
          workspaceRootPath.trim().isEmpty ? null : workspaceRootPath.trim(),
    );
    final workspace = await _workspaceRepository.resolvePaths(
      effectiveSettings,
    );
    final manifest = await _backupService.createBackup(
      dbPath: workspace.dbPath,
      docsDirectoryPath: workspace.docsPath,
      destinationZipPath: destinationZipPath,
      dbSchemaVersion: _dbSchemaVersion,
      appVersion: _appVersion,
    );
    final updated = settings.copyWith(
      workspaceRootPath: workspace.rootPath,
      lastBackupAt: manifest.createdAt,
      lastBackupPath: destinationZipPath,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _inputsRepository.updateSettings(updated);
    return BackupCreateResult(
      updatedSettings: updated,
      destinationZipPath: destinationZipPath,
      manifest: manifest,
    );
  }

  Future<BackupRestoreResult> restoreBackup({
    required AppSettingsRecord settings,
    required String workspaceRootPath,
    required String sourceZipPath,
    required String Function(int backupSchemaVersion, int currentSchemaVersion)
    newerSchemaMessage,
  }) async {
    final effectiveSettings = settings.copyWith(
      workspaceRootPath:
          workspaceRootPath.trim().isEmpty ? null : workspaceRootPath.trim(),
    );
    final workspace = await _workspaceRepository.resolvePaths(
      effectiveSettings,
    );
    final manifest = await _backupService.readManifest(sourceZipPath);
    if (manifest.dbSchemaVersion > _dbSchemaVersion) {
      throw StateError(
        newerSchemaMessage(manifest.dbSchemaVersion, _dbSchemaVersion),
      );
    }

    final preRestorePath = p.join(
      workspace.backupsPath,
      'pre_restore_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    await _backupService.createBackup(
      dbPath: workspace.dbPath,
      docsDirectoryPath: workspace.docsPath,
      destinationZipPath: preRestorePath,
      dbSchemaVersion: _dbSchemaVersion,
      appVersion: _appVersion,
    );

    await _backupService.restoreFromBackup(
      zipPath: sourceZipPath,
      docsDirectoryPath: workspace.docsPath,
      tempDirectoryPath: workspace.tempPath,
      restoreDbFromFile: (extractedDbFile) async {
        final backupDb = await databaseFactoryFfi.openDatabase(
          extractedDbFile.path,
          options: OpenDatabaseOptions(readOnly: true),
        );
        try {
          await _restoreDatabaseData(
            currentDb: _database,
            backupDb: backupDb,
          );
        } finally {
          await backupDb.close();
        }
      },
    );

    await _searchRepository.rebuildIndex();
    return BackupRestoreResult(
      sourceZipPath: sourceZipPath,
      preRestoreBackupPath: preRestorePath,
    );
  }

  Future<void> _restoreDatabaseData({
    required Database currentDb,
    required Database backupDb,
  }) async {
    final currentTables = await currentDb.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final backupTables = await backupDb.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final backupTableNames =
        backupTables.map((row) => row['name'] as String).toSet();

    await currentDb.transaction((txn) async {
      await txn.execute('PRAGMA foreign_keys = OFF');
      for (final row in currentTables) {
        final table = row['name'] as String;
        if (table == 'android_metadata') {
          continue;
        }
        if (!backupTableNames.contains(table)) {
          await txn.delete(table);
          continue;
        }
        final currentCols =
            (await txn.rawQuery(
              'PRAGMA table_info($table)',
            )).map((c) => c['name'] as String).toSet();
        final backupCols =
            (await backupDb.rawQuery(
              'PRAGMA table_info($table)',
            )).map((c) => c['name'] as String).toSet();
        final commonCols =
            currentCols
                .where((c) => backupCols.contains(c))
                .toList(growable: false);
        await txn.delete(table);
        if (commonCols.isEmpty) {
          continue;
        }
        final backupRows = await backupDb.query(table, columns: commonCols);
        for (final backupRow in backupRows) {
          final map = <String, Object?>{
            for (final col in commonCols) col: backupRow[col],
          };
          await txn.insert(
            table,
            map,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await txn.execute('PRAGMA foreign_keys = ON');
    });
  }
}
