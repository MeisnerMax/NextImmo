import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/identity_access/data/supabase_identity_access_repository_adapter.dart';

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

  @override
  Stream<AuthenticatedSession?> watchSession() =>
      const Stream<AuthenticatedSession?>.empty();

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
