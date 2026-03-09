import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_writer.dart';
import '../../core/models/security.dart';
import 'audit_log_repo.dart';

class SecurityOperationException implements Exception {
  const SecurityOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SecurityRepo {
  const SecurityRepo(this._db, {AuditLogRepo? auditLogRepo})
    : _auditLogRepo = auditLogRepo;

  final Database _db;
  final AuditLogRepo? _auditLogRepo;

  Future<void> bootstrapDefaults() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('workspaces', <String, Object?>{
      'id': 'ws_default',
      'name': 'Default Workspace',
      'docs_root_path': 'workspace/docs',
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await _db.insert('local_users', <String, Object?>{
      'id': 'user_owner',
      'workspace_id': 'ws_default',
      'email': null,
      'display_name': 'Owner',
      'password_hash': null,
      'role': 'admin',
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await _db.rawUpdate(
      '''
      UPDATE app_settings
      SET active_workspace_id = COALESCE(active_workspace_id, 'ws_default'),
          active_user_id = COALESCE(active_user_id, 'user_owner'),
          updated_at = ?
      WHERE id = 1
      ''',
      <Object?>[now],
    );
  }

  Future<List<WorkspaceRecord>> listWorkspaces() async {
    final rows = await _db.query('workspaces', orderBy: 'name COLLATE NOCASE');
    return rows.map(WorkspaceRecord.fromMap).toList(growable: false);
  }

  Future<WorkspaceRecord> createWorkspace({
    required String name,
    required String docsRootPath,
  }) async {
    final record = WorkspaceRecord(
      id: const Uuid().v4(),
      name: name.trim(),
      docsRootPath: docsRootPath.trim(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insert(
      'workspaces',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _recordAudit(
      entityType: 'workspace',
      entityId: record.id,
      action: 'create',
      summary: 'Workspace created: ${record.name}',
      newValues: record.toMap(),
    );
    return record;
  }

  Future<List<LocalUserRecord>> listUsers(String workspaceId) async {
    final rows = await _db.query(
      'local_users',
      where: 'workspace_id = ?',
      whereArgs: <Object?>[workspaceId],
      orderBy: 'display_name COLLATE NOCASE',
    );
    return rows.map(LocalUserRecord.fromMap).toList(growable: false);
  }

  Future<LocalUserRecord> createUser({
    required String workspaceId,
    String? email,
    required String displayName,
    String? passwordHash,
    required String role,
  }) async {
    final user = LocalUserRecord(
      id: const Uuid().v4(),
      workspaceId: workspaceId,
      email: email?.trim(),
      displayName: displayName.trim(),
      passwordHash: passwordHash,
      role: role.trim().toLowerCase(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insert(
      'local_users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _recordAudit(
      entityType: 'user',
      entityId: user.id,
      action: 'create',
      summary: 'User created: ${user.displayName}',
      parentEntityType: 'workspace',
      parentEntityId: user.workspaceId,
      newValues: user.toMap(),
    );
    return user;
  }

  Future<void> updateUserRole({
    required String userId,
    required String role,
  }) async {
    final before = await _db.query(
      'local_users',
      where: 'id = ?',
      whereArgs: <Object?>[userId],
      limit: 1,
    );
    await _db.update(
      'local_users',
      <String, Object?>{'role': role.trim().toLowerCase()},
      where: 'id = ?',
      whereArgs: <Object?>[userId],
    );
    final after = await _db.query(
      'local_users',
      where: 'id = ?',
      whereArgs: <Object?>[userId],
      limit: 1,
    );
    if (before.isNotEmpty && after.isNotEmpty) {
      await _recordAudit(
        entityType: 'user',
        entityId: userId,
        action: 'update_role',
        summary: 'User role updated',
        parentEntityType: 'workspace',
        parentEntityId: before.first['workspace_id'] as String?,
        oldValues: before.first,
        newValues: after.first,
        reason: 'role change',
      );
    }
  }

  Future<void> deleteUser(String userId) async {
    final userRows = await _db.query(
      'local_users',
      where: 'id = ?',
      whereArgs: <Object?>[userId],
      limit: 1,
    );
    if (userRows.isEmpty) {
      return;
    }
    final user = LocalUserRecord.fromMap(userRows.first);
    final activeContext = await getActiveContext();
    if (activeContext.user.id == userId) {
      throw const SecurityOperationException(
        'The active user cannot be deleted.',
      );
    }

    final usersInWorkspace = await listUsers(user.workspaceId);
    if (usersInWorkspace.length <= 1) {
      throw const SecurityOperationException(
        'The last user in a workspace cannot be deleted.',
      );
    }

    final adminCount = usersInWorkspace.where((entry) => entry.role == 'admin').length;
    if (user.role == 'admin' && adminCount <= 1) {
      throw const SecurityOperationException(
        'The last admin in a workspace cannot be deleted.',
      );
    }

    await _db.delete(
      'local_users',
      where: 'id = ?',
      whereArgs: <Object?>[userId],
    );
    await _recordAudit(
      entityType: 'user',
      entityId: userId,
      action: 'delete',
      summary: 'User deleted: ${user.displayName}',
      parentEntityType: 'workspace',
      parentEntityId: user.workspaceId,
      oldValues: user.toMap(),
    );
  }

  Future<SecurityContextRecord> getActiveContext() async {
    final settingsRows = await _db.query(
      'app_settings',
      columns: const <String>['active_workspace_id', 'active_user_id'],
      where: 'id = 1',
      limit: 1,
    );
    if (settingsRows.isEmpty) {
      throw StateError('Settings row is missing.');
    }
    final activeWorkspaceId =
        settingsRows.first['active_workspace_id'] as String?;
    final activeUserId = settingsRows.first['active_user_id'] as String?;

    WorkspaceRecord workspace;
    if (activeWorkspaceId != null) {
      final wsRows = await _db.query(
        'workspaces',
        where: 'id = ?',
        whereArgs: <Object?>[activeWorkspaceId],
        limit: 1,
      );
      if (wsRows.isNotEmpty) {
        workspace = WorkspaceRecord.fromMap(wsRows.first);
      } else {
        workspace = (await listWorkspaces()).first;
      }
    } else {
      workspace = (await listWorkspaces()).first;
    }

    LocalUserRecord user;
    if (activeUserId != null) {
      final userRows = await _db.query(
        'local_users',
        where: 'id = ?',
        whereArgs: <Object?>[activeUserId],
        limit: 1,
      );
      if (userRows.isNotEmpty) {
        user = LocalUserRecord.fromMap(userRows.first);
      } else {
        final users = await listUsers(workspace.id);
        if (users.isEmpty) {
          throw StateError('No users found in active workspace.');
        }
        user = users.first;
      }
    } else {
      final users = await listUsers(workspace.id);
      if (users.isEmpty) {
        throw StateError('No users found in active workspace.');
      }
      user = users.first;
    }
    return SecurityContextRecord(workspace: workspace, user: user);
  }

  Future<void> setActiveWorkspace(String workspaceId) async {
    final users = await listUsers(workspaceId);
    if (users.isEmpty) {
      throw const SecurityOperationException(
        'A workspace without users cannot be activated.',
      );
    }
    final fallbackUserId = users.first.id;
    await _db.update('app_settings', <String, Object?>{
      'active_workspace_id': workspaceId,
      'active_user_id': fallbackUserId,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = 1');
    await _recordAudit(
      entityType: 'security_context',
      entityId: workspaceId,
      action: 'switch_workspace',
      summary: 'Active workspace switched',
      parentEntityType: 'workspace',
      parentEntityId: workspaceId,
    );
  }

  Future<void> setActiveUser(String userId) async {
    await _db.update('app_settings', <String, Object?>{
      'active_user_id': userId,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = 1');
    final userRows = await _db.query(
      'local_users',
      columns: const <String>['workspace_id'],
      where: 'id = ?',
      whereArgs: <Object?>[userId],
      limit: 1,
    );
    await _recordAudit(
      entityType: 'security_context',
      entityId: userId,
      action: 'switch_user',
      summary: 'Active user switched',
      parentEntityType: userRows.isEmpty ? null : 'workspace',
      parentEntityId:
          userRows.isEmpty ? null : userRows.first['workspace_id'] as String?,
    );
  }

  Future<UserSessionRecord> startSession({
    required String workspaceId,
    required String userId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = UserSessionRecord(
      id: const Uuid().v4(),
      workspaceId: workspaceId,
      userId: userId,
      startedAt: now,
      endedAt: null,
    );
    await _db.insert(
      'user_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _recordAudit(
      entityType: 'user_session',
      entityId: session.id,
      action: 'start_session',
      summary: 'User session started',
      parentEntityType: 'workspace',
      parentEntityId: workspaceId,
      newValues: session.toMap(),
      source: 'security',
    );
    return session;
  }

  Future<void> _recordAudit({
    required String entityType,
    required String entityId,
    required String action,
    String? summary,
    String source = 'security',
    String? parentEntityType,
    String? parentEntityId,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
    String? reason,
  }) async {
    final repo = _auditLogRepo;
    if (repo == null) {
      return;
    }
    final writer = AuditWriter(repo, getActiveContext);
    await writer.record(
      entityType: entityType,
      entityId: entityId,
      action: action,
      summary: summary,
      source: source,
      parentEntityType: parentEntityType,
      parentEntityId: parentEntityId,
      oldValues: oldValues,
      newValues: newValues,
      reason: reason,
      isSystemEvent: source != 'ui',
    );
  }
}
