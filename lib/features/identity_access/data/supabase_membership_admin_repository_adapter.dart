import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/membership_admin_repository.dart';

abstract interface class MembershipAdminSupabaseGateway {
  String? get currentUserId;

  Future<List<Map<String, dynamic>>> listMemberships({
    required String workspaceId,
  });

  Future<List<Map<String, dynamic>>> listRoles({required String workspaceId});

  Future<List<Map<String, dynamic>>> listRolePermissions({
    required String workspaceId,
  });

  Future<List<Map<String, dynamic>>> listPermissions({
    required List<String> permissionIds,
  });

  Future<List<Map<String, dynamic>>> listInvitations({
    required String workspaceId,
    required bool includeResolved,
  });

  Future<List<Map<String, dynamic>>> listAuditEvents({
    required String workspaceId,
    required List<String> entityTypes,
    required int limit,
    ({String createdAt, String id})? before,
  });

  Future<Object?> callRpc(String function, Map<String, Object?> parameters);
}

class SupabaseMembershipAdminGateway implements MembershipAdminSupabaseGateway {
  SupabaseMembershipAdminGateway(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> listMemberships({
    required String workspaceId,
  }) async {
    final rows = await _client
        .from('memberships')
        .select(
          'id, workspace_id, user_id, role_id, status, created_at, '
          'updated_at, version',
        )
        .eq('workspace_id', workspaceId)
        .order('id', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listRoles({
    required String workspaceId,
  }) async {
    final rows = await _client
        .from('roles')
        .select('id, workspace_id, key, name')
        .eq('workspace_id', workspaceId)
        .order('key', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listRolePermissions({
    required String workspaceId,
  }) async {
    final rows = await _client
        .from('role_permissions')
        .select('workspace_id, role_id, permission_id')
        .eq('workspace_id', workspaceId)
        .order('role_id', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listPermissions({
    required List<String> permissionIds,
  }) async {
    if (permissionIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final rows = await _client
        .from('permissions')
        .select('id, key, name')
        .inFilter('id', permissionIds);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listAuditEvents({
    required String workspaceId,
    required List<String> entityTypes,
    required int limit,
    ({String createdAt, String id})? before,
  }) async {
    var query = _client
        .from('audit_events')
        .select(
          'id, workspace_id, action, entity_type, entity_id, actor_user_id, '
          'role_key, reason, old_values, new_values, created_at',
        )
        .eq('workspace_id', workspaceId)
        .inFilter('entity_type', entityTypes);
    if (before != null) {
      // Keyset over (created_at desc, id desc): strictly older, or the same
      // timestamp with a smaller id.
      query = query.or(
        'created_at.lt."${before.createdAt}",'
        'and(created_at.eq."${before.createdAt}",id.lt."${before.id}")',
      );
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listInvitations({
    required String workspaceId,
    required bool includeResolved,
  }) async {
    var query = _client
        .from('membership_invitations')
        .select(
          'id, workspace_id, email, role_id, status, accepted_membership_id, '
          'created_at, updated_at, version',
        )
        .eq('workspace_id', workspaceId);
    if (!includeResolved) {
      query = query.eq('status', 'pending');
    }
    final rows = await query.order('id', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) {
    return _client.rpc(function, params: parameters);
  }
}

class SupabaseMembershipAdminRepositoryAdapter
    implements MembershipAdminRepository {
  SupabaseMembershipAdminRepositoryAdapter({required SupabaseClient client})
    : _gateway = SupabaseMembershipAdminGateway(client);

  SupabaseMembershipAdminRepositoryAdapter.withGateway(
    MembershipAdminSupabaseGateway gateway,
  ) : _gateway = gateway;

  final MembershipAdminSupabaseGateway _gateway;

  @override
  Future<MembershipAdminResult<List<WorkspaceMember>>> listMembers({
    required String workspaceId,
  }) async {
    try {
      final rows = await _gateway.listMemberships(workspaceId: workspaceId);
      final members = rows.map(_parseMember).toList(growable: false);
      if (members.any((member) => member.workspaceId != workspaceId)) {
        throw const FormatException('Membership workspace mismatch.');
      }
      return MembershipAdminSuccess<List<WorkspaceMember>>(members);
    } catch (_) {
      return const MembershipAdminFailure<List<WorkspaceMember>>(
        kind: MembershipAdminFailureKind.infrastructureFailure,
        message: 'Supabase memberships could not be loaded.',
      );
    }
  }

  @override
  Future<MembershipAdminResult<List<WorkspaceMemberDirectoryEntry>>>
  listMemberDirectory({required String workspaceId}) async {
    try {
      final response = await _gateway.callRpc(
        'list_workspace_members',
        <String, Object?>{'p_workspace_id': workspaceId},
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        final entity = payload['entity'];
        if (entity is! List) {
          throw const FormatException('Expected a directory list.');
        }
        final entries = entity
            .map((row) => _parseDirectoryEntry(_asMap(row)))
            .toList(growable: false);
        if (entries.any((entry) => entry.workspaceId != workspaceId)) {
          throw const FormatException('Directory workspace mismatch.');
        }
        return MembershipAdminSuccess<List<WorkspaceMemberDirectoryEntry>>(
          entries,
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<List<WorkspaceMemberDirectoryEntry>>(
        _asMap(payload['error']),
        null,
      );
    } catch (_) {
      return const MembershipAdminFailure<List<WorkspaceMemberDirectoryEntry>>(
        kind: MembershipAdminFailureKind.infrastructureFailure,
        message: 'Supabase member directory could not be loaded.',
      );
    }
  }

  @override
  Future<MembershipAdminResult<List<WorkspaceRole>>> listRoles({
    required String workspaceId,
  }) async {
    try {
      final rows = await _gateway.listRoles(workspaceId: workspaceId);
      final roles = rows.map(_parseRole).toList(growable: false);
      if (roles.any((role) => role.workspaceId != workspaceId)) {
        throw const FormatException('Role workspace mismatch.');
      }
      return MembershipAdminSuccess<List<WorkspaceRole>>(roles);
    } catch (_) {
      return const MembershipAdminFailure<List<WorkspaceRole>>(
        kind: MembershipAdminFailureKind.infrastructureFailure,
        message: 'Supabase workspace roles could not be loaded.',
      );
    }
  }

  @override
  Future<MembershipAdminResult<List<WorkspaceRoleCapability>>>
  listRolePermissions({required String workspaceId}) async {
    try {
      final assignments = await _gateway.listRolePermissions(
        workspaceId: workspaceId,
      );
      if (assignments.isEmpty) {
        return const MembershipAdminSuccess<List<WorkspaceRoleCapability>>(
          <WorkspaceRoleCapability>[],
        );
      }
      final permissionIds = <String>{};
      for (final assignment in assignments) {
        if (_requiredString(assignment, 'workspace_id') != workspaceId) {
          throw const FormatException('Role permission workspace mismatch.');
        }
        permissionIds.add(_requiredString(assignment, 'permission_id'));
      }
      final permissionRows = await _gateway.listPermissions(
        permissionIds: permissionIds.toList(growable: false),
      );
      final permissionsById = <String, ({String key, String name})>{
        for (final row in permissionRows)
          _requiredString(row, 'id'): (
            key: _requiredString(row, 'key'),
            name: _requiredString(row, 'name'),
          ),
      };
      final capabilities = <WorkspaceRoleCapability>[];
      for (final assignment in assignments) {
        final permission =
            permissionsById[_requiredString(assignment, 'permission_id')];
        if (permission == null) {
          throw const FormatException('Unknown permission reference.');
        }
        capabilities.add(
          WorkspaceRoleCapability(
            roleId: _requiredString(assignment, 'role_id'),
            permissionKey: permission.key,
            permissionName: permission.name,
          ),
        );
      }
      capabilities.sort((a, b) => a.permissionKey.compareTo(b.permissionKey));
      return MembershipAdminSuccess<List<WorkspaceRoleCapability>>(
        List<WorkspaceRoleCapability>.unmodifiable(capabilities),
      );
    } catch (_) {
      return const MembershipAdminFailure<List<WorkspaceRoleCapability>>(
        kind: MembershipAdminFailureKind.infrastructureFailure,
        message: 'Supabase role permissions could not be loaded.',
      );
    }
  }

  static const _membershipAuditEntityTypes = <String>[
    'membership',
    'membership_invitation',
  ];

  @override
  Future<MembershipAdminResult<MembershipAuditPage>> listMembershipAuditEvents({
    required String workspaceId,
    int limit = 50,
    MembershipAuditCursor? before,
  }) async {
    try {
      final rows = await _gateway.listAuditEvents(
        workspaceId: workspaceId,
        entityTypes: _membershipAuditEntityTypes,
        limit: limit + 1,
        before:
            before == null
                ? null
                : (createdAt: before.createdAt, id: before.id),
      );
      final events = <MembershipAuditEvent>[];
      final rawCursorByEventId = <String, String>{};
      for (final row in rows) {
        // A row of a foreign entity type is never a membership activity;
        // dropping it beats mislabelling it (defense in depth over the
        // server-side filter).
        if (!_membershipAuditEntityTypes.contains(
          _requiredString(row, 'entity_type'),
        )) {
          continue;
        }
        final event = _parseAuditEvent(row);
        if (event.workspaceId != workspaceId) {
          throw const FormatException('Audit event workspace mismatch.');
        }
        events.add(event);
        rawCursorByEventId[event.id] = _requiredString(row, 'created_at');
      }
      final hasMore = events.length > limit;
      final page = hasMore ? events.sublist(0, limit) : events;
      final cursorEvent = hasMore ? page.last : null;
      return MembershipAdminSuccess<MembershipAuditPage>(
        MembershipAuditPage(
          events: List<MembershipAuditEvent>.unmodifiable(page),
          nextCursor:
              cursorEvent == null
                  ? null
                  : MembershipAuditCursor(
                    createdAt: rawCursorByEventId[cursorEvent.id]!,
                    id: cursorEvent.id,
                  ),
        ),
      );
    } catch (_) {
      return const MembershipAdminFailure<MembershipAuditPage>(
        kind: MembershipAdminFailureKind.infrastructureFailure,
        message: 'Supabase membership audit events could not be loaded.',
      );
    }
  }

  @override
  Future<MembershipAdminResult<List<MembershipInvitation>>> listInvitations({
    required String workspaceId,
    bool includeResolved = false,
  }) async {
    try {
      final rows = await _gateway.listInvitations(
        workspaceId: workspaceId,
        includeResolved: includeResolved,
      );
      final invitations = rows.map(_parseInvitation).toList(growable: false);
      if (invitations.any(
        (invitation) => invitation.workspaceId != workspaceId,
      )) {
        throw const FormatException('Invitation workspace mismatch.');
      }
      return MembershipAdminSuccess<List<MembershipInvitation>>(invitations);
    } catch (_) {
      return const MembershipAdminFailure<List<MembershipInvitation>>(
        kind: MembershipAdminFailureKind.infrastructureFailure,
        message: 'Supabase membership invitations could not be loaded.',
      );
    }
  }

  @override
  Future<MembershipAdminResult<List<PendingInvitationEntry>>>
  listMyPendingInvitations() async {
    try {
      final response = await _gateway.callRpc(
        'list_my_pending_invitations',
        const <String, Object?>{},
      );
      if (response is! List) {
        throw const FormatException('Expected a list result.');
      }
      final entries = response
          .map((entry) => _parsePendingInvitationEntry(_asMap(entry)))
          .toList(growable: false);
      return MembershipAdminSuccess<List<PendingInvitationEntry>>(entries);
    } catch (_) {
      return const MembershipAdminFailure<List<PendingInvitationEntry>>(
        kind: MembershipAdminFailureKind.infrastructureFailure,
        message: 'Supabase pending invitations could not be loaded.',
      );
    }
  }

  @override
  Future<MembershipAdminResult<InviteOutcome>> invite(
    InviteMemberCommand command,
  ) {
    return _executeCommand<InviteOutcome>(
      context: command.context,
      function: 'invite_workspace_member',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_email': command.email,
        'p_role_id': command.roleId,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity: (Map<String, dynamic> entity) {
        if (entity.containsKey('user_id')) {
          final member = _parseMember(entity);
          _requireWorkspace(member.workspaceId, command.context.workspaceId);
          return InviteOutcome(member: member);
        }
        final invitation = _parseInvitation(entity);
        _requireWorkspace(invitation.workspaceId, command.context.workspaceId);
        return InviteOutcome(invitation: invitation);
      },
    );
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> accept(
    AcceptInvitationCommand command,
  ) {
    return _executeCommand<WorkspaceMember>(
      context: command.context,
      function: 'accept_workspace_invitation',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity: (Map<String, dynamic> entity) {
        final member = _parseMember(entity);
        _requireWorkspace(member.workspaceId, command.context.workspaceId);
        return member;
      },
    );
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> updateStatus(
    UpdateMembershipStatusCommand command,
  ) {
    return _executeCommand<WorkspaceMember>(
      context: command.context,
      function: 'update_membership_status',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_membership_id': command.membershipId,
        'p_new_status': command.newStatus.name,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity: (Map<String, dynamic> entity) {
        final member = _parseMember(entity);
        _requireWorkspace(member.workspaceId, command.context.workspaceId);
        return member;
      },
      parseConflictEntity: (Map<String, dynamic> entity) {
        final member = _parseMember(entity);
        _requireWorkspace(member.workspaceId, command.context.workspaceId);
        return (currentMember: member, currentInvitation: null);
      },
    );
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> changeRole(
    ChangeMembershipRoleCommand command,
  ) {
    return _executeCommand<WorkspaceMember>(
      context: command.context,
      function: 'change_membership_role',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_membership_id': command.membershipId,
        'p_new_role_id': command.newRoleId,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity: (Map<String, dynamic> entity) {
        final member = _parseMember(entity);
        _requireWorkspace(member.workspaceId, command.context.workspaceId);
        return member;
      },
      parseConflictEntity: (Map<String, dynamic> entity) {
        final member = _parseMember(entity);
        _requireWorkspace(member.workspaceId, command.context.workspaceId);
        return (currentMember: member, currentInvitation: null);
      },
    );
  }

  @override
  Future<MembershipAdminResult<MembershipInvitation>> revokeInvitation(
    RevokeInvitationCommand command,
  ) {
    return _executeCommand<MembershipInvitation>(
      context: command.context,
      function: 'revoke_workspace_invitation',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_invitation_id': command.invitationId,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity: (Map<String, dynamic> entity) {
        final invitation = _parseInvitation(entity);
        _requireWorkspace(invitation.workspaceId, command.context.workspaceId);
        return invitation;
      },
      parseConflictEntity: (Map<String, dynamic> entity) {
        final invitation = _parseInvitation(entity);
        _requireWorkspace(invitation.workspaceId, command.context.workspaceId);
        return (currentMember: null, currentInvitation: invitation);
      },
    );
  }

  Future<MembershipAdminResult<T>> _executeCommand<T>({
    required MembershipCommandContext context,
    required String function,
    required Map<String, Object?> parameters,
    required T Function(Map<String, dynamic> entity) parseEntity,
    _ConflictEntity Function(Map<String, dynamic> entity)? parseConflictEntity,
  }) async {
    if (_gateway.currentUserId != context.actorId) {
      return MembershipAdminFailure<T>(
        kind: MembershipAdminFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }

    try {
      final response = await _gateway.callRpc(function, parameters);
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return MembershipAdminSuccess<T>(
          parseEntity(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<T>(_asMap(payload['error']), parseConflictEntity);
    } catch (_) {
      return MembershipAdminFailure<T>(
        kind: MembershipAdminFailureKind.infrastructureFailure,
        message: 'Supabase membership command failed.',
      );
    }
  }

  MembershipAdminFailure<T> _mapRpcFailure<T>(
    Map<String, dynamic> error,
    _ConflictEntity Function(Map<String, dynamic> entity)? parseConflictEntity,
  ) {
    final code = _requiredString(error, 'code');
    final message =
        error['message'] is String
            ? error['message'] as String
            : 'Membership command failed.';
    switch (code) {
      case 'not_found':
        return MembershipAdminFailure<T>(
          kind: MembershipAdminFailureKind.notFound,
          message: message,
        );
      case 'forbidden':
        return MembershipAdminFailure<T>(
          kind: MembershipAdminFailureKind.forbidden,
          message: message,
        );
      case 'validation_failed':
        return MembershipAdminFailure<T>(
          kind: MembershipAdminFailureKind.validationFailed,
          message: message,
        );
      case 'mutation_conflict':
        return MembershipAdminFailure<T>(
          kind: MembershipAdminFailureKind.mutationConflict,
          message: message,
        );
      case 'in_progress':
        return MembershipAdminFailure<T>(
          kind: MembershipAdminFailureKind.mutationInProgress,
          message: message,
        );
      case 'version_conflict':
        if (parseConflictEntity == null) {
          throw const FormatException('Unexpected version conflict.');
        }
        final conflictEntity = parseConflictEntity(
          _asMap(error['current_entity']),
        );
        return MembershipAdminFailure<T>(
          kind: MembershipAdminFailureKind.versionConflict,
          message: message,
          versionConflict: MembershipVersionConflict(
            expectedVersion: _requiredInt(error, 'expected_version'),
            actualVersion: _requiredInt(error, 'actual_version'),
            currentMember: conflictEntity.currentMember,
            currentInvitation: conflictEntity.currentInvitation,
          ),
        );
      case 'infrastructure_failure':
      default:
        return MembershipAdminFailure<T>(
          kind: MembershipAdminFailureKind.infrastructureFailure,
          message: 'Supabase membership command failed.',
        );
    }
  }
}

typedef _ConflictEntity =
    ({WorkspaceMember? currentMember, MembershipInvitation? currentInvitation});

WorkspaceMember _parseMember(Map<String, dynamic> json) {
  return WorkspaceMember(
    membershipId: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    userId: _requiredString(json, 'user_id'),
    roleId: _requiredString(json, 'role_id'),
    status: MembershipStatus.values.byName(_requiredString(json, 'status')),
    createdAt: DateTime.parse(_requiredString(json, 'created_at')),
    updatedAt: DateTime.parse(_requiredString(json, 'updated_at')),
    version: _requiredInt(json, 'version'),
  );
}

MembershipInvitation _parseInvitation(Map<String, dynamic> json) {
  return MembershipInvitation(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    email: _requiredString(json, 'email'),
    roleId: _requiredString(json, 'role_id'),
    status: MembershipInvitationStatus.values.byName(
      _requiredString(json, 'status'),
    ),
    createdAt: DateTime.parse(_requiredString(json, 'created_at')),
    updatedAt: DateTime.parse(_requiredString(json, 'updated_at')),
    version: _requiredInt(json, 'version'),
    acceptedMembershipId: _nullableString(json, 'accepted_membership_id'),
  );
}

WorkspaceMemberDirectoryEntry _parseDirectoryEntry(Map<String, dynamic> json) {
  return WorkspaceMemberDirectoryEntry(
    membershipId: _requiredString(json, 'membership_id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    userId: _requiredString(json, 'user_id'),
    roleId: _requiredString(json, 'role_id'),
    roleKey: _requiredString(json, 'role_key'),
    roleName: _requiredString(json, 'role_name'),
    status: MembershipStatus.values.byName(_requiredString(json, 'status')),
    createdAt: DateTime.parse(_requiredString(json, 'created_at')),
    updatedAt: DateTime.parse(_requiredString(json, 'updated_at')),
    version: _requiredInt(json, 'version'),
    displayName: _nullableString(json, 'display_name'),
    email: _nullableString(json, 'email'),
  );
}

WorkspaceRole _parseRole(Map<String, dynamic> json) {
  return WorkspaceRole(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    key: _requiredString(json, 'key'),
    name: _requiredString(json, 'name'),
  );
}

MembershipAuditEvent _parseAuditEvent(Map<String, dynamic> json) {
  final entityType = _requiredString(json, 'entity_type');
  final oldValues = json['old_values'];
  final newValues = json['new_values'];
  final isInvitation = entityType == 'membership_invitation';
  return MembershipAuditEvent(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    action: _requiredString(json, 'action'),
    entityType: entityType,
    createdAt: DateTime.parse(_requiredString(json, 'created_at')),
    entityId: _nullableString(json, 'entity_id'),
    actorUserId: _nullableString(json, 'actor_user_id'),
    actorRoleKey: _nullableString(json, 'role_key'),
    reason: _nullableString(json, 'reason'),
    targetUserId:
        isInvitation
            ? null
            : _snapshotString(newValues, 'user_id') ??
                _snapshotString(oldValues, 'user_id'),
    targetEmail:
        isInvitation
            ? _snapshotString(newValues, 'email') ??
                _snapshotString(oldValues, 'email')
            : null,
    oldRoleId: _snapshotString(oldValues, 'role_id'),
    newRoleId: _snapshotString(newValues, 'role_id'),
  );
}

/// Fail-safe snapshot lookup: a malformed payload nulls the extract instead
/// of failing the whole page.
String? _snapshotString(Object? snapshot, String key) {
  if (snapshot is! Map) {
    return null;
  }
  final value = snapshot[key];
  return value is String ? value : null;
}

PendingInvitationEntry _parsePendingInvitationEntry(Map<String, dynamic> json) {
  final kind = _requiredString(json, 'kind');
  if (kind != 'membership' && kind != 'invitation') {
    throw FormatException('Unknown pending entry kind: $kind.');
  }
  final isMembership = kind == 'membership';
  return PendingInvitationEntry(
    isMembership: isMembership,
    workspaceId: _requiredString(json, 'workspace_id'),
    workspaceName: _requiredString(json, 'workspace_name'),
    roleKey: _requiredString(json, 'role_key'),
    roleName: _requiredString(json, 'role_name'),
    createdAt: DateTime.parse(_requiredString(json, 'created_at')),
    version: _requiredInt(json, 'version'),
    membershipId: isMembership ? _requiredString(json, 'membership_id') : null,
    invitationId: isMembership ? null : _requiredString(json, 'invitation_id'),
  );
}

void _requireWorkspace(String workspaceId, String expectedWorkspaceId) {
  if (workspaceId != expectedWorkspaceId) {
    throw const FormatException('Entity workspace mismatch.');
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected an object.');
  }
  return Map<String, dynamic>.from(value);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Expected string field: $key.');
  }
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Expected nullable string field: $key.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Expected integer field: $key.');
}
