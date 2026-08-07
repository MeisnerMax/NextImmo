import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/membership_admin_repository.dart';
import 'package:neximmo_app/features/identity_access/data/supabase_membership_admin_repository_adapter.dart';

import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const workspaceId = 'f1000000-0000-0000-0000-000000000001';
  const adminId = 'fa000000-0000-0000-0000-000000000001';
  const inviteeId = 'fa000000-0000-0000-0000-000000000002';
  const managerRoleId = 'f2000000-0000-0000-0000-000000000001';
  const viewerRoleId = 'f2000000-0000-0000-0000-000000000002';

  var mutationCounter = 0;
  MembershipCommandContext context(String actorId, {String? reason}) {
    mutationCounter++;
    final suffix = mutationCounter.toString().padLeft(2, '0');
    return MembershipCommandContext(
      workspaceId: workspaceId,
      actorId: actorId,
      mutationId: 'f5000000-0000-0000-0000-0000000000$suffix',
      correlationId: 'f6000000-0000-0000-0000-0000000000$suffix',
      reason: reason,
    );
  }

  test(
    'real client drives the membership lifecycle end to end',
    () async {
      expect(url, isNotEmpty, reason: 'SUPABASE_URL dart define is required.');
      expect(
        publishableKey,
        isNotEmpty,
        reason: 'SUPABASE_PUBLISHABLE_KEY dart define is required.',
      );
      expect(
        Uri.tryParse(url)?.host,
        anyOf('127.0.0.1', 'localhost', '::1'),
        reason: 'This integration test is restricted to local Supabase.',
      );

      final adminClient = createSupabaseTestClient(url, publishableKey);
      final inviteeClient = createSupabaseTestClient(url, publishableKey);
      try {
        await adminClient.auth.signInWithPassword(
          email: 'p2-d01-admin@example.test',
          password: 'NexImmo-Test-2026!',
        );
        final adminRepo = SupabaseMembershipAdminRepositoryAdapter(
          client: adminClient,
        );

        // Mutations are AAL2-gated server-side: an aal1 session is refused.
        final aal1Result = await adminRepo.invite(
          InviteMemberCommand(
            context: context(adminId),
            email: 'p2-d01-invitee@example.test',
            roleId: viewerRoleId,
          ),
        );
        expect(
          (aal1Result as MembershipAdminFailure<InviteOutcome>).kind,
          MembershipAdminFailureKind.forbidden,
        );

        await elevateSupabaseTestClientToAal2(adminClient);

        final roles =
            (await adminRepo.listRoles(workspaceId: workspaceId))
                as MembershipAdminSuccess<List<WorkspaceRole>>;
        expect(roles.value.map((role) => role.key), <String>[
          'manager',
          'viewer',
        ]);

        // Inviting an existing auth user creates a membership in 'invited'.
        final invite = await adminRepo.invite(
          InviteMemberCommand(
            context: context(adminId, reason: 'integration invite'),
            email: 'p2-d01-invitee@example.test',
            roleId: viewerRoleId,
          ),
        );
        final invited =
            (invite as MembershipAdminSuccess<InviteOutcome>).value.member!;
        expect(invited.status, MembershipStatus.invited);
        expect(invited.userId, inviteeId);

        // The invitee sees the pending membership and accepts it.
        await inviteeClient.auth.signInWithPassword(
          email: 'p2-d01-invitee@example.test',
          password: 'NexImmo-Test-2026!',
        );
        await elevateSupabaseTestClientToAal2(inviteeClient);
        final inviteeRepo = SupabaseMembershipAdminRepositoryAdapter(
          client: inviteeClient,
        );

        final pending =
            (await inviteeRepo.listMyPendingInvitations())
                as MembershipAdminSuccess<List<PendingInvitationEntry>>;
        expect(pending.value, hasLength(1));
        expect(pending.value.single.isMembership, isTrue);
        expect(pending.value.single.workspaceName, 'P2-D01');

        final accepted =
            (await inviteeRepo.accept(
                  AcceptInvitationCommand(context: context(inviteeId)),
                ))
                as MembershipAdminSuccess<WorkspaceMember>;
        expect(accepted.value.status, MembershipStatus.active);
        expect(accepted.value.version, 2);

        // Admin sees both members and drives the STM-001 transitions.
        final members =
            (await adminRepo.listMembers(workspaceId: workspaceId))
                as MembershipAdminSuccess<List<WorkspaceMember>>;
        expect(members.value, hasLength(2));

        // The security.manage-gated directory joins display name and email.
        final directory =
            (await adminRepo.listMemberDirectory(workspaceId: workspaceId))
                as MembershipAdminSuccess<List<WorkspaceMemberDirectoryEntry>>;
        expect(directory.value, hasLength(2));
        final adminEntry = directory.value.firstWhere(
          (entry) => entry.userId == adminId,
        );
        expect(adminEntry.displayName, 'Directory Admin');
        expect(adminEntry.email, 'p2-d01-admin@example.test');
        final inviteeEntry = directory.value.firstWhere(
          (entry) => entry.userId == inviteeId,
        );
        expect(inviteeEntry.email, 'p2-d01-invitee@example.test');
        expect(inviteeEntry.status, MembershipStatus.active);

        // The invitee is a viewer without security.manage: the directory read
        // is forbidden, distinctly from an empty result.
        final inviteeDirectory = await inviteeRepo.listMemberDirectory(
          workspaceId: workspaceId,
        );
        expect(
          (inviteeDirectory
                  as MembershipAdminFailure<
                      List<WorkspaceMemberDirectoryEntry>>)
              .kind,
          MembershipAdminFailureKind.forbidden,
        );

        final suspended =
            (await adminRepo.updateStatus(
                  UpdateMembershipStatusCommand(
                    context: context(adminId, reason: 'integration suspend'),
                    membershipId: accepted.value.membershipId,
                    newStatus: MembershipStatus.suspended,
                    expectedVersion: 2,
                  ),
                ))
                as MembershipAdminSuccess<WorkspaceMember>;
        expect(suspended.value.status, MembershipStatus.suspended);

        final stale = await adminRepo.updateStatus(
          UpdateMembershipStatusCommand(
            context: context(adminId),
            membershipId: accepted.value.membershipId,
            newStatus: MembershipStatus.active,
            expectedVersion: 2,
          ),
        );
        final conflict = stale as MembershipAdminFailure<WorkspaceMember>;
        expect(conflict.kind, MembershipAdminFailureKind.versionConflict);
        expect(conflict.versionConflict?.actualVersion, 3);
        expect(
          conflict.versionConflict?.currentMember?.status,
          MembershipStatus.suspended,
        );

        final promoted =
            (await adminRepo.changeRole(
                  ChangeMembershipRoleCommand(
                    context: context(adminId, reason: 'integration promote'),
                    membershipId: accepted.value.membershipId,
                    newRoleId: managerRoleId,
                    expectedVersion: 3,
                  ),
                ))
                as MembershipAdminSuccess<WorkspaceMember>;
        expect(promoted.value.roleId, managerRoleId);
        expect(promoted.value.version, 4);

        // Unknown emails become pending invitations, revocable by the admin.
        final ghostInvite =
            (await adminRepo.invite(
                  InviteMemberCommand(
                    context: context(adminId),
                    email: 'p2-d01-ghost@example.test',
                    roleId: viewerRoleId,
                  ),
                ))
                as MembershipAdminSuccess<InviteOutcome>;
        final ghost = ghostInvite.value.invitation!;
        expect(ghost.status, MembershipInvitationStatus.pending);

        final invitations =
            (await adminRepo.listInvitations(workspaceId: workspaceId))
                as MembershipAdminSuccess<List<MembershipInvitation>>;
        expect(invitations.value.map((invitation) => invitation.id), [
          ghost.id,
        ]);

        final revoked =
            (await adminRepo.revokeInvitation(
                  RevokeInvitationCommand(
                    context: context(adminId, reason: 'integration revoke'),
                    invitationId: ghost.id,
                    expectedVersion: ghost.version,
                  ),
                ))
                as MembershipAdminSuccess<MembershipInvitation>;
        expect(revoked.value.status, MembershipInvitationStatus.revoked);
      } finally {
        await inviteeClient.auth.signOut();
        await adminClient.auth.signOut();
      }
    },
    skip:
        url.isEmpty || publishableKey.isEmpty
            ? 'Requires the local Supabase integration harness.'
            : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
