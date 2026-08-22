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

  /// The only condition under which workspace business data may be requested.
  ///
  /// `DEC-025` makes aal2 the server-side boundary for the whole workspace
  /// business surface, so anything below it is an incomplete authentication
  /// rather than an account without access. The distinction matters because a
  /// denied read answers `200` with an empty body: a client that waits for the
  /// server to object cannot tell "not elevated yet" from "no workspaces", and
  /// would show an empty shell to a perfectly authorized member.
  bool get isAal2 =>
      currentAssuranceLevel == AuthenticationAssuranceLevel.aal2;

  /// Whether reaching aal2 runs through a *challenge* of an existing verified
  /// factor. False for a session that has no verified factor yet -- that one
  /// reaches aal2 through enrolment instead. Both are below the boundary; this
  /// only says which path leads out of it, never whether business data may
  /// load. Use [isAal2] for that.
  bool get requiresMfaChallenge =>
      currentAssuranceLevel == AuthenticationAssuranceLevel.unknown ||
      nextAssuranceLevel == AuthenticationAssuranceLevel.unknown ||
      (currentAssuranceLevel == AuthenticationAssuranceLevel.aal1 &&
          nextAssuranceLevel == AuthenticationAssuranceLevel.aal2);
}

/// The friendly name this application enrols every TOTP factor under.
///
/// GoTrue rejects a second enrolment under a name that is already taken --
/// by a verified factor or by the unverified residue of an abandoned one. The
/// recovery path therefore looks for exactly this name, and never invents
/// another to slip past the conflict.
const totpEnrollmentFriendlyName = 'NexImmo';

/// Whether a TOTP factor has completed its enrolment.
///
/// GoTrue leaves an enrolled-but-unverified factor on the account when a setup
/// is abandoned before the first code is accepted. `listFactors().totp` filters
/// those out, so a client reading only that list sees an account with a
/// half-finished enrolment as an account with no factor at all.
///
/// [unknown] is a status the SDK could not map. Such a factor is neither
/// challengeable nor removable: the only safe reading of "I do not know what
/// this is" is to touch nothing.
enum TotpFactorStatus { verified, unverified, unknown }

class TotpFactor {
  const TotpFactor({
    required this.id,
    this.friendlyName,
    this.status = TotpFactorStatus.verified,
  });

  final String id;
  final String? friendlyName;
  final TotpFactorStatus status;

  bool get isVerified => status == TotpFactorStatus.verified;

  bool get isUnverified => status == TotpFactorStatus.unverified;
}

/// The complete TOTP factor inventory for the current user, unverified factors
/// included.
///
/// One object rather than two loose lists, so no caller can reason about "the
/// factors" without saying which kind it means: only [challengeable] can answer
/// a challenge, and only [recoverable] may ever be considered for removal.
class TotpFactorInventory {
  TotpFactorInventory({required List<TotpFactor> factors})
    : factors = List<TotpFactor>.unmodifiable(factors);

  const TotpFactorInventory.empty() : factors = const <TotpFactor>[];

  final List<TotpFactor> factors;

  /// Verified factors. These, and only these, can answer a challenge.
  List<TotpFactor> get challengeable =>
      factors.where((factor) => factor.isVerified).toList(growable: false);

  /// Unverified factors -- the residue of an interrupted enrolment, and the
  /// only factors this application may ever unenroll. A factor of unknown
  /// status is deliberately not in here.
  List<TotpFactor> get recoverable =>
      factors.where((factor) => factor.isUnverified).toList(growable: false);

  bool get isEmpty => factors.isEmpty;

  TotpFactor? findById(String id) {
    for (final factor in factors) {
      if (factor.id == id) {
        return factor;
      }
    }
    return null;
  }

  /// The factor an interrupted enrolment left behind, when that is the whole
  /// story the inventory tells: no verified factor, and exactly one unverified
  /// factor under this application's own name. A verified factor takes
  /// precedence -- the account can reach aal2 through it, and nothing needs
  /// recovering -- so this is null whenever [challengeable] is not empty.
  TotpFactor? get interruptedEnrollment {
    if (challengeable.isNotEmpty) {
      return null;
    }
    final candidates = _ownUnverified;
    return candidates.length == 1 ? candidates.single : null;
  }

  /// True when the inventory cannot be reduced to one of the states the client
  /// knows how to leave safely: a factor of unknown status, or more than one
  /// unverified factor under this application's name. Neither a challenge, an
  /// enrolment nor a removal is a sound move from here.
  bool get isAmbiguous =>
      factors.any((factor) => factor.status == TotpFactorStatus.unknown) ||
      (challengeable.isEmpty && _ownUnverified.length > 1);

  List<TotpFactor> get _ownUnverified => recoverable
      .where((factor) => factor.friendlyName == totpEnrollmentFriendlyName)
      .toList(growable: false);
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

  /// A factor with the requested friendly name already exists. Almost always
  /// the residue of an interrupted enrolment rather than a real conflict, and
  /// recoverable -- which is why it must not land in the generic
  /// infrastructure bucket that reads "temporarily unavailable".
  factorNameConflict,

  /// The account already holds the maximum number of enrolled factors. Also
  /// recoverable, but never by deleting a verified factor.
  tooManyFactors,
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

  /// The full factor inventory, unverified factors included. Replaces the older
  /// verified-only listing: an interrupted enrolment is invisible in that view,
  /// and a client cannot recover from a state it cannot see.
  Future<IdentityAccessResult<TotpFactorInventory>> listTotpFactorInventory();

  /// Removes a factor through the caller's own session.
  ///
  /// Only ever called for a factor the caller has just re-read from the
  /// inventory and found unverified. No `service_role`, no admin API: a user
  /// clearing their own abandoned setup needs neither.
  Future<IdentityAccessResult<void>> unenrollTotpFactor({
    required String factorId,
  });

  Future<IdentityAccessResult<TotpChallenge>> challengeTotp({
    required String factorId,
  });

  Future<IdentityAccessResult<AuthenticatedSession>> verifyTotp({
    required TotpChallenge challenge,
    required String code,
  });

  Future<IdentityAccessResult<void>> signOut();
}
