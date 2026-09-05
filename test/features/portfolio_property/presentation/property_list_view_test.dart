import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_list_view.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';

import 'property_workspace_fixtures.dart';

void main() {
  _searchTests();
  group('PropertyListView', () {
    testWidgets('shows a skeleton while the first page loads', (tester) async {
      await _pump(
        tester,
        sliceState(
          listPhase: PropertyListPhase.loading,
          properties: const <PropertySummaryDto>[],
        ),
      );

      expect(find.byKey(const Key('property-list-skeleton')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders the table with summary data only, no search and no '
        'lifecycle actions', (tester) async {
      await _pump(
        tester,
        sliceState(
          properties: <PropertySummaryDto>[
            property(),
            property(
              id: 'property-b',
              name: 'Beta Offices',
              addressLine1: 'Office Road 2',
            ),
          ],
        ),
      );

      expect(find.byKey(const Key('property-list-table')), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Office Road 2, 10115 Berlin'), findsOneWidget);
      expect(
        find.byKey(const Key('property-list-open-property-a')),
        findsOneWidget,
      );
      expect(find.text('Atlas House'), findsOneWidget);
      expect(find.text('Long Street 123, 10115 Berlin'), findsOneWidget);
      expect(find.text('Aktiv'), findsNWidgets(2));
      expect(find.byKey(const Key('property-list-count')), findsOneWidget);
      expect(find.text('2 Objekte geladen'), findsOneWidget);
      // No text search in the approved increment.
      expect(find.byType(TextField), findsNothing);
      // No create/archive/restore/delete without PROPERTY-DATA-02.
      expect(find.byType(FilledButton), findsNothing);
      for (final forbidden in const <String>[
        'Neu',
        'Neues Objekt',
        'Archivieren',
        'Wiederherstellen',
        'Löschen',
      ]) {
        expect(find.text(forbidden), findsNothing);
      }
      // No KPI cells: only name, address, status columns.
      expect(find.text('NAME'), findsOneWidget);
      expect(find.text('ADRESSE'), findsOneWidget);
      expect(find.text('STATUS'), findsOneWidget);
    });

    testWidgets('opens a property through the row action once', (tester) async {
      final opened = <String>[];
      await _pump(tester, sliceState(), onOpenProperty: opened.add);

      await tester.tap(find.byKey(const Key('property-list-open-property-a')));
      await tester.pump();

      expect(opened, <String>['property-a']);
    });

    testWidgets('a row in flight shows progress and blocks a second open', (
      tester,
    ) async {
      final opened = <String>[];
      await _pump(
        tester,
        sliceState(
          properties: <PropertySummaryDto>[
            property(),
            property(id: 'property-b', name: 'Beta Offices'),
          ],
        ),
        onOpenProperty: opened.add,
        openingPropertyId: 'property-a',
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const Key('property-list-open-property-b')));
      await tester.pump();
      expect(opened, isEmpty);
    });

    testWidgets('renders cards on a phone and opens from the whole card', (
      tester,
    ) async {
      final opened = <String>[];
      await _pump(
        tester,
        sliceState(),
        viewport: const Size(390, 844),
        onOpenProperty: opened.add,
      );

      expect(find.byKey(const Key('property-list-cards')), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
      await tester.tap(find.byKey(const Key('property-list-card-property-a')));
      await tester.pump();
      expect(opened, <String>['property-a']);
    });

    testWidgets('offers load more only with a cursor and reports progress', (
      tester,
    ) async {
      var loadMoreCalls = 0;
      await _pump(
        tester,
        sliceState(nextCursor: 'property-a'),
        onLoadMore: () => loadMoreCalls++,
      );

      final button = find.byKey(const Key('property-list-load-more'));
      expect(button, findsOneWidget);
      expect(find.text('Weitere Objekte laden'), findsOneWidget);
      await tester.tap(button);
      expect(loadMoreCalls, 1);

      await _pump(
        tester,
        sliceState(
          listPhase: PropertyListPhase.loading,
          nextCursor: 'property-a',
        ),
      );
      expect(find.text('Lädt …'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(button).onPressed,
        isNull,
        reason: 'disabled while loading',
      );
      expect(
        find.byKey(const Key('property-list-table')),
        findsOneWidget,
        reason: 'loaded rows stay visible during load more',
      );

      await _pump(tester, sliceState());
      expect(button, findsNothing);
    });

    testWidgets('a load-more failure keeps the list and offers a retry', (
      tester,
    ) async {
      var loadMoreCalls = 0;
      await _pump(
        tester,
        sliceState(
          nextCursor: 'property-a',
          loadMoreFailureMessage: 'Temporary failure.',
        ),
        onLoadMore: () => loadMoreCalls++,
      );

      expect(find.byKey(const Key('property-list-table')), findsOneWidget);
      expect(
        find.byKey(const Key('property-list-load-more-error')),
        findsOneWidget,
      );
      expect(find.text('Temporary failure.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('property-list-load-more-retry')));
      expect(loadMoreCalls, 1);
    });

    testWidgets('empty active view offers the archive filter, archive view is '
        'plain empty', (tester) async {
      final filterChanges = <bool>[];
      await _pump(
        tester,
        sliceState(
          listPhase: PropertyListPhase.empty,
          properties: const <PropertySummaryDto>[],
        ),
        onSetIncludeArchived: filterChanges.add,
      );

      expect(find.byKey(const Key('property-list-no-match')), findsOneWidget);
      expect(find.byKey(const Key('property-list-empty')), findsNothing);
      await tester.tap(find.byKey(const Key('property-list-include-archived')));
      expect(filterChanges, <bool>[true]);

      await _pump(
        tester,
        sliceState(
          listPhase: PropertyListPhase.empty,
          properties: const <PropertySummaryDto>[],
          includeArchived: true,
        ),
      );
      expect(find.byKey(const Key('property-list-empty')), findsOneWidget);
      expect(find.byKey(const Key('property-list-no-match')), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('the archive filter chip reflects and switches the filter', (
      tester,
    ) async {
      final filterChanges = <bool>[];
      await _pump(
        tester,
        sliceState(includeArchived: true),
        onSetIncludeArchived: filterChanges.add,
      );

      final chip = find.byKey(const Key('property-list-archive-filter'));
      expect(tester.widget<FilterChip>(chip).selected, isTrue);
      await tester.tap(chip);
      expect(filterChanges, <bool>[false]);
    });

    testWidgets('forbidden is an explicit state naming the capability', (
      tester,
    ) async {
      await _pump(
        tester,
        sliceState(
          listPhase: PropertyListPhase.forbidden,
          properties: const <PropertySummaryDto>[],
          permissions: const <String>{},
        ),
      );

      expect(find.byKey(const Key('property-list-forbidden')), findsOneWidget);
      expect(find.textContaining('(property.read)'), findsOneWidget);
      expect(find.byKey(const Key('property-list-table')), findsNothing);
      expect(find.byKey(const Key('property-list-empty')), findsNothing);
      expect(find.byKey(const Key('property-list-no-match')), findsNothing);
    });

    testWidgets('a first-page error offers the single retry style', (
      tester,
    ) async {
      var reloads = 0;
      await _pump(
        tester,
        sliceState(
          listPhase: PropertyListPhase.error,
          properties: const <PropertySummaryDto>[],
          message: 'Backend down.',
        ),
        onReload: () => reloads++,
      );

      expect(find.byKey(const Key('property-list-error')), findsOneWidget);
      expect(find.text('Backend down.'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      expect(reloads, 1);
    });

    testWidgets('degraded live updates show the passive notice over the list', (
      tester,
    ) async {
      await _pump(tester, sliceState(liveUpdatesDegraded: true));

      expect(
        find.byKey(const Key('property-list-live-degraded')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('property-list-table')), findsOneWidget);
    });

    testWidgets('notFound and forbidden after opening are distinct notices', (
      tester,
    ) async {
      await _pump(
        tester,
        sliceState(detailPhase: PropertyDetailPhase.notFound),
      );
      expect(find.byKey(const Key('property-open-not-found')), findsOneWidget);
      expect(find.byKey(const Key('property-open-forbidden')), findsNothing);
      expect(find.byKey(const Key('property-list-table')), findsOneWidget);

      await _pump(
        tester,
        sliceState(detailPhase: PropertyDetailPhase.forbidden),
      );
      expect(find.byKey(const Key('property-open-forbidden')), findsOneWidget);
      expect(find.byKey(const Key('property-open-not-found')), findsNothing);
      expect(find.textContaining('(property.read)'), findsOneWidget);
    });

    testWidgets('a recoverable open error can be retried', (tester) async {
      var retries = 0;
      await _pump(
        tester,
        sliceState(
          detailPhase: PropertyDetailPhase.error,
          message: 'Detail unavailable.',
        ),
        onRetryOpen: () => retries++,
      );

      expect(find.byKey(const Key('property-open-error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('property-open-retry')));
      expect(retries, 1);
    });

    testWidgets('session and workspace transitions never look like an empty '
        'list', (tester) async {
      await _pump(
        tester,
        sliceState(
          authPhase: ReferenceAuthPhase.loading,
          properties: const <PropertySummaryDto>[],
        ),
      );
      expect(find.byKey(const Key('property-list-session')), findsOneWidget);

      await _pump(
        tester,
        sliceState(
          workspacePhase: WorkspacePhase.selectionRequired,
          listPhase: PropertyListPhase.idle,
          properties: const <PropertySummaryDto>[],
        ),
      );
      expect(
        find.byKey(const Key('property-list-no-workspace')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('property-list-empty')), findsNothing);
    });

    testWidgets('restores keyboard focus to the previously opened row', (
      tester,
    ) async {
      await _pump(
        tester,
        sliceState(
          properties: <PropertySummaryDto>[
            property(),
            property(id: 'property-b', name: 'Beta Offices'),
          ],
        ),
        restoreFocusPropertyId: 'property-b',
      );

      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);
      expect(
        focused!.context!.findAncestorWidgetOfExactType<IconButton>()?.key,
        const Key('property-list-open-property-b'),
      );
    });

    for (final viewport in goldenViewports) {
      testWidgets('has no overflow with long names at $viewport', (
        tester,
      ) async {
        await _pump(
          tester,
          sliceState(
            liveUpdatesDegraded: true,
            nextCursor: 'property-b',
            loadMoreFailureMessage: 'Temporary failure.',
            properties: <PropertySummaryDto>[
              property(
                name:
                    'Ein außerordentlich langer Objektname der auf keinen '
                    'Fall in eine Zeile passt und deshalb umbrechen muss',
                addressLine1:
                    'Sehr lange Straße mit vielen Wörtern und Zusätzen 1234a',
              ),
              property(id: 'property-b', name: 'Beta Offices'),
            ],
          ),
          viewport: viewport,
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// The workspace-wide search (`PROPERTY-LOOKUP-01`) on the list.
///
/// The distinction the whole package exists for is pinned here: the term goes
/// to the server, and an empty result set is reported as "no match for this
/// search", never as "this workspace has no properties".
void _searchTests() {
  group('PropertyListView search', () {
    testWidgets('is absent when the host cannot search', (tester) async {
      await _pump(tester, sliceState());

      expect(find.byKey(const Key('property-search-field')), findsNothing);
    });

    testWidgets('submits the term once typing pauses', (tester) async {
      final submitted = <String>[];
      await _pump(tester, sliceState(), onSearch: submitted.add);

      await tester.enterText(
        find.byKey(const Key('property-search-field')),
        'atlas',
      );
      await tester.pump();
      expect(submitted, isEmpty, reason: 'debounced, not per keystroke');

      await tester.pump(const Duration(milliseconds: 400));
      expect(submitted, <String>['atlas']);
    });

    testWidgets('does not submit a single character', (tester) async {
      final submitted = <String>[];
      await _pump(tester, sliceState(), onSearch: submitted.add);

      await tester.enterText(
        find.byKey(const Key('property-search-field')),
        'a',
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(submitted, isEmpty);
      expect(find.textContaining('Mindestens 2 Zeichen'), findsOneWidget);
    });

    testWidgets('clearing drops the filter immediately', (tester) async {
      final submitted = <String>[];
      await _pump(
        tester,
        sliceState(propertySearchTerm: 'atlas'),
        onSearch: submitted.add,
      );

      await tester.tap(find.byKey(const Key('property-search-clear')));
      await tester.pump();

      expect(submitted, <String>[
        '',
      ], reason: 'removing a filter is not a search and must not wait');
    });

    testWidgets('an empty result under a search says so, and offers to reset', (
      tester,
    ) async {
      final submitted = <String>[];
      await _pump(
        tester,
        sliceState(
          listPhase: PropertyListPhase.empty,
          properties: const <PropertySummaryDto>[],
          propertySearchTerm: 'lissabon',
        ),
        onSearch: submitted.add,
      );

      expect(
        find.byKey(const Key('property-list-search-empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-list-empty')),
        findsNothing,
        reason: 'no match is not an empty workspace',
      );
      expect(find.byKey(const Key('property-list-no-match')), findsNothing);
      // The term is named in the empty state, not only echoed in the input.
      expect(
        find.descendant(
          of: find.byKey(const Key('property-list-search-empty')),
          matching: find.textContaining('lissabon'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('property-list-search-reset')));
      await tester.pump();
      expect(submitted, <String>['']);
    });

    testWidgets('an empty result without a search keeps the archive hint', (
      tester,
    ) async {
      await _pump(
        tester,
        sliceState(
          listPhase: PropertyListPhase.empty,
          properties: const <PropertySummaryDto>[],
        ),
        onSearch: (_) {},
      );

      expect(find.byKey(const Key('property-list-no-match')), findsOneWidget);
      expect(find.byKey(const Key('property-list-search-empty')), findsNothing);
    });

    testWidgets('an external reset clears the input', (tester) async {
      await _pump(
        tester,
        sliceState(propertySearchTerm: 'atlas'),
        onSearch: (_) {},
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('property-search-field')))
            .controller
            ?.text,
        'atlas',
      );

      // A workspace switch clears the term on the state; the field follows.
      await _pump(tester, sliceState(), onSearch: (_) {});
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('property-search-field')))
            .controller
            ?.text,
        '',
      );
    });

    for (final viewport in const <Size>[Size(390, 844), Size(1440, 900)]) {
      testWidgets('has no overflow at $viewport', (tester) async {
        await _pump(
          tester,
          sliceState(propertySearchTerm: 'atlas'),
          onSearch: (_) {},
          viewport: viewport,
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('property-search-field')), findsOneWidget);
      });
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  ReferenceSliceState state, {
  Size viewport = const Size(1440, 900),
  ValueChanged<String>? onOpenProperty,
  VoidCallback? onLoadMore,
  VoidCallback? onReload,
  ValueChanged<bool>? onSetIncludeArchived,
  ValueChanged<String>? onSearch,
  VoidCallback? onRetryOpen,
  String? openingPropertyId,
  String? restoreFocusPropertyId,
}) async {
  setViewport(tester, viewport);
  await tester.pumpWidget(
    wrapApp(
      PropertyListView(
        state: state,
        onOpenProperty: onOpenProperty ?? (_) {},
        onLoadMore: onLoadMore ?? () {},
        onReload: onReload ?? () {},
        onSetIncludeArchived: onSetIncludeArchived ?? (_) {},
        onSearch: onSearch,
        onRefreshWorkspaces: () {},
        onRetryOpen: onRetryOpen,
        openingPropertyId: openingPropertyId,
        restoreFocusPropertyId: restoreFocusPropertyId,
      ),
    ),
  );
  // Not pumpAndSettle: several states carry indeterminate progress
  // indicators, which never settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
