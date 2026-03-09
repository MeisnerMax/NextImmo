import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migrations.dart';

class AppDatabase {
  AppDatabase({this.overridePath});

  final String? overridePath;
  Database? _database;

  Future<Database> get instance async {
    if (_database != null) {
      return _database!;
    }

    final path = await resolvePath();
    _database = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: DbMigrations.currentVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: DbMigrations.onCreate,
        onUpgrade: DbMigrations.onUpgrade,
      ),
    );

    return _database!;
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  Future<String> resolvePath() async {
    return overridePath ?? await _defaultDbPath();
  }

  Future<String> _defaultDbPath() async {
    final baseDirectory = await getApplicationSupportDirectory();
    if (!baseDirectory.existsSync()) {
      await Directory(baseDirectory.path).create(recursive: true);
    }
    return p.join(baseDirectory.path, 'app_data.db');
  }
}
