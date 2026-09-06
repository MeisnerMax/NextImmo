import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/leasing_operations/application/leases_controller.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_component_dto.dart';
import 'package:neximmo_app/ui/screens/property_detail/leasing/widgets/lease_components_section.dart';

void main() {
  testWidgets('a component shows its amount and the period it covers', (
    tester,
  ) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
        _component(
          type: LeaseComponentType.heatingAdvance,
          amount: 90,
          validTo: DateTime(2026, 6, 30),
        ),
      ],
    );

    expect(find.text('Grundmiete'), findsOneWidget);
    expect(find.textContaining('1000.00 EUR'), findsWidgets);
    expect(find.text('seit 01.01.2026'), findsOneWidget);
    expect(find.text('01.01.2026 – 30.06.2026'), findsOneWidget);
  });

  testWidgets('an unrecorded type says so in words, never as a figure', (
    tester,
  ) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
      ],
    );

    // The whole point of DEC-029 in the UI: four of the five types have no
    // component, and none of them may render as a dash or a zero, because both
    // read as "nothing owed" rather than "nothing recorded".
    expect(find.text('nicht erfasst'), findsNWidgets(4));
    expect(find.text('—'), findsNothing);
    expect(find.text('0.00 EUR'), findsNothing);
    expect(
      find.textContaining('Nicht erfasst heißt nicht null'),
      findsOneWidget,
    );
  });

  testWidgets('nothing recorded at all is a statement, not an empty box', (
    tester,
  ) async {
    await _pump(tester, components: const <LeaseComponentDto>[]);

    expect(
      find.byKey(const Key('lease-components-empty')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Nicht erfasst heißt nicht null'),
      findsOneWidget,
    );
  });

  testWidgets('mixed currencies produce no total at all', (tester) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
        _component(
          type: LeaseComponentType.parking,
          amount: 50,
          currency: 'CHF',
        ),
      ],
    );

    // A number here would look authoritative and mean nothing.
    expect(
      tester
          .widget<Text>(find.byKey(const Key('lease-components-total')))
          .data,
      'nicht summierbar',
    );
    expect(find.textContaining('verschiedene Währungen'), findsOneWidget);
  });

  testWidgets('a net amount without a rate does not invent a gross one', (
    tester,
  ) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(
          type: LeaseComponentType.parking,
          amount: 100,
          vatMode: LeaseComponentVatMode.net,
        ),
      ],
    );

    expect(find.text('netto, Steuersatz nicht erfasst'), findsOneWidget);
    expect(find.textContaining('119.00 EUR'), findsNothing);
  });

  testWidgets('a net amount with a rate shows the gross figure', (
    tester,
  ) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(
          type: LeaseComponentType.parking,
          amount: 100,
          vatMode: LeaseComponentVatMode.net,
          vatRate: 19,
        ),
      ],
    );

    expect(find.textContaining('netto, brutto'), findsOneWidget);
    expect(find.textContaining('19 %'), findsOneWidget);
  });

  testWidgets('an unfamiliar type is shown with the key the server sent', (
    tester,
  ) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
        _component(
          type: LeaseComponentType.unknown,
          amount: 25,
          rawTypeKey: 'garden_levy',
        ),
      ],
    );

    // Dropping it would understate what a tenant pays; naming it "Sonstiges"
    // would claim a classification this build did not make.
    expect(find.text('garden_levy'), findsOneWidget);
    expect(find.textContaining('25'), findsWidgets);
  });

  testWidgets('the section names the date it is true on', (tester) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
      ],
      asOf: DateTime(2026, 3, 15),
    );

    expect(find.textContaining('Stand 15.03.2026'), findsOneWidget);
  });

  testWidgets('loading is its own state', (tester) async {
    await _pump(tester, phase: LeaseComponentsPhase.loading, settle: false);

    expect(
      find.byKey(const Key('lease-components-loading')),
      findsOneWidget,
    );
  });

  testWidgets('a refusal names the capability', (tester) async {
    await _pump(tester, phase: LeaseComponentsPhase.forbidden);

    expect(
      find.byKey(const Key('lease-components-forbidden')),
      findsOneWidget,
    );
    expect(find.textContaining('(lease.read)'), findsOneWidget);
  });

  testWidgets('an error offers a retry rather than a raw message', (
    tester,
  ) async {
    var retries = 0;
    await _pump(
      tester,
      phase: LeaseComponentsPhase.error,
      onRetry: () => retries++,
    );

    expect(find.byKey(const Key('lease-components-error')), findsOneWidget);
    await tester.tap(find.text('Erneut versuchen'));
    expect(retries, 1);
  });

  for (final size in const <Size>[
    Size(320, 700),
    Size(390, 844),
    Size(768, 1024),
    Size(1440, 900),
  ]) {
    testWidgets('renders without overflow at ${size.width.toInt()} px', (
      tester,
    ) async {
      await _pump(
        tester,
        size: size,
        components: <LeaseComponentDto>[
          _component(type: LeaseComponentType.baseRent, amount: 1234.56),
          _component(
            type: LeaseComponentType.serviceChargeAdvance,
            amount: 210,
            vatMode: LeaseComponentVatMode.net,
            vatRate: 19,
          ),
        ],
      );

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('net and gross amounts are not added together', (tester) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        // Payable as it stands.
        _component(type: LeaseComponentType.baseRent, amount: 1000),
        // Payable plus tax. Each number in the column is correct; their sum
        // would be neither a net nor a gross figure.
        _component(
          type: LeaseComponentType.parking,
          amount: 100,
          vatMode: LeaseComponentVatMode.net,
          vatRate: 19,
        ),
      ],
    );

    expect(
      tester.widget<Text>(find.byKey(const Key('lease-components-total'))).data,
      'nicht summierbar',
    );
    expect(
      find.textContaining('Netto- und Bruttobeträge stehen nebeneinander'),
      findsOneWidget,
    );
    // And not the currency sentence, which would name the wrong reason.
    expect(find.textContaining('verschiedene Währungen'), findsNothing);
  });

  testWidgets('an all-net set totals, and the label says it is net', (
    tester,
  ) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(
          type: LeaseComponentType.baseRent,
          amount: 2400,
          vatMode: LeaseComponentVatMode.net,
          vatRate: 19,
        ),
        _component(
          type: LeaseComponentType.serviceChargeAdvance,
          amount: 380,
          vatMode: LeaseComponentVatMode.net,
          vatRate: 19,
        ),
      ],
    );

    expect(
      tester.widget<Text>(find.byKey(const Key('lease-components-total'))).data,
      '2780.00 EUR',
    );
    // The qualifier belongs in the label: a net total read as a payable one is
    // off by the tax rate.
    expect(
      find.text('Summe der erfassten Bestandteile (netto)'),
      findsOneWidget,
    );
  });

  testWidgets('an unknown VAT mode blocks the total and says why', (
    tester,
  ) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
        _component(
          type: LeaseComponentType.unknown,
          amount: 25,
          vatMode: LeaseComponentVatMode.unknown,
          rawTypeKey: 'garden_levy',
        ),
      ],
    );

    expect(
      tester.widget<Text>(find.byKey(const Key('lease-components-total'))).data,
      'nicht summierbar',
    );
    expect(
      find.textContaining('Steuerbehandlung'),
      findsWidgets,
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  LeaseComponentsPhase phase = LeaseComponentsPhase.ready,
  List<LeaseComponentDto>? components,
  DateTime? asOf,
  VoidCallback? onRetry,
  Size size = const Size(1000, 900),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LeaseComponentsSection(
            phase: phase,
            components: components == null
                ? null
                : LeaseComponentsAsOfDto(
                    asOfDate: asOf ?? DateTime(2026, 3, 15),
                    components: components,
                  ),
            onRetry: onRetry ?? () {},
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // An indeterminate progress indicator animates forever; settling would time
    // out instead of asserting.
    await tester.pump();
  }
}

LeaseComponentDto _component({
  required LeaseComponentType type,
  required double amount,
  String currency = 'EUR',
  LeaseComponentVatMode vatMode = LeaseComponentVatMode.exempt,
  double? vatRate,
  DateTime? validTo,
  String? rawTypeKey,
}) => LeaseComponentDto(
  id: 'k-${type.name}',
  leaseId: 'l1',
  propertyId: 'p1',
  componentType: type,
  amount: amount,
  currencyCode: currency,
  vatMode: vatMode,
  vatRatePercent: vatRate,
  validFrom: DateTime(2026, 1, 1),
  validTo: validTo,
  version: 1,
  rawTypeKey: rawTypeKey,
);
