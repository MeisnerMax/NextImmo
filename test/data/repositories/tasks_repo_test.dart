import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/audit_log_repo.dart';
import 'package:neximmo_app/data/repositories/tasks_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late TasksRepo repo;
  late AuditLogRepo auditRepo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    auditRepo = AuditLogRepo(db);
    repo = TasksRepo(db, auditLogRepo: auditRepo);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('unique template name is enforced', () async {
    await repo.createTemplate(
      name: 'Monthly Review',
      entityType: 'property',
      defaultTitle: 'Review',
      recurrenceRule: 'monthly',
    );
    expect(
      () => repo.createTemplate(
        name: 'monthly review',
        entityType: 'property',
        defaultTitle: 'Review 2',
        recurrenceRule: 'monthly',
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('task checklist item can be created and listed', () async {
    final task = await repo.createTask(
      entityType: 'none',
      title: 'Do something',
    );
    await repo.addChecklistItem(taskId: task.id, text: 'Step 1', position: 0);
    final items = await repo.listChecklistItems(task.id);
    expect(items.length, 1);
    expect(items.first.text, 'Step 1');

    final audits = await auditRepo.list(entityType: 'task', entityId: task.id);
    expect(audits.where((event) => event.action == 'create'), isNotEmpty);
  });
}
