import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/core/models/property_creation.dart';
import 'package:neximmo_app/ui/screens/properties/property_creation_workflow_screen.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for the redesigned `PropertyCreationWorkflowScreen`
/// (Phase 2, Wave 1, Arbeitspaket 5 / SCR-008, BIG-012 split): step navigation,
/// visible validation state, the save lifecycle (loading, success, and a
/// retry-without-data-loss error path), the cancel-with-confirmation guard, and
/// a responsive smoke check at the three golden widths. The screen is
/// provider-less local state, so no `ProviderScope` is needed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PropertyRecord createdRecord() => const PropertyRecord(
        id: 'NX-NEW-1',
        name: 'Test Objekt',
        addressLine1: 'Teststrasse',
        zip: '10115',
        city: 'Berlin',
        country: 'DE',
        propertyType: 'rental',
        units: 1,
        createdAt: 1,
        updatedAt: 1,
      );

  Future<void> pumpWizard(
    WidgetTester tester, {
    required Future<PropertyRecord?> Function(
      PropertyCreationDraft draft,
      PropertyCreationAssessment assessment,
    ) onCreate,
    List<PropertyRecord> existing = const <PropertyRecord>[],
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PropertyCreationWorkflowScreen(
          existingProperties: existing,
          onCreateProperty: onCreate,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Enters the minimum fields required for `canSave`: object name plus a
  // complete-enough address (street, zip, city; country defaults to DE).
  Future<void> fillRequired(WidgetTester tester) async {
    await tester.tap(find.text('2. Basisdaten'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Objektname *'),
      'Test Objekt',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('3. Adresse und Lage'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Strasse *'),
      'Teststrasse',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'PLZ *'), '10115');
    await tester.enterText(find.widgetWithText(TextFormField, 'Ort *'), 'Berlin');
    await tester.pumpAndSettle();
  }

  Future<void> gotoSaveStep(WidgetTester tester) async {
    await tester.tap(find.text('Zur Pruefung'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a nav tile switches the visible step', (tester) async {
    await pumpWizard(tester, onCreate: (_, __) async => createdRecord());

    expect(find.text('Einstieg und Objektart'), findsOneWidget);

    await tester.tap(find.text('3. Adresse und Lage'));
    await tester.pumpAndSettle();

    expect(find.text('Adresse und Lage'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Strasse *'), findsOneWidget);
  });

  testWidgets('an incomplete required step surfaces its validation state', (
    tester,
  ) async {
    await pumpWizard(tester, onCreate: (_, __) async => createdRecord());

    await tester.tap(find.text('Zur Pruefung'));
    await tester.pumpAndSettle();

    expect(find.text('Fehlende Pflichtangaben'), findsOneWidget);
    expect(find.text('Objektname fehlt.'), findsOneWidget);
  });

  testWidgets('save shows a clear loading state while in flight', (
    tester,
  ) async {
    final completer = Completer<PropertyRecord?>();
    await pumpWizard(tester, onCreate: (_, __) => completer.future);

    await fillRequired(tester);
    await gotoSaveStep(tester);

    await tester.tap(find.text('Property final speichern'));
    await tester.pump();

    expect(
      find.text('Das Objekt wird gespeichert. Bitte einen Moment Geduld.'),
      findsOneWidget,
    );

    completer.complete(createdRecord());
    await tester.pumpAndSettle();
  });

  testWidgets('successful save shows the success state', (tester) async {
    await pumpWizard(tester, onCreate: (_, __) async => createdRecord());

    await fillRequired(tester);
    await gotoSaveStep(tester);

    await tester.tap(find.text('Property final speichern'));
    await tester.pumpAndSettle();

    expect(find.text('Property wurde erfolgreich angelegt'), findsOneWidget);
  });

  testWidgets('failed save offers a retry that keeps the entered data', (
    tester,
  ) async {
    var calls = 0;
    final seenNames = <String>[];
    Future<PropertyRecord?> onCreate(
      PropertyCreationDraft draft,
      PropertyCreationAssessment assessment,
    ) async {
      calls++;
      seenNames.add(draft.objectName);
      if (calls == 1) {
        throw Exception('save failed');
      }
      return createdRecord();
    }

    await pumpWizard(tester, onCreate: onCreate);

    await fillRequired(tester);
    await gotoSaveStep(tester);

    await tester.tap(find.text('Property final speichern'));
    await tester.pumpAndSettle();

    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(calls, 1);

    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();

    // The retry reused the preserved draft — same entered name both times.
    expect(find.text('Property wurde erfolgreich angelegt'), findsOneWidget);
    expect(calls, 2);
    expect(seenNames, ['Test Objekt', 'Test Objekt']);
  });

  testWidgets('closing a dirty draft asks for confirmation', (tester) async {
    await pumpWizard(tester, onCreate: (_, __) async => createdRecord());

    await tester.tap(find.text('2. Basisdaten'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Objektname *'),
      'Dirty draft',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Schliessen'));
    await tester.pumpAndSettle();

    expect(find.text('Anlage abbrechen?'), findsOneWidget);

    await tester.tap(find.text('Weiter bearbeiten'));
    await tester.pumpAndSettle();

    // Dialog dismissed, still editing the same draft.
    expect(find.text('Anlage abbrechen?'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Objektname *'), findsOneWidget);
  });

  for (final size in const [
    Size(390, 844),
    Size(1024, 768),
    Size(1440, 900),
  ]) {
    testWidgets('renders without overflow at ${size.width}x${size.height}', (
      tester,
    ) async {
      await pumpWizard(
        tester,
        onCreate: (_, __) async => createdRecord(),
        size: size,
      );

      expect(find.text('Objekt anlegen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
