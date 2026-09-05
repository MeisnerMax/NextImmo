/// Screen-facing orchestration for a property's audit trail (AUDIT-01).
///
/// One keyset-paginated list, newest first, plus the selected event. It holds
/// no filters yet: the read port offers none, and a client-side filter over the
/// pages that happen to be loaded would report a trail for the slice in memory
/// rather than for the property. Server-side filters (period, action, actor)
/// are named in `PROPERTY_AUDIT_V2.md` §11 and belong to the read port, not
/// here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/audit_event_dto.dart';
import 'audit_read_port.dart';
import 'platform_providers.dart';
import 'platform_repository.dart';

const Object _unchanged = Object();

enum PropertyAuditPhase { idle, loading, ready, empty, forbidden, error }

class PropertyAuditState {
  const PropertyAuditState({
    this.phase = PropertyAuditPhase.idle,
    this.events = const <AuditEventDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreMessage,
    this.selectedEventId,
    this.message,
  });

  final PropertyAuditPhase phase;
  final List<AuditEventDto> events;

  /// Null when the server reported no further page. Never inferred from a
  /// short page.
  final AuditEventCursor? nextCursor;

  final bool loadingMore;

  /// A failed *additional* page. The loaded events stay visible; only the
  /// load-more affordance reports it, because losing a page is not losing the
  /// trail.
  final String? loadMoreMessage;

  final String? selectedEventId;
  final String? message;

  bool get hasMore => nextCursor != null;

  AuditEventDto? get selectedEvent {
    final id = selectedEventId;
    if (id == null) {
      return null;
    }
    for (final event in events) {
      if (event.id == id) {
        return event;
      }
    }
    return null;
  }

  PropertyAuditState copyWith({
    PropertyAuditPhase? phase,
    List<AuditEventDto>? events,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    Object? loadMoreMessage = _unchanged,
    Object? selectedEventId = _unchanged,
    Object? message = _unchanged,
  }) {
    return PropertyAuditState(
      phase: phase ?? this.phase,
      events: events ?? this.events,
      nextCursor:
          identical(nextCursor, _unchanged)
              ? this.nextCursor
              : nextCursor as AuditEventCursor?,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreMessage:
          identical(loadMoreMessage, _unchanged)
              ? this.loadMoreMessage
              : loadMoreMessage as String?,
      selectedEventId:
          identical(selectedEventId, _unchanged)
              ? this.selectedEventId
              : selectedEventId as String?,
      message:
          identical(message, _unchanged) ? this.message : message as String?,
    );
  }
}

class PropertyAuditController extends StateNotifier<PropertyAuditState> {
  PropertyAuditController({
    required this.propertyId,
    required AuditReadPort readPort,
    required WorkspaceSessionScope scope,
  }) : _readPort = readPort,
       _scope = scope,
       super(const PropertyAuditState());

  static const String auditReadPermission = 'audit.read';

  final String propertyId;
  final AuditReadPort _readPort;
  final WorkspaceSessionScope _scope;

  int _generation = 0;

  bool get canRead => _scope.permissions.contains(auditReadPermission);

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    if (!canRead) {
      // The server would refuse anyway; saying so without the round trip keeps
      // the reason exact instead of reporting a generic failure.
      state = state.copyWith(
        phase: PropertyAuditPhase.forbidden,
        events: const <AuditEventDto>[],
        nextCursor: null,
        selectedEventId: null,
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(
      phase: PropertyAuditPhase.loading,
      message: null,
      loadMoreMessage: null,
    );
    final result = await _readPort.propertyAuditEvents(
      PropertyAuditQuery(workspaceId: workspaceId, propertyId: propertyId),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case PlatformRepositorySuccess<AuditEventPage>(:final value):
        state = state.copyWith(
          phase:
              value.events.isEmpty
                  ? PropertyAuditPhase.empty
                  : PropertyAuditPhase.ready,
          events: value.events,
          nextCursor: value.nextCursor,
          // A reload can drop the selected event out of the page; the
          // selection follows what is actually there.
          selectedEventId:
              value.events.any((event) => event.id == state.selectedEventId)
                  ? state.selectedEventId
                  : null,
        );
      case PlatformRepositoryFailure<AuditEventPage>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase:
              kind == PlatformRepositoryFailureKind.forbidden
                  ? PropertyAuditPhase.forbidden
                  : PropertyAuditPhase.error,
          events: const <AuditEventDto>[],
          nextCursor: null,
          selectedEventId: null,
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
    state = state.copyWith(loadingMore: true, loadMoreMessage: null);
    final result = await _readPort.propertyAuditEvents(
      PropertyAuditQuery(
        workspaceId: workspaceId,
        propertyId: propertyId,
        cursor: cursor,
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case PlatformRepositorySuccess<AuditEventPage>(:final value):
        final known = state.events.map((event) => event.id).toSet();
        state = state.copyWith(
          loadingMore: false,
          events: <AuditEventDto>[
            ...state.events,
            for (final event in value.events)
              if (!known.contains(event.id)) event,
          ],
          nextCursor: value.nextCursor,
        );
      case PlatformRepositoryFailure<AuditEventPage>(:final message):
        // The loaded pages stay: a failed continuation is not a lost trail.
        state = state.copyWith(loadingMore: false, loadMoreMessage: message);
    }
  }

  /// Selects an event from the loaded page. There is no read-by-id: the page
  /// already carries the whole published projection, so a second round trip
  /// would return exactly the same fields.
  void select(String? eventId) {
    state = state.copyWith(selectedEventId: eventId);
  }
}

final propertyAuditControllerProvider = StateNotifierProvider.autoDispose
    .family<PropertyAuditController, PropertyAuditState, String>((
      ref,
      propertyId,
    ) {
      final controller = PropertyAuditController(
        propertyId: propertyId,
        readPort: ref.watch(auditReadPortProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
      );
      controller.load();
      return controller;
    });
