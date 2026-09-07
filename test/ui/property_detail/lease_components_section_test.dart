import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/leasing_operations/application/leases_controller.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_component_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/warm_rent_dto.dart';
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
    // A component that was ended is absent on a later date and renders the
    // same way as one that was never entered. The as-of read returns only what
    // is in force, so this section cannot tell them apart — it says so, and
    // since LEASING-COMPONENTS-02 it names where the answer is instead of
    // leaving the reader with the question.
    expect(
      find.textContaining('Er kann fehlen oder beendet sein'),
      findsOneWidget,
    );
    expect(
      find.textContaining('zeigt der Verlauf'),
      findsOneWidget,
      reason: 'the sentence used to end "eine Historie zeigt dieser Abschnitt '
          'noch nicht", which V-2b made untrue',
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

  testWidgets('offers nothing to write without lease.manage', (tester) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
      ],
      canMutate: false,
      onAdd: (_) {},
      onEdit: (_) {},
      onClose: (_) {},
    );

    // The server checks it too; this only decides whether a control is offered,
    // so nobody spends a round trip on a certain refusal.
    expect(find.byKey(const Key('lease-component-add')), findsNothing);
    expect(find.text('erfassen'), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });

  testWidgets('an unrecorded row offers to record that very type', (
    tester,
  ) async {
    LeaseComponentType? asked;
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
      ],
      canMutate: true,
      onAdd: (type) => asked = type,
    );

    // Four types are unrecorded, so four offers - and the one tapped carries
    // its own type into the form rather than making the reader pick it again.
    expect(find.text('erfassen'), findsNWidgets(4));
    await tester.tap(find.text('erfassen').first);
    await tester.pumpAndSettle();
    expect(asked, LeaseComponentType.serviceChargeAdvance);
  });

  testWidgets('the add button carries no preselection', (tester) async {
    var calls = 0;
    LeaseComponentType? asked = LeaseComponentType.parking;
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
      ],
      canMutate: true,
      onAdd: (type) {
        calls++;
        asked = type;
      },
    );

    await tester.tap(find.byKey(const Key('lease-component-add')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(asked, isNull);
  });

  testWidgets('an empty section still offers a way in', (tester) async {
    await _pump(
      tester,
      components: const <LeaseComponentDto>[],
      canMutate: true,
      onAdd: (_) {},
    );

    // Otherwise the only screen where nothing exists is the one screen with no
    // way to create anything.
    expect(find.byKey(const Key('lease-component-add')), findsOneWidget);
  });

  testWidgets('only a running component can be ended', (tester) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
        _component(
          type: LeaseComponentType.parking,
          amount: 50,
          validTo: DateTime(2026, 12, 31),
        ),
      ],
      canMutate: true,
      onEdit: (_) {},
      onClose: (_) {},
    );

    await tester.tap(
      find.byKey(const Key('lease-component-actions-k-baseRent')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beenden'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // A component that already has an end date is corrected through the form,
    // where the date is a field rather than the whole action.
    await tester.tap(
      find.byKey(const Key('lease-component-actions-k-parking')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beenden'), findsNothing);
    expect(find.text('Bearbeiten'), findsOneWidget);
  });

  testWidgets('an unfamiliar component offers no actions at all', (
    tester,
  ) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(
          type: LeaseComponentType.unknown,
          amount: 25,
          rawTypeKey: 'garden_levy',
        ),
      ],
      canMutate: true,
      onEdit: (_) {},
      onClose: (_) {},
    );

    // This build does not know what the type means, so it must not offer to
    // rewrite it.
    expect(find.text('garden_levy'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });

  testWidgets('a type recorded before but not today says so, and blocks the '
      'total', (tester) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
      ],
      coverage: <LeaseComponentCoverage>[
        _coverage(
          types: <LeaseComponentCoverageType>[
            _coverageType(LeaseComponentType.baseRent, inForce: true),
            _coverageType(
              LeaseComponentType.parking,
              inForce: false,
              gapCount: 1,
              openGapFrom: DateTime(2026, 6, 1),
            ),
          ],
        ),
      ],
      // The server's answer, not the section's: since WARM-RENT-01 the figure
      // is withheld server-side and this widget reports the refusal.
      warmRent: const WarmRentDto(
        leaseId: 'l1',
        propertyId: 'p1',
        currencyCode: 'EUR',
        isWarm: false,
        gapTypes: <LeaseComponentType>[LeaseComponentType.parking],
      ),
    );

    // Until LEASING-COMPONENTS-01c this read exactly like a type nobody had
    // ever recorded.
    expect(find.text('seit 01.06.2026 nicht erfasst'), findsOneWidget);
    expect(find.text('nicht erfasst'), findsNWidgets(3));

    // And the figure must not quietly leave it out — DEC-029 in as many words:
    // never sum around a gap. The server withholds it and the section says why.
    expect(
      tester.widget<Text>(find.byKey(const Key('lease-components-total'))).data,
      'nicht ermittelbar',
    );
    expect(
      find.textContaining('plausible, falsche Zahl'),
      findsOneWidget,
    );
  });

  testWidgets('a hole earlier in the term is reported even though today looks '
      'complete', (tester) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
      ],
      coverage: <LeaseComponentCoverage>[
        _coverage(
          complete: false,
          types: <LeaseComponentCoverageType>[
            _coverageType(
              LeaseComponentType.baseRent,
              inForce: true,
              gapCount: 1,
              firstGapFrom: DateTime(2026, 3, 1),
            ),
          ],
        ),
      ],
    );

    // The component IS in force, so nothing on the row is wrong; the gap is
    // in July of some other reading and would never have surfaced.
    expect(
      find.byKey(const Key('lease-components-history-gaps')),
      findsOneWidget,
    );
    expect(find.textContaining('erste ab 01.03.2026'), findsOneWidget);
    expect(
      find.textContaining('nicht aus den Vertragsbeginn-Zahlen ergänzt'),
      findsOneWidget,
    );
  });

  testWidgets('no gaps means no notice at all', (tester) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
      ],
      coverage: <LeaseComponentCoverage>[
        _coverage(
          types: <LeaseComponentCoverageType>[
            _coverageType(LeaseComponentType.baseRent, inForce: true),
          ],
        ),
      ],
      warmRent: const WarmRentDto(
        leaseId: 'l1',
        propertyId: 'p1',
        currencyCode: 'EUR',
        isWarm: true,
        netMonthly: 1000,
      ),
    );

    // The counterpart assertion: a widget that always warned would pass the
    // two above and fail here.
    expect(
      find.byKey(const Key('lease-components-history-gaps')),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('lease-components-total'))).data,
      '1000.00 EUR',
    );
    expect(find.text('Warmmiete'), findsOneWidget);
  });

  testWidgets('without coverage the rows read as before', (tester) async {
    await _pump(
      tester,
      components: <LeaseComponentDto>[
        _component(type: LeaseComponentType.baseRent, amount: 1000),
      ],
    );

    // A server that predates 01c sends no coverage. The section must not start
    // claiming things it was not told.
    expect(find.text('nicht erfasst'), findsNWidgets(4));
    // Not `textContaining('seit')` — an open-ended period legitimately reads
    // "seit 01.01.2026", and an assertion that cannot tell the two apart tests
    // the wrong thing.
    expect(find.textContaining('seit'), findsWidgets);
    expect(find.text('für diesen Stichtag nicht erfasst'), findsNothing);
    expect(find.textContaining('seit 01.06.2026 nicht erfasst'), findsNothing);
    expect(
      find.byKey(const Key('lease-components-history-gaps')),
      findsNothing,
    );
  });

  test('complete is true when there is nothing to cover', () {
    final dto = LeaseComponentsAsOfDto(
      asOfDate: DateTime(2026, 9, 7),
      components: const <LeaseComponentDto>[],
    );

    // Nothing to cover, so nothing incomplete. The total that used to be
    // asserted here moved to the server with WARM-RENT-01 — this type no
    // longer adds money up at all, which was the point.
    expect(dto.complete, isTrue);
  });
}

LeaseComponentCoverage _coverage({
  required List<LeaseComponentCoverageType> types,
  bool complete = true,
}) => LeaseComponentCoverage(
  leaseId: 'l1',
  windowFrom: DateTime(2026, 1, 1),
  windowTo: DateTime(2026, 9, 7),
  complete: complete,
  types: types,
);

LeaseComponentCoverageType _coverageType(
  LeaseComponentType type, {
  required bool inForce,
  int gapCount = 0,
  DateTime? firstGapFrom,
  DateTime? openGapFrom,
}) => LeaseComponentCoverageType(
  componentType: type,
  inForce: inForce,
  gapCount: gapCount,
  firstGapFrom: firstGapFrom,
  firstGapTo: firstGapFrom?.add(const Duration(days: 30)),
  openGapFrom: openGapFrom,
);

Future<void> _pump(
  WidgetTester tester, {
  LeaseComponentsPhase phase = LeaseComponentsPhase.ready,
  List<LeaseComponentDto>? components,
  List<LeaseComponentCoverage> coverage = const <LeaseComponentCoverage>[],
  WarmRentDto? warmRent,
  DateTime? asOf,
  VoidCallback? onRetry,
  Size size = const Size(1000, 900),
  bool settle = true,
  bool canMutate = false,
  void Function(LeaseComponentType? preselectedType)? onAdd,
  void Function(LeaseComponentDto component)? onEdit,
  void Function(LeaseComponentDto component)? onClose,
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
                    coverage: coverage,
                  ),
            onRetry: onRetry ?? () {},
            warmRent: warmRent,
            canMutate: canMutate,
            onAdd: onAdd,
            onEdit: onEdit,
            onClose: onClose,
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
