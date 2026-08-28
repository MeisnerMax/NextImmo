import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/components/nx_list_skeleton.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// UX-FOUNDATION-IMPL-01 (Foundation §11/§18): the one list skeleton. Loading
/// is a skeleton, not a spinner; the six private per-panel copies converge on
/// this component as their screens are rebuilt.
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
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the requested number of rows', (tester) async {
    await pump(tester, const NxListSkeleton(rows: 4));

    expect(
      find.byKey(const Key('nx-list-skeleton-row-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('nx-list-skeleton-row-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('nx-list-skeleton-row-4')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('defaults to six rows and stays overflow-free on a phone', (
    tester,
  ) async {
    await pump(tester, const NxListSkeleton(), viewport: const Size(320, 568));

    expect(find.byKey(const Key('nx-list-skeleton-row-5')), findsOneWidget);
    expect(find.byKey(const Key('nx-list-skeleton-row-6')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('is excluded from semantics as pure decoration', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const NxListSkeleton(rows: 2));

    // The individual placeholder bars carry no semantics of their own; the
    // component announces a single loading label instead.
    expect(find.bySemanticsLabel(RegExp('Wird geladen')), findsOneWidget);
    handle.dispose();
    expect(tester.takeException(), isNull);
  });
}
