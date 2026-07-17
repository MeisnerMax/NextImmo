import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/identity_access_repository.dart';

abstract interface class IdentityAccessSupabaseGateway {
  AuthenticatedSession? get currentSession;

  Stream<AuthenticatedSession?> watchSession();

  Future<List<Map<String, dynamic>>> listActiveMemberships(String userId);

  Future<List<Map<String, dynamic>>> listWorkspaces(List<String> workspaceIds);

  Future<List<Map<String, dynamic>>> listRolePermissions(
    List<String> workspaceIds,
  );

  Future<List<Map<String, dynamic>>> listPermissions(
    List<String> permissionIds,
  );
}

class SupabaseIdentityAccessGateway implements IdentityAccessSupabaseGateway {
  SupabaseIdentityAccessGateway(this._client);

  final SupabaseClient _client;

  @override
  AuthenticatedSession? get currentSession => _currentSession();

  @override
  Stream<AuthenticatedSession?> watchSession() {
    return _client.auth.onAuthStateChange
        .map((_) => _currentSession())
        .distinct(
          (previous, next) =>
              previous?.userId == next?.userId &&
              previous?.currentAssuranceLevel == next?.currentAssuranceLevel &&
              previous?.nextAssuranceLevel == next?.nextAssuranceLevel,
        );
  }

  AuthenticatedSession? _currentSession() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }
    final assurance = _client.auth.mfa.getAuthenticatorAssuranceLevel();
    return AuthenticatedSession(
      userId: userId,
      currentAssuranceLevel: _mapAssurance(assurance.currentLevel?.name),
      nextAssuranceLevel: _mapAssurance(assurance.nextLevel?.name),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listActiveMemberships(
    String userId,
  ) async {
    final rows = await _client
        .from('memberships')
        .select('id, workspace_id, user_id, role_id, status, version')
        .eq('user_id', userId)
        .eq('status', 'active');
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listWorkspaces(
    List<String> workspaceIds,
  ) async {
    if (workspaceIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final rows = await _client
        .from('workspaces')
        .select('id, key, name, version, archived_at')
        .inFilter('id', workspaceIds)
        .isFilter('archived_at', null)
        .order('name', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listRolePermissions(
    List<String> workspaceIds,
  ) async {
    if (workspaceIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final rows = await _client
        .from('role_permissions')
        .select('workspace_id, role_id, permission_id')
        .inFilter('workspace_id', workspaceIds);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listPermissions(
    List<String> permissionIds,
  ) async {
    if (permissionIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final rows = await _client
        .from('permissions')
        .select('id, key')
        .inFilter('id', permissionIds);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }
}

class SupabaseIdentityAccessRepositoryAdapter
    implements IdentityAccessRepository {
  SupabaseIdentityAccessRepositoryAdapter({required SupabaseClient client})
    : _gateway = SupabaseIdentityAccessGateway(client);

  SupabaseIdentityAccessRepositoryAdapter.withGateway(
    IdentityAccessSupabaseGateway gateway,
  ) : _gateway = gateway;

  final IdentityAccessSupabaseGateway _gateway;

  @override
  AuthenticatedSession? get currentSession => _gateway.currentSession;

  @override
  Stream<AuthenticatedSession?> watchSession() => _gateway.watchSession();

  @override
  Future<IdentityAccessResult<List<WorkspaceAccess>>> listWorkspaceAccesses({
    required String userId,
  }) async {
    final session = _gateway.currentSession;
    if (session?.userId != userId || session!.requiresMfaChallenge) {
      return const IdentityAccessFailure<List<WorkspaceAccess>>(
        kind: IdentityAccessFailureKind.unauthenticated,
        message: 'The requested user is not authenticated.',
      );
    }

    try {
      final membershipRows = await _gateway.listActiveMemberships(userId);
      final memberships = membershipRows
          .map((row) {
            if (_requiredString(row, 'user_id') != userId ||
                _requiredString(row, 'status') != 'active') {
              throw const FormatException('Membership scope mismatch.');
            }
            return MembershipSummary(
              id: _requiredString(row, 'id'),
              workspaceId: _requiredString(row, 'workspace_id'),
              userId: userId,
              roleId: _requiredString(row, 'role_id'),
              version: _requiredInt(row, 'version'),
            );
          })
          .toList(growable: false);
      if (memberships.isEmpty) {
        return const IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[],
        );
      }

      final workspaceIds = memberships
          .map((membership) => membership.workspaceId)
          .toSet()
          .toList(growable: false);
      final workspaceRows = await _gateway.listWorkspaces(workspaceIds);
      final workspaces = <String, WorkspaceSummary>{};
      for (final row in workspaceRows) {
        final id = _requiredString(row, 'id');
        if (!workspaceIds.contains(id) || row['archived_at'] != null) {
          throw const FormatException('Workspace scope mismatch.');
        }
        if (workspaces.containsKey(id)) {
          throw const FormatException('Duplicate workspace.');
        }
        workspaces[id] = WorkspaceSummary(
          id: id,
          key: _requiredString(row, 'key'),
          name: _requiredString(row, 'name'),
          version: _requiredInt(row, 'version'),
        );
      }

      final visibleMemberships = memberships
          .where((membership) => workspaces.containsKey(membership.workspaceId))
          .toList(growable: false);
      final rolePermissionRows = await _gateway.listRolePermissions(
        visibleMemberships
            .map((membership) => membership.workspaceId)
            .toSet()
            .toList(growable: false),
      );
      final permissionIds = rolePermissionRows
          .map((row) => _requiredString(row, 'permission_id'))
          .toSet()
          .toList(growable: false);
      final permissionRows = await _gateway.listPermissions(permissionIds);
      final permissionKeysById = <String, String>{
        for (final row in permissionRows)
          _requiredString(row, 'id'): _requiredString(row, 'key'),
      };
      if (!permissionKeysById.keys.toSet().containsAll(permissionIds)) {
        throw const FormatException('Permission reference is missing.');
      }

      final permissionsByMembership = <String, Set<String>>{
        for (final membership in visibleMemberships) membership.id: <String>{},
      };
      for (final row in rolePermissionRows) {
        final workspaceId = _requiredString(row, 'workspace_id');
        final roleId = _requiredString(row, 'role_id');
        final permissionId = _requiredString(row, 'permission_id');
        final matching = visibleMemberships.where(
          (membership) =>
              membership.workspaceId == workspaceId &&
              membership.roleId == roleId,
        );
        for (final membership in matching) {
          permissionsByMembership[membership.id]!.add(
            permissionKeysById[permissionId]!,
          );
        }
      }

      final accesses = visibleMemberships
        .map(
          (membership) => WorkspaceAccess(
            workspace: workspaces[membership.workspaceId]!,
            membership: membership,
            permissions: permissionsByMembership[membership.id]!,
          ),
        )
        .toList(growable: false)..sort((left, right) {
        final byName = left.workspace.name.compareTo(right.workspace.name);
        return byName != 0
            ? byName
            : left.workspace.id.compareTo(right.workspace.id);
      });
      return IdentityAccessSuccess<List<WorkspaceAccess>>(accesses);
    } catch (_) {
      return const IdentityAccessFailure<List<WorkspaceAccess>>(
        kind: IdentityAccessFailureKind.infrastructureFailure,
        message: 'Workspace access could not be loaded.',
      );
    }
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected non-empty string field: $key.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('Expected integer field: $key.');
  }
  return value;
}

AuthenticationAssuranceLevel _mapAssurance(String? value) {
  return switch (value) {
    'aal2' => AuthenticationAssuranceLevel.aal2,
    _ => AuthenticationAssuranceLevel.aal1,
  };
}
