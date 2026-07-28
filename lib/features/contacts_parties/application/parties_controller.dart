/// Screen-facing orchestration over the contacts_parties contract (P2-D02),
/// mirroring `MembersAdminController`: explicit phases per zone, a generation
/// guard against out-of-order responses, and every mandatory screen state of
/// `03_design_system.md` represented as data rather than as an ad hoc widget
/// branch.
///
/// Two deliberate choices:
///
/// * **`forbidden` comes from the server.** The local RBAC catalogue has no
///   `party.*` permission, so a client-side pre-check would invent policy.
///   Reads are attempted and `PartyRepositoryFailureKind.forbidden` (RLS
///   `party.read`) is mapped to the forbidden phase. The [AuthorizationPort] is
///   consulted only for the mutate affordance, where a pre-check saves a call
///   that is certain to fail.
/// * **Text search and sorting are client-side.** `PartyListQuery` has no text
///   predicate; the wave plan rules out new backend reads for this screen.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/authorization_port.dart';
import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/party_dto.dart';
import 'party_providers.dart';
import 'party_query_invalidation_source.dart';
import 'party_repository.dart';

const Object _unchanged = Object();

enum PartiesListPhase { idle, loading, ready, empty, forbidden, error }

enum PartiesDetailPhase { idle, loading, ready, forbidden, error }

enum PartiesActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,

  /// The bound backend cannot mutate yet (legacy SQLite adapters are read-only
  /// by design). Rendered as the mandatory "read-only until migrated" notice.
  readOnly,
  failed,
}

class PartiesState {
  const PartiesState({
    required this.listPhase,
    this.detailPhase = PartiesDetailPhase.idle,
    this.actionPhase = PartiesActionPhase.idle,
    this.parties = const <PartySummaryDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.roleFilter,
    this.selectedPartyId,
    this.selectedParty,
    this.roles = const <PartyRoleDto>[],
    this.contractorDetails,
    this.duplicates = const <PartyDuplicateCandidate>[],
    this.versionConflict,
    this.message,
    this.actionMessage,
  });

  const PartiesState.loading() : this(listPhase: PartiesListPhase.loading);

  final PartiesListPhase listPhase;
  final PartiesDetailPhase detailPhase;
  final PartiesActionPhase actionPhase;
  final List<PartySummaryDto> parties;
  final String? nextCursor;
  final bool loadingMore;
  final PartyRoleType? roleFilter;
  final String? selectedPartyId;
  final PartyDto? selectedParty;
  final List<PartyRoleDto> roles;
  final ContractorDetailsDto? contractorDetails;
  final List<PartyDuplicateCandidate> duplicates;
  final PartyVersionConflict? versionConflict;
  final String? message;
  final String? actionMessage;

  bool get hasMore => nextCursor != null;

  PartiesState copyWith({
    PartiesListPhase? listPhase,
    PartiesDetailPhase? detailPhase,
    PartiesActionPhase? actionPhase,
    List<PartySummaryDto>? parties,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    Object? roleFilter = _unchanged,
    Object? selectedPartyId = _unchanged,
    Object? selectedParty = _unchanged,
    List<PartyRoleDto>? roles,
    Object? contractorDetails = _unchanged,
    List<PartyDuplicateCandidate>? duplicates,
    Object? versionConflict = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
  }) {
    return PartiesState(
      listPhase: listPhase ?? this.listPhase,
      detailPhase: detailPhase ?? this.detailPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      parties: parties ?? this.parties,
      nextCursor:
          identical(nextCursor, _unchanged)
              ? this.nextCursor
              : nextCursor as String?,
      loadingMore: loadingMore ?? this.loadingMore,
      roleFilter:
          identical(roleFilter, _unchanged)
              ? this.roleFilter
              : roleFilter as PartyRoleType?,
      selectedPartyId:
          identical(selectedPartyId, _unchanged)
              ? this.selectedPartyId
              : selectedPartyId as String?,
      selectedParty:
          identical(selectedParty, _unchanged)
              ? this.selectedParty
              : selectedParty as PartyDto?,
      roles: roles ?? this.roles,
      contractorDetails:
          identical(contractorDetails, _unchanged)
              ? this.contractorDetails
              : contractorDetails as ContractorDetailsDto?,
      duplicates: duplicates ?? this.duplicates,
      versionConflict:
          identical(versionConflict, _unchanged)
              ? this.versionConflict
              : versionConflict as PartyVersionConflict?,
      message:
          identical(message, _unchanged) ? this.message : message as String?,
      actionMessage:
          identical(actionMessage, _unchanged)
              ? this.actionMessage
              : actionMessage as String?,
    );
  }
}

typedef PartiesIdFactory = String Function();

class PartiesController extends StateNotifier<PartiesState> {
  PartiesController({
    required PartyRepository repository,
    required PartySearchPort search,
    required PartyRoleRepository roles,
    required DuplicateDetectionPort duplicates,
    required WorkspaceSessionScope scope,
    PartyQueryInvalidationSource? invalidationSource,
    PartiesIdFactory? idFactory,
  }) : _repository = repository,
       _search = search,
       _roles = roles,
       _duplicates = duplicates,
       _scope = scope,
       _invalidationSource = invalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       super(const PartiesState.loading());

  static const String readPermission = 'party.read';
  static const String managePermission = 'party.manage';
  static const int pageSize = 50;

  final PartyRepository _repository;
  final PartySearchPort _search;
  final PartyRoleRepository _roles;
  final DuplicateDetectionPort _duplicates;
  final WorkspaceSessionScope _scope;
  final PartyQueryInvalidationSource? _invalidationSource;
  final PartiesIdFactory _idFactory;

  StreamSubscription<PartyQueryInvalidation>? _invalidationSubscription;
  int _generation = 0;
  int _detailGeneration = 0;

  AuthorizationPort get _authorization => _scope.authorization;

  /// Whether mutation affordances are actionable at all. False in a read-only
  /// backend and when the actor lacks `party.manage` in cloud mode.
  bool get canMutate =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _authorization.can(managePermission);

  /// True exactly when the backend itself blocks mutations, which is what the
  /// "read-only until migrated" notice reports (as opposed to a rights issue).
  bool get isReadOnlyBackend => !_scope.mutationsSupported;

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        listPhase: PartiesListPhase.idle,
        parties: const <PartySummaryDto>[],
        nextCursor: null,
        message: null,
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(
      listPhase: PartiesListPhase.loading,
      message: null,
    );
    final result = await _search.search(
      PartyListQuery(
        workspaceId: workspaceId,
        roleType: state.roleFilter,
        page: const PartyPageRequest(limit: pageSize),
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case PartyRepositorySuccess<PartyPageResult>(:final value):
        state = state.copyWith(
          listPhase:
              value.items.isEmpty
                  ? PartiesListPhase.empty
                  : PartiesListPhase.ready,
          parties: value.items,
          nextCursor: value.nextCursor,
          message: null,
        );
      case PartyRepositoryFailure<PartyPageResult>(:final kind, :final message):
        state = state.copyWith(
          listPhase:
              kind == PartyRepositoryFailureKind.forbidden
                  ? PartiesListPhase.forbidden
                  : PartiesListPhase.error,
          parties: const <PartySummaryDto>[],
          nextCursor: null,
          message: message,
        );
    }
  }

  Future<void> loadMore() async {
    final workspaceId = _scope.workspaceId;
    final cursor = state.nextCursor;
    if (workspaceId == null || cursor == null || state.loadingMore) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(loadingMore: true);
    final result = await _search.search(
      PartyListQuery(
        workspaceId: workspaceId,
        roleType: state.roleFilter,
        page: PartyPageRequest(limit: pageSize, cursor: cursor),
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case PartyRepositorySuccess<PartyPageResult>(:final value):
        state = state.copyWith(
          parties: <PartySummaryDto>[...state.parties, ...value.items],
          nextCursor: value.nextCursor,
          loadingMore: false,
        );
      case PartyRepositoryFailure<PartyPageResult>(:final message):
        state = state.copyWith(loadingMore: false, message: message);
    }
  }

  Future<void> setRoleFilter(PartyRoleType? roleType) async {
    if (roleType == state.roleFilter) {
      return;
    }
    state = state.copyWith(roleFilter: roleType);
    await load();
  }

  Future<void> select(String? partyId) async {
    if (partyId == null) {
      _detailGeneration++;
      state = state.copyWith(
        detailPhase: PartiesDetailPhase.idle,
        selectedPartyId: null,
        selectedParty: null,
        roles: const <PartyRoleDto>[],
        contractorDetails: null,
      );
      return;
    }
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_detailGeneration;
    state = state.copyWith(
      detailPhase: PartiesDetailPhase.loading,
      selectedPartyId: partyId,
      selectedParty: null,
      roles: const <PartyRoleDto>[],
      contractorDetails: null,
    );
    final partyResult = await _repository.getById(
      workspaceId: workspaceId,
      partyId: partyId,
    );
    if (generation != _detailGeneration) {
      return;
    }
    if (partyResult is PartyRepositoryFailure<PartyDto>) {
      state = state.copyWith(
        detailPhase:
            partyResult.kind == PartyRepositoryFailureKind.forbidden
                ? PartiesDetailPhase.forbidden
                : PartiesDetailPhase.error,
        message: partyResult.message,
      );
      return;
    }
    final party = (partyResult as PartyRepositorySuccess<PartyDto>).value;
    final rolesResult = await _roles.listForParty(
      workspaceId: workspaceId,
      partyId: partyId,
    );
    final contractorResult = await _roles.getContractorDetails(
      workspaceId: workspaceId,
      partyId: partyId,
    );
    if (generation != _detailGeneration) {
      return;
    }
    state = state.copyWith(
      detailPhase: PartiesDetailPhase.ready,
      selectedParty: party,
      roles: switch (rolesResult) {
        PartyRepositorySuccess<List<PartyRoleDto>>(:final value) => value,
        PartyRepositoryFailure<List<PartyRoleDto>>() => const <PartyRoleDto>[],
      },
      contractorDetails: switch (contractorResult) {
        PartyRepositorySuccess<ContractorDetailsDto?>(:final value) => value,
        PartyRepositoryFailure<ContractorDetailsDto?>() => null,
      },
    );
  }

  /// Live duplicate probe for the create/edit dialog. Never blocks saving on
  /// its own — it warns, the user decides.
  Future<void> probeDuplicates({
    String? displayName,
    String? email,
    String? phone,
  }) async {
    final workspaceId = _scope.workspaceId;
    final name = _trimToNull(displayName);
    final mail = _trimToNull(email);
    final tel = _trimToNull(phone);
    if (workspaceId == null || (name == null && mail == null && tel == null)) {
      state = state.copyWith(duplicates: const <PartyDuplicateCandidate>[]);
      return;
    }
    final result = await _duplicates.detect(
      PartyDuplicateQuery(
        workspaceId: workspaceId,
        displayName: name,
        email: mail,
        phone: tel,
      ),
    );
    state = state.copyWith(
      duplicates: switch (result) {
        PartyRepositorySuccess<List<PartyDuplicateCandidate>>(:final value) =>
          value,
        PartyRepositoryFailure<List<PartyDuplicateCandidate>>() =>
          const <PartyDuplicateCandidate>[],
      },
    );
  }

  void clearDuplicates() {
    state = state.copyWith(duplicates: const <PartyDuplicateCandidate>[]);
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: PartiesActionPhase.idle,
      actionMessage: null,
      versionConflict: null,
    );
  }

  Future<void> createParty(PartyDraft draft) async {
    await _runMutation(
      () => _repository.create(
        CreatePartyCommand(context: _commandContext(), draft: draft),
      ),
      onSuccess: (PartyDto party) async {
        await load();
        await select(party.id);
      },
      successMessage: 'Partei angelegt.',
    );
  }

  Future<void> updateParty({
    required String partyId,
    required int expectedVersion,
    required PartyUpdateDto changes,
  }) async {
    await _runMutation(
      () => _repository.update(
        UpdatePartyCommand(
          context: _commandContext(),
          partyId: partyId,
          expectedVersion: expectedVersion,
          changes: changes,
        ),
      ),
      onSuccess: (PartyDto party) async {
        await load();
        await select(party.id);
      },
      successMessage: 'Partei aktualisiert.',
    );
  }

  Future<void> assignRole({
    required String partyId,
    required PartyRoleType roleType,
    DateTime? validFrom,
    DateTime? validUntil,
    ContractorDetailsInput? contractorDetails,
  }) async {
    await _runMutation(
      () => _roles.assign(
        AssignPartyRoleCommand(
          context: _commandContext(),
          partyId: partyId,
          roleType: roleType,
          validFrom: validFrom,
          validUntil: validUntil,
          contractorDetails: contractorDetails,
        ),
      ),
      onSuccess: (PartyRoleDto _) => select(partyId),
      successMessage: 'Rolle zugewiesen.',
    );
  }

  Future<void> endRole({
    required String partyRoleId,
    required int expectedVersion,
    DateTime? validUntil,
  }) async {
    final partyId = state.selectedPartyId;
    await _runMutation(
      () => _roles.end(
        EndPartyRoleCommand(
          context: _commandContext(),
          partyRoleId: partyRoleId,
          expectedVersion: expectedVersion,
          validUntil: validUntil,
        ),
      ),
      onSuccess: (PartyRoleDto _) => select(partyId),
      successMessage: 'Rolle beendet.',
    );
  }

  /// Folds [sourcePartyId] into [targetPartyId]. Consequential and audited —
  /// the screen must confirm before calling this.
  Future<void> mergeParties({
    required String targetPartyId,
    required String sourcePartyId,
    required int expectedTargetVersion,
    required int expectedSourceVersion,
  }) async {
    await _runMutation(
      () => _repository.merge(
        MergePartiesCommand(
          context: _commandContext(),
          targetPartyId: targetPartyId,
          sourcePartyId: sourcePartyId,
          expectedTargetVersion: expectedTargetVersion,
          expectedSourceVersion: expectedSourceVersion,
        ),
      ),
      onSuccess: (PartyDto party) async {
        await load();
        await select(party.id);
      },
      successMessage: 'Parteien zusammengeführt.',
    );
  }

  Future<void> _runMutation<T>(
    Future<PartyRepositoryResult<T>> Function() command, {
    required Future<void> Function(T value) onSuccess,
    required String successMessage,
  }) async {
    if (isReadOnlyBackend) {
      state = state.copyWith(
        actionPhase: PartiesActionPhase.readOnly,
        actionMessage:
            'Parteien sind in der lokalen Datenbank schreibgeschützt, bis '
            'diese Domäne migriert ist.',
        versionConflict: null,
      );
      return;
    }
    if (!_scope.isResolved || !_authorization.can(managePermission)) {
      state = state.copyWith(
        actionPhase: PartiesActionPhase.forbidden,
        actionMessage: 'Für diese Aktion fehlt die Berechtigung.',
        versionConflict: null,
      );
      return;
    }
    state = state.copyWith(
      actionPhase: PartiesActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await command();
    switch (result) {
      case PartyRepositorySuccess<T>(:final value):
        await onSuccess(value);
        state = state.copyWith(
          actionPhase: PartiesActionPhase.succeeded,
          actionMessage: successMessage,
          versionConflict: null,
        );
      case PartyRepositoryFailure<T>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        state = state.copyWith(
          actionPhase: switch (kind) {
            PartyRepositoryFailureKind.versionConflict =>
              PartiesActionPhase.conflict,
            PartyRepositoryFailureKind.forbidden =>
              PartiesActionPhase.forbidden,
            PartyRepositoryFailureKind.dependencyConflict =>
              PartiesActionPhase.readOnly,
            _ => PartiesActionPhase.failed,
          },
          actionMessage: message,
          versionConflict: versionConflict,
        );
    }
  }

  PartyCommandContext _commandContext() {
    return PartyCommandContext(
      workspaceId: _scope.workspaceId!,
      actorId: _scope.actorId!,
      mutationId: _idFactory(),
      correlationId: _idFactory(),
    );
  }

  void _subscribeToInvalidation(String workspaceId) {
    final source = _invalidationSource;
    if (source == null || _invalidationSubscription != null) {
      return;
    }
    _invalidationSubscription = source
        .watchWorkspace(workspaceId: workspaceId)
        .listen((invalidation) {
          if (invalidation.workspaceId != _scope.workspaceId) {
            return;
          }
          unawaited(load());
          final selectedId = state.selectedPartyId;
          if (selectedId != null &&
              (invalidation.isReconciliation ||
                  invalidation.partyId == selectedId)) {
            unawaited(select(selectedId));
          }
        });
  }

  static String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  void dispose() {
    unawaited(_invalidationSubscription?.cancel());
    _invalidationSubscription = null;
    super.dispose();
  }
}

final partiesControllerProvider = StateNotifierProvider.autoDispose<
  PartiesController,
  PartiesState
>((ref) {
  final controller = PartiesController(
    repository: ref.watch(partyRepositoryProvider),
    search: ref.watch(partySearchProvider),
    roles: ref.watch(partyRoleProvider),
    duplicates: ref.watch(duplicateDetectionProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
    invalidationSource: ref.watch(partyQueryInvalidationSourceProvider),
  );
  unawaited(controller.load());
  return controller;
});
