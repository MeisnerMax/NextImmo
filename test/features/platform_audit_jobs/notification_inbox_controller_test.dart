import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/notification_inbox_controller.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_query_invalidation_source.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/notification_dto.dart';

const String _workspace = 'workspace-a';
const String _actor = 'user-1';

NotificationDto _notification({
  String id = 'note-a',
  DateTime? readAt,
  DateTime? createdAt,
}) {
  final stamp = createdAt ?? DateTime.utc(2026, 9, 1, 8);
  return NotificationDto(
    id: id,
    workspaceId: _workspace,
    recipientUserId: _actor,
    kind: 'task.assigned',
    title: 'Mitteilung $id',
    createdAt: stamp,
    updatedAt: stamp,
    createdBy: 'user-2',
    updatedBy: 'user-2',
    version: 1,
    readAt: readAt,
  );
}

PlatformRepositorySuccess<PlatformPageResult<NotificationDto>> _page(
  List<NotificationDto> items, {
  String? nextCursor,
}) {
  return PlatformRepositorySuccess<PlatformPageResult<NotificationDto>>(
    PlatformPageResult<NotificationDto>(items: items, nextCursor: nextCursor),
  );
}

class _FakeNotifications implements NotificationPort {
  final List<NotificationFeedQuery> queries = <NotificationFeedQuery>[];
  final List<MarkNotificationReadCommand> marks =
      <MarkNotificationReadCommand>[];

  PlatformRepositoryResult<PlatformPageResult<NotificationDto>> Function(
    NotificationFeedQuery query,
  )?
  onFeed;
  PlatformRepositoryResult<NotificationDto> Function(
    MarkNotificationReadCommand command,
  )?
  onMarkRead;

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<NotificationDto>>>
  notificationFeed(NotificationFeedQuery query) async {
    queries.add(query);
    return onFeed?.call(query) ?? _page(const <NotificationDto>[]);
  }

  @override
  Future<PlatformRepositoryResult<NotificationDto>> markNotificationRead(
    MarkNotificationReadCommand command,
  ) async {
    marks.add(command);
    return onMarkRead?.call(command) ??
        PlatformRepositorySuccess<NotificationDto>(
          _notification(
            id: command.notificationId,
            readAt: DateTime.utc(2026, 9, 3, 12),
          ),
        );
  }

  @override
  Future<PlatformRepositoryResult<NotificationFanOutReceipt>>
  fanOutNotification(CreateNotificationCommand command) {
    throw UnimplementedError('The inbox never creates notifications.');
  }
}

class _FakeInvalidation implements PlatformQueryInvalidationSource {
  final StreamController<PlatformQueryInvalidation> controller =
      StreamController<PlatformQueryInvalidation>.broadcast();

  @override
  Stream<PlatformQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) => controller.stream;
}

NotificationInboxScope _scope() {
  return NotificationInboxScope(
    workspaceId: _workspace,
    actorId: _actor,
    permissions: const <String>{'notification.read'},
    canMutate: true,
  );
}

({
  NotificationInboxController controller,
  _FakeNotifications port,
  _FakeInvalidation inv,
})
_build() {
  final port = _FakeNotifications();
  final inv = _FakeInvalidation();
  var counter = 0;
  final controller = NotificationInboxController(
    notifications: port,
    scope: _scope(),
    invalidationSource: inv,
    invalidationCoalesceWindow: Duration.zero,
    idFactory: () => 'gen-${counter++}',
  );
  addTearDown(controller.dispose);
  addTearDown(inv.controller.close);
  return (controller: controller, port: port, inv: inv);
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('OD-2 pretense regression (§17)', () {
    test('every offered control maps onto a NotificationFeedQuery field', () {
      // The full server capability set, pinned by name: recipient, the
      // unread toggle and the keyset page. The recipient is fixed to the
      // signed-in user and the page is machinery — the single user-facing
      // control is the tab pair.
      const contractFields = <String>{'recipientUserId', 'unreadOnly', 'page'};
      expect(notificationInboxOfferedControls, hasLength(1));
      for (final offered in notificationInboxOfferedControls) {
        expect(contractFields.contains(offered.queryField), isTrue);
      }
      // No kind/context/time filter and no search is offered (B15).
      expect(
        notificationInboxOfferedControls.map((entry) => entry.control),
        isNot(
          anyElement(
            anyOf(
              contains('kind'),
              contains('entity'),
              contains('search'),
              contains('range'),
            ),
          ),
        ),
      );
    });

    test('the badge caps at the page size instead of inventing a total', () {
      final many = <NotificationDto>[
        for (var index = 0; index < 50; index++)
          _notification(id: 'note-$index'),
      ];
      final capped = NotificationInboxState(
        unread: NotificationFeedSlice(
          phase: NotificationFeedPhase.ready,
          items: many,
          nextCursor: 'more',
          loaded: true,
        ),
      );
      expect(capped.unreadBadgeLabel, '50+');
      expect(capped.unreadBadgeCapped, isTrue);

      final exact = NotificationInboxState(
        unread: NotificationFeedSlice(
          phase: NotificationFeedPhase.ready,
          items: many.take(3).toList(),
          loaded: true,
        ),
      );
      expect(exact.unreadBadgeLabel, '3');
      expect(exact.unreadBadgeCapped, isFalse);
    });
  });

  group('feed (A11)', () {
    test('every query carries the signed-in user as recipient (§6.2)', () async {
      final harness = _build();
      harness.port.onFeed = (query) =>
          _page(<NotificationDto>[_notification()], nextCursor: 'cursor-1');
      await harness.controller.load();
      await harness.controller.setTab(unreadOnly: false);
      await harness.controller.loadMore();
      await harness.controller.reload();

      expect(harness.port.queries, isNotEmpty);
      expect(
        harness.port.queries.every((query) => query.recipientUserId == _actor),
        isTrue,
      );
    });

    test('opens on the Ungelesen tab and loads Alle lazily', () async {
      final harness = _build();
      await harness.controller.load();

      expect(harness.controller.state.unreadOnly, isTrue);
      expect(harness.port.queries.single.unreadOnly, isTrue);
      expect(harness.controller.state.all.loaded, isFalse);

      await harness.controller.setTab(unreadOnly: false);
      expect(harness.port.queries.last.unreadOnly, isFalse);
      expect(harness.controller.state.all.loaded, isTrue);
    });

    test('loadMore consumes the cursor of the active tab', () async {
      final harness = _build();
      harness.port.onFeed = (query) => query.page.cursor == null
          ? _page(<NotificationDto>[_notification(id: 'note-1')],
              nextCursor: 'cursor-1')
          : _page(<NotificationDto>[_notification(id: 'note-2')]);
      await harness.controller.load();
      await harness.controller.loadMore();

      expect(harness.port.queries.last.page.cursor, 'cursor-1');
      expect(
        harness.controller.state.unread.items.map((item) => item.id),
        <String>['note-1', 'note-2'],
      );
    });

    test('a forbidden read lands in the forbidden phase', () async {
      final harness = _build();
      harness.port.onFeed = (_) =>
          const PlatformRepositoryFailure<PlatformPageResult<NotificationDto>>(
            kind: PlatformRepositoryFailureKind.forbidden,
            message: 'permission denied for table notifications',
          );
      await harness.controller.load();

      expect(
        harness.controller.state.unread.phase,
        NotificationFeedPhase.forbidden,
      );
    });
  });

  group('read semantics (A12)', () {
    test('marks optimistically and decrements the badge', () async {
      final harness = _build();
      harness.port.onFeed = (_) => _page(<NotificationDto>[_notification()]);
      await harness.controller.load();
      expect(harness.controller.state.unreadBadgeCount, 1);

      await harness.controller.markRead(_notification());

      expect(
        harness.controller.state.unread.items.single.readAt,
        isNotNull,
      );
      expect(harness.controller.state.unreadBadgeCount, 0);
      expect(harness.port.marks, hasLength(1));
      expect(harness.port.marks.single.context.reason, isNotNull);
    });

    test('a second mark on a read row is a client no-op (idempotent)', () async {
      final harness = _build();
      harness.port.onFeed = (_) => _page(<NotificationDto>[_notification()]);
      await harness.controller.load();

      await harness.controller.markRead(_notification());
      await harness.controller.markRead(
        _notification(readAt: DateTime.utc(2026, 9, 3)),
      );

      expect(harness.port.marks, hasLength(1));
    });

    test('a failure rolls the row back and surfaces the message', () async {
      final harness = _build();
      harness.port.onFeed = (_) => _page(<NotificationDto>[_notification()]);
      harness.port.onMarkRead = (_) =>
          const PlatformRepositoryFailure<NotificationDto>(
            kind: PlatformRepositoryFailureKind.infrastructureFailure,
            message: 'Supabase platform command failed.',
          );
      await harness.controller.load();

      await harness.controller.markRead(_notification());

      expect(harness.controller.state.unread.items.single.readAt, isNull);
      expect(
        harness.controller.state.actionPhase,
        NotificationActionPhase.failed,
      );
    });

    test('not_found removes the row and says "nicht mehr verfügbar" — '
        'never "Kein Zugriff" (§6.3)', () async {
      final harness = _build();
      harness.port.onFeed = (_) => _page(<NotificationDto>[_notification()]);
      harness.port.onMarkRead = (_) =>
          const PlatformRepositoryFailure<NotificationDto>(
            kind: PlatformRepositoryFailureKind.notFound,
            message: 'Notification not found.',
          );
      await harness.controller.load();
      harness.controller.select(_notification());

      await harness.controller.markRead(_notification());

      expect(harness.controller.state.unread.items, isEmpty);
      expect(
        harness.controller.state.actionMessage,
        'Diese Mitteilung ist nicht mehr verfügbar.',
      );
      expect(
        harness.controller.state.actionMessage,
        isNot(contains('Zugriff')),
      );
      expect(harness.controller.state.selectedId, isNull);
    });
  });

  group('realtime (§9)', () {
    test('a fan-out burst coalesces into exactly one reload', () async {
      final harness = _build();
      await harness.controller.load();
      final before = harness.port.queries.length;

      harness.inv.controller
        ..add(
          const PlatformQueryInvalidation(
            workspaceId: _workspace,
            aggregate: PlatformAggregate.notification,
            eventType: 'notification.fanned_out',
          ),
        )
        ..add(
          const PlatformQueryInvalidation.reconcile(workspaceId: _workspace),
        )
        ..add(
          const PlatformQueryInvalidation.reconcile(workspaceId: _workspace),
        );
      await _settle();

      expect(harness.port.queries.length, before + 1);
    });

    test('a task event does not reload the inbox', () async {
      final harness = _build();
      await harness.controller.load();
      final before = harness.port.queries.length;

      harness.inv.controller.add(
        const PlatformQueryInvalidation(
          workspaceId: _workspace,
          aggregate: PlatformAggregate.task,
          eventType: 'task.updated',
        ),
      );
      await _settle();

      expect(harness.port.queries.length, before);
    });

    test('stream errors degrade, the next signal recovers', () async {
      final harness = _build();
      await harness.controller.load();

      harness.inv.controller.addError(StateError('channel down'));
      await _settle();
      expect(harness.controller.state.liveUpdatesDegraded, isTrue);

      harness.inv.controller.add(
        const PlatformQueryInvalidation.reconcile(workspaceId: _workspace),
      );
      await _settle();
      expect(harness.controller.state.liveUpdatesDegraded, isFalse);
    });
  });
}
