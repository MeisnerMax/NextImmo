class WorkspaceRecord {
  const WorkspaceRecord({
    required this.id,
    required this.name,
    required this.docsRootPath,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String docsRootPath;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'docs_root_path': docsRootPath,
      'created_at': createdAt,
    };
  }

  factory WorkspaceRecord.fromMap(Map<String, Object?> map) {
    return WorkspaceRecord(
      id: map['id']! as String,
      name: map['name']! as String,
      docsRootPath: map['docs_root_path']! as String,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class LocalUserRecord {
  const LocalUserRecord({
    required this.id,
    required this.workspaceId,
    required this.email,
    required this.displayName,
    required this.passwordHash,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String workspaceId;
  final String? email;
  final String displayName;
  final String? passwordHash;
  final String role;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'workspace_id': workspaceId,
      'email': email,
      'display_name': displayName,
      'password_hash': passwordHash,
      'role': role,
      'created_at': createdAt,
    };
  }

  factory LocalUserRecord.fromMap(Map<String, Object?> map) {
    return LocalUserRecord(
      id: map['id']! as String,
      workspaceId: map['workspace_id']! as String,
      email: map['email'] as String?,
      displayName: map['display_name']! as String,
      passwordHash: map['password_hash'] as String?,
      role: map['role']! as String,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class UserSessionRecord {
  const UserSessionRecord({
    required this.id,
    required this.workspaceId,
    required this.userId,
    required this.startedAt,
    required this.endedAt,
  });

  final String id;
  final String workspaceId;
  final String userId;
  final int startedAt;
  final int? endedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'workspace_id': workspaceId,
      'user_id': userId,
      'started_at': startedAt,
      'ended_at': endedAt,
    };
  }

  factory UserSessionRecord.fromMap(Map<String, Object?> map) {
    return UserSessionRecord(
      id: map['id']! as String,
      workspaceId: map['workspace_id']! as String,
      userId: map['user_id']! as String,
      startedAt: (map['started_at']! as num).toInt(),
      endedAt: (map['ended_at'] as num?)?.toInt(),
    );
  }
}

class SecurityContextRecord {
  const SecurityContextRecord({required this.workspace, required this.user});

  final WorkspaceRecord workspace;
  final LocalUserRecord user;
}
