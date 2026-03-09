import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/services/task_generation_service.dart';
import 'data/repositories/inputs_repo.dart';
import 'data/repositories/security_repo.dart';
import 'data/repositories/tasks_repo.dart';
import 'data/sqlite/db.dart';
import 'ui/state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final appDatabase = AppDatabase();
  final db = await appDatabase.instance;
  await SecurityRepo(db).bootstrapDefaults();
  await _runStartupTaskGeneration(db);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appDatabaseProvider.overrideWithValue(appDatabase),
      ],
      child: const NexImmoApp(),
    ),
  );
}

Future<void> _runStartupTaskGeneration(Database db) async {
  final inputsRepo = InputsRepository(db);
  final settings = await inputsRepo.getSettings();
  final lastRun = settings.lastTaskGenerationAt;
  final now = DateTime.now();
  final nowMs = now.millisecondsSinceEpoch;
  final shouldRun =
      lastRun == null ||
      now.difference(DateTime.fromMillisecondsSinceEpoch(lastRun)).inHours >=
          24;
  if (!shouldRun) {
    return;
  }
  final service = TaskGenerationService(db, TasksRepo(db));
  await service.generate(
    now: nowMs,
    dueSoonDays: settings.taskDueSoonDays,
    enableNotifications: settings.enableTaskNotifications,
  );
  await inputsRepo.updateSettings(
    settings.copyWith(
      lastTaskGenerationAt: nowMs,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );
}
