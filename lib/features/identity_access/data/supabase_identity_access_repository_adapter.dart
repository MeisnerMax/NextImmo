import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/identity_access_repository.dart';

abstract interface class IdentityAccessSupabaseGateway {
  AuthenticatedSession? get currentSession;

  Stream<AuthenticatedSession?> watchSession();

  Future<void> requestPasswordlessSignIn(String email);

  Future<TotpEnrollment> enrollTotp();

  Future<List<TotpFactor>> listTotpFactors();

  Future<TotpChallenge> challengeTotp(String factorId);

  Future<void> verifyTotp(TotpChallenge challenge, String code);

  Future<void> signOut();

  Future<List<Map<String, dynamic>>> listActiveMemberships(String userId);

  Future<List<Map<String, dynamic>>> listWorkspaces(List<String> workspaceIds);

  Future<List<Map<String, dynamic>>> listRolePermissions(
    List<String> workspaceIds,
  );

  Future<List<Map<String, dynamic>>> listPermissions(
    List<String> permissionIds,
  );
}

class SupabaseIdentityAccessGateway implements IdentityAccessSupabaseGateway {
  SupabaseIdentityAccessGateway(this._client);

  final SupabaseClient _client;

  @override
  AuthenticatedSession? get currentSession => _currentSession();

  @override
  Stream<AuthenticatedSession?> watchSession() {
    return _client.auth.onAuthStateChange
        .map((_) => _currentSession())
        .distinct(
          (previous, next) =>
              previous?.userId == next?.userId &&
              previous?.currentAssuranceLevel == next?.currentAssuranceLevel &&
              previous?.nextAssuranceLevel == next?.nextAssuranceLevel,
        );
  }

  @override
  Future<void> requestPasswordlessSignIn(String email) {
    return _client.auth.signInWithOtp(email: email, shouldCreateUser: false);
  }

  @override
  Future<TotpEnrollment> enrollTotp() async {
    final enrollment = await _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      friendlyName: 'NexImmo',
    );
    final totp = enrollment.totp;
    if (totp == null || totp.secret.isEmpty || totp.uri.isEmpty) {
      throw const FormatException('Invalid TOTP enrollment response.');
    }
    return TotpEnrollment(
      factorId: enrollment.id,
      secret: totp.secret,
      uri: totp.uri,
    );
  }

  @override
  Future<List<TotpFactor>> listTotpFactors() async {
    final factors = (await _client.auth.mfa.listFactors()).totp
        .map(
          (factor) =>
              TotpFactor(id: factor.id, friendlyName: factor.friendlyName),
        )
        .toList(growable: false);
    factors.sort((left, right) {
      final byName = (left.friendlyName ?? '').compareTo(
        right.friendlyName ?? '',
      );
      return byName != 0 ? byName : left.id.compareTo(right.id);
    });
    return factors;
  }

  @override
  Future<TotpChallenge> challengeTotp(String factorId) async {
    final challenge = await _client.auth.mfa.challenge(factorId: factorId);
    return TotpChallenge(
      factorId: factorId,
      challengeId: challenge.id,
      expiresAt: challenge.expiresAt,
    );
  }

  @override
  Future<void> verifyTotp(TotpChallenge challenge, String code) async {
    await _client.auth.mfa.verify(
      factorId: challenge.factorId,
      challengeId: challenge.challengeId,
      code: code,
    );
  }

  @override
  Future<void> signOut() {
    return _client.auth.signOut(scope: SignOutScope.local);
  }

  AuthenticatedSession? _currentSession() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }
    final assurance = _client.auth.mfa.getAuthenticatorAssuranceLevel();
    return AuthenticatedSession(
      userId: userId,
      currentAssuranceLevel: _mapAssurance(assurance.currentLevel?.name),
      nextAssuranceLevel: _mapAssurance(assurance.nextLevel?.name),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listActiveMemberships(
    String userId,
  ) async {
    final rows = await _client
        .from('memberships')
        .select('id, workspace_id, user_id, role_id, status, version')
        .eq('user_id', userId)
        .eq('status', 'active');
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listWorkspaces(
    List<String> workspaceIds,
  ) async {
    if (workspaceIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final rows = await _client
        .from('workspaces')
        .select('id, key, name, version, archived_at')
        .inFilter('id', workspaceIds)
        .isFilter('archived_at', null)
        .order('name', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listRolePermissions(
    List<String> workspaceIds,
  ) async {
    if (workspaceIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final rows = await _client
        .from('role_permissions')
        .select('workspace_id, role_id, permission_id')
        .inFilter('workspace_id', workspaceIds);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listPermissions(
    List<String> permissionIds,
  ) async {
    if (permissionIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final rows = await _client
        .from('permissions')
        .select('id, key')
        .inFilter('id', permissionIds);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }
}

class SupabaseIdentityAccessRepositoryAdapter
    implements IdentityAccessRepository {
  SupabaseIdentityAccessRepositoryAdapter({required SupabaseClient client})
    : _gateway = SupabaseIdentityAccessGateway(client);

  SupabaseIdentityAccessRepositoryAdapter.withGateway(
    IdentityAccessSupabaseGateway gateway,
  ) : _gateway = gateway;

  final IdentityAccessSupabaseGateway _gateway;

  @override
  AuthenticatedSession? get currentSession => _gateway.currentSession;

  @override
  Stream<AuthenticatedSession?> watchSession() => _gateway.watchSession();

  @override
  Future<IdentityAccessResult<void>> requestPasswordlessSignIn({
    required String email,
  }) async {
    final normalized = email.trim();
    if (!_validEmail(normalized)) {
      return const IdentityAccessFailure<void>(
        kind: IdentityAccessFailureKind.invalidInput,
        message: 'Enter a valid email address.',
      );
    }
    if (_gateway.currentSession != null) {
      return const IdentityAccessFailure<void>(
        kind: IdentityAccessFailureKind.forbidden,
        message: 'Sign out before requesting another sign-in link.',
      );
    }
    try {
      await _gateway.requestPasswordlessSignIn(normalized);
      return const IdentityAccessSuccess<void>(null);
    } catch (error) {
      return _authFailure<void>(error);
    }
  }

  @override
  Future<IdentityAccessResult<TotpEnrollment>> enrollTotp() async {
    if (_gateway.currentSession == null) {
      return const IdentityAccessFailure<TotpEnrollment>(
        kind: IdentityAccessFailureKind.unauthenticated,
        message: 'Sign in before setting up multi-factor authentication.',
      );
    }
    try {
      return IdentityAccessSuccess<TotpEnrollment>(await _gateway.enrollTotp());
    } catch (error) {
      return _authFailure<TotpEnrollment>(error);
    }
  }

  @override
  Future<IdentityAccessResult<List<TotpFactor>>> listTotpFactors() async {
    if (_gateway.currentSession == null) {
      return const IdentityAccessFailure<List<TotpFactor>>(
        kind: IdentityAccessFailureKind.unauthenticated,
        message: 'Sign in before loading multi-factor authentication.',
      );
    }
    try {
      return IdentityAccessSuccess<List<TotpFactor>>(
        await _gateway.listTotpFactors(),
      );
    } catch (error) {
      return _authFailure<List<TotpFactor>>(error);
    }
  }

  @override
  Future<IdentityAccessResult<TotpChallenge>> challengeTotp({
    required String factorId,
  }) async {
    if (_gateway.currentSession == null) {
      return const IdentityAccessFailure<TotpChallenge>(
        kind: IdentityAccessFailureKind.unauthenticated,
        message: 'Sign in before completing multi-factor authentication.',
      );
    }
    if (factorId.trim().isEmpty) {
      return const IdentityAccessFailure<TotpChallenge>(
        kind: IdentityAccessFailureKind.invalidInput,
        message: 'Select a valid authenticator.',
      );
    }
    try {
      return IdentityAccessSuccess<TotpChallenge>(
        await _gateway.challengeTotp(factorId),
      );
    } catch (error) {
      return _authFailure<TotpChallenge>(error);
    }
  }

  @override
  Future<IdentityAccessResult<AuthenticatedSession>> verifyTotp({
    required TotpChallenge challenge,
    required String code,
  }) async {
    final actor = _gateway.currentSession;
    if (actor == null) {
      return const IdentityAccessFailure<AuthenticatedSession>(
        kind: IdentityAccessFailureKind.unauthenticated,
        message: 'Sign in before completing multi-factor authentication.',
      );
    }
    if (challenge.factorId.trim().isEmpty ||
        challenge.challengeId.trim().isEmpty ||
        !RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      return const IdentityAccessFailure<AuthenticatedSession>(
        kind: IdentityAccessFailureKind.invalidInput,
        message: 'Enter a valid six-digit authenticator code.',
      );
    }
    try {
      await _gateway.verifyTotp(challenge, code.trim());
      final elevated = _gateway.currentSession;
      if (elevated?.userId != actor.userId ||
          elevated?.currentAssuranceLevel !=
              AuthenticationAssuranceLevel.aal2) {
        return const IdentityAccessFailure<AuthenticatedSession>(
          kind: IdentityAccessFailureKind.verificationFailed,
          message: 'The authenticator code could not be verified.',
        );
      }
      return IdentityAccessSuccess<AuthenticatedSession>(elevated!);
    } catch (error) {
      return _authFailure<AuthenticatedSession>(error);
    }
  }

  @override
  Future<IdentityAccessResult<void>> signOut() async {
    if (_gateway.currentSession == null) {
      return const IdentityAccessSuccess<void>(null);
    }
    try {
      await _gateway.signOut();
      return const IdentityAccessSuccess<void>(null);
    } catch (error) {
      return _authFailure<void>(error);
    }
  }

  @override
  Future<IdentityAccessResult<List<WorkspaceAccess>>> listWorkspaceAccesses({
    required String userId,
  }) async {
    final session = _gateway.currentSession;
    if (session?.userId != userId || session!.requiresMfaChallenge) {
      return const IdentityAccessFailure<List<WorkspaceAccess>>(
        kind: IdentityAccessFailureKind.unauthenticated,
        message: 'The requested user is not authenticated.',
      );
    }

    try {
      final membershipRows = await _gateway.listActiveMemberships(userId);
      final memberships = membershipRows
          .map((row) {
            if (_requiredString(row, 'user_id') != userId ||
                _requiredString(row, 'status') != 'active') {
              throw const FormatException('Membership scope mismatch.');
            }
            return MembershipSummary(
              id: _requiredString(row, 'id'),
              workspaceId: _requiredString(row, 'workspace_id'),
              userId: userId,
              roleId: _requiredString(row, 'role_id'),
              version: _requiredInt(row, 'version'),
            );
          })
          .toList(growable: false);
      if (memberships.isEmpty) {
        return const IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[],
        );
      }

      final workspaceIds = memberships
          .map((membership) => membership.workspaceId)
          .toSet()
          .toList(growable: false);
      final workspaceRows = await _gateway.listWorkspaces(workspaceIds);
      final workspaces = <String, WorkspaceSummary>{};
      for (final row in workspaceRows) {
        final id = _requiredString(row, 'id');
        if (!workspaceIds.contains(id) || row['archived_at'] != null) {
          throw const FormatException('Workspace scope mismatch.');
        }
        if (workspaces.containsKey(id)) {
          throw const FormatException('Duplicate workspace.');
        }
        workspaces[id] = WorkspaceSummary(
          id: id,
          key: _requiredString(row, 'key'),
          name: _requiredString(row, 'name'),
          version: _requiredInt(row, 'version'),
        );
      }

      final visibleMemberships = memberships
          .where((membership) => workspaces.containsKey(membership.workspaceId))
          .toList(growable: false);
      final rolePermissionRows = await _gateway.listRolePermissions(
        visibleMemberships
            .map((membership) => membership.workspaceId)
            .toSet()
            .toList(growable: false),
      );
      final permissionIds = rolePermissionRows
          .map((row) => _requiredString(row, 'permission_id'))
          .toSet()
          .toList(growable: false);
      final permissionRows = await _gateway.listPermissions(permissionIds);
      final permissionKeysById = <String, String>{
        for (final row in permissionRows)
          _requiredString(row, 'id'): _requiredString(row, 'key'),
      };
      if (!permissionKeysById.keys.toSet().containsAll(permissionIds)) {
        throw const FormatException('Permission reference is missing.');
      }

      final permissionsByMembership = <String, Set<String>>{
        for (final membership in visibleMemberships) membership.id: <String>{},
      };
      for (final row in rolePermissionRows) {
        final workspaceId = _requiredString(row, 'workspace_id');
        final roleId = _requiredString(row, 'role_id');
        final permissionId = _requiredString(row, 'permission_id');
        final matching = visibleMemberships.where(
          (membership) =>
              membership.workspaceId == workspaceId &&
              membership.roleId == roleId,
        );
        for (final membership in matching) {
          permissionsByMembership[membership.id]!.add(
            permissionKeysById[permissionId]!,
          );
        }
      }

      final accesses = visibleMemberships
        .map(
          (membership) => WorkspaceAccess(
            workspace: workspaces[membership.workspaceId]!,
            membership: membership,
            permissions: permissionsByMembership[membership.id]!,
          ),
        )
        .toList(growable: false)..sort((left, right) {
        final byName = left.workspace.name.compareTo(right.workspace.name);
        return byName != 0
            ? byName
            : left.workspace.id.compareTo(right.workspace.id);
      });
      return IdentityAccessSuccess<List<WorkspaceAccess>>(accesses);
    } catch (_) {
      return const IdentityAccessFailure<List<WorkspaceAccess>>(
        kind: IdentityAccessFailureKind.infrastructureFailure,
        message: 'Workspace access could not be loaded.',
      );
    }
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected non-empty string field: $key.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('Expected integer field: $key.');
  }
  return value;
}

AuthenticationAssuranceLevel _mapAssurance(String? value) {
  return switch (value) {
    'aal1' => AuthenticationAssuranceLevel.aal1,
    'aal2' => AuthenticationAssuranceLevel.aal2,
    _ => AuthenticationAssuranceLevel.unknown,
  };
}

bool _validEmail(String value) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
}

IdentityAccessFailure<T> _authFailure<T>(Object error) {
  final kind = switch (error) {
    AuthException(code: final code) when _rateLimitCodes.contains(code) =>
      IdentityAccessFailureKind.rateLimited,
    AuthException(code: final code) when _verificationCodes.contains(code) =>
      IdentityAccessFailureKind.verificationFailed,
    AuthException(code: final code) when _unauthenticatedCodes.contains(code) =>
      IdentityAccessFailureKind.unauthenticated,
    AuthException(code: final code) when _forbiddenCodes.contains(code) =>
      IdentityAccessFailureKind.forbidden,
    _ => IdentityAccessFailureKind.infrastructureFailure,
  };
  final message = switch (kind) {
    IdentityAccessFailureKind.rateLimited =>
      'Too many authentication attempts. Try again later.',
    IdentityAccessFailureKind.verificationFailed =>
      'The authenticator code could not be verified.',
    IdentityAccessFailureKind.unauthenticated => 'The session has expired.',
    IdentityAccessFailureKind.forbidden =>
      'This authentication action is not permitted.',
    _ => 'Authentication is temporarily unavailable.',
  };
  return IdentityAccessFailure<T>(kind: kind, message: message);
}

const _rateLimitCodes = <String?>{
  'over_request_rate_limit',
  'over_email_send_rate_limit',
};
const _verificationCodes = <String?>{
  'otp_expired',
  'mfa_challenge_expired',
  'mfa_verification_failed',
  'mfa_verification_rejected',
  'mfa_factor_not_found',
};
const _unauthenticatedCodes = <String?>{
  'session_not_found',
  'session_expired',
  'session_missing',
  'no_authorization',
  'bad_jwt',
};
const _forbiddenCodes = <String?>{
  'user_banned',
  'email_provider_disabled',
  'mfa_totp_enroll_not_enabled',
  'mfa_totp_verify_not_enabled',
  'insufficient_aal',
};
