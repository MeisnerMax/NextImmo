/// Backend-agnostic membership administration contract (P2-D01, STM-001).
///
/// The membership lifecycle lives on the membership row itself:
/// `invited -> active` via the invitee's [MembershipAdminRepository.accept],
/// `active <-> suspended` and `-> revoked` (terminal) via admin transitions.
/// Emails without an auth user are staged as [MembershipInvitation]s and
/// converted by the invitee's accept on first sign-in. All mutations are
/// workspace-scoped, AAL2-gated server-side, idempotent (`mutationId`),
/// versioned (`expectedVersion` where a row is edited) and audited
/// append-only — the same envelope as the property contract.
library;

enum MembershipStatus { invited, active, suspended, revoked }

enum MembershipInvitationStatus { pending, accepted, revoked }

class WorkspaceMember {
  const WorkspaceMember({
    required this.membershipId,
    required this.workspaceId,
    required this.userId,
    required this.roleId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
  });

  final String membershipId;
  final String workspaceId;
  final String userId;
  final String roleId;
  final MembershipStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
}

class MembershipInvitation {
  const MembershipInvitation({
    required this.id,
    required this.workspaceId,
    required this.email,
    required this.roleId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.acceptedMembershipId,
  });

  final String id;
  final String workspaceId;
  final String email;
  final String roleId;
  final MembershipInvitationStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final String? acceptedMembershipId;
}

class WorkspaceRole {
  const WorkspaceRole({
    required this.id,
    required this.workspaceId,
    required this.key,
    required this.name,
  });

  final String id;
  final String workspaceId;
  final String key;
  final String name;
}

/// One entry of the signed-in user's own pending-invitation list. Carries the
/// workspace/role names the invitee's row-level security could not otherwise
/// read yet.
class PendingInvitationEntry {
  const PendingInvitationEntry({
    required this.isMembership,
    required this.workspaceId,
    required this.workspaceName,
    required this.roleKey,
    required this.roleName,
    required this.createdAt,
    required this.version,
    this.membershipId,
    this.invitationId,
  }) : assert(isMembership ? membershipId != null : invitationId != null);

  /// True when the entry is an `invited` membership (existing auth user);
  /// false when it is a pre-auth email invitation.
  final bool isMembership;
  final String workspaceId;
  final String workspaceName;
  final String roleKey;
  final String roleName;
  final DateTime createdAt;
  final int version;
  final String? membershipId;
  final String? invitationId;
}

/// Either the membership (existing auth user) or the pre-auth email
/// invitation an invite resolved to — exactly one is set.
class InviteOutcome {
  const InviteOutcome({this.member, this.invitation})
    : assert((member != null) != (invitation != null));

  final WorkspaceMember? member;
  final MembershipInvitation? invitation;
}

class MembershipCommandContext {
  const MembershipCommandContext({
    required this.workspaceId,
    required this.actorId,
    required this.mutationId,
    required this.correlationId,
    this.reason,
  });

  final String workspaceId;
  final String actorId;
  final String mutationId;
  final String correlationId;
  final String? reason;
}

class InviteMemberCommand {
  const InviteMemberCommand({
    required this.context,
    required this.email,
    required this.roleId,
  });

  final MembershipCommandContext context;
  final String email;
  final String roleId;
}

class AcceptInvitationCommand {
  const AcceptInvitationCommand({required this.context});

  final MembershipCommandContext context;
}

class UpdateMembershipStatusCommand {
  const UpdateMembershipStatusCommand({
    required this.context,
    required this.membershipId,
    required this.newStatus,
    required this.expectedVersion,
  });

  final MembershipCommandContext context;
  final String membershipId;
  final MembershipStatus newStatus;
  final int expectedVersion;
}

class ChangeMembershipRoleCommand {
  const ChangeMembershipRoleCommand({
    required this.context,
    required this.membershipId,
    required this.newRoleId,
    required this.expectedVersion,
  });

  final MembershipCommandContext context;
  final String membershipId;
  final String newRoleId;
  final int expectedVersion;
}

class RevokeInvitationCommand {
  const RevokeInvitationCommand({
    required this.context,
    required this.invitationId,
    required this.expectedVersion,
  });

  final MembershipCommandContext context;
  final String invitationId;
  final int expectedVersion;
}

enum MembershipAdminFailureKind {
  notFound,
  forbidden,
  validationFailed,
  versionConflict,
  mutationConflict,
  mutationInProgress,
  dependencyConflict,
  infrastructureFailure,
}

/// Structured optimistic-concurrency conflict. Exactly one of
/// [currentMember]/[currentInvitation] is set, matching the entity the
/// failed command targeted.
class MembershipVersionConflict {
  const MembershipVersionConflict({
    required this.expectedVersion,
    required this.actualVersion,
    this.currentMember,
    this.currentInvitation,
  }) : assert((currentMember != null) != (currentInvitation != null));

  final int expectedVersion;
  final int actualVersion;
  final WorkspaceMember? currentMember;
  final MembershipInvitation? currentInvitation;
}

sealed class MembershipAdminResult<T> {
  const MembershipAdminResult();
}

class MembershipAdminSuccess<T> extends MembershipAdminResult<T> {
  const MembershipAdminSuccess(this.value);

  final T value;
}

class MembershipAdminFailure<T> extends MembershipAdminResult<T> {
  const MembershipAdminFailure({
    required this.kind,
    required this.message,
    this.versionConflict,
  }) : assert(
         kind == MembershipAdminFailureKind.versionConflict
             ? versionConflict != null
             : versionConflict == null,
       );

  final MembershipAdminFailureKind kind;
  final String message;
  final MembershipVersionConflict? versionConflict;
}

/// Workspace membership administration. Reads are server-authorized (a
/// `security.manage` holder sees the whole workspace, everyone else at most
/// their own row); mutations run through the audited RPC envelope only.
abstract interface class MembershipAdminRepository {
  Future<MembershipAdminResult<List<WorkspaceMember>>> listMembers({
    required String workspaceId,
  });

  Future<MembershipAdminResult<List<WorkspaceRole>>> listRoles({
    required String workspaceId,
  });

  Future<MembershipAdminResult<List<MembershipInvitation>>> listInvitations({
    required String workspaceId,
    bool includeResolved = false,
  });

  Future<MembershipAdminResult<List<PendingInvitationEntry>>>
  listMyPendingInvitations();

  Future<MembershipAdminResult<InviteOutcome>> invite(
    InviteMemberCommand command,
  );

  Future<MembershipAdminResult<WorkspaceMember>> accept(
    AcceptInvitationCommand command,
  );

  Future<MembershipAdminResult<WorkspaceMember>> updateStatus(
    UpdateMembershipStatusCommand command,
  );

  Future<MembershipAdminResult<WorkspaceMember>> changeRole(
    ChangeMembershipRoleCommand command,
  );

  Future<MembershipAdminResult<MembershipInvitation>> revokeInvitation(
    RevokeInvitationCommand command,
  );
}
