/// PROPERTY-CARD-METRICS-01, on the card.
///
/// The one rule these tests exist to hold: **nothing renders as zero.** A
/// property whose metrics have not arrived, a property the server withheld and
/// a section the caller may not read all look the same on a card — no figures
/// — and none of them may look like a property with nothing open.
///
/// Every "shows nothing" assertion here is paired with a "shows something"
/// assertion using the same finder. On its own, `findsNothing` would also pass
/// if the widget stopped rendering facts altogether.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_card_metrics_dto.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_overview_dto.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_card.dart';

import 'property_workspace_fixtures.dart';

PropertyCardMetricsDto _metrics({
  Map<String, int>? leasing,
  Map<String, int>? maintenance,
  String? leasingDenied,
  String? maintenanceDenied,
}) {
  return PropertyCardMetricsDto(
    propertyId: 'property-a',
    leasing: leasingDenied != null
        ? PropertyOverviewSection.unavailable(leasingDenied)
        : PropertyOverviewSection.available(leasing ?? const <String, int>{}),
    maintenance: maintenanceDenied != null
        ? PropertyOverviewSection.unavailable(maintenanceDenied)
        : PropertyOverviewSection.available(
            maintenance ?? const <String, int>{},
          ),
  );
}

Future<void> _pump(WidgetTester tester, PropertyCardMetricsDto? metrics) async {
  setViewport(tester, const Size(420, 900));
  await tester.pumpWidget(
    wrapApp(
      PropertyCard(
        property: PropertySummaryDto.fromProperty(property()),
        metrics: metrics,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows occupied out of total, not a percentage', (tester) async {
    await _pump(
      tester,
      _metrics(leasing: const <String, int>{
        'units_total': 4,
        'units_occupied': 3,
      }),
    );

    expect(find.text('3/4 vermietet'), findsOneWidget);
    expect(
      find.textContaining('%'),
      findsNothing,
      reason: 'by unit or by area is an owner decision nobody has taken, so '
          'the card reports the constituents and lets the reader see the '
          'fraction without the server picking a denominator',
    );
  });

  testWidgets('a fully vacant property still states its occupancy', (
    tester,
  ) async {
    await _pump(
      tester,
      _metrics(leasing: const <String, int>{
        'units_total': 12,
        'units_occupied': 0,
      }),
    );

    expect(
      find.text('0/12 vermietet'),
      findsOneWidget,
      reason: 'the one figure a card must never suppress -- it is the whole '
          'reason to look at the grid rather than the list',
    );
  });

  testWidgets('open tickets and expiring leases appear only when there are '
      'any', (tester) async {
    await _pump(
      tester,
      _metrics(
        leasing: const <String, int>{
          'units_total': 4,
          'units_occupied': 4,
          'leases_ending_90d': 1,
          'leases_expired_open': 2,
        },
        maintenance: const <String, int>{
          'tickets_open': 3,
          'tickets_overdue': 1,
        },
      ),
    );

    expect(find.text('1 läuft aus'), findsOneWidget);
    expect(find.text('2 Verträge überfällig'), findsOneWidget);
    expect(find.text('3 Tickets offen'), findsOneWidget);
  });

  testWidgets('and are absent, not zero, when the counts are zero', (
    tester,
  ) async {
    await _pump(
      tester,
      _metrics(
        leasing: const <String, int>{
          'units_total': 4,
          'units_occupied': 4,
          'leases_ending_90d': 0,
          'leases_expired_open': 0,
        },
        maintenance: const <String, int>{'tickets_open': 0},
      ),
    );

    // The occupancy fact proves the row is rendering at all, so the three
    // findsNothing below cannot pass by the widget having disappeared.
    expect(find.text('4/4 vermietet'), findsOneWidget);
    expect(find.textContaining('läuft aus'), findsNothing);
    expect(find.textContaining('überfällig'), findsNothing);
    expect(
      find.textContaining('Tickets offen'),
      findsNothing,
      reason: '"0 Tickets offen" is not news, and a card that listed every '
          'zero would bury the one property that has a problem',
    );
  });

  testWidgets('a section the caller may not read contributes nothing', (
    tester,
  ) async {
    await _pump(
      tester,
      _metrics(
        leasing: const <String, int>{'units_total': 4, 'units_occupied': 3},
        maintenanceDenied: 'maintenance.read',
      ),
    );

    expect(find.text('3/4 vermietet'), findsOneWidget);
    expect(
      find.textContaining('Ticket'),
      findsNothing,
      reason: 'never "0 Tickets offen" -- that would tell someone who may not '
          'see tickets that there are none',
    );
  });

  testWidgets('without metrics the card shows the row facts and no figures', (
    tester,
  ) async {
    await _pump(tester, null);

    // Type and recorded unit count come from the list row and are always
    // there; their presence is what makes the absence below meaningful.
    expect(find.text('Gemischt'), findsOneWidget);
    expect(find.text('12 Einheiten'), findsOneWidget);
    expect(
      find.textContaining('vermietet'),
      findsNothing,
      reason: 'not loaded yet, withheld, or a failed read -- all three mean '
          'the card has nothing to say, and saying 0 would be a claim',
    );
  });

  testWidgets('the recorded unit count and the counted units are both shown '
      'when they disagree', (tester) async {
    await _pump(
      tester,
      _metrics(leasing: const <String, int>{
        'units_total': 9,
        'units_occupied': 7,
      }),
    );

    // `property()` records 12 units; the register holds 9. A building half
    // entered looks exactly like this, and hiding either number would make
    // the discrepancy invisible instead of obvious.
    expect(find.text('12 Einheiten'), findsOneWidget);
    expect(find.text('7/9 vermietet'), findsOneWidget);
  });

  testWidgets('a property with no units recorded shows no occupancy', (
    tester,
  ) async {
    await _pump(
      tester,
      _metrics(leasing: const <String, int>{
        'units_total': 0,
        'units_occupied': 0,
      }),
    );

    expect(
      find.textContaining('vermietet'),
      findsNothing,
      reason: '"0/0 vermietet" says nothing about a property whose units have '
          'simply not been entered yet',
    );
    expect(
      find.text('12 Einheiten'),
      findsOneWidget,
      reason: 'while the figure typed on the property is still shown',
    );
  });
}
