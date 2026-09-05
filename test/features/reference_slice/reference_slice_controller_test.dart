import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/identity_access/application/entitlement_invalidation_source.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_query_invalidation_source.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';

void main() {
  group('ReferenceSliceController', () {
    late _FakeIdentityRepository identity;
    late _FakePropertyRepository properties;
    late _FakePropertyInvalidationSource invalidations;
    late _FakeEntitlementInvalidationSource entitlementInvalidations;
    late ReferenceSliceController controller;
    late Queue<String> ids;

    setUp(() {
      identity = _FakeIdentityRepository();
      properties = _FakePropertyRepository();
      invalidations = _FakePropertyInvalidationSource();
      entitlementInvalidations = _FakeEntitlementInvalidationSource();
      ids = Queue<String>.of(<String>['mutation-a', 'correlation-a']);
      controller = ReferenceSliceController(
        identityRepository: identity,
        propertyRepository: properties,
        propertyInvalidationSource: invalidations,
        entitlementInvalidationSource: entitlementInvalidations,
        entitlementRevalidationInterval: const Duration(hours: 1),
        idFactory: () => ids.removeFirst(),
      );
    });

    tearDown(() async {
      controller.dispose();
      await _flushEvents();
      await identity.close();
      await invalidations.close();
      await entitlementInvalidations.close();
    });

    test('stays unprivileged without an authenticated session', () async {
      await controller.start();

      expect(controller.state.authPhase, ReferenceAuthPhase.unauthenticated);
      expect(controller.state.workspacePhase, WorkspacePhase.idle);
      expect(properties.listCalls, 0);
      expect(identity.listCalls, 0);
    });

    test('signs in with email and password', () async {
      await controller.start();

      await controller.signInWithPassword('user@example.test', 'correct-horse');

      expect(identity.passwordSignIns, hasLength(1));
      expect(identity.passwordSignIns.single.email, 'user@example.test');
      expect(identity.passwordSignIns.single.password, 'correct-horse');
      // No magic link is sent on the primary path any more.
      expect(identity.passwordlessEmails, isEmpty);
      expect(controller.state.authActionPhase, ReferenceAuthActionPhase.idle);
      // Nothing about the credentials is echoed back into the state.
      expect(controller.state.authMessage, isNull);
    });

    test('reports a generic message for wrong credentials', () async {
      identity.passwordResult = const IdentityAccessFailure<void>(
        kind: IdentityAccessFailureKind.invalidCredentials,
        message: 'Email or password is incorrect.',
      );
      await controller.start();

      await controller.signInWithPassword('user@example.test', 'wrong');

      expect(controller.state.authActionPhase, ReferenceAuthActionPhase.failed);
      // Must not disclose whether the account exists.
      expect(controller.state.authMessage, 'Email or password is incorrect.');
      expect(controller.state.authMessage, isNot(contains('not found')));
      expect(controller.state.authMessage, isNot(contains('no account')));
    });

    test('ignores a second submit while a sign-in is in flight', () async {
      await controller.start();

      final first = controller.signInWithPassword('user@example.test', 'pw');
      final second = controller.signInWithPassword('user@example.test', 'pw');
      await Future.wait(<Future<void>>[first, second]);

      expect(identity.passwordSignIns, hasLength(1));
    });

    test('blocks all data while an enrolled MFA factor is pending', () async {
      identity.currentSession = const AuthenticatedSession(
        userId: 'user-a',
        currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
        nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
      );
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(id: 'factor-a', friendlyName: 'Primary'),
      ]);

      await controller.start();

      expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
      expect(controller.state.totpFactors.single.id, 'factor-a');
      expect(controller.state.workspacePhase, WorkspacePhase.idle);
      expect(identity.listCalls, 0);
      expect(properties.listCalls, 0);
    });

    test(
      'verifies an existing TOTP factor and loads authorized data',
      () async {
        identity.currentSession = const AuthenticatedSession(
          userId: 'user-a',
          currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
          nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
        );
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(id: 'factor-a', friendlyName: 'Primary'),
        ]);
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read'}),
          ],
        );

        await controller.start();
        await controller.verifyTotp(factorId: 'factor-a', code: '123456');

        expect(controller.state.authPhase, ReferenceAuthPhase.authenticated);
        expect(
          controller.state.assuranceLevel,
          AuthenticationAssuranceLevel.aal2,
        );
        expect(controller.state.totpFactors, isEmpty);
        expect(identity.challengedFactorIds, <String>['factor-a']);
        expect(identity.verifiedCodes, <String>['123456']);
        expect(identity.enrollmentCalls, 0, reason: 'nothing to enrol');
        expect(identity.unenrolledFactorIds, isEmpty);
        expect(controller.state.selectedWorkspaceId, 'workspace-a');
        expect(identity.listCalls, 1, reason: 'business load only after aal2');
      },
    );

    test('enrolls TOTP, verifies it and clears secrets on sign-out', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );

      await controller.start();
      await controller.beginTotpEnrollment();

      expect(
        controller.state.authActionPhase,
        ReferenceAuthActionPhase.enrollmentReady,
      );
      expect(controller.state.totpEnrollment?.secret, 'sensitive-secret');

      await controller.verifyTotp(factorId: 'factor-new', code: '654321');
      expect(
        controller.state.assuranceLevel,
        AuthenticationAssuranceLevel.aal2,
      );
      expect(controller.state.totpEnrollment, isNull);

      await controller.signOut();
      expect(controller.state.authPhase, ReferenceAuthPhase.unauthenticated);
      expect(controller.state.properties, isEmpty);
      expect(controller.state.totpEnrollment, isNull);
      expect(identity.signOutCalls, 1);
    });

    // SECURITY-AAL-CLIENT-02. DEC-025 made aal2 the server-side boundary for
    // every workspace business surface, so an aal1 session is an incomplete
    // authentication, not an account without access. The client has to reach
    // that conclusion on its own: a denied read now answers 200 with an empty
    // body, which is indistinguishable from "no workspaces" if the client waits
    // for the server to tell it.
    test(
      'a factorless aal1 session is MFA-required, not authenticated',
      () async {
        // current == next == aal1: an administratively created user who has not
        // enrolled a factor yet. There is no challenge to answer, only an
        // enrolment to complete.
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        identity.factorsResult = _inventory(const <TotpFactor>[]);

        await controller.start();

        expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.enrollmentRequired,
        );
        expect(controller.state.workspacePhase, WorkspacePhase.idle);
        expect(identity.listCalls, 0, reason: 'no workspace read below aal2');
        expect(properties.listCalls, 0, reason: 'no property read below aal2');
      },
    );

    test('a factorless aal1 session can enrol its first factor', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[]);
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );

      await controller.start();
      // Enrolment has to be reachable from mfaRequired -- that is the only
      // state a factorless user can ever be in.
      await controller.beginTotpEnrollment();

      expect(
        controller.state.authActionPhase,
        ReferenceAuthActionPhase.enrollmentReady,
      );
      expect(identity.listCalls, 0, reason: 'still below aal2');

      await controller.verifyTotp(factorId: 'factor-new', code: '654321');

      expect(controller.state.authPhase, ReferenceAuthPhase.authenticated);
      expect(
        controller.state.assuranceLevel,
        AuthenticationAssuranceLevel.aal2,
      );
      expect(identity.listCalls, 1, reason: 'business load starts only now');
    });

    test(
      'an assurance downgrade leaves the business shell fail-closed',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read'}),
          ],
        );

        await controller.start();
        expect(controller.state.authPhase, ReferenceAuthPhase.authenticated);
        expect(controller.state.selectedWorkspaceId, 'workspace-a');

        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(id: 'factor-a', friendlyName: 'Primary'),
        ]);
        identity.emit(
          const AuthenticatedSession(
            userId: 'user-a',
            currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
            nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
        expect(controller.state.workspacePhase, WorkspacePhase.idle);
        expect(controller.state.selectedWorkspaceId, isNull);
        expect(controller.state.properties, isEmpty);
        expect(controller.state.selectedProperty, isNull);
      },
    );

    test(
      'a factor lookup failure is an MFA error, not an empty workspace',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        identity
            .factorsResult = const IdentityAccessFailure<TotpFactorInventory>(
          kind: IdentityAccessFailureKind.infrastructureFailure,
          message: 'Factor lookup failed.',
        );

        await controller.start();

        expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.failed,
        );
        expect(controller.state.workspacePhase, WorkspacePhase.idle);
        expect(identity.listCalls, 0);
        expect(properties.listCalls, 0);
        expect(identity.enrollmentCalls, 0, reason: 'unknown state: no enrol');
      },
    );

    // === SECURITY-AAL-CLIENT-03: interrupted enrolment ==================
    //
    // GoTrue keeps an enrolled-but-unverified factor when a setup is abandoned
    // before the first code is accepted. The client read only the verified
    // list, so it saw such an account as factorless and offered a fresh
    // enrolment -- which GoTrue then refused, because the abandoned factor
    // already holds the friendly name. The user was locked out of enrolling
    // for good, and told it was temporary.

    test('an unverified factor is recovery, not a fresh enrolment', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);

      await controller.start();

      expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
      expect(
        controller.state.authActionPhase,
        ReferenceAuthActionPhase.interruptedEnrollmentRecovery,
        reason: 'an unverified factor must not read as factorless',
      );
      expect(
        identity.enrollmentCalls,
        0,
        reason: 'enrolling again is exactly what collides',
      );
      expect(controller.state.workspacePhase, WorkspacePhase.idle);
      expect(identity.listCalls, 0);
      expect(properties.listCalls, 0);
    });

    test('recovery can resume the existing unverified factor', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );

      await controller.start();
      // The user still has the authenticator key: the abandoned factor is
      // finished rather than replaced, so nothing is deleted.
      await controller.resumeTotpEnrollment(code: '123456');

      expect(identity.challengedFactorIds, <String>['factor-stale']);
      expect(identity.unenrolledFactorIds, isEmpty);
      expect(controller.state.authPhase, ReferenceAuthPhase.authenticated);
      expect(
        controller.state.assuranceLevel,
        AuthenticationAssuranceLevel.aal2,
      );
      expect(controller.state.recoveryFactor, isNull);
      expect(controller.state.totpEnrollment, isNull);
      expect(identity.listCalls, 1);
    });

    test('recovery can restart, removing only the unverified factor', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);

      await controller.start();
      await controller.restartTotpEnrollment();

      expect(identity.unenrolledFactorIds, <String>['factor-stale']);
      expect(identity.enrollmentCalls, 1);
      expect(
        controller.state.authActionPhase,
        ReferenceAuthActionPhase.enrollmentReady,
      );
      expect(controller.state.totpEnrollment?.secret, 'sensitive-secret');
      // Still below the boundary until a code is verified.
      expect(identity.listCalls, 0);
    });

    test('restart never removes a verified factor', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(id: 'factor-good', friendlyName: 'Primary'),
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);

      await controller.start();

      // A verified factor exists, so the safe way to aal2 is a challenge and
      // the state is the ordinary one -- no recovery, no deletion offered.
      expect(controller.state.authActionPhase, ReferenceAuthActionPhase.idle);
      expect(controller.state.totpFactors.single.id, 'factor-good');
      expect(controller.state.recoveryFactor, isNull);

      await controller.restartTotpEnrollment();
      await controller.resumeTotpEnrollment(code: '123456');
      // The stale factor is not offered for a challenge either: it cannot
      // answer one, and routing a code at it would only confuse the user.
      await controller.verifyTotp(factorId: 'factor-stale', code: '123456');
      expect(
        identity.unenrolledFactorIds,
        isEmpty,
        reason: 'a verified factor must never reach the unenroll path',
      );
      expect(identity.enrollmentCalls, 0);
      expect(identity.challengedFactorIds, isEmpty);

      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      await controller.verifyTotp(factorId: 'factor-good', code: '123456');

      expect(identity.challengedFactorIds, <String>['factor-good']);
      expect(controller.state.authPhase, ReferenceAuthPhase.authenticated);
      expect(
        controller.state.assuranceLevel,
        AuthenticationAssuranceLevel.aal2,
      );
      expect(
        identity.unenrolledFactorIds,
        isEmpty,
        reason: 'reaching aal2 does not clean up the stale factor either',
      );
    });

    test('restart re-reads the inventory before deleting anything', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);

      await controller.start();
      final callsAfterLoad = identity.factorCalls;

      // Between the listing and the action the factor got verified elsewhere.
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(id: 'factor-stale', friendlyName: 'NexImmo'),
      ]);
      await controller.restartTotpEnrollment();

      expect(
        identity.factorCalls,
        greaterThan(callsAfterLoad),
        reason: 'the inventory must be re-read immediately before unenrolling',
      );
      expect(
        identity.unenrolledFactorIds,
        isEmpty,
        reason: 'the factor is verified now and must be left alone',
      );
      expect(identity.enrollmentCalls, 0);
      // The state is recomputed from what was actually found: a verified
      // factor, so the ordinary challenge path.
      expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
      expect(controller.state.authActionPhase, ReferenceAuthActionPhase.idle);
      expect(controller.state.totpFactors.single.id, 'factor-stale');
      expect(controller.state.recoveryFactor, isNull);
      expect(controller.state.totpEnrollment, isNull);
      expect(identity.listCalls, 0);
    });

    test('a factor that vanished mid-recovery fails closed', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);

      await controller.start();
      identity.factorsResult = _inventory(const <TotpFactor>[]);
      await controller.restartTotpEnrollment();

      expect(identity.unenrolledFactorIds, isEmpty);
      expect(
        identity.enrollmentCalls,
        0,
        reason: 'a vanished target is a reason to look again, not to act',
      );
      // Recomputed from the fresh inventory: the account is factorless now,
      // and gets the ordinary first-enrolment offer.
      expect(
        controller.state.authActionPhase,
        ReferenceAuthActionPhase.enrollmentRequired,
      );
      expect(controller.state.recoveryFactor, isNull);
      expect(controller.state.workspacePhase, WorkspacePhase.idle);
      expect(identity.listCalls, 0);
    });

    test('a name conflict resolves to recovery, not a generic error', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      // The client believed the account was factorless -- the inventory says
      // so -- but the server knows better.
      identity.factorsResult = _inventory(const <TotpFactor>[]);
      identity.enrollmentResult = const IdentityAccessFailure<TotpEnrollment>(
        kind: IdentityAccessFailureKind.factorNameConflict,
        message:
            'An unfinished authenticator setup is already on this '
            'account.',
      );

      await controller.start();
      // The inventory refresh now reveals the abandoned factor.
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);
      await controller.beginTotpEnrollment();

      expect(
        controller.state.authActionPhase,
        ReferenceAuthActionPhase.interruptedEnrollmentRecovery,
        reason: 'the conflict is recoverable, not an outage',
      );
      expect(
        controller.state.authMessage,
        isNot(contains('temporarily unavailable')),
      );
      expect(controller.state.recoveryFactor?.id, 'factor-stale');
      expect(identity.unenrolledFactorIds, isEmpty);
      expect(
        identity.enrollmentCalls,
        1,
        reason:
            'one attempt, then a look at the inventory -- no retry loop '
            'and no renamed second attempt',
      );
      expect(
        identity.factorCalls,
        2,
        reason: 'the conflict triggers a refresh',
      );
      expect(identity.listCalls, 0);
    });

    test('too many factors never triggers an automatic deletion', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[]);
      identity.enrollmentResult = const IdentityAccessFailure<TotpEnrollment>(
        kind: IdentityAccessFailureKind.tooManyFactors,
        message:
            'This account already has the maximum number of '
            'authenticators.',
      );

      await controller.start();
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(id: 'factor-good', friendlyName: 'Primary'),
      ]);
      await controller.beginTotpEnrollment();

      expect(identity.unenrolledFactorIds, isEmpty);
      expect(
        controller.state.authMessage,
        isNot(contains('temporarily unavailable')),
      );
      expect(identity.enrollmentCalls, 1);
      expect(
        identity.factorCalls,
        2,
        reason: 'the rejection triggers a refresh',
      );
      // The refreshed inventory holds a verified factor, so the safe way
      // forward is the ordinary challenge -- offered, not a deletion.
      expect(controller.state.authActionPhase, ReferenceAuthActionPhase.idle);
      expect(controller.state.totpFactors.single.id, 'factor-good');
      expect(controller.state.recoveryFactor, isNull);
      expect(identity.listCalls, 0);
    });

    test('too many factors without a safe way out fails closed', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[]);
      identity.enrollmentResult = const IdentityAccessFailure<TotpEnrollment>(
        kind: IdentityAccessFailureKind.tooManyFactors,
        message:
            'This account already has the maximum number of '
            'authenticators.',
      );

      await controller.start();
      // The refresh still shows nothing this client can act on.
      await controller.beginTotpEnrollment();

      expect(controller.state.authActionPhase, ReferenceAuthActionPhase.failed);
      expect(controller.state.authMessage, isNotNull);
      expect(
        controller.state.authMessage,
        isNot(contains('temporarily unavailable')),
      );
      expect(identity.unenrolledFactorIds, isEmpty);
      expect(identity.enrollmentCalls, 1, reason: 'no blind retry');
      expect(controller.state.recoveryFactor, isNull);
      expect(identity.listCalls, 0);
    });

    test('sign-out clears recovery state and deletes nothing remote', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);

      await controller.start();
      await controller.restartTotpEnrollment();
      expect(controller.state.totpEnrollment?.secret, 'sensitive-secret');

      await controller.signOut();

      expect(controller.state.authPhase, ReferenceAuthPhase.unauthenticated);
      expect(controller.state.totpEnrollment, isNull);
      expect(controller.state.totpFactors, isEmpty);
      expect(controller.state.recoveryFactor, isNull);
      expect(controller.state.authMessage, isNull);
      expect(
        identity.unenrolledFactorIds,
        <String>['factor-stale'],
        reason:
            'only the deliberate restart removed it; sign-out removes '
            'nothing remote',
      );
    });

    test(
      'a recreated controller recovers the remote factor, never re-enrols',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        identity.factorsResult = _inventory(const <TotpFactor>[]);

        await controller.start();
        await controller.beginTotpEnrollment();
        expect(controller.state.totpEnrollment?.secret, 'sensitive-secret');
        expect(identity.enrollmentCalls, 1);

        // The app is closed before a code is entered. The secret lived only in
        // the controller and goes with it; the factor stays on the server,
        // unverified.
        controller.dispose();
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-new',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
        ]);
        controller = ReferenceSliceController(
          identityRepository: identity,
          propertyRepository: properties,
          propertyInvalidationSource: invalidations,
          entitlementInvalidationSource: entitlementInvalidations,
          entitlementRevalidationInterval: const Duration(hours: 1),
          idFactory: () => ids.removeFirst(),
        );
        await controller.start();

        expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.interruptedEnrollmentRecovery,
        );
        expect(
          controller.state.totpEnrollment,
          isNull,
          reason: 'no secret survives a restart',
        );
        expect(controller.state.recoveryFactor?.id, 'factor-new');
        expect(
          identity.enrollmentCalls,
          1,
          reason: 'the reload must not issue a second blind enrolment',
        );
        expect(identity.unenrolledFactorIds, isEmpty);
        expect(identity.listCalls, 0);
        expect(properties.listCalls, 0);
      },
    );

    test('restart confirms the old factor is gone before enrolling', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);
      // The unenroll call returns fine, but the next listing still shows the
      // factor -- a replica lag, a retried request, whatever. Enrolling on top
      // of it is exactly the collision this package exists to avoid.
      identity.unenrollRemovesFactor = false;

      await controller.start();
      await controller.restartTotpEnrollment();

      expect(identity.unenrolledFactorIds, <String>['factor-stale']);
      expect(
        identity.factorCalls,
        3,
        reason: 'initial load, pre-unenroll check, post-unenroll confirmation',
      );
      expect(
        identity.enrollmentCalls,
        0,
        reason: 'the factor is still on the account; enrolling would collide',
      );
      expect(controller.state.authActionPhase, ReferenceAuthActionPhase.failed);
      expect(controller.state.totpEnrollment, isNull);
      expect(
        controller.state.recoveryFactor?.id,
        'factor-stale',
        reason: 'the user can try again once the account has caught up',
      );
      expect(identity.listCalls, 0);
    });

    test('restart reads the inventory three times on the happy path', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);

      await controller.start();
      await controller.restartTotpEnrollment();

      expect(
        identity.factorCalls,
        3,
        reason: 'initial load, pre-unenroll check, post-unenroll confirmation',
      );
      expect(identity.unenrolledFactorIds, <String>['factor-stale']);
      expect(identity.enrollmentCalls, 1);
      expect(controller.state.recoveryFactor, isNull);
      expect(controller.state.totpEnrollment?.factorId, 'factor-new');
    });

    test('restart and resume are refused outside recovery', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(id: 'factor-good', friendlyName: 'Primary'),
      ]);

      await controller.start();
      await controller.restartTotpEnrollment();
      await controller.resumeTotpEnrollment(code: '123456');

      expect(identity.unenrolledFactorIds, isEmpty);
      expect(identity.enrollmentCalls, 0);
      expect(
        identity.challengedFactorIds,
        isEmpty,
        reason: 'the ordinary challenge goes through verifyTotp, not resume',
      );
      expect(controller.state.authActionPhase, ReferenceAuthActionPhase.idle);
      expect(controller.state.totpFactors.single.id, 'factor-good');
      expect(identity.factorCalls, 1, reason: 'refused before any re-read');
    });

    test(
      'resume re-validates the factor and recomputes when it vanished',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-stale',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
        ]);

        await controller.start();
        identity.factorsResult = _inventory(const <TotpFactor>[]);
        await controller.resumeTotpEnrollment(code: '123456');

        expect(identity.challengedFactorIds, isEmpty);
        expect(identity.verifiedCodes, isEmpty);
        expect(identity.unenrolledFactorIds, isEmpty);
        expect(identity.enrollmentCalls, 0);
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.enrollmentRequired,
        );
        expect(controller.state.recoveryFactor, isNull);
        expect(identity.listCalls, 0);
      },
    );

    test('restart aborts when the inventory re-read fails', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);

      await controller.start();
      identity.factorsResult = const IdentityAccessFailure<TotpFactorInventory>(
        kind: IdentityAccessFailureKind.infrastructureFailure,
        message: 'Factor lookup failed.',
      );
      await controller.restartTotpEnrollment();
      await controller.resumeTotpEnrollment(code: '123456');

      expect(
        identity.unenrolledFactorIds,
        isEmpty,
        reason: 'no fresh state, no destructive action',
      );
      expect(identity.enrollmentCalls, 0);
      expect(identity.challengedFactorIds, isEmpty);
      expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
      expect(controller.state.authActionPhase, ReferenceAuthActionPhase.failed);
      expect(controller.state.workspacePhase, WorkspacePhase.idle);
      expect(identity.listCalls, 0);
      expect(properties.listCalls, 0);
    });

    test(
      'repeated retries and reloads never issue a blind enrolment',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-stale',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
        ]);

        await controller.start();
        // The plain "set up" action is not available from recovery: it is the
        // call that collides.
        await controller.beginTotpEnrollment();
        await controller.beginTotpEnrollment();
        expect(identity.enrollmentCalls, 0);

        // Reload: the session goes away and comes back, the factor is still
        // there. Recovery again, still no enrolment.
        identity.emit(null);
        await _flushEvents();
        expect(controller.state.recoveryFactor, isNull);
        identity.emit(
          const AuthenticatedSession(
            userId: 'user-a',
            currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
            nextAssuranceLevel: AuthenticationAssuranceLevel.aal1,
          ),
        );
        await _flushEvents();
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.interruptedEnrollmentRecovery,
        );
        expect(identity.enrollmentCalls, 0);

        // Two restarts racing: the second must fall to the busy guard.
        await Future.wait<void>(<Future<void>>[
          controller.restartTotpEnrollment(),
          controller.restartTotpEnrollment(),
        ]);
        expect(identity.unenrolledFactorIds, <String>['factor-stale']);
        expect(identity.enrollmentCalls, 1);
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.enrollmentReady,
        );
        expect(identity.listCalls, 0);
      },
    );

    test(
      'session loss drops the enrolment secret and recovery target',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-stale',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
        ]);

        await controller.start();
        expect(controller.state.recoveryFactor?.id, 'factor-stale');
        await controller.restartTotpEnrollment();
        expect(controller.state.totpEnrollment?.secret, 'sensitive-secret');

        identity.emit(null);
        await _flushEvents();

        expect(controller.state.authPhase, ReferenceAuthPhase.unauthenticated);
        expect(controller.state.totpEnrollment, isNull);
        expect(controller.state.recoveryFactor, isNull);
        expect(controller.state.totpFactors, isEmpty);
        expect(controller.state.authMessage, isNull);
        expect(
          identity.unenrolledFactorIds,
          <String>['factor-stale'],
          reason: 'session loss removes nothing remote',
        );
      },
    );

    test(
      'a factor of unknown status is neither challenged nor removed',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-odd',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unknown,
          ),
        ]);

        await controller.start();

        expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.failed,
        );
        expect(controller.state.totpFactors, isEmpty);
        expect(controller.state.recoveryFactor, isNull);

        await controller.restartTotpEnrollment();
        await controller.resumeTotpEnrollment(code: '123456');
        await controller.verifyTotp(factorId: 'factor-odd', code: '123456');

        expect(identity.unenrolledFactorIds, isEmpty);
        expect(identity.challengedFactorIds, isEmpty);
        expect(identity.enrollmentCalls, 0);
        expect(identity.listCalls, 0);
        expect(properties.listCalls, 0);
      },
    );

    // --- Pre-PR review additions: the re-read must be judged by the same
    // rules as the initial load, a refused removal is not an excuse to act on
    // the old picture, and a state the client could not determine is not a
    // licence to enrol.

    test(
      'an unknown factor appearing on the re-read aborts restart and resume',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-stale',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
        ]);

        await controller.start();
        expect(controller.state.recoveryFactor?.id, 'factor-stale');

        // The fresh read is ambiguous by the inventory's own definition. Had it
        // been the initial load nothing would have been offered; the action
        // must hold itself to the same standard.
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-stale',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
          TotpFactor(
            id: 'factor-odd',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unknown,
          ),
        ]);
        await controller.restartTotpEnrollment();

        expect(identity.unenrolledFactorIds, isEmpty);
        expect(identity.enrollmentCalls, 0);
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.failed,
        );
        expect(controller.state.recoveryFactor, isNull);

        // Resume from the state before the ambiguity was seen.
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-stale',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
        ]);
        identity.emit(null);
        await _flushEvents();
        identity.emit(
          const AuthenticatedSession(
            userId: 'user-a',
            currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
            nextAssuranceLevel: AuthenticationAssuranceLevel.aal1,
          ),
        );
        await _flushEvents();
        expect(controller.state.recoveryFactor?.id, 'factor-stale');
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-stale',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
          TotpFactor(
            id: 'factor-odd',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unknown,
          ),
        ]);
        await controller.resumeTotpEnrollment(code: '123456');

        expect(identity.challengedFactorIds, isEmpty);
        expect(identity.unenrolledFactorIds, isEmpty);
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.failed,
        );
        expect(identity.listCalls, 0);
      },
    );

    test(
      'a verified factor appearing on the re-read wins over the stale one',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-stale',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
        ]);

        await controller.start();
        // Meanwhile another session completed a different enrolment. The stale
        // factor is still unverified, but it is no longer the only story.
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-stale',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
          TotpFactor(id: 'factor-good', friendlyName: 'Primary'),
        ]);
        await controller.restartTotpEnrollment();

        expect(
          identity.unenrolledFactorIds,
          isEmpty,
          reason: 'a verified factor exists; nothing is cleaned up for it',
        );
        expect(identity.enrollmentCalls, 0);
        expect(controller.state.authActionPhase, ReferenceAuthActionPhase.idle);
        expect(controller.state.totpFactors.single.id, 'factor-good');
        expect(controller.state.recoveryFactor, isNull);

        // The same for resume, starting again from the recovery state.
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-stale',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
        ]);
        identity.emit(null);
        await _flushEvents();
        identity.emit(
          const AuthenticatedSession(
            userId: 'user-a',
            currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
            nextAssuranceLevel: AuthenticationAssuranceLevel.aal1,
          ),
        );
        await _flushEvents();
        expect(controller.state.recoveryFactor?.id, 'factor-stale');
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-stale',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
          TotpFactor(id: 'factor-good', friendlyName: 'Primary'),
        ]);
        await controller.resumeTotpEnrollment(code: '123456');

        expect(identity.challengedFactorIds, isEmpty);
        expect(controller.state.authActionPhase, ReferenceAuthActionPhase.idle);
        expect(controller.state.totpFactors.single.id, 'factor-good');
        expect(identity.listCalls, 0);
      },
    );

    test(
      'restart does not enrol when another factor remains after removal',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        const stale = TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        );
        // Reads 1 and 2 (initial, pre-unenroll) see the stale factor; read 3
        // (post-unenroll) finds it gone but a verified factor in its place.
        identity.factorsHandler =
            (call) async =>
                call < 3
                    ? _inventory(const <TotpFactor>[stale])
                    : _inventory(const <TotpFactor>[
                      TotpFactor(id: 'factor-good', friendlyName: 'Primary'),
                    ]);

        await controller.start();
        await controller.restartTotpEnrollment();

        expect(identity.unenrolledFactorIds, <String>['factor-stale']);
        expect(identity.factorCalls, 3);
        expect(
          identity.enrollmentCalls,
          0,
          reason: 'the account is not bare; enrolling would be blind',
        );
        expect(controller.state.authActionPhase, ReferenceAuthActionPhase.idle);
        expect(controller.state.totpFactors.single.id, 'factor-good');
        expect(controller.state.recoveryFactor, isNull);
        expect(controller.state.totpEnrollment, isNull);
      },
    );

    test('a refused removal re-reads and never enrols', () async {
      identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
      identity.factorsResult = _inventory(const <TotpFactor>[
        TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        ),
      ]);
      identity.unenrollResult = const IdentityAccessFailure<void>(
        kind: IdentityAccessFailureKind.forbidden,
        message: 'This authentication action is not permitted.',
      );

      await controller.start();
      await controller.restartTotpEnrollment();

      expect(identity.unenrolledFactorIds, <String>['factor-stale']);
      expect(
        identity.factorCalls,
        3,
        reason: 'the refusal is followed by a re-read like any other outcome',
      );
      expect(identity.enrollmentCalls, 0);
      expect(controller.state.authActionPhase, ReferenceAuthActionPhase.failed);
      expect(
        controller.state.recoveryFactor?.id,
        'factor-stale',
        reason: 'still on the account, still recoverable',
      );
      expect(controller.state.authMessage, contains('could not be removed'));
    });

    test(
      'a removal refused because the factor is already gone recomputes',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        const stale = TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        );
        // Another session of the same account removed it first: the DELETE
        // answers not-found, which the adapter files under verification codes.
        identity.unenrollResult = const IdentityAccessFailure<void>(
          kind: IdentityAccessFailureKind.verificationFailed,
          message: 'The authenticator code could not be verified.',
        );
        identity.factorsHandler =
            (call) async =>
                call < 3
                    ? _inventory(const <TotpFactor>[stale])
                    : _inventory(const <TotpFactor>[]);

        await controller.start();
        await controller.restartTotpEnrollment();

        expect(identity.unenrolledFactorIds, <String>['factor-stale']);
        expect(
          identity.enrollmentCalls,
          0,
          reason: 'a refused removal never flows straight into an enrolment',
        );
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.enrollmentRequired,
        );
        expect(controller.state.recoveryFactor, isNull);
        expect(
          controller.state.authMessage,
          isNot(contains('code could not be verified')),
          reason: 'no code was entered; the verify message would mislead',
        );
      },
    );

    test(
      'enrolment is refused from a state the client could not determine',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        identity.factorsResult = _inventory(const <TotpFactor>[
          TotpFactor(
            id: 'factor-odd',
            friendlyName: 'Other',
            status: TotpFactorStatus.unknown,
          ),
        ]);

        await controller.start();
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.failed,
        );
        await controller.beginTotpEnrollment();
        expect(identity.enrollmentCalls, 0, reason: 'ambiguous inventory');

        // The same after the inventory could not be read at all.
        identity
            .factorsResult = const IdentityAccessFailure<TotpFactorInventory>(
          kind: IdentityAccessFailureKind.infrastructureFailure,
          message: 'Factor lookup failed.',
        );
        identity.emit(null);
        await _flushEvents();
        identity.emit(
          const AuthenticatedSession(
            userId: 'user-a',
            currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
            nextAssuranceLevel: AuthenticationAssuranceLevel.aal1,
          ),
        );
        await _flushEvents();
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.failed,
        );
        await controller.beginTotpEnrollment();
        expect(identity.enrollmentCalls, 0, reason: 'unread inventory');
        expect(identity.listCalls, 0);
      },
    );

    test(
      'a session change during the pre-unenroll read aborts the restart',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        const stale = TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        );
        identity.factorsHandler = (call) async {
          if (call == 2) {
            // While the pre-unenroll read is in flight, the session watcher
            // reports the factor verified elsewhere (next level now aal2). The
            // read itself still answers with the old picture.
            identity.emit(
              const AuthenticatedSession(
                userId: 'user-a',
                currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
                nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
              ),
            );
            await _flushEvents();
            return _inventory(const <TotpFactor>[stale]);
          }
          return _inventory(
            call == 1
                ? const <TotpFactor>[stale]
                : const <TotpFactor>[
                  TotpFactor(id: 'factor-stale', friendlyName: 'NexImmo'),
                ],
          );
        };

        await controller.start();
        await controller.restartTotpEnrollment();
        await _flushEvents();

        expect(
          identity.unenrolledFactorIds,
          isEmpty,
          reason: 'the session moved on; the stale read must not be acted upon',
        );
        expect(identity.enrollmentCalls, 0);
        expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
        expect(controller.state.authActionPhase, ReferenceAuthActionPhase.idle);
        expect(controller.state.totpFactors.single.id, 'factor-stale');
        expect(controller.state.recoveryFactor, isNull);
        expect(identity.listCalls, 0);
      },
    );

    test(
      'a same-session refresh during the pre-unenroll read is harmless',
      () async {
        identity.authenticate(level: AuthenticationAssuranceLevel.aal1);
        const stale = TotpFactor(
          id: 'factor-stale',
          friendlyName: 'NexImmo',
          status: TotpFactorStatus.unverified,
        );
        identity.factorsHandler = (call) async {
          if (call == 2) {
            // A token refresh re-emits the unchanged session.
            identity.emit(identity.currentSession);
            await _flushEvents();
          }
          return _inventory(
            identity.unenrolledFactorIds.isEmpty
                ? const <TotpFactor>[stale]
                : const <TotpFactor>[],
          );
        };

        await controller.start();
        await controller.restartTotpEnrollment();

        expect(identity.unenrolledFactorIds, <String>['factor-stale']);
        expect(identity.enrollmentCalls, 1);
        expect(
          controller.state.authActionPhase,
          ReferenceAuthActionPhase.enrollmentReady,
        );
        expect(identity.listCalls, 0);
      },
    );

    test('loads the only active workspace and explicit empty list', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );

      await controller.start();

      expect(controller.state.authPhase, ReferenceAuthPhase.authenticated);
      expect(controller.state.workspacePhase, WorkspacePhase.selected);
      expect(controller.state.selectedWorkspaceId, 'workspace-a');
      expect(controller.state.propertyListPhase, PropertyListPhase.empty);
      expect(properties.listWorkspaceIds, <String>['workspace-a']);
    });

    test(
      'requires selection with multiple workspaces and rejects foreign id',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read'}),
            _access(
              workspaceId: 'workspace-b',
              permissions: <String>{'property.read'},
            ),
          ],
        );

        await controller.start();
        expect(
          controller.state.workspacePhase,
          WorkspacePhase.selectionRequired,
        );
        expect(properties.listCalls, 0);

        await controller.selectWorkspace('foreign-workspace');
        expect(controller.state.propertyListPhase, PropertyListPhase.forbidden);
        expect(controller.state.selectedWorkspaceId, isNull);
        expect(properties.listCalls, 0);

        await controller.selectWorkspace('workspace-b');
        expect(controller.state.selectedWorkspaceId, 'workspace-b');
        expect(properties.listWorkspaceIds, <String>['workspace-b']);
      },
    );

    test(
      'derives forbidden list state before calling the repository',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[_access(permissions: <String>{})],
        );

        await controller.start();

        expect(controller.state.propertyListPhase, PropertyListPhase.forbidden);
        expect(
          controller.state.failureKind,
          PropertyRepositoryFailureKind.forbidden,
        );
        expect(properties.listCalls, 0);
      },
    );

    test('loads stable-id detail and applies a successful update', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read', 'property.update'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );
      properties.updateResults.add(
        PropertyRepositorySuccess<PropertyDto>(
          _property(version: 2, name: 'After'),
        ),
      );

      await controller.start();
      await controller.openProperty('property-a');
      await controller.updateSelectedProperty(_changes(name: 'After'));

      expect(properties.detailPropertyIds, <String>['property-a']);
      expect(controller.state.propertyDetailPhase, PropertyDetailPhase.ready);
      expect(controller.state.mutationPhase, PropertyMutationPhase.succeeded);
      expect(controller.state.selectedProperty?.version, 2);
      expect(properties.updateCommands.single.context.actorId, 'user-a');
      expect(
        properties.updateCommands.single.context.workspaceId,
        'workspace-a',
      );
      expect(properties.updateCommands.single.context.expectedVersion, 1);
    });

    test('detail does not downgrade a newer list summary', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property(version: 3)]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(version: 2, name: 'Stale detail'),
      );

      await controller.start();
      await controller.openProperty('property-a');

      expect(controller.state.selectedProperty?.version, 2);
      expect(controller.state.properties.single.version, 3);
    });

    test('deep-link detail does not extend the loaded keyset page', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(id: 'property-b'),
      );

      await controller.start();
      await controller.openProperty('property-b');

      expect(controller.state.selectedProperty?.id, 'property-b');
      expect(
        controller.state.properties.map((property) => property.id),
        <String>['property-a'],
      );
    });

    test(
      'archived mutation removes the property from the active list',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read', 'property.update'}),
          ],
        );
        properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
          PropertyPageResult(items: <PropertyDto>[_property()]),
        );
        properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
          _property(),
        );
        properties.updateResults.add(
          PropertyRepositorySuccess<PropertyDto>(
            _property(version: 2, status: PropertyStatus.archived),
          ),
        );

        await controller.start();
        await controller.openProperty('property-a');
        await controller.updateSelectedProperty(_changes());

        expect(controller.state.propertyListPhase, PropertyListPhase.empty);
        expect(controller.state.properties, isEmpty);
        expect(
          controller.state.selectedProperty?.status,
          PropertyStatus.archived,
        );
      },
    );

    test('archived mutation preserves a remaining keyset cursor', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read', 'property.update'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(
          items: <PropertyDto>[_property()],
          nextCursor: 'property-b',
        ),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );
      properties.updateResults.add(
        PropertyRepositorySuccess<PropertyDto>(
          _property(version: 2, status: PropertyStatus.archived),
        ),
      );

      await controller.start();
      await controller.openProperty('property-a');
      await controller.updateSelectedProperty(_changes());

      expect(controller.state.propertyListPhase, PropertyListPhase.ready);
      expect(controller.state.properties, isEmpty);
      expect(controller.state.nextCursor, 'property-b');
    });

    // === PROPERTY-WORKSPACE-01 A1 ==========================================
    //
    // The workspace host reuses this controller as the property list/detail
    // engine and adds the one contract-backed list filter, a graceful
    // load-more failure and an explicit way out of the property context.

    test('passes includeArchived to every list query and resets it on '
        'workspace switch', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(
          items: <PropertyDto>[_property()],
          nextCursor: 'property-a',
        ),
      );

      await controller.start();
      expect(controller.state.includeArchived, isFalse);
      expect(properties.listQueries.single.includeArchived, isFalse);

      await controller.setIncludeArchived(true);
      expect(controller.state.includeArchived, isTrue);
      expect(properties.listQueries.last.includeArchived, isTrue);
      expect(
        properties.listQueries.last.page.cursor,
        isNull,
        reason: 'a filter change restarts the keyset',
      );

      await controller.loadNextPropertyPage();
      expect(properties.listQueries.last.includeArchived, isTrue);
      expect(properties.listQueries.last.page.cursor, 'property-a');

      invalidations.emit(
        const PropertyQueryInvalidation.reconcile(workspaceId: 'workspace-a'),
      );
      await _flushEvents();
      await _flushEvents();
      expect(
        properties.listQueries.last.includeArchived,
        isTrue,
        reason: 'a realtime reconcile re-reads the visible query',
      );

      // Same value is a no-op: no extra read.
      final calls = properties.listCalls;
      await controller.setIncludeArchived(true);
      expect(properties.listCalls, calls);

      await controller.selectWorkspace('workspace-a');
      expect(controller.state.includeArchived, isFalse);
      expect(properties.listQueries.last.includeArchived, isFalse);
    });

    test('a failed additional page keeps the loaded pages visible', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      var call = 0;
      properties.listHandler = (query) async {
        call++;
        return switch (call) {
          1 => PropertyRepositorySuccess<PropertyPageResult>(
            PropertyPageResult(
              items: <PropertyDto>[
                _property(id: 'property-a'),
                _property(id: 'property-b'),
              ],
              nextCursor: 'property-b',
            ),
          ),
          2 => const PropertyRepositoryFailure<PropertyPageResult>(
            kind: PropertyRepositoryFailureKind.infrastructureFailure,
            message: 'Temporary failure.',
          ),
          _ => PropertyRepositorySuccess<PropertyPageResult>(
            PropertyPageResult(
              items: <PropertyDto>[_property(id: 'property-c')],
            ),
          ),
        };
      };

      await controller.start();
      await controller.loadNextPropertyPage();

      expect(controller.state.propertyListPhase, PropertyListPhase.ready);
      expect(controller.state.properties, hasLength(2));
      expect(controller.state.nextCursor, 'property-b');
      expect(controller.state.loadMoreFailureMessage, 'Temporary failure.');
      expect(controller.state.failureKind, isNull);

      await controller.loadNextPropertyPage();
      expect(controller.state.loadMoreFailureMessage, isNull);
      expect(
        controller.state.properties.map((property) => property.id),
        <String>['property-a', 'property-b', 'property-c'],
      );
      expect(controller.state.nextCursor, isNull);
    });

    test('a forbidden additional page clears the list fail closed', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      var call = 0;
      properties.listHandler = (query) async {
        call++;
        return call == 1
            ? PropertyRepositorySuccess<PropertyPageResult>(
              PropertyPageResult(
                items: <PropertyDto>[_property()],
                nextCursor: 'property-a',
              ),
            )
            : const PropertyRepositoryFailure<PropertyPageResult>(
              kind: PropertyRepositoryFailureKind.forbidden,
              message: 'Revoked.',
            );
      };

      await controller.start();
      await controller.loadNextPropertyPage();

      expect(controller.state.propertyListPhase, PropertyListPhase.forbidden);
      expect(controller.state.properties, isEmpty);
      expect(controller.state.loadMoreFailureMessage, isNull);
    });

    test(
      'closeSelectedProperty leaves the context but keeps the list scope',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read', 'property.update'}),
          ],
        );
        properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
          PropertyPageResult(
            items: <PropertyDto>[_property()],
            nextCursor: 'property-a',
          ),
        );
        properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
          _property(),
        );
        properties.updateResults.add(
          PropertyRepositoryFailure<PropertyDto>(
            kind: PropertyRepositoryFailureKind.versionConflict,
            message: 'Stale version.',
            versionConflict: PropertyVersionConflict(
              expectedVersion: 1,
              actualVersion: 2,
              currentProperty: _property(version: 2),
            ),
          ),
        );

        await controller.start();
        await controller.setIncludeArchived(true);
        await controller.openProperty('property-a');
        await controller.updateSelectedProperty(_changes());
        expect(controller.state.mutationPhase, PropertyMutationPhase.conflict);

        controller.closeSelectedProperty();

        expect(controller.state.propertyDetailPhase, PropertyDetailPhase.idle);
        expect(controller.state.selectedProperty, isNull);
        expect(controller.state.mutationPhase, PropertyMutationPhase.idle);
        expect(controller.state.versionConflict, isNull);
        expect(controller.state.failureKind, isNull);
        // The list the property was opened from is untouched.
        expect(controller.state.propertyListPhase, PropertyListPhase.ready);
        expect(controller.state.properties, hasLength(1));
        expect(controller.state.nextCursor, 'property-a');
        expect(controller.state.includeArchived, isTrue);
        expect(properties.listCalls, 2, reason: 'closing reads nothing');
      },
    );

    test('the archive view keeps an archived property in the list', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read', 'property.update'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );
      properties.updateResults.add(
        PropertyRepositorySuccess<PropertyDto>(
          _property(version: 2, status: PropertyStatus.archived),
        ),
      );

      await controller.start();
      await controller.setIncludeArchived(true);
      await controller.openProperty('property-a');
      await controller.updateSelectedProperty(_changes());

      expect(controller.state.propertyListPhase, PropertyListPhase.ready);
      expect(
        controller.state.properties.single.status,
        PropertyStatus.archived,
      );
      expect(controller.state.properties.single.version, 2);
    });

    test('retries a transient failure with the identical command', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read', 'property.update'}),
        ],
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );
      properties.updateResults
        ..add(
          const PropertyRepositoryFailure<PropertyDto>(
            kind: PropertyRepositoryFailureKind.infrastructureFailure,
            message: 'Temporary failure.',
          ),
        )
        ..add(PropertyRepositorySuccess<PropertyDto>(_property(version: 2)));

      await controller.start();
      await controller.openProperty('property-a');
      await controller.updateSelectedProperty(_changes());
      expect(controller.state.mutationPhase, PropertyMutationPhase.failed);

      await controller.retryUpdate();

      expect(properties.updateCommands, hasLength(2));
      expect(
        identical(properties.updateCommands[0], properties.updateCommands[1]),
        isTrue,
      );
      expect(properties.updateCommands[1].context.mutationId, 'mutation-a');
      expect(controller.state.mutationPhase, PropertyMutationPhase.succeeded);
    });

    test(
      'surfaces version conflict and replaces stale detail safely',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read', 'property.update'}),
          ],
        );
        properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
          _property(),
        );
        final current = _property(version: 4, name: 'Server value');
        properties.updateResults.add(
          PropertyRepositoryFailure<PropertyDto>(
            kind: PropertyRepositoryFailureKind.versionConflict,
            message: 'Stale version.',
            versionConflict: PropertyVersionConflict(
              expectedVersion: 1,
              actualVersion: 4,
              currentProperty: current,
            ),
          ),
        );

        await controller.start();
        await controller.openProperty('property-a');
        await controller.updateSelectedProperty(_changes());

        expect(controller.state.mutationPhase, PropertyMutationPhase.conflict);
        expect(controller.state.versionConflict?.actualVersion, 4);
        expect(controller.state.selectedProperty?.name, 'Server value');
        await controller.retryUpdate();
        expect(properties.updateCommands, hasLength(1));
      },
    );

    test('session loss invalidates a late property response', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      final pendingList =
          Completer<PropertyRepositoryResult<PropertyPageResult>>();
      properties.listHandler = (_) => pendingList.future;

      final start = controller.start();
      await _flushEvents();
      identity.emit(null);
      await _flushEvents();
      pendingList.complete(
        PropertyRepositorySuccess<PropertyPageResult>(
          PropertyPageResult(items: <PropertyDto>[_property()]),
        ),
      );
      await start;
      await _flushEvents();

      expect(controller.state.authPhase, ReferenceAuthPhase.unauthenticated);
      expect(controller.state.properties, isEmpty);
      expect(controller.state.selectedWorkspaceId, isNull);
    });

    test('Realtime refreshes the active list and matching detail', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );

      await controller.start();
      await controller.openProperty('property-a');
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property(version: 2)]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(version: 2, name: 'Realtime'),
      );

      invalidations.emit(
        const PropertyQueryInvalidation(
          workspaceId: 'workspace-a',
          propertyId: 'property-a',
        ),
      );
      await _flushEvents();
      await _flushEvents();

      expect(invalidations.workspaceIds, <String>['workspace-a']);
      expect(properties.listCalls, 2);
      expect(properties.detailPropertyIds, <String>[
        'property-a',
        'property-a',
      ]);
      expect(controller.state.selectedProperty?.name, 'Realtime');
      expect(controller.state.selectedProperty?.version, 2);
    });

    // === REALTIME-STAGING-FIX-01 ==========================================
    //
    // Measured on staging: a mobile client's socket dropped and reconnected
    // seven times in four minutes. Realtime replays nothing across a gap, so
    // the rejoin's reconciliation is the only thing that can recover a change
    // the client was disconnected for. If it never arrives, the list stays
    // stale until the user reloads by hand -- which is exactly what was
    // observed.

    test('a reconnect reconciliation reloads the list exactly once', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );

      await controller.start();
      expect(properties.listCalls, 1, reason: 'initial load');

      // The change the client missed while its socket was down.
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(
          items: <PropertyDto>[
            _property(version: 2, name: 'Changed While Offline'),
          ],
        ),
      );
      invalidations.emit(
        const PropertyQueryInvalidation.reconcile(workspaceId: 'workspace-a'),
      );
      await _flushEvents();
      await _flushEvents();

      expect(
        properties.listCalls,
        2,
        reason: 'the rejoin catches up exactly once, no burst',
      );
      expect(controller.state.properties.single.name, 'Changed While Offline');
      expect(controller.state.propertyListPhase, PropertyListPhase.ready);
    });

    test('a subscription failure is visible, not silently swallowed', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );

      await controller.start();
      expect(controller.state.liveUpdatesDegraded, isFalse);

      invalidations.emitError(
        'workspace-a',
        StateError('Property Realtime subscription failed.'),
      );
      await _flushEvents();

      expect(
        controller.state.liveUpdatesDegraded,
        isTrue,
        reason: 'a dead subscription must not look like a quiet workspace',
      );
      // Non-fatal: REST stays canonical and the authorized surfaces stand.
      expect(controller.state.authPhase, ReferenceAuthPhase.authenticated);
      expect(controller.state.propertyListPhase, PropertyListPhase.ready);
      expect(controller.state.properties, hasLength(1));
      expect(controller.state.workspacePhase, WorkspacePhase.selected);

      // A later successful (re)subscription clears the flag again.
      invalidations.emit(
        const PropertyQueryInvalidation.reconcile(workspaceId: 'workspace-a'),
      );
      await _flushEvents();
      await _flushEvents();
      expect(controller.state.liveUpdatesDegraded, isFalse);
    });

    test('Realtime refresh preserves already loaded property pages', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      var call = 0;
      properties.listHandler = (query) async {
        call++;
        return switch (call) {
          1 => PropertyRepositorySuccess<PropertyPageResult>(
            PropertyPageResult(
              items: <PropertyDto>[
                _property(id: 'property-a'),
                _property(id: 'property-b'),
              ],
              nextCursor: 'property-b',
            ),
          ),
          2 => PropertyRepositorySuccess<PropertyPageResult>(
            PropertyPageResult(
              items: <PropertyDto>[_property(id: 'property-c')],
            ),
          ),
          _ => PropertyRepositorySuccess<PropertyPageResult>(
            PropertyPageResult(
              items: <PropertyDto>[
                _property(id: 'property-a', version: 2),
                _property(id: 'property-b'),
              ],
              nextCursor: 'property-b',
            ),
          ),
        };
      };

      await controller.start();
      await controller.loadNextPropertyPage();
      invalidations.emit(
        const PropertyQueryInvalidation(
          workspaceId: 'workspace-a',
          propertyId: 'property-a',
        ),
      );
      await _flushEvents();
      await _flushEvents();

      expect(
        controller.state.properties.map((property) => property.id),
        <String>['property-a', 'property-b', 'property-c'],
      );
      expect(controller.state.properties.first.version, 2);
      expect(controller.state.nextCursor, isNull);
    });

    test('Realtime burst is coalesced to one pending refresh', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      await controller.start();

      final firstRefresh =
          Completer<PropertyRepositoryResult<PropertyPageResult>>();
      var refreshCalls = 0;
      properties.listHandler = (_) {
        refreshCalls++;
        if (refreshCalls == 1) {
          return firstRefresh.future;
        }
        return Future<PropertyRepositoryResult<PropertyPageResult>>.value(
          PropertyRepositorySuccess<PropertyPageResult>(
            PropertyPageResult(items: <PropertyDto>[_property(version: 2)]),
          ),
        );
      };

      for (var index = 0; index < 20; index++) {
        invalidations.emit(
          const PropertyQueryInvalidation(
            workspaceId: 'workspace-a',
            propertyId: 'property-a',
          ),
        );
      }
      await _flushEvents();
      expect(refreshCalls, 1);

      firstRefresh.complete(
        PropertyRepositorySuccess<PropertyPageResult>(
          PropertyPageResult(items: <PropertyDto>[_property(version: 2)]),
        ),
      );
      await _flushEvents();
      await _flushEvents();

      expect(refreshCalls, 2);
      expect(properties.listCalls, 3);
      expect(controller.state.properties.single.version, 2);
    });

    test('Realtime forbidden response clears cached property data', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );

      await controller.start();
      await controller.openProperty('property-a');
      properties
          .listResult = const PropertyRepositoryFailure<PropertyPageResult>(
        kind: PropertyRepositoryFailureKind.forbidden,
        message: 'Access revoked.',
      );
      invalidations.emit(
        const PropertyQueryInvalidation(
          workspaceId: 'workspace-a',
          propertyId: 'property-a',
        ),
      );
      await _flushEvents();
      await _flushEvents();

      expect(controller.state.propertyListPhase, PropertyListPhase.forbidden);
      expect(
        controller.state.propertyDetailPhase,
        PropertyDetailPhase.forbidden,
      );
      expect(controller.state.properties, isEmpty);
      expect(controller.state.selectedProperty, isNull);
    });

    test(
      'entitlement signal clears caches before membership revalidation completes',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read'}),
          ],
        );
        properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
          PropertyPageResult(items: <PropertyDto>[_property()]),
        );

        await controller.start();
        expect(controller.state.properties, hasLength(1));

        final pending =
            Completer<IdentityAccessResult<List<WorkspaceAccess>>>();
        identity.listHandler = (_) => pending.future;
        entitlementInvalidations.emit(
          const EntitlementInvalidation(
            userId: 'user-a',
            workspaceId: 'workspace-a',
          ),
        );
        await _flushEvents();
        await _flushEvents();

        expect(controller.state.workspacePhase, WorkspacePhase.loading);
        expect(controller.state.workspaces, isEmpty);
        expect(controller.state.selectedWorkspaceId, isNull);
        expect(controller.state.properties, isEmpty);
        expect(controller.state.selectedProperty, isNull);
        expect(invalidations.cancelCalls['workspace-a'], 1);

        pending.complete(
          const IdentityAccessSuccess<List<WorkspaceAccess>>(
            <WorkspaceAccess>[],
          ),
        );
        await _flushEvents();
        await _flushEvents();

        expect(controller.state.workspacePhase, WorkspacePhase.empty);
        expect(controller.state.properties, isEmpty);
      },
    );

    test(
      'periodic reconcile keeps workspace and property state in place',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read', 'property.update'}),
          ],
        );
        properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
          PropertyPageResult(items: <PropertyDto>[_property()]),
        );
        properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
          _property(),
        );

        await controller.start();
        await controller.openProperty('property-a');
        expect(controller.state.selectedProperty, isNotNull);

        final pending =
            Completer<IdentityAccessResult<List<WorkspaceAccess>>>();
        identity.listHandler = (_) => pending.future;
        entitlementInvalidations.emit(
          const EntitlementInvalidation.reconcile(userId: 'user-a'),
        );
        await _flushEvents();
        await _flushEvents();

        // While the quiet check is in flight nothing is torn down, so the
        // widget tree above this state — and any unsaved form input in it —
        // stays mounted.
        expect(controller.state.workspacePhase, WorkspacePhase.selected);
        expect(controller.state.selectedWorkspaceId, 'workspace-a');
        expect(controller.state.properties, hasLength(1));
        expect(controller.state.selectedProperty, isNotNull);
        expect(invalidations.cancelCalls['workspace-a'], isNull);

        pending.complete(
          IdentityAccessSuccess<List<WorkspaceAccess>>(<WorkspaceAccess>[
            _access(permissions: <String>{'property.read', 'property.update'}),
          ]),
        );
        await _flushEvents();
        await _flushEvents();

        expect(controller.state.workspacePhase, WorkspacePhase.selected);
        expect(controller.state.selectedWorkspaceId, 'workspace-a');
        expect(controller.state.properties, hasLength(1));
        expect(controller.state.selectedProperty, isNotNull);
        expect(controller.state.propertyDetailPhase, PropertyDetailPhase.ready);
        expect(invalidations.cancelCalls['workspace-a'], isNull);
      },
    );

    test('repeated reconciles stay non-destructive', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );

      await controller.start();
      await controller.openProperty('property-a');

      for (var round = 0; round < 3; round++) {
        entitlementInvalidations.emit(
          const EntitlementInvalidation.reconcile(userId: 'user-a'),
        );
        await _flushEvents();
        await _flushEvents();

        expect(controller.state.workspacePhase, WorkspacePhase.selected);
        expect(controller.state.properties, hasLength(1));
        expect(controller.state.selectedProperty, isNotNull);
        expect(invalidations.cancelCalls['workspace-a'], isNull);
      }
    });

    test('reconcile applies refreshed permissions in place', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read', 'property.update'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );

      await controller.start();
      await controller.openProperty('property-a');
      expect(
        controller.state.selectedWorkspace!.allows('property.update'),
        isTrue,
      );

      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      entitlementInvalidations.emit(
        const EntitlementInvalidation.reconcile(userId: 'user-a'),
      );
      await _flushEvents();
      await _flushEvents();

      // The revoked capability takes effect while list and detail stay.
      expect(
        controller.state.selectedWorkspace!.allows('property.update'),
        isFalse,
      );
      expect(controller.state.workspacePhase, WorkspacePhase.selected);
      expect(controller.state.properties, hasLength(1));
      expect(controller.state.selectedProperty, isNotNull);
    });

    test('reconcile revokes read access fail closed', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );

      await controller.start();
      await controller.openProperty('property-a');

      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'workspace.read'}),
        ],
      );
      entitlementInvalidations.emit(
        const EntitlementInvalidation.reconcile(userId: 'user-a'),
      );
      await _flushEvents();
      await _flushEvents();

      expect(controller.state.propertyListPhase, PropertyListPhase.forbidden);
      expect(
        controller.state.propertyDetailPhase,
        PropertyDetailPhase.forbidden,
      );
      expect(controller.state.properties, isEmpty);
      expect(controller.state.selectedProperty, isNull);
      expect(invalidations.cancelCalls['workspace-a'], 1);
    });

    test(
      'reconcile that loses the workspace falls back to the reload',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read'}),
          ],
        );
        properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
          PropertyPageResult(items: <PropertyDto>[_property()]),
        );
        properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
          _property(),
        );

        await controller.start();
        await controller.openProperty('property-a');

        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(
              workspaceId: 'workspace-b',
              permissions: <String>{'property.read'},
            ),
          ],
        );
        entitlementInvalidations.emit(
          const EntitlementInvalidation.reconcile(userId: 'user-a'),
        );
        await _flushEvents();
        await _flushEvents();

        // The stale selection is gone; the standard reload took over and
        // auto-selected the only remaining workspace.
        expect(controller.state.selectedWorkspaceId, 'workspace-b');
        expect(controller.state.selectedProperty, isNull);
        expect(invalidations.cancelCalls['workspace-a'], 1);
      },
    );

    test(
      'reconcile infrastructure failure keeps the last authorized state',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read'}),
          ],
        );
        properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
          PropertyPageResult(items: <PropertyDto>[_property()]),
        );
        properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
          _property(),
        );

        await controller.start();
        await controller.openProperty('property-a');

        identity.result = const IdentityAccessFailure<List<WorkspaceAccess>>(
          kind: IdentityAccessFailureKind.infrastructureFailure,
          message: 'Network unavailable.',
        );
        entitlementInvalidations.emit(
          const EntitlementInvalidation.reconcile(userId: 'user-a'),
        );
        await _flushEvents();
        await _flushEvents();

        // A transient failure of the quiet check must not destroy the shell;
        // the next interval retries and server-side guards stay
        // authoritative.
        expect(controller.state.workspacePhase, WorkspacePhase.selected);
        expect(controller.state.properties, hasLength(1));
        expect(controller.state.selectedProperty, isNotNull);
      },
    );

    test('update uses the version the form was seeded from', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read', 'property.update'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property(version: 3)]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(version: 3),
      );
      final current = _property(version: 3);
      properties.updateResults.add(
        PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.versionConflict,
          message: 'Version is stale.',
          versionConflict: PropertyVersionConflict(
            expectedVersion: 1,
            actualVersion: 3,
            currentProperty: current,
          ),
        ),
      );

      await controller.start();
      await controller.openProperty('property-a');
      expect(controller.state.selectedProperty?.version, 3);

      // The form seeded its fields at version 1; a remote actor has since
      // moved the property to version 3. The explicit base version must win
      // over the refreshed canonical version, so the server can surface the
      // conflict instead of silently losing the remote change.
      await controller.updateSelectedProperty(_changes(), expectedVersion: 1);

      expect(properties.updateCommands, hasLength(1));
      expect(properties.updateCommands.single.context.expectedVersion, 1);
      expect(controller.state.mutationPhase, PropertyMutationPhase.conflict);
    });

    test('workspace switch cancels the old Realtime scope', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
          _access(
            workspaceId: 'workspace-b',
            permissions: <String>{'property.read'},
          ),
        ],
      );

      await controller.start();
      await controller.selectWorkspace('workspace-a');
      await controller.selectWorkspace('workspace-b');
      final callsBeforeLateEvent = properties.listCalls;

      invalidations.emit(
        const PropertyQueryInvalidation(
          workspaceId: 'workspace-a',
          propertyId: 'property-a',
        ),
      );
      await _flushEvents();

      expect(invalidations.workspaceIds, <String>[
        'workspace-a',
        'workspace-b',
      ]);
      expect(invalidations.cancelCalls['workspace-a'], 1);
      expect(properties.listCalls, callsBeforeLateEvent);
      expect(controller.state.selectedWorkspaceId, 'workspace-b');
    });

    test(
      'session downgrade cancels Realtime and ignores late events',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read'}),
          ],
        );

        await controller.start();
        identity.emit(
          const AuthenticatedSession(
            userId: 'user-a',
            currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
            nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
          ),
        );
        await _flushEvents();
        final callsAfterDowngrade = properties.listCalls;

        invalidations.emit(
          const PropertyQueryInvalidation(
            workspaceId: 'workspace-a',
            propertyId: 'property-a',
          ),
        );
        await _flushEvents();

        expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
        expect(invalidations.cancelCalls['workspace-a'], 1);
        expect(properties.listCalls, callsAfterDowngrade);
      },
    );
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

/// A successful factor inventory. Factors default to verified, so a test only
/// states a status when the unverified case is what it is about.
IdentityAccessResult<TotpFactorInventory> _inventory(
  List<TotpFactor> factors,
) => IdentityAccessSuccess<TotpFactorInventory>(
  TotpFactorInventory(factors: factors),
);

WorkspaceAccess _access({
  String workspaceId = 'workspace-a',
  required Set<String> permissions,
}) {
  return WorkspaceAccess(
    workspace: WorkspaceSummary(
      id: workspaceId,
      key: workspaceId,
      name: workspaceId,
      version: 1,
    ),
    membership: MembershipSummary(
      id: 'membership-$workspaceId',
      workspaceId: workspaceId,
      userId: 'user-a',
      roleId: 'role-$workspaceId',
      version: 1,
    ),
    permissions: permissions,
  );
}

PropertyDto _property({
  String id = 'property-a',
  int version = 1,
  String name = 'Property',
  PropertyStatus status = PropertyStatus.active,
}) {
  return PropertyDto(
    id: id,
    workspaceId: 'workspace-a',
    name: name,
    addressLine1: 'Street 1',
    zip: '10115',
    city: 'Berlin',
    country: 'de',
    propertyType: 'office',
    units: 1,
    status: status,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
    createdBy: 'user-a',
    updatedBy: 'user-a',
    version: version,
  );
}

PropertyUpdateDto _changes({String name = 'Updated'}) {
  return PropertyUpdateDto(
    name: name,
    addressLine1: 'Street 2',
    zip: '10117',
    city: 'Berlin',
    country: 'de',
    propertyType: 'office',
    units: 2,
    status: PropertyStatus.active,
  );
}

class _FakeIdentityRepository implements IdentityAccessRepository {
  final StreamController<AuthenticatedSession?> _sessions =
      StreamController<AuthenticatedSession?>.broadcast();

  @override
  AuthenticatedSession? currentSession;

  IdentityAccessResult<List<WorkspaceAccess>> result =
      const IdentityAccessSuccess<List<WorkspaceAccess>>(<WorkspaceAccess>[]);
  IdentityAccessResult<void> passwordlessResult =
      const IdentityAccessSuccess<void>(null);
  IdentityAccessResult<TotpEnrollment> enrollmentResult =
      const IdentityAccessSuccess<TotpEnrollment>(
        TotpEnrollment(
          factorId: 'factor-new',
          secret: 'sensitive-secret',
          uri: 'otpauth://sensitive',
        ),
      );
  IdentityAccessResult<TotpFactorInventory> factorsResult =
      const IdentityAccessSuccess<TotpFactorInventory>(
        TotpFactorInventory.empty(),
      );
  IdentityAccessResult<void> unenrollResult = const IdentityAccessSuccess<void>(
    null,
  );
  final List<String> unenrolledFactorIds = <String>[];

  /// Whether a successful unenroll also drops the factor from the next
  /// inventory read, as the real server does. Off to simulate an account that
  /// still lists the factor afterwards.
  bool unenrollRemovesFactor = true;
  IdentityAccessResult<TotpChallenge> challengeResult =
      IdentityAccessSuccess<TotpChallenge>(
        TotpChallenge(
          factorId: 'factor-a',
          challengeId: 'challenge-a',
          expiresAt: DateTime.utc(2026, 7, 18, 12),
        ),
      );
  IdentityAccessResult<AuthenticatedSession> verifyResult =
      const IdentityAccessSuccess<AuthenticatedSession>(
        AuthenticatedSession(
          userId: 'user-a',
          currentAssuranceLevel: AuthenticationAssuranceLevel.aal2,
          nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
        ),
      );
  IdentityAccessResult<void> signOutResult = const IdentityAccessSuccess<void>(
    null,
  );
  int listCalls = 0;
  final List<String> passwordlessEmails = <String>[];
  final List<({String email, String password})> passwordSignIns =
      <({String email, String password})>[];
  IdentityAccessResult<void> passwordResult = const IdentityAccessSuccess<void>(
    null,
  );
  int enrollmentCalls = 0;
  int factorCalls = 0;
  final List<String> challengedFactorIds = <String>[];
  final List<String> verifiedCodes = <String>[];
  int signOutCalls = 0;
  Future<IdentityAccessResult<List<WorkspaceAccess>>> Function(String userId)?
  listHandler;

  @override
  Stream<AuthenticatedSession?> watchSession() => _sessions.stream;

  @override
  Future<IdentityAccessResult<void>> signInWithPassword({
    required String email,
    required String password,
  }) async {
    passwordSignIns.add((email: email, password: password));
    return passwordResult;
  }

  @override
  Future<IdentityAccessResult<void>> requestPasswordlessSignIn({
    required String email,
  }) async {
    passwordlessEmails.add(email);
    return passwordlessResult;
  }

  @override
  Future<IdentityAccessResult<TotpEnrollment>> enrollTotp() async {
    enrollmentCalls++;
    return enrollmentResult;
  }

  /// Optional per-call override of [factorsResult]; receives the 1-based
  /// number of this inventory read so a test can script what each read sees.
  Future<IdentityAccessResult<TotpFactorInventory>> Function(int call)?
  factorsHandler;

  @override
  Future<IdentityAccessResult<TotpFactorInventory>>
  listTotpFactorInventory() async {
    factorCalls++;
    final handler = factorsHandler;
    return handler == null ? factorsResult : handler(factorCalls);
  }

  @override
  Future<IdentityAccessResult<void>> unenrollTotpFactor({
    required String factorId,
  }) async {
    unenrolledFactorIds.add(factorId);
    final inventory = factorsResult;
    if (unenrollRemovesFactor &&
        unenrollResult is IdentityAccessSuccess<void> &&
        inventory is IdentityAccessSuccess<TotpFactorInventory>) {
      factorsResult = _inventory(
        inventory.value.factors
            .where((factor) => factor.id != factorId)
            .toList(growable: false),
      );
    }
    return unenrollResult;
  }

  @override
  Future<IdentityAccessResult<TotpChallenge>> challengeTotp({
    required String factorId,
  }) async {
    challengedFactorIds.add(factorId);
    if (challengeResult case IdentityAccessSuccess<TotpChallenge>(
      value: final challenge,
    )) {
      return IdentityAccessSuccess<TotpChallenge>(
        TotpChallenge(
          factorId: factorId,
          challengeId: challenge.challengeId,
          expiresAt: challenge.expiresAt,
        ),
      );
    }
    return challengeResult;
  }

  @override
  Future<IdentityAccessResult<AuthenticatedSession>> verifyTotp({
    required TotpChallenge challenge,
    required String code,
  }) async {
    verifiedCodes.add(code);
    if (verifyResult case IdentityAccessSuccess<AuthenticatedSession>(
      value: final session,
    )) {
      currentSession = session;
    }
    return verifyResult;
  }

  @override
  Future<IdentityAccessResult<void>> signOut() async {
    signOutCalls++;
    if (signOutResult is IdentityAccessSuccess<void>) {
      currentSession = null;
    }
    return signOutResult;
  }

  @override
  Future<IdentityAccessResult<List<WorkspaceAccess>>> listWorkspaceAccesses({
    required String userId,
  }) async {
    listCalls++;
    final handler = listHandler;
    return handler == null ? result : handler(userId);
  }

  void authenticate({
    AuthenticationAssuranceLevel level = AuthenticationAssuranceLevel.aal2,
  }) {
    currentSession = AuthenticatedSession(
      userId: 'user-a',
      currentAssuranceLevel: level,
      nextAssuranceLevel: level,
    );
  }

  void emit(AuthenticatedSession? session) {
    currentSession = session;
    _sessions.add(session);
  }

  Future<void> close() => _sessions.close();
}

class _FakePropertyRepository implements PropertyRepository {
  PropertyRepositoryResult<PropertyPageResult> listResult =
      const PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[]),
      );
  PropertyRepositoryResult<PropertyDto> detailResult =
      const PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.notFound,
        message: 'Not found.',
      );
  Future<PropertyRepositoryResult<PropertyPageResult>> Function(
    PropertyListQuery query,
  )?
  listHandler;
  final Queue<PropertyRepositoryResult<PropertyDto>> updateResults =
      Queue<PropertyRepositoryResult<PropertyDto>>();
  final List<String> listWorkspaceIds = <String>[];
  final List<PropertyListQuery> listQueries = <PropertyListQuery>[];
  final List<String> detailPropertyIds = <String>[];
  final List<PropertyUpdateCommand> updateCommands = <PropertyUpdateCommand>[];
  final Queue<PropertyRepositoryResult<PropertyDto>> createResults =
      Queue<PropertyRepositoryResult<PropertyDto>>();
  final List<PropertyCreateCommand> createCommands = <PropertyCreateCommand>[];

  int get listCalls => listWorkspaceIds.length;

  @override
  Future<PropertyRepositoryResult<PropertyPageResult>> list(
    PropertyListQuery query,
  ) async {
    listWorkspaceIds.add(query.workspaceId);
    listQueries.add(query);
    final handler = listHandler;
    return handler == null ? listResult : handler(query);
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> create(
    PropertyCreateCommand command,
  ) async {
    createCommands.add(command);
    return createResults.isEmpty
        ? const PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.forbidden,
          message: 'Property creation is not permitted.',
        )
        : createResults.removeFirst();
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> getById({
    required String workspaceId,
    required String propertyId,
  }) async {
    detailPropertyIds.add(propertyId);
    return detailResult;
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> update(
    PropertyUpdateCommand command,
  ) async {
    updateCommands.add(command);
    return updateResults.removeFirst();
  }
}

class _FakePropertyInvalidationSource
    implements PropertyQueryInvalidationSource {
  final Map<String, StreamController<PropertyQueryInvalidation>> _controllers =
      <String, StreamController<PropertyQueryInvalidation>>{};
  final List<String> workspaceIds = <String>[];
  final Map<String, int> cancelCalls = <String, int>{};

  @override
  Stream<PropertyQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) {
    workspaceIds.add(workspaceId);
    final controller = StreamController<PropertyQueryInvalidation>.broadcast(
      onCancel: () {
        cancelCalls.update(
          workspaceId,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      },
    );
    _controllers[workspaceId] = controller;
    return controller.stream;
  }

  void emit(PropertyQueryInvalidation invalidation) {
    _controllers[invalidation.workspaceId]?.add(invalidation);
  }

  void emitError(String workspaceId, Object error) {
    _controllers[workspaceId]?.addError(error);
  }

  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}

class _FakeEntitlementInvalidationSource
    implements EntitlementInvalidationSource {
  final Map<String, StreamController<EntitlementInvalidation>> _controllers =
      <String, StreamController<EntitlementInvalidation>>{};
  final List<String> userIds = <String>[];
  final Map<String, int> cancelCalls = <String, int>{};

  @override
  Stream<EntitlementInvalidation> watchUser({required String userId}) {
    userIds.add(userId);
    final controller = StreamController<EntitlementInvalidation>.broadcast(
      onCancel: () {
        cancelCalls.update(userId, (value) => value + 1, ifAbsent: () => 1);
      },
    );
    _controllers[userId] = controller;
    return controller.stream;
  }

  void emit(EntitlementInvalidation invalidation) {
    _controllers[invalidation.userId]?.add(invalidation);
  }

  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}
