/// Screen-facing orchestration for the contractor surface (Welle 4, SCR-040).
///
/// A contractor is a party holding an open `contractor` role — the same
/// P2-D02 pattern `tenants_controller.dart` established for tenants, applied
/// to a role that has satellite attributes (`ContractorDetailsDto`/
/// `ContractorDetailsInput`: trade, rate, service area, five rating
/// dimensions, insurance expiry) instead of none. Replaces the standalone
/// legacy `ContractorRecord` table, which had no identity in common with any
/// other party — a company that was both a landlord contact and a contractor
/// was two disconnected rows.
///
/// Deliberately **not** composed with `maintenance_capex` (unlike
/// `TenantsController`'s lease half): the original brief for this screen
/// names only the P2-D02 contract, and a "tickets for this contractor" view
/// would need the workspace-wide read filtered by `contractor_party_id`,
/// which does not exist. Left as a documented gap, not built around.
///
/// **The contract has no update path for the contractor satellite.**
/// `PartyRoleRepository` offers `assign` (sets `ContractorDetailsInput` once,
/// when the role is granted) and `end`, but no `updateContractorDetails`. So
/// [updateContractor] can only change the party's own identity fields
/// (`PartyUpdateDto` — name/email/phone/notes); rate/rating/trade/insurance
/// stay whatever they were assigned with until the role ends and a new one is
/// assigned. The panel says this rather than offering an edit control that
/// would silently do nothing.
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

enum ContractorsListPhase { idle, loading, ready, empty, forbidden, error }

enum ContractorsDetailPhase { idle, loading, ready, notFound, forbidden, error }

enum ContractorsActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,
  readOnly,

  /// The party was created but its `contractor` role was not assigned — same
  /// shape as `TenantsActionPhase.partiallyApplied`, same reason: the record
  /// exists and the user has to know that, not have it hidden.
  partiallyApplied,
  failed,
}

class ContractorsState {
  const ContractorsState({
    required this.listPhase,
    this.detailPhase = ContractorsDetailPhase.idle,
    this.actionPhase = ContractorsActionPhase.idle,
    this.contractors = const <PartySummaryDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.selectedPartyId,
    this.selectedParty,
    this.selectedRoles = const <PartyRoleDto>[],
    this.selectedContractorDetails,
    this.versionConflict,
    this.message,
    this.actionMessage,
  });

  const ContractorsState.loading()
    : this(listPhase: ContractorsListPhase.loading);

  final ContractorsListPhase listPhase;
  final ContractorsDetailPhase detailPhase;
  final ContractorsActionPhase actionPhase;

  /// Parties holding an open `contractor` role — the filter is server-side.
  final List<PartySummaryDto> contractors;

  final String? nextCursor;
  final bool loadingMore;
  final String? selectedPartyId;
  final PartyDto? selectedParty;

  /// **All** roles of the selected party, not only the contractor one — same
  /// reasoning as `TenantsState.selectedRoles`: one identity, several roles.
  final List<PartyRoleDto> selectedRoles;
  final ContractorDetailsDto? selectedContractorDetails;
  final PartyVersionConflict? versionConflict;
  final String? message;
  final String? actionMessage;

  bool get hasMore => nextCursor != null;

  PartyRoleDto? get openContractorRole => selectedRoles
      .where((role) => role.roleType == PartyRoleType.contractor && role.isOpen)
      .firstOrNull;

  ContractorsState copyWith({
    ContractorsListPhase? listPhase,
    ContractorsDetailPhase? detailPhase,
    ContractorsActionPhase? actionPhase,
    List<PartySummaryDto>? contractors,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    Object? selectedPartyId = _unchanged,
    Object? selectedParty = _unchanged,
    List<PartyRoleDto>? selectedRoles,
    Object? selectedContractorDetails = _unchanged,
    Object? versionConflict = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
  }) {
    return ContractorsState(
      listPhase: listPhase ?? this.listPhase,
      detailPhase: detailPhase ?? this.detailPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      contractors: contractors ?? this.contractors,
      nextCursor: identical(nextCursor, _unchanged)
          ? this.nextCursor
          : nextCursor as String?,
      loadingMore: loadingMore ?? this.loadingMore,
      selectedPartyId: identical(selectedPartyId, _unchanged)
          ? this.selectedPartyId
          : selectedPartyId as String?,
      selectedParty: identical(selectedParty, _unchanged)
          ? this.selectedParty
          : selectedParty as PartyDto?,
      selectedRoles: selectedRoles ?? this.selectedRoles,
      selectedContractorDetails: identical(selectedContractorDetails, _unchanged)
          ? this.selectedContractorDetails
          : selectedContractorDetails as ContractorDetailsDto?,
      versionConflict: identical(versionConflict, _unchanged)
          ? this.versionConflict
          : versionConflict as PartyVersionConflict?,
      message: identical(message, _unchanged) ? this.message : message as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
    );
  }
}

typedef ContractorsIdFactory = String Function();

class ContractorsController extends StateNotifier<ContractorsState> {
  ContractorsController({
    required PartyRepository partyRepository,
    required PartySearchPort partySearch,
    required PartyRoleRepository partyRoles,
    required WorkspaceSessionScope scope,
    PartyQueryInvalidationSource? partyInvalidationSource,
    ContractorsIdFactory? idFactory,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
  }) : _partyRepository = partyRepository,
       _partySearch = partySearch,
       _partyRoles = partyRoles,
       _scope = scope,
       _partyInvalidationSource = partyInvalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       _coalesceWindow = invalidationCoalesceWindow,
       super(const ContractorsState.loading());

  static const String partyReadPermission = 'party.read';
  static const String partyManagePermission = 'party.manage';
  static const int pageSize = 50;

  final PartyRepository _partyRepository;
  final PartySearchPort _partySearch;
  final PartyRoleRepository _partyRoles;
  final WorkspaceSessionScope _scope;
  final PartyQueryInvalidationSource? _partyInvalidationSource;
  final ContractorsIdFactory _idFactory;
  final Duration _coalesceWindow;

  StreamSubscription<PartyQueryInvalidation>? _partySubscription;
  Timer? _invalidationTimer;
  int _generation = 0;
  int _detailGeneration = 0;

  AuthorizationPort get _authorization => _scope.authorization;

  bool get canMutate =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _authorization.can(partyManagePermission);

  bool get isReadOnlyBackend => !_scope.mutationsSupported;

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        listPhase: ContractorsListPhase.idle,
        contractors: const <PartySummaryDto>[],
        nextCursor: null,
        message: null,
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(
      listPhase: ContractorsListPhase.loading,
      message: null,
    );
    final result = await _partySearch.search(
      PartyListQuery(
        workspaceId: workspaceId,
        roleType: PartyRoleType.contractor,
        page: const PartyPageRequest(limit: pageSize),
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case PartyRepositorySuccess<PartyPageResult>(:final value):
        state = state.copyWith(
          listPhase: value.items.isEmpty
              ? ContractorsListPhase.empty
              : ContractorsListPhase.ready,
          contractors: value.items,
          nextCursor: value.nextCursor,
          message: null,
        );
      case PartyRepositoryFailure<PartyPageResult>(:final kind, :final message):
        state = state.copyWith(
          listPhase: kind == PartyRepositoryFailureKind.forbidden
              ? ContractorsListPhase.forbidden
              : ContractorsListPhase.error,
          contractors: const <PartySummaryDto>[],
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
    final result = await _partySearch.search(
      PartyListQuery(
        workspaceId: workspaceId,
        roleType: PartyRoleType.contractor,
        page: PartyPageRequest(limit: pageSize, cursor: cursor),
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case PartyRepositorySuccess<PartyPageResult>(:final value):
        state = state.copyWith(
          contractors: <PartySummaryDto>[...state.contractors, ...value.items],
          nextCursor: value.nextCursor,
          loadingMore: false,
        );
      case PartyRepositoryFailure<PartyPageResult>(:final message):
        state = state.copyWith(loadingMore: false, message: message);
    }
  }

  Future<void> select(String? partyId) async {
    if (partyId == null) {
      _detailGeneration++;
      state = state.copyWith(
        detailPhase: ContractorsDetailPhase.idle,
        selectedPartyId: null,
        selectedParty: null,
        selectedRoles: const <PartyRoleDto>[],
        selectedContractorDetails: null,
      );
      return;
    }
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_detailGeneration;
    state = state.copyWith(
      detailPhase: ContractorsDetailPhase.loading,
      selectedPartyId: partyId,
      selectedParty: null,
      selectedRoles: const <PartyRoleDto>[],
      selectedContractorDetails: null,
    );
    final result = await _partyRepository.getById(
      workspaceId: workspaceId,
      partyId: partyId,
    );
    if (generation != _detailGeneration) {
      return;
    }
    switch (result) {
      case PartyRepositorySuccess<PartyDto>(:final value):
        final roles = await _loadRoles(workspaceId, partyId);
        final details = await _loadContractorDetails(workspaceId, partyId);
        if (generation != _detailGeneration) {
          return;
        }
        state = state.copyWith(
          detailPhase: ContractorsDetailPhase.ready,
          selectedParty: value,
          selectedRoles: roles,
          selectedContractorDetails: details,
        );
      case PartyRepositoryFailure<PartyDto>(:final kind, :final message):
        state = state.copyWith(
          detailPhase: switch (kind) {
            PartyRepositoryFailureKind.notFound =>
              ContractorsDetailPhase.notFound,
            PartyRepositoryFailureKind.forbidden =>
              ContractorsDetailPhase.forbidden,
            _ => ContractorsDetailPhase.error,
          },
          message: message,
        );
    }
  }

  /// A role list that cannot be read degrades to empty: the identity loaded,
  /// and the view says the roles are unknown rather than claiming none exist.
  Future<List<PartyRoleDto>> _loadRoles(
    String workspaceId,
    String partyId,
  ) async {
    final result = await _partyRoles.listForParty(
      workspaceId: workspaceId,
      partyId: partyId,
    );
    return switch (result) {
      PartyRepositorySuccess<List<PartyRoleDto>>(:final value) => value,
      PartyRepositoryFailure<List<PartyRoleDto>>() => const <PartyRoleDto>[],
    };
  }

  Future<ContractorDetailsDto?> _loadContractorDetails(
    String workspaceId,
    String partyId,
  ) async {
    final result = await _partyRoles.getContractorDetails(
      workspaceId: workspaceId,
      partyId: partyId,
    );
    return switch (result) {
      PartyRepositorySuccess<ContractorDetailsDto?>(:final value) => value,
      PartyRepositoryFailure<ContractorDetailsDto?>() => null,
    };
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: ContractorsActionPhase.idle,
      actionMessage: null,
      versionConflict: null,
    );
  }

  /// Creating a contractor is creating a **party** and giving it the
  /// `contractor` role with its satellite details — two commands, not one
  /// transaction, exactly `TenantsController.createTenant`'s shape.
  Future<void> createContractor({
    required PartyDraft draft,
    required ContractorDetailsInput details,
  }) async {
    if (_applyMutationGate()) {
      return;
    }
    state = state.copyWith(
      actionPhase: ContractorsActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final created = await _partyRepository.create(
      CreatePartyCommand(context: _commandContext(), draft: draft),
    );
    switch (created) {
      case PartyRepositoryFailure<PartyDto>(:final kind, :final message):
        _applyFailure(kind, message, null);
      case PartyRepositorySuccess<PartyDto>(:final value):
        final assigned = await _partyRoles.assign(
          AssignPartyRoleCommand(
            context: _commandContext(),
            partyId: value.id,
            roleType: PartyRoleType.contractor,
            contractorDetails: details,
          ),
        );
        switch (assigned) {
          case PartyRepositorySuccess<PartyRoleDto>():
            await load();
            await select(value.id);
            state = state.copyWith(
              actionPhase: ContractorsActionPhase.succeeded,
              actionMessage: 'Handwerker angelegt.',
              versionConflict: null,
            );
          case PartyRepositoryFailure<PartyRoleDto>(:final message):
            // Not a rollback — same reasoning as TenantsController: deleting
            // the party would need a delete path this domain does not have.
            await load();
            state = state.copyWith(
              actionPhase: ContractorsActionPhase.partiallyApplied,
              actionMessage:
                  '„${value.displayName}" wurde als Partei angelegt, aber die '
                  'Handwerker-Rolle konnte nicht zugewiesen werden: $message. '
                  'Die Partei existiert und kann im Verzeichnis '
                  'weiterbearbeitet werden.',
              versionConflict: null,
            );
        }
    }
  }

  /// Party identity only — see the library comment for why the contractor
  /// satellite (rate/rating/trade/insurance) has no update path today.
  Future<void> updateContractor({
    required PartyDto party,
    required PartyUpdateDto changes,
  }) async {
    await _runMutation(
      () => _partyRepository.update(
        UpdatePartyCommand(
          context: _commandContext(),
          partyId: party.id,
          expectedVersion: party.version,
          changes: changes,
        ),
      ),
      onSuccess: (PartyDto updated) async {
        await load();
        await select(updated.id);
      },
      successMessage: 'Handwerker gespeichert.',
    );
  }

  /// Ends the contractor role rather than deleting anything. The party keeps
  /// its identity and its other roles; it simply leaves this role-scoped list.
  Future<void> endContractorRole({
    required PartyRoleDto role,
    DateTime? validUntil,
  }) async {
    await _runMutation(
      () => _partyRoles.end(
        EndPartyRoleCommand(
          context: _commandContext(),
          partyRoleId: role.id,
          expectedVersion: role.version,
          validUntil: validUntil,
        ),
      ),
      onSuccess: (PartyRoleDto ended) async {
        await load();
        await select(null);
      },
      successMessage:
          'Handwerker-Rolle beendet. Die Partei bleibt im Verzeichnis '
          'erhalten.',
    );
  }

  Future<void> _runMutation<T>(
    Future<PartyRepositoryResult<T>> Function() command, {
    required Future<void> Function(T value) onSuccess,
    required String successMessage,
  }) async {
    if (_applyMutationGate()) {
      return;
    }
    state = state.copyWith(
      actionPhase: ContractorsActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await command();
    switch (result) {
      case PartyRepositorySuccess<T>(:final value):
        await onSuccess(value);
        state = state.copyWith(
          actionPhase: ContractorsActionPhase.succeeded,
          actionMessage: successMessage,
          versionConflict: null,
        );
      case PartyRepositoryFailure<T>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        _applyFailure(kind, message, versionConflict);
    }
  }

  void _applyFailure(
    PartyRepositoryFailureKind kind,
    String message,
    PartyVersionConflict? versionConflict,
  ) {
    state = state.copyWith(
      actionPhase: switch (kind) {
        PartyRepositoryFailureKind.versionConflict =>
          ContractorsActionPhase.conflict,
        PartyRepositoryFailureKind.forbidden => ContractorsActionPhase.forbidden,
        PartyRepositoryFailureKind.dependencyConflict =>
          ContractorsActionPhase.readOnly,
        _ => ContractorsActionPhase.failed,
      },
      actionMessage: message,
      versionConflict: versionConflict,
    );
  }

  bool _applyMutationGate() {
    if (isReadOnlyBackend) {
      state = state.copyWith(
        actionPhase: ContractorsActionPhase.readOnly,
        actionMessage:
            'Handwerker sind in der lokalen Datenbank schreibgeschützt, bis '
            'das Parteienverzeichnis migriert ist.',
        versionConflict: null,
      );
      return true;
    }
    if (!_scope.isResolved || !_authorization.can(partyManagePermission)) {
      state = state.copyWith(
        actionPhase: ContractorsActionPhase.forbidden,
        actionMessage: 'Für diese Aktion fehlt die Berechtigung.',
        versionConflict: null,
      );
      return true;
    }
    return false;
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
    final partySource = _partyInvalidationSource;
    if (partySource != null && _partySubscription == null) {
      _partySubscription = partySource
          .watchWorkspace(workspaceId: workspaceId)
          .listen((invalidation) {
            if (invalidation.workspaceId != _scope.workspaceId) {
              return;
            }
            _scheduleInvalidationReload();
          });
    }
  }

  void _scheduleInvalidationReload() {
    _invalidationTimer?.cancel();
    _invalidationTimer = Timer(_coalesceWindow, () {
      unawaited(load());
      final selectedId = state.selectedPartyId;
      if (selectedId != null) {
        unawaited(select(selectedId));
      }
    });
  }

  @override
  void dispose() {
    _invalidationTimer?.cancel();
    _invalidationTimer = null;
    unawaited(_partySubscription?.cancel());
    _partySubscription = null;
    super.dispose();
  }
}

final contractorsControllerProvider =
    StateNotifierProvider.autoDispose<ContractorsController, ContractorsState>((
      ref,
    ) {
      final controller = ContractorsController(
        partyRepository: ref.watch(partyRepositoryProvider),
        partySearch: ref.watch(partySearchProvider),
        partyRoles: ref.watch(partyRoleProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        partyInvalidationSource: ref.watch(partyQueryInvalidationSourceProvider),
      );
      unawaited(controller.load());
      return controller;
    });
