/// Screen-facing orchestration for a property's activity timeline
/// (PROPERTY-ACTIVITY-01).
///
/// Filters are server-side, and that is the whole design. A domain or period
/// filter applied to the pages that happen to be in memory would report the
/// activity of a slice, not of the property — the same reason the audit
/// controller carries no filters at all. Changing a filter here therefore
/// discards the loaded pages and asks again.
///
/// The coverage statement travels with the page rather than being derived: how
/// many domains this membership can see is the server's answer, and a client
/// that recomputed it from its permission set would drift the moment the two
/// disagreed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/property_activity_dto.dart';
import 'audit_read_port.dart';
import 'platform_providers.dart';
import 'platform_repository.dart';

const Object _unchanged = Object();

enum PropertyActivityPhase {
  idle,
  loading,
  ready,
  empty,
  noMatch,
  forbidden,
  error,
}

class PropertyActivityState {
  const PropertyActivityState({
    this.phase = PropertyActivityPhase.idle,
    this.events = const <PropertyActivityEventDto>[],
    this.visibleDomains = const <PropertyActivityDomain>{},
    this.unknownDomainKeys = const <String>[],
    this.actorNamesVisible = false,
    this.selectedDomains = const <PropertyActivityDomain>{},
    this.asOf,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreMessage,
    this.message,
  });

  final PropertyActivityPhase phase;
  final List<PropertyActivityEventDto> events;

  /// What the server said this caller covers. Empty before the first answer;
  /// never assumed from the permission set.
  final Set<PropertyActivityDomain> visibleDomains;

  /// Domain keys a newer server named that this build cannot label.
  final List<String> unknownDomainKeys;

  final bool actorNamesVisible;

  /// The filter in force. Empty means every visible domain.
  final Set<PropertyActivityDomain> selectedDomains;

  final DateTime? asOf;
  final PropertyActivityCursor? nextCursor;

  final bool loadingMore;

  /// A failed *additional* page. The loaded events stay visible; only the
  /// load-more affordance reports it, because losing a page is not losing the
  /// timeline.
  final String? loadMoreMessage;

  final String? message;

  bool get hasMore => nextCursor != null;

  bool get isFiltered => selectedDomains.isNotEmpty;

  /// True when the caller sees fewer domains than the taxonomy has. The
  /// timeline then says so instead of reading as the whole history.
  bool get coverageIsPartial =>
      visibleDomains.length < PropertyActivityDomain.values.length ||
      unknownDomainKeys.isNotEmpty;

  PropertyActivityState copyWith({
    PropertyActivityPhase? phase,
    List<PropertyActivityEventDto>? events,
    Set<PropertyActivityDomain>? visibleDomains,
    List<String>? unknownDomainKeys,
    bool? actorNamesVisible,
    Set<PropertyActivityDomain>? selectedDomains,
    Object? asOf = _unchanged,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    Object? loadMoreMessage = _unchanged,
    Object? message = _unchanged,
  }) {
    return PropertyActivityState(
      phase: phase ?? this.phase,
      events: events ?? this.events,
      visibleDomains: visibleDomains ?? this.visibleDomains,
      unknownDomainKeys: unknownDomainKeys ?? this.unknownDomainKeys,
      actorNamesVisible: actorNamesVisible ?? this.actorNamesVisible,
      selectedDomains: selectedDomains ?? this.selectedDomains,
      asOf: identical(asOf, _unchanged) ? this.asOf : asOf as DateTime?,
      nextCursor: identical(nextCursor, _unchanged)
          ? this.nextCursor
          : nextCursor as PropertyActivityCursor?,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreMessage: identical(loadMoreMessage, _unchanged)
          ? this.loadMoreMessage
          : loadMoreMessage as String?,
      message: identical(message, _unchanged) ? this.message : message as String?,
    );
  }
}

class PropertyActivityController extends StateNotifier<PropertyActivityState> {
  PropertyActivityController({
    required this.propertyId,
    required AuditReadPort readPort,
    required WorkspaceSessionScope scope,
  }) : _readPort = readPort,
       _scope = scope,
       super(const PropertyActivityState());

  static const String propertyReadPermission = 'property.read';

  final String propertyId;
  final AuditReadPort _readPort;
  final WorkspaceSessionScope _scope;

  int _generation = 0;

  bool get canRead => _scope.permissions.contains(propertyReadPermission);

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      // Settled, not loading: nothing was asked, so nothing is in flight.
      state = state.copyWith(
        phase: PropertyActivityPhase.idle,
        events: const <PropertyActivityEventDto>[],
        nextCursor: null,
      );
      return;
    }
    if (!canRead) {
      state = state.copyWith(
        phase: PropertyActivityPhase.forbidden,
        events: const <PropertyActivityEventDto>[],
        nextCursor: null,
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(
      phase: PropertyActivityPhase.loading,
      message: null,
      loadMoreMessage: null,
    );
    final result = await _readPort.propertyActivity(
      PropertyActivityQuery(
        workspaceId: workspaceId,
        propertyId: propertyId,
        domains: state.selectedDomains,
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case PlatformRepositorySuccess<PropertyActivityPage>(:final value):
        state = state.copyWith(
          // An empty *filtered* timeline is a no-match, not an empty history.
          // Telling them apart is what decides whether the surface offers to
          // clear the filter or explains that nothing has happened yet.
          phase: value.events.isNotEmpty
              ? PropertyActivityPhase.ready
              : (state.selectedDomains.isEmpty
                    ? PropertyActivityPhase.empty
                    : PropertyActivityPhase.noMatch),
          events: value.events,
          visibleDomains: value.visibleDomains,
          unknownDomainKeys: value.unknownDomainKeys,
          actorNamesVisible: value.actorNamesVisible,
          asOf: value.asOf,
          nextCursor: value.nextCursor,
        );
      case PlatformRepositoryFailure<PropertyActivityPage>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase: kind == PlatformRepositoryFailureKind.forbidden
              ? PropertyActivityPhase.forbidden
              : PropertyActivityPhase.error,
          events: const <PropertyActivityEventDto>[],
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
    state = state.copyWith(loadingMore: true, loadMoreMessage: null);
    final result = await _readPort.propertyActivity(
      PropertyActivityQuery(
        workspaceId: workspaceId,
        propertyId: propertyId,
        domains: state.selectedDomains,
        cursor: cursor,
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case PlatformRepositorySuccess<PropertyActivityPage>(:final value):
        final known = state.events.map((event) => event.id).toSet();
        state = state.copyWith(
          loadingMore: false,
          events: <PropertyActivityEventDto>[
            ...state.events,
            for (final event in value.events)
              if (!known.contains(event.id)) event,
          ],
          nextCursor: value.nextCursor,
        );
      case PlatformRepositoryFailure<PropertyActivityPage>(:final message):
        // The loaded pages stay: a failed continuation is not a lost timeline.
        state = state.copyWith(loadingMore: false, loadMoreMessage: message);
    }
  }

  /// Applies a server-side domain filter. The loaded pages are dropped, since
  /// keeping them would mix a filtered page with an unfiltered one under one
  /// heading.
  Future<void> setDomains(Set<PropertyActivityDomain> domains) async {
    if (_sameDomains(domains, state.selectedDomains)) {
      return;
    }
    state = state.copyWith(
      selectedDomains: Set<PropertyActivityDomain>.unmodifiable(domains),
      events: const <PropertyActivityEventDto>[],
      nextCursor: null,
    );
    await load();
  }

  Future<void> toggleDomain(PropertyActivityDomain domain) {
    final next = <PropertyActivityDomain>{...state.selectedDomains};
    if (!next.remove(domain)) {
      next.add(domain);
    }
    return setDomains(next);
  }

  Future<void> clearFilter() => setDomains(const <PropertyActivityDomain>{});

  static bool _sameDomains(
    Set<PropertyActivityDomain> a,
    Set<PropertyActivityDomain> b,
  ) => a.length == b.length && a.containsAll(b);
}

final propertyActivityControllerProvider = StateNotifierProvider.autoDispose
    .family<PropertyActivityController, PropertyActivityState, String>((
      ref,
      propertyId,
    ) {
      final controller = PropertyActivityController(
        propertyId: propertyId,
        readPort: ref.watch(auditReadPortProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
      );
      controller.load();
      return controller;
    });
