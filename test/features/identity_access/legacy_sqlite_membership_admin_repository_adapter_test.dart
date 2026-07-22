import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/security.dart';
import 'package:neximmo_app/data/repositories/security_repo.dart';
import 'package:neximmo_app/features/identity_access/application/membership_admin_repository.dart';
import 'package:neximmo_app/features/identity_access/data/legacy_sqlite_membership_admin_repository_adapter.dart';

void main() {
  group('LegacySqliteMembershipAdminRepositoryAdapter', () {
    late _FakeSecurityRepo securityRepo;
    late LegacySqliteMembershipAdminRepositoryAdapter adapter;

    MembershipCommandContext context({String workspaceId = 'workspace-a'}) {
      return MembershipCommandContext(
        workspaceId: workspaceId,
        actorId: 'actor-a',
        mutationId: 'mutation-a',
        correlationId: 'correlation-a',
      );
    }

    setUp(() {
      securityRepo = _FakeSecurityRepo();
      adapter = LegacySqliteMembershipAdminRepositoryAdapter(
        securityRepo: securityRepo,
        legacyWorkspaceId: 'workspace-a',
      );
    });

    test('maps local users onto always-active members', () async {
      securityRepo.users = <LocalUserRecord>[
        _user(id: 'user-1', role: 'admin'),
        _user(id: 'user-2', role: 'viewer'),
      ];

      final result = await adapter.listMembers(workspaceId: 'workspace-a');

      final members =
          (result as MembershipAdminSuccess<List<WorkspaceMember>>).value;
      expect(members.map((member) => member.userId), <String>[
        'user-1',
        'user-2',
      ]);
      expect(
        members.every(
          (member) =>
              member.status == MembershipStatus.active &&
              member.version ==
                  LegacySqliteMembershipAdminRepositoryAdapter
                      .unsupportedVersion,
        ),
        isTrue,
      );
    });

    test('derives roles from the distinct role strings in use', () async {
      securityRepo.users = <LocalUserRecord>[
        _user(id: 'user-1', role: 'viewer'),
        _user(id: 'user-2', role: 'admin'),
        _user(id: 'user-3', role: 'viewer'),
      ];

      final result = await adapter.listRoles(workspaceId: 'workspace-a');

      final roles =
          (result as MembershipAdminSuccess<List<WorkspaceRole>>).value;
      expect(roles.map((role) => role.key), <String>['admin', 'viewer']);
    });

    test('has no invitation surface', () async {
      final invitations = await adapter.listInvitations(
        workspaceId: 'workspace-a',
      );
      final pending = await adapter.listMyPendingInvitations();

      expect(
        (invitations as MembershipAdminSuccess<List<MembershipInvitation>>)
            .value,
        isEmpty,
      );
      expect(
        (pending as MembershipAdminSuccess<List<PendingInvitationEntry>>)
            .value,
        isEmpty,
      );
    });

    test('rejects a foreign workspace scope fail-closed', () async {
      final result = await adapter.listMembers(workspaceId: 'workspace-b');

      expect(
        (result as MembershipAdminFailure<List<WorkspaceMember>>).kind,
        MembershipAdminFailureKind.forbidden,
      );
    });

    test('blocks every mutation with dependencyConflict', () async {
      final results = <MembershipAdminResult<Object?>>[
        await adapter.invite(
          InviteMemberCommand(
            context: context(),
            email: 'a@example.test',
            roleId: 'viewer',
          ),
        ),
        await adapter.accept(AcceptInvitationCommand(context: context())),
        await adapter.updateStatus(
          UpdateMembershipStatusCommand(
            context: context(),
            membershipId: 'user-1',
            newStatus: MembershipStatus.suspended,
            expectedVersion: 1,
          ),
        ),
        await adapter.changeRole(
          ChangeMembershipRoleCommand(
            context: context(),
            membershipId: 'user-1',
            newRoleId: 'admin',
            expectedVersion: 1,
          ),
        ),
        await adapter.revokeInvitation(
          RevokeInvitationCommand(
            context: context(),
            invitationId: 'invitation-1',
            expectedVersion: 1,
          ),
        ),
      ];

      for (final result in results) {
        expect(
          (result as MembershipAdminFailure<Object?>).kind,
          MembershipAdminFailureKind.dependencyConflict,
        );
      }
    });

    test('hides repository exception details', () async {
      securityRepo.listError = StateError('sensitive sqlite detail');

      final result = await adapter.listMembers(workspaceId: 'workspace-a');

      final failure = result as MembershipAdminFailure<List<WorkspaceMember>>;
      expect(failure.kind, MembershipAdminFailureKind.infrastructureFailure);
      expect(failure.message, isNot(contains('sensitive')));
    });
  });
}

LocalUserRecord _user({required String id, required String role}) {
  return LocalUserRecord(
    id: id,
    workspaceId: 'workspace-a',
    email: null,
    displayName: id,
    passwordHash: null,
    passwordSalt: null,
    role: role,
    createdAt: 1,
  );
}

class _FakeSecurityRepo implements SecurityRepo {
  List<LocalUserRecord> users = <LocalUserRecord>[];
  Object? listError;

  @override
  Future<List<LocalUserRecord>> listUsers(String workspaceId) async {
    if (listError != null) {
      throw listError!;
    }
    return users;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}
