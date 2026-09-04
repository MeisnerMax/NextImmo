/// Screen-facing orchestration for the Notification Inbox
/// (NOTIFICATION-INBOX-01, NOTIFICATIONS-V2) and the CloudTopBar bell — one
/// controller feeds both, so the badge and the Ungelesen tab can never tell
/// two different stories.
///
/// The OD-2 rule governs the surface: `NotificationFeedQuery` carries exactly
/// `recipientUserId`, `unreadOnly` and the keyset page — so the state offers
/// exactly the two tabs and nothing else. There is no kind/context/time
/// filter, no search, no "mark all read" and **no count RPC**: the badge
/// shows the exact number up to one page and "50+" beyond it, never an
/// invented total. [notificationInboxOfferedControls] is the machine-checkable
/// registry the §17 pretense-regression test verifies.
///
/// The recipient is **always** the signed-in user (§6.2): reading foreign
/// inboxes is no product feature of this surface, whatever the RLS policy
/// would allow a `notification.read` holder.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/notification_dto.dart';
import 'platform_providers.dart';
import 'platform_query_invalidation_source.dart';
import 'platform_repository.dart';

const Object _unchanged = Object();

/// The §17 registry of everything the inbox offers as a list control, named
/// with the `NotificationFeedQuery` field that serves it.
const List<({String control, String queryField})>
notificationInboxOfferedControls = [
  (control: 'unreadOnly', queryField: 'unreadOnly'),
];

/// Identifies the workspace/actor a [NotificationInboxController] is bound
/// to. Value equality keeps the Riverpod family stable, which also makes the
/// CloudTopBar bell and the inbox page share one controller instance.
class NotificationInboxScope {
  NotificationInboxScope({
    required this.workspaceId,
    required this.actorId,
    required Set<String> permissions,
    required this.canMutate,
  }) : permissions = Set<String>.unmodifiable(permissions);

  final String? workspaceId;
  final String? actorId;
  final Set<String> permissions;

  /// Whether the session is at AAL2 (DEC-025 gates every platform read and
  /// mutation; at aal1 the feed is empty by policy and must render as the
  /// step-up state, never as an empty inbox).
  final bool canMutate;

  /// PERMISSION-CATALOG-02: the inbox reads the member's OWN feed, which the
  /// server serves recipient-scoped without any permission
  /// (notifications_select_own_or_read). A bound scope is therefore always
  /// readable; `notification.read` remains the admin-only workspace oversight
  /// capability and is deliberately not consulted here.
  bool get canRead => workspaceId != null && actorId != null;

  @override
  bool operator ==(Object other) {
    return other is NotificationInboxScope &&
        other.workspaceId == workspaceId &&
        other.actorId == actorId &&
        other.canMutate == canMutate &&
        other.permissions.length == permissions.length &&
        other.permissions.containsAll(permissions);
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    actorId,
    canMutate,
    Object.hashAllUnordered(permissions),
  );
}

enum NotificationFeedPhase { loading, ready, forbidden, error }

/// One keyset feed (the Ungelesen slice doubles as the badge source).
class NotificationFeedSlice {
  const NotificationFeedSlice({
    this.phase = NotificationFeedPhase.loading,
    this.items = const <NotificationDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.loaded = false,
    this.message,
  });

  final NotificationFeedPhase phase;
  final List<NotificationDto> items;
  final String? nextCursor;
  final bool loadingMore;

  /// Whether this slice was ever requested — the Alle tab loads lazily.
  final bool loaded;
  final String? message;

  NotificationFeedSlice copyWith({
    NotificationFeedPhase? phase,
    List<NotificationDto>? items,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    bool? loaded,
    Object? message = _unchanged,
  }) {
    return NotificationFeedSlice(
      phase: phase ?? this.phase,
      items: items ?? this.items,
      nextCursor: identical(nextCursor, _unchanged)
          ? this.nextCursor
          : nextCursor as String?,
      loadingMore: loadingMore ?? this.loadingMore,
      loaded: loaded ?? this.loaded,
      message: identical(message, _unchanged)
          ? this.message
          : message as String?,
    );
  }
}

enum NotificationActionPhase { idle, succeeded, failed }

class NotificationInboxState {
  const NotificationInboxState({
    this.unread = const NotificationFeedSlice(),
    this.all = const NotificationFeedSlice(),
    this.unreadOnly = true,
    this.selectedId,
    this.refreshing = false,
    this.liveUpdatesDegraded = false,
    this.actionPhase = NotificationActionPhase.idle,
    this.actionMessage,
  });

  /// Always maintained: it is the badge source and the default tab (§2 —
  /// the inbox is an action list and opens on Ungelesen).
  final NotificationFeedSlice unread;
  final NotificationFeedSlice all;

  /// The active tab: true = Ungelesen (default), false = Alle.
  final bool unreadOnly;

  final String? selectedId;
  final bool refreshing;
  final bool liveUpdatesDegraded;
  final NotificationActionPhase actionPhase;
  final String? actionMessage;

  NotificationFeedSlice get active => unreadOnly ? unread : all;

  NotificationDto? get selected {
    if (selectedId == null) {
      return null;
    }
    for (final slice in <NotificationFeedSlice>[unread, all]) {
      for (final item in slice.items) {
        if (item.id == selectedId) {
          return item;
        }
      }
    }
    return null;
  }

  /// The honest badge: exactly the unread rows of the loaded page. There is
  /// no count RPC, so above one page the badge caps (§9/A14).
  int get unreadBadgeCount =>
      unread.items.where((item) => item.readAt == null).length;

  bool get unreadBadgeCapped => unread.nextCursor != null;

  /// "3" or "50+" — never an invented total.
  String get unreadBadgeLabel =>
      unreadBadgeCapped ? '$unreadBadgeCount+' : '$unreadBadgeCount';

  NotificationInboxState copyWith({
    NotificationFeedSlice? unread,
    NotificationFeedSlice? all,
    bool? unreadOnly,
    Object? selectedId = _unchanged,
    bool? refreshing,
    bool? liveUpdatesDegraded,
    NotificationActionPhase? actionPhase,
    Object? actionMessage = _unchanged,
  }) {
    return NotificationInboxState(
      unread: unread ?? this.unread,
      all: all ?? this.all,
      unreadOnly: unreadOnly ?? this.unreadOnly,
      selectedId: identical(selectedId, _unchanged)
          ? this.selectedId
          : selectedId as String?,
      refreshing: refreshing ?? this.refreshing,
      liveUpdatesDegraded: liveUpdatesDegraded ?? this.liveUpdatesDegraded,
      actionPhase: actionPhase ?? this.actionPhase,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
    );
  }
}

class NotificationInboxController
    extends StateNotifier<NotificationInboxState> {
  NotificationInboxController({
    required NotificationPort notifications,
    required NotificationInboxScope scope,
    PlatformQueryInvalidationSource? invalidationSource,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
    String Function()? idFactory,
  }) : _notifications = notifications,
       _scope = scope,
       _invalidationSource = invalidationSource,
       _coalesceWindow = invalidationCoalesceWindow,
       _idFactory = idFactory ?? const Uuid().v4,
       super(const NotificationInboxState());

  final NotificationPort _notifications;
  final NotificationInboxScope _scope;
  final PlatformQueryInvalidationSource? _invalidationSource;
  final Duration _coalesceWindow;
  final String Function() _idFactory;

  StreamSubscription<PlatformQueryInvalidation>? _invalidationSubscription;
  Timer? _invalidationTimer;

  /// One staleness token **per slice**: a reload() runs both slice requests
  /// in parallel, and a global counter would let the second request's start
  /// invalidate the first request's result — leaving the unread slice (and
  /// with it the A14 bell badge) silently stale. A newer unread request
  /// invalidates only an older unread request, an all request only an older
  /// all request; cross-slice requests never cancel each other.
  int _unreadGeneration = 0;
  int _allGeneration = 0;

  int _bumpGeneration({required bool unreadOnly}) =>
      unreadOnly ? ++_unreadGeneration : ++_allGeneration;

  int _currentGeneration({required bool unreadOnly}) =>
      unreadOnly ? _unreadGeneration : _allGeneration;

  NotificationInboxScope get scope => _scope;

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    _subscribeToInvalidation(workspaceId);
    await _loadSlice(unreadOnly: true);
  }

  Future<void> setTab({required bool unreadOnly}) async {
    if (state.unreadOnly == unreadOnly) {
      return;
    }
    state = state.copyWith(unreadOnly: unreadOnly);
    final slice = unreadOnly ? state.unread : state.all;
    if (!slice.loaded) {
      await _loadSlice(unreadOnly: unreadOnly);
    }
  }

  /// Reloads every loaded slice; with [background] visible data stays and
  /// only the refresh indicator flips.
  Future<void> reload({bool background = false}) async {
    final futures = <Future<void>>[
      _loadSlice(unreadOnly: true, background: background),
      if (state.all.loaded)
        _loadSlice(unreadOnly: false, background: background),
    ];
    await Future.wait(futures);
  }

  Future<void> _loadSlice({
    required bool unreadOnly,
    bool background = false,
  }) async {
    final workspaceId = _scope.workspaceId;
    final actorId = _scope.actorId;
    if (workspaceId == null || actorId == null) {
      return;
    }
    final generation = _bumpGeneration(unreadOnly: unreadOnly);
    final before = unreadOnly ? state.unread : state.all;
    _setSlice(
      unreadOnly,
      background
          ? before
          : before.copyWith(
              phase: NotificationFeedPhase.loading,
              message: null,
            ),
      refreshing: background,
    );
    final result = await _notifications.notificationFeed(
      NotificationFeedQuery(
        workspaceId: workspaceId,
        // §6.2: always the signed-in user. Reading foreign inboxes is not a
        // feature of this surface.
        recipientUserId: actorId,
        unreadOnly: unreadOnly,
      ),
    );
    if (generation != _currentGeneration(unreadOnly: unreadOnly) ||
        !mounted) {
      return;
    }
    switch (result) {
      case PlatformRepositoryFailure<PlatformPageResult<NotificationDto>>(
        :final kind,
        :final message,
      ):
        _setSlice(
          unreadOnly,
          NotificationFeedSlice(
            phase: kind == PlatformRepositoryFailureKind.forbidden
                ? NotificationFeedPhase.forbidden
                : NotificationFeedPhase.error,
            loaded: true,
            message: message,
          ),
          refreshing: false,
        );
      case PlatformRepositorySuccess<PlatformPageResult<NotificationDto>>(
        :final value,
      ):
        _setSlice(
          unreadOnly,
          NotificationFeedSlice(
            phase: NotificationFeedPhase.ready,
            items: value.items,
            nextCursor: value.nextCursor,
            loaded: true,
          ),
          refreshing: false,
        );
    }
  }

  Future<void> loadMore() async {
    final workspaceId = _scope.workspaceId;
    final actorId = _scope.actorId;
    final unreadOnly = state.unreadOnly;
    final slice = state.active;
    final cursor = slice.nextCursor;
    if (workspaceId == null ||
        actorId == null ||
        cursor == null ||
        slice.loadingMore) {
      return;
    }
    // No bump: a reload of the same slice that starts during this page
    // fetch supersedes it, exactly as before — but only within its slice.
    final generation = _currentGeneration(unreadOnly: unreadOnly);
    _setSlice(unreadOnly, slice.copyWith(loadingMore: true));
    final result = await _notifications.notificationFeed(
      NotificationFeedQuery(
        workspaceId: workspaceId,
        recipientUserId: actorId,
        unreadOnly: unreadOnly,
        page: PlatformPageRequest(cursor: cursor),
      ),
    );
    if (generation != _currentGeneration(unreadOnly: unreadOnly) ||
        !mounted) {
      return;
    }
    final current = unreadOnly ? state.unread : state.all;
    switch (result) {
      case PlatformRepositoryFailure<PlatformPageResult<NotificationDto>>(
        :final message,
      ):
        _setSlice(unreadOnly, current.copyWith(loadingMore: false));
        state = state.copyWith(
          actionPhase: NotificationActionPhase.failed,
          actionMessage: message,
        );
      case PlatformRepositorySuccess<PlatformPageResult<NotificationDto>>(
        :final value,
      ):
        _setSlice(
          unreadOnly,
          current.copyWith(
            loadingMore: false,
            items: <NotificationDto>[...current.items, ...value.items],
            nextCursor: value.nextCursor,
          ),
        );
    }
  }

  void _setSlice(
    bool unreadOnly,
    NotificationFeedSlice slice, {
    bool? refreshing,
  }) {
    state = unreadOnly
        ? state.copyWith(unread: slice, refreshing: refreshing)
        : state.copyWith(all: slice, refreshing: refreshing);
  }

  // ---------------------------------------------------------------------------
  // Detail
  // ---------------------------------------------------------------------------

  void select(NotificationDto notification) {
    state = state.copyWith(selectedId: notification.id);
  }

  void closeDetail() {
    state = state.copyWith(selectedId: null);
  }

  // ---------------------------------------------------------------------------
  // Read semantics (A12)
  // ---------------------------------------------------------------------------

  /// Marks [notification] read: optimistic (the row restyles immediately,
  /// the badge decrements), idempotent (an already-read row is a no-op), and
  /// `not_found` removes the row with "nicht mehr verfügbar" — never
  /// "Kein Zugriff" (§6.3). A failure rolls the row back.
  Future<void> markRead(NotificationDto notification) async {
    final workspaceId = _scope.workspaceId;
    final actorId = _scope.actorId;
    if (workspaceId == null || actorId == null) {
      return;
    }
    final current = _find(notification.id);
    if (current == null || current.readAt != null) {
      return;
    }
    _replaceRow(_withReadAt(current, DateTime.now().toUtc()));
    final result = await _notifications.markNotificationRead(
      MarkNotificationReadCommand(
        context: PlatformCommandContext(
          workspaceId: workspaceId,
          actorId: actorId,
          // Marking read is monotonic and idempotent server-side, so each
          // attempt may carry a fresh intent id without any replay hazard.
          mutationId: _idFactory(),
          correlationId: _idFactory(),
          reason: 'Als gelesen markiert (Inbox)',
        ),
        notificationId: notification.id,
      ),
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case PlatformRepositorySuccess<NotificationDto>(:final value):
        _replaceRow(value);
      case PlatformRepositoryFailure<NotificationDto>(
        :final kind,
        :final message,
      ):
        if (kind == PlatformRepositoryFailureKind.notFound) {
          _removeRow(notification.id);
          state = state.copyWith(
            actionPhase: NotificationActionPhase.failed,
            actionMessage: 'Diese Mitteilung ist nicht mehr verfügbar.',
            selectedId: state.selectedId == notification.id
                ? null
                : state.selectedId,
          );
        } else {
          _replaceRow(current);
          state = state.copyWith(
            actionPhase: NotificationActionPhase.failed,
            actionMessage: message,
          );
        }
    }
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: NotificationActionPhase.idle,
      actionMessage: null,
    );
  }

  NotificationDto? _find(String id) {
    for (final slice in <NotificationFeedSlice>[state.unread, state.all]) {
      for (final item in slice.items) {
        if (item.id == id) {
          return item;
        }
      }
    }
    return null;
  }

  NotificationDto _withReadAt(NotificationDto row, DateTime? readAt) {
    return NotificationDto(
      id: row.id,
      workspaceId: row.workspaceId,
      recipientUserId: row.recipientUserId,
      kind: row.kind,
      title: row.title,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      createdBy: row.createdBy,
      updatedBy: row.updatedBy,
      version: row.version,
      body: row.body,
      entity: row.entity,
      readAt: readAt,
    );
  }

  void _replaceRow(NotificationDto row) {
    NotificationFeedSlice patch(NotificationFeedSlice slice) {
      return slice.copyWith(
        items: <NotificationDto>[
          for (final item in slice.items)
            if (item.id == row.id) row else item,
        ],
      );
    }

    state = state.copyWith(
      unread: patch(state.unread),
      all: patch(state.all),
    );
  }

  void _removeRow(String id) {
    NotificationFeedSlice patch(NotificationFeedSlice slice) {
      return slice.copyWith(
        items: <NotificationDto>[
          for (final item in slice.items)
            if (item.id != id) item,
        ],
      );
    }

    state = state.copyWith(
      unread: patch(state.unread),
      all: patch(state.all),
    );
  }

  // ---------------------------------------------------------------------------
  // Realtime (§9)
  // ---------------------------------------------------------------------------

  void _subscribeToInvalidation(String workspaceId) {
    final source = _invalidationSource;
    if (source == null || _invalidationSubscription != null) {
      return;
    }
    _invalidationSubscription = source
        .watchWorkspace(workspaceId: workspaceId)
        .listen(
          (invalidation) {
            if (invalidation.workspaceId != _scope.workspaceId) {
              return;
            }
            if (!invalidation.isReconciliation &&
                invalidation.aggregate != PlatformAggregate.notification) {
              return;
            }
            if (mounted && state.liveUpdatesDegraded) {
              state = state.copyWith(liveUpdatesDegraded: false);
            }
            _scheduleInvalidationReload();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (mounted) {
              state = state.copyWith(liveUpdatesDegraded: true);
            }
          },
        );
  }

  /// `notification.fanned_out` invalidates workspace-wide without an
  /// aggregate id; the feed refetches its own rows. Bursts — up to three
  /// reconciles after a reconnect — coalesce into exactly one reload.
  void _scheduleInvalidationReload() {
    _invalidationTimer?.cancel();
    _invalidationTimer = Timer(_coalesceWindow, () {
      unawaited(reload(background: true));
    });
  }

  @override
  void dispose() {
    _invalidationTimer?.cancel();
    _invalidationTimer = null;
    unawaited(_invalidationSubscription?.cancel());
    _invalidationSubscription = null;
    super.dispose();
  }
}

final notificationInboxControllerProvider = StateNotifierProvider.autoDispose
    .family<
      NotificationInboxController,
      NotificationInboxState,
      NotificationInboxScope
    >((ref, scope) {
      final controller = NotificationInboxController(
        notifications: ref.watch(notificationPortProvider),
        scope: scope,
        invalidationSource: ref.watch(platformQueryInvalidationSourceProvider),
      );
      unawaited(controller.load());
      return controller;
    });
