import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/widgets/kpi_tile.dart';

void main() {
  testWidgets('kpi tile renders value and mandatory info icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KpiTile(
            title: 'Cap Rate',
            value: '5.20%',
            metricKey: 'cap_rate',
          ),
        ),
      ),
    );

    expect(find.text('Cap Rate'), findsOneWidget);
    expect(find.text('5.20%'), findsOneWidget);
    expect(find.text('i'), findsOneWidget);
  });
}
