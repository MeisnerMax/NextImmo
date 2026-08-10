class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.key,
    required this.name,
    required this.version,
  });

  final String id;
  final String key;
  final String name;
  final int version;
}

class MembershipSummary {
  const MembershipSummary({
    required this.id,
    required this.workspaceId,
    required this.userId,
    required this.roleId,
    required this.version,
  });

  final String id;
  final String workspaceId;
  final String userId;
  final String roleId;
  final int version;
}

class WorkspaceAccess {
  WorkspaceAccess({
    required this.workspace,
    required this.membership,
    required Set<String> permissions,
  }) : permissions = Set<String>.unmodifiable(permissions);

  final WorkspaceSummary workspace;
  final MembershipSummary membership;
  final Set<String> permissions;

  bool allows(String permission) => permissions.contains(permission);
}

enum AuthenticationAssuranceLevel { unknown, aal1, aal2 }

class AuthenticatedSession {
  const AuthenticatedSession({
    required this.userId,
    required this.currentAssuranceLevel,
    required this.nextAssuranceLevel,
  });

  final String userId;
  final AuthenticationAssuranceLevel currentAssuranceLevel;
  final AuthenticationAssuranceLevel nextAssuranceLevel;

  bool get requiresMfaChallenge =>
      currentAssuranceLevel == AuthenticationAssuranceLevel.unknown ||
      nextAssuranceLevel == AuthenticationAssuranceLevel.unknown ||
      (currentAssuranceLevel == AuthenticationAssuranceLevel.aal1 &&
          nextAssuranceLevel == AuthenticationAssuranceLevel.aal2);
}

class TotpFactor {
  const TotpFactor({required this.id, this.friendlyName});

  final String id;
  final String? friendlyName;
}

class TotpEnrollment {
  const TotpEnrollment({
    required this.factorId,
    required this.secret,
    required this.uri,
  });

  final String factorId;
  final String secret;
  final String uri;
}

class TotpChallenge {
  const TotpChallenge({
    required this.factorId,
    required this.challengeId,
    required this.expiresAt,
  });

  final String factorId;
  final String challengeId;
  final DateTime expiresAt;
}

enum IdentityAccessFailureKind {
  invalidInput,
  unauthenticated,
  forbidden,
  verificationFailed,
  rateLimited,
  infrastructureFailure,

  /// Email and password did not match an account. Deliberately a single kind
  /// for "no such user" and "wrong password": distinguishing them would let an
  /// unauthenticated caller enumerate accounts.
  invalidCredentials,
}

sealed class IdentityAccessResult<T> {
  const IdentityAccessResult();
}

class IdentityAccessSuccess<T> extends IdentityAccessResult<T> {
  const IdentityAccessSuccess(this.value);

  final T value;
}

class IdentityAccessFailure<T> extends IdentityAccessResult<T> {
  const IdentityAccessFailure({required this.kind, required this.message});

  final IdentityAccessFailureKind kind;
  final String message;
}

abstract interface class IdentityAccessRepository {
  AuthenticatedSession? get currentSession;

  Stream<AuthenticatedSession?> watchSession();

  Future<IdentityAccessResult<List<WorkspaceAccess>>> listWorkspaceAccesses({
    required String userId,
  });

  /// The primary sign-in. Yields an `aal1` session; privileged capabilities
  /// stay closed until a TOTP factor lifts it to `aal2`.
  Future<IdentityAccessResult<void>> signInWithPassword({
    required String email,
    required String password,
  });

  /// Retained for link-based flows such as password recovery, which still need
  /// the desktop deep link. It is no longer part of the primary sign-in path.
  Future<IdentityAccessResult<void>> requestPasswordlessSignIn({
    required String email,
  });

  Future<IdentityAccessResult<TotpEnrollment>> enrollTotp();

  Future<IdentityAccessResult<List<TotpFactor>>> listTotpFactors();

  Future<IdentityAccessResult<TotpChallenge>> challengeTotp({
    required String factorId,
  });

  Future<IdentityAccessResult<AuthenticatedSession>> verifyTotp({
    required TotpChallenge challenge,
    required String code,
  });

  Future<IdentityAccessResult<void>> signOut();
}
