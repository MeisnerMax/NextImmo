import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/ui/screens/property_detail/leasing/widgets/leasing_area_gate.dart';
import 'package:neximmo_app/ui/state/property_state.dart';

void main() {
  testWidgets('a rental property passes straight through', (tester) async {
    await _pump(tester, properties: <PropertyRecord>[_property('rental')]);

    expect(find.text('leasing area'), findsOneWidget);
  });

  testWidgets('a hotel gets the explanation instead of the leasing area', (
    tester,
  ) async {
    await _pump(tester, properties: <PropertyRecord>[_property('hotel')]);

    expect(find.text('leasing area'), findsNothing);
    expect(find.textContaining('als Hotel angelegt'), findsOneWidget);
    expect(find.textContaining('Gäste'), findsOneWidget);
  });

  testWidgets('a sale object names what belongs there instead', (tester) async {
    await _pump(tester, properties: <PropertyRecord>[_property('sale')]);

    expect(find.textContaining('Verkaufsobjekt'), findsOneWidget);
    expect(find.textContaining('Kaufinteressenten'), findsOneWidget);
  });

  testWidgets('an unknown property fails open rather than hiding the area', (
    tester,
  ) async {
    // A suitability gate, not a permission gate: hiding a rental property's
    // leases because its record had not loaded yet would be the worse error.
    await _pump(tester, properties: const <PropertyRecord>[]);

    expect(find.text('leasing area'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required List<PropertyRecord> properties,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        propertiesControllerProvider.overrideWith(
          () => _FakePropertiesController(properties),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: LeasingAreaGate(
            propertyId: 'p1',
            child: Text('leasing area'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PropertyRecord _property(String type) => PropertyRecord(
  id: 'p1',
  name: 'Objekt',
  addressLine1: 'Musterweg 1',
  zip: '10115',
  city: 'Berlin',
  country: 'DE',
  propertyType: type,
  units: 4,
  createdAt: 0,
  updatedAt: 0,
);

class _FakePropertiesController extends PropertiesController {
  _FakePropertiesController(this.properties);

  final List<PropertyRecord> properties;

  @override
  Future<List<PropertyRecord>> build() async => properties;
}
