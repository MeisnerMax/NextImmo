/// Screen-facing orchestration for the portfolio-wide maintenance ticket
/// surface (Welle 4, SCR-039).
///
/// Reads through [MaintenanceTicketSearchPort.searchWorkspace] — the P2-D06
/// follow-up RPC added specifically because this screen has no single
/// property to scope to (see `maintenance_capex_repository.dart`'s doc
/// comment on `WorkspaceMaintenanceTicketListQuery`). Mutations still go
/// through the ordinary per-ticket commands; only the read is workspace-wide.
///
/// Cloud-only (`04d_wave4_maintenance_capex.md`): no read-only-backend phase,
/// because this panel never mounts against the legacy SQLite adapter.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/authorization_port.dart';
import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/maintenance_ticket_dto.dart';
import 'maintenance_capex_providers.dart';
import 'maintenance_capex_query_invalidation_source.dart';
import 'maintenance_capex_repository.dart';

const Object _unchanged = Object();

enum MaintenanceTicketsListPhase { idle, loading, ready, empty, forbidden, error }

enum MaintenanceTicketsActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,
  failed,
}

class MaintenanceTicketsState {
  const MaintenanceTicketsState({
    required this.listPhase,
    this.actionPhase = MaintenanceTicketsActionPhase.idle,
    this.tickets = const <MaintenanceTicketSummaryDto>[],
    this.statusFilter,
    this.priorityFilter,
    this.versionConflict,
    this.message,
    this.actionMessage,
  });

  const MaintenanceTicketsState.loading()
    : this(listPhase: MaintenanceTicketsListPhase.loading);

  final MaintenanceTicketsListPhase listPhase;
  final MaintenanceTicketsActionPhase actionPhase;
  final List<MaintenanceTicketSummaryDto> tickets;
  final MaintenanceTicketStatus? statusFilter;
  final MaintenanceTicketPriority? priorityFilter;
  final MaintenanceCapexVersionConflict? versionConflict;
  final String? message;
  final String? actionMessage;

  MaintenanceTicketsState copyWith({
    MaintenanceTicketsListPhase? listPhase,
    MaintenanceTicketsActionPhase? actionPhase,
    List<MaintenanceTicketSummaryDto>? tickets,
    Object? statusFilter = _unchanged,
    Object? priorityFilter = _unchanged,
    Object? versionConflict = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
  }) {
    return MaintenanceTicketsState(
      listPhase: listPhase ?? this.listPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      tickets: tickets ?? this.tickets,
      statusFilter: identical(statusFilter, _unchanged)
          ? this.statusFilter
          : statusFilter as MaintenanceTicketStatus?,
      priorityFilter: identical(priorityFilter, _unchanged)
          ? this.priorityFilter
          : priorityFilter as MaintenanceTicketPriority?,
      versionConflict: identical(versionConflict, _unchanged)
          ? this.versionConflict
          : versionConflict as MaintenanceCapexVersionConflict?,
      message: identical(message, _unchanged) ? this.message : message as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
    );
  }
}

typedef MaintenanceTicketsIdFactory = String Function();

class MaintenanceTicketsController extends StateNotifier<MaintenanceTicketsState> {
  MaintenanceTicketsController({
    required MaintenanceTicketRepository repository,
    required MaintenanceTicketSearchPort search,
    required WorkspaceSessionScope scope,
    MaintenanceCapexQueryInvalidationSource? invalidationSource,
    MaintenanceTicketsIdFactory? idFactory,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
  }) : _repository = repository,
       _search = search,
       _scope = scope,
       _invalidationSource = invalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       _coalesceWindow = invalidationCoalesceWindow,
       super(const MaintenanceTicketsState.loading());

  static const String managePermission = 'maintenance.manage';

  final MaintenanceTicketRepository _repository;
  final MaintenanceTicketSearchPort _search;
  final WorkspaceSessionScope _scope;
  final MaintenanceCapexQueryInvalidationSource? _invalidationSource;
  final MaintenanceTicketsIdFactory _idFactory;
  final Duration _coalesceWindow;

  StreamSubscription<MaintenanceCapexQueryInvalidation>? _subscription;
  Timer? _invalidationTimer;
  int _generation = 0;

  AuthorizationPort get _authorization => _scope.authorization;

  bool get canMutate =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _authorization.can(managePermission);

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        listPhase: MaintenanceTicketsListPhase.idle,
        tickets: const <MaintenanceTicketSummaryDto>[],
        message: null,
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(
      listPhase: MaintenanceTicketsListPhase.loading,
      message: null,
    );
    final result = await _search.searchWorkspace(
      WorkspaceMaintenanceTicketListQuery(
        workspaceId: workspaceId,
        status: state.statusFilter,
        priority: state.priorityFilter,
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case MaintenanceCapexRepositorySuccess<List<MaintenanceTicketSummaryDto>>(
        :final value,
      ):
        state = state.copyWith(
          listPhase: value.isEmpty
              ? MaintenanceTicketsListPhase.empty
              : MaintenanceTicketsListPhase.ready,
          tickets: value,
          message: null,
        );
      case MaintenanceCapexRepositoryFailure<List<MaintenanceTicketSummaryDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          listPhase: kind == MaintenanceCapexRepositoryFailureKind.forbidden
              ? MaintenanceTicketsListPhase.forbidden
              : MaintenanceTicketsListPhase.error,
          tickets: const <MaintenanceTicketSummaryDto>[],
          message: message,
        );
    }
  }

  Future<void> updateFilters({
    Object? status = _unchanged,
    Object? priority = _unchanged,
  }) async {
    state = state.copyWith(statusFilter: status, priorityFilter: priority);
    await load();
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: MaintenanceTicketsActionPhase.idle,
      actionMessage: null,
      versionConflict: null,
    );
  }

  Future<void> createTicket(MaintenanceTicketDraft draft) async {
    if (_applyMutationGate()) {
      return;
    }
    state = state.copyWith(
      actionPhase: MaintenanceTicketsActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await _repository.create(
      CreateMaintenanceTicketCommand(context: _commandContext(), draft: draft),
    );
    switch (result) {
      case MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>():
        await load();
        state = state.copyWith(
          actionPhase: MaintenanceTicketsActionPhase.succeeded,
          actionMessage: 'Ticket angelegt.',
          versionConflict: null,
        );
      case MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        _applyFailure(kind, message, versionConflict);
    }
  }

  /// Only the lawful next steps from [ticket.status] should ever reach here —
  /// the panel offers [MaintenanceTicketStatus.allowedNextStatuses], the
  /// server is still the authority.
  Future<void> transition({
    required MaintenanceTicketSummaryDto ticket,
    required MaintenanceTicketStatus target,
    double? costActual,
  }) async {
    if (_applyMutationGate()) {
      return;
    }
    state = state.copyWith(
      actionPhase: MaintenanceTicketsActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await _repository.transitionStatus(
      TransitionMaintenanceTicketStatusCommand(
        context: _commandContext(),
        ticketId: ticket.id,
        expectedVersion: ticket.version,
        targetStatus: target,
        costActual: costActual,
      ),
    );
    switch (result) {
      case MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>():
        await load();
        state = state.copyWith(
          actionPhase: MaintenanceTicketsActionPhase.succeeded,
          actionMessage: 'Status aktualisiert.',
          versionConflict: null,
        );
      case MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        _applyFailure(kind, message, versionConflict);
    }
  }

  void _applyFailure(
    MaintenanceCapexRepositoryFailureKind kind,
    String message,
    MaintenanceCapexVersionConflict? versionConflict,
  ) {
    state = state.copyWith(
      actionPhase: switch (kind) {
        MaintenanceCapexRepositoryFailureKind.versionConflict =>
          MaintenanceTicketsActionPhase.conflict,
        MaintenanceCapexRepositoryFailureKind.forbidden =>
          MaintenanceTicketsActionPhase.forbidden,
        _ => MaintenanceTicketsActionPhase.failed,
      },
      actionMessage: message,
      versionConflict: versionConflict,
    );
  }

  bool _applyMutationGate() {
    if (!_scope.mutationsSupported ||
        !_scope.isResolved ||
        !_authorization.can(managePermission)) {
      state = state.copyWith(
        actionPhase: MaintenanceTicketsActionPhase.forbidden,
        actionMessage: 'Für diese Aktion fehlt die Berechtigung.',
        versionConflict: null,
      );
      return true;
    }
    return false;
  }

  MaintenanceCapexCommandContext _commandContext() {
    return MaintenanceCapexCommandContext(
      workspaceId: _scope.workspaceId!,
      actorId: _scope.actorId!,
      mutationId: _idFactory(),
      correlationId: _idFactory(),
    );
  }

  void _subscribeToInvalidation(String workspaceId) {
    final source = _invalidationSource;
    if (source == null || _subscription != null) {
      return;
    }
    _subscription = source.watchWorkspace(workspaceId: workspaceId).listen((
      invalidation,
    ) {
      if (invalidation.workspaceId != _scope.workspaceId) {
        return;
      }
      if (!invalidation.isReconciliation &&
          invalidation.aggregate != MaintenanceCapexAggregate.maintenanceTicket) {
        return;
      }
      _scheduleInvalidationReload();
    });
  }

  void _scheduleInvalidationReload() {
    _invalidationTimer?.cancel();
    _invalidationTimer = Timer(_coalesceWindow, () {
      unawaited(load());
    });
  }

  @override
  void dispose() {
    _invalidationTimer?.cancel();
    _invalidationTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}

final maintenanceTicketsControllerProvider = StateNotifierProvider.autoDispose<
  MaintenanceTicketsController,
  MaintenanceTicketsState
>((ref) {
  final controller = MaintenanceTicketsController(
    repository: ref.watch(maintenanceTicketRepositoryProvider),
    search: ref.watch(maintenanceTicketSearchProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
    invalidationSource: ref.watch(maintenanceCapexQueryInvalidationSourceProvider),
  );
  unawaited(controller.load());
  return controller;
});
