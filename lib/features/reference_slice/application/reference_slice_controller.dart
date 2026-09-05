import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/identity_access_repository.dart';
import '../../identity_access/application/entitlement_invalidation_source.dart';
import '../../portfolio_property/application/property_query_invalidation_source.dart';
import '../../portfolio_property/application/property_repository.dart';
import '../../portfolio_property/domain/property_dto.dart';
import '../../portfolio_property/domain/property_overview_dto.dart';

const _unchanged = Object();

enum ReferenceAuthPhase {
  loading,
  unauthenticated,
  mfaRequired,
  authenticated,
  error,
}

enum ReferenceAuthActionPhase {
  idle,
  signingIn,
  loadingFactors,

  /// The session is below aal2 and the account has no verified factor yet, so
  /// there is nothing to challenge -- the user has to enrol one first. Distinct
  /// from [failed]: nothing went wrong, this is the expected state for an
  /// administratively created account on its first sign-in.
  enrollmentRequired,

  /// An earlier enrolment was started but never verified, so the account holds
  /// an unverified factor and no verified one. Neither a challenge nor a fresh
  /// enrolment works from here -- the first has nothing to challenge, the
  /// second collides with the abandoned factor -- so the user is offered a
  /// choice between resuming and restarting.
  interruptedEnrollmentRecovery,
  enrolling,
  enrollmentReady,
  verifying,
  signingOut,
  failed,
}

enum WorkspacePhase { idle, loading, empty, selectionRequired, selected, error }

enum PropertyListPhase { idle, loading, empty, ready, forbidden, error }

enum PropertyDetailPhase { idle, loading, ready, notFound, forbidden, error }

enum PropertyMutationPhase {
  idle,
  submitting,
  retrying,
  succeeded,
  conflict,
  forbidden,
  failed,
}

class ReferenceSliceState {
  const ReferenceSliceState({
    required this.authPhase,
    this.authActionPhase = ReferenceAuthActionPhase.idle,
    this.assuranceLevel = AuthenticationAssuranceLevel.unknown,
    required this.workspacePhase,
    required this.propertyListPhase,
    required this.propertyDetailPhase,
    required this.mutationPhase,
    this.userId,
    this.workspaces = const <WorkspaceAccess>[],
    this.selectedWorkspaceId,
    this.properties = const <PropertySummaryDto>[],
    this.nextCursor,
    this.selectedProperty,
    this.failureKind,
    this.versionConflict,
    this.message,
    this.authMessage,
    this.totpFactors = const <TotpFactor>[],
    this.totpEnrollment,
    this.recoveryFactor,
    this.liveUpdatesDegraded = false,
    this.includeArchived = false,
    this.propertySearchTerm = '',
    this.loadMoreFailureMessage,
    this.validationField,
  });

  const ReferenceSliceState.loading()
    : this(
        authPhase: ReferenceAuthPhase.loading,
        workspacePhase: WorkspacePhase.idle,
        propertyListPhase: PropertyListPhase.idle,
        propertyDetailPhase: PropertyDetailPhase.idle,
        mutationPhase: PropertyMutationPhase.idle,
      );

  final ReferenceAuthPhase authPhase;
  final ReferenceAuthActionPhase authActionPhase;
  final AuthenticationAssuranceLevel assuranceLevel;
  final WorkspacePhase workspacePhase;
  final PropertyListPhase propertyListPhase;
  final PropertyDetailPhase propertyDetailPhase;
  final PropertyMutationPhase mutationPhase;
  final String? userId;
  final List<WorkspaceAccess> workspaces;
  final String? selectedWorkspaceId;
  final List<PropertySummaryDto> properties;
  final String? nextCursor;
  final PropertyDto? selectedProperty;
  final PropertyRepositoryFailureKind? failureKind;
  final PropertyVersionConflict? versionConflict;
  final String? message;
  final String? authMessage;
  final List<TotpFactor> totpFactors;
  final TotpEnrollment? totpEnrollment;

  /// The unverified factor an interrupted enrolment left on the account, while
  /// the user is being offered to resume or restart it. Held only so the two
  /// recovery actions know which factor they are about, and never shown: the
  /// UI renders the situation, not the id. Null outside recovery.
  final TotpFactor? recoveryFactor;

  /// The Realtime subscription for the selected workspace is not delivering.
  ///
  /// Deliberately non-fatal: the repository stays canonical, so every
  /// authorized surface keeps working — only the *live* part is degraded, and
  /// the UI may say so instead of presenting a stale list as current. Cleared
  /// as soon as a subscription reports ready again.
  final bool liveUpdatesDegraded;

  /// Whether the property list query surfaces tombstoned (archived) rows.
  /// Reset on every workspace switch so a new scope always starts from the
  /// active view.
  final bool includeArchived;

  /// The free-text filter the server applies over name, address, zip and city
  /// (`PROPERTY-LOOKUP-01`). Empty means no text filter. It is a *server*
  /// filter: the result is the workspace's matches, never a filter over the
  /// pages that happen to be loaded. Reset on every workspace switch.
  final String propertySearchTerm;

  /// Whether a text filter is in effect, which the list needs in order to tell
  /// "no property matches this search" from "this workspace has no
  /// properties" — two empty lists with different next actions.
  bool get hasPropertySearch => propertySearchTerm.isNotEmpty;

  /// A failed *additional* page load. Unlike a first-page failure this keeps
  /// the already loaded pages visible ([propertyListPhase] stays `ready`) and
  /// only the load-more affordance reports the error. Forbidden stays the
  /// exception: revoked read access clears the list fail-closed instead.
  final String? loadMoreFailureMessage;

  /// The contract field a server-side validation failure named, when it named
  /// one. Lets a form point at the rejected input instead of only reporting at
  /// form level; null unless the last mutation failed validation.
  final String? validationField;

  WorkspaceAccess? get selectedWorkspace {
    final selectedId = selectedWorkspaceId;
    if (selectedId == null) {
      return null;
    }
    for (final access in workspaces) {
      if (access.workspace.id == selectedId) {
        return access;
      }
    }
    return null;
  }

  ReferenceSliceState copyWith({
    ReferenceAuthPhase? authPhase,
    ReferenceAuthActionPhase? authActionPhase,
    AuthenticationAssuranceLevel? assuranceLevel,
    WorkspacePhase? workspacePhase,
    PropertyListPhase? propertyListPhase,
    PropertyDetailPhase? propertyDetailPhase,
    PropertyMutationPhase? mutationPhase,
    Object? userId = _unchanged,
    List<WorkspaceAccess>? workspaces,
    Object? selectedWorkspaceId = _unchanged,
    List<PropertySummaryDto>? properties,
    Object? nextCursor = _unchanged,
    Object? selectedProperty = _unchanged,
    Object? failureKind = _unchanged,
    Object? versionConflict = _unchanged,
    Object? message = _unchanged,
    Object? authMessage = _unchanged,
    List<TotpFactor>? totpFactors,
    Object? totpEnrollment = _unchanged,
    Object? recoveryFactor = _unchanged,
    bool? liveUpdatesDegraded,
    bool? includeArchived,
    String? propertySearchTerm,
    Object? loadMoreFailureMessage = _unchanged,
    Object? validationField = _unchanged,
  }) {
    return ReferenceSliceState(
      authPhase: authPhase ?? this.authPhase,
      authActionPhase: authActionPhase ?? this.authActionPhase,
      assuranceLevel: assuranceLevel ?? this.assuranceLevel,
      workspacePhase: workspacePhase ?? this.workspacePhase,
      propertyListPhase: propertyListPhase ?? this.propertyListPhase,
      propertyDetailPhase: propertyDetailPhase ?? this.propertyDetailPhase,
      mutationPhase: mutationPhase ?? this.mutationPhase,
      userId: identical(userId, _unchanged) ? this.userId : userId as String?,
      workspaces: workspaces ?? this.workspaces,
      selectedWorkspaceId:
          identical(selectedWorkspaceId, _unchanged)
              ? this.selectedWorkspaceId
              : selectedWorkspaceId as String?,
      properties: properties ?? this.properties,
      nextCursor:
          identical(nextCursor, _unchanged)
              ? this.nextCursor
              : nextCursor as String?,
      selectedProperty:
          identical(selectedProperty, _unchanged)
              ? this.selectedProperty
              : selectedProperty as PropertyDto?,
      failureKind:
          identical(failureKind, _unchanged)
              ? this.failureKind
              : failureKind as PropertyRepositoryFailureKind?,
      versionConflict:
          identical(versionConflict, _unchanged)
              ? this.versionConflict
              : versionConflict as PropertyVersionConflict?,
      message:
          identical(message, _unchanged) ? this.message : message as String?,
      authMessage:
          identical(authMessage, _unchanged)
              ? this.authMessage
              : authMessage as String?,
      totpFactors: totpFactors ?? this.totpFactors,
      totpEnrollment:
          identical(totpEnrollment, _unchanged)
              ? this.totpEnrollment
              : totpEnrollment as TotpEnrollment?,
      recoveryFactor:
          identical(recoveryFactor, _unchanged)
              ? this.recoveryFactor
              : recoveryFactor as TotpFactor?,
      liveUpdatesDegraded: liveUpdatesDegraded ?? this.liveUpdatesDegraded,
      includeArchived: includeArchived ?? this.includeArchived,
      propertySearchTerm: propertySearchTerm ?? this.propertySearchTerm,
      loadMoreFailureMessage:
          identical(loadMoreFailureMessage, _unchanged)
              ? this.loadMoreFailureMessage
              : loadMoreFailureMessage as String?,
      validationField:
          identical(validationField, _unchanged)
              ? this.validationField
              : validationField as String?,
    );
  }
}

typedef ReferenceIdFactory = String Function();

class ReferenceSliceController extends StateNotifier<ReferenceSliceState> {
  ReferenceSliceController({
    required IdentityAccessRepository identityRepository,
    required PropertyRepository propertyRepository,
    PropertyQueryInvalidationSource? propertyInvalidationSource,
    EntitlementInvalidationSource? entitlementInvalidationSource,
    Duration entitlementRevalidationInterval = const Duration(minutes: 1),
    ReferenceIdFactory? idFactory,
  }) : _identityRepository = identityRepository,
       _propertyRepository = propertyRepository,
       _propertyInvalidationSource = propertyInvalidationSource,
       _entitlementInvalidationSource = entitlementInvalidationSource,
       _entitlementRevalidationInterval = entitlementRevalidationInterval,
       _idFactory = idFactory ?? const Uuid().v4,
       assert(entitlementRevalidationInterval > Duration.zero),
       super(const ReferenceSliceState.loading());

  static const propertyReadPermission = 'property.read';
  static const propertyCreatePermission = 'property.create';
  static const propertyUpdatePermission = 'property.update';

  final IdentityAccessRepository _identityRepository;
  final PropertyRepository _propertyRepository;
  final PropertyQueryInvalidationSource? _propertyInvalidationSource;
  final EntitlementInvalidationSource? _entitlementInvalidationSource;
  final Duration _entitlementRevalidationInterval;
  final ReferenceIdFactory _idFactory;

  StreamSubscription<AuthenticatedSession?>? _sessionSubscription;
  StreamSubscription<PropertyQueryInvalidation>? _propertySubscription;
  StreamSubscription<EntitlementInvalidation>? _entitlementSubscription;
  Timer? _entitlementRevalidationTimer;
  PropertyUpdateCommand? _retryCommand;

  /// Mutation/correlation ids per creation attempt, so a resubmit of the same
  /// attempt reaches the server's idempotency instead of creating a duplicate.
  /// Cleared on scope changes together with the rest of the workspace state.
  final Map<String, ({String mutationId, String correlationId})>
  _createAttempts = <String, ({String mutationId, String correlationId})>{};
  String? _handledSessionKey;
  int _scopeGeneration = 0;
  int _detailGeneration = 0;
  int _mutationGeneration = 0;
  int _identityActionGeneration = 0;
  int _propertySubscriptionGeneration = 0;
  int _entitlementSubscriptionGeneration = 0;
  final Map<int, _InvalidationRefreshRequest> _pendingInvalidationRefreshes =
      <int, _InvalidationRefreshRequest>{};
  final Set<int> _runningInvalidationRefreshes = <int>{};
  bool _started = false;
  bool _entitlementRevalidationPending = false;
  bool _entitlementRevalidationRunning = false;
  bool _entitlementRevalidationDestructive = false;
  String? _entitlementPreservedWorkspaceId;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _sessionSubscription = _identityRepository.watchSession().listen(
      (session) => unawaited(_handleSession(session)),
      onError: (_, __) => _setAuthenticationError(),
    );
    await _handleSession(_identityRepository.currentSession, force: true);
  }

  /// Primary sign-in. On success the session watcher drives the phase onwards:
  /// to `mfaRequired` when a second factor is still owed, or to `authenticated`
  /// once the session already carries `aal2`.
  Future<void> signInWithPassword(String email, String password) async {
    if (state.authPhase != ReferenceAuthPhase.unauthenticated ||
        _identityActionBusy) {
      return;
    }
    final generation = ++_identityActionGeneration;
    state = state.copyWith(
      authActionPhase: ReferenceAuthActionPhase.signingIn,
      authMessage: null,
      totpFactors: const <TotpFactor>[],
      totpEnrollment: null,
      recoveryFactor: null,
    );
    final result = await _identityRepository.signInWithPassword(
      email: email,
      password: password,
    );
    if (generation != _identityActionGeneration) {
      return;
    }
    switch (result) {
      case IdentityAccessSuccess<void>():
        // No success message: the phase change is the feedback, and the
        // password is never echoed back in any form.
        state = state.copyWith(authActionPhase: ReferenceAuthActionPhase.idle);
      case IdentityAccessFailure<void>():
        if (state.authPhase != ReferenceAuthPhase.unauthenticated) {
          return;
        }
        state = state.copyWith(
          authActionPhase: ReferenceAuthActionPhase.failed,
          authMessage: result.message,
        );
    }
  }

  // SECURITY-AAL-CLIENT-03. GoTrue keeps an enrolled-but-unverified factor
  // when a setup is abandoned before its first code is accepted. Such an
  // account is neither factorless (a fresh enrolment under the same name is
  // refused) nor challengeable (there is no verified factor). The two methods
  // below are the only ways out, and the controller offers them only when the
  // inventory shows exactly that shape: see [_applyInventory].

  /// Recovery option A: finish the interrupted enrolment with the factor that
  /// is already on the account, for a user who still has it in their
  /// authenticator app. Nothing is deleted.
  ///
  /// The inventory is re-read first. A code is sent only if the factor the
  /// user was shown is still the one the account holds -- still the lone
  /// unverified factor, or verified in the meantime, which the same challenge
  /// completes just as well. Anything else means the picture changed
  /// underneath, and the state is recomputed from what was actually found.
  Future<void> resumeTotpEnrollment({required String code}) async {
    final target = state.recoveryFactor;
    if (state.authPhase != ReferenceAuthPhase.mfaRequired ||
        target == null ||
        _identityActionBusy) {
      return;
    }
    final generation = ++_identityActionGeneration;
    state = state.copyWith(
      authActionPhase: ReferenceAuthActionPhase.verifying,
      authMessage: null,
    );
    final inventory = await _reloadInventory(generation);
    if (inventory == null) {
      return;
    }
    final current = inventory.findById(target.id);
    final stillResumable =
        current != null &&
        !inventory.isAmbiguous &&
        (current.isVerified ||
            inventory.interruptedEnrollment?.id == target.id);
    if (!stillResumable) {
      _applyInventory(inventory);
      return;
    }
    await _challengeAndVerify(
      factorId: target.id,
      code: code,
      generation: generation,
    );
  }

  /// Recovery option B: the user no longer has the original secret, so the
  /// abandoned factor is replaced.
  ///
  /// The removal is the one destructive call on the whole MFA surface and is
  /// guarded accordingly. It targets exactly the factor the user was shown,
  /// only after a fresh read confirms that factor is still there, still
  /// unverified and still the only story the inventory tells; a factor that
  /// got verified, vanished or gained a verified sibling in the meantime is
  /// left alone and the state recomputed instead. The enrolment that follows
  /// waits for a second read to confirm the old factor is gone, because
  /// enrolling on top of it is exactly the collision this recovers from.
  Future<void> restartTotpEnrollment() async {
    final target = state.recoveryFactor;
    if (state.authPhase != ReferenceAuthPhase.mfaRequired ||
        target == null ||
        _identityActionBusy) {
      return;
    }
    final generation = ++_identityActionGeneration;
    state = state.copyWith(
      authActionPhase: ReferenceAuthActionPhase.enrolling,
      authMessage: null,
      totpEnrollment: null,
    );
    final before = await _reloadInventory(generation);
    if (before == null) {
      return;
    }
    final current = before.findById(target.id);
    if (current == null ||
        !current.isUnverified ||
        before.isAmbiguous ||
        before.interruptedEnrollment?.id != target.id) {
      _applyInventory(before);
      return;
    }
    final removal = await _identityRepository.unenrollTotpFactor(
      factorId: current.id,
    );
    if (generation != _identityActionGeneration ||
        state.authPhase != ReferenceAuthPhase.mfaRequired) {
      return;
    }
    // Whatever the removal reported, the account is re-read before anything
    // else happens: a refused removal is no reason to trust the old picture
    // either (the factor may be gone already, or verified after all), and a
    // confirmed removal still has to show in the listing before an enrolment
    // may follow.
    final after = await _reloadInventory(generation);
    if (after == null) {
      return;
    }
    if (after.findById(target.id) != null) {
      state = state.copyWith(
        authActionPhase: ReferenceAuthActionPhase.failed,
        authMessage:
            'The previous authenticator setup could not be removed. '
            'Try again in a moment.',
      );
      return;
    }
    if (removal is IdentityAccessFailure<void> || !after.isEmpty) {
      // Either the removal was refused and the factor is simply gone, or it
      // worked but the account is not bare: a verified factor or another
      // leftover appeared meanwhile. Neither is something to enrol blindly
      // over; the state is recomputed and the user chooses again.
      _applyInventory(after);
      return;
    }
    await _enroll(generation, from: ReferenceAuthPhase.mfaRequired);
  }

  Future<void> beginTotpEnrollment() async {
    // Reachable from mfaRequired, which is the only state a factorless account
    // can be in, and still from authenticated so an elevated user can add a
    // further factor. Enrolling from mfaRequired is what lets an
    // administratively created user complete their first factor at all --
    // public signup stays off, so nobody arrives here with one already.
    if ((state.authPhase != ReferenceAuthPhase.authenticated &&
            state.authPhase != ReferenceAuthPhase.mfaRequired) ||
        _identityActionBusy) {
      return;
    }
    // Below aal2 a plain enrolment is only for an account the inventory has
    // positively shown to be bare. A verified factor wants a challenge, an
    // interrupted one has its own two actions -- enrolling over it is exactly
    // the call that collides -- and a state the client could not determine
    // (ambiguous inventory, failed read) is not a licence to try anyway.
    if (state.authPhase == ReferenceAuthPhase.mfaRequired &&
        state.authActionPhase != ReferenceAuthActionPhase.enrollmentRequired) {
      return;
    }
    final enrollmentPhase = state.authPhase;
    final generation = ++_identityActionGeneration;
    state = state.copyWith(
      authActionPhase: ReferenceAuthActionPhase.enrolling,
      authMessage: null,
      totpEnrollment: null,
    );
    await _enroll(generation, from: enrollmentPhase);
  }

  Future<void> _enroll(
    int generation, {
    required ReferenceAuthPhase from,
  }) async {
    final result = await _identityRepository.enrollTotp();
    if (generation != _identityActionGeneration || state.authPhase != from) {
      return;
    }
    switch (result) {
      case IdentityAccessSuccess<TotpEnrollment>():
        state = state.copyWith(
          authActionPhase: ReferenceAuthActionPhase.enrollmentReady,
          authMessage:
              'Add the setup key to an authenticator, then enter its code.',
          totpEnrollment: result.value,
          recoveryFactor: null,
        );
      case IdentityAccessFailure<TotpEnrollment>():
        // A name conflict or a full factor list is the server describing the
        // account, not an outage. Below aal2 the inventory is re-read and the
        // state re-derived from it: an abandoned factor becomes recovery, a
        // verified one the ordinary challenge, and anything else fails closed.
        // Never a retry, never a renamed second attempt, never a deletion.
        if (from == ReferenceAuthPhase.mfaRequired &&
            (result.kind == IdentityAccessFailureKind.factorNameConflict ||
                result.kind == IdentityAccessFailureKind.tooManyFactors)) {
          final inventory = await _reloadInventory(
            generation,
            failureMessage: result.message,
          );
          if (inventory != null) {
            _applyInventory(inventory, rejection: result.message);
          }
          return;
        }
        state = state.copyWith(
          authActionPhase: ReferenceAuthActionPhase.failed,
          authMessage: result.message,
          totpEnrollment: null,
        );
    }
  }

  Future<void> verifyTotp({
    required String factorId,
    required String code,
  }) async {
    final knownFactor =
        state.totpEnrollment?.factorId == factorId ||
        state.totpFactors.any((factor) => factor.id == factorId);
    if (!knownFactor || _identityActionBusy) {
      return;
    }
    final generation = ++_identityActionGeneration;
    state = state.copyWith(
      authActionPhase: ReferenceAuthActionPhase.verifying,
      authMessage: null,
    );
    await _challengeAndVerify(
      factorId: factorId,
      code: code,
      generation: generation,
    );
  }

  Future<void> _challengeAndVerify({
    required String factorId,
    required String code,
    required int generation,
  }) async {
    final challengeResult = await _identityRepository.challengeTotp(
      factorId: factorId,
    );
    if (generation != _identityActionGeneration) {
      return;
    }
    if (challengeResult case IdentityAccessFailure<TotpChallenge>()) {
      state = state.copyWith(
        authActionPhase: ReferenceAuthActionPhase.failed,
        authMessage: challengeResult.message,
      );
      return;
    }
    final challenge =
        (challengeResult as IdentityAccessSuccess<TotpChallenge>).value;
    final verification = await _identityRepository.verifyTotp(
      challenge: challenge,
      code: code,
    );
    if (generation != _identityActionGeneration) {
      return;
    }
    switch (verification) {
      case IdentityAccessSuccess<AuthenticatedSession>():
        // Rebuilds the state from the elevated session, which also drops the
        // enrolment secret and any recovery target.
        await _handleSession(verification.value, force: true);
      case IdentityAccessFailure<AuthenticatedSession>():
        state = state.copyWith(
          authActionPhase: ReferenceAuthActionPhase.failed,
          authMessage: verification.message,
        );
    }
  }

  Future<void> signOut() async {
    if (state.authPhase == ReferenceAuthPhase.unauthenticated ||
        _identityActionBusy) {
      return;
    }
    final generation = ++_identityActionGeneration;
    state = state.copyWith(
      authActionPhase: ReferenceAuthActionPhase.signingOut,
      authMessage: null,
    );
    final result = await _identityRepository.signOut();
    if (generation != _identityActionGeneration) {
      return;
    }
    switch (result) {
      case IdentityAccessSuccess<void>():
        await _handleSession(null, force: true);
      case IdentityAccessFailure<void>():
        state = state.copyWith(
          authActionPhase: ReferenceAuthActionPhase.failed,
          authMessage: result.message,
        );
    }
  }

  bool get _identityActionBusy {
    return switch (state.authActionPhase) {
      ReferenceAuthActionPhase.signingIn ||
      ReferenceAuthActionPhase.loadingFactors ||
      ReferenceAuthActionPhase.enrolling ||
      ReferenceAuthActionPhase.verifying ||
      ReferenceAuthActionPhase.signingOut => true,
      _ => false,
    };
  }

  Future<void> refreshWorkspaces() async {
    final userId = state.userId;
    if (state.authPhase != ReferenceAuthPhase.authenticated || userId == null) {
      return;
    }
    await _loadWorkspaces(
      userId,
      preserveWorkspaceId: state.selectedWorkspaceId,
    );
  }

  Future<void> selectWorkspace(String workspaceId) async {
    final access = _findWorkspace(workspaceId);
    if (access == null) {
      _scopeGeneration++;
      await _stopPropertyInvalidations();
      _retryCommand = null;
      state = state.copyWith(
        workspacePhase:
            state.workspaces.isEmpty
                ? WorkspacePhase.empty
                : WorkspacePhase.selectionRequired,
        propertyListPhase: PropertyListPhase.forbidden,
        propertyDetailPhase: PropertyDetailPhase.idle,
        mutationPhase: PropertyMutationPhase.idle,
        selectedWorkspaceId: null,
        properties: const <PropertySummaryDto>[],
        nextCursor: null,
        selectedProperty: null,
        failureKind: PropertyRepositoryFailureKind.forbidden,
        versionConflict: null,
        message: 'Workspace access is not available.',
        includeArchived: false,
        propertySearchTerm: '',
        loadMoreFailureMessage: null,
      );
      return;
    }
    await _stopPropertyInvalidations();
    final generation = ++_scopeGeneration;
    _retryCommand = null;
    _createAttempts.clear();
    state = state.copyWith(
      workspacePhase: WorkspacePhase.selected,
      selectedWorkspaceId: workspaceId,
      propertyListPhase: PropertyListPhase.loading,
      propertyDetailPhase: PropertyDetailPhase.idle,
      mutationPhase: PropertyMutationPhase.idle,
      properties: const <PropertySummaryDto>[],
      nextCursor: null,
      selectedProperty: null,
      failureKind: null,
      versionConflict: null,
      message: null,
      includeArchived: false,
      propertySearchTerm: '',
      loadMoreFailureMessage: null,
    );
    await _loadFirstPropertyPage(access, generation);
    if (generation == _scopeGeneration &&
        state.selectedWorkspaceId == access.workspace.id) {
      _startPropertyInvalidations(access);
    }
  }

  Future<void> reloadProperties() async {
    final access = state.selectedWorkspace;
    if (access == null) {
      return;
    }
    final generation = ++_scopeGeneration;
    state = state.copyWith(
      propertyListPhase: PropertyListPhase.loading,
      properties: const <PropertySummaryDto>[],
      nextCursor: null,
      failureKind: null,
      message: null,
      loadMoreFailureMessage: null,
    );
    await _loadFirstPropertyPage(access, generation);
  }

  /// Reads the server-authoritative overview of [propertyId]
  /// (PROPERTY-OVERVIEW-DATA-01).
  ///
  /// Side-effect free like [loadPropertyPage]: the overview is a projection
  /// the surface owns, not controller state, so a failed or slow read never
  /// disturbs the property context around it. Permission scoping happens
  /// server-side per section; the client neither aggregates nor guesses.
  Future<PropertyRepositoryResult<PropertyOverviewDto>> loadPropertyOverview(
    String propertyId,
  ) async {
    final access = state.selectedWorkspace;
    if (access == null || !access.allows(propertyReadPermission)) {
      return const PropertyRepositoryFailure<PropertyOverviewDto>(
        kind: PropertyRepositoryFailureKind.forbidden,
        message: 'Property access is not permitted.',
      );
    }
    return _propertyRepository.overview(
      workspaceId: access.workspace.id,
      propertyId: propertyId,
    );
  }

  /// Reads one keyset page for a browse-and-search surface (the property
  /// switcher).
  ///
  /// Deliberately side-effect free: it changes no controller state, so the
  /// list the user came from keeps its pages, cursor, filter and selection
  /// while another property is looked up. [searchTerm] is the switcher's own
  /// search and never touches the list's. Archived properties stay out — a
  /// switcher offers working contexts, and the archive view is the list's own
  /// filter.
  Future<PropertyRepositoryResult<PropertyPageResult>> loadPropertyPage({
    String? cursor,
    String? searchTerm,
  }) async {
    final access = state.selectedWorkspace;
    if (access == null || !access.allows(propertyReadPermission)) {
      return const PropertyRepositoryFailure<PropertyPageResult>(
        kind: PropertyRepositoryFailureKind.forbidden,
        message: 'Property access is not permitted.',
      );
    }
    return _propertyRepository.list(
      PropertyListQuery(
        workspaceId: access.workspace.id,
        page: PropertyPageRequest(cursor: cursor),
        searchTerm: searchTerm,
      ),
    );
  }

  /// Switches the single contract-backed list filter. A change restarts the
  /// keyset from the first page — a cursor from the other filter view is not
  /// a valid position in this one.
  Future<void> setIncludeArchived(bool value) async {
    final access = state.selectedWorkspace;
    if (access == null || state.includeArchived == value) {
      return;
    }
    final generation = ++_scopeGeneration;
    state = state.copyWith(
      includeArchived: value,
      propertyListPhase: PropertyListPhase.loading,
      properties: const <PropertySummaryDto>[],
      nextCursor: null,
      failureKind: null,
      message: null,
      loadMoreFailureMessage: null,
    );
    await _loadFirstPropertyPage(access, generation);
  }

  /// Applies the workspace-wide text search (`PROPERTY-LOOKUP-01`).
  ///
  /// Like the archive filter, a change restarts the keyset from the first
  /// page: a cursor taken from a different result set is not a valid position
  /// in this one. Normalized here rather than at the call site so a trailing
  /// space or a double space never counts as a new search and never spends a
  /// round trip.
  Future<void> setPropertySearch(String term) async {
    final access = state.selectedWorkspace;
    final normalized = term.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (access == null || state.propertySearchTerm == normalized) {
      return;
    }
    final generation = ++_scopeGeneration;
    state = state.copyWith(
      propertySearchTerm: normalized,
      propertyListPhase: PropertyListPhase.loading,
      properties: const <PropertySummaryDto>[],
      nextCursor: null,
      failureKind: null,
      message: null,
      loadMoreFailureMessage: null,
    );
    await _loadFirstPropertyPage(access, generation);
  }

  Future<void> loadNextPropertyPage() async {
    final access = state.selectedWorkspace;
    final cursor = state.nextCursor;
    if (access == null || cursor == null) {
      return;
    }
    if (!access.allows(propertyReadPermission)) {
      _setPropertyForbidden();
      return;
    }
    final generation = _scopeGeneration;
    final includeArchived = state.includeArchived;
    final searchTerm = state.propertySearchTerm;
    state = state.copyWith(
      propertyListPhase: PropertyListPhase.loading,
      failureKind: null,
      message: null,
      loadMoreFailureMessage: null,
    );
    final result = await _propertyRepository.list(
      PropertyListQuery(
        workspaceId: access.workspace.id,
        page: PropertyPageRequest(cursor: cursor),
        includeArchived: includeArchived,
        // The next page has to come from the same result set the cursor was
        // taken from, so the filter travels with it.
        searchTerm: searchTerm,
      ),
    );
    if (generation != _scopeGeneration ||
        state.selectedWorkspaceId != access.workspace.id) {
      return;
    }
    switch (result) {
      case PropertyRepositorySuccess<PropertyPageResult>():
        final byId = <String, PropertySummaryDto>{
          for (final property in state.properties) property.id: property,
          for (final property in result.value.items) property.id: property,
        };
        state = state.copyWith(
          propertyListPhase:
              byId.isEmpty ? PropertyListPhase.empty : PropertyListPhase.ready,
          properties: byId.values.toList(growable: false),
          nextCursor: result.value.nextCursor,
        );
      case PropertyRepositoryFailure<PropertyPageResult>():
        if (result.kind == PropertyRepositoryFailureKind.forbidden ||
            state.properties.isEmpty) {
          _applyListFailure(result);
          return;
        }
        // A later page failing is no reason to blank the pages the user
        // already has: the list stays ready and only the load-more affordance
        // carries the error.
        state = state.copyWith(
          propertyListPhase: PropertyListPhase.ready,
          loadMoreFailureMessage: result.message,
        );
    }
  }

  /// Leaves the property context: detail, mutation and conflict state are
  /// cleared and any in-flight detail read is invalidated. The list scope
  /// (pages, cursor, filter) stays untouched so the caller can restore the
  /// exact list the property was opened from.
  void closeSelectedProperty() {
    _detailGeneration++;
    _mutationGeneration++;
    _retryCommand = null;
    state = state.copyWith(
      propertyDetailPhase: PropertyDetailPhase.idle,
      mutationPhase: PropertyMutationPhase.idle,
      selectedProperty: null,
      failureKind: null,
      versionConflict: null,
      message: null,
    );
  }

  Future<void> openProperty(String propertyId) async {
    final access = state.selectedWorkspace;
    if (access == null || !access.allows(propertyReadPermission)) {
      state = state.copyWith(
        propertyDetailPhase: PropertyDetailPhase.forbidden,
        selectedProperty: null,
        failureKind: PropertyRepositoryFailureKind.forbidden,
        message: 'Property access is not permitted.',
      );
      return;
    }
    final generation = ++_detailGeneration;
    state = state.copyWith(
      propertyDetailPhase: PropertyDetailPhase.loading,
      mutationPhase: PropertyMutationPhase.idle,
      selectedProperty: null,
      failureKind: null,
      versionConflict: null,
      message: null,
    );
    final result = await _propertyRepository.getById(
      workspaceId: access.workspace.id,
      propertyId: propertyId,
    );
    if (generation != _detailGeneration ||
        state.selectedWorkspaceId != access.workspace.id) {
      return;
    }
    switch (result) {
      case PropertyRepositorySuccess<PropertyDto>():
        state = state.copyWith(
          propertyDetailPhase: PropertyDetailPhase.ready,
          selectedProperty: result.value,
        );
      case PropertyRepositoryFailure<PropertyDto>():
        final phase = switch (result.kind) {
          PropertyRepositoryFailureKind.notFound =>
            PropertyDetailPhase.notFound,
          PropertyRepositoryFailureKind.forbidden =>
            PropertyDetailPhase.forbidden,
          _ => PropertyDetailPhase.error,
        };
        state = state.copyWith(
          propertyDetailPhase: phase,
          selectedProperty: null,
          failureKind: result.kind,
          message: result.message,
        );
    }
  }

  /// Opens a new property (PROPERTY-DATA-02) and makes it the selected one.
  ///
  /// The created record is canonical: the server returns it, so no local
  /// shadow row is invented. On success the property context is ready for the
  /// new draft and the list carries it without a second read; every failure
  /// leaves the current selection untouched so the caller can keep the form
  /// open with the user input intact.
  ///
  /// [attemptId] makes the server-side idempotency reachable from the UI. A
  /// resubmit of the *same* draft after a lost or failed response must reuse
  /// the previous attempt id, so `create_property` replays the property it
  /// already committed instead of opening a second one. Callers that mean a
  /// genuinely new property pass a new id (or none).
  Future<void> createProperty(
    PropertyCreateDto draft, {
    String? reason,
    String? attemptId,
  }) async {
    final access = state.selectedWorkspace;
    final userId = state.userId;
    if (access == null ||
        userId == null ||
        state.assuranceLevel != AuthenticationAssuranceLevel.aal2 ||
        !access.allows(propertyCreatePermission)) {
      state = state.copyWith(
        mutationPhase: PropertyMutationPhase.forbidden,
        failureKind: PropertyRepositoryFailureKind.forbidden,
        versionConflict: null,
        message: 'Creating properties is not permitted.',
      );
      return;
    }

    final generation = ++_mutationGeneration;
    final workspaceId = access.workspace.id;
    state = state.copyWith(
      mutationPhase: PropertyMutationPhase.submitting,
      failureKind: null,
      versionConflict: null,
      message: null,
      validationField: null,
    );

    // A retry of the same attempt must carry the same mutation id, or the
    // server's replay branch can never fire and a lost response would open a
    // second property. Ids are minted once per attempt and remembered; a
    // caller without an attempt id cannot retry, so nothing is remembered for
    // it and no id is spent on bookkeeping.
    final ids =
        attemptId == null
            ? (mutationId: _idFactory(), correlationId: _idFactory())
            : _createAttempts.putIfAbsent(
              attemptId,
              () => (mutationId: _idFactory(), correlationId: _idFactory()),
            );

    final result = await _propertyRepository.create(
      PropertyCreateCommand(
        context: PropertyCreateContext(
          workspaceId: workspaceId,
          actorId: userId,
          mutationId: ids.mutationId,
          correlationId: ids.correlationId,
          reason: reason,
        ),
        draft: draft,
      ),
    );
    if (generation != _mutationGeneration ||
        workspaceId != state.selectedWorkspaceId ||
        userId != state.userId) {
      return;
    }

    switch (result) {
      case PropertyRepositorySuccess<PropertyDto>():
        final created = result.value;
        // The new row belongs at its keyset position (`id ASC`), so it is
        // inserted in order rather than appended: the list stays a faithful
        // view of the contract ordering without a full reload.
        // A list that never loaded (error, forbidden, idle) is not a list the
        // new row may join: showing it as the single entry would present an
        // unloaded workspace as a complete one. The property is still selected
        // and the workspace opens on it; the list keeps its own state and its
        // retry.
        final listLoaded = switch (state.propertyListPhase) {
          PropertyListPhase.error ||
          PropertyListPhase.forbidden ||
          PropertyListPhase.idle => false,
          _ => true,
        };
        final summaries = List<PropertySummaryDto>.of(state.properties)
          ..removeWhere((property) => property.id == created.id);
        final insertAt = summaries.indexWhere(
          (property) => property.id.compareTo(created.id) > 0,
        );
        final summary = PropertySummaryDto.fromProperty(created);
        // A draft is only listed here when the loaded page range still covers
        // its position: appending past the last loaded page would claim a row
        // the user has not paged to yet.
        final withinLoadedRange =
            listLoaded && (insertAt >= 0 || state.nextCursor == null);
        if (withinLoadedRange) {
          summaries.insert(
            insertAt >= 0 ? insertAt : summaries.length,
            summary,
          );
        }
        _detailGeneration++;
        // The attempt landed: its ids must not be replayed by a later,
        // genuinely new creation.
        if (attemptId != null) {
          _createAttempts.remove(attemptId);
        }
        state = state.copyWith(
          properties: List<PropertySummaryDto>.unmodifiable(summaries),
          // A creation says nothing about whether the *list* loaded. A list
          // parked in error or forbidden keeps that phase -- claiming `ready`
          // would present a never-loaded workspace as complete and swallow the
          // retry. Only a genuinely loaded list moves, and it only becomes
          // `empty` when no further page exists.
          propertyListPhase: switch (state.propertyListPhase) {
            PropertyListPhase.error ||
            PropertyListPhase.forbidden ||
            PropertyListPhase.idle => state.propertyListPhase,
            _ =>
              summaries.isEmpty && state.nextCursor == null
                  ? PropertyListPhase.empty
                  : PropertyListPhase.ready,
          },
          propertyDetailPhase: PropertyDetailPhase.ready,
          selectedProperty: created,
          mutationPhase: PropertyMutationPhase.succeeded,
        );
      case PropertyRepositoryFailure<PropertyDto>():
        state = state.copyWith(
          mutationPhase:
              result.kind == PropertyRepositoryFailureKind.forbidden
                  ? PropertyMutationPhase.forbidden
                  : PropertyMutationPhase.failed,
          failureKind: result.kind,
          versionConflict: null,
          message: result.message,
          validationField: result.field,
        );
    }
  }

  /// Archives the selected property (DEBT-012 tombstone) or restores it.
  ///
  /// Deliberately not a status dropdown: archiving is a named, confirmed
  /// action that rides the existing audited `update` contract with the full
  /// record, so optimistic version, idempotency and the canonical readback all
  /// behave exactly as for a field edit.
  Future<void> setSelectedPropertyArchived({
    required bool archived,
    String? reason,
  }) async {
    final property = state.selectedProperty;
    if (property == null) {
      return;
    }
    final target = archived ? PropertyStatus.archived : PropertyStatus.active;
    if (property.status == target) {
      return;
    }
    await updateSelectedProperty(
      PropertyUpdateDto(
        name: property.name,
        addressLine1: property.addressLine1,
        addressLine2: property.addressLine2,
        zip: property.zip,
        city: property.city,
        country: property.country,
        propertyType: property.propertyType,
        units: property.units,
        sqft: property.sqft,
        yearBuilt: property.yearBuilt,
        notes: property.notes,
        status: target,
      ),
      reason: reason,
      expectedVersion: property.version,
    );
  }

  /// [expectedVersion] is the version the caller's edits are based on — the
  /// detail form passes the version it seeded its fields from. When a remote
  /// change has moved the property past that version in the meantime, the
  /// server answers with a version conflict instead of silently overwriting
  /// the concurrent edit. Falls back to the current canonical version when
  /// not provided.
  Future<void> updateSelectedProperty(
    PropertyUpdateDto changes, {
    String? reason,
    int? expectedVersion,
  }) async {
    final access = state.selectedWorkspace;
    final property = state.selectedProperty;
    final userId = state.userId;
    if (access == null ||
        property == null ||
        userId == null ||
        state.assuranceLevel != AuthenticationAssuranceLevel.aal2 ||
        !access.allows(propertyUpdatePermission)) {
      _retryCommand = null;
      state = state.copyWith(
        mutationPhase: PropertyMutationPhase.forbidden,
        failureKind: PropertyRepositoryFailureKind.forbidden,
        versionConflict: null,
        message: 'Property updates are not permitted.',
      );
      return;
    }
    final command = PropertyUpdateCommand(
      propertyId: property.id,
      context: CommandContext(
        workspaceId: access.workspace.id,
        actorId: userId,
        mutationId: _idFactory(),
        expectedVersion: expectedVersion ?? property.version,
        correlationId: _idFactory(),
        reason: reason,
      ),
      changes: changes,
    );
    _retryCommand = command;
    await _submitUpdate(command, retry: false);
  }

  Future<void> retryUpdate() async {
    final command = _retryCommand;
    if (command == null ||
        (state.failureKind !=
                PropertyRepositoryFailureKind.infrastructureFailure &&
            state.failureKind !=
                PropertyRepositoryFailureKind.mutationInProgress)) {
      return;
    }
    await _submitUpdate(command, retry: true);
  }

  Future<void> _handleSession(
    AuthenticatedSession? session, {
    bool force = false,
  }) async {
    final sessionKey =
        session == null
            ? null
            : '${session.userId}:${session.currentAssuranceLevel.name}:'
                '${session.nextAssuranceLevel.name}';
    if (!force && sessionKey == _handledSessionKey) {
      return;
    }
    _handledSessionKey = sessionKey;
    _scopeGeneration++;
    _detailGeneration++;
    _mutationGeneration++;
    final identityGeneration = ++_identityActionGeneration;
    await _stopEntitlementInvalidations();
    await _stopPropertyInvalidations();
    _retryCommand = null;
    if (session == null) {
      state = const ReferenceSliceState(
        authPhase: ReferenceAuthPhase.unauthenticated,
        workspacePhase: WorkspacePhase.idle,
        propertyListPhase: PropertyListPhase.idle,
        propertyDetailPhase: PropertyDetailPhase.idle,
        mutationPhase: PropertyMutationPhase.idle,
      );
      return;
    }
    final userId = session.userId;
    // The business-load barrier. Anything below aal2 is an authentication
    // state, never a workspace state -- including a session whose next level is
    // also aal1, which is what an administratively created account looks like
    // before it enrols its first factor. Routing that to `authenticated` would
    // load a workspace the server is bound to answer empty, and the user would
    // be told they have no access when they simply have no second factor yet.
    if (!session.isAal2) {
      state = ReferenceSliceState(
        authPhase: ReferenceAuthPhase.mfaRequired,
        authActionPhase: ReferenceAuthActionPhase.loadingFactors,
        assuranceLevel: session.currentAssuranceLevel,
        workspacePhase: WorkspacePhase.idle,
        propertyListPhase: PropertyListPhase.idle,
        propertyDetailPhase: PropertyDetailPhase.idle,
        mutationPhase: PropertyMutationPhase.idle,
        userId: userId,
      );
      await _loadTotpFactors(identityGeneration);
      return;
    }
    state = ReferenceSliceState(
      authPhase: ReferenceAuthPhase.authenticated,
      assuranceLevel: session.currentAssuranceLevel,
      workspacePhase: WorkspacePhase.loading,
      propertyListPhase: PropertyListPhase.idle,
      propertyDetailPhase: PropertyDetailPhase.idle,
      mutationPhase: PropertyMutationPhase.idle,
      userId: userId,
    );
    await _loadWorkspaces(userId);
    if (state.authPhase == ReferenceAuthPhase.authenticated &&
        state.userId == userId) {
      _startEntitlementInvalidations(userId);
    }
  }

  Future<void> _loadTotpFactors(int generation) async {
    final inventory = await _reloadInventory(generation);
    if (inventory != null) {
      _applyInventory(inventory);
    }
  }

  /// Reads the factor inventory for the current mfaRequired session. Returns
  /// it when the caller is still the current identity action and the session
  /// is unchanged; otherwise the state has been set (fail closed on a read
  /// failure) or superseded, and null tells the caller to stop.
  ///
  /// A read failure keeps [ReferenceSliceState.recoveryFactor], so the user
  /// can retry the action once the service answers again. What it never does
  /// is let a stale inventory stand in for a fresh one.
  Future<TotpFactorInventory?> _reloadInventory(
    int generation, {
    String? failureMessage,
  }) async {
    final userId = state.userId;
    final result = await _identityRepository.listTotpFactorInventory();
    if (generation != _identityActionGeneration ||
        state.authPhase != ReferenceAuthPhase.mfaRequired ||
        state.userId != userId) {
      return null;
    }
    switch (result) {
      case IdentityAccessSuccess<TotpFactorInventory>():
        return result.value;
      case IdentityAccessFailure<TotpFactorInventory>():
        state = state.copyWith(
          authActionPhase: ReferenceAuthActionPhase.failed,
          authMessage: failureMessage ?? result.message,
          totpFactors: const <TotpFactor>[],
          totpEnrollment: null,
        );
        return null;
    }
  }

  /// Derives the mfaRequired sub-state from a freshly read inventory. This is
  /// the only place that chooses between challenge, enrolment, recovery and
  /// fail-closed, so the initial load, a rejected enrolment and a recovery
  /// action that found the world changed all land on the same decision:
  ///
  /// - a verified factor exists: the ordinary challenge, whatever else is on
  ///   the account. A stale unverified sibling is left where it is -- the
  ///   point is reaching aal2 safely, not tidying the factor list;
  /// - the inventory is ambiguous (a status the SDK could not map, or more
  ///   than one abandoned factor under this app's name): fail closed;
  /// - exactly one abandoned factor under this app's name: recovery;
  /// - nothing at all: enrolment -- unless the server has just refused one
  ///   ([rejection]), in which case the account is not bare whatever the
  ///   listing says, and offering the same enrolment again would only loop.
  void _applyInventory(TotpFactorInventory inventory, {String? rejection}) {
    final challengeable = inventory.challengeable;
    if (challengeable.isNotEmpty) {
      state = state.copyWith(
        authActionPhase: ReferenceAuthActionPhase.idle,
        authMessage: rejection,
        totpFactors: challengeable,
        totpEnrollment: null,
        recoveryFactor: null,
      );
      return;
    }
    if (inventory.isAmbiguous) {
      state = state.copyWith(
        authActionPhase: ReferenceAuthActionPhase.failed,
        authMessage:
            rejection ??
            'The authenticator setup on this account could not be '
                'determined. Sign out and try again, or contact an '
                'administrator.',
        totpFactors: const <TotpFactor>[],
        totpEnrollment: null,
        recoveryFactor: null,
      );
      return;
    }
    final interrupted = inventory.interruptedEnrollment;
    if (interrupted != null) {
      state = state.copyWith(
        authActionPhase: ReferenceAuthActionPhase.interruptedEnrollmentRecovery,
        authMessage: rejection,
        totpFactors: const <TotpFactor>[],
        totpEnrollment: null,
        recoveryFactor: interrupted,
      );
      return;
    }
    if (rejection != null) {
      state = state.copyWith(
        authActionPhase: ReferenceAuthActionPhase.failed,
        authMessage: rejection,
        totpFactors: const <TotpFactor>[],
        totpEnrollment: null,
        recoveryFactor: null,
      );
      return;
    }
    state = state.copyWith(
      authActionPhase: ReferenceAuthActionPhase.enrollmentRequired,
      authMessage:
          'NexImmo requires an authenticator before workspace data can be '
          'accessed.',
      totpFactors: const <TotpFactor>[],
      totpEnrollment: null,
      recoveryFactor: null,
    );
  }

  Future<void> _loadWorkspaces(
    String userId, {
    String? preserveWorkspaceId,
  }) async {
    await _stopPropertyInvalidations();
    final generation = ++_scopeGeneration;
    _createAttempts.clear();
    state = state.copyWith(
      workspacePhase: WorkspacePhase.loading,
      propertyListPhase: PropertyListPhase.idle,
      propertyDetailPhase: PropertyDetailPhase.idle,
      mutationPhase: PropertyMutationPhase.idle,
      workspaces: const <WorkspaceAccess>[],
      selectedWorkspaceId: null,
      properties: const <PropertySummaryDto>[],
      nextCursor: null,
      selectedProperty: null,
      failureKind: null,
      versionConflict: null,
      message: null,
      includeArchived: false,
      propertySearchTerm: '',
      loadMoreFailureMessage: null,
    );
    final result = await _identityRepository.listWorkspaceAccesses(
      userId: userId,
    );
    if (generation != _scopeGeneration || state.userId != userId) {
      return;
    }
    switch (result) {
      case IdentityAccessSuccess<List<WorkspaceAccess>>():
        final accesses = result.value;
        if (accesses.isEmpty) {
          state = state.copyWith(workspacePhase: WorkspacePhase.empty);
          return;
        }
        state = state.copyWith(
          workspacePhase: WorkspacePhase.selectionRequired,
          workspaces: accesses,
        );
        final preserved =
            preserveWorkspaceId == null
                ? null
                : _findWorkspace(preserveWorkspaceId);
        if (preserved != null) {
          await selectWorkspace(preserved.workspace.id);
        } else if (accesses.length == 1) {
          await selectWorkspace(accesses.single.workspace.id);
        }
      case IdentityAccessFailure<List<WorkspaceAccess>>():
        if (result.kind == IdentityAccessFailureKind.unauthenticated) {
          await _handleSession(null, force: true);
          return;
        }
        state = state.copyWith(
          workspacePhase: WorkspacePhase.error,
          message: result.message,
        );
    }
  }

  Future<void> _loadFirstPropertyPage(
    WorkspaceAccess access,
    int generation,
  ) async {
    if (!access.allows(propertyReadPermission)) {
      if (generation == _scopeGeneration) {
        _setPropertyForbidden();
      }
      return;
    }
    final result = await _propertyRepository.list(
      PropertyListQuery(
        workspaceId: access.workspace.id,
        includeArchived: state.includeArchived,
        searchTerm: state.propertySearchTerm,
      ),
    );
    if (generation != _scopeGeneration ||
        state.selectedWorkspaceId != access.workspace.id) {
      return;
    }
    switch (result) {
      case PropertyRepositorySuccess<PropertyPageResult>():
        state = state.copyWith(
          propertyListPhase:
              result.value.items.isEmpty
                  ? PropertyListPhase.empty
                  : PropertyListPhase.ready,
          properties: result.value.items,
          nextCursor: result.value.nextCursor,
        );
      case PropertyRepositoryFailure<PropertyPageResult>():
        _applyListFailure(result);
    }
  }

  void _applyListFailure(
    PropertyRepositoryFailure<PropertyPageResult> failure,
  ) {
    state = state.copyWith(
      propertyListPhase:
          failure.kind == PropertyRepositoryFailureKind.forbidden
              ? PropertyListPhase.forbidden
              : PropertyListPhase.error,
      properties: const <PropertySummaryDto>[],
      nextCursor: null,
      failureKind: failure.kind,
      message: failure.message,
      loadMoreFailureMessage: null,
    );
  }

  void _setPropertyForbidden() {
    state = state.copyWith(
      propertyListPhase: PropertyListPhase.forbidden,
      properties: const <PropertySummaryDto>[],
      nextCursor: null,
      failureKind: PropertyRepositoryFailureKind.forbidden,
      message: 'Property access is not permitted.',
    );
  }

  void _startPropertyInvalidations(WorkspaceAccess access) {
    final source = _propertyInvalidationSource;
    if (source == null || !access.allows(propertyReadPermission)) {
      return;
    }
    final subscriptionGeneration = ++_propertySubscriptionGeneration;
    _propertySubscription = source
        .watchWorkspace(workspaceId: access.workspace.id)
        .listen(
          (invalidation) => _queuePropertyInvalidation(
            invalidation,
            subscriptionGeneration: subscriptionGeneration,
          ),
          // A dead subscription is not nothing: without a marker the list just
          // stops updating and looks like a quiet workspace. Non-fatal by
          // design -- the repository stays canonical and every authorized
          // surface keeps working -- so this only records that live updates
          // are degraded and leaves the business state untouched.
          onError:
              (_, __) => _markLiveUpdates(
                degraded: true,
                subscriptionGeneration: subscriptionGeneration,
              ),
        );
  }

  void _markLiveUpdates({
    required bool degraded,
    required int subscriptionGeneration,
  }) {
    if (subscriptionGeneration != _propertySubscriptionGeneration ||
        state.liveUpdatesDegraded == degraded) {
      return;
    }
    state = state.copyWith(liveUpdatesDegraded: degraded);
  }

  Future<void> _stopPropertyInvalidations() async {
    _propertySubscriptionGeneration++;
    _pendingInvalidationRefreshes.clear();
    final subscription = _propertySubscription;
    _propertySubscription = null;
    if (subscription == null) {
      return;
    }
    try {
      await subscription.cancel();
    } catch (_) {
      // REST-backed state remains usable when Realtime cleanup fails.
    }
  }

  void _startEntitlementInvalidations(String userId) {
    final source = _entitlementInvalidationSource;
    if (source == null) {
      return;
    }
    final subscriptionGeneration = ++_entitlementSubscriptionGeneration;
    _entitlementSubscription = source
        .watchUser(userId: userId)
        .listen(
          (invalidation) => _queueEntitlementRevalidation(
            invalidation,
            subscriptionGeneration: subscriptionGeneration,
          ),
          onError:
              (_, __) => _queueEntitlementRevalidation(
                EntitlementInvalidation.reconcile(userId: userId),
                subscriptionGeneration: subscriptionGeneration,
              ),
        );
    _entitlementRevalidationTimer = Timer.periodic(
      _entitlementRevalidationInterval,
      (_) => _queueEntitlementRevalidation(
        EntitlementInvalidation.reconcile(userId: userId),
        subscriptionGeneration: subscriptionGeneration,
      ),
    );
  }

  Future<void> _stopEntitlementInvalidations() async {
    _entitlementSubscriptionGeneration++;
    _entitlementRevalidationPending = false;
    _entitlementRevalidationDestructive = false;
    _entitlementPreservedWorkspaceId = null;
    _entitlementRevalidationTimer?.cancel();
    _entitlementRevalidationTimer = null;
    final subscription = _entitlementSubscription;
    _entitlementSubscription = null;
    if (subscription == null) {
      return;
    }
    try {
      await subscription.cancel();
    } catch (_) {
      // Periodic REST revalidation remains the fail-closed fallback.
    }
  }

  void _queueEntitlementRevalidation(
    EntitlementInvalidation invalidation, {
    required int subscriptionGeneration,
  }) {
    if (subscriptionGeneration != _entitlementSubscriptionGeneration ||
        state.authPhase != ReferenceAuthPhase.authenticated ||
        state.userId != invalidation.userId) {
      return;
    }
    _entitlementRevalidationPending = true;
    if (!invalidation.isReconciliation) {
      // A targeted entitlement signal says this user's authorization changed:
      // the cached workspace state is suspect and is dropped before the
      // reload completes (fail closed). The periodic reconcile tick carries
      // no such evidence, so it revalidates without tearing down the state —
      // discarding it every interval also discards unsaved form input.
      _entitlementRevalidationDestructive = true;
      _entitlementPreservedWorkspaceId ??= state.selectedWorkspaceId;
      _clearWorkspaceCachesForRevalidation();
    }
    if (!_entitlementRevalidationRunning) {
      _entitlementRevalidationRunning = true;
      unawaited(
        _drainEntitlementRevalidations(
          invalidation.userId,
          subscriptionGeneration: subscriptionGeneration,
        ),
      );
    }
  }

  void _clearWorkspaceCachesForRevalidation() {
    _scopeGeneration++;
    _detailGeneration++;
    _mutationGeneration++;
    _retryCommand = null;
    unawaited(_stopPropertyInvalidations());
    state = state.copyWith(
      workspacePhase: WorkspacePhase.loading,
      propertyListPhase: PropertyListPhase.idle,
      propertyDetailPhase: PropertyDetailPhase.idle,
      mutationPhase: PropertyMutationPhase.idle,
      workspaces: const <WorkspaceAccess>[],
      selectedWorkspaceId: null,
      properties: const <PropertySummaryDto>[],
      nextCursor: null,
      selectedProperty: null,
      failureKind: null,
      versionConflict: null,
      message: null,
      includeArchived: false,
      propertySearchTerm: '',
      loadMoreFailureMessage: null,
    );
  }

  /// Periodic entitlement reconciliation. Unlike a targeted signal this
  /// carries no evidence that anything changed, so the currently authorized
  /// state keeps being served while the check runs. The result still applies
  /// fail closed: lost access clears the affected surfaces exactly like the
  /// destructive path, only a confirmed-unchanged authorization leaves the
  /// workspace, property list and detail (and with them any unsaved form
  /// input in the UI layer) untouched.
  Future<void> _revalidateWorkspacesQuietly(String userId) async {
    final generation = _scopeGeneration;
    final result = await _identityRepository.listWorkspaceAccesses(
      userId: userId,
    );
    if (generation != _scopeGeneration ||
        state.authPhase != ReferenceAuthPhase.authenticated ||
        state.userId != userId) {
      // Another flow (workspace switch, sign-out, targeted signal) took over
      // while the check was in flight; that flow owns the state now.
      return;
    }
    switch (result) {
      case IdentityAccessSuccess<List<WorkspaceAccess>>():
        final accesses = result.value;
        final selectedId = state.selectedWorkspaceId;
        WorkspaceAccess? selectedAccess;
        for (final access in accesses) {
          if (access.workspace.id == selectedId) {
            selectedAccess = access;
          }
        }
        if (selectedId == null || selectedAccess == null) {
          // The current selection did not survive the refresh; the standard
          // reload owns empty/selection handling and clears fail closed.
          await _loadWorkspaces(userId, preserveWorkspaceId: selectedId);
          return;
        }
        // Same workspace, still a member: swap in the refreshed authorization
        // so revoked capabilities (e.g. property.update) take effect, without
        // resetting the surfaces built on top of it.
        state = state.copyWith(workspaces: accesses);
        if (!selectedAccess.allows(propertyReadPermission)) {
          _scopeGeneration++;
          _detailGeneration++;
          _mutationGeneration++;
          _retryCommand = null;
          await _stopPropertyInvalidations();
          state = state.copyWith(
            propertyListPhase: PropertyListPhase.forbidden,
            propertyDetailPhase: PropertyDetailPhase.forbidden,
            mutationPhase: PropertyMutationPhase.idle,
            properties: const <PropertySummaryDto>[],
            nextCursor: null,
            selectedProperty: null,
            failureKind: PropertyRepositoryFailureKind.forbidden,
            versionConflict: null,
            message: 'Property access is not permitted.',
          );
        }
      case IdentityAccessFailure<List<WorkspaceAccess>>():
        if (result.kind == IdentityAccessFailureKind.unauthenticated) {
          await _handleSession(null, force: true);
          return;
        }
      // A transient reconcile failure is no evidence of revocation: the
      // next interval retries and the server-side guards stay
      // authoritative, so the last authorized state keeps being served
      // instead of being destroyed by a network hiccup.
    }
  }

  Future<void> _drainEntitlementRevalidations(
    String userId, {
    required int subscriptionGeneration,
  }) async {
    try {
      while (_entitlementRevalidationPending &&
          subscriptionGeneration == _entitlementSubscriptionGeneration &&
          state.authPhase == ReferenceAuthPhase.authenticated &&
          state.userId == userId) {
        _entitlementRevalidationPending = false;
        final destructive = _entitlementRevalidationDestructive;
        _entitlementRevalidationDestructive = false;
        if (destructive) {
          await _loadWorkspaces(
            userId,
            preserveWorkspaceId: _entitlementPreservedWorkspaceId,
          );
        } else {
          await _revalidateWorkspacesQuietly(userId);
        }
      }
    } finally {
      _entitlementRevalidationRunning = false;
      if (_entitlementRevalidationPending &&
          subscriptionGeneration == _entitlementSubscriptionGeneration) {
        _entitlementRevalidationRunning = true;
        unawaited(
          _drainEntitlementRevalidations(
            userId,
            subscriptionGeneration: subscriptionGeneration,
          ),
        );
      } else {
        _entitlementPreservedWorkspaceId = null;
      }
    }
  }

  void _queuePropertyInvalidation(
    PropertyQueryInvalidation invalidation, {
    required int subscriptionGeneration,
  }) {
    final access = state.selectedWorkspace;
    if (subscriptionGeneration != _propertySubscriptionGeneration ||
        access == null ||
        !access.allows(propertyReadPermission) ||
        invalidation.workspaceId != access.workspace.id) {
      return;
    }
    if (invalidation.isReconciliation) {
      // The subscription is delivering again (first join or rejoin), so the
      // degraded marker is stale; the readback queued below is the catch-up.
      _markLiveUpdates(
        degraded: false,
        subscriptionGeneration: subscriptionGeneration,
      );
    }
    final selectedPropertyId = state.selectedProperty?.id;
    final refreshDetail =
        selectedPropertyId != null &&
        (invalidation.isReconciliation ||
            invalidation.propertyId == selectedPropertyId);
    final pending = _pendingInvalidationRefreshes[subscriptionGeneration];
    _pendingInvalidationRefreshes[subscriptionGeneration] =
        _InvalidationRefreshRequest(
          workspaceId: access.workspace.id,
          refreshDetail: refreshDetail || (pending?.refreshDetail ?? false),
        );
    if (_runningInvalidationRefreshes.add(subscriptionGeneration)) {
      unawaited(_drainPropertyInvalidations(subscriptionGeneration));
    }
  }

  Future<void> _drainPropertyInvalidations(int subscriptionGeneration) async {
    try {
      while (true) {
        final request = _pendingInvalidationRefreshes.remove(
          subscriptionGeneration,
        );
        if (request == null) {
          return;
        }
        await _refreshPropertiesFromInvalidation(
          request,
          subscriptionGeneration: subscriptionGeneration,
        );
      }
    } finally {
      _runningInvalidationRefreshes.remove(subscriptionGeneration);
      if (_pendingInvalidationRefreshes.containsKey(subscriptionGeneration) &&
          subscriptionGeneration == _propertySubscriptionGeneration &&
          _runningInvalidationRefreshes.add(subscriptionGeneration)) {
        unawaited(_drainPropertyInvalidations(subscriptionGeneration));
      }
    }
  }

  Future<void> _refreshPropertiesFromInvalidation(
    _InvalidationRefreshRequest request, {
    required int subscriptionGeneration,
  }) async {
    final access = state.selectedWorkspace;
    if (subscriptionGeneration != _propertySubscriptionGeneration ||
        access == null ||
        !access.allows(propertyReadPermission) ||
        access.workspace.id != request.workspaceId) {
      return;
    }
    final workspaceId = request.workspaceId;
    final selectedPropertyId = state.selectedProperty?.id;
    final refreshDetail = request.refreshDetail && selectedPropertyId != null;
    final scopeGeneration = ++_scopeGeneration;
    final detailGeneration = refreshDetail ? ++_detailGeneration : null;
    final currentNextCursor = state.nextCursor;
    final listFuture = _propertyRepository.list(
      PropertyListQuery(
        workspaceId: workspaceId,
        includeArchived: state.includeArchived,
        searchTerm: state.propertySearchTerm,
      ),
    );
    final detailFuture =
        refreshDetail
            ? _propertyRepository.getById(
              workspaceId: workspaceId,
              propertyId: selectedPropertyId,
            )
            : null;

    final listResult = await listFuture;
    if (subscriptionGeneration != _propertySubscriptionGeneration ||
        scopeGeneration != _scopeGeneration ||
        state.selectedWorkspaceId != workspaceId) {
      return;
    }
    if (listResult case PropertyRepositorySuccess<PropertyPageResult>()) {
      final merged = _mergeRefreshedFirstPage(
        current: state.properties,
        currentNextCursor: currentNextCursor,
        refreshed: listResult.value.items,
        refreshedNextCursor: listResult.value.nextCursor,
      );
      state = state.copyWith(
        propertyListPhase:
            merged.items.isEmpty
                ? PropertyListPhase.empty
                : PropertyListPhase.ready,
        properties: merged.items,
        nextCursor: merged.nextCursor,
      );
    } else if (listResult case PropertyRepositoryFailure<PropertyPageResult>(
      kind: PropertyRepositoryFailureKind.forbidden,
    )) {
      state = state.copyWith(
        propertyListPhase: PropertyListPhase.forbidden,
        propertyDetailPhase: PropertyDetailPhase.forbidden,
        mutationPhase: PropertyMutationPhase.idle,
        properties: const <PropertySummaryDto>[],
        nextCursor: null,
        selectedProperty: null,
        failureKind: PropertyRepositoryFailureKind.forbidden,
        versionConflict: null,
        message: listResult.message,
      );
      return;
    }

    if (detailFuture == null || detailGeneration == null) {
      return;
    }
    final detailResult = await detailFuture;
    if (subscriptionGeneration != _propertySubscriptionGeneration ||
        detailGeneration != _detailGeneration ||
        state.selectedWorkspaceId != workspaceId ||
        state.selectedProperty?.id != selectedPropertyId) {
      return;
    }
    if (detailResult case PropertyRepositorySuccess<PropertyDto>()) {
      final current = state.selectedProperty;
      if (current == null || detailResult.value.version >= current.version) {
        final mergedProperties = _replaceProperty(
          state.properties,
          detailResult.value,
          keepArchived: state.includeArchived,
        );
        state = state.copyWith(
          propertyListPhase:
              mergedProperties.isEmpty && state.nextCursor == null
                  ? PropertyListPhase.empty
                  : state.propertyListPhase,
          propertyDetailPhase: PropertyDetailPhase.ready,
          selectedProperty: detailResult.value,
          properties: mergedProperties,
        );
      }
    }
  }

  Future<void> _submitUpdate(
    PropertyUpdateCommand command, {
    required bool retry,
  }) async {
    final generation = ++_mutationGeneration;
    final workspaceId = state.selectedWorkspaceId;
    state = state.copyWith(
      mutationPhase:
          retry
              ? PropertyMutationPhase.retrying
              : PropertyMutationPhase.submitting,
      failureKind: null,
      versionConflict: null,
      message: null,
    );
    final result = await _propertyRepository.update(command);
    if (generation != _mutationGeneration ||
        workspaceId != state.selectedWorkspaceId ||
        command.context.actorId != state.userId) {
      return;
    }
    switch (result) {
      case PropertyRepositorySuccess<PropertyDto>():
        _scopeGeneration++;
        _detailGeneration++;
        _retryCommand = null;
        final mergedProperties = _replaceProperty(
          state.properties,
          result.value,
          keepArchived: state.includeArchived,
        );
        state = state.copyWith(
          propertyListPhase:
              mergedProperties.isEmpty && state.nextCursor == null
                  ? PropertyListPhase.empty
                  : state.propertyListPhase,
          propertyDetailPhase: PropertyDetailPhase.ready,
          mutationPhase: PropertyMutationPhase.succeeded,
          selectedProperty: result.value,
          properties: mergedProperties,
        );
      case PropertyRepositoryFailure<PropertyDto>():
        if (result.kind == PropertyRepositoryFailureKind.versionConflict) {
          final conflict = result.versionConflict!;
          _scopeGeneration++;
          _detailGeneration++;
          _retryCommand = null;
          final mergedProperties = _replaceProperty(
            state.properties,
            conflict.currentProperty,
            keepArchived: state.includeArchived,
          );
          state = state.copyWith(
            propertyListPhase:
                mergedProperties.isEmpty && state.nextCursor == null
                    ? PropertyListPhase.empty
                    : state.propertyListPhase,
            propertyDetailPhase: PropertyDetailPhase.ready,
            mutationPhase: PropertyMutationPhase.conflict,
            selectedProperty: conflict.currentProperty,
            properties: mergedProperties,
            failureKind: result.kind,
            versionConflict: conflict,
            message: result.message,
          );
          return;
        }
        final retryable =
            result.kind ==
                PropertyRepositoryFailureKind.infrastructureFailure ||
            result.kind == PropertyRepositoryFailureKind.mutationInProgress;
        if (!retryable) {
          _retryCommand = null;
        }
        state = state.copyWith(
          mutationPhase:
              result.kind == PropertyRepositoryFailureKind.forbidden
                  ? PropertyMutationPhase.forbidden
                  : PropertyMutationPhase.failed,
          failureKind: result.kind,
          versionConflict: null,
          message: result.message,
        );
    }
  }

  WorkspaceAccess? _findWorkspace(String workspaceId) {
    for (final access in state.workspaces) {
      if (access.workspace.id == workspaceId) {
        return access;
      }
    }
    return null;
  }

  void _setAuthenticationError() {
    _scopeGeneration++;
    _detailGeneration++;
    _mutationGeneration++;
    unawaited(_stopPropertyInvalidations());
    unawaited(_stopEntitlementInvalidations());
    _retryCommand = null;
    state = const ReferenceSliceState(
      authPhase: ReferenceAuthPhase.error,
      workspacePhase: WorkspacePhase.idle,
      propertyListPhase: PropertyListPhase.idle,
      propertyDetailPhase: PropertyDetailPhase.idle,
      mutationPhase: PropertyMutationPhase.idle,
      message: 'Authentication state could not be loaded.',
    );
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription?.cancel());
    unawaited(_stopPropertyInvalidations());
    unawaited(_stopEntitlementInvalidations());
    super.dispose();
  }
}

List<PropertySummaryDto> _replaceProperty(
  List<PropertySummaryDto> properties,
  PropertyDto replacement, {
  required bool keepArchived,
}) {
  final index = properties.indexWhere(
    (property) => property.id == replacement.id,
  );
  if (index < 0) {
    return properties;
  }
  final current = properties[index];
  if (current.version > replacement.version) {
    return properties;
  }
  final result = List<PropertySummaryDto>.of(properties, growable: true);
  if (replacement.status == PropertyStatus.archived && !keepArchived) {
    // The active view excludes tombstoned rows server-side, so a row that got
    // archived leaves the list. The archive view (includeArchived) keeps it
    // and shows the refreshed summary instead.
    result.removeAt(index);
  } else {
    result[index] = PropertySummaryDto.fromProperty(replacement);
  }
  return List<PropertySummaryDto>.unmodifiable(result);
}

class _InvalidationRefreshRequest {
  const _InvalidationRefreshRequest({
    required this.workspaceId,
    required this.refreshDetail,
  });

  final String workspaceId;
  final bool refreshDetail;
}

class _MergedPropertyPage {
  const _MergedPropertyPage({required this.items, required this.nextCursor});

  final List<PropertySummaryDto> items;
  final String? nextCursor;
}

_MergedPropertyPage _mergeRefreshedFirstPage({
  required List<PropertySummaryDto> current,
  required String? currentNextCursor,
  required List<PropertySummaryDto> refreshed,
  required String? refreshedNextCursor,
}) {
  final currentById = <String, PropertySummaryDto>{
    for (final property in current) property.id: property,
  };
  final refreshedItems = refreshed
      .map((property) {
        final existing = currentById[property.id];
        return existing != null && existing.version > property.version
            ? existing
            : property;
      })
      .toList(growable: false);
  if (refreshedNextCursor == null) {
    return _MergedPropertyPage(
      items: List<PropertySummaryDto>.unmodifiable(refreshedItems),
      nextCursor: null,
    );
  }
  final refreshedIds = refreshedItems.map((property) => property.id).toSet();
  final tail = current.where(
    (property) =>
        property.id.compareTo(refreshedNextCursor) > 0 &&
        !refreshedIds.contains(property.id),
  );
  final items = List<PropertySummaryDto>.unmodifiable(<PropertySummaryDto>[
    ...refreshedItems,
    ...tail,
  ]);
  return _MergedPropertyPage(
    items: items,
    nextCursor:
        items.length > refreshedItems.length
            ? currentNextCursor
            : refreshedNextCursor,
  );
}

final identityAccessRepositoryProvider = Provider<IdentityAccessRepository>(
  (ref) => throw StateError('IdentityAccessRepository is not configured.'),
);

final referencePropertyRepositoryProvider = Provider<PropertyRepository>(
  (ref) => throw StateError('Reference PropertyRepository is not configured.'),
);

final propertyQueryInvalidationSourceProvider =
    Provider<PropertyQueryInvalidationSource?>((ref) => null);

final entitlementInvalidationSourceProvider =
    Provider<EntitlementInvalidationSource?>((ref) => null);

final referenceSliceControllerProvider = StateNotifierProvider.autoDispose<
  ReferenceSliceController,
  ReferenceSliceState
>((ref) {
  final controller = ReferenceSliceController(
    identityRepository: ref.watch(identityAccessRepositoryProvider),
    propertyRepository: ref.watch(referencePropertyRepositoryProvider),
    propertyInvalidationSource: ref.watch(
      propertyQueryInvalidationSourceProvider,
    ),
    entitlementInvalidationSource: ref.watch(
      entitlementInvalidationSourceProvider,
    ),
  );
  unawaited(controller.start());
  return controller;
});
