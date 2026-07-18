import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_environment.dart';
import 'core/services/startup_task_service.dart';
import 'core/services/task_generation_service.dart';
import 'data/repositories/inputs_repo.dart';
import 'data/repositories/security_repo.dart';
import 'data/repositories/tasks_repo.dart';
import 'data/sqlite/db.dart';
import 'features/identity_access/data/supabase_identity_access_repository_adapter.dart';
import 'features/portfolio_property/data/supabase_property_query_invalidation_adapter.dart';
import 'features/portfolio_property/data/supabase_property_repository_adapter.dart';
import 'features/reference_slice/application/reference_slice_controller.dart';
import 'ui/state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final environment = AppEnvironment.fromDartDefines();

  if (environment.dataBackend == DataBackend.supabase) {
    await Supabase.initialize(
      url: environment.supabaseUrl!,
      anonKey: environment.supabasePublishableKey!,
    );
    final client = Supabase.instance.client;
    runApp(
      ProviderScope(
        overrides: [
          identityAccessRepositoryProvider.overrideWithValue(
            SupabaseIdentityAccessRepositoryAdapter(client: client),
          ),
          referencePropertyRepositoryProvider.overrideWithValue(
            SupabasePropertyRepositoryAdapter(client: client),
          ),
          propertyQueryInvalidationSourceProvider.overrideWithValue(
            SupabasePropertyQueryInvalidationAdapter(client: client),
          ),
        ],
        child: NexImmoApp(environment: environment),
      ),
    );
    return;
  }

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
      child: NexImmoApp(environment: environment),
    ),
  );
}
