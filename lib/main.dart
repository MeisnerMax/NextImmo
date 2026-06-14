import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/services/startup_task_service.dart';
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
  await StartupTaskService(
    inputsRepository: InputsRepository(db),
    taskGenerationService: TaskGenerationService(db, TasksRepo(db)),
  ).runIfDue();

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
