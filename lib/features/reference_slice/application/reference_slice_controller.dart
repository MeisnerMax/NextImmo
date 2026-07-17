import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/identity_access_repository.dart';
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
  }) {
    return ReferenceSliceState(
      authPhase: authPhase ?? this.authPhase,
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
    );
  }
}

typedef ReferenceIdFactory = String Function();

class ReferenceSliceController extends StateNotifier<ReferenceSliceState> {
  ReferenceSliceController({
    required IdentityAccessRepository identityRepository,
    required PropertyRepository propertyRepository,
    PropertyQueryInvalidationSource? propertyInvalidationSource,
    ReferenceIdFactory? idFactory,
  }) : _identityRepository = identityRepository,
       _propertyRepository = propertyRepository,
       _propertyInvalidationSource = propertyInvalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       super(const ReferenceSliceState.loading());

  static const propertyReadPermission = 'property.read';
  static const propertyUpdatePermission = 'property.update';

  final IdentityAccessRepository _identityRepository;
  final PropertyRepository _propertyRepository;
  final PropertyQueryInvalidationSource? _propertyInvalidationSource;
  final ReferenceIdFactory _idFactory;

  StreamSubscription<AuthenticatedSession?>? _sessionSubscription;
  StreamSubscription<PropertyQueryInvalidation>? _propertySubscription;
  PropertyUpdateCommand? _retryCommand;
  String? _handledSessionKey;
  int _scopeGeneration = 0;
  int _detailGeneration = 0;
  int _mutationGeneration = 0;
  int _propertySubscriptionGeneration = 0;
  bool _started = false;

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
        workspacePhase: WorkspacePhase.idle,
        propertyListPhase: PropertyListPhase.idle,
        propertyDetailPhase: PropertyDetailPhase.idle,
        mutationPhase: PropertyMutationPhase.idle,
        userId: userId,
      );
      return;
    }
    state = ReferenceSliceState(
      authPhase: ReferenceAuthPhase.authenticated,
      workspacePhase: WorkspacePhase.loading,
      propertyListPhase: PropertyListPhase.idle,
      propertyDetailPhase: PropertyDetailPhase.idle,
      mutationPhase: PropertyMutationPhase.idle,
      userId: userId,
    );
    await _loadWorkspaces(userId);
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
          (invalidation) => unawaited(
            _handlePropertyInvalidation(
              invalidation,
              subscriptionGeneration: subscriptionGeneration,
            ),
          ),
          onError: (_, __) {},
        );
  }

  Future<void> _stopPropertyInvalidations() async {
    _propertySubscriptionGeneration++;
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

  Future<void> _handlePropertyInvalidation(
    PropertyQueryInvalidation invalidation, {
    required int subscriptionGeneration,
  }) async {
    final access = state.selectedWorkspace;
    if (subscriptionGeneration != _propertySubscriptionGeneration ||
        access == null ||
        !access.allows(propertyReadPermission) ||
        invalidation.workspaceId != access.workspace.id) {
      return;
    }
    final workspaceId = access.workspace.id;
    final selectedPropertyId = state.selectedProperty?.id;
    final refreshDetail =
        selectedPropertyId != null &&
        (invalidation.isReconciliation ||
            invalidation.propertyId == selectedPropertyId);
    final scopeGeneration = ++_scopeGeneration;
    final detailGeneration = refreshDetail ? ++_detailGeneration : null;
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
      final items = _preferNewerProperties(
        current: state.properties,
        refreshed: listResult.value.items,
      );
      state = state.copyWith(
        propertyListPhase:
            items.isEmpty ? PropertyListPhase.empty : PropertyListPhase.ready,
        properties: items,
        nextCursor: listResult.value.nextCursor,
      );
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

List<PropertyDto> _preferNewerProperties({
  required List<PropertyDto> current,
  required List<PropertyDto> refreshed,
}) {
  final currentById = <String, PropertyDto>{
    for (final property in current) property.id: property,
  };
  return List<PropertyDto>.unmodifiable(
    refreshed.map((property) {
      final existing = currentById[property.id];
      return existing != null && existing.version > property.version
          ? existing
          : property;
    }),
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
  );
  unawaited(controller.start());
  return controller;
});
