import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/notification_inbox_controller.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/notification_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/notification_inbox_screen.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/notification_targets.dart';
import 'package:neximmo_app/ui/templates/list_filter_template.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

final DateTime _now = DateTime(2026, 9, 3, 10);

NotificationDto _notification({
  String id = 'note-a',
  String kind = 'task.assigned',
  DateTime? createdAt,
  DateTime? readAt,
  PlatformEntityRef? entity,
  String? body,
}) {
  final stamp = createdAt ?? DateTime(2026, 9, 3, 8);
  return NotificationDto(
    id: id,
    workspaceId: 'workspace-a',
    recipientUserId: 'user-1',
    kind: kind,
    title: 'Wohnungsübergabe Musterstraße 4 — dir zugewiesen ($id)',
    createdAt: stamp,
    updatedAt: stamp,
    createdBy: '0b7cf3a2-9df5-4f6e-9a41-1c2d3e4f5a6b',
    updatedBy: '0b7cf3a2-9df5-4f6e-9a41-1c2d3e4f5a6b',
    version: 1,
    readAt: readAt,
    entity: entity,
    body: body,
  );
}

class _Calls {
  final List<NotificationDto> selected = <NotificationDto>[];
  final List<NotificationDto> marked = <NotificationDto>[];
  final List<(NotificationDto, NotificationTarget)> opened =
      <(NotificationDto, NotificationTarget)>[];
  final List<bool> tabs = <bool>[];
  int reloads = 0;
}

NotificationInboxState _ready(
  List<NotificationDto> items, {
  bool unreadOnly = true,
  String? nextCursor,
  String? selectedId,
}) {
  final slice = NotificationFeedSlice(
    phase: NotificationFeedPhase.ready,
    items: items,
    nextCursor: nextCursor,
    loaded: true,
  );
  return NotificationInboxState(
    unread: slice,
    all: unreadOnly ? const NotificationFeedSlice() : slice,
    unreadOnly: unreadOnly,
    selectedId: selectedId,
  );
}

Future<_Calls> _pump(
  WidgetTester tester,
  NotificationInboxState state, {
  double width = 1440,
  double height = 900,
  bool dark = false,
}) async {
  final calls = _Calls();
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(
        body: NotificationInboxView(
          state: state,
          now: _now,
          onReload: () async => calls.reloads++,
          onLoadMore: () async {},
          onSetTab: (unreadOnly) async => calls.tabs.add(unreadOnly),
          onSelect: calls.selected.add,
          onCloseDetail: () {},
          onMarkRead: (notification) async => calls.marked.add(notification),
          onOpenTarget: (notification, target) =>
              calls.opened.add((notification, target)),
        ),
      ),
    ),
  );
  await tester.pump();
  return calls;
}

void main() {
  testWidgets('offers nothing the contract does not carry '
      '(§17 pretense regression, widget half)', (tester) async {
    await _pump(tester, _ready(<NotificationDto>[_notification()]));

    // No filter bar, no search, no "Alle als gelesen", exactly two tabs.
    expect(find.byType(ListFilterBar), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Alle als gelesen'), findsNothing);
    final segments = tester.widget<SegmentedButton<bool>>(
      find.byKey(const Key('notification-inbox-tabs')),
    );
    expect(segments.segments, hasLength(2));
  });

  testWidgets('renders the §10 states at their keys', (tester) async {
    await _pump(tester, const NotificationInboxState());
    expect(
      find.byKey(const Key('notification-inbox-loading')),
      findsOneWidget,
    );

    await _pump(tester, _ready(const <NotificationDto>[]));
    expect(
      find.byKey(const Key('notification-inbox-empty-unread')),
      findsOneWidget,
    );
    expect(find.text('Alles gelesen'), findsOneWidget);

    await _pump(
      tester,
      _ready(const <NotificationDto>[], unreadOnly: false),
    );
    expect(
      find.byKey(const Key('notification-inbox-empty-all')),
      findsOneWidget,
    );
    // §10: the empty inbox names the missing emitter honestly.
    expect(
      find.textContaining('serverseitig erzeugt und sind noch nicht aktiv'),
      findsOneWidget,
    );

    await _pump(
      tester,
      const NotificationInboxState(
        unread: NotificationFeedSlice(
          phase: NotificationFeedPhase.error,
          loaded: true,
          message: 'Ausfall',
        ),
      ),
    );
    expect(find.byKey(const Key('notification-inbox-error')), findsOneWidget);

    await _pump(
      tester,
      _ready(<NotificationDto>[_notification()], nextCursor: 'more'),
    );
    expect(
      find.byKey(const Key('notification-inbox-partial')),
      findsOneWidget,
    );

    await _pump(
      tester,
      _ready(<NotificationDto>[_notification()]).copyWith(
        liveUpdatesDegraded: true,
      ),
    );
    expect(
      find.byKey(const Key('notification-inbox-live-degraded')),
      findsOneWidget,
    );

    await _pump(
      tester,
      _ready(<NotificationDto>[_notification()], selectedId: 'missing'),
    );
    expect(
      find.byKey(const Key('notification-detail-not-found')),
      findsOneWidget,
    );
  });

  testWidgets('no row renders a raw UUID or an ISO-8601 timestamp '
      '(acceptance 1, legacy regression)', (tester) async {
    await _pump(
      tester,
      _ready(<NotificationDto>[
        _notification(
          entity: const PlatformEntityRef(
            type: PlatformEntityType.lease,
            id: 'e57f2b19-1234-4c00-9d0e-aa41bb52cc63',
          ),
        ),
      ]),
    );

    expect(find.textContaining('e57f2b19'), findsNothing);
    expect(find.textContaining('0b7cf3a2'), findsNothing);
    expect(find.textContaining(RegExp(r'\d{4}-\d{2}-\d{2}T')), findsNothing);
    expect(find.textContaining('Vertrag'), findsWidgets);
    expect(find.textContaining('vor 2 Stunden'), findsWidgets);
  });

  testWidgets('unread is triple-coded and the badge caps at 50+ (§15/A14)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final many = <NotificationDto>[
      for (var index = 0; index < 50; index++)
        _notification(id: 'note-$index'),
    ];
    await _pump(tester, _ready(many, nextCursor: 'more'));

    expect(find.bySemanticsLabel(RegExp('Ungelesen')), findsWidgets);
    expect(find.textContaining('Ungelesen (50+)'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('groups the DESC feed into Heute / Diese Woche / Älter (§4)', (
    tester,
  ) async {
    await _pump(
      tester,
      _ready(<NotificationDto>[
        _notification(id: 'today', createdAt: DateTime(2026, 9, 3, 8)),
        _notification(id: 'week', createdAt: DateTime(2026, 9, 1, 8)),
        _notification(id: 'older', createdAt: DateTime(2026, 8, 20, 8)),
      ]),
    );

    expect(
      find.byKey(const Key('notification-inbox-group-today')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('notification-inbox-group-thisWeek')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('notification-inbox-group-older')),
      findsOneWidget,
    );
  });

  testWidgets('desktop: resolvable targets open, unresolvable ones render '
      'the disabled Öffnen (§9/A13)', (tester) async {
    final resolvable = _notification(
      id: 'with-target',
      entity: const PlatformEntityRef(
        type: PlatformEntityType.property,
        id: 'property-1',
      ),
    );
    final unresolvable = _notification(
      id: 'no-target',
      entity: const PlatformEntityRef(
        type: PlatformEntityType.unit,
        id: 'unit-1',
      ),
    );
    final calls = await _pump(
      tester,
      _ready(<NotificationDto>[resolvable, unresolvable]),
    );

    await tester.tap(find.byKey(const Key('notification-open-with-target')));
    await tester.pump();
    expect(calls.opened.single.$1.id, 'with-target');
    expect(calls.opened.single.$2.route, '/properties/property-1');

    final disabled = tester.widget<TextButton>(
      find.byKey(const Key('notification-open-no-target')),
    );
    expect(disabled.onPressed, isNull);
    expect(
      find.byKey(const Key('notification-target-unavailable-no-target')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('notification-mark-read-with-target')),
    );
    await tester.pump();
    expect(calls.marked.single.id, 'with-target');
  });

  testWidgets('mobile: the ListTile fallback jumps directly for resolvable '
      'targets and opens the detail otherwise (§5)', (tester) async {
    final resolvable = _notification(
      id: 'with-target',
      entity: const PlatformEntityRef(
        type: PlatformEntityType.property,
        id: 'property-1',
      ),
    );
    final unresolvable = _notification(id: 'no-target');
    final calls = await _pump(
      tester,
      _ready(<NotificationDto>[resolvable, unresolvable]),
      width: 390,
      height: 844,
    );

    expect(
      find.byKey(const Key('notification-mobile-row-with-target')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.chevron_right), findsWidgets);

    await tester.tap(
      find.byKey(const Key('notification-mobile-row-with-target')),
    );
    await tester.pump();
    expect(calls.opened.single.$1.id, 'with-target');
    expect(calls.selected, isEmpty);

    await tester.tap(
      find.byKey(const Key('notification-mobile-row-no-target')),
    );
    await tester.pump();
    expect(calls.selected.single.id, 'no-target');
  });

  group('responsive matrix (§17)', () {
    for (final size in const <Size>[
      Size(320, 700),
      Size(390, 844),
      Size(1024, 768),
      Size(1440, 900),
    ]) {
      for (final dark in <bool>[false, true]) {
        testWidgets(
          'renders without overflow at ${size.width.toInt()} px '
          '(${dark ? 'dark' : 'light'})',
          (tester) async {
            await _pump(
              tester,
              _ready(<NotificationDto>[
                _notification(
                  body:
                      'Sehr langer Mitteilungstext mit vielen Details zur '
                      'Wohnungsübergabe inklusive Terminvorschlägen und '
                      'weiterer Nachverfolgung im Bestand des Gebäudeteils B',
                  entity: const PlatformEntityRef(
                    type: PlatformEntityType.property,
                    id: 'property-1',
                  ),
                ),
              ], nextCursor: 'more'),
              width: size.width,
              height: size.height,
              dark: dark,
            );

            expect(tester.takeException(), isNull);
            final mobile = size.width <= 767;
            expect(
              find.byKey(const Key('notification-mobile-row-note-a')),
              mobile ? findsOneWidget : findsNothing,
            );
          },
        );
      }
    }

    testWidgets('1024 px narrow mode replaces the list with the detail', (
      tester,
    ) async {
      final row = _notification();
      await _pump(
        tester,
        _ready(<NotificationDto>[row], selectedId: row.id),
        width: 1024,
        height: 768,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('notification-detail')), findsOneWidget);
      expect(find.text('Zur Liste'), findsOneWidget);
    });

    testWidgets('1440 px shows list and detail side by side with the read '
        'action', (tester) async {
      final row = _notification();
      final calls = await _pump(
        tester,
        _ready(<NotificationDto>[row], selectedId: row.id),
      );

      expect(find.byKey(const Key('notification-detail')), findsOneWidget);
      expect(find.text('Zur Liste'), findsNothing);
      await tester.tap(
        find.byKey(const Key('notification-detail-mark-read')),
      );
      await tester.pump();
      expect(calls.marked.single.id, row.id);
    });
  });
}
