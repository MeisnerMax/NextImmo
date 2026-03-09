import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/widgets/info_tooltip.dart';

void main() {
  testWidgets('info tooltip renders and shows tooltip message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: InfoTooltip(metricKey: 'cap_rate'))),
      ),
    );

    expect(find.byType(InfoTooltip), findsOneWidget);

    final center = tester.getCenter(find.byType(InfoTooltip));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(center);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.textContaining('Net Operating Income divided'), findsOneWidget);
  });
}
