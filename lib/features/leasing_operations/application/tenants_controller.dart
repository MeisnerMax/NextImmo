/// Screen-facing orchestration for the tenant surface (Welle 3, AP5).
///
/// This controller lives in `leasing_operations` although its list comes from
/// `contacts_parties`, because what makes a party a *tenant* is the leasing
/// side: the role is the filter, the leases are the content. It composes the
/// two contracts and reads them **separately** — there is no joint query and
/// this layer does not invent one (AGG-005: there is deliberately no cloud
/// `tenants` table, so a tenant is a party holding an open `tenant` role).
///
/// Three things follow from that composition and are visible in the API:
///
///   * **Creating a tenant is two commands, not one.** Create the party, then
///     assign the role. There is no transaction across two RPCs, so the failure
///     mode is real and is reported as what it is — a party that exists without
///     its role — rather than as a generic failure. Hiding it would leave the
///     user with an invisible record.
///   * **A tenant is never deleted; the role ends.** The party survives with
///     its history and simply leaves this list, because the list is
///     role-scoped. `OPN-DOM-005` aside, that is also the honest model: the
///     person did not stop existing.
///   * **The lease half degrades on its own.** `lease.read` and `party.read`
///     are separate permissions, so a tenant whose leases cannot be read still
///     shows an identity, with the lease section saying why it is empty.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../contacts_parties/application/party_providers.dart';
import '../../contacts_parties/application/party_query_invalidation_source.dart';
import '../../contacts_parties/application/party_repository.dart';
import '../../contacts_parties/domain/party_dto.dart';
import '../../identity_access/application/authorization_port.dart';
import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/lease_dto.dart';
import 'leasing_providers.dart';
import 'leasing_query_invalidation_source.dart';
import 'leasing_repository.dart';

const Object _unchanged = Object();

enum TenantsListPhase { idle, loading, ready, empty, forbidden, error }

enum TenantsDetailPhase { idle, loading, ready, notFound, forbidden, error }

/// How the selected tenant's lease list turned out. Its own zone because
/// `lease.read` is a different permission from `party.read`: the identity can
/// be readable while the leases are not.
enum TenantLeasesPhase { idle, ready, empty, forbidden, error }

enum TenantsActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,
  readOnly,

  /// The party was created but its `tenant` role was not assigned. Its own
  /// phase because the record exists and the user has to know that.
  partiallyApplied,
  failed,
}

class TenantsState {
  const TenantsState({
    required this.listPhase,
    this.detailPhase = TenantsDetailPhase.idle,
    this.leasesPhase = TenantLeasesPhase.idle,
    this.actionPhase = TenantsActionPhase.idle,
    this.tenants = const <PartySummaryDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.selectedPartyId,
    this.selectedParty,
    this.selectedRoles = const <PartyRoleDto>[],
    this.selectedLeases = const <LeaseSummaryDto>[],
    this.versionConflict,
    this.message,
    this.actionMessage,
    this.leasesMessage,
  });

  const TenantsState.loading() : this(listPhase: TenantsListPhase.loading);

  final TenantsListPhase listPhase;
  final TenantsDetailPhase detailPhase;
  final TenantLeasesPhase leasesPhase;
  final TenantsActionPhase actionPhase;

  /// Parties holding an open `tenant` role — the filter is server-side.
  final List<PartySummaryDto> tenants;

  final String? nextCursor;
  final bool loadingMore;
  final String? selectedPartyId;
  final PartyDto? selectedParty;

  /// **All** roles of the selected party, not only the tenant one: the point of
  /// P2-D02 is that one identity carries several roles, and hiding the others
  /// here would rebuild the per-role person file `DUP-010` exists to remove.
  final List<PartyRoleDto> selectedRoles;

  final List<LeaseSummaryDto> selectedLeases;
  final PartyVersionConflict? versionConflict;
  final String? message;
  final String? actionMessage;
  final String? leasesMessage;

  bool get hasMore => nextCursor != null;

  /// The open tenant role of the selected party, if any — the one that would be
  /// ended. Null when the role was already closed while the screen was open.
  PartyRoleDto? get openTenantRole => selectedRoles
      .where((role) => role.roleType == PartyRoleType.tenant && role.isOpen)
      .firstOrNull;

  TenantsState copyWith({
    TenantsListPhase? listPhase,
    TenantsDetailPhase? detailPhase,
    TenantLeasesPhase? leasesPhase,
    TenantsActionPhase? actionPhase,
    List<PartySummaryDto>? tenants,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    Object? selectedPartyId = _unchanged,
    Object? selectedParty = _unchanged,
    List<PartyRoleDto>? selectedRoles,
    List<LeaseSummaryDto>? selectedLeases,
    Object? versionConflict = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
    Object? leasesMessage = _unchanged,
  }) {
    return TenantsState(
      listPhase: listPhase ?? this.listPhase,
      detailPhase: detailPhase ?? this.detailPhase,
      leasesPhase: leasesPhase ?? this.leasesPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      tenants: tenants ?? this.tenants,
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
      selectedLeases: selectedLeases ?? this.selectedLeases,
      versionConflict: identical(versionConflict, _unchanged)
          ? this.versionConflict
          : versionConflict as PartyVersionConflict?,
      message: identical(message, _unchanged) ? this.message : message as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
      leasesMessage: identical(leasesMessage, _unchanged)
          ? this.leasesMessage
          : leasesMessage as String?,
    );
  }
}

typedef TenantsIdFactory = String Function();

class TenantsController extends StateNotifier<TenantsState> {
  TenantsController({
    required PartyRepository partyRepository,
    required PartySearchPort partySearch,
    required PartyRoleRepository partyRoles,
    required LeaseSearchPort leaseSearch,
    required WorkspaceSessionScope scope,
    PartyQueryInvalidationSource? partyInvalidationSource,
    LeasingQueryInvalidationSource? leasingInvalidationSource,
    TenantsIdFactory? idFactory,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
  }) : _partyRepository = partyRepository,
       _partySearch = partySearch,
       _partyRoles = partyRoles,
       _leaseSearch = leaseSearch,
       _scope = scope,
       _partyInvalidationSource = partyInvalidationSource,
       _leasingInvalidationSource = leasingInvalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       _coalesceWindow = invalidationCoalesceWindow,
       super(const TenantsState.loading());

  static const String partyReadPermission = 'party.read';
  static const String partyManagePermission = 'party.manage';
  static const int pageSize = 50;
  static const int leasePageSize = 100;

  final PartyRepository _partyRepository;
  final PartySearchPort _partySearch;
  final PartyRoleRepository _partyRoles;
  final LeaseSearchPort _leaseSearch;
  final WorkspaceSessionScope _scope;
  final PartyQueryInvalidationSource? _partyInvalidationSource;
  final LeasingQueryInvalidationSource? _leasingInvalidationSource;
  final TenantsIdFactory _idFactory;
  final Duration _coalesceWindow;

  StreamSubscription<PartyQueryInvalidation>? _partySubscription;
  StreamSubscription<LeasingQueryInvalidation>? _leasingSubscription;
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
        listPhase: TenantsListPhase.idle,
        tenants: const <PartySummaryDto>[],
        nextCursor: null,
        message: null,
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(listPhase: TenantsListPhase.loading, message: null);
    final result = await _partySearch.search(
      PartyListQuery(
        workspaceId: workspaceId,
        roleType: PartyRoleType.tenant,
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
              ? TenantsListPhase.empty
              : TenantsListPhase.ready,
          tenants: value.items,
          nextCursor: value.nextCursor,
          message: null,
        );
      case PartyRepositoryFailure<PartyPageResult>(:final kind, :final message):
        state = state.copyWith(
          listPhase: kind == PartyRepositoryFailureKind.forbidden
              ? TenantsListPhase.forbidden
              : TenantsListPhase.error,
          tenants: const <PartySummaryDto>[],
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
        roleType: PartyRoleType.tenant,
        page: PartyPageRequest(limit: pageSize, cursor: cursor),
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case PartyRepositorySuccess<PartyPageResult>(:final value):
        state = state.copyWith(
          tenants: <PartySummaryDto>[...state.tenants, ...value.items],
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
        detailPhase: TenantsDetailPhase.idle,
        leasesPhase: TenantLeasesPhase.idle,
        selectedPartyId: null,
        selectedParty: null,
        selectedRoles: const <PartyRoleDto>[],
        selectedLeases: const <LeaseSummaryDto>[],
        leasesMessage: null,
      );
      return;
    }
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_detailGeneration;
    state = state.copyWith(
      detailPhase: TenantsDetailPhase.loading,
      leasesPhase: TenantLeasesPhase.idle,
      selectedPartyId: partyId,
      selectedParty: null,
      selectedRoles: const <PartyRoleDto>[],
      selectedLeases: const <LeaseSummaryDto>[],
      leasesMessage: null,
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
        if (generation != _detailGeneration) {
          return;
        }
        state = state.copyWith(
          detailPhase: TenantsDetailPhase.ready,
          selectedParty: value,
          selectedRoles: roles,
        );
        await _loadLeases(workspaceId, partyId, generation);
      case PartyRepositoryFailure<PartyDto>(:final kind, :final message):
        state = state.copyWith(
          detailPhase: switch (kind) {
            PartyRepositoryFailureKind.notFound => TenantsDetailPhase.notFound,
            PartyRepositoryFailureKind.forbidden => TenantsDetailPhase.forbidden,
            _ => TenantsDetailPhase.error,
          },
          message: message,
        );
    }
  }

  /// A role list that cannot be read degrades to empty: the identity loaded,
  /// and the view says the roles are unknown rather than claiming there are
  /// none.
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

  /// The leasing half of the detail. Its own phase and its own message: this is
  /// where the second contract can fail independently of the first.
  Future<void> _loadLeases(
    String workspaceId,
    String partyId,
    int generation,
  ) async {
    final result = await _leaseSearch.search(
      LeaseListQuery(
        workspaceId: workspaceId,
        tenantPartyId: partyId,
        page: const LeasingPageRequest(limit: leasePageSize),
      ),
    );
    if (generation != _detailGeneration) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
        :final value,
      ):
        state = state.copyWith(
          leasesPhase: value.items.isEmpty
              ? TenantLeasesPhase.empty
              : TenantLeasesPhase.ready,
          selectedLeases: value.items,
          leasesMessage: null,
        );
      case LeasingRepositoryFailure<LeasingPageResult<LeaseSummaryDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          leasesPhase: kind == LeasingRepositoryFailureKind.forbidden
              ? TenantLeasesPhase.forbidden
              : TenantLeasesPhase.error,
          selectedLeases: const <LeaseSummaryDto>[],
          leasesMessage: message,
        );
    }
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: TenantsActionPhase.idle,
      actionMessage: null,
      versionConflict: null,
    );
  }

  /// Creating a tenant is creating a **party** and giving it the `tenant` role.
  /// There is no tenant write path, and this method does not invent one.
  ///
  /// The two commands are not one transaction. If the role assignment fails the
  /// party is already there, so the outcome is reported as
  /// [TenantsActionPhase.partiallyApplied] with the party named — an existing
  /// record the user cannot see would be worse than an honest half-failure.
  Future<void> createTenant(PartyDraft draft) async {
    if (_applyMutationGate()) {
      return;
    }
    state = state.copyWith(
      actionPhase: TenantsActionPhase.submitting,
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
            roleType: PartyRoleType.tenant,
          ),
        );
        switch (assigned) {
          case PartyRepositorySuccess<PartyRoleDto>():
            await load();
            await select(value.id);
            state = state.copyWith(
              actionPhase: TenantsActionPhase.succeeded,
              actionMessage: 'Mieter angelegt.',
              versionConflict: null,
            );
          case PartyRepositoryFailure<PartyRoleDto>(:final message):
            // Deliberately not a rollback: deleting the party would be a delete
            // path this domain does not have, and would destroy an audited
            // record. The user is told what exists and what is missing.
            await load();
            state = state.copyWith(
              actionPhase: TenantsActionPhase.partiallyApplied,
              actionMessage:
                  '„${value.displayName}" wurde als Partei angelegt, aber die '
                  'Mieter-Rolle konnte nicht zugewiesen werden: $message. Die '
                  'Partei existiert und kann im Verzeichnis weiterbearbeitet '
                  'werden.',
              versionConflict: null,
            );
        }
    }
  }

  Future<void> updateTenant({
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
      successMessage: 'Mieter gespeichert.',
    );
  }

  /// Ends the tenant role rather than deleting anything. The party keeps its
  /// identity and its other roles; it simply leaves this role-scoped list.
  Future<void> endTenantRole({
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
        // The party is no longer a tenant, so it is no longer in this list.
        await select(null);
      },
      successMessage:
          'Mieter-Rolle beendet. Die Partei bleibt im Verzeichnis erhalten.',
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
      actionPhase: TenantsActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await command();
    switch (result) {
      case PartyRepositorySuccess<T>(:final value):
        await onSuccess(value);
        state = state.copyWith(
          actionPhase: TenantsActionPhase.succeeded,
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
        PartyRepositoryFailureKind.versionConflict => TenantsActionPhase.conflict,
        PartyRepositoryFailureKind.forbidden => TenantsActionPhase.forbidden,
        PartyRepositoryFailureKind.dependencyConflict =>
          TenantsActionPhase.readOnly,
        _ => TenantsActionPhase.failed,
      },
      actionMessage: message,
      versionConflict: versionConflict,
    );
  }

  bool _applyMutationGate() {
    if (isReadOnlyBackend) {
      state = state.copyWith(
        actionPhase: TenantsActionPhase.readOnly,
        actionMessage:
            'Mieter sind in der lokalen Datenbank schreibgeschützt, bis das '
            'Parteienverzeichnis migriert ist.',
        versionConflict: null,
      );
      return true;
    }
    if (!_scope.isResolved || !_authorization.can(partyManagePermission)) {
      state = state.copyWith(
        actionPhase: TenantsActionPhase.forbidden,
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

  /// Both contracts feed this screen, so both can invalidate it: a party write
  /// changes the list, a lease write changes the selected tenant's leases. They
  /// share one coalescing window, so a command that touches both — which is
  /// exactly what naming a tenant on a lease does — still causes one refetch.
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
    final leasingSource = _leasingInvalidationSource;
    if (leasingSource != null && _leasingSubscription == null) {
      _leasingSubscription = leasingSource
          .watchWorkspace(workspaceId: workspaceId)
          .listen((invalidation) {
            if (invalidation.workspaceId != _scope.workspaceId) {
              return;
            }
            // Only leases can change what this screen shows of the leasing
            // domain; units, cases and snapshots cannot.
            if (!invalidation.isReconciliation &&
                invalidation.aggregate != LeasingAggregate.lease) {
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
    unawaited(_leasingSubscription?.cancel());
    _leasingSubscription = null;
    super.dispose();
  }
}

final tenantsControllerProvider =
    StateNotifierProvider.autoDispose<TenantsController, TenantsState>((ref) {
      final controller = TenantsController(
        partyRepository: ref.watch(partyRepositoryProvider),
        partySearch: ref.watch(partySearchProvider),
        partyRoles: ref.watch(partyRoleProvider),
        leaseSearch: ref.watch(leaseSearchProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        partyInvalidationSource: ref.watch(partyQueryInvalidationSourceProvider),
        leasingInvalidationSource: ref.watch(
          leasingQueryInvalidationSourceProvider,
        ),
      );
      unawaited(controller.load());
      return controller;
    });
