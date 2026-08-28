import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/components/nx_empty_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// UX-FOUNDATION-IMPL-01 (Foundation §11/§18): the one error/retry state —
/// `cloud_off` icon plus a filled refresh action — centralizing what four
/// divergent retry styles did before.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('error state renders cloud_off with a filled retry', (
    tester,
  ) async {
    var retried = false;
    await pump(
      tester,
      NxEmptyState.error(
        description: 'Die Tickets konnten nicht geladen werden.',
        onRetry: () => retried = true,
      ),
    );

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
    // FilledButton.icon builds a private FilledButton subclass, so the
    // subtype finder is the correct probe for "a filled retry button".
    expect(find.bySubtype<FilledButton>(), findsOneWidget);
    await tester.tap(find.text('Erneut versuchen'));
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without onRetry there is no dangling button', (tester) async {
    await pump(
      tester,
      NxEmptyState.error(description: 'Nicht ladbar.'),
    );

    expect(find.bySubtype<FilledButton>(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
