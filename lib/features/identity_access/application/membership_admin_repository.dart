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

/// One row of the workspace member directory: a [WorkspaceMember] enriched
/// with the display name (public.user_profiles) and email (auth.users) that
/// row-level security cannot expose to the client directly, plus the resolved
/// role key/name. Populated by the `security.manage`-gated
/// `list_workspace_members` RPC.
class WorkspaceMemberDirectoryEntry {
  const WorkspaceMemberDirectoryEntry({
    required this.membershipId,
    required this.workspaceId,
    required this.userId,
    required this.roleId,
    required this.roleKey,
    required this.roleName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.displayName,
    this.email,
  });

  final String membershipId;
  final String workspaceId;
  final String userId;
  final String roleId;
  final String roleKey;
  final String roleName;
  final MembershipStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final String? displayName;
  final String? email;
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

/// One role→capability assignment of the workspace's permission catalog
/// (`role_permissions` joined with `permissions`). Read-only: roles and their
/// capabilities are maintained centrally (PERMISSION-CATALOG-02), never
/// through this contract.
class WorkspaceRoleCapability {
  const WorkspaceRoleCapability({
    required this.roleId,
    required this.permissionKey,
    required this.permissionName,
  });

  final String roleId;
  final String permissionKey;
  final String permissionName;
}

/// One membership-related audit event (`audit_events` rows with entity_type
/// `membership`/`membership_invitation`), reduced to the fields the Aktivität
/// tab presents. Target/role extracts are pulled defensively from the event
/// snapshots — raw payloads never reach the UI.
class MembershipAuditEvent {
  const MembershipAuditEvent({
    required this.id,
    required this.workspaceId,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.entityId,
    this.actorUserId,
    this.actorRoleKey,
    this.reason,
    this.targetUserId,
    this.targetEmail,
    this.oldRoleId,
    this.newRoleId,
  });

  final String id;
  final String workspaceId;

  /// The stored action key, e.g. `membership.role_change`. Presentation maps
  /// known keys to German copy and renders unknown-but-real keys neutrally.
  final String action;
  final String entityType;
  final DateTime createdAt;
  final String? entityId;
  final String? actorUserId;
  final String? actorRoleKey;
  final String? reason;
  final String? targetUserId;
  final String? targetEmail;
  final String? oldRoleId;
  final String? newRoleId;
}

/// Opaque keyset cursor over `(created_at desc, id desc)`. [createdAt] keeps
/// the server's raw timestamp representation so the follow-up filter compares
/// exactly what the server returned.
class MembershipAuditCursor {
  const MembershipAuditCursor({required this.createdAt, required this.id});

  final String createdAt;
  final String id;

  @override
  bool operator ==(Object other) {
    return other is MembershipAuditCursor &&
        other.createdAt == createdAt &&
        other.id == id;
  }

  @override
  int get hashCode => Object.hash(createdAt, id);
}

class MembershipAuditPage {
  const MembershipAuditPage({required this.events, this.nextCursor});

  final List<MembershipAuditEvent> events;

  /// Null when this page ends the feed.
  final MembershipAuditCursor? nextCursor;
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

  /// The full member directory (name/email/role/status) for an admin console.
  /// Server-gated on `security.manage`; a caller without it fails with
  /// [MembershipAdminFailureKind.forbidden] rather than an empty list.
  Future<MembershipAdminResult<List<WorkspaceMemberDirectoryEntry>>>
  listMemberDirectory({required String workspaceId});

  Future<MembershipAdminResult<List<WorkspaceRole>>> listRoles({
    required String workspaceId,
  });

  /// The workspace's role→capability assignments. Row-level security gates
  /// the read on `workspace.read` (at AAL2); a caller below that sees an
  /// empty list, matching the RLS filter semantics of the underlying tables.
  Future<MembershipAdminResult<List<WorkspaceRoleCapability>>>
  listRolePermissions({required String workspaceId});

  /// One keyset page of membership audit events, newest first
  /// (`created_at desc, id desc`; [before] continues after a prior page's
  /// cursor). Row-level security gates the read on `audit.read` (at AAL2);
  /// a caller below that sees an empty page, so callers pre-check the
  /// capability for an honest forbidden state.
  Future<MembershipAdminResult<MembershipAuditPage>> listMembershipAuditEvents({
    required String workspaceId,
    int limit = 50,
    MembershipAuditCursor? before,
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
