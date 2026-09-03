import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/membership_admin_repository.dart';
import 'package:neximmo_app/features/identity_access/data/supabase_membership_admin_repository_adapter.dart';

void main() {
  group('SupabaseMembershipAdminRepositoryAdapter', () {
    late _FakeMembershipAdminSupabaseGateway gateway;
    late SupabaseMembershipAdminRepositoryAdapter repository;

    setUp(() {
      gateway = _FakeMembershipAdminSupabaseGateway();
      repository = SupabaseMembershipAdminRepositoryAdapter.withGateway(
        gateway,
      );
    });

    test('lists members scoped to the requested workspace', () async {
      gateway.membershipsResult = <Map<String, dynamic>>[
        _memberJson(),
        _memberJson(id: 'membership-b', status: 'suspended', version: 3),
      ];

      final result = await repository.listMembers(workspaceId: 'workspace-a');

      expect(gateway.membershipsWorkspaceId, 'workspace-a');
      final members =
          (result as MembershipAdminSuccess<List<WorkspaceMember>>).value;
      expect(members.map((member) => member.membershipId), <String>[
        'membership-a',
        'membership-b',
      ]);
      expect(members.first.status, MembershipStatus.active);
      expect(members.last.status, MembershipStatus.suspended);
      expect(members.last.version, 3);
    });

    test('rejects a member row from a foreign workspace', () async {
      gateway.membershipsResult = <Map<String, dynamic>>[
        _memberJson(),
        _memberJson(id: 'membership-b', workspaceId: 'workspace-b'),
      ];

      final result = await repository.listMembers(workspaceId: 'workspace-a');

      expect(
        (result as MembershipAdminFailure<List<WorkspaceMember>>).kind,
        MembershipAdminFailureKind.infrastructureFailure,
      );
    });

    test('lists the member directory from the RPC envelope', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': <Object?>[
          _directoryJson(),
          _directoryJson(
            membershipId: 'membership-b',
            userId: 'user-b',
            roleKey: 'viewer',
            roleName: 'Viewer',
            status: 'suspended',
            displayName: null,
            email: null,
            version: 2,
          ),
        ],
      };

      final result = await repository.listMemberDirectory(
        workspaceId: 'workspace-a',
      );

      expect(gateway.rpcFunction, 'list_workspace_members');
      expect(gateway.rpcParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
      });
      final entries =
          (result
                  as MembershipAdminSuccess<
                    List<WorkspaceMemberDirectoryEntry>
                  >)
              .value;
      expect(entries.first.displayName, 'Directory Admin');
      expect(entries.first.email, 'admin@example.com');
      expect(entries.first.status, MembershipStatus.active);
      expect(entries.last.displayName, isNull);
      expect(entries.last.email, isNull);
      expect(entries.last.roleKey, 'viewer');
      expect(entries.last.status, MembershipStatus.suspended);
      expect(entries.last.version, 2);
    });

    test(
      'maps a forbidden directory envelope to a forbidden failure',
      () async {
        gateway.rpcResult = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'forbidden',
            'message': 'Member directory access is not permitted',
          },
        };

        final result = await repository.listMemberDirectory(
          workspaceId: 'workspace-a',
        );

        expect(
          (result
                  as MembershipAdminFailure<
                    List<WorkspaceMemberDirectoryEntry>
                  >)
              .kind,
          MembershipAdminFailureKind.forbidden,
        );
      },
    );

    test('rejects a directory entry from a foreign workspace', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': <Object?>[_directoryJson(workspaceId: 'workspace-b')],
      };

      final result = await repository.listMemberDirectory(
        workspaceId: 'workspace-a',
      );

      expect(
        (result as MembershipAdminFailure<List<WorkspaceMemberDirectoryEntry>>)
            .kind,
        MembershipAdminFailureKind.infrastructureFailure,
      );
    });

    test('hides a malformed directory response', () async {
      gateway.rpcResult = <String, Object?>{'ok': true, 'entity': 'not-a-list'};

      final result = await repository.listMemberDirectory(
        workspaceId: 'workspace-a',
      );

      expect(
        (result as MembershipAdminFailure<List<WorkspaceMemberDirectoryEntry>>)
            .kind,
        MembershipAdminFailureKind.infrastructureFailure,
      );
    });

    test('lists roles scoped to the requested workspace', () async {
      gateway.rolesResult = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'role-a',
          'workspace_id': 'workspace-a',
          'key': 'manager',
          'name': 'Manager',
        },
      ];

      final result = await repository.listRoles(workspaceId: 'workspace-a');

      expect(gateway.rolesWorkspaceId, 'workspace-a');
      final roles =
          (result as MembershipAdminSuccess<List<WorkspaceRole>>).value;
      expect(roles.single.key, 'manager');
      expect(roles.single.name, 'Manager');
    });

    test('lists invitations with the resolved filter forwarded', () async {
      gateway.invitationsResult = <Map<String, dynamic>>[
        _invitationJson(),
        _invitationJson(
          id: 'invitation-b',
          status: 'accepted',
          acceptedMembershipId: 'membership-b',
        ),
      ];

      final result = await repository.listInvitations(
        workspaceId: 'workspace-a',
        includeResolved: true,
      );

      expect(gateway.invitationsWorkspaceId, 'workspace-a');
      expect(gateway.invitationsIncludeResolved, isTrue);
      final invitations =
          (result as MembershipAdminSuccess<List<MembershipInvitation>>).value;
      expect(invitations.first.status, MembershipInvitationStatus.pending);
      expect(invitations.first.acceptedMembershipId, isNull);
      expect(invitations.last.status, MembershipInvitationStatus.accepted);
      expect(invitations.last.acceptedMembershipId, 'membership-b');
    });

    test('lists only pending invitations by default', () async {
      await repository.listInvitations(workspaceId: 'workspace-a');

      expect(gateway.invitationsIncludeResolved, isFalse);
    });

    test('parses pending invitation entries of both kinds', () async {
      gateway.rpcResult = <Object?>[
        <String, dynamic>{
          'kind': 'membership',
          'membership_id': 'membership-a',
          'workspace_id': 'workspace-a',
          'workspace_name': 'Workspace A',
          'role_key': 'manager',
          'role_name': 'Manager',
          'created_at': '2026-07-20T10:00:00Z',
          'version': 1,
        },
        <String, dynamic>{
          'kind': 'invitation',
          'invitation_id': 'invitation-a',
          'workspace_id': 'workspace-b',
          'workspace_name': 'Workspace B',
          'role_key': 'viewer',
          'role_name': 'Viewer',
          'created_at': '2026-07-21T10:00:00Z',
          'version': 2,
        },
      ];

      final result = await repository.listMyPendingInvitations();

      expect(gateway.rpcFunction, 'list_my_pending_invitations');
      expect(gateway.rpcParameters, isEmpty);
      final entries =
          (result as MembershipAdminSuccess<List<PendingInvitationEntry>>)
              .value;
      expect(entries.first.isMembership, isTrue);
      expect(entries.first.membershipId, 'membership-a');
      expect(entries.first.invitationId, isNull);
      expect(entries.first.workspaceName, 'Workspace A');
      expect(entries.last.isMembership, isFalse);
      expect(entries.last.invitationId, 'invitation-a');
      expect(entries.last.membershipId, isNull);
      expect(entries.last.roleKey, 'viewer');
      expect(entries.last.version, 2);
    });

    test('rejects an unknown pending invitation kind', () async {
      gateway.rpcResult = <Object?>[
        <String, dynamic>{
          'kind': 'mystery',
          'membership_id': 'membership-a',
          'workspace_id': 'workspace-a',
          'workspace_name': 'Workspace A',
          'role_key': 'manager',
          'role_name': 'Manager',
          'created_at': '2026-07-20T10:00:00Z',
          'version': 1,
        },
      ];

      final result = await repository.listMyPendingInvitations();

      expect(
        (result as MembershipAdminFailure<List<PendingInvitationEntry>>).kind,
        MembershipAdminFailureKind.infrastructureFailure,
      );
    });

    test('rejects actor mismatch before calling the invite RPC', () async {
      gateway.currentUserId = 'another-actor';

      final result = await repository.invite(_inviteCommand());

      expect(gateway.rpcCalls, 0);
      expect(
        (result as MembershipAdminFailure<InviteOutcome>).kind,
        MembershipAdminFailureKind.forbidden,
      );
    });

    test('invites through RPC and resolves a membership outcome', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _memberJson(status: 'invited'),
      };

      final result = await repository.invite(_inviteCommand());

      expect(gateway.rpcCalls, 1);
      expect(gateway.rpcFunction, 'invite_workspace_member');
      expect(gateway.rpcParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_email': 'invitee@example.com',
        'p_role_id': 'role-a',
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_reason': 'Onboarding',
      });
      final outcome = (result as MembershipAdminSuccess<InviteOutcome>).value;
      expect(outcome.member?.membershipId, 'membership-a');
      expect(outcome.member?.status, MembershipStatus.invited);
      expect(outcome.invitation, isNull);
    });

    test('invites and resolves a staged invitation outcome', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _invitationJson(),
      };

      final result = await repository.invite(_inviteCommand());

      final outcome = (result as MembershipAdminSuccess<InviteOutcome>).value;
      expect(outcome.member, isNull);
      expect(outcome.invitation?.id, 'invitation-a');
      expect(outcome.invitation?.email, 'invitee@example.com');
      expect(outcome.invitation?.status, MembershipInvitationStatus.pending);
    });

    test('rejects an invite entity from a foreign workspace', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _memberJson(workspaceId: 'workspace-b'),
      };

      final result = await repository.invite(_inviteCommand());

      expect(
        (result as MembershipAdminFailure<InviteOutcome>).kind,
        MembershipAdminFailureKind.infrastructureFailure,
      );
    });

    test('accepts through RPC with the context envelope', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _memberJson(version: 2),
      };

      final result = await repository.accept(
        AcceptInvitationCommand(context: _context()),
      );

      expect(gateway.rpcFunction, 'accept_workspace_invitation');
      expect(gateway.rpcParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_reason': 'Onboarding',
      });
      final member = (result as MembershipAdminSuccess<WorkspaceMember>).value;
      expect(member.status, MembershipStatus.active);
      expect(member.version, 2);
    });

    test('updates status through RPC with the serialized enum name', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _memberJson(status: 'suspended', version: 2),
      };

      final result = await repository.updateStatus(_updateStatusCommand());

      expect(gateway.rpcCalls, 1);
      expect(gateway.rpcFunction, 'update_membership_status');
      expect(gateway.rpcParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_membership_id': 'membership-a',
        'p_new_status': 'suspended',
        'p_expected_version': 1,
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_reason': 'Onboarding',
      });
      final member = (result as MembershipAdminSuccess<WorkspaceMember>).value;
      expect(member.status, MembershipStatus.suspended);
      expect(member.version, 2);
    });

    test('changes role through RPC with the serialized command', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _memberJson(version: 2),
      };

      final result = await repository.changeRole(
        ChangeMembershipRoleCommand(
          context: _context(),
          membershipId: 'membership-a',
          newRoleId: 'role-b',
          expectedVersion: 1,
        ),
      );

      expect(gateway.rpcFunction, 'change_membership_role');
      expect(gateway.rpcParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_membership_id': 'membership-a',
        'p_new_role_id': 'role-b',
        'p_expected_version': 1,
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_reason': 'Onboarding',
      });
      expect(result, isA<MembershipAdminSuccess<WorkspaceMember>>());
    });

    test('revokes an invitation through RPC', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _invitationJson(status: 'revoked', version: 2),
      };

      final result = await repository.revokeInvitation(_revokeCommand());

      expect(gateway.rpcFunction, 'revoke_workspace_invitation');
      expect(gateway.rpcParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_invitation_id': 'invitation-a',
        'p_expected_version': 1,
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_reason': 'Onboarding',
      });
      final invitation =
          (result as MembershipAdminSuccess<MembershipInvitation>).value;
      expect(invitation.status, MembershipInvitationStatus.revoked);
      expect(invitation.version, 2);
    });

    test('maps membership version conflict including current member', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'version_conflict',
          'message': 'Membership version is stale',
          'expected_version': 1,
          'actual_version': 3,
          'current_entity': _memberJson(version: 3),
        },
      };

      final result = await repository.updateStatus(_updateStatusCommand());
      final failure = result as MembershipAdminFailure<WorkspaceMember>;

      expect(failure.kind, MembershipAdminFailureKind.versionConflict);
      expect(failure.versionConflict?.expectedVersion, 1);
      expect(failure.versionConflict?.actualVersion, 3);
      expect(failure.versionConflict?.currentMember?.version, 3);
      expect(failure.versionConflict?.currentInvitation, isNull);
    });

    test(
      'maps invitation version conflict including current invitation',
      () async {
        gateway.rpcResult = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'version_conflict',
            'message': 'Invitation version is stale',
            'expected_version': 1,
            'actual_version': 2,
            'current_entity': _invitationJson(version: 2),
          },
        };

        final result = await repository.revokeInvitation(_revokeCommand());
        final failure = result as MembershipAdminFailure<MembershipInvitation>;

        expect(failure.kind, MembershipAdminFailureKind.versionConflict);
        expect(failure.versionConflict?.expectedVersion, 1);
        expect(failure.versionConflict?.actualVersion, 2);
        expect(failure.versionConflict?.currentInvitation?.version, 2);
        expect(failure.versionConflict?.currentMember, isNull);
      },
    );

    test('maps mutation conflict and in-progress separately', () async {
      for (final entry in <(String, MembershipAdminFailureKind)>[
        ('mutation_conflict', MembershipAdminFailureKind.mutationConflict),
        ('in_progress', MembershipAdminFailureKind.mutationInProgress),
      ]) {
        gateway.rpcResult = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': entry.$1,
            'message': 'Mutation failed',
          },
        };

        final result = await repository.accept(
          AcceptInvitationCommand(context: _context()),
        );

        expect(
          (result as MembershipAdminFailure<WorkspaceMember>).kind,
          entry.$2,
        );
      }
    });

    test('hides malformed response and gateway exception details', () async {
      gateway.rpcResult = <String, Object?>{'entity': _memberJson()};
      final malformed = await repository.updateStatus(_updateStatusCommand());

      gateway.rpcError = StateError('sensitive Postgrest detail');
      final failedCommand = await repository.updateStatus(
        _updateStatusCommand(),
      );

      gateway.membershipsError = StateError('sensitive Postgrest detail');
      final failedRead = await repository.listMembers(
        workspaceId: 'workspace-a',
      );

      for (final failure in <MembershipAdminFailure<dynamic>>[
        malformed as MembershipAdminFailure<WorkspaceMember>,
        failedCommand as MembershipAdminFailure<WorkspaceMember>,
        failedRead as MembershipAdminFailure<List<WorkspaceMember>>,
      ]) {
        expect(failure.kind, MembershipAdminFailureKind.infrastructureFailure);
        expect(failure.message, isNot(contains('sensitive')));
        expect(failure.message, isNot(contains('Postgrest')));
      }
    });

    group('listRolePermissions (ADMIN-AREA-01 A1)', () {
      test('joins role assignments with the permission catalog', () async {
        gateway.rolePermissionsResult = <Map<String, dynamic>>[
          _rolePermissionJson(roleId: 'role-a', permissionId: 'perm-1'),
          _rolePermissionJson(roleId: 'role-a', permissionId: 'perm-2'),
          _rolePermissionJson(roleId: 'role-b', permissionId: 'perm-2'),
        ];
        gateway.permissionsResult = <Map<String, dynamic>>[
          _permissionJson(
            id: 'perm-1',
            key: 'security.manage',
            name: 'Sicherheitsverwaltung',
          ),
          _permissionJson(
            id: 'perm-2',
            key: 'property.read',
            name: 'Objekte lesen',
          ),
        ];

        final result = await repository.listRolePermissions(
          workspaceId: 'workspace-a',
        );

        expect(gateway.rolePermissionsWorkspaceId, 'workspace-a');
        expect(
          gateway.permissionsRequestedIds,
          unorderedEquals(<String>['perm-1', 'perm-2']),
        );
        final capabilities =
            (result as MembershipAdminSuccess<List<WorkspaceRoleCapability>>)
                .value;
        expect(capabilities, hasLength(3));
        final adminKeys = capabilities
            .where((capability) => capability.roleId == 'role-a')
            .map((capability) => capability.permissionKey);
        expect(
          adminKeys,
          unorderedEquals(<String>['security.manage', 'property.read']),
        );
        expect(
          capabilities
              .firstWhere(
                (capability) => capability.permissionKey == 'security.manage',
              )
              .permissionName,
          'Sicherheitsverwaltung',
        );
      });

      test('returns an empty set without querying the catalog', () async {
        final result = await repository.listRolePermissions(
          workspaceId: 'workspace-a',
        );

        final capabilities =
            (result as MembershipAdminSuccess<List<WorkspaceRoleCapability>>)
                .value;
        expect(capabilities, isEmpty);
        expect(gateway.permissionsCalls, 0);
      });

      test('rejects assignments from a foreign workspace', () async {
        gateway.rolePermissionsResult = <Map<String, dynamic>>[
          _rolePermissionJson(workspaceId: 'workspace-b'),
        ];

        final result = await repository.listRolePermissions(
          workspaceId: 'workspace-a',
        );

        expect(
          (result as MembershipAdminFailure<List<WorkspaceRoleCapability>>)
              .kind,
          MembershipAdminFailureKind.infrastructureFailure,
        );
      });

      test(
        'fails closed when a referenced permission row is missing',
        () async {
          gateway.rolePermissionsResult = <Map<String, dynamic>>[
            _rolePermissionJson(permissionId: 'perm-unknown'),
          ];
          gateway.permissionsResult = <Map<String, dynamic>>[];

          final result = await repository.listRolePermissions(
            workspaceId: 'workspace-a',
          );

          expect(
            (result as MembershipAdminFailure<List<WorkspaceRoleCapability>>)
                .kind,
            MembershipAdminFailureKind.infrastructureFailure,
          );
        },
      );

      test('hides infrastructure details on gateway failures', () async {
        gateway.rolePermissionsError = StateError('sensitive Postgrest detail');

        final result = await repository.listRolePermissions(
          workspaceId: 'workspace-a',
        );

        final failure =
            result as MembershipAdminFailure<List<WorkspaceRoleCapability>>;
        expect(failure.kind, MembershipAdminFailureKind.infrastructureFailure);
        expect(failure.message, isNot(contains('sensitive')));
        expect(failure.message, isNot(contains('Postgrest')));
      });
    });

    group('listMembershipAuditEvents (ADMIN-AREA-01 A2)', () {
      test('reads membership audit events with keyset parameters', () async {
        gateway.auditEventsResult = <Map<String, dynamic>>[
          _auditEventJson(
            id: 'event-2',
            action: 'membership.role_change',
            createdAt: '2026-08-28T12:00:00.200000+00:00',
            reason: 'Beförderung',
            oldValues: <String, dynamic>{
              'user_id': 'user-a',
              'role_id': 'role-viewer',
            },
            newValues: <String, dynamic>{
              'user_id': 'user-a',
              'role_id': 'role-admin',
            },
          ),
          _auditEventJson(
            id: 'event-1',
            action: 'membership_invitation.revoke',
            entityType: 'membership_invitation',
            createdAt: '2026-08-28T11:00:00.100000+00:00',
            oldValues: <String, dynamic>{'email': 'gast@example.com'},
            newValues: <String, dynamic>{'email': 'gast@example.com'},
          ),
        ];

        final result = await repository.listMembershipAuditEvents(
          workspaceId: 'workspace-a',
        );

        expect(gateway.auditWorkspaceId, 'workspace-a');
        expect(
          gateway.auditEntityTypes,
          unorderedEquals(<String>['membership', 'membership_invitation']),
        );
        expect(gateway.auditLimit, 51);
        expect(gateway.auditBefore, isNull);
        final page =
            (result as MembershipAdminSuccess<MembershipAuditPage>).value;
        expect(page.events, hasLength(2));
        expect(page.nextCursor, isNull);
        final roleChange = page.events.first;
        expect(roleChange.id, 'event-2');
        expect(roleChange.action, 'membership.role_change');
        expect(roleChange.entityType, 'membership');
        expect(roleChange.actorUserId, 'actor-a');
        expect(roleChange.actorRoleKey, 'manager');
        expect(roleChange.reason, 'Beförderung');
        expect(roleChange.targetUserId, 'user-a');
        expect(roleChange.oldRoleId, 'role-viewer');
        expect(roleChange.newRoleId, 'role-admin');
        final revoke = page.events.last;
        expect(revoke.reason, isNull);
        expect(revoke.targetEmail, 'gast@example.com');
        expect(revoke.targetUserId, isNull);
      });

      test('pages with a cursor and hands back the next one', () async {
        gateway.auditEventsResult = <Map<String, dynamic>>[
          _auditEventJson(
            id: 'event-3',
            action: 'membership.suspend',
            createdAt: '2026-08-28T10:00:00.300000+00:00',
          ),
          _auditEventJson(
            id: 'event-2',
            action: 'membership.reactivate',
            createdAt: '2026-08-28T09:00:00.200000+00:00',
          ),
          _auditEventJson(
            id: 'event-1',
            action: 'membership.revoke',
            createdAt: '2026-08-28T08:00:00.100000+00:00',
          ),
        ];

        final result = await repository.listMembershipAuditEvents(
          workspaceId: 'workspace-a',
          limit: 2,
          before: const MembershipAuditCursor(
            createdAt: '2026-08-28T11:00:00.000000+00:00',
            id: 'event-9',
          ),
        );

        expect(gateway.auditLimit, 3);
        expect(gateway.auditBefore, (
          createdAt: '2026-08-28T11:00:00.000000+00:00',
          id: 'event-9',
        ));
        final page =
            (result as MembershipAdminSuccess<MembershipAuditPage>).value;
        expect(page.events, hasLength(2));
        expect(page.events.map((event) => event.id), <String>[
          'event-3',
          'event-2',
        ]);
        expect(page.nextCursor?.id, 'event-2');
        expect(page.nextCursor?.createdAt, '2026-08-28T09:00:00.200000+00:00');
      });

      test('returns an empty page as success, not as an error', () async {
        final result = await repository.listMembershipAuditEvents(
          workspaceId: 'workspace-a',
        );

        final page =
            (result as MembershipAdminSuccess<MembershipAuditPage>).value;
        expect(page.events, isEmpty);
        expect(page.nextCursor, isNull);
      });

      test(
        'drops rows of foreign entity types instead of relabelling them',
        () async {
          gateway.auditEventsResult = <Map<String, dynamic>>[
            _auditEventJson(
              id: 'event-2',
              action: 'membership.suspend',
              createdAt: '2026-08-28T10:00:00.200000+00:00',
            ),
            _auditEventJson(
              id: 'event-x',
              action: 'property.update',
              entityType: 'property',
              createdAt: '2026-08-28T09:30:00.000000+00:00',
            ),
          ];

          final result = await repository.listMembershipAuditEvents(
            workspaceId: 'workspace-a',
          );

          final page =
              (result as MembershipAdminSuccess<MembershipAuditPage>).value;
          expect(page.events.map((event) => event.id), <String>['event-2']);
        },
      );

      test(
        'keeps events with malformed payloads and nulls the extracts',
        () async {
          gateway.auditEventsResult = <Map<String, dynamic>>[
            _auditEventJson(
              id: 'event-1',
              action: 'membership.role_change',
              createdAt: '2026-08-28T10:00:00.100000+00:00',
              newValues: 'kaputt',
            ),
          ];

          final result = await repository.listMembershipAuditEvents(
            workspaceId: 'workspace-a',
          );

          final page =
              (result as MembershipAdminSuccess<MembershipAuditPage>).value;
          final event = page.events.single;
          expect(event.targetUserId, isNull);
          expect(event.newRoleId, isNull);
        },
      );

      test('fails closed on a malformed required field', () async {
        final row = _auditEventJson(
          id: 'event-1',
          action: 'membership.suspend',
          createdAt: '2026-08-28T10:00:00.100000+00:00',
        )..remove('action');
        gateway.auditEventsResult = <Map<String, dynamic>>[row];

        final result = await repository.listMembershipAuditEvents(
          workspaceId: 'workspace-a',
        );

        expect(
          (result as MembershipAdminFailure<MembershipAuditPage>).kind,
          MembershipAdminFailureKind.infrastructureFailure,
        );
      });

      test('rejects events from a foreign workspace', () async {
        gateway.auditEventsResult = <Map<String, dynamic>>[
          _auditEventJson(
            id: 'event-1',
            action: 'membership.suspend',
            createdAt: '2026-08-28T10:00:00.100000+00:00',
            workspaceId: 'workspace-b',
          ),
        ];

        final result = await repository.listMembershipAuditEvents(
          workspaceId: 'workspace-a',
        );

        expect(
          (result as MembershipAdminFailure<MembershipAuditPage>).kind,
          MembershipAdminFailureKind.infrastructureFailure,
        );
      });

      test('hides infrastructure details on gateway failures', () async {
        gateway.auditEventsError = StateError('sensitive Postgrest detail');

        final result = await repository.listMembershipAuditEvents(
          workspaceId: 'workspace-a',
        );

        final failure = result as MembershipAdminFailure<MembershipAuditPage>;
        expect(failure.kind, MembershipAdminFailureKind.infrastructureFailure);
        expect(failure.message, isNot(contains('sensitive')));
        expect(failure.message, isNot(contains('Postgrest')));
      });
    });
  });
}

MembershipCommandContext _context() {
  return const MembershipCommandContext(
    workspaceId: 'workspace-a',
    actorId: 'actor-a',
    mutationId: 'mutation-a',
    correlationId: 'correlation-a',
    reason: 'Onboarding',
  );
}

InviteMemberCommand _inviteCommand() {
  return InviteMemberCommand(
    context: _context(),
    email: 'invitee@example.com',
    roleId: 'role-a',
  );
}

UpdateMembershipStatusCommand _updateStatusCommand() {
  return UpdateMembershipStatusCommand(
    context: _context(),
    membershipId: 'membership-a',
    newStatus: MembershipStatus.suspended,
    expectedVersion: 1,
  );
}

RevokeInvitationCommand _revokeCommand() {
  return RevokeInvitationCommand(
    context: _context(),
    invitationId: 'invitation-a',
    expectedVersion: 1,
  );
}

Map<String, dynamic> _memberJson({
  String id = 'membership-a',
  String workspaceId = 'workspace-a',
  String status = 'active',
  int version = 1,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'user_id': 'user-a',
    'role_id': 'role-a',
    'status': status,
    'created_at': '2026-07-20T10:00:00Z',
    'updated_at': '2026-07-21T11:00:00Z',
    'created_by': 'actor-a',
    'updated_by': 'actor-a',
    'version': version,
  };
}

Map<String, dynamic> _directoryJson({
  String membershipId = 'membership-a',
  String workspaceId = 'workspace-a',
  String userId = 'user-a',
  String roleKey = 'manager',
  String roleName = 'Manager',
  String status = 'active',
  int version = 1,
  String? displayName = 'Directory Admin',
  String? email = 'admin@example.com',
}) {
  return <String, dynamic>{
    'membership_id': membershipId,
    'workspace_id': workspaceId,
    'user_id': userId,
    'role_id': 'role-a',
    'role_key': roleKey,
    'role_name': roleName,
    'display_name': displayName,
    'email': email,
    'status': status,
    'created_at': '2026-07-20T10:00:00Z',
    'updated_at': '2026-07-21T11:00:00Z',
    'version': version,
  };
}

Map<String, dynamic> _invitationJson({
  String id = 'invitation-a',
  String workspaceId = 'workspace-a',
  String status = 'pending',
  int version = 1,
  String? acceptedMembershipId,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'email': 'invitee@example.com',
    'role_id': 'role-a',
    'status': status,
    'accepted_membership_id': acceptedMembershipId,
    'created_at': '2026-07-20T10:00:00Z',
    'updated_at': '2026-07-21T11:00:00Z',
    'created_by': 'actor-a',
    'updated_by': 'actor-a',
    'version': version,
  };
}

class _FakeMembershipAdminSupabaseGateway
    implements MembershipAdminSupabaseGateway {
  @override
  String? currentUserId = 'actor-a';

  List<Map<String, dynamic>> membershipsResult = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> rolesResult = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> invitationsResult = <Map<String, dynamic>>[];
  Object? rpcResult;
  Object? membershipsError;
  Object? rolesError;
  Object? invitationsError;
  Object? rpcError;

  String? membershipsWorkspaceId;
  String? rolesWorkspaceId;
  String? invitationsWorkspaceId;
  bool? invitationsIncludeResolved;
  int rpcCalls = 0;
  String? rpcFunction;
  Map<String, Object?>? rpcParameters;

  @override
  Future<List<Map<String, dynamic>>> listMemberships({
    required String workspaceId,
  }) async {
    if (membershipsError != null) {
      throw membershipsError!;
    }
    membershipsWorkspaceId = workspaceId;
    return membershipsResult;
  }

  @override
  Future<List<Map<String, dynamic>>> listRoles({
    required String workspaceId,
  }) async {
    if (rolesError != null) {
      throw rolesError!;
    }
    rolesWorkspaceId = workspaceId;
    return rolesResult;
  }

  @override
  Future<List<Map<String, dynamic>>> listInvitations({
    required String workspaceId,
    required bool includeResolved,
  }) async {
    if (invitationsError != null) {
      throw invitationsError!;
    }
    invitationsWorkspaceId = workspaceId;
    invitationsIncludeResolved = includeResolved;
    return invitationsResult;
  }

  @override
  Future<Object?> callRpc(
    String function,
    Map<String, Object?> parameters,
  ) async {
    rpcCalls++;
    rpcFunction = function;
    rpcParameters = parameters;
    if (rpcError != null) {
      throw rpcError!;
    }
    return rpcResult;
  }

  List<Map<String, dynamic>> rolePermissionsResult = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> permissionsResult = <Map<String, dynamic>>[];
  Object? rolePermissionsError;
  Object? permissionsError;
  String? rolePermissionsWorkspaceId;
  List<String>? permissionsRequestedIds;
  int permissionsCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> listRolePermissions({
    required String workspaceId,
  }) async {
    if (rolePermissionsError != null) {
      throw rolePermissionsError!;
    }
    rolePermissionsWorkspaceId = workspaceId;
    return rolePermissionsResult;
  }

  @override
  Future<List<Map<String, dynamic>>> listPermissions({
    required List<String> permissionIds,
  }) async {
    permissionsCalls++;
    if (permissionsError != null) {
      throw permissionsError!;
    }
    permissionsRequestedIds = permissionIds;
    return permissionsResult;
  }

  List<Map<String, dynamic>> auditEventsResult = <Map<String, dynamic>>[];
  Object? auditEventsError;
  String? auditWorkspaceId;
  List<String>? auditEntityTypes;
  int? auditLimit;
  ({String createdAt, String id})? auditBefore;

  @override
  Future<List<Map<String, dynamic>>> listAuditEvents({
    required String workspaceId,
    required List<String> entityTypes,
    required int limit,
    ({String createdAt, String id})? before,
  }) async {
    if (auditEventsError != null) {
      throw auditEventsError!;
    }
    auditWorkspaceId = workspaceId;
    auditEntityTypes = entityTypes;
    auditLimit = limit;
    auditBefore = before;
    return auditEventsResult;
  }
}

Map<String, dynamic> _auditEventJson({
  required String id,
  required String action,
  required String createdAt,
  String entityType = 'membership',
  String workspaceId = 'workspace-a',
  String? actorUserId = 'actor-a',
  String? roleKey = 'manager',
  String? reason,
  Object? oldValues,
  Object? newValues,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'action': action,
    'entity_type': entityType,
    'entity_id': 'entity-$id',
    'actor_user_id': actorUserId,
    'role_key': roleKey,
    'reason': reason,
    'old_values': oldValues,
    'new_values': newValues,
    'created_at': createdAt,
  };
}

Map<String, dynamic> _rolePermissionJson({
  String workspaceId = 'workspace-a',
  String roleId = 'role-a',
  String permissionId = 'perm-1',
}) {
  return <String, dynamic>{
    'workspace_id': workspaceId,
    'role_id': roleId,
    'permission_id': permissionId,
  };
}

Map<String, dynamic> _permissionJson({
  required String id,
  required String key,
  required String name,
}) {
  return <String, dynamic>{'id': id, 'key': key, 'name': name};
}
