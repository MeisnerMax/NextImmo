import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/components/nx_notice.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// UX-FOUNDATION-IMPL-01 (Foundation §12/§18): the shared inline notice that
/// consolidates the hand-rolled `_Notice`/`_TruncationNotice` warning
/// containers. Inline and passive — not a toast, not a banner system.
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
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(8), child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders message, default warning icon and optional action', (
    tester,
  ) async {
    var acted = false;
    await pump(
      tester,
      NxNotice(
        message: 'Nur die ersten 200 Zeilen wurden geladen.',
        action: TextButton(
          onPressed: () => acted = true,
          child: const Text('Alle laden'),
        ),
      ),
    );

    expect(
      find.text('Nur die ersten 200 Zeilen wurden geladen.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    await tester.tap(find.text('Alle laden'));
    expect(acted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports info and error kinds with their own icons', (
    tester,
  ) async {
    await pump(
      tester,
      const Column(
        children: [
          NxNotice(kind: NxNoticeKind.info, message: 'Hinweis.'),
          SizedBox(height: 8),
          NxNotice(kind: NxNoticeKind.error, message: 'Fehler.'),
        ],
      ),
    );

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long copy wraps instead of overflowing at 320px', (
    tester,
  ) async {
    await pump(
      tester,
      const NxNotice(
        title: 'Unvollständige Daten',
        message:
            'Diese Ansicht wurde begrenzt geladen, weil der Arbeitsbereich '
            'sehr viele Einträge enthält und die Abfrage serverseitig '
            'beschnitten wurde. Die Summen können deshalb unvollständig sein.',
      ),
      viewport: const Size(320, 568),
    );

    expect(find.text('Unvollständige Daten'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
