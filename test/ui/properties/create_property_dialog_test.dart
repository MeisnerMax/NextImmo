import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/ui/screens/properties/create_property_dialog.dart';

void main() {
  test('maps property type values to readable labels', () {
    expect(propertyTypeDisplayLabel('single_family'), 'Single Family');
    expect(propertyTypeDisplayLabel('multi_family'), 'Multi Family');
    expect(propertyTypeDisplayLabel('commercial'), 'Commercial Asset');
  });

  testWidgets('create property dialog keeps only base fields', (tester) async {
    CreatePropertyDraft? createdDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<PropertyRecord>(
                        context: context,
                        builder:
                            (_) => CreatePropertyDialog(
                              onCreateProperty: (draft) async {
                                createdDraft = draft;
                                return PropertyRecord(
                                  id: 'p1',
                                  name: draft.name,
                                  addressLine1: draft.address,
                                  zip: draft.zip,
                                  city: draft.city,
                                  country: draft.country,
                                  propertyType: draft.propertyType,
                                  units: draft.units,
                                  createdAt: 1,
                                  updatedAt: 1,
                                );
                              },
                            ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Basic Information'), findsOneWidget);
    expect(find.text('Property Details'), findsOneWidget);
    expect(find.text('Strategy (rental/flip/brrrr)'), findsNothing);
    expect(find.text('Purchase Price'), findsNothing);
    expect(find.text('Rent Monthly'), findsNothing);
    expect(find.text('Rehab Budget'), findsNothing);
    expect(find.text('Financing (cash/loan)'), findsNothing);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Test');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Address'),
      'Main Street 1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'City'),
      'Berlin',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'ZIP'), '10115');
    await tester.enterText(find.widgetWithText(TextFormField, 'Units'), '');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Property'));
    await tester.pumpAndSettle();

    expect(createdDraft, isNotNull);
    expect(createdDraft!.country, 'DE');
    expect(createdDraft!.units, 1);
    expect(createdDraft!.propertyType, 'single_family');
  });
}
