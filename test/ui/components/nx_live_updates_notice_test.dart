import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/components/nx_live_updates_notice.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// UX-FOUNDATION-IMPL-01 (Foundation §13/§18): the passive realtime-degraded
/// notice proven in REALTIME-DEGRADED-UI-01, generalized as a shared
/// component. It informs and nothing else — no dialog, no barrier — and must
/// hold the 320px floor without overflow.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size viewport = const Size(1024, 768),
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              child,
              const Expanded(child: Center(child: Text('business surface'))),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the default copy with a warning badge', (tester) async {
    await pump(tester, const NxLiveUpdatesNotice());

    expect(find.byType(NxLiveUpdatesNotice), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.textContaining('Live-Updates'), findsOneWidget);
    // Passive: it never interrupts.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('business surface'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a caller-provided message replaces the default copy', (
    tester,
  ) async {
    await pump(
      tester,
      const NxLiveUpdatesNotice(
        message: 'Live updates are temporarily interrupted.',
      ),
    );

    expect(
      find.text('Live updates are temporarily interrupted.'),
      findsOneWidget,
    );
    expect(find.textContaining('Live-Updates'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('holds the 320px floor without overflow', (tester) async {
    await pump(
      tester,
      const NxLiveUpdatesNotice(),
      viewport: const Size(320, 568),
    );

    expect(find.byType(NxLiveUpdatesNotice), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
