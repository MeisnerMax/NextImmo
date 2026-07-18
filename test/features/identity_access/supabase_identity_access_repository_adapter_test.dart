import 'package:flutter_test/flutter_test.dart';
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
  @override
  AuthenticatedSession? currentSession = const AuthenticatedSession(
    userId: 'user-a',
    currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
    nextAssuranceLevel: AuthenticationAssuranceLevel.aal1,
  );

  List<Map<String, dynamic>> memberships = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> workspaces = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> rolePermissions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> permissions = <Map<String, dynamic>>[];
  int membershipCalls = 0;
  int workspaceCalls = 0;
  List<String>? workspaceIds;
  final List<String> passwordlessEmails = <String>[];
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
  Future<void> requestPasswordlessSignIn(String email) async {
    passwordlessEmails.add(email);
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
    return workspaces;
  }

  @override
  Future<List<Map<String, dynamic>>> listRolePermissions(
    List<String> workspaceIds,
  ) async {
    return rolePermissions;
  }

  @override
  Future<List<Map<String, dynamic>>> listPermissions(
    List<String> permissionIds,
  ) async {
    return permissions;
  }
}
