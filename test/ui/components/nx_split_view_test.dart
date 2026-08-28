import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/components/nx_split_view.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// UX-FOUNDATION-IMPL-01 (Foundation §4/§8/§18): the unified split view.
/// Split when width > AppBreakpoints.tabletMax (via AppLayout.splitViewMinWidth),
/// desktop ratio list:detail = 3:2, narrow mode replaces the list with the
/// detail and offers a back affordance — the Wave-2 pattern, centralized.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required Size viewport,
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
    await tester.pumpAndSettle();
  }

  testWidgets('the constant sits one pixel above the tablet ceiling', (
    tester,
  ) async {
    expect(AppLayout.splitViewMinWidth, AppBreakpoints.tabletMax + 1);
  });

  testWidgets('desktop renders list and detail side by side at 3:2', (
    tester,
  ) async {
    await pump(
      tester,
      NxSplitView(
        list: Container(key: const Key('the-list')),
        detail: Container(key: const Key('the-detail')),
        showDetail: true,
        onBackToList: () {},
      ),
      viewport: const Size(1440, 900),
    );

    expect(find.byKey(const Key('the-list')), findsOneWidget);
    expect(find.byKey(const Key('the-detail')), findsOneWidget);
    // No back affordance in split mode.
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    final listWidth = tester.getSize(find.byKey(const Key('the-list'))).width;
    final detailWidth =
        tester.getSize(find.byKey(const Key('the-detail'))).width;
    expect(
      listWidth / detailWidth,
      closeTo(3 / 2, 0.05),
      reason: 'Foundation fixes the split at list:detail = 3:2',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('exactly the tablet ceiling still stacks (no split at 1199)', (
    tester,
  ) async {
    await pump(
      tester,
      NxSplitView(
        list: Container(key: const Key('the-list')),
        detail: Container(key: const Key('the-detail')),
        showDetail: false,
      ),
      viewport: const Size(1199, 900),
    );

    expect(find.byKey(const Key('the-list')), findsOneWidget);
    expect(find.byKey(const Key('the-detail')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow mode replaces the list with the detail plus back', (
    tester,
  ) async {
    var wentBack = false;
    await pump(
      tester,
      NxSplitView(
        list: Container(key: const Key('the-list')),
        detail: Container(key: const Key('the-detail')),
        showDetail: true,
        onBackToList: () => wentBack = true,
      ),
      viewport: const Size(768, 1024),
    );

    expect(find.byKey(const Key('the-detail')), findsOneWidget);
    expect(
      find.byKey(const Key('the-list')),
      findsNothing,
      reason: 'narrow mode replaces the list, it does not stack',
    );
    expect(find.text('Zur Liste'), findsOneWidget);
    await tester.tap(find.text('Zur Liste'));
    expect(wentBack, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow mode without a selection just shows the list', (
    tester,
  ) async {
    await pump(
      tester,
      NxSplitView(
        list: Container(key: const Key('the-list')),
        detail: Container(key: const Key('the-detail')),
        showDetail: false,
        onBackToList: () {},
      ),
      viewport: const Size(390, 844),
    );

    expect(find.byKey(const Key('the-list')), findsOneWidget);
    expect(find.byKey(const Key('the-detail')), findsNothing);
    expect(find.text('Zur Liste'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
