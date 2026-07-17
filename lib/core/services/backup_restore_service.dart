import 'dart:io';

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
    if (manifest.formatVersion != BackupManifest.currentFormatVersion) {
      throw StateError(
        'Backup format ${manifest.formatVersion} is not supported.',
      );
    }
    if (manifest.dbSchemaVersion != _dbSchemaVersion) {
      if (manifest.dbSchemaVersion < _dbSchemaVersion) {
        throw StateError(
          'Backup database schema ${manifest.dbSchemaVersion} does not match '
          'current schema $_dbSchemaVersion.',
        );
      }
      throw StateError(
        newerSchemaMessage(manifest.dbSchemaVersion, _dbSchemaVersion),
      );
    }

    final rollbackRoot = Directory(
      p.join(
        workspace.tempPath,
        'restore_rollback_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final rollbackDbPath = p.join(rollbackRoot.path, 'app.db');
    final rollbackDocsPath = p.join(rollbackRoot.path, 'docs');
    final preRestorePath = p.join(
      workspace.backupsPath,
      'pre_restore_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    Object? primaryError;
    await rollbackRoot.create(recursive: true);
    try {
      await _createDatabaseSnapshot(rollbackDbPath);
      await _copyDirectory(
        Directory(workspace.docsPath),
        Directory(rollbackDocsPath),
      );
      await _backupService.createBackup(
        dbPath: rollbackDbPath,
        docsDirectoryPath: rollbackDocsPath,
        destinationZipPath: preRestorePath,
        dbSchemaVersion: _dbSchemaVersion,
        appVersion: _appVersion,
      );

      try {
        await _backupService.restoreFromBackup(
          zipPath: sourceZipPath,
          docsDirectoryPath: workspace.docsPath,
          tempDirectoryPath: p.join(rollbackRoot.path, 'extracted'),
          restoreDbFromFile: (extractedDbFile) async {
            final backupDb = await databaseFactoryFfi.openDatabase(
              extractedDbFile.path,
              options: OpenDatabaseOptions(readOnly: true),
            );
            try {
              await _validateRestoreDatabase(backupDb);
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
      } catch (error, stackTrace) {
        await _rollbackBestEffort(
          rollbackDbPath: rollbackDbPath,
          rollbackDocsPath: rollbackDocsPath,
          docsTargetPath: workspace.docsPath,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }

      return BackupRestoreResult(
        sourceZipPath: sourceZipPath,
        preRestoreBackupPath: preRestorePath,
      );
    } catch (error) {
      primaryError = error;
      rethrow;
    } finally {
      try {
        if (rollbackRoot.existsSync()) {
          await rollbackRoot.delete(recursive: true);
        }
      } catch (error, stackTrace) {
        if (primaryError == null) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
    }
  }

  Future<void> _createDatabaseSnapshot(String destinationPath) async {
    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    await _database.execute(
      "VACUUM INTO '${destination.path.replaceAll("'", "''")}'",
    );
  }

  Future<void> _validateRestoreDatabase(Database backupDb) async {
    final integrityRows = await backupDb.rawQuery('PRAGMA integrity_check');
    if (integrityRows.length != 1 ||
        integrityRows.single.values.single.toString().toLowerCase() != 'ok') {
      throw const FormatException('Backup database integrity check failed.');
    }

    final versionRows = await backupDb.rawQuery('PRAGMA user_version');
    final backupVersion = (versionRows.single.values.single as num).toInt();
    if (backupVersion != _dbSchemaVersion) {
      throw FormatException(
        'Backup database schema $backupVersion does not match current schema '
        '$_dbSchemaVersion.',
      );
    }

    final currentTables = await _tableNames(_database);
    final backupTables = await _tableNames(backupDb);
    if (currentTables.length != backupTables.length ||
        !currentTables.toSet().containsAll(backupTables)) {
      throw const FormatException(
        'Backup database tables do not match the current schema.',
      );
    }
    for (final table in currentTables) {
      final currentColumns = await _tableColumns(_database, table);
      final backupColumns = await _tableColumns(backupDb, table);
      if (currentColumns.length != backupColumns.length) {
        throw FormatException(
          'Backup database table "$table" has incompatible columns.',
        );
      }
      for (var index = 0; index < currentColumns.length; index++) {
        if (!_sameColumn(currentColumns[index], backupColumns[index])) {
          throw FormatException(
            'Backup database table "$table" has incompatible columns.',
          );
        }
      }
    }
  }

  Future<void> _rollbackBestEffort({
    required String rollbackDbPath,
    required String rollbackDocsPath,
    required String docsTargetPath,
  }) async {
    try {
      final rollbackDb = await databaseFactoryFfi.openDatabase(
        rollbackDbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        await _restoreDatabaseData(currentDb: _database, backupDb: rollbackDb);
      } finally {
        await rollbackDb.close();
      }
    } catch (_) {}

    try {
      final target = Directory(docsTargetPath);
      if (target.existsSync()) {
        await target.delete(recursive: true);
      }
      await _copyDirectory(Directory(rollbackDocsPath), target);
    } catch (_) {}
  }

  Future<void> _restoreDatabaseData({
    required Database currentDb,
    required Database backupDb,
  }) async {
    final tables = await _tableNames(currentDb);
    final foreignKeysRows = await currentDb.rawQuery('PRAGMA foreign_keys');
    final foreignKeysEnabled =
        (foreignKeysRows.single.values.single as num).toInt() == 1;
    await currentDb.execute('PRAGMA foreign_keys = OFF');
    try {
      await currentDb.transaction((txn) async {
        for (final table in tables) {
          final columns =
              (await txn.rawQuery(
                'PRAGMA table_info(${_quoteIdentifier(table)})',
              )).map((column) => column['name']! as String).toList();
          await txn.delete(table);
          final backupRows = await backupDb.query(table, columns: columns);
          for (final backupRow in backupRows) {
            await txn.insert(table, <String, Object?>{
              for (final column in columns) column: backupRow[column],
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      });
    } finally {
      await currentDb.execute(
        'PRAGMA foreign_keys = ${foreignKeysEnabled ? 'ON' : 'OFF'}',
      );
    }
  }

  Future<List<String>> _tableNames(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' "
      'ORDER BY name',
    );
    return rows.map((row) => row['name']! as String).toList();
  }

  Future<List<Map<String, Object?>>> _tableColumns(Database db, String table) {
    return db.rawQuery('PRAGMA table_info(${_quoteIdentifier(table)})');
  }

  bool _sameColumn(Map<String, Object?> current, Map<String, Object?> backup) {
    const keys = <String>['cid', 'name', 'type', 'notnull', 'dflt_value', 'pk'];
    return keys.every((key) => current[key] == backup[key]);
  }

  String _quoteIdentifier(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final targetPath = p.join(destination.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      } else {
        throw StateError('Documents must not contain symbolic links.');
      }
    }
  }
}
