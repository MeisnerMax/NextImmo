import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/membership_admin_repository.dart';
import 'package:neximmo_app/features/reference_slice/application/members_admin_controller.dart';
import 'package:neximmo_app/features/reference_slice/presentation/reference_members_screen.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

void main() {
  group('MembersAdminView', () {
    testWidgets('renders the directory with name, email, role and status', (
      tester,
    ) async {
      await _pumpView(tester, state: _readyState());

      expect(find.byKey(const Key('member-card-user-admin')), findsOneWidget);
      expect(find.byKey(const Key('member-card-user-viewer')), findsOneWidget);
      expect(find.text('Directory Admin'), findsOneWidget);
      expect(find.text('admin@example.test'), findsOneWidget);
      expect(find.text('active'), findsOneWidget);
      expect(find.text('suspended'), findsOneWidget);
      expect(find.byKey(const Key('members-invite-card')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a distinct forbidden state for non-managers', (
      tester,
    ) async {
      await _pumpView(
        tester,
        canManage: false,
        state: const MembersAdminState(
          directoryPhase: MembersDirectoryPhase.forbidden,
          pendingPhase: MembersPendingPhase.empty,
        ),
      );

      expect(find.byKey(const Key('members-forbidden')), findsOneWidget);
      expect(find.byKey(const Key('members-invite-card')), findsNothing);
    });

    testWidgets('shows an error state with retry', (tester) async {
      var retried = false;
      await _pumpView(
        tester,
        state: const MembersAdminState(
          directoryPhase: MembersDirectoryPhase.error,
          pendingPhase: MembersPendingPhase.empty,
          message: 'boom',
        ),
        onReloadDirectory: () async => retried = true,
      );

      expect(find.byKey(const Key('members-directory-error')), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('shows a directory skeleton while loading', (tester) async {
      await _pumpView(
        tester,
        settle: false,
        state: const MembersAdminState(
          directoryPhase: MembersDirectoryPhase.loading,
          pendingPhase: MembersPendingPhase.loading,
        ),
      );

      expect(
        find.byKey(const Key('members-directory-skeleton')),
        findsOneWidget,
      );
    });

    testWidgets('offers an accept banner for own pending invitations', (
      tester,
    ) async {
      PendingInvitationEntry? accepted;
      await _pumpView(
        tester,
        state: _readyState(),
        onAcceptOwnInvitation: (entry) async => accepted = entry,
      );

      expect(find.byKey(const Key('members-pending-zone')), findsOneWidget);
      await tester.tap(find.byKey(const Key('members-accept-workspace-x')));
      await tester.pump();
      expect(accepted?.workspaceId, 'workspace-x');
    });

    testWidgets('submits an invite with the entered email and role', (
      tester,
    ) async {
      String? invitedEmail;
      String? invitedRole;
      await _pumpView(
        tester,
        state: _readyState(),
        onInvite: (email, roleId) async {
          invitedEmail = email;
          invitedRole = roleId;
        },
      );

      await tester.enterText(
        find.byKey(const Key('members-invite-email')),
        'newcomer@example.test',
      );
      await tester.tap(find.byKey(const Key('members-invite-submit')));
      await tester.pump();

      expect(invitedEmail, 'newcomer@example.test');
      expect(invitedRole, 'role-manager');
    });

    testWidgets('suspends a member only after confirmation', (tester) async {
      MembershipStatus? newStatus;
      int? expectedVersion;
      await _pumpView(
        tester,
        state: _readyState(),
        onUpdateStatus: (membershipId, status, version) async {
          newStatus = status;
          expectedVersion = version;
        },
      );

      await tester.tap(find.byKey(const Key('member-actions-membership-admin')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspend').last);
      await tester.pumpAndSettle();
      expect(find.text('Suspend member?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('members-confirm')));
      await tester.pumpAndSettle();

      expect(newStatus, MembershipStatus.suspended);
      expect(expectedVersion, 4);
    });

    testWidgets('revokes a pending email invitation after confirmation', (
      tester,
    ) async {
      String? revokedId;
      await _pumpView(
        tester,
        state: _readyState(),
        onRevokeInvitation: (invitationId, version) async =>
            revokedId = invitationId,
      );

      await tester.ensureVisible(
        find.byKey(const Key('invitation-revoke-invitation-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('invitation-revoke-invitation-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('members-confirm')));
      await tester.pumpAndSettle();

      expect(revokedId, 'invitation-1');
    });

    testWidgets('disables mutations and hints when AAL2 is missing', (
      tester,
    ) async {
      await _pumpView(tester, canMutate: false, state: _readyState());

      expect(find.byKey(const Key('members-mfa-hint')), findsOneWidget);
      final invite = tester.widget<FilledButton>(
        find.byKey(const Key('members-invite-submit')),
      );
      expect(invite.onPressed, isNull);
      final actions = tester.widget<PopupMenuButton<String>>(
        find.byKey(const Key('member-actions-membership-admin')),
      );
      expect(actions.enabled, isFalse);
    });

    for (final viewport in const <Size>[
      Size(390, 844),
      Size(1024, 768),
      Size(1440, 900),
    ]) {
      testWidgets('has no overflow at $viewport', (tester) async {
        await _pumpView(tester, state: _readyState(), viewport: viewport);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('members-view')), findsOneWidget);
      });
    }
  });
}

Future<void> _pumpView(
  WidgetTester tester, {
  required MembersAdminState state,
  bool canManage = true,
  bool canMutate = true,
  bool settle = true,
  Size viewport = const Size(1440, 900),
  Future<void> Function()? onReloadDirectory,
  Future<void> Function(String email, String roleId)? onInvite,
  Future<void> Function(String membershipId, MembershipStatus status, int version)?
  onUpdateStatus,
  Future<void> Function(String invitationId, int version)? onRevokeInvitation,
  Future<void> Function(PendingInvitationEntry entry)? onAcceptOwnInvitation,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: MembersAdminView(
          state: state,
          workspaceName: 'Workspace X',
          canManage: canManage,
          canMutate: canMutate,
          onBack: () {},
          onReloadDirectory: onReloadDirectory ?? () async {},
          onReloadPending: () async {},
          onInvite: onInvite ?? (_, __) async {},
          onChangeRole: (_, __, ___) async {},
          onUpdateStatus: onUpdateStatus ?? (_, __, ___) async {},
          onRevokeInvitation: onRevokeInvitation ?? (_, __) async {},
          onAcceptOwnInvitation: onAcceptOwnInvitation ?? (_) async {},
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

MembersAdminState _readyState() {
  return MembersAdminState(
    directoryPhase: MembersDirectoryPhase.ready,
    pendingPhase: MembersPendingPhase.ready,
    directory: <WorkspaceMemberDirectoryEntry>[
      WorkspaceMemberDirectoryEntry(
        membershipId: 'membership-admin',
        workspaceId: 'workspace-x',
        userId: 'user-admin',
        roleId: 'role-manager',
        roleKey: 'manager',
        roleName: 'Manager',
        status: MembershipStatus.active,
        createdAt: DateTime.utc(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 7, 2),
        version: 4,
        displayName: 'Directory Admin',
        email: 'admin@example.test',
      ),
      WorkspaceMemberDirectoryEntry(
        membershipId: 'membership-viewer',
        workspaceId: 'workspace-x',
        userId: 'user-viewer',
        roleId: 'role-viewer',
        roleKey: 'viewer',
        roleName: 'Viewer',
        status: MembershipStatus.suspended,
        createdAt: DateTime.utc(2026, 7, 3),
        updatedAt: DateTime.utc(2026, 7, 4),
        version: 2,
        email: 'viewer@example.test',
      ),
    ],
    roles: const <WorkspaceRole>[
      WorkspaceRole(
        id: 'role-manager',
        workspaceId: 'workspace-x',
        key: 'manager',
        name: 'Manager',
      ),
      WorkspaceRole(
        id: 'role-viewer',
        workspaceId: 'workspace-x',
        key: 'viewer',
        name: 'Viewer',
      ),
    ],
    invitations: <MembershipInvitation>[
      MembershipInvitation(
        id: 'invitation-1',
        workspaceId: 'workspace-x',
        email: 'ghost@example.test',
        roleId: 'role-viewer',
        status: MembershipInvitationStatus.pending,
        createdAt: DateTime.utc(2026, 7, 5),
        updatedAt: DateTime.utc(2026, 7, 5),
        version: 1,
      ),
    ],
    pending: <PendingInvitationEntry>[
      PendingInvitationEntry(
        isMembership: true,
        workspaceId: 'workspace-x',
        workspaceName: 'Workspace X',
        roleKey: 'viewer',
        roleName: 'Viewer',
        createdAt: DateTime.utc(2026, 7, 6),
        version: 1,
        membershipId: 'membership-self',
      ),
    ],
  );
}
