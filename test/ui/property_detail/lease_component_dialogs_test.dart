import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_component_dto.dart';
import 'package:neximmo_app/ui/screens/property_detail/leasing/widgets/lease_component_dialogs.dart';

void main() {
  group('component form', () {
    testWidgets('refuses an empty amount before spending a round trip', (
      tester,
    ) async {
      final captured = await _openForm(tester, submitImmediately: true);

      expect(captured.result, isNull, reason: 'the dialog stays open');
      expect(find.text('Bitte einen Betrag eingeben.'), findsOneWidget);
    });

    testWidgets('refuses a negative amount and says why', (tester) async {
      final captured = await _openForm(tester);
      await tester.enterText(
        find.byKey(const Key('lease-component-amount')),
        '-50',
      );
      await tester.tap(find.byKey(const Key('lease-component-submit')));
      await tester.pumpAndSettle();

      // Mirrors the CHECK, and explains the modelling rather than just
      // refusing: a reduction is a smaller amount for a period.
      expect(
        find.textContaining('Eine Minderung ist ein kleinerer Betrag'),
        findsOneWidget,
      );
      expect(captured.result, isNull);
    });

    testWidgets('a net amount demands a rate', (tester) async {
      final captured = await _openForm(tester);
      await tester.enterText(
        find.byKey(const Key('lease-component-amount')),
        '100',
      );
      await tester.tap(find.byKey(const Key('lease-component-vat-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Netto (Steuer kommt hinzu)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lease-component-submit')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Ohne Steuersatz lässt sich der Betrag nicht'),
        findsOneWidget,
      );
      expect(captured.result, isNull);
    });

    testWidgets('the rate field only exists when it means something', (
      tester,
    ) async {
      await _openForm(tester);

      // Exempt by default, so no rate field at all rather than a disabled one
      // that invites the reader to look for the way to enable it.
      expect(find.byKey(const Key('lease-component-vat-rate')), findsNothing);

      await tester.tap(find.byKey(const Key('lease-component-vat-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brutto (Steuer enthalten)').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lease-component-vat-rate')), findsOneWidget);
    });

    testWidgets('a complete entry comes back as a result', (tester) async {
      final captured = await _openForm(tester);
      await tester.enterText(
        find.byKey(const Key('lease-component-amount')),
        // A comma, because a German keyboard produces one and a form that
        // silently rejects it looks broken rather than strict.
        '1234,50',
      );
      await tester.tap(find.byKey(const Key('lease-component-submit')));
      await tester.pumpAndSettle();

      final result = captured.result;
      expect(result, isNotNull);
      expect(result!.amount, 1234.5);
      expect(result.componentType, LeaseComponentType.baseRent);
      expect(result.vatMode, LeaseComponentVatMode.exempt);
      expect(result.vatRatePercent, isNull);
      expect(result.validTo, isNull, reason: 'open-ended is the normal case');
    });

    testWidgets('the type is a fact when editing, not a disabled field', (
      tester,
    ) async {
      await _openForm(
        tester,
        existing: _component(type: LeaseComponentType.heatingAdvance),
      );

      expect(find.byKey(const Key('lease-component-type')), findsNothing);
      expect(find.text('Heizkostenvorauszahlung'), findsOneWidget);
      expect(
        find.textContaining('Die Art eines Bestandteils ist unveränderlich'),
        findsOneWidget,
      );
    });

    testWidgets('the currency is shown but never asked for', (tester) async {
      await _openForm(tester, currencyCode: 'CHF');

      // The server reads it from the lease, so a field here could only
      // introduce a mismatch it would then refuse.
      expect(find.text('CHF'), findsWidgets);
      expect(find.textContaining('Übernimmt der Vertrag'), findsOneWidget);
    });

    testWidgets('the unknown type is never offered', (tester) async {
      await _openForm(tester);
      await tester.tap(find.byKey(const Key('lease-component-type')));
      await tester.pumpAndSettle();

      expect(find.text('Unbekannter Bestandteil'), findsNothing);
      expect(find.text('Grundmiete'), findsWidgets);
    });
  });

  group('close dialog', () {
    testWidgets('refuses an end before the beginning', (tester) async {
      // The dialog defaults its end date to today, so the component has to
      // begin in the future for "end before beginning" to be reachable without
      // driving a date picker.
      final captured = await _openClose(
        tester,
        component: _component(validFrom: DateTime(2099, 1, 1)),
      );
      await tester.tap(find.byKey(const Key('lease-component-close-submit')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('lease-component-close-error')),
        findsOneWidget,
      );
      expect(captured.result, isNull);
    });

    testWidgets('says the component is kept, not deleted', (tester) async {
      await _openClose(tester, component: _component());

      expect(
        find.textContaining('Gelöscht wird nichts'),
        findsOneWidget,
      );
    });
  });

  group('amount parsing', () {
    test('accepts a comma and rejects nonsense', () {
      expect(parseComponentAmount('1234,50'), 1234.5);
      expect(parseComponentAmount('1234.50'), 1234.5);
      expect(parseComponentAmount('  12  '), 12);
      expect(parseComponentAmount(''), isNull);
      expect(parseComponentAmount('abc'), isNull);
    });
  });
}

class _Captured {
  LeaseComponentFormResult? result;
  DateTime? closeResult;
}

Future<_Captured> _openForm(
  WidgetTester tester, {
  LeaseComponentDto? existing,
  String currencyCode = 'EUR',
  bool submitImmediately = false,
}) async {
  // The form is taller than the default 800x600 test view, and a tap that
  // lands off-screen fails with a hit-test warning rather than an assertion —
  // which reads like a broken widget instead of a small window.
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final captured = _Captured();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured.result = await showLeaseComponentFormDialog(
                context: context,
                currencyCode: currencyCode,
                existing: existing,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (submitImmediately) {
    await tester.tap(find.byKey(const Key('lease-component-submit')));
    await tester.pumpAndSettle();
  }
  return captured;
}

Future<_Captured> _openClose(
  WidgetTester tester, {
  required LeaseComponentDto component,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final captured = _Captured();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured.closeResult = await showLeaseComponentCloseDialog(
                context: context,
                component: component,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return captured;
}

LeaseComponentDto _component({
  LeaseComponentType type = LeaseComponentType.baseRent,
  DateTime? validFrom,
  DateTime? validTo,
}) => LeaseComponentDto(
  id: 'k1',
  leaseId: 'l1',
  propertyId: 'p1',
  componentType: type,
  amount: 1000,
  currencyCode: 'EUR',
  vatMode: LeaseComponentVatMode.exempt,
  validFrom: validFrom ?? DateTime(2026, 1, 1),
  validTo: validTo,
  version: 1,
);
