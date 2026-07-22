import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/components/nx_chart_container.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Component coverage for the Wave-1 `NxChartContainer` extension
/// (SCR-011): optional fixed `height` for unbounded-height parents and an
/// optional `trailing` header action. Behavior without `height` (Expanded
/// into a bounded parent) must stay unchanged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  testWidgets('without height the chart expands into a bounded parent', (
    tester,
  ) async {
    const chartKey = ValueKey<String>('chart_child');
    await pump(
      tester,
      const SizedBox(
        height: 320,
        width: 400,
        child: NxChartContainer(
          title: 'Cashflow',
          state: NxChartState.ready,
          child: ColoredBox(color: Colors.transparent, key: chartKey),
        ),
      ),
    );

    expect(find.text('Cashflow'), findsOneWidget);
    expect(find.byKey(chartKey), findsOneWidget);
    // The child fills the remaining card height (Expanded behavior).
    final chartSize = tester.getSize(find.byKey(chartKey));
    expect(chartSize.height, greaterThan(200));
  });

  testWidgets('with height the container works inside an unbounded scroll view',
      (tester) async {
    const chartKey = ValueKey<String>('chart_child');
    await pump(
      tester,
      const SingleChildScrollView(
        child: NxChartContainer(
          title: 'Cashflow',
          state: NxChartState.ready,
          height: 260,
          child: ColoredBox(color: Colors.transparent, key: chartKey),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Cashflow'), findsOneWidget);
    final chartSize = tester.getSize(find.byKey(chartKey));
    expect(chartSize.height, 260);
  });

  testWidgets('renders subtitle and the trailing header action', (
    tester,
  ) async {
    await pump(
      tester,
      SingleChildScrollView(
        child: NxChartContainer(
          title: 'Cashflow',
          subtitle: 'vor Steuern',
          state: NxChartState.ready,
          height: 200,
          trailing: TextButton(
            onPressed: () {},
            child: const Text('Monthly'),
          ),
          child: const SizedBox.shrink(),
        ),
      ),
    );

    expect(find.text('Cashflow'), findsOneWidget);
    expect(find.text('vor Steuern'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
  });

  testWidgets('empty and error states show their scoped texts', (
    tester,
  ) async {
    await pump(
      tester,
      const SingleChildScrollView(
        child: Column(
          children: [
            NxChartContainer(
              title: 'Leer',
              state: NxChartState.empty,
              emptyText: 'Keine Daten vorhanden.',
              height: 120,
              child: SizedBox.shrink(),
            ),
            NxChartContainer(
              title: 'Fehler',
              state: NxChartState.error,
              errorText: 'Chart konnte nicht geladen werden.',
              height: 120,
              child: SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Keine Daten vorhanden.'), findsOneWidget);
    expect(find.text('Chart konnte nicht geladen werden.'), findsOneWidget);
  });
}
