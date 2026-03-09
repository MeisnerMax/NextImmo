import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/audit_log_repo.dart';
import 'package:neximmo_app/data/repositories/security_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late SecurityRepo repo;
  late AuditLogRepo auditRepo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;
    auditRepo = AuditLogRepo(db);
    repo = SecurityRepo(db, auditLogRepo: auditRepo);
    await repo.bootstrapDefaults();
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('bootstrap creates default context and switching works', () async {
    final context = await repo.getActiveContext();
    expect(context.workspace.id, isNotEmpty);
    expect(context.user.role, 'admin');

    final workspace = await repo.createWorkspace(
      name: 'Workspace 2',
      docsRootPath: 'workspace2/docs',
    );
    final user = await repo.createUser(
      workspaceId: workspace.id,
      displayName: 'Analyst 1',
      role: 'analyst',
    );
    await repo.setActiveWorkspace(workspace.id);
    await repo.setActiveUser(user.id);
    final switched = await repo.getActiveContext();
    expect(switched.workspace.id, workspace.id);
    expect(switched.user.id, user.id);

    final audits = await auditRepo.list(source: 'security');
    expect(
      audits.any((event) => event.action == 'switch_workspace'),
      isTrue,
    );
    expect(audits.any((event) => event.action == 'switch_user'), isTrue);
  });

  test('deleteUser prevents deleting active user', () async {
    await expectLater(
      repo.deleteUser('user_owner'),
      throwsA(
        isA<SecurityOperationException>().having(
          (error) => error.message,
          'message',
          'The active user cannot be deleted.',
        ),
      ),
    );
  });

  test('deleteUser prevents deleting last user in a workspace', () async {
    final workspace = await repo.createWorkspace(
      name: 'Workspace Solo',
      docsRootPath: 'workspace-solo/docs',
    );
    final soloUser = await repo.createUser(
      workspaceId: workspace.id,
      displayName: 'Solo Analyst',
      role: 'analyst',
    );

    await expectLater(
      repo.deleteUser(soloUser.id),
      throwsA(
        isA<SecurityOperationException>().having(
          (error) => error.message,
          'message',
          'The last user in a workspace cannot be deleted.',
        ),
      ),
    );
  });

  test('deleteUser prevents deleting last admin', () async {
    final workspace = await repo.createWorkspace(
      name: 'Workspace 2',
      docsRootPath: 'workspace2/docs',
    );
    final admin = await repo.createUser(
      workspaceId: workspace.id,
      displayName: 'Admin 2',
      role: 'admin',
    );
    await repo.createUser(
      workspaceId: workspace.id,
      displayName: 'Viewer 1',
      role: 'viewer',
    );
    await expectLater(
      repo.deleteUser(admin.id),
      throwsA(
        isA<SecurityOperationException>().having(
          (error) => error.message,
          'message',
          'The last admin in a workspace cannot be deleted.',
        ),
      ),
    );
  });

  test('setActiveWorkspace rejects workspaces without users', () async {
    final workspace = await repo.createWorkspace(
      name: 'Workspace Empty',
      docsRootPath: 'workspace-empty/docs',
    );

    await expectLater(
      repo.setActiveWorkspace(workspace.id),
      throwsA(
        isA<SecurityOperationException>().having(
          (error) => error.message,
          'message',
          'A workspace without users cannot be activated.',
        ),
      ),
    );
  });
}
