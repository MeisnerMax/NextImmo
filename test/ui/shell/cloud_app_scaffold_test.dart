import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/navigation/app_navigation.dart';
import 'package:neximmo_app/ui/shell/cloud_app_scaffold.dart';

void main() {
  for (final viewport in <({double width, String shellKey})>[
    (width: 375, shellKey: 'cloud-shell-mobile'),
    (width: 900, shellKey: 'cloud-shell-wide'),
    (width: 1440, shellKey: 'cloud-shell-wide'),
  ]) {
    testWidgets('cloud shell is responsive at ${viewport.width}px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(viewport.width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: CloudAppScaffold(
            activeRoute: referencePropertiesRoute,
            child: ColoredBox(color: Colors.transparent),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(Key(viewport.shellKey)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('property document deep link selects documents', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CloudAppScaffold(
          activeRoute: propertyDocumentsRouteFor('property-a'),
          child: const SizedBox.shrink(),
        ),
      ),
    );

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, 2);
  });
}
