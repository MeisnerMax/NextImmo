import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_workspace_host_state.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_overview_dto.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_overview_panel.dart';

import 'property_workspace_fixtures.dart';

/// `Übersicht` (`PROPERTY_OVERVIEW_V2.md` on `PROPERTY-OVERVIEW-DATA-01`).
///
/// The screen's whole value is honesty about what it knows, so that is what
/// these tests pin: a figure is exactly what the server counted, a section the
/// membership may not read is visibly different from an empty one, attention
/// keeps the server's order, and nothing on the surface is computed here.
void main() {
  group('Property overview', () {
    testWidgets('renders the counts the server sent, with their freshness', (
      tester,
    ) async {
      await _pump(tester, _Load(overview()));

      expect(find.byKey(const Key('property-overview')), findsOneWidget);
      expect(
        find.byKey(const Key('property-overview-as-of')),
        findsOneWidget,
        reason: 'the overview states how old it is',
      );
      expect(find.textContaining('06.09.2026'), findsWidgets);

      // Leasing counters, straight from the payload.
      expect(find.text('Flächen gesamt'), findsOneWidget);
      expect(find.text('12'), findsWidgets);
      expect(find.text('Abgelaufen, noch aktiv'), findsOneWidget);
      // Nothing derived: no occupancy rate anywhere on the surface.
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('a section the membership may not read names its capability '
        'and shows no number', (tester) async {
      await _pump(
        tester,
        _Load(
          overview(
            maintenance: const PropertyOverviewSection.unavailable(
              'maintenance.read',
            ),
          ),
        ),
      );

      expect(find.textContaining('maintenance.read'), findsOneWidget);
      expect(
        find.text('Offene Tickets'),
        findsNothing,
        reason: 'an unavailable section has no counter rows at all',
      );
      expect(
        find.byKey(const Key('property-overview-kpi-tickets')),
        findsNothing,
        reason: 'and no KPI tile, because there is no number to show',
      );
    });

    testWidgets('an unavailable section never renders as zero', (tester) async {
      await _pump(
        tester,
        _Load(
          overview(
            documents: const PropertyOverviewSection.unavailable(
              'document.read',
            ),
            // Everything else is unavailable too, so a stray `0` could only
            // come from the client inventing one.
            leasing: const PropertyOverviewSection.unavailable('lease.read'),
            maintenance: const PropertyOverviewSection.unavailable(
              'maintenance.read',
            ),
            capex: const PropertyOverviewSection.unavailable('capex.read'),
            tasks: const PropertyOverviewSection.unavailable('task.read'),
            valuation: const PropertyOverviewSection.unavailable(
              'valuation.read',
            ),
          ),
        ),
      );

      expect(find.text('0'), findsNothing);
      expect(find.byKey(const Key('property-overview-kpis')), findsNothing);
      expect(find.textContaining('Benötigt die Berechtigung'), findsWidgets);
    });

    testWidgets('a real zero is shown, because the server counted it', (
      tester,
    ) async {
      await _pump(
        tester,
        _Load(
          overview(
            tasks: const PropertyOverviewSection.available(<String, int>{
              'tasks_open': 0,
              'tasks_overdue': 0,
              'tasks_blocked': 0,
            }),
          ),
        ),
      );

      expect(find.text('0'), findsWidgets);
    });

    testWidgets('attention keeps the order the server sent', (tester) async {
      await _pump(
        tester,
        _Load(
          overview(
            attention: const <PropertyOverviewAttention>[
              PropertyOverviewAttention(
                type: 'tickets_overdue',
                severity: PropertyAttentionSeverity.critical,
                count: 2,
                domain: 'operations',
              ),
              PropertyOverviewAttention(
                type: 'leases_ending_90d',
                severity: PropertyAttentionSeverity.warning,
                count: 2,
                domain: 'leasing',
              ),
              PropertyOverviewAttention(
                type: 'units_vacant',
                severity: PropertyAttentionSeverity.info,
                count: 3,
                domain: 'leasing',
              ),
            ],
          ),
        ),
      );

      final labels =
          tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byKey(const Key('property-overview-attention')),
                  matching: find.byType(Text),
                ),
              )
              .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
              .where((value) => value.contains(':'))
              .toList();
      expect(
        labels,
        <String>[
          'Kritisch: Überfällige Tickets',
          'Warnung: Verträge mit Ende in 90 Tagen',
          'Hinweis: Leerstehende Flächen',
        ],
        reason: 'the client renders the server order and never re-ranks it',
      );
    });

    testWidgets('severity carries a word and an icon, not only a colour', (
      tester,
    ) async {
      await _pump(
        tester,
        _Load(
          overview(
            attention: const <PropertyOverviewAttention>[
              PropertyOverviewAttention(
                type: 'tickets_overdue',
                severity: PropertyAttentionSeverity.critical,
                count: 2,
                domain: 'operations',
              ),
            ],
          ),
        ),
      );

      expect(find.textContaining('Kritisch'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('property-overview-attention')),
          matching: find.byIcon(Icons.error_outline),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an empty attention list says what it actually means', (
      tester,
    ) async {
      await _pump(tester, _Load(overview()));

      expect(
        find.byKey(const Key('property-overview-attention-empty')),
        findsOneWidget,
      );
      // It scopes the statement to what this membership may read instead of
      // claiming the property is fine.
      expect(find.textContaining('lesen dürfen'), findsOneWidget);
    });

    testWidgets(
      'an unknown attention type stays visible instead of vanishing',
      (tester) async {
        await _pump(
          tester,
          _Load(
            overview(
              attention: const <PropertyOverviewAttention>[
                PropertyOverviewAttention(
                  type: 'insurance_expired',
                  severity: PropertyAttentionSeverity.critical,
                  count: 1,
                  domain: 'documents',
                ),
              ],
            ),
          ),
        );

        expect(find.textContaining('insurance_expired'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Drilldown
    // -----------------------------------------------------------------------

    testWidgets('an attention row drills into the domain that owns it', (
      tester,
    ) async {
      final opened = <PropertyWorkspaceDomain>[];
      await _pump(
        tester,
        _Load(
          overview(
            attention: const <PropertyOverviewAttention>[
              PropertyOverviewAttention(
                type: 'tickets_overdue',
                severity: PropertyAttentionSeverity.critical,
                count: 2,
                domain: 'operations',
              ),
            ],
          ),
        ),
        onOpenDomain: opened.add,
      );

      await tester.tap(
        find.byKey(const Key('property-overview-attention-tickets_overdue')),
      );
      await tester.pump();

      expect(opened, <PropertyWorkspaceDomain>[
        PropertyWorkspaceDomain.operations,
      ]);
    });

    testWidgets('a KPI tile drills into its domain', (tester) async {
      final opened = <PropertyWorkspaceDomain>[];
      await _pump(tester, _Load(overview()), onOpenDomain: opened.add);

      await tester.tap(find.byKey(const Key('property-overview-kpi-units')));
      await tester.pump();

      expect(opened, <PropertyWorkspaceDomain>[
        PropertyWorkspaceDomain.leasing,
      ]);
    });

    testWidgets('no drilldown into a domain this membership cannot open', (
      tester,
    ) async {
      final opened = <PropertyWorkspaceDomain>[];
      await _pump(
        tester,
        _Load(
          overview(
            attention: const <PropertyOverviewAttention>[
              PropertyOverviewAttention(
                type: 'tickets_overdue',
                severity: PropertyAttentionSeverity.critical,
                count: 2,
                domain: 'operations',
              ),
            ],
          ),
        ),
        // The membership can read the overview but not the operations domain.
        availableDomains: const <PropertyWorkspaceDomain>{
          PropertyWorkspaceDomain.overview,
          PropertyWorkspaceDomain.leasing,
        },
        onOpenDomain: opened.add,
      );

      expect(
        find.byKey(const Key('property-overview-attention-tickets_overdue')),
        findsNothing,
        reason: 'a dead affordance is worse than none',
      );
      expect(
        find.byKey(const Key('property-overview-operations-open')),
        findsNothing,
      );
      // The figures themselves stay: the server sent them, so the membership
      // may see them.
      expect(find.text('Offene Tickets'), findsOneWidget);
      expect(opened, isEmpty);
    });

    testWidgets('the valuation module drills into Investment where it is '
        'readable, and nowhere where it is not', (tester) async {
      final opened = <PropertyWorkspaceDomain>[];
      await _pump(
        tester,
        _Load(overview()),
        availableDomains: const <PropertyWorkspaceDomain>{
          ..._allDomains,
          PropertyWorkspaceDomain.investment,
        },
        onOpenDomain: opened.add,
      );
      await tester.tap(
        find.byKey(const Key('property-overview-valuation-open')),
      );
      await tester.pump();
      expect(opened, <PropertyWorkspaceDomain>[
        PropertyWorkspaceDomain.investment,
      ]);

      // Without valuation.read the domain is not in the membership's list, so
      // the module keeps its figures and loses only the affordance.
      await _pump(tester, _Load(overview()), onOpenDomain: (_) {});
      expect(
        find.byKey(const Key('property-overview-valuation')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-overview-valuation-open')),
        findsNothing,
      );
    });

    // -----------------------------------------------------------------------
    // States
    // -----------------------------------------------------------------------

    testWidgets('forbidden shows no figures at all', (tester) async {
      await _pump(
        tester,
        _Load.failure(
          const PropertyRepositoryFailure<PropertyOverviewDto>(
            kind: PropertyRepositoryFailureKind.forbidden,
            message: 'Property access is not permitted',
          ),
        ),
      );

      expect(
        find.byKey(const Key('property-overview-forbidden')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('property-overview')), findsNothing);
    });

    testWidgets('a first-load failure offers a retry and then recovers', (
      tester,
    ) async {
      final load = _Load.failure(
        const PropertyRepositoryFailure<PropertyOverviewDto>(
          kind: PropertyRepositoryFailureKind.infrastructureFailure,
          message: 'Serverfehler.',
        ),
      );
      await _pump(tester, load);

      expect(find.byKey(const Key('property-overview-error')), findsOneWidget);
      load.result = PropertyRepositorySuccess<PropertyOverviewDto>(overview());
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('property-overview')), findsOneWidget);
    });

    testWidgets(
      'a failed refresh keeps the last figures and marks them stale',
      (tester) async {
        final load = _Load(overview());
        await _pump(tester, load);
        expect(find.byKey(const Key('property-overview-stale')), findsNothing);

        load.result = const PropertyRepositoryFailure<PropertyOverviewDto>(
          kind: PropertyRepositoryFailureKind.infrastructureFailure,
          message: 'Serverfehler.',
        );
        await tester.tap(find.byKey(const Key('property-overview-refresh')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.byKey(const Key('property-overview-stale')),
          findsOneWidget,
        );
        expect(
          find.text('Flächen gesamt'),
          findsOneWidget,
          reason: 'the last good snapshot stays visible',
        );
      },
    );

    testWidgets('a late answer for the previous property is discarded', (
      tester,
    ) async {
      final load = _Load(overview());
      load.gate = Completer<void>();
      await tester.pumpWidget(
        wrapApp(
          PropertyOverviewPanel(
            propertyId: 'property-a',
            onLoad: load.call,
            availableDomains: _allDomains,
          ),
        ),
      );
      await tester.pump();

      // The user switches property while the first read is still in flight.
      load.result = PropertyRepositorySuccess<PropertyOverviewDto>(
        overview(propertyId: 'property-b'),
      );
      await tester.pumpWidget(
        wrapApp(
          PropertyOverviewPanel(
            propertyId: 'property-b',
            onLoad: load.call,
            availableDomains: _allDomains,
          ),
        ),
      );
      load.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(load.requested, <String>['property-a', 'property-b']);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('property-overview')), findsOneWidget);
    });

    testWidgets('what is not covered yet is named, not faked', (tester) async {
      await _pump(tester, _Load(overview()));
      await tester.scrollUntilVisible(
        find.byKey(const Key('property-overview-coverage')),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(
        find.byKey(const Key('property-overview-coverage')),
        findsOneWidget,
      );
      expect(find.textContaining('nicht geschätzt'), findsOneWidget);
      // No invented financial figures anywhere.
      expect(find.textContaining('NOI:'), findsNothing);
      expect(find.textContaining('€'), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Responsive
    // -----------------------------------------------------------------------

    for (final viewport in goldenViewports) {
      testWidgets('has no overflow at $viewport', (tester) async {
        await _pump(
          tester,
          _Load(
            overview(
              attention: const <PropertyOverviewAttention>[
                PropertyOverviewAttention(
                  type: 'tickets_overdue',
                  severity: PropertyAttentionSeverity.critical,
                  count: 2,
                  domain: 'operations',
                ),
              ],
            ),
          ),
          viewport: viewport,
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('property-overview')), findsOneWidget);
      });
    }
  });
}

const Set<PropertyWorkspaceDomain> _allDomains = <PropertyWorkspaceDomain>{
  PropertyWorkspaceDomain.overview,
  PropertyWorkspaceDomain.asset,
  PropertyWorkspaceDomain.leasing,
  PropertyWorkspaceDomain.operations,
  PropertyWorkspaceDomain.documents,
};

/// A scripted overview read. [result] can be swapped between calls to model a
/// refresh that fails, or a retry that succeeds.
class _Load {
  _Load(PropertyOverviewDto value)
    : result = PropertyRepositorySuccess<PropertyOverviewDto>(value);

  _Load.failure(this.result);

  PropertyRepositoryResult<PropertyOverviewDto> result;
  final List<String> requested = <String>[];

  /// Holds the answer until completed, to model a read still in flight.
  Completer<void>? gate;

  Future<PropertyRepositoryResult<PropertyOverviewDto>> call(
    String propertyId,
  ) async {
    requested.add(propertyId);
    if (gate != null) {
      await gate!.future;
    }
    return result;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Load load, {
  Set<PropertyWorkspaceDomain> availableDomains = _allDomains,
  ValueChanged<PropertyWorkspaceDomain>? onOpenDomain,
  Size viewport = const Size(1440, 900),
}) async {
  setViewport(tester, viewport);
  await tester.pumpWidget(
    wrapApp(
      PropertyOverviewPanel(
        propertyId: 'property-a',
        onLoad: load.call,
        availableDomains: availableDomains,
        onOpenDomain: onOpenDomain,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
