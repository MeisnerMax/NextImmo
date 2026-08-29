import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/members_admin_controller.dart';
import 'package:neximmo_app/features/identity_access/application/membership_admin_repository.dart';
import 'package:neximmo_app/features/identity_access/presentation/admin_members_screen.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// ADMIN-AREA-01 A1 widget contract for the V2 Mitglieder screen:
/// German product surface, tabs Mitglieder/Einladungen/Rollen (no Aktivität),
/// split detail with narrow replace-with-back, mandatory mobileChild, typed
/// nullable filters with revoked hidden by default, honest invite UX, capability
/// diff on role changes, conflict UX that preserves input, and no password UI.
void main() {
  group('frame', () {
    testWidgets('renders header, all three tabs and no activity tab', (
      tester,
    ) async {
      await _pumpView(tester, state: _readyState());

      expect(find.byKey(const Key('admin-members-header')), findsOneWidget);
      expect(
        find.byKey(const Key('admin-members-tab-members')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('admin-members-tab-invitations')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('admin-members-tab-roles')), findsOneWidget);
      expect(find.text('Aktivität'), findsNothing);
      expect(find.byKey(const Key('admin-members-refresh')), findsOneWidget);
      expect(find.byKey(const Key('admin-members-invite')), findsOneWidget);
    });

    testWidgets(
      'keeps the pending accept zone functional (package B pending)',
      (tester) async {
        var accepted = 0;
        await _pumpView(
          tester,
          state: _readyState(),
          onAcceptOwnInvitation: (_) async {
            accepted += 1;
          },
        );

        expect(
          find.byKey(const Key('admin-members-pending-zone')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('admin-members-accept-ws-2')));
        await tester.pumpAndSettle();
        expect(accepted, 1);
      },
    );
  });

  group('directory states', () {
    testWidgets('loading renders the shared skeleton', (tester) async {
      await _pumpView(
        tester,
        state: _state(directoryPhase: MembersTabPhase.loading),
        settle: false,
      );
      expect(
        find.byKey(const Key('admin-members-directory-skeleton')),
        findsOneWidget,
      );
    });

    testWidgets('idle, empty, forbidden and error states render', (
      tester,
    ) async {
      await _pumpView(
        tester,
        state: _state(directoryPhase: MembersTabPhase.idle),
      );
      expect(
        find.byKey(const Key('admin-members-directory-idle')),
        findsOneWidget,
      );

      await _pumpView(
        tester,
        state: _state(directoryPhase: MembersTabPhase.empty),
      );
      expect(
        find.byKey(const Key('admin-members-directory-empty')),
        findsOneWidget,
      );

      await _pumpView(
        tester,
        state: _state(directoryPhase: MembersTabPhase.forbidden),
      );
      expect(
        find.byKey(const Key('admin-members-directory-forbidden')),
        findsOneWidget,
      );

      var retried = 0;
      await _pumpView(
        tester,
        state: _state(directoryPhase: MembersTabPhase.error),
        onReloadDirectory: () async {
          retried += 1;
        },
      );
      expect(
        find.byKey(const Key('admin-members-directory-error')),
        findsOneWidget,
      );
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect(retried, 1);
    });
  });

  group('split and narrow layout', () {
    testWidgets('desktop shows table and detail side by side', (tester) async {
      await _pumpView(tester, state: _readyState());

      expect(find.byType(DataTable), findsOneWidget);
      expect(
        find.byKey(const Key('admin-members-detail-idle')),
        findsOneWidget,
      );

      await tester.tap(find.text('Clara Admin').first);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-members-detail')), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('narrow replaces the list with the detail and back returns', (
      tester,
    ) async {
      await _pumpView(
        tester,
        state: _readyState(),
        viewport: const Size(1024, 768),
      );

      expect(find.byKey(const Key('admin-members-detail')), findsNothing);
      await tester.tap(find.text('Clara Admin').first);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-members-detail')), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-members-detail')), findsNothing);
      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('mobile renders the mandatory mobileChild list', (
      tester,
    ) async {
      await _pumpView(
        tester,
        state: _readyState(),
        viewport: const Size(390, 844),
      );

      expect(
        find.byKey(const Key('admin-members-mobile-list')),
        findsOneWidget,
      );
      await _dragIntoView(
        tester,
        target: find.byKey(const Key('admin-members-mobile-row-m-1')),
        scrollable:
            find
                .descendant(
                  of: find.byKey(const Key('admin-members-mobile-list')),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      expect(
        find.byKey(const Key('admin-members-mobile-row-m-1')),
        findsOneWidget,
      );
      expect(find.byType(DataTable), findsNothing);
    });

    for (final viewport in const <Size>[
      Size(320, 700),
      Size(390, 844),
      Size(1024, 768),
      Size(1440, 900),
    ]) {
      testWidgets('renders without overflow at ${viewport.width.toInt()}px', (
        tester,
      ) async {
        await _pumpView(tester, state: _readyState(), viewport: viewport);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('search and filters', () {
    testWidgets('search narrows by name and email', (tester) async {
      await _pumpView(tester, state: _readyState());

      await tester.enterText(
        find.byKey(const Key('admin-members-search')),
        'clara',
      );
      await tester.pumpAndSettle();

      expect(find.text('Clara Admin'), findsWidgets);
      expect(find.text('Ben Viewer'), findsNothing);
    });

    testWidgets('role filter is a typed nullable dropdown', (tester) async {
      await _pumpView(tester, state: _readyState());

      await tester.tap(find.byKey(const Key('admin-members-role-filter')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin-members-role-filter-role-viewer')).last,
      );
      await tester.pumpAndSettle();

      expect(find.text('Ben Viewer'), findsWidgets);
      expect(find.text('Clara Admin'), findsNothing);
    });

    testWidgets('revoked members are hidden by default and shown on demand', (
      tester,
    ) async {
      await _pumpView(tester, state: _readyState());

      expect(find.text('Rita Revoked'), findsNothing);

      await tester.tap(find.byKey(const Key('admin-members-status-filter')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin-members-status-filter-revoked')).last,
      );
      await tester.pumpAndSettle();

      expect(find.text('Rita Revoked'), findsWidgets);
      expect(find.text('Clara Admin'), findsNothing);
    });

    testWidgets('active filters with no hits render the no-match state', (
      tester,
    ) async {
      await _pumpView(tester, state: _readyState());

      await tester.enterText(
        find.byKey(const Key('admin-members-search')),
        'gibtesnicht',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-members-no-match')), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-members-reset-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Clara Admin'), findsWidgets);
    });
  });

  group('invite dialog', () {
    testWidgets('validates email and requires an explicit role choice', (
      tester,
    ) async {
      await _pumpView(tester, state: _readyState());

      await tester.tap(find.byKey(const Key('admin-members-invite')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('admin-members-invite-dialog')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('admin-members-invite-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Pflichtfeld'), findsNWidgets(2));

      await tester.enterText(
        find.byKey(const Key('admin-members-invite-email')),
        'keineemail',
      );
      await tester.tap(find.byKey(const Key('admin-members-invite-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Ungültige E-Mail-Adresse.'), findsOneWidget);
    });

    testWidgets('submits email, role and reason and closes on success', (
      tester,
    ) async {
      String? invitedEmail;
      String? invitedRole;
      String? invitedReason;
      await _pumpView(
        tester,
        state: _readyState(),
        onInvite: ({required email, required roleId, reason}) async {
          invitedEmail = email;
          invitedRole = roleId;
          invitedReason = reason;
          return const MembersActionOutcome(
            kind: MembersActionResultKind.success,
            message: 'Einladung angelegt.',
          );
        },
      );

      await tester.tap(find.byKey(const Key('admin-members-invite')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('admin-members-invite-email')),
        'neu@neximmo.de',
      );
      await tester.tap(find.byKey(const Key('admin-members-invite-role')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin-members-invite-role-role-viewer')).last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('admin-members-invite-reason')),
        'Onboarding',
      );
      await tester.tap(find.byKey(const Key('admin-members-invite-submit')));
      await tester.pumpAndSettle();

      expect(invitedEmail, 'neu@neximmo.de');
      expect(invitedRole, 'role-viewer');
      expect(invitedReason, 'Onboarding');
      expect(
        find.byKey(const Key('admin-members-invite-dialog')),
        findsNothing,
      );
    });

    testWidgets('a duplicate keeps the dialog open with the input preserved', (
      tester,
    ) async {
      await _pumpView(
        tester,
        state: _readyState(),
        onInvite: ({required email, required roleId, reason}) async {
          return const MembersActionOutcome(
            kind: MembersActionResultKind.validationFailed,
            message:
                'Diese E-Mail-Adresse hat bereits eine Mitgliedschaft in '
                'diesem Workspace.',
          );
        },
      );

      await tester.tap(find.byKey(const Key('admin-members-invite')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('admin-members-invite-email')),
        'doppelt@neximmo.de',
      );
      await tester.tap(find.byKey(const Key('admin-members-invite-role')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin-members-invite-role-role-viewer')).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin-members-invite-submit')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin-members-invite-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('admin-members-invite-error')),
        findsOneWidget,
      );
      expect(find.text('doppelt@neximmo.de'), findsOneWidget);
    });
  });

  group('change role dialog', () {
    testWidgets('shows the capability diff before saving', (tester) async {
      await _pumpView(tester, state: _readyState());
      await _openDetail(tester, 'Clara Admin');

      await _tapDetailAction(tester, 'admin-members-action-change-role');
      await tester.tap(
        find.byKey(const Key('admin-members-role-dialog-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(const Key('admin-members-role-dialog-option-role-viewer'))
            .last,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin-members-role-dialog-diff')),
        findsOneWidget,
      );
      expect(find.textContaining('Entfallen'), findsOneWidget);
    });

    testWidgets(
      'a manage-role demotion asks for explicit confirmation, then submits',
      (tester) async {
        String? newRole;
        int? version;
        await _pumpView(
          tester,
          state: _readyState(),
          onChangeRole: ({
            required membershipId,
            required newRoleId,
            required expectedVersion,
            reason,
          }) async {
            newRole = newRoleId;
            version = expectedVersion;
            return const MembersActionOutcome(
              kind: MembersActionResultKind.success,
              message: 'Rolle aktualisiert.',
            );
          },
        );
        await _openDetail(tester, 'Clara Admin');
        await _tapDetailAction(tester, 'admin-members-action-change-role');
        await tester.tap(
          find.byKey(const Key('admin-members-role-dialog-dropdown')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .byKey(const Key('admin-members-role-dialog-option-role-viewer'))
              .last,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('admin-members-role-dialog-submit')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('admin-members-role-guard-confirm')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('admin-members-role-guard-confirm')),
        );
        await tester.pumpAndSettle();

        expect(newRole, 'role-viewer');
        expect(version, 3);
        expect(
          find.byKey(const Key('admin-members-role-dialog')),
          findsNothing,
        );
      },
    );

    testWidgets('a version conflict keeps input and retries with the server '
        'version', (tester) async {
      final calls = <int>[];
      await _pumpView(
        tester,
        state: _readyState(),
        onChangeRole: ({
          required membershipId,
          required newRoleId,
          required expectedVersion,
          reason,
        }) async {
          calls.add(expectedVersion);
          if (calls.length == 1) {
            return MembersActionOutcome(
              kind: MembersActionResultKind.versionConflict,
              message: 'Der Datensatz wurde zwischenzeitlich geändert.',
              conflict: MembershipVersionConflict(
                expectedVersion: expectedVersion,
                actualVersion: 7,
                currentMember: _memberFixture('m-1', version: 7),
              ),
            );
          }
          return const MembersActionOutcome(
            kind: MembersActionResultKind.success,
            message: 'Rolle aktualisiert.',
          );
        },
      );
      await _openDetail(tester, 'Clara Admin');
      await _tapDetailAction(tester, 'admin-members-action-change-role');
      await tester.tap(
        find.byKey(const Key('admin-members-role-dialog-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(const Key('admin-members-role-dialog-option-role-viewer'))
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin-members-role-dialog-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin-members-role-guard-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin-members-role-dialog-conflict')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('admin-members-role-dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('admin-members-role-dialog-retry')),
      );
      await tester.pumpAndSettle();

      expect(calls, <int>[3, 7]);
      expect(find.byKey(const Key('admin-members-role-dialog')), findsNothing);
    });

    testWidgets('the last-security-manager refusal is explained inline', (
      tester,
    ) async {
      await _pumpView(
        tester,
        state: _readyState(),
        onChangeRole: ({
          required membershipId,
          required newRoleId,
          required expectedVersion,
          reason,
        }) async {
          return const MembersActionOutcome(
            kind: MembersActionResultKind.lastSecurityManager,
            message:
                'Diese Person ist die letzte Person mit Sicherheitsverwaltung '
                'in diesem Workspace. Übertrage die Berechtigung zuerst an '
                'jemand anderen.',
          );
        },
      );
      await _openDetail(tester, 'Clara Admin');
      await _tapDetailAction(tester, 'admin-members-action-change-role');
      await tester.tap(
        find.byKey(const Key('admin-members-role-dialog-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(const Key('admin-members-role-dialog-option-role-viewer'))
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin-members-role-dialog-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin-members-role-guard-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin-members-role-dialog-error')),
        findsOneWidget,
      );
      expect(find.textContaining('Sicherheitsverwaltung'), findsWidgets);
      expect(
        find.byKey(const Key('admin-members-role-dialog')),
        findsOneWidget,
      );
    });
  });

  group('status actions', () {
    testWidgets('suspend confirms with the member named and submits', (
      tester,
    ) async {
      MembershipStatus? status;
      int? version;
      await _pumpView(
        tester,
        state: _readyState(),
        onUpdateStatus: ({
          required membershipId,
          required newStatus,
          required expectedVersion,
          reason,
        }) async {
          status = newStatus;
          version = expectedVersion;
          return const MembersActionOutcome(
            kind: MembersActionResultKind.success,
            message: 'Mitglied suspendiert.',
          );
        },
      );
      await _openDetail(tester, 'Clara Admin');

      await _tapDetailAction(tester, 'admin-members-action-suspend');
      expect(find.textContaining('Clara Admin'), findsWidgets);
      await tester.tap(find.byKey(const Key('admin-members-confirm')));
      await tester.pumpAndSettle();

      expect(status, MembershipStatus.suspended);
      expect(version, 3);
    });

    testWidgets('a suspended member offers reactivate', (tester) async {
      MembershipStatus? status;
      await _pumpView(
        tester,
        state: _readyState(),
        onUpdateStatus: ({
          required membershipId,
          required newStatus,
          required expectedVersion,
          reason,
        }) async {
          status = newStatus;
          return const MembersActionOutcome(
            kind: MembersActionResultKind.success,
            message: 'Mitglied reaktiviert.',
          );
        },
      );
      await _openDetail(tester, 'Susi Suspendiert');

      expect(
        find.byKey(const Key('admin-members-action-suspend')),
        findsNothing,
      );
      await _tapDetailAction(tester, 'admin-members-action-reactivate');
      await tester.tap(find.byKey(const Key('admin-members-confirm')));
      await tester.pumpAndSettle();

      expect(status, MembershipStatus.active);
    });

    testWidgets('revoke is labelled permanent and submits revoked', (
      tester,
    ) async {
      MembershipStatus? status;
      await _pumpView(
        tester,
        state: _readyState(),
        onUpdateStatus: ({
          required membershipId,
          required newStatus,
          required expectedVersion,
          reason,
        }) async {
          status = newStatus;
          return const MembersActionOutcome(
            kind: MembersActionResultKind.success,
            message: 'Zugriff entzogen.',
          );
        },
      );
      await _openDetail(tester, 'Clara Admin');

      await _tapDetailAction(tester, 'admin-members-action-revoke');
      expect(find.textContaining('Endgültig'), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-members-confirm')));
      await tester.pumpAndSettle();

      expect(status, MembershipStatus.revoked);
    });

    testWidgets('a last-manager refusal after a confirm flow is explained in a '
        'snackbar', (tester) async {
      await _pumpView(
        tester,
        state: _readyState(),
        onUpdateStatus: ({
          required membershipId,
          required newStatus,
          required expectedVersion,
          reason,
        }) async {
          return const MembersActionOutcome(
            kind: MembersActionResultKind.lastSecurityManager,
            message:
                'Diese Person ist die letzte Person mit Sicherheitsverwaltung '
                'in diesem Workspace. Übertrage die Berechtigung zuerst an '
                'jemand anderen.',
          );
        },
      );
      await _openDetail(tester, 'Clara Admin');

      await _tapDetailAction(tester, 'admin-members-action-suspend');
      await tester.tap(find.byKey(const Key('admin-members-confirm')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sicherheitsverwaltung'), findsWidgets);
      expect(find.textContaining('Clara Admin'), findsWidgets);
    });
  });

  group('AAL gating', () {
    testWidgets('below AAL2 mutations are disabled with the MFA notice shown', (
      tester,
    ) async {
      await _pumpView(tester, state: _readyState(), canMutate: false);

      expect(find.byKey(const Key('admin-members-mfa-hint')), findsOneWidget);
      final invite = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('admin-members-invite')),
          matching: find.bySubtype<FilledButton>(),
        ),
      );
      expect(invite.onPressed, isNull);

      await _openDetail(tester, 'Clara Admin');
      final suspend = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const Key('admin-members-action-suspend')),
          matching: find.bySubtype<OutlinedButton>(),
        ),
      );
      expect(suspend.onPressed, isNull);
    });
  });

  group('invitations tab', () {
    testWidgets('lists open invitations and revokes after confirmation', (
      tester,
    ) async {
      String? revokedId;
      int? revokedVersion;
      await _pumpView(
        tester,
        state: _readyState(),
        onRevokeInvitation: ({
          required invitationId,
          required expectedVersion,
          reason,
        }) async {
          revokedId = invitationId;
          revokedVersion = expectedVersion;
          return const MembersActionOutcome(
            kind: MembersActionResultKind.success,
            message: 'Einladung widerrufen.',
          );
        },
      );

      await tester.tap(find.byKey(const Key('admin-members-tab-invitations')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin-members-invitation-card-inv-1')),
        findsOneWidget,
      );
      expect(find.text('Erneut senden'), findsNothing);

      await tester.tap(
        find.byKey(const Key('admin-members-invitation-revoke-inv-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin-members-confirm')));
      await tester.pumpAndSettle();

      expect(revokedId, 'inv-1');
      expect(revokedVersion, 2);
    });

    testWidgets('empty invitations state renders', (tester) async {
      await _pumpView(
        tester,
        state: _readyState(invitations: const <MembershipInvitation>[]),
      );
      await tester.tap(find.byKey(const Key('admin-members-tab-invitations')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('admin-members-invitations-empty')),
        findsOneWidget,
      );
    });
  });

  group('roles tab', () {
    testWidgets(
      'is read-only: capability lists but no management affordances',
      (tester) async {
        await _pumpView(tester, state: _readyState());

        await tester.tap(find.byKey(const Key('admin-members-tab-roles')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('admin-members-role-card-role-admin')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('admin-members-role-card-role-viewer')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('admin-members-roles-hint')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('admin-members-role-card-role-admin')),
        );
        await tester.pumpAndSettle();
        expect(find.text('security.manage'), findsWidgets);

        expect(find.text('Rolle anlegen'), findsNothing);
        expect(find.text('Rolle bearbeiten'), findsNothing);
        expect(find.byIcon(Icons.edit_outlined), findsNothing);
      },
    );
  });

  group('no password UI', () {
    testWidgets('no tab contains any password affordance', (tester) async {
      await _pumpView(tester, state: _readyState());
      expect(find.textContaining('asswort'), findsNothing);

      await tester.tap(find.byKey(const Key('admin-members-tab-invitations')));
      await tester.pumpAndSettle();
      expect(find.textContaining('asswort'), findsNothing);

      await tester.tap(find.byKey(const Key('admin-members-tab-roles')));
      await tester.pumpAndSettle();
      expect(find.textContaining('asswort'), findsNothing);
    });
  });
}

Future<void> _openDetail(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('admin-members-detail')), findsOneWidget);
}

/// Drags [scrollable] until [target] is hit-testable. Deliberately avoids
/// ensureVisible/scrollUntilVisible: both end in Scrollable.ensureVisible,
/// which recurses into the enclosing TabBarView PageView and pages the tab
/// away, unmounting the target.
Future<void> _dragIntoView(
  WidgetTester tester, {
  required Finder target,
  required Finder scrollable,
}) async {
  for (var i = 0; i < 30 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -80), warnIfMissed: false);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Detail actions can sit below the fold of the detail pane's scroll region —
/// bring them into view (detail pane scroll only), then tap.
Future<void> _tapDetailAction(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await _dragIntoView(
    tester,
    target: target,
    scrollable:
        find
            .descendant(
              of: find.byKey(const Key('admin-members-detail')),
              matching: find.byType(Scrollable),
            )
            .first,
  );
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _pumpView(
  WidgetTester tester, {
  required MembersAdminState state,
  bool canManage = true,
  bool canMutate = true,
  bool settle = true,
  Size viewport = const Size(1440, 900),
  Future<void> Function()? onReloadDirectory,
  AdminMembersInviteSubmit? onInvite,
  AdminMembersChangeRoleSubmit? onChangeRole,
  AdminMembersUpdateStatusSubmit? onUpdateStatus,
  AdminMembersRevokeInvitationSubmit? onRevokeInvitation,
  Future<void> Function(PendingInvitationEntry entry)? onAcceptOwnInvitation,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const successOutcome = MembersActionOutcome(
    kind: MembersActionResultKind.success,
    message: 'Ok.',
  );

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: AdminMembersView(
          state: state,
          workspaceName: 'Workspace X',
          canManage: canManage,
          canMutate: canMutate,
          onRefresh: () async {},
          onReloadDirectory: onReloadDirectory ?? () async {},
          onReloadInvitations: () async {},
          onReloadRoles: () async {},
          onReloadPending: () async {},
          onInvite:
              onInvite ??
              ({required email, required roleId, reason}) async =>
                  successOutcome,
          onChangeRole:
              onChangeRole ??
              ({
                required membershipId,
                required newRoleId,
                required expectedVersion,
                reason,
              }) async => successOutcome,
          onUpdateStatus:
              onUpdateStatus ??
              ({
                required membershipId,
                required newStatus,
                required expectedVersion,
                reason,
              }) async => successOutcome,
          onRevokeInvitation:
              onRevokeInvitation ??
              ({
                required invitationId,
                required expectedVersion,
                reason,
              }) async => successOutcome,
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

MembersAdminState _state({
  MembersTabPhase directoryPhase = MembersTabPhase.ready,
  MembersTabPhase invitationsPhase = MembersTabPhase.empty,
  MembersTabPhase rolesPhase = MembersTabPhase.ready,
}) {
  return MembersAdminState(
    directoryPhase: directoryPhase,
    invitationsPhase: invitationsPhase,
    rolesPhase: rolesPhase,
    pendingPhase: MembersPendingPhase.empty,
  );
}

MembersAdminState _readyState({List<MembershipInvitation>? invitations}) {
  return MembersAdminState(
    directoryPhase: MembersTabPhase.ready,
    invitationsPhase:
        (invitations ?? _invitationsFixture()).isEmpty
            ? MembersTabPhase.empty
            : MembersTabPhase.ready,
    rolesPhase: MembersTabPhase.ready,
    pendingPhase: MembersPendingPhase.ready,
    directory: <WorkspaceMemberDirectoryEntry>[
      _entryFixture(
        'm-1',
        name: 'Clara Admin',
        email: 'clara@neximmo.de',
        roleId: 'role-admin',
        version: 3,
      ),
      _entryFixture(
        'm-2',
        name: 'Ben Viewer',
        email: 'ben@neximmo.de',
        roleId: 'role-viewer',
      ),
      _entryFixture(
        'm-3',
        name: 'Rita Revoked',
        email: 'rita@neximmo.de',
        status: MembershipStatus.revoked,
      ),
      _entryFixture(
        'm-4',
        name: 'Susi Suspendiert',
        email: 'susi@neximmo.de',
        status: MembershipStatus.suspended,
        version: 5,
      ),
    ],
    roles: <WorkspaceRole>[
      const WorkspaceRole(
        id: 'role-admin',
        workspaceId: 'ws-1',
        key: 'admin',
        name: 'Administration',
      ),
      const WorkspaceRole(
        id: 'role-viewer',
        workspaceId: 'ws-1',
        key: 'viewer',
        name: 'Betrachtung',
      ),
    ],
    roleCapabilities: <WorkspaceRoleCapability>[
      const WorkspaceRoleCapability(
        roleId: 'role-admin',
        permissionKey: 'security.manage',
        permissionName: 'Sicherheitsverwaltung',
      ),
      const WorkspaceRoleCapability(
        roleId: 'role-admin',
        permissionKey: 'workspace.read',
        permissionName: 'Workspace lesen',
      ),
      const WorkspaceRoleCapability(
        roleId: 'role-admin',
        permissionKey: 'property.read',
        permissionName: 'Objekte lesen',
      ),
      const WorkspaceRoleCapability(
        roleId: 'role-viewer',
        permissionKey: 'property.read',
        permissionName: 'Objekte lesen',
      ),
    ],
    invitations: invitations ?? _invitationsFixture(),
    pending: <PendingInvitationEntry>[
      PendingInvitationEntry(
        isMembership: true,
        workspaceId: 'ws-2',
        workspaceName: 'Workspace Zwei',
        roleKey: 'viewer',
        roleName: 'Betrachtung',
        createdAt: DateTime.utc(2026, 2, 1),
        version: 1,
        membershipId: 'm-pending',
      ),
    ],
  );
}

List<MembershipInvitation> _invitationsFixture() {
  return <MembershipInvitation>[
    MembershipInvitation(
      id: 'inv-1',
      workspaceId: 'ws-1',
      email: 'gast@neximmo.de',
      roleId: 'role-viewer',
      status: MembershipInvitationStatus.pending,
      createdAt: DateTime.utc(2026, 3, 1),
      updatedAt: DateTime.utc(2026, 3, 1),
      version: 2,
    ),
  ];
}

WorkspaceMemberDirectoryEntry _entryFixture(
  String membershipId, {
  required String name,
  required String email,
  String roleId = 'role-admin',
  MembershipStatus status = MembershipStatus.active,
  int version = 1,
}) {
  return WorkspaceMemberDirectoryEntry(
    membershipId: membershipId,
    workspaceId: 'ws-1',
    userId: 'user-$membershipId',
    roleId: roleId,
    roleKey: roleId == 'role-admin' ? 'admin' : 'viewer',
    roleName: roleId == 'role-admin' ? 'Administration' : 'Betrachtung',
    status: status,
    createdAt: DateTime.utc(2026, 1, 15),
    updatedAt: DateTime.utc(2026, 1, 20),
    version: version,
    displayName: name,
    email: email,
  );
}

WorkspaceMember _memberFixture(String membershipId, {int version = 1}) {
  return WorkspaceMember(
    membershipId: membershipId,
    workspaceId: 'ws-1',
    userId: 'user-$membershipId',
    roleId: 'role-admin',
    status: MembershipStatus.active,
    createdAt: DateTime.utc(2026, 1, 15),
    updatedAt: DateTime.utc(2026, 1, 20),
    version: version,
  );
}
