import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/authorization_port.dart';
import 'package:neximmo_app/features/identity_access/application/members_admin_controller.dart';
import 'package:neximmo_app/features/identity_access/application/membership_admin_repository.dart';

/// ADMIN-AREA-01 A1: the members admin controller drives the V2 screen with
/// independent tab phases (Mitglieder / Einladungen / Rollen), a preserved
/// own-invitations zone, AAL2/capability gating, German action feedback and a
/// version-conflict payload that reaches the dialogs instead of being
/// flattened away.
void main() {
  const workspaceId = 'ws-1';
  const actorId = 'user-1';

  MembersAdminController buildController({
    required _FakeMembershipAdminRepository repository,
    Set<String> permissions = const <String>{
      'security.manage',
      'workspace.read',
    },
    bool canMutate = true,
    String? workspace = workspaceId,
  }) {
    var counter = 0;
    return MembersAdminController(
      repository: repository,
      actorId: actorId,
      authorization: PermissionSetAuthorizationPort(permissions),
      canMutate: canMutate,
      workspaceId: workspace,
      idFactory: () => 'id-${counter++}',
    );
  }

  group('load', () {
    test('populates all four zones independently', () async {
      final repository =
          _FakeMembershipAdminRepository()
            ..directory = <WorkspaceMemberDirectoryEntry>[_entry('m-1')]
            ..roles = <WorkspaceRole>[_role('role-admin')]
            ..roleCapabilities = <WorkspaceRoleCapability>[
              _capability('role-admin', 'security.manage'),
            ]
            ..invitations = <MembershipInvitation>[_invitation('inv-1')]
            ..pending = <PendingInvitationEntry>[_pendingEntry()];
      final controller = buildController(repository: repository);
      await controller.load();

      expect(controller.state.directoryPhase, MembersTabPhase.ready);
      expect(controller.state.invitationsPhase, MembersTabPhase.ready);
      expect(controller.state.rolesPhase, MembersTabPhase.ready);
      expect(controller.state.pendingPhase, MembersPendingPhase.ready);
      expect(controller.state.directory, hasLength(1));
      expect(controller.state.invitations, hasLength(1));
      expect(controller.state.roles, hasLength(1));
      expect(controller.state.roleCapabilities, hasLength(1));
      expect(controller.state.pending, hasLength(1));
    });

    test('empty results map to empty phases', () async {
      final repository = _FakeMembershipAdminRepository();
      final controller = buildController(repository: repository);
      await controller.load();

      expect(controller.state.directoryPhase, MembersTabPhase.empty);
      expect(controller.state.invitationsPhase, MembersTabPhase.empty);
      expect(controller.state.pendingPhase, MembersPendingPhase.empty);
      // Roles: an empty role list still renders as empty, not as an error.
      expect(controller.state.rolesPhase, MembersTabPhase.empty);
    });

    test(
      'no workspace leaves the admin zones idle but loads pending',
      () async {
        final repository =
            _FakeMembershipAdminRepository()
              ..pending = <PendingInvitationEntry>[_pendingEntry()];
        final controller = buildController(
          repository: repository,
          workspace: null,
        );
        await controller.load();

        expect(controller.state.directoryPhase, MembersTabPhase.idle);
        expect(controller.state.invitationsPhase, MembersTabPhase.idle);
        expect(controller.state.rolesPhase, MembersTabPhase.idle);
        expect(controller.state.pendingPhase, MembersPendingPhase.ready);
        expect(repository.directoryCalls, 0);
      },
    );

    test(
      'missing security.manage fails the directory closed without a call',
      () async {
        final repository = _FakeMembershipAdminRepository();
        final controller = buildController(
          repository: repository,
          permissions: const <String>{'workspace.read'},
        );
        await controller.load();

        expect(controller.state.directoryPhase, MembersTabPhase.forbidden);
        expect(controller.state.invitationsPhase, MembersTabPhase.forbidden);
        expect(repository.directoryCalls, 0);
        expect(repository.invitationsCalls, 0);
      },
    );

    test(
      'missing workspace.read fails the roles tab closed without a call',
      () async {
        final repository =
            _FakeMembershipAdminRepository()
              ..directory = <WorkspaceMemberDirectoryEntry>[_entry('m-1')];
        final controller = buildController(
          repository: repository,
          permissions: const <String>{'security.manage'},
        );
        await controller.load();

        expect(controller.state.rolesPhase, MembersTabPhase.forbidden);
        expect(repository.rolesCalls, 0);
        expect(repository.rolePermissionsCalls, 0);
        expect(controller.state.directoryPhase, MembersTabPhase.ready);
      },
    );

    test(
      'server forbidden on the directory maps to the forbidden phase',
      () async {
        final repository =
            _FakeMembershipAdminRepository()
              ..directoryResult = const MembershipAdminFailure<
                List<WorkspaceMemberDirectoryEntry>
              >(
                kind: MembershipAdminFailureKind.forbidden,
                message: 'Member directory access is not permitted',
              );
        final controller = buildController(repository: repository);
        await controller.load();

        expect(controller.state.directoryPhase, MembersTabPhase.forbidden);
      },
    );

    test('a broken roles read does not block the directory', () async {
      final repository =
          _FakeMembershipAdminRepository()
            ..directory = <WorkspaceMemberDirectoryEntry>[_entry('m-1')]
            ..rolesResult = const MembershipAdminFailure<List<WorkspaceRole>>(
              kind: MembershipAdminFailureKind.infrastructureFailure,
              message: 'boom',
            );
      final controller = buildController(repository: repository);
      await controller.load();

      expect(controller.state.directoryPhase, MembersTabPhase.ready);
      expect(controller.state.rolesPhase, MembersTabPhase.error);
    });

    test(
      'a broken role-permissions read fails the roles tab, not the rest',
      () async {
        final repository =
            _FakeMembershipAdminRepository()
              ..directory = <WorkspaceMemberDirectoryEntry>[_entry('m-1')]
              ..roles = <WorkspaceRole>[_role('role-admin')]
              ..rolePermissionsResult =
                  const MembershipAdminFailure<List<WorkspaceRoleCapability>>(
                    kind: MembershipAdminFailureKind.infrastructureFailure,
                    message: 'boom',
                  );
        final controller = buildController(repository: repository);
        await controller.load();

        expect(controller.state.rolesPhase, MembersTabPhase.error);
        expect(controller.state.directoryPhase, MembersTabPhase.ready);
        expect(controller.state.invitationsPhase, MembersTabPhase.empty);
      },
    );

    test('a broken invitations read fails only the invitations tab', () async {
      final repository =
          _FakeMembershipAdminRepository()
            ..directory = <WorkspaceMemberDirectoryEntry>[_entry('m-1')]
            ..invitationsResult =
                const MembershipAdminFailure<List<MembershipInvitation>>(
                  kind: MembershipAdminFailureKind.infrastructureFailure,
                  message: 'boom',
                );
      final controller = buildController(repository: repository);
      await controller.load();

      expect(controller.state.invitationsPhase, MembersTabPhase.error);
      expect(controller.state.directoryPhase, MembersTabPhase.ready);
    });

    test('stale directory loads are dropped by the generation guard', () async {
      final repository =
          _FakeMembershipAdminRepository()
            ..directory = <WorkspaceMemberDirectoryEntry>[_entry('m-old')];
      final gate = Completer<void>();
      repository.directoryGate = gate.future;
      final controller = buildController(repository: repository);

      final first = controller.reloadDirectory();
      repository
        ..directoryGate = null
        ..directory = <WorkspaceMemberDirectoryEntry>[_entry('m-new')];
      final second = controller.reloadDirectory();
      gate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(controller.state.directory.single.membershipId, 'm-new');
    });
  });

  group('background refresh', () {
    test(
      'keeps ready data visible instead of blanking to a skeleton',
      () async {
        final repository =
            _FakeMembershipAdminRepository()
              ..directory = <WorkspaceMemberDirectoryEntry>[_entry('m-1')];
        final controller = buildController(repository: repository);
        await controller.load();
        expect(controller.state.directoryPhase, MembersTabPhase.ready);

        final gate = Completer<void>();
        repository.directoryGate = gate.future;
        final refresh = controller.refreshAll();
        expect(controller.state.directoryPhase, MembersTabPhase.ready);
        expect(controller.state.refreshing, isTrue);
        gate.complete();
        await refresh;

        expect(controller.state.refreshing, isFalse);
        expect(controller.state.directoryPhase, MembersTabPhase.ready);
      },
    );
  });

  group('mutation gates', () {
    test(
      'below AAL2 mutations are blocked with a German explanation',
      () async {
        final repository = _FakeMembershipAdminRepository();
        final controller = buildController(
          repository: repository,
          canMutate: false,
        );
        await controller.load();

        final outcome = await controller.invite(
          email: 'a@b.de',
          roleId: 'role-admin',
        );

        expect(outcome.kind, MembersActionResultKind.forbidden);
        expect(outcome.message, contains('AAL2'));
        expect(controller.state.actionPhase, MembersActionPhase.forbidden);
        expect(repository.inviteCalls, 0);
      },
    );

    test('without security.manage mutations are refused client-side', () async {
      final repository = _FakeMembershipAdminRepository();
      final controller = buildController(
        repository: repository,
        permissions: const <String>{'workspace.read'},
      );
      await controller.load();

      final outcome = await controller.updateStatus(
        membershipId: 'm-1',
        newStatus: MembershipStatus.suspended,
        expectedVersion: 1,
      );

      expect(outcome.kind, MembersActionResultKind.forbidden);
      expect(repository.updateStatusCalls, 0);
    });
  });

  group('invite', () {
    test('membership outcome reloads directory and invitations', () async {
      final repository =
          _FakeMembershipAdminRepository()
            ..inviteResult = MembershipAdminSuccess<InviteOutcome>(
              InviteOutcome(member: _member('m-9')),
            );
      final controller = buildController(repository: repository);
      await controller.load();
      final directoryCallsBefore = repository.directoryCalls;
      final invitationCallsBefore = repository.invitationsCalls;

      final outcome = await controller.invite(
        email: 'neu@neximmo.de',
        roleId: 'role-admin',
        reason: 'Onboarding',
      );

      expect(outcome.kind, MembersActionResultKind.success);
      expect(outcome.message, contains('neu@neximmo.de'));
      expect(controller.state.actionPhase, MembersActionPhase.succeeded);
      expect(repository.directoryCalls, directoryCallsBefore + 1);
      expect(repository.invitationsCalls, invitationCallsBefore + 1);
      expect(repository.lastInviteCommand?.context.reason, 'Onboarding');
    });

    test(
      'email-invitation outcome also succeeds with the email named',
      () async {
        final repository =
            _FakeMembershipAdminRepository()
              ..inviteResult = MembershipAdminSuccess<InviteOutcome>(
                InviteOutcome(invitation: _invitation('inv-9')),
              );
        final controller = buildController(repository: repository);
        await controller.load();

        final outcome = await controller.invite(
          email: 'extern@neximmo.de',
          roleId: 'role-viewer',
        );

        expect(outcome.kind, MembersActionResultKind.success);
        expect(outcome.message, contains('extern@neximmo.de'));
      },
    );

    test(
      'duplicate membership maps to a German inline validation message',
      () async {
        final repository =
            _FakeMembershipAdminRepository()
              ..inviteResult = const MembershipAdminFailure<InviteOutcome>(
                kind: MembershipAdminFailureKind.validationFailed,
                message: 'The user already has a membership in this workspace',
              );
        final controller = buildController(repository: repository);
        await controller.load();

        final outcome = await controller.invite(
          email: 'a@b.de',
          roleId: 'role-admin',
        );

        expect(outcome.kind, MembersActionResultKind.validationFailed);
        expect(outcome.message, contains('bereits eine Mitgliedschaft'));
        expect(
          controller.state.actionPhase,
          MembersActionPhase.validationFailed,
        );
      },
    );

    test('duplicate invitation maps to its own German message', () async {
      final repository =
          _FakeMembershipAdminRepository()
            ..inviteResult = const MembershipAdminFailure<InviteOutcome>(
              kind: MembershipAdminFailureKind.validationFailed,
              message: 'A pending invitation for this email already exists',
            );
      final controller = buildController(repository: repository);
      await controller.load();

      final outcome = await controller.invite(
        email: 'a@b.de',
        roleId: 'role-admin',
      );

      expect(outcome.kind, MembersActionResultKind.validationFailed);
      expect(outcome.message, contains('bereits eine offene Einladung'));
    });
  });

  group('change role', () {
    test(
      'version conflict carries the payload and keeps the conflict phase',
      () async {
        final conflict = MembershipVersionConflict(
          expectedVersion: 1,
          actualVersion: 4,
          currentMember: _member('m-1', version: 4),
        );
        final repository =
            _FakeMembershipAdminRepository()
              ..directory = <WorkspaceMemberDirectoryEntry>[_entry('m-1')]
              ..changeRoleResult = MembershipAdminFailure<WorkspaceMember>(
                kind: MembershipAdminFailureKind.versionConflict,
                message: 'Membership version is stale',
                versionConflict: conflict,
              );
        final controller = buildController(repository: repository);
        await controller.load();
        final directoryCallsBefore = repository.directoryCalls;

        final outcome = await controller.changeRole(
          membershipId: 'm-1',
          newRoleId: 'role-viewer',
          expectedVersion: 1,
        );

        expect(outcome.kind, MembersActionResultKind.versionConflict);
        expect(outcome.conflict?.actualVersion, 4);
        expect(outcome.conflict?.currentMember?.membershipId, 'm-1');
        expect(controller.state.actionPhase, MembersActionPhase.conflict);
        expect(controller.state.actionConflict?.actualVersion, 4);
        expect(repository.directoryCalls, directoryCallsBefore + 1);
      },
    );

    test(
      'the last-security-manager refusal is classified and translated',
      () async {
        final repository =
            _FakeMembershipAdminRepository()
              ..changeRoleResult = const MembershipAdminFailure<
                WorkspaceMember
              >(
                kind: MembershipAdminFailureKind.validationFailed,
                message:
                    'The last active security manager of a workspace cannot lose '
                    'the managing role',
              );
        final controller = buildController(repository: repository);
        await controller.load();

        final outcome = await controller.changeRole(
          membershipId: 'm-1',
          newRoleId: 'role-viewer',
          expectedVersion: 1,
        );

        expect(outcome.kind, MembersActionResultKind.lastSecurityManager);
        expect(outcome.message, contains('Sicherheitsverwaltung'));
        expect(
          controller.state.actionPhase,
          MembersActionPhase.validationFailed,
        );
      },
    );
  });

  group('status transitions', () {
    test(
      'suspend, reactivate and revoke succeed with German feedback',
      () async {
        final repository =
            _FakeMembershipAdminRepository()
              ..updateStatusResult = MembershipAdminSuccess<WorkspaceMember>(
                _member('m-1', version: 2),
              );
        final controller = buildController(repository: repository);
        await controller.load();

        final suspended = await controller.updateStatus(
          membershipId: 'm-1',
          newStatus: MembershipStatus.suspended,
          expectedVersion: 1,
        );
        final reactivated = await controller.updateStatus(
          membershipId: 'm-1',
          newStatus: MembershipStatus.active,
          expectedVersion: 2,
        );
        final revoked = await controller.updateStatus(
          membershipId: 'm-1',
          newStatus: MembershipStatus.revoked,
          expectedVersion: 3,
        );

        expect(suspended.kind, MembersActionResultKind.success);
        expect(suspended.message, contains('suspendiert'));
        expect(reactivated.message, contains('reaktiviert'));
        expect(revoked.message, contains('entzogen'));
        expect(repository.updateStatusCalls, 3);
      },
    );

    test('the suspend/revoke last-manager refusal is classified too', () async {
      final repository =
          _FakeMembershipAdminRepository()
            ..updateStatusResult = const MembershipAdminFailure<
              WorkspaceMember
            >(
              kind: MembershipAdminFailureKind.validationFailed,
              message:
                  'The last active security manager of a workspace cannot be '
                  'suspended or revoked',
            );
      final controller = buildController(repository: repository);
      await controller.load();

      final outcome = await controller.updateStatus(
        membershipId: 'm-1',
        newStatus: MembershipStatus.suspended,
        expectedVersion: 1,
      );

      expect(outcome.kind, MembersActionResultKind.lastSecurityManager);
    });
  });

  group('revoke invitation', () {
    test('success reloads the invitations zone', () async {
      final repository =
          _FakeMembershipAdminRepository()
            ..revokeInvitationResult =
                MembershipAdminSuccess<MembershipInvitation>(
                  _invitation('inv-1'),
                );
      final controller = buildController(repository: repository);
      await controller.load();
      final invitationCallsBefore = repository.invitationsCalls;

      final outcome = await controller.revokeInvitation(
        invitationId: 'inv-1',
        expectedVersion: 1,
      );

      expect(outcome.kind, MembersActionResultKind.success);
      expect(repository.invitationsCalls, invitationCallsBefore + 1);
    });

    test(
      'a conflict reloads the invitations and reports the conflict',
      () async {
        final repository =
            _FakeMembershipAdminRepository()
              ..revokeInvitationResult =
                  MembershipAdminFailure<MembershipInvitation>(
                    kind: MembershipAdminFailureKind.versionConflict,
                    message: 'Invitation version is stale',
                    versionConflict: MembershipVersionConflict(
                      expectedVersion: 1,
                      actualVersion: 2,
                      currentInvitation: _invitation('inv-1', version: 2),
                    ),
                  );
        final controller = buildController(repository: repository);
        await controller.load();
        final invitationCallsBefore = repository.invitationsCalls;

        final outcome = await controller.revokeInvitation(
          invitationId: 'inv-1',
          expectedVersion: 1,
        );

        expect(outcome.kind, MembersActionResultKind.versionConflict);
        expect(repository.invitationsCalls, invitationCallsBefore + 1);
      },
    );
  });

  group('own invitations (accept zone stays until package B)', () {
    test('accepting requires AAL2', () async {
      final repository = _FakeMembershipAdminRepository();
      final controller = buildController(
        repository: repository,
        canMutate: false,
      );
      await controller.load();

      final outcome = await controller.acceptOwnInvitation(_pendingEntry());

      expect(outcome.kind, MembersActionResultKind.forbidden);
      expect(repository.acceptCalls, 0);
    });

    test('accepting succeeds and reloads pending and admin zones', () async {
      final repository =
          _FakeMembershipAdminRepository()
            ..acceptResult = MembershipAdminSuccess<WorkspaceMember>(
              _member('m-1'),
            );
      final controller = buildController(repository: repository);
      await controller.load();
      final pendingCallsBefore = repository.pendingCalls;

      final outcome = await controller.acceptOwnInvitation(_pendingEntry());

      expect(outcome.kind, MembersActionResultKind.success);
      expect(repository.acceptCalls, 1);
      expect(repository.pendingCalls, pendingCallsBefore + 1);
    });
  });

  test('clearAction resets action state', () async {
    final repository = _FakeMembershipAdminRepository();
    final controller = buildController(
      repository: repository,
      canMutate: false,
    );
    await controller.load();
    await controller.invite(email: 'a@b.de', roleId: 'r');
    expect(controller.state.actionPhase, MembersActionPhase.forbidden);

    controller.clearAction();

    expect(controller.state.actionPhase, MembersActionPhase.idle);
    expect(controller.state.actionMessage, isNull);
    expect(controller.state.actionConflict, isNull);
  });

  group('filterMemberDirectory', () {
    final entries = <WorkspaceMemberDirectoryEntry>[
      _entry('m-1', name: 'Clara Admin', email: 'clara@x.de'),
      _entry(
        'm-2',
        name: 'Ben Viewer',
        email: 'ben@x.de',
        roleId: 'role-viewer',
      ),
      _entry(
        'm-3',
        name: 'Alte Nutzerin',
        email: 'alt@x.de',
        status: MembershipStatus.revoked,
      ),
      _entry(
        'm-4',
        name: null,
        email: 'zzz@x.de',
        status: MembershipStatus.suspended,
      ),
    ];

    test('hides revoked members by default', () {
      final filtered = filterMemberDirectory(entries);
      expect(
        filtered.map((entry) => entry.membershipId),
        isNot(contains('m-3')),
      );
      expect(filtered, hasLength(3));
    });

    test('an explicit revoked status filter shows only revoked members', () {
      final filtered = filterMemberDirectory(
        entries,
        status: MembershipStatus.revoked,
      );
      expect(filtered.map((entry) => entry.membershipId), <String>['m-3']);
    });

    test('filters by role', () {
      final filtered = filterMemberDirectory(entries, roleId: 'role-viewer');
      expect(filtered.map((entry) => entry.membershipId), <String>['m-2']);
    });

    test('searches name and email case-insensitively', () {
      expect(
        filterMemberDirectory(entries, query: 'CLARA').single.membershipId,
        'm-1',
      );
      expect(
        filterMemberDirectory(entries, query: 'zzz@').single.membershipId,
        'm-4',
      );
    });

    test('sorts by display name with email fallback', () {
      final filtered = filterMemberDirectory(entries);
      expect(filtered.first.membershipId, 'm-2');
      expect(filtered.last.membershipId, 'm-4');
    });
  });

  group('computeRoleCapabilityDiff', () {
    test('reports added and removed capabilities by key', () {
      final from = <WorkspaceRoleCapability>[
        _capability('role-admin', 'security.manage'),
        _capability('role-admin', 'property.read'),
      ];
      final to = <WorkspaceRoleCapability>[
        _capability('role-viewer', 'property.read'),
        _capability('role-viewer', 'workspace.read'),
      ];

      final diff = computeRoleCapabilityDiff(from: from, to: to);

      expect(diff.added.map((capability) => capability.permissionKey), <String>[
        'workspace.read',
      ]);
      expect(
        diff.removed.map((capability) => capability.permissionKey),
        <String>['security.manage'],
      );
    });
  });
}

WorkspaceMemberDirectoryEntry _entry(
  String membershipId, {
  String? name = 'Mitglied',
  String? email = 'mitglied@neximmo.de',
  String roleId = 'role-admin',
  MembershipStatus status = MembershipStatus.active,
  int version = 1,
}) {
  return WorkspaceMemberDirectoryEntry(
    membershipId: membershipId,
    workspaceId: 'ws-1',
    userId: 'user-$membershipId',
    roleId: roleId,
    roleKey: roleId,
    roleName: roleId,
    status: status,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
    version: version,
    displayName: name,
    email: email,
  );
}

WorkspaceMember _member(String membershipId, {int version = 1}) {
  return WorkspaceMember(
    membershipId: membershipId,
    workspaceId: 'ws-1',
    userId: 'user-$membershipId',
    roleId: 'role-admin',
    status: MembershipStatus.active,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
    version: version,
  );
}

MembershipInvitation _invitation(
  String id, {
  String email = 'gast@neximmo.de',
  int version = 1,
}) {
  return MembershipInvitation(
    id: id,
    workspaceId: 'ws-1',
    email: email,
    roleId: 'role-viewer',
    status: MembershipInvitationStatus.pending,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    version: version,
  );
}

WorkspaceRole _role(String id) {
  return WorkspaceRole(id: id, workspaceId: 'ws-1', key: id, name: id);
}

WorkspaceRoleCapability _capability(String roleId, String key) {
  return WorkspaceRoleCapability(
    roleId: roleId,
    permissionKey: key,
    permissionName: key,
  );
}

PendingInvitationEntry _pendingEntry() {
  return PendingInvitationEntry(
    isMembership: true,
    workspaceId: 'ws-2',
    workspaceName: 'Workspace Zwei',
    roleKey: 'viewer',
    roleName: 'Viewer',
    createdAt: DateTime.utc(2026, 1, 1),
    version: 1,
    membershipId: 'm-pending',
  );
}

class _FakeMembershipAdminRepository implements MembershipAdminRepository {
  List<WorkspaceMemberDirectoryEntry> directory =
      <WorkspaceMemberDirectoryEntry>[];
  List<WorkspaceRole> roles = <WorkspaceRole>[];
  List<WorkspaceRoleCapability> roleCapabilities = <WorkspaceRoleCapability>[];
  List<MembershipInvitation> invitations = <MembershipInvitation>[];
  List<PendingInvitationEntry> pending = <PendingInvitationEntry>[];

  MembershipAdminResult<List<WorkspaceMemberDirectoryEntry>>? directoryResult;
  MembershipAdminResult<List<WorkspaceRole>>? rolesResult;
  MembershipAdminResult<List<WorkspaceRoleCapability>>? rolePermissionsResult;
  MembershipAdminResult<List<MembershipInvitation>>? invitationsResult;
  MembershipAdminResult<List<PendingInvitationEntry>>? pendingResult;
  MembershipAdminResult<InviteOutcome>? inviteResult;
  MembershipAdminResult<WorkspaceMember>? acceptResult;
  MembershipAdminResult<WorkspaceMember>? updateStatusResult;
  MembershipAdminResult<WorkspaceMember>? changeRoleResult;
  MembershipAdminResult<MembershipInvitation>? revokeInvitationResult;

  Future<void>? directoryGate;

  int directoryCalls = 0;
  int rolesCalls = 0;
  int rolePermissionsCalls = 0;
  int invitationsCalls = 0;
  int pendingCalls = 0;
  int inviteCalls = 0;
  int acceptCalls = 0;
  int updateStatusCalls = 0;
  int changeRoleCalls = 0;
  int revokeInvitationCalls = 0;

  InviteMemberCommand? lastInviteCommand;

  @override
  Future<MembershipAdminResult<List<WorkspaceMember>>> listMembers({
    required String workspaceId,
  }) async {
    return const MembershipAdminSuccess<List<WorkspaceMember>>(
      <WorkspaceMember>[],
    );
  }

  @override
  Future<MembershipAdminResult<List<WorkspaceMemberDirectoryEntry>>>
  listMemberDirectory({required String workspaceId}) async {
    directoryCalls += 1;
    final gate = directoryGate;
    if (gate != null) {
      await gate;
    }
    return directoryResult ??
        MembershipAdminSuccess<List<WorkspaceMemberDirectoryEntry>>(
          List<WorkspaceMemberDirectoryEntry>.from(directory),
        );
  }

  @override
  Future<MembershipAdminResult<List<WorkspaceRole>>> listRoles({
    required String workspaceId,
  }) async {
    rolesCalls += 1;
    return rolesResult ??
        MembershipAdminSuccess<List<WorkspaceRole>>(
          List<WorkspaceRole>.from(roles),
        );
  }

  @override
  Future<MembershipAdminResult<List<WorkspaceRoleCapability>>>
  listRolePermissions({required String workspaceId}) async {
    rolePermissionsCalls += 1;
    return rolePermissionsResult ??
        MembershipAdminSuccess<List<WorkspaceRoleCapability>>(
          List<WorkspaceRoleCapability>.from(roleCapabilities),
        );
  }

  @override
  Future<MembershipAdminResult<List<MembershipInvitation>>> listInvitations({
    required String workspaceId,
    bool includeResolved = false,
  }) async {
    invitationsCalls += 1;
    return invitationsResult ??
        MembershipAdminSuccess<List<MembershipInvitation>>(
          List<MembershipInvitation>.from(invitations),
        );
  }

  @override
  Future<MembershipAdminResult<List<PendingInvitationEntry>>>
  listMyPendingInvitations() async {
    pendingCalls += 1;
    return pendingResult ??
        MembershipAdminSuccess<List<PendingInvitationEntry>>(
          List<PendingInvitationEntry>.from(pending),
        );
  }

  @override
  Future<MembershipAdminResult<InviteOutcome>> invite(
    InviteMemberCommand command,
  ) async {
    inviteCalls += 1;
    lastInviteCommand = command;
    return inviteResult ??
        MembershipAdminSuccess<InviteOutcome>(
          InviteOutcome(member: _member('m-new')),
        );
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> accept(
    AcceptInvitationCommand command,
  ) async {
    acceptCalls += 1;
    return acceptResult ??
        MembershipAdminSuccess<WorkspaceMember>(_member('m-accepted'));
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> updateStatus(
    UpdateMembershipStatusCommand command,
  ) async {
    updateStatusCalls += 1;
    return updateStatusResult ??
        MembershipAdminSuccess<WorkspaceMember>(_member(command.membershipId));
  }

  @override
  Future<MembershipAdminResult<WorkspaceMember>> changeRole(
    ChangeMembershipRoleCommand command,
  ) async {
    changeRoleCalls += 1;
    return changeRoleResult ??
        MembershipAdminSuccess<WorkspaceMember>(_member(command.membershipId));
  }

  @override
  Future<MembershipAdminResult<MembershipInvitation>> revokeInvitation(
    RevokeInvitationCommand command,
  ) async {
    revokeInvitationCalls += 1;
    return revokeInvitationResult ??
        MembershipAdminSuccess<MembershipInvitation>(
          _invitation(command.invitationId),
        );
  }
}
