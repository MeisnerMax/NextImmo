import '../../../data/repositories/security_repo.dart';
import '../application/membership_admin_repository.dart';

/// Read-only wrapper of the local security store behind the membership-admin
/// contract (P2-D01 step 5, mirroring the P1-006 property adapter): local
/// users project onto always-active members, roles onto the distinct role
/// strings in use, and the invitation surface is empty (the local schema has
/// no invitation lifecycle). Mutations are blocked with [dependencyConflict]
/// — the local schema has neither durable versions nor unique mutation ids,
/// so the audited command envelope cannot be honored.
class LegacySqliteMembershipAdminRepositoryAdapter
    implements MembershipAdminRepository {
  LegacySqliteMembershipAdminRepositoryAdapter({
    required SecurityRepo securityRepo,
    required String legacyWorkspaceId,
  }) : _securityRepo = securityRepo,
       _legacyWorkspaceId = legacyWorkspaceId;

  static const int unsupportedVersion = 0;

  final SecurityRepo _securityRepo;
  final String _legacyWorkspaceId;

  @override
  Future<MembershipAdminResult<List<WorkspaceMember>>> listMembers({
    required String workspaceId,
  }) async {
    final scopeFailure = _scopeFailure<List<WorkspaceMember>>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final users = await _securityRepo.listUsers(_legacyWorkspaceId);
      return MembershipAdminSuccess<List<WorkspaceMember>>(
        users
            .map(
              (user) => WorkspaceMember(
                membershipId: user.id,
                workspaceId: _legacyWorkspaceId,
                userId: user.id,
                roleId: user.role,
                // The local store has no lifecycle: every user is active.
                status: MembershipStatus.active,
                createdAt: DateTime.fromMillisecondsSinceEpoch(
                  user.createdAt,
                  isUtc: true,
                ),
                updatedAt: DateTime.fromMillisecondsSinceEpoch(
                  user.createdAt,
                  isUtc: true,
                ),
                version: unsupportedVersion,
              ),
            )
            .toList(growable: false),
      );
    } catch (_) {
      return const MembershipAdminFailure<List<WorkspaceMember>>(
        kind: MembershipAdminFailureKind.infrastructureFailure,
        message: 'Legacy SQLite users could not be loaded.',
      );
    }
  }

  @override
  Future<MembershipAdminResult<List<WorkspaceRole>>> listRoles({
    required String workspaceId,
  }) async {
    final scopeFailure = _scopeFailure<List<WorkspaceRole>>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final users = await _securityRepo.listUsers(_legacyWorkspaceId);
      final keys =
          users.map((user) => user.role).toSet().toList(growable: false)
            ..sort();
      return MembershipAdminSuccess<List<WorkspaceRole>>(
        keys
            .map(
              (key) => WorkspaceRole(
                id: key,
                workspaceId: _legacyWorkspaceId,
                key: key,
                name: key,
              ),
            )
            .toList(growable: false),
      );
    } catch (_) {
      return const MembershipAdminFailure<List<WorkspaceRole>>(
        kind: MembershipAdminFailureKind.infrastructureFailure,
        message: 'Legacy SQLite roles could not be loaded.',
      );
    }
  }

  @override
  Future<MembershipAdminResult<List<MembershipInvitation>>> listInvitations({
    required String workspaceId,
    bool includeResolved = false,
  }) async {
    final scopeFailure = _scopeFailure<List<MembershipInvitation>>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }
    // The local schema has no invitation lifecycle.
    return const MembershipAdminSuccess<List<MembershipInvitation>>(
      <MembershipInvitation>[],
    );
  }

  @override
  Future<MembershipAdminResult<List<PendingInvitationEntry>>>
  listMyPendingInvitations() async {
    return const MembershipAdminSuccess<List<PendingInvitationEntry>>(
      <PendingInvitationEntry>[],
    );
  }

  @override
  Future<MembershipAdminResult<InviteOutcome>> invite(
    InviteMemberCommand command,
  ) {
    return _blockedMutation<InviteOutcome>(command.context.workspaceId);
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> accept(
    AcceptInvitationCommand command,
  ) {
    return _blockedMutation<WorkspaceMember>(command.context.workspaceId);
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> updateStatus(
    UpdateMembershipStatusCommand command,
  ) {
    return _blockedMutation<WorkspaceMember>(command.context.workspaceId);
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> changeRole(
    ChangeMembershipRoleCommand command,
  ) {
    return _blockedMutation<WorkspaceMember>(command.context.workspaceId);
  }

  @override
  Future<MembershipAdminResult<MembershipInvitation>> revokeInvitation(
    RevokeInvitationCommand command,
  ) {
    return _blockedMutation<MembershipInvitation>(command.context.workspaceId);
  }

  Future<MembershipAdminResult<T>> _blockedMutation<T>(
    String workspaceId,
  ) async {
    final scopeFailure = _scopeFailure<T>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }
    return const MembershipAdminFailure(
      kind: MembershipAdminFailureKind.dependencyConflict,
      message:
          'Legacy SQLite membership administration is blocked: the local '
          'schema has no membership lifecycle, durable version or unique '
          'mutation id.',
    );
  }

  MembershipAdminFailure<T>? _scopeFailure<T>(String workspaceId) {
    if (workspaceId == _legacyWorkspaceId) {
      return null;
    }
    return MembershipAdminFailure<T>(
      kind: MembershipAdminFailureKind.forbidden,
      message: 'The legacy SQLite database is bound to another workspace.',
    );
  }
}
