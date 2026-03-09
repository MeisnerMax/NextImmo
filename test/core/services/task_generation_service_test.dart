import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/services/task_generation_service.dart';
import 'package:neximmo_app/data/repositories/tasks_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late TasksRepo tasksRepo;
  late TaskGenerationService service;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    tasksRepo = TasksRepo(db);
    service = TaskGenerationService(db, tasksRepo);

    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Objekt',
      'address_line1': 'Street',
      'address_line2': null,
      'zip': '10115',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'single_family',
      'units': 1,
      'sqft': null,
      'year_built': null,
      'notes': null,
      'created_at': 1,
      'updated_at': 1,
      'archived': 0,
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('generation is idempotent and checklist is copied', () async {
    final template = await tasksRepo.createTemplate(
      name: 'Monthly Property Review',
      entityType: 'property',
      defaultTitle: 'Review monthly',
      recurrenceRule: 'monthly',
      recurrenceInterval: 1,
    );
    await tasksRepo.addTemplateChecklistItem(
      templateId: template.id,
      text: 'Check rent inflow',
      position: 0,
    );
    await tasksRepo.addTemplateChecklistItem(
      templateId: template.id,
      text: 'Check expenses',
      position: 1,
    );

    final now = DateTime(2026, 3, 3).millisecondsSinceEpoch;
    final first = await service.generate(
      now: now,
      dueSoonDays: 3,
      enableNotifications: true,
    );
    final second = await service.generate(
      now: now,
      dueSoonDays: 3,
      enableNotifications: true,
    );

    expect(first.generatedTasks, 1);
    expect(second.generatedTasks, 0);

    final tasks = await tasksRepo.listTasks(entityType: 'property');
    expect(tasks.length, 1);
    final checklist = await tasksRepo.listChecklistItems(tasks.first.id);
    expect(checklist.length, 2);
    expect(checklist.first.text, 'Check rent inflow');
  });
}
