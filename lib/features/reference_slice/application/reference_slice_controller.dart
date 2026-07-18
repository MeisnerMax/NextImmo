import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/identity_access_repository.dart';
import '../../identity_access/application/entitlement_invalidation_source.dart';
import '../../portfolio_property/application/property_query_invalidation_source.dart';
import '../../portfolio_property/application/property_repository.dart';
import '../../portfolio_property/domain/property_dto.dart';

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
  sendingEmail,
  emailSent,
  loadingFactors,
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
    this.properties = const <PropertyDto>[],
    this.nextCursor,
    this.selectedProperty,
    this.failureKind,
    this.versionConflict,
    this.message,
    this.authMessage,
    this.totpFactors = const <TotpFactor>[],
    this.totpEnrollment,
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
  final List<PropertyDto> properties;
  final String? nextCursor;
  final PropertyDto? selectedProperty;
  final PropertyRepositoryFailureKind? failureKind;
  final PropertyVersionConflict? versionConflict;
  final String? message;
  final String? authMessage;
  final List<TotpFactor> totpFactors;
  final TotpEnrollment? totpEnrollment;

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
    List<PropertyDto>? properties,
    Object? nextCursor = _unchanged,
    Object? selectedProperty = _unchanged,
    Object? failureKind = _unchanged,
    Object? versionConflict = _unchanged,
    Object? message = _unchanged,
    Object? authMessage = _unchanged,
    List<TotpFactor>? totpFactors,
    Object? totpEnrollment = _unchanged,
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

  Future<void> requestPasswordlessSignIn(String email) async {
    if (state.authPhase != ReferenceAuthPhase.unauthenticated ||
        _identityActionBusy) {
      return;
    }
    final generation = ++_identityActionGeneration;
    state = state.copyWith(
      authActionPhase: ReferenceAuthActionPhase.sendingEmail,
      authMessage: null,
      totpFactors: const <TotpFactor>[],
      totpEnrollment: null,
    );
    final result = await _identityRepository.requestPasswordlessSignIn(
      email: email,
    );
    if (generation != _identityActionGeneration ||
        state.authPhase != ReferenceAuthPhase.unauthenticated) {
      return;
    }
    switch (result) {
      case IdentityAccessSuccess<void>():
        state = state.copyWith(
          authActionPhase: ReferenceAuthActionPhase.emailSent,
          authMessage:
              'If the account exists, a passwordless sign-in link was sent.',
        );
      case IdentityAccessFailure<void>():
        state = state.copyWith(
          authActionPhase: ReferenceAuthActionPhase.failed,
          authMessage: result.message,
        );
    }
  }

  Future<void> beginTotpEnrollment() async {
    if (state.authPhase != ReferenceAuthPhase.authenticated ||
        _identityActionBusy) {
      return;
    }
    final generation = ++_identityActionGeneration;
    state = state.copyWith(
      authActionPhase: ReferenceAuthActionPhase.enrolling,
      authMessage: null,
      totpEnrollment: null,
    );
    final result = await _identityRepository.enrollTotp();
    if (generation != _identityActionGeneration ||
        state.authPhase != ReferenceAuthPhase.authenticated) {
      return;
    }
    switch (result) {
      case IdentityAccessSuccess<TotpEnrollment>():
        state = state.copyWith(
          authActionPhase: ReferenceAuthActionPhase.enrollmentReady,
          authMessage:
              'Add the setup key to an authenticator, then enter its code.',
          totpEnrollment: result.value,
        );
      case IdentityAccessFailure<TotpEnrollment>():
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
      ReferenceAuthActionPhase.sendingEmail ||
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
        properties: const <PropertyDto>[],
        nextCursor: null,
        selectedProperty: null,
        failureKind: PropertyRepositoryFailureKind.forbidden,
        versionConflict: null,
        message: 'Workspace access is not available.',
      );
      return;
    }
    await _stopPropertyInvalidations();
    final generation = ++_scopeGeneration;
    _retryCommand = null;
    state = state.copyWith(
      workspacePhase: WorkspacePhase.selected,
      selectedWorkspaceId: workspaceId,
      propertyListPhase: PropertyListPhase.loading,
      propertyDetailPhase: PropertyDetailPhase.idle,
      mutationPhase: PropertyMutationPhase.idle,
      properties: const <PropertyDto>[],
      nextCursor: null,
      selectedProperty: null,
      failureKind: null,
      versionConflict: null,
      message: null,
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
      properties: const <PropertyDto>[],
      nextCursor: null,
      failureKind: null,
      message: null,
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
    state = state.copyWith(
      propertyListPhase: PropertyListPhase.loading,
      failureKind: null,
      message: null,
    );
    final result = await _propertyRepository.list(
      PropertyListQuery(
        workspaceId: access.workspace.id,
        page: PropertyPageRequest(cursor: cursor),
      ),
    );
    if (generation != _scopeGeneration ||
        state.selectedWorkspaceId != access.workspace.id) {
      return;
    }
    switch (result) {
      case PropertyRepositorySuccess<PropertyPageResult>():
        final byId = <String, PropertyDto>{
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
        _applyListFailure(result);
    }
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

  Future<void> updateSelectedProperty(
    PropertyUpdateDto changes, {
    String? reason,
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
        expectedVersion: property.version,
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
    if (session.requiresMfaChallenge) {
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
      await _loadTotpFactors(userId, identityGeneration);
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

  Future<void> _loadTotpFactors(String userId, int generation) async {
    final result = await _identityRepository.listTotpFactors();
    if (generation != _identityActionGeneration ||
        state.authPhase != ReferenceAuthPhase.mfaRequired ||
        state.userId != userId) {
      return;
    }
    switch (result) {
      case IdentityAccessSuccess<List<TotpFactor>>():
        state = state.copyWith(
          authActionPhase:
              result.value.isEmpty
                  ? ReferenceAuthActionPhase.failed
                  : ReferenceAuthActionPhase.idle,
          authMessage:
              result.value.isEmpty
                  ? 'No verified authenticator is available.'
                  : null,
          totpFactors: result.value,
          totpEnrollment: null,
        );
      case IdentityAccessFailure<List<TotpFactor>>():
        state = state.copyWith(
          authActionPhase: ReferenceAuthActionPhase.failed,
          authMessage: result.message,
          totpFactors: const <TotpFactor>[],
          totpEnrollment: null,
        );
    }
  }

  Future<void> _loadWorkspaces(
    String userId, {
    String? preserveWorkspaceId,
  }) async {
    await _stopPropertyInvalidations();
    final generation = ++_scopeGeneration;
    state = state.copyWith(
      workspacePhase: WorkspacePhase.loading,
      propertyListPhase: PropertyListPhase.idle,
      propertyDetailPhase: PropertyDetailPhase.idle,
      mutationPhase: PropertyMutationPhase.idle,
      workspaces: const <WorkspaceAccess>[],
      selectedWorkspaceId: null,
      properties: const <PropertyDto>[],
      nextCursor: null,
      selectedProperty: null,
      failureKind: null,
      versionConflict: null,
      message: null,
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
      PropertyListQuery(workspaceId: access.workspace.id),
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
      properties: const <PropertyDto>[],
      nextCursor: null,
      failureKind: failure.kind,
      message: failure.message,
    );
  }

  void _setPropertyForbidden() {
    state = state.copyWith(
      propertyListPhase: PropertyListPhase.forbidden,
      properties: const <PropertyDto>[],
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
          onError: (_, __) {},
        );
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
    _entitlementPreservedWorkspaceId ??= state.selectedWorkspaceId;
    _clearWorkspaceCachesForRevalidation();
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
      properties: const <PropertyDto>[],
      nextCursor: null,
      selectedProperty: null,
      failureKind: null,
      versionConflict: null,
      message: null,
    );
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
        await _loadWorkspaces(
          userId,
          preserveWorkspaceId: _entitlementPreservedWorkspaceId,
        );
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
      PropertyListQuery(workspaceId: workspaceId),
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
        properties: const <PropertyDto>[],
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
        state = state.copyWith(
          propertyDetailPhase: PropertyDetailPhase.ready,
          selectedProperty: detailResult.value,
          properties: _replaceProperty(state.properties, detailResult.value),
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
        state = state.copyWith(
          propertyDetailPhase: PropertyDetailPhase.ready,
          mutationPhase: PropertyMutationPhase.succeeded,
          selectedProperty: result.value,
          properties: _replaceProperty(state.properties, result.value),
        );
      case PropertyRepositoryFailure<PropertyDto>():
        if (result.kind == PropertyRepositoryFailureKind.versionConflict) {
          final conflict = result.versionConflict!;
          _scopeGeneration++;
          _detailGeneration++;
          _retryCommand = null;
          state = state.copyWith(
            propertyDetailPhase: PropertyDetailPhase.ready,
            mutationPhase: PropertyMutationPhase.conflict,
            selectedProperty: conflict.currentProperty,
            properties: _replaceProperty(
              state.properties,
              conflict.currentProperty,
            ),
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

List<PropertyDto> _replaceProperty(
  List<PropertyDto> properties,
  PropertyDto replacement,
) {
  var replaced = false;
  final result = properties
      .map((property) {
        if (property.id != replacement.id) {
          return property;
        }
        replaced = true;
        return replacement;
      })
      .toList(growable: true);
  if (!replaced) {
    result.add(replacement);
  }
  return List<PropertyDto>.unmodifiable(result);
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

  final List<PropertyDto> items;
  final String? nextCursor;
}

_MergedPropertyPage _mergeRefreshedFirstPage({
  required List<PropertyDto> current,
  required String? currentNextCursor,
  required List<PropertyDto> refreshed,
  required String? refreshedNextCursor,
}) {
  final currentById = <String, PropertyDto>{
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
      items: List<PropertyDto>.unmodifiable(refreshedItems),
      nextCursor: null,
    );
  }
  final refreshedIds = refreshedItems.map((property) => property.id).toSet();
  final tail = current.where(
    (property) =>
        property.id.compareTo(refreshedNextCursor) > 0 &&
        !refreshedIds.contains(property.id),
  );
  final items = List<PropertyDto>.unmodifiable(<PropertyDto>[
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
