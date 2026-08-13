import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/desktop_auth_callback.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/identity_access/data/supabase_identity_access_repository_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabaseIdentityAccessRepositoryAdapter', () {
    late _FakeIdentityGateway gateway;
    late SupabaseIdentityAccessRepositoryAdapter repository;

    setUp(() {
      gateway = _FakeIdentityGateway();
      repository = SupabaseIdentityAccessRepositoryAdapter.withGateway(gateway);
    });

    test('rejects a user other than the authenticated actor', () async {
      final result = await repository.listWorkspaceAccesses(
        userId: 'another-user',
      );

      expect(
        (result as IdentityAccessFailure<List<WorkspaceAccess>>).kind,
        IdentityAccessFailureKind.unauthenticated,
      );
      expect(gateway.membershipCalls, 0);
    });

    test(
      'rejects workspace access while an MFA challenge is pending',
      () async {
        gateway.currentSession = const AuthenticatedSession(
          userId: 'user-a',
          currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
          nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
        );

        final result = await repository.listWorkspaceAccesses(userId: 'user-a');

        expect(
          (result as IdentityAccessFailure<List<WorkspaceAccess>>).kind,
          IdentityAccessFailureKind.unauthenticated,
        );
        expect(gateway.membershipCalls, 0);
      },
    );

    // SECURITY-AAL-CLIENT-02: the factorless case. current == next == aal1 has
    // no pending challenge, so the old guard let it through and the server
    // answered every business read with an empty body -- which the client then
    // showed as "no workspace access" to an authorized member.
    test('rejects workspace access for a session with no factor yet', () async {
      gateway.currentSession = const AuthenticatedSession(
        userId: 'user-a',
        currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
        nextAssuranceLevel: AuthenticationAssuranceLevel.aal1,
      );

      final result = await repository.listWorkspaceAccesses(userId: 'user-a');

      expect(
        (result as IdentityAccessFailure<List<WorkspaceAccess>>).kind,
        IdentityAccessFailureKind.unauthenticated,
      );
      expect(gateway.membershipCalls, 0);
    });

    test('fails closed for an unknown assurance level', () async {
      gateway.currentSession = const AuthenticatedSession(
        userId: 'user-a',
        currentAssuranceLevel: AuthenticationAssuranceLevel.unknown,
        nextAssuranceLevel: AuthenticationAssuranceLevel.unknown,
      );

      final result = await repository.listWorkspaceAccesses(userId: 'user-a');

      expect(
        (result as IdentityAccessFailure<List<WorkspaceAccess>>).kind,
        IdentityAccessFailureKind.unauthenticated,
      );
      expect(gateway.membershipCalls, 0);
    });

    test('maps active memberships and exact role permissions', () async {
      gateway.memberships = <Map<String, dynamic>>[_membershipJson()];
      gateway.workspaces = <Map<String, dynamic>>[_workspaceJson()];
      gateway.rolePermissions = <Map<String, dynamic>>[
        <String, dynamic>{
          'workspace_id': 'workspace-a',
          'role_id': 'role-a',
          'permission_id': 'permission-read',
        },
        <String, dynamic>{
          'workspace_id': 'workspace-a',
          'role_id': 'another-role',
          'permission_id': 'permission-update',
        },
      ];
      gateway.permissions = <Map<String, dynamic>>[
        <String, dynamic>{'id': 'permission-read', 'key': 'property.read'},
        <String, dynamic>{'id': 'permission-update', 'key': 'property.update'},
      ];

      final result = await repository.listWorkspaceAccesses(userId: 'user-a');
      final access =
          (result as IdentityAccessSuccess<List<WorkspaceAccess>>).value.single;

      expect(access.workspace.id, 'workspace-a');
      expect(access.membership.userId, 'user-a');
      expect(access.allows('property.read'), isTrue);
      expect(access.allows('property.update'), isFalse);
      expect(gateway.workspaceIds, <String>['workspace-a']);
    });

    test('returns no access when no active membership is visible', () async {
      final result = await repository.listWorkspaceAccesses(userId: 'user-a');

      expect(
        (result as IdentityAccessSuccess<List<WorkspaceAccess>>).value,
        isEmpty,
      );
      expect(gateway.workspaceCalls, 0);
    });

    test('loads workspace and role-permission rows concurrently', () async {
      gateway.memberships = <Map<String, dynamic>>[_membershipJson()];
      gateway.workspaces = <Map<String, dynamic>>[_workspaceJson()];
      gateway.rolePermissions = <Map<String, dynamic>>[
        <String, dynamic>{
          'workspace_id': 'workspace-a',
          'role_id': 'role-a',
          'permission_id': 'permission-read',
        },
      ];
      gateway.permissions = <Map<String, dynamic>>[
        <String, dynamic>{'id': 'permission-read', 'key': 'property.read'},
      ];
      gateway.workspaceBlocker = Completer<void>();
      gateway.rolePermissionBlocker = Completer<void>();

      final resultFuture = repository.listWorkspaceAccesses(userId: 'user-a');
      await Future<void>.delayed(Duration.zero);

      expect(gateway.workspaceCalls, 1);
      expect(gateway.rolePermissionCalls, 1);
      gateway.workspaceBlocker!.complete();
      gateway.rolePermissionBlocker!.complete();

      final result = await resultFuture;
      expect(result, isA<IdentityAccessSuccess<List<WorkspaceAccess>>>());
    });

    test('fails closed for malformed or foreign membership data', () async {
      gateway.memberships = <Map<String, dynamic>>[
        _membershipJson()..['user_id'] = 'foreign-user',
      ];

      final result = await repository.listWorkspaceAccesses(userId: 'user-a');

      expect(
        (result as IdentityAccessFailure<List<WorkspaceAccess>>).kind,
        IdentityAccessFailureKind.infrastructureFailure,
      );
    });

    test('fails closed when a permission reference is missing', () async {
      gateway.memberships = <Map<String, dynamic>>[_membershipJson()];
      gateway.workspaces = <Map<String, dynamic>>[_workspaceJson()];
      gateway.rolePermissions = <Map<String, dynamic>>[
        <String, dynamic>{
          'workspace_id': 'workspace-a',
          'role_id': 'role-a',
          'permission_id': 'missing-permission',
        },
      ];

      final result = await repository.listWorkspaceAccesses(userId: 'user-a');

      final failure = result as IdentityAccessFailure<List<WorkspaceAccess>>;
      expect(failure.kind, IdentityAccessFailureKind.infrastructureFailure);
      expect(failure.message, isNot(contains('missing-permission')));
    });

    test('signs in with email and password', () async {
      gateway.currentSession = null;

      final result = await repository.signInWithPassword(
        email: '  user@example.test  ',
        password: 'correct-horse',
      );

      expect(result, isA<IdentityAccessSuccess<void>>());
      expect(gateway.passwordSignIns, hasLength(1));
      // The email is normalised, the password is passed through untouched:
      // surrounding whitespace is part of a password.
      expect(gateway.passwordSignIns.single.email, 'user@example.test');
      expect(gateway.passwordSignIns.single.password, 'correct-horse');
      // The primary path must not fall back to a magic link.
      expect(gateway.passwordlessEmails, isEmpty);
    });

    test('rejects malformed input before contacting the gateway', () async {
      gateway.currentSession = null;

      final badEmail = await repository.signInWithPassword(
        email: 'invalid',
        password: 'correct-horse',
      );
      expect(
        (badEmail as IdentityAccessFailure<void>).kind,
        IdentityAccessFailureKind.invalidInput,
      );

      final noPassword = await repository.signInWithPassword(
        email: 'user@example.test',
        password: '',
      );
      expect(
        (noPassword as IdentityAccessFailure<void>).kind,
        IdentityAccessFailureKind.invalidInput,
      );

      expect(gateway.passwordSignIns, isEmpty);
    });

    test('does not disclose whether an account exists', () async {
      // GoTrue answers a wrong password and an unknown address with the same
      // code; the adapter must not turn that into two different messages.
      gateway.currentSession = null;
      gateway.passwordError = const AuthException(
        'Invalid login credentials',
        code: 'invalid_credentials',
      );

      final failure =
          await repository.signInWithPassword(
                email: 'user@example.test',
                password: 'wrong',
              )
              as IdentityAccessFailure<void>;

      expect(failure.kind, IdentityAccessFailureKind.invalidCredentials);
      expect(failure.message, 'Email or password is incorrect.');
      expect(failure.message, isNot(contains('Invalid login credentials')));
      expect(failure.message.toLowerCase(), isNot(contains('not found')));
      expect(failure.message.toLowerCase(), isNot(contains('no user')));
    });

    test('reports an unconfirmed email the same way', () async {
      // Otherwise the sign-in form reveals that the address is registered.
      gateway.currentSession = null;
      gateway.passwordError = const AuthException(
        'Email not confirmed',
        code: 'email_not_confirmed',
      );

      final failure =
          await repository.signInWithPassword(
                email: 'user@example.test',
                password: 'correct-horse',
              )
              as IdentityAccessFailure<void>;

      expect(failure.kind, IdentityAccessFailureKind.invalidCredentials);
      expect(failure.message, 'Email or password is incorrect.');
    });

    test('refuses a second sign-in while a session exists', () async {
      final failure =
          await repository.signInWithPassword(
                email: 'user@example.test',
                password: 'correct-horse',
              )
              as IdentityAccessFailure<void>;

      expect(failure.kind, IdentityAccessFailureKind.forbidden);
      expect(gateway.passwordSignIns, isEmpty);
    });

    test('requests passwordless sign-in without implicit signup', () async {
      gateway.currentSession = null;

      final invalid = await repository.requestPasswordlessSignIn(
        email: 'invalid',
      );
      expect(
        (invalid as IdentityAccessFailure<void>).kind,
        IdentityAccessFailureKind.invalidInput,
      );
      expect(gateway.passwordlessEmails, isEmpty);

      final result = await repository.requestPasswordlessSignIn(
        email: '  user@example.test  ',
      );
      expect(result, isA<IdentityAccessSuccess<void>>());
      expect(gateway.passwordlessEmails, <String>['user@example.test']);
    });

    test('sends the desktop callback as the passwordless redirect', () async {
      // Without this the sign-in mail points at the Site URL, the browser
      // completes the flow there, and the desktop app is never called back.
      gateway.currentSession = null;
      final desktop = SupabaseIdentityAccessRepositoryAdapter.withGateway(
        gateway,
        passwordlessRedirectTo: desktopAuthCallbackUri,
      );

      await desktop.requestPasswordlessSignIn(email: 'user@example.test');

      expect(gateway.passwordlessRedirects, <String?>[desktopAuthCallbackUri]);
    });

    test('resolves the redirect per platform when none is given', () async {
      // The platform override is set explicitly so the expectation holds on
      // every host the suite runs on, not just on Windows.
      gateway.currentSession = null;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await SupabaseIdentityAccessRepositoryAdapter.withGateway(
        gateway,
      ).requestPasswordlessSignIn(email: 'user@example.test');

      // Anything that is not the desktop app keeps GoTrue's default: a custom
      // scheme would send a browser to a URL it cannot open.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await SupabaseIdentityAccessRepositoryAdapter.withGateway(
        gateway,
      ).requestPasswordlessSignIn(email: 'user@example.test');

      expect(gateway.passwordlessRedirects, <String?>[
        desktopAuthCallbackUri,
        null,
      ]);
    });

    test(
      'maps passwordless rate limits without leaking provider details',
      () async {
        gateway.currentSession = null;
        gateway.passwordlessError = const AuthApiException(
          'provider detail',
          code: 'over_email_send_rate_limit',
        );

        final result = await repository.requestPasswordlessSignIn(
          email: 'user@example.test',
        );
        final failure = result as IdentityAccessFailure<void>;

        expect(failure.kind, IdentityAccessFailureKind.rateLimited);
        expect(failure.message, isNot(contains('provider detail')));
        expect(failure.message, isNot(contains('user@example.test')));
      },
    );

    test('enrolls and lists TOTP factors only for a session', () async {
      gateway.enrollment = const TotpEnrollment(
        factorId: 'factor-new',
        secret: 'sensitive-secret',
        uri: 'otpauth://sensitive',
      );
      gateway.factors = const <TotpFactor>[
        TotpFactor(id: 'factor-a', friendlyName: 'Primary'),
      ];

      final enrollment = await repository.enrollTotp();
      final factors = await repository.listTotpFactors();

      expect(
        (enrollment as IdentityAccessSuccess<TotpEnrollment>).value.factorId,
        'factor-new',
      );
      expect(
        (factors as IdentityAccessSuccess<List<TotpFactor>>).value.single.id,
        'factor-a',
      );

      gateway.currentSession = null;
      expect(
        (await repository.enrollTotp() as IdentityAccessFailure<TotpEnrollment>)
            .kind,
        IdentityAccessFailureKind.unauthenticated,
      );
    });

    test('challenges and verifies TOTP with an exact AAL2 result', () async {
      gateway.challenge = TotpChallenge(
        factorId: 'factor-a',
        challengeId: 'challenge-a',
        expiresAt: DateTime.utc(2026, 7, 18, 12),
      );

      final challengeResult = await repository.challengeTotp(
        factorId: 'factor-a',
      );
      final challenge =
          (challengeResult as IdentityAccessSuccess<TotpChallenge>).value;
      final verified = await repository.verifyTotp(
        challenge: challenge,
        code: '123456',
      );

      expect(verified, isA<IdentityAccessSuccess<AuthenticatedSession>>());
      expect(gateway.challengeFactorIds, <String>['factor-a']);
      expect(gateway.verifiedCodes, <String>['123456']);
      expect(
        gateway.currentSession?.currentAssuranceLevel,
        AuthenticationAssuranceLevel.aal2,
      );
    });

    test('rejects invalid TOTP input before verification', () async {
      final challenge = TotpChallenge(
        factorId: 'factor-a',
        challengeId: 'challenge-a',
        expiresAt: DateTime.utc(2026, 7, 18, 12),
      );

      final result = await repository.verifyTotp(
        challenge: challenge,
        code: '12-secret',
      );

      expect(
        (result as IdentityAccessFailure<AuthenticatedSession>).kind,
        IdentityAccessFailureKind.invalidInput,
      );
      expect(gateway.verifiedCodes, isEmpty);
    });

    test('sign-out is local and idempotent', () async {
      expect(await repository.signOut(), isA<IdentityAccessSuccess<void>>());
      expect(gateway.signOutCalls, 1);
      expect(gateway.currentSession, isNull);

      expect(await repository.signOut(), isA<IdentityAccessSuccess<void>>());
      expect(gateway.signOutCalls, 1);
    });
  });
}

Map<String, dynamic> _membershipJson() {
  return <String, dynamic>{
    'id': 'membership-a',
    'workspace_id': 'workspace-a',
    'user_id': 'user-a',
    'role_id': 'role-a',
    'status': 'active',
    'version': 1,
  };
}

Map<String, dynamic> _workspaceJson() {
  return <String, dynamic>{
    'id': 'workspace-a',
    'key': 'workspace-a',
    'name': 'Workspace A',
    'version': 1,
    'archived_at': null,
  };
}

class _FakeIdentityGateway implements IdentityAccessSupabaseGateway {
  // aal2 by default. The mapping and fail-closed tests below are about
  // membership and permission handling, and since DEC-025 a session below aal2
  // never reaches that code at all -- the default used to be aal1/aal1, which
  // meant those tests were quietly asserting that a factorless session could
  // read workspace access. The boundary itself is covered by the three
  // assurance-level tests at the top of this file.
  @override
  AuthenticatedSession? currentSession = const AuthenticatedSession(
    userId: 'user-a',
    currentAssuranceLevel: AuthenticationAssuranceLevel.aal2,
    nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
  );

  final List<({String email, String password})> passwordSignIns =
      <({String email, String password})>[];
  Object? passwordError;

  List<Map<String, dynamic>> memberships = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> workspaces = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> rolePermissions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> permissions = <Map<String, dynamic>>[];
  int membershipCalls = 0;
  int workspaceCalls = 0;
  int rolePermissionCalls = 0;
  List<String>? workspaceIds;
  Completer<void>? workspaceBlocker;
  Completer<void>? rolePermissionBlocker;
  final List<String> passwordlessEmails = <String>[];
  final List<String?> passwordlessRedirects = <String?>[];
  Object? passwordlessError;
  TotpEnrollment enrollment = const TotpEnrollment(
    factorId: 'factor-new',
    secret: 'secret',
    uri: 'otpauth://totp',
  );
  List<TotpFactor> factors = const <TotpFactor>[];
  TotpChallenge challenge = TotpChallenge(
    factorId: 'factor-a',
    challengeId: 'challenge-a',
    expiresAt: DateTime.utc(2026, 7, 18, 12),
  );
  final List<String> challengeFactorIds = <String>[];
  final List<String> verifiedCodes = <String>[];
  int signOutCalls = 0;

  @override
  Stream<AuthenticatedSession?> watchSession() =>
      const Stream<AuthenticatedSession?>.empty();

  @override
  Future<void> signInWithPassword(String email, String password) async {
    passwordSignIns.add((email: email, password: password));
    final error = passwordError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> requestPasswordlessSignIn(
    String email, {
    String? redirectTo,
  }) async {
    passwordlessEmails.add(email);
    passwordlessRedirects.add(redirectTo);
    final error = passwordlessError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<TotpEnrollment> enrollTotp() async => enrollment;

  @override
  Future<List<TotpFactor>> listTotpFactors() async => factors;

  @override
  Future<TotpChallenge> challengeTotp(String factorId) async {
    challengeFactorIds.add(factorId);
    return challenge;
  }

  @override
  Future<void> verifyTotp(TotpChallenge challenge, String code) async {
    verifiedCodes.add(code);
    currentSession = const AuthenticatedSession(
      userId: 'user-a',
      currentAssuranceLevel: AuthenticationAssuranceLevel.aal2,
      nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    currentSession = null;
  }

  @override
  Future<List<Map<String, dynamic>>> listActiveMemberships(
    String userId,
  ) async {
    membershipCalls++;
    return memberships;
  }

  @override
  Future<List<Map<String, dynamic>>> listWorkspaces(
    List<String> workspaceIds,
  ) async {
    workspaceCalls++;
    this.workspaceIds = workspaceIds;
    await workspaceBlocker?.future;
    return workspaces;
  }

  @override
  Future<List<Map<String, dynamic>>> listRolePermissions(
    List<String> workspaceIds,
  ) async {
    rolePermissionCalls++;
    await rolePermissionBlocker?.future;
    return rolePermissions;
  }

  @override
  Future<List<Map<String, dynamic>>> listPermissions(
    List<String> permissionIds,
  ) async {
    return permissions;
  }
}
