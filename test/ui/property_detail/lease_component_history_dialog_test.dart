/// LEASING-COMPONENTS-02 (V-2b) on screen.
///
/// The timeline's job is to make a hole in a contract visible in the place it
/// happened. So the assertion that matters most is the interleaving: a gap
/// listed under the periods reads as a footnote, while a gap drawn between the
/// period before it and the period after it reads as the missing step it is.
///
/// The second job is restraint. The server reports interior gaps only, and the
/// dialog must not add its own — a lease whose components were entered years
/// after it began would otherwise open with a red line at the top, every time,
/// for every migrated tenancy in the portfolio.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/leasing_operations/application/leases_controller.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_component_dto.dart';
import 'package:neximmo_app/ui/screens/property_detail/leasing/widgets/lease_component_history_dialog.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

LeaseComponentPeriodDto _period({
  required String from,
  String? to,
  required double amount,
  bool inForce = false,
  String? note,
  LeaseComponentVatMode vatMode = LeaseComponentVatMode.exempt,
  double? rate,
}) {
  return LeaseComponentPeriodDto(
    id: 'p-$from',
    validFrom: DateTime.parse(from),
    validTo: to == null ? null : DateTime.parse(to),
    amount: amount,
    currencyCode: 'EUR',
    vatMode: vatMode,
    vatRatePercent: rate,
    note: note,
    version: 1,
    inForce: inForce,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required LeaseComponentHistoryPhase phase,
  LeaseComponentHistoryDto? history,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: LeaseComponentHistoryDialog(
          phase: phase,
          history: history,
          onRetry: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

LeaseComponentHistoryDto _history(List<LeaseComponentTimelineDto> timelines) {
  return LeaseComponentHistoryDto(
    leaseId: 'lease-1',
    asOfDate: DateTime.parse('2026-09-07'),
    timelines: timelines,
  );
}

void main() {
  testWidgets('shows every period of a type, not just the current one', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: LeaseComponentHistoryPhase.ready,
      history: _history(<LeaseComponentTimelineDto>[
        LeaseComponentTimelineDto(
          componentType: LeaseComponentType.baseRent,
          periods: <LeaseComponentPeriodDto>[
            _period(from: '2024-01-01', to: '2024-06-30', amount: 800),
            _period(
              from: '2025-01-01',
              to: '2027-01-31',
              amount: 900,
              inForce: true,
            ),
            _period(from: '2027-02-01', amount: 950, note: 'Erhöhung'),
          ],
          gaps: const <LeaseComponentGap>[],
        ),
      ]),
    );

    expect(find.text('Grundmiete'), findsOneWidget);
    expect(find.textContaining('800.00'), findsOneWidget);
    expect(find.textContaining('900.00'), findsOneWidget);
    expect(
      find.textContaining('950.00'),
      findsOneWidget,
      reason: 'including the one that starts in the future -- showing it is '
          'the point, and the as-of read never could',
    );
    expect(find.text('Erhöhung'), findsOneWidget);
  });

  testWidgets('marks exactly the period the server called current', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: LeaseComponentHistoryPhase.ready,
      history: _history(<LeaseComponentTimelineDto>[
        LeaseComponentTimelineDto(
          componentType: LeaseComponentType.baseRent,
          periods: <LeaseComponentPeriodDto>[
            _period(from: '2024-01-01', to: '2024-06-30', amount: 800),
            _period(from: '2025-01-01', amount: 900, inForce: true),
          ],
          gaps: const <LeaseComponentGap>[],
        ),
      ]),
    );

    expect(
      find.text('aktuell'),
      findsOneWidget,
      reason: 'one badge, not one per period and not none -- the table forbids '
          'two periods covering the same day',
    );
  });

  testWidgets('draws a gap between the periods it separates', (tester) async {
    await _pump(
      tester,
      phase: LeaseComponentHistoryPhase.ready,
      history: _history(<LeaseComponentTimelineDto>[
        LeaseComponentTimelineDto(
          componentType: LeaseComponentType.baseRent,
          periods: <LeaseComponentPeriodDto>[
            _period(from: '2024-01-01', to: '2024-06-30', amount: 800),
            _period(from: '2025-01-01', amount: 900, inForce: true),
          ],
          gaps: <LeaseComponentGap>[
            LeaseComponentGap(
              from: DateTime.parse('2024-07-01'),
              to: DateTime.parse('2024-12-31'),
            ),
          ],
        ),
      ]),
    );

    expect(find.text('1 Lücke'), findsOneWidget);
    expect(
      find.textContaining('01.07.2024 – 31.12.2024: nicht erfasst'),
      findsOneWidget,
    );

    // Ordered by start date: the gap sits between the two periods rather than
    // below them. Compared by vertical position, because that is the thing the
    // reader actually uses to understand the sequence.
    final double firstPeriod = tester
        .getTopLeft(find.textContaining('01.01.2024'))
        .dy;
    final double gap = tester
        .getTopLeft(find.textContaining('01.07.2024'))
        .dy;
    final double secondPeriod = tester
        .getTopLeft(find.textContaining('01.01.2025'))
        .dy;
    expect(firstPeriod, lessThan(gap));
    expect(gap, lessThan(secondPeriod));
  });

  testWidgets('a timeline without gaps shows no warning at all', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: LeaseComponentHistoryPhase.ready,
      history: _history(<LeaseComponentTimelineDto>[
        LeaseComponentTimelineDto(
          componentType: LeaseComponentType.serviceChargeAdvance,
          periods: <LeaseComponentPeriodDto>[
            _period(from: '2025-01-01', amount: 150, inForce: true),
          ],
          gaps: const <LeaseComponentGap>[],
        ),
      ]),
    );

    // The type renders, so the two absences below cannot pass by the widget
    // having drawn nothing.
    expect(find.text('Betriebskostenvorauszahlung'), findsOneWidget);
    expect(find.byKey(const Key('lease-component-history-gap')), findsNothing);
    expect(
      find.textContaining('Lücke'),
      findsNothing,
      reason: 'the years before 2025 are not a gap. A dialog that opened with '
          'a red line for every migrated tenancy would train people to ignore '
          'the one that means something',
    );
  });

  testWidgets('a net period says what its gross is, and says when it cannot', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: LeaseComponentHistoryPhase.ready,
      history: _history(<LeaseComponentTimelineDto>[
        LeaseComponentTimelineDto(
          componentType: LeaseComponentType.other,
          periods: <LeaseComponentPeriodDto>[
            _period(
              from: '2025-01-01',
              to: '2025-12-31',
              amount: 100,
              vatMode: LeaseComponentVatMode.net,
              rate: 19,
            ),
            _period(
              from: '2026-01-01',
              amount: 100,
              vatMode: LeaseComponentVatMode.net,
              inForce: true,
            ),
          ],
          gaps: const <LeaseComponentGap>[],
        ),
      ]),
    );

    expect(find.textContaining('brutto 119.00 EUR'), findsOneWidget);
    expect(
      find.textContaining('brutto nicht ermittelbar'),
      findsOneWidget,
      reason: 'a net amount without a rate cannot be grossed up, and showing '
          'the net figure as gross is the one thing this must never do',
    );
  });

  testWidgets('an unfamiliar type is shown by its raw key', (tester) async {
    await _pump(
      tester,
      phase: LeaseComponentHistoryPhase.ready,
      history: _history(<LeaseComponentTimelineDto>[
        LeaseComponentTimelineDto(
          componentType: LeaseComponentType.unknown,
          rawTypeKey: 'index_rent',
          periods: <LeaseComponentPeriodDto>[
            _period(from: '2025-01-01', amount: 100, inForce: true),
          ],
          gaps: const <LeaseComponentGap>[],
        ),
      ]),
    );

    expect(find.text('index_rent'), findsOneWidget);
    expect(find.text('Unbekannter Bestandteil'), findsNothing);
  });

  testWidgets('a refused history says so instead of looking empty', (
    tester,
  ) async {
    await _pump(tester, phase: LeaseComponentHistoryPhase.forbidden);

    expect(
      find.byKey(const Key('lease-component-history-forbidden')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('lease-component-history-empty')),
      findsNothing,
      reason: '"nothing recorded" is a claim about the contract; "no access" '
          'is a claim about the reader, and they must never be confused',
    );
  });

  testWidgets('a failed history offers a retry', (tester) async {
    await _pump(tester, phase: LeaseComponentHistoryPhase.error);

    expect(
      find.byKey(const Key('lease-component-history-error')),
      findsOneWidget,
    );
    expect(find.text('Erneut laden'), findsOneWidget);
  });

  testWidgets('a lease with no components at all says so positively', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: LeaseComponentHistoryPhase.ready,
      history: _history(const <LeaseComponentTimelineDto>[]),
    );

    expect(
      find.byKey(const Key('lease-component-history-empty')),
      findsOneWidget,
    );
  });

  testWidgets('renders without overflow at a phone width', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: LeaseComponentHistoryDialog(
            phase: LeaseComponentHistoryPhase.ready,
            history: _history(<LeaseComponentTimelineDto>[
              LeaseComponentTimelineDto(
                componentType: LeaseComponentType.serviceChargeAdvance,
                periods: <LeaseComponentPeriodDto>[
                  for (int year = 2018; year < 2026; year++)
                    _period(
                      from: '$year-01-01',
                      to: '$year-12-31',
                      amount: 100 + year.toDouble(),
                      note: 'Anpassung zum Jahreswechsel $year',
                    ),
                ],
                gaps: const <LeaseComponentGap>[],
              ),
            ]),
            onRetry: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
