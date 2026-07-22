import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/authorization_port.dart';
import 'package:neximmo_app/features/identity_access/application/membership_admin_repository.dart';
import 'package:neximmo_app/features/reference_slice/application/members_admin_controller.dart';

void main() {
  group('MembersAdminController', () {
    late _FakeMembershipAdminRepository repository;

    setUp(() {
      repository = _FakeMembershipAdminRepository();
    });

    MembersAdminController controller({
      String? workspaceId = 'workspace-a',
      Set<String> permissions = const <String>{'security.manage'},
      bool canMutate = true,
    }) {
      var counter = 0;
      return MembersAdminController(
        repository: repository,
        actorId: 'actor-a',
        authorization: PermissionSetAuthorizationPort(permissions),
        canMutate: canMutate,
        workspaceId: workspaceId,
        idFactory: () => 'id-${counter++}',
      );
    }

    test('reports manage capability via the authorization port', () {
      expect(controller().canManageMembers, isTrue);
      expect(
        controller(permissions: const <String>{'property.read'})
            .canManageMembers,
        isFalse,
      );
      expect(controller(workspaceId: null).canManageMembers, isFalse);
    });

    test('load populates the directory and pending zones for a manager', () async {
      repository.directory = <WorkspaceMemberDirectoryEntry>[_entry()];
      repository.pending = <PendingInvitationEntry>[_pending()];

      final subject = controller();
      await subject.load();

      expect(subject.state.directoryPhase, MembersDirectoryPhase.ready);
      expect(subject.state.directory, hasLength(1));
      expect(subject.state.pendingPhase, MembersPendingPhase.ready);
      expect(repository.directoryCalls, 1);
    });

    test('load forbids the directory without security.manage', () async {
      final subject = controller(permissions: const <String>{'property.read'});
      await subject.load();

      expect(subject.state.directoryPhase, MembersDirectoryPhase.forbidden);
      // The forbidden directory short-circuits before hitting the RPC.
      expect(repository.directoryCalls, 0);
    });

    test('load leaves the directory idle without a workspace', () async {
      repository.pending = <PendingInvitationEntry>[_pending()];

      final subject = controller(workspaceId: null);
      await subject.load();

      expect(subject.state.directoryPhase, MembersDirectoryPhase.idle);
      expect(subject.state.pendingPhase, MembersPendingPhase.ready);
      expect(repository.directoryCalls, 0);
    });

    test('blocks a mutation with a forbidden action when AAL2 is missing', () async {
      final subject = controller(canMutate: false);

      await subject.invite(email: 'x@example.test', roleId: 'role-a');

      expect(subject.state.actionPhase, MembersActionPhase.forbidden);
      expect(repository.inviteCalls, 0);
    });

    test('invites through the repository and reloads the directory', () async {
      final subject = controller();
      await subject.load();
      repository.directoryCalls = 0;

      await subject.invite(email: 'x@example.test', roleId: 'role-a');

      expect(repository.inviteCalls, 1);
      expect(subject.state.actionPhase, MembersActionPhase.succeeded);
      // Success triggers a directory refresh.
      expect(repository.directoryCalls, 1);
    });

    test('surfaces a version conflict as a conflict action', () async {
      repository.updateStatusResult = MembershipAdminFailure<WorkspaceMember>(
        kind: MembershipAdminFailureKind.versionConflict,
        message: 'stale',
        versionConflict: MembershipVersionConflict(
          expectedVersion: 1,
          actualVersion: 3,
          currentMember: _member(),
        ),
      );

      final subject = controller();
      await subject.updateStatus(
        membershipId: 'membership-a',
        newStatus: MembershipStatus.suspended,
        expectedVersion: 1,
      );

      expect(subject.state.actionPhase, MembersActionPhase.conflict);
    });

    test('accepts an own invitation through the repository', () async {
      final subject = controller(workspaceId: null);
      await subject.load();

      await subject.acceptOwnInvitation(_pending());

      expect(repository.acceptCalls, 1);
      expect(subject.state.actionPhase, MembersActionPhase.succeeded);
    });
  });
}

WorkspaceMemberDirectoryEntry _entry() {
  return WorkspaceMemberDirectoryEntry(
    membershipId: 'membership-a',
    workspaceId: 'workspace-a',
    userId: 'user-a',
    roleId: 'role-a',
    roleKey: 'manager',
    roleName: 'Manager',
    status: MembershipStatus.active,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 2),
    version: 1,
    displayName: 'Admin',
    email: 'admin@example.test',
  );
}

WorkspaceMember _member() {
  return WorkspaceMember(
    membershipId: 'membership-a',
    workspaceId: 'workspace-a',
    userId: 'user-a',
    roleId: 'role-a',
    status: MembershipStatus.suspended,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 2),
    version: 3,
  );
}

PendingInvitationEntry _pending() {
  return PendingInvitationEntry(
    isMembership: true,
    workspaceId: 'workspace-a',
    workspaceName: 'Workspace A',
    roleKey: 'viewer',
    roleName: 'Viewer',
    createdAt: DateTime.utc(2026, 7, 3),
    version: 1,
    membershipId: 'membership-self',
  );
}

class _FakeMembershipAdminRepository implements MembershipAdminRepository {
  List<WorkspaceMemberDirectoryEntry> directory =
      const <WorkspaceMemberDirectoryEntry>[];
  List<PendingInvitationEntry> pending = const <PendingInvitationEntry>[];
  List<WorkspaceRole> roles = const <WorkspaceRole>[];
  List<MembershipInvitation> invitations = const <MembershipInvitation>[];
  MembershipAdminResult<WorkspaceMember>? updateStatusResult;

  int directoryCalls = 0;
  int inviteCalls = 0;
  int acceptCalls = 0;

  @override
  Future<MembershipAdminResult<List<WorkspaceMemberDirectoryEntry>>>
  listMemberDirectory({required String workspaceId}) async {
    directoryCalls++;
    return MembershipAdminSuccess<List<WorkspaceMemberDirectoryEntry>>(
      directory,
    );
  }

  @override
  Future<MembershipAdminResult<List<PendingInvitationEntry>>>
  listMyPendingInvitations() async {
    return MembershipAdminSuccess<List<PendingInvitationEntry>>(pending);
  }

  @override
  Future<MembershipAdminResult<List<WorkspaceRole>>> listRoles({
    required String workspaceId,
  }) async {
    return MembershipAdminSuccess<List<WorkspaceRole>>(roles);
  }

  @override
  Future<MembershipAdminResult<List<MembershipInvitation>>> listInvitations({
    required String workspaceId,
    bool includeResolved = false,
  }) async {
    return MembershipAdminSuccess<List<MembershipInvitation>>(invitations);
  }

  @override
  Future<MembershipAdminResult<List<WorkspaceMember>>> listMembers({
    required String workspaceId,
  }) async {
    return const MembershipAdminSuccess<List<WorkspaceMember>>(
      <WorkspaceMember>[],
    );
  }

  @override
  Future<MembershipAdminResult<InviteOutcome>> invite(
    InviteMemberCommand command,
  ) async {
    inviteCalls++;
    return MembershipAdminSuccess<InviteOutcome>(
      InviteOutcome(
        invitation: MembershipInvitation(
          id: 'invitation-new',
          workspaceId: command.context.workspaceId,
          email: command.email,
          roleId: command.roleId,
          status: MembershipInvitationStatus.pending,
          createdAt: DateTime.utc(2026, 7, 7),
          updatedAt: DateTime.utc(2026, 7, 7),
          version: 1,
        ),
      ),
    );
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> accept(
    AcceptInvitationCommand command,
  ) async {
    acceptCalls++;
    return MembershipAdminSuccess<WorkspaceMember>(_member());
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> updateStatus(
    UpdateMembershipStatusCommand command,
  ) async {
    return updateStatusResult ??
        MembershipAdminSuccess<WorkspaceMember>(_member());
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> changeRole(
    ChangeMembershipRoleCommand command,
  ) async {
    return MembershipAdminSuccess<WorkspaceMember>(_member());
  }

  @override
  Future<MembershipAdminResult<MembershipInvitation>> revokeInvitation(
    RevokeInvitationCommand command,
  ) async {
    return MembershipAdminSuccess<MembershipInvitation>(
      MembershipInvitation(
        id: command.invitationId,
        workspaceId: command.context.workspaceId,
        email: 'x@example.test',
        roleId: 'role-a',
        status: MembershipInvitationStatus.revoked,
        createdAt: DateTime.utc(2026, 7, 7),
        updatedAt: DateTime.utc(2026, 7, 8),
        version: command.expectedVersion + 1,
      ),
    );
  }
}
