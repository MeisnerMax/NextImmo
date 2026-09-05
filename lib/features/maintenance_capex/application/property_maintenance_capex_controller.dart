/// Screen-facing orchestration for the property-scoped maintenance_capex
/// panel (Welle 4, merges SCR-034 and the renovation half of SCR-031 — see
/// `04d_wave4_maintenance_capex.md` for why they are one panel, not two).
///
/// Two independently loadable zones (tickets, CapEx projects) so a failure in
/// one does not block the other — the same "pro-zone phases" shape
/// `PropertyDocumentsController` established for its requirement/document
/// split. Cloud-only: no read-only-backend phase, this panel never mounts
/// against the legacy SQLite adapter.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/authorization_port.dart';
import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/capex_project_dto.dart';
import '../domain/maintenance_ticket_dto.dart';
import 'maintenance_capex_providers.dart';
import 'maintenance_capex_query_invalidation_source.dart';
import 'maintenance_capex_repository.dart';

const Object _unchanged = Object();

enum PropertyMaintenanceZonePhase {
  idle,
  loading,
  ready,
  empty,
  forbidden,
  error,
}

enum PropertyMaintenanceActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,
  failed,
}

/// Phase of a single selected record's canonical read.
enum PropertyMaintenanceDetailPhase {
  idle,
  loading,
  ready,
  notFound,
  forbidden,
  error,
}

class PropertyMaintenanceCapexState {
  const PropertyMaintenanceCapexState({
    this.ticketsPhase = PropertyMaintenanceZonePhase.idle,
    this.tickets = const <MaintenanceTicketSummaryDto>[],
    this.ticketsMessage,
    this.ticketStatusFilter,
    this.ticketPriorityFilter,
    this.selectedTicketId,
    this.selectedTicket,
    this.ticketDetailPhase = PropertyMaintenanceDetailPhase.idle,
    this.ticketDetailMessage,
    this.capexPhase = PropertyMaintenanceZonePhase.idle,
    this.capexProjects = const <CapexProjectSummaryDto>[],
    this.capexMessage,
    this.capexStatusFilter,
    this.selectedProjectId,
    this.selectedProject,
    this.projectDetailPhase = PropertyMaintenanceDetailPhase.idle,
    this.projectDetailMessage,
    this.actionPhase = PropertyMaintenanceActionPhase.idle,
    this.actionMessage,
    this.ticketVersionConflict,
    this.projectVersionConflict,
  });

  final PropertyMaintenanceZonePhase ticketsPhase;
  final List<MaintenanceTicketSummaryDto> tickets;
  final String? ticketsMessage;

  /// Server-side ticket filters (`PROPERTY_OPERATIONS_V2.md` §4/§11). Null is
  /// "no filter"; the list never narrows a loaded page client-side.
  final MaintenanceTicketStatus? ticketStatusFilter;
  final MaintenanceTicketPriority? ticketPriorityFilter;

  /// The selected ticket, read canonically rather than taken from the list
  /// row: a summary is a projection, and a detail that edits must be the
  /// server's own snapshot including its version.
  final String? selectedTicketId;
  final MaintenanceTicketDto? selectedTicket;
  final PropertyMaintenanceDetailPhase ticketDetailPhase;
  final String? ticketDetailMessage;

  final PropertyMaintenanceZonePhase capexPhase;
  final List<CapexProjectSummaryDto> capexProjects;
  final String? capexMessage;
  final CapexProjectStatus? capexStatusFilter;

  final String? selectedProjectId;
  final CapexProjectDto? selectedProject;
  final PropertyMaintenanceDetailPhase projectDetailPhase;
  final String? projectDetailMessage;

  final PropertyMaintenanceActionPhase actionPhase;
  final String? actionMessage;
  final MaintenanceCapexVersionConflict? ticketVersionConflict;
  final MaintenanceCapexVersionConflict? projectVersionConflict;

  bool get hasTicketFilter =>
      ticketStatusFilter != null || ticketPriorityFilter != null;
  bool get hasCapexFilter => capexStatusFilter != null;

  PropertyMaintenanceCapexState copyWith({
    PropertyMaintenanceZonePhase? ticketsPhase,
    List<MaintenanceTicketSummaryDto>? tickets,
    Object? ticketsMessage = _unchanged,
    Object? ticketStatusFilter = _unchanged,
    Object? ticketPriorityFilter = _unchanged,
    Object? selectedTicketId = _unchanged,
    Object? selectedTicket = _unchanged,
    PropertyMaintenanceDetailPhase? ticketDetailPhase,
    Object? ticketDetailMessage = _unchanged,
    PropertyMaintenanceZonePhase? capexPhase,
    List<CapexProjectSummaryDto>? capexProjects,
    Object? capexMessage = _unchanged,
    Object? capexStatusFilter = _unchanged,
    Object? selectedProjectId = _unchanged,
    Object? selectedProject = _unchanged,
    PropertyMaintenanceDetailPhase? projectDetailPhase,
    Object? projectDetailMessage = _unchanged,
    PropertyMaintenanceActionPhase? actionPhase,
    Object? actionMessage = _unchanged,
    Object? ticketVersionConflict = _unchanged,
    Object? projectVersionConflict = _unchanged,
  }) {
    return PropertyMaintenanceCapexState(
      ticketsPhase: ticketsPhase ?? this.ticketsPhase,
      tickets: tickets ?? this.tickets,
      ticketsMessage:
          identical(ticketsMessage, _unchanged)
              ? this.ticketsMessage
              : ticketsMessage as String?,
      ticketStatusFilter:
          identical(ticketStatusFilter, _unchanged)
              ? this.ticketStatusFilter
              : ticketStatusFilter as MaintenanceTicketStatus?,
      ticketPriorityFilter:
          identical(ticketPriorityFilter, _unchanged)
              ? this.ticketPriorityFilter
              : ticketPriorityFilter as MaintenanceTicketPriority?,
      selectedTicketId:
          identical(selectedTicketId, _unchanged)
              ? this.selectedTicketId
              : selectedTicketId as String?,
      selectedTicket:
          identical(selectedTicket, _unchanged)
              ? this.selectedTicket
              : selectedTicket as MaintenanceTicketDto?,
      ticketDetailPhase: ticketDetailPhase ?? this.ticketDetailPhase,
      ticketDetailMessage:
          identical(ticketDetailMessage, _unchanged)
              ? this.ticketDetailMessage
              : ticketDetailMessage as String?,
      capexPhase: capexPhase ?? this.capexPhase,
      capexProjects: capexProjects ?? this.capexProjects,
      capexMessage:
          identical(capexMessage, _unchanged)
              ? this.capexMessage
              : capexMessage as String?,
      capexStatusFilter:
          identical(capexStatusFilter, _unchanged)
              ? this.capexStatusFilter
              : capexStatusFilter as CapexProjectStatus?,
      selectedProjectId:
          identical(selectedProjectId, _unchanged)
              ? this.selectedProjectId
              : selectedProjectId as String?,
      selectedProject:
          identical(selectedProject, _unchanged)
              ? this.selectedProject
              : selectedProject as CapexProjectDto?,
      projectDetailPhase: projectDetailPhase ?? this.projectDetailPhase,
      projectDetailMessage:
          identical(projectDetailMessage, _unchanged)
              ? this.projectDetailMessage
              : projectDetailMessage as String?,
      actionPhase: actionPhase ?? this.actionPhase,
      actionMessage:
          identical(actionMessage, _unchanged)
              ? this.actionMessage
              : actionMessage as String?,
      ticketVersionConflict:
          identical(ticketVersionConflict, _unchanged)
              ? this.ticketVersionConflict
              : ticketVersionConflict as MaintenanceCapexVersionConflict?,
      projectVersionConflict:
          identical(projectVersionConflict, _unchanged)
              ? this.projectVersionConflict
              : projectVersionConflict as MaintenanceCapexVersionConflict?,
    );
  }
}

typedef PropertyMaintenanceIdFactory = String Function();

class PropertyMaintenanceCapexController
    extends StateNotifier<PropertyMaintenanceCapexState> {
  PropertyMaintenanceCapexController({
    required this.propertyId,
    required MaintenanceTicketRepository ticketRepository,
    required MaintenanceTicketSearchPort ticketSearch,
    required CapexProjectRepository projectRepository,
    required CapexProjectSearchPort projectSearch,
    required WorkspaceSessionScope scope,
    MaintenanceCapexQueryInvalidationSource? invalidationSource,
    PropertyMaintenanceIdFactory? idFactory,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
  }) : _ticketRepository = ticketRepository,
       _ticketSearch = ticketSearch,
       _projectRepository = projectRepository,
       _projectSearch = projectSearch,
       _scope = scope,
       _invalidationSource = invalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       _coalesceWindow = invalidationCoalesceWindow,
       super(const PropertyMaintenanceCapexState());

  static const String maintenanceManagePermission = 'maintenance.manage';
  static const String capexManagePermission = 'capex.manage';
  static const String capexApprovePermission = 'capex.approve';

  final String propertyId;
  final MaintenanceTicketRepository _ticketRepository;
  final MaintenanceTicketSearchPort _ticketSearch;
  final CapexProjectRepository _projectRepository;
  final CapexProjectSearchPort _projectSearch;
  final WorkspaceSessionScope _scope;
  final MaintenanceCapexQueryInvalidationSource? _invalidationSource;
  final PropertyMaintenanceIdFactory _idFactory;
  final Duration _coalesceWindow;

  StreamSubscription<MaintenanceCapexQueryInvalidation>? _subscription;
  Timer? _invalidationTimer;
  int _ticketsGeneration = 0;
  int _capexGeneration = 0;
  int _ticketDetailGeneration = 0;
  int _projectDetailGeneration = 0;

  AuthorizationPort get _authorization => _scope.authorization;

  bool get canManageTickets =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _authorization.can(maintenanceManagePermission);

  bool get canManageCapex =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _authorization.can(capexManagePermission);

  bool get canApproveCapex =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _authorization.can(capexApprovePermission);

  Future<void> loadAll() async {
    _subscribeToInvalidation();
    await Future.wait(<Future<void>>[loadTickets(), loadCapexProjects()]);
  }

  Future<void> loadTickets() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_ticketsGeneration;
    state = state.copyWith(
      ticketsPhase: PropertyMaintenanceZonePhase.loading,
      ticketsMessage: null,
    );
    final result = await _ticketSearch.search(
      MaintenanceTicketListQuery(
        workspaceId: workspaceId,
        propertyId: propertyId,
        status: state.ticketStatusFilter,
        priority: state.ticketPriorityFilter,
      ),
    );
    if (generation != _ticketsGeneration) {
      return;
    }
    switch (result) {
      case MaintenanceCapexRepositorySuccess<List<MaintenanceTicketSummaryDto>>(
        :final value,
      ):
        state = state.copyWith(
          ticketsPhase:
              value.isEmpty
                  ? PropertyMaintenanceZonePhase.empty
                  : PropertyMaintenanceZonePhase.ready,
          tickets: value,
          ticketsMessage: null,
        );
      case MaintenanceCapexRepositoryFailure<List<MaintenanceTicketSummaryDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          ticketsPhase:
              kind == MaintenanceCapexRepositoryFailureKind.forbidden
                  ? PropertyMaintenanceZonePhase.forbidden
                  : PropertyMaintenanceZonePhase.error,
          tickets: const <MaintenanceTicketSummaryDto>[],
          ticketsMessage: message,
        );
    }
  }

  Future<void> loadCapexProjects() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_capexGeneration;
    state = state.copyWith(
      capexPhase: PropertyMaintenanceZonePhase.loading,
      capexMessage: null,
    );
    final result = await _projectSearch.search(
      CapexProjectListQuery(
        workspaceId: workspaceId,
        propertyId: propertyId,
        status: state.capexStatusFilter,
      ),
    );
    if (generation != _capexGeneration) {
      return;
    }
    switch (result) {
      case MaintenanceCapexRepositorySuccess<List<CapexProjectSummaryDto>>(
        :final value,
      ):
        state = state.copyWith(
          capexPhase:
              value.isEmpty
                  ? PropertyMaintenanceZonePhase.empty
                  : PropertyMaintenanceZonePhase.ready,
          capexProjects: value,
          capexMessage: null,
        );
      case MaintenanceCapexRepositoryFailure<List<CapexProjectSummaryDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          capexPhase:
              kind == MaintenanceCapexRepositoryFailureKind.forbidden
                  ? PropertyMaintenanceZonePhase.forbidden
                  : PropertyMaintenanceZonePhase.error,
          capexProjects: const <CapexProjectSummaryDto>[],
          capexMessage: message,
        );
    }
  }

  /// Applies the server-side ticket filters. A change re-reads the list; the
  /// client never narrows an already loaded page, because that would report a
  /// count for the loaded slice rather than for the property.
  Future<void> setTicketFilters({
    Object? status = _unchanged,
    Object? priority = _unchanged,
  }) async {
    final nextStatus =
        identical(status, _unchanged)
            ? state.ticketStatusFilter
            : status as MaintenanceTicketStatus?;
    final nextPriority =
        identical(priority, _unchanged)
            ? state.ticketPriorityFilter
            : priority as MaintenanceTicketPriority?;
    if (nextStatus == state.ticketStatusFilter &&
        nextPriority == state.ticketPriorityFilter) {
      return;
    }
    state = state.copyWith(
      ticketStatusFilter: nextStatus,
      ticketPriorityFilter: nextPriority,
    );
    await loadTickets();
  }

  Future<void> setCapexStatusFilter(CapexProjectStatus? status) async {
    if (status == state.capexStatusFilter) {
      return;
    }
    state = state.copyWith(capexStatusFilter: status);
    await loadCapexProjects();
  }

  /// Opens a ticket by reading it canonically. The list row is a summary; the
  /// detail — and anything that edits from it — must be the server's snapshot,
  /// version included.
  Future<void> selectTicket(String ticketId) async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_ticketDetailGeneration;
    state = state.copyWith(
      selectedTicketId: ticketId,
      selectedTicket: null,
      ticketDetailPhase: PropertyMaintenanceDetailPhase.loading,
      ticketDetailMessage: null,
    );
    final result = await _ticketRepository.getById(
      workspaceId: workspaceId,
      ticketId: ticketId,
    );
    if (generation != _ticketDetailGeneration) {
      return;
    }
    switch (result) {
      case MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>(
        :final value,
      ):
        state = state.copyWith(
          selectedTicket: value,
          ticketDetailPhase: PropertyMaintenanceDetailPhase.ready,
        );
      case MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          selectedTicket: null,
          ticketDetailPhase: switch (kind) {
            MaintenanceCapexRepositoryFailureKind.notFound =>
              PropertyMaintenanceDetailPhase.notFound,
            MaintenanceCapexRepositoryFailureKind.forbidden =>
              PropertyMaintenanceDetailPhase.forbidden,
            _ => PropertyMaintenanceDetailPhase.error,
          },
          ticketDetailMessage: message,
        );
    }
  }

  void clearTicketSelection() {
    _ticketDetailGeneration++;
    state = state.copyWith(
      selectedTicketId: null,
      selectedTicket: null,
      ticketDetailPhase: PropertyMaintenanceDetailPhase.idle,
      ticketDetailMessage: null,
    );
  }

  Future<void> selectProject(String projectId) async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_projectDetailGeneration;
    state = state.copyWith(
      selectedProjectId: projectId,
      selectedProject: null,
      projectDetailPhase: PropertyMaintenanceDetailPhase.loading,
      projectDetailMessage: null,
    );
    final result = await _projectRepository.getById(
      workspaceId: workspaceId,
      projectId: projectId,
    );
    if (generation != _projectDetailGeneration) {
      return;
    }
    switch (result) {
      case MaintenanceCapexRepositorySuccess<CapexProjectDto>(:final value):
        state = state.copyWith(
          selectedProject: value,
          projectDetailPhase: PropertyMaintenanceDetailPhase.ready,
        );
      case MaintenanceCapexRepositoryFailure<CapexProjectDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          selectedProject: null,
          projectDetailPhase: switch (kind) {
            MaintenanceCapexRepositoryFailureKind.notFound =>
              PropertyMaintenanceDetailPhase.notFound,
            MaintenanceCapexRepositoryFailureKind.forbidden =>
              PropertyMaintenanceDetailPhase.forbidden,
            _ => PropertyMaintenanceDetailPhase.error,
          },
          projectDetailMessage: message,
        );
    }
  }

  void clearProjectSelection() {
    _projectDetailGeneration++;
    state = state.copyWith(
      selectedProjectId: null,
      selectedProject: null,
      projectDetailPhase: PropertyMaintenanceDetailPhase.idle,
      projectDetailMessage: null,
    );
  }

  /// Edits the open ticket's attributes. Status is deliberately not editable
  /// here: it only moves through the audited transition contract.
  Future<void> updateTicket(MaintenanceTicketUpdateDto changes) async {
    final ticket = state.selectedTicket;
    if (ticket == null) {
      return;
    }
    if (!canManageTickets) {
      _forbidAction();
      return;
    }
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    state = state.copyWith(
      actionPhase: PropertyMaintenanceActionPhase.submitting,
      actionMessage: null,
      ticketVersionConflict: null,
    );
    final result = await _ticketRepository.update(
      UpdateMaintenanceTicketCommand(
        context: _commandContext(),
        ticketId: ticket.id,
        expectedVersion: ticket.version,
        changes: changes,
      ),
    );
    switch (result) {
      case MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>(
        :final value,
      ):
        // The canonical readback is what the detail shows from here on.
        state = state.copyWith(
          selectedTicket: value,
          ticketDetailPhase: PropertyMaintenanceDetailPhase.ready,
          actionPhase: PropertyMaintenanceActionPhase.succeeded,
          actionMessage: 'Ticket gespeichert.',
        );
        await loadTickets();
      case MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        _applyTicketFailure(kind, message, versionConflict);
    }
  }

  Future<void> updateCapexProject(CapexProjectUpdateDto changes) async {
    final project = state.selectedProject;
    if (project == null) {
      return;
    }
    if (!canManageCapex) {
      _forbidAction();
      return;
    }
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    state = state.copyWith(
      actionPhase: PropertyMaintenanceActionPhase.submitting,
      actionMessage: null,
      projectVersionConflict: null,
    );
    final result = await _projectRepository.update(
      UpdateCapexProjectCommand(
        context: _commandContext(),
        projectId: project.id,
        expectedVersion: project.version,
        changes: changes,
      ),
    );
    switch (result) {
      case MaintenanceCapexRepositorySuccess<CapexProjectDto>(:final value):
        state = state.copyWith(
          selectedProject: value,
          projectDetailPhase: PropertyMaintenanceDetailPhase.ready,
          actionPhase: PropertyMaintenanceActionPhase.succeeded,
          actionMessage: 'Projekt gespeichert.',
        );
        await loadCapexProjects();
      case MaintenanceCapexRepositoryFailure<CapexProjectDto>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        _applyProjectFailure(kind, message, versionConflict);
    }
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: PropertyMaintenanceActionPhase.idle,
      actionMessage: null,
      ticketVersionConflict: null,
      projectVersionConflict: null,
    );
  }

  Future<void> createTicket(MaintenanceTicketDraft draft) async {
    if (!canManageTickets) {
      _forbidAction();
      return;
    }
    state = state.copyWith(
      actionPhase: PropertyMaintenanceActionPhase.submitting,
      actionMessage: null,
    );
    final result = await _ticketRepository.create(
      CreateMaintenanceTicketCommand(context: _commandContext(), draft: draft),
    );
    switch (result) {
      case MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>():
        await loadTickets();
        state = state.copyWith(
          actionPhase: PropertyMaintenanceActionPhase.succeeded,
          actionMessage: 'Ticket angelegt.',
        );
      case MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        _applyTicketFailure(kind, message, versionConflict);
    }
  }

  Future<void> transitionTicket({
    required MaintenanceTicketSummaryDto ticket,
    required MaintenanceTicketStatus target,
    double? costActual,
  }) async {
    if (!canManageTickets) {
      _forbidAction();
      return;
    }
    state = state.copyWith(
      actionPhase: PropertyMaintenanceActionPhase.submitting,
      actionMessage: null,
    );
    final result = await _ticketRepository.transitionStatus(
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
        await loadTickets();
        state = state.copyWith(
          actionPhase: PropertyMaintenanceActionPhase.succeeded,
          actionMessage: 'Status aktualisiert.',
        );
      case MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        _applyTicketFailure(kind, message, versionConflict);
    }
  }

  Future<void> createCapexProject(CapexProjectDraft draft) async {
    if (!canManageCapex) {
      _forbidAction();
      return;
    }
    state = state.copyWith(
      actionPhase: PropertyMaintenanceActionPhase.submitting,
      actionMessage: null,
    );
    final result = await _projectRepository.create(
      CreateCapexProjectCommand(context: _commandContext(), draft: draft),
    );
    switch (result) {
      case MaintenanceCapexRepositorySuccess<CapexProjectDto>():
        await loadCapexProjects();
        state = state.copyWith(
          actionPhase: PropertyMaintenanceActionPhase.succeeded,
          actionMessage: 'CapEx-Projekt angelegt.',
        );
      case MaintenanceCapexRepositoryFailure<CapexProjectDto>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        _applyProjectFailure(kind, message, versionConflict);
    }
  }

  /// Entering [CapexProjectStatus.approved] needs `capex.approve`, checked
  /// server-side — [canApproveCapex] only lets the panel disable the
  /// affordance with an explanation up front, it is not the authority.
  Future<void> transitionCapexProject({
    required CapexProjectSummaryDto project,
    required CapexProjectStatus target,
    double? actualAmount,
  }) async {
    final requiresApprove = target == CapexProjectStatus.approved;
    if (requiresApprove ? !canApproveCapex : !canManageCapex) {
      _forbidAction();
      return;
    }
    state = state.copyWith(
      actionPhase: PropertyMaintenanceActionPhase.submitting,
      actionMessage: null,
    );
    final result = await _projectRepository.transitionStatus(
      TransitionCapexProjectStatusCommand(
        context: _commandContext(),
        projectId: project.id,
        expectedVersion: project.version,
        targetStatus: target,
        actualAmount: actualAmount,
      ),
    );
    switch (result) {
      case MaintenanceCapexRepositorySuccess<CapexProjectDto>():
        await loadCapexProjects();
        state = state.copyWith(
          actionPhase: PropertyMaintenanceActionPhase.succeeded,
          actionMessage: 'Status aktualisiert.',
        );
      case MaintenanceCapexRepositoryFailure<CapexProjectDto>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        _applyProjectFailure(kind, message, versionConflict);
    }
  }

  void _forbidAction() {
    state = state.copyWith(
      actionPhase: PropertyMaintenanceActionPhase.forbidden,
      actionMessage: 'Für diese Aktion fehlt die Berechtigung.',
    );
  }

  void _applyTicketFailure(
    MaintenanceCapexRepositoryFailureKind kind,
    String message,
    MaintenanceCapexVersionConflict? versionConflict,
  ) {
    state = state.copyWith(
      actionPhase: switch (kind) {
        MaintenanceCapexRepositoryFailureKind.versionConflict =>
          PropertyMaintenanceActionPhase.conflict,
        MaintenanceCapexRepositoryFailureKind.forbidden =>
          PropertyMaintenanceActionPhase.forbidden,
        _ => PropertyMaintenanceActionPhase.failed,
      },
      actionMessage: message,
      ticketVersionConflict: versionConflict,
    );
  }

  void _applyProjectFailure(
    MaintenanceCapexRepositoryFailureKind kind,
    String message,
    MaintenanceCapexVersionConflict? versionConflict,
  ) {
    state = state.copyWith(
      actionPhase: switch (kind) {
        MaintenanceCapexRepositoryFailureKind.versionConflict =>
          PropertyMaintenanceActionPhase.conflict,
        MaintenanceCapexRepositoryFailureKind.forbidden =>
          PropertyMaintenanceActionPhase.forbidden,
        _ => PropertyMaintenanceActionPhase.failed,
      },
      actionMessage: message,
      projectVersionConflict: versionConflict,
    );
  }

  MaintenanceCapexCommandContext _commandContext() {
    return MaintenanceCapexCommandContext(
      workspaceId: _scope.workspaceId!,
      actorId: _scope.actorId!,
      mutationId: _idFactory(),
      correlationId: _idFactory(),
    );
  }

  void _subscribeToInvalidation() {
    final workspaceId = _scope.workspaceId;
    final source = _invalidationSource;
    if (workspaceId == null || source == null || _subscription != null) {
      return;
    }
    _subscription = source.watchWorkspace(workspaceId: workspaceId).listen((
      invalidation,
    ) {
      if (invalidation.workspaceId != _scope.workspaceId) {
        return;
      }
      _scheduleInvalidationReload();
    });
  }

  void _scheduleInvalidationReload() {
    _invalidationTimer?.cancel();
    _invalidationTimer = Timer(_coalesceWindow, () {
      unawaited(loadTickets());
      unawaited(loadCapexProjects());
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

final propertyMaintenanceCapexControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      PropertyMaintenanceCapexController,
      PropertyMaintenanceCapexState,
      String
    >((ref, propertyId) {
      final controller = PropertyMaintenanceCapexController(
        propertyId: propertyId,
        ticketRepository: ref.watch(maintenanceTicketRepositoryProvider),
        ticketSearch: ref.watch(maintenanceTicketSearchProvider),
        projectRepository: ref.watch(capexProjectRepositoryProvider),
        projectSearch: ref.watch(capexProjectSearchProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        invalidationSource: ref.watch(
          maintenanceCapexQueryInvalidationSourceProvider,
        ),
      );
      unawaited(controller.loadAll());
      return controller;
    });
