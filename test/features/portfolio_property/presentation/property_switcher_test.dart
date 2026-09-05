import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_workspace_screen.dart';

import 'property_workspace_fixtures.dart';

/// The property switcher (`PROPERTY_WORKSPACE_V2.md` §6).
///
/// The rule the spec is emphatic about: the switcher browses a server-paginated
/// list, never a filter over whatever the workspace happens to have loaded.
/// These tests pin that, the dirty gate in front of it, and the canonical open
/// behind it.
void main() {
  group('Property switcher', () {
    testWidgets('reads its own server pages instead of the loaded list', (
      tester,
    ) async {
      final calls = _Calls();
      // The workspace has exactly one property loaded; the switcher must still
      // offer what the server returns, not that one row.
      await _pump(tester, calls);

      await tester.tap(find.byKey(const Key('property-context-switch')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('property-switcher-dialog')), findsOneWidget);
      expect(calls.cursors, <String?>[null], reason: 'first page, no cursor');
      expect(
        find.byKey(const Key('property-switcher-item-property-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-switcher-item-property-c')),
        findsOneWidget,
      );
      // It browses in contract order and says exactly what its scope is.
      expect(calls.searchTerms, <String?>[null]);
      expect(find.textContaining('über alle Objekte'), findsOneWidget);
    });

    testWidgets('a search asks the server, not the loaded page', (
      tester,
    ) async {
      final calls = _Calls();
      await _pump(tester, calls);
      await tester.tap(find.byKey(const Key('property-context-switch')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('property-search-field')),
        'gamma',
      );
      // Debounced: nothing has been asked yet.
      await tester.pump();
      expect(calls.searchTerms, <String?>[null]);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(calls.searchTerms, <String?>[null, 'gamma']);
      expect(
        find.byKey(const Key('property-switcher-item-property-c')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-switcher-item-property-b')),
        findsNothing,
        reason: 'the result set is the server answer, not a client filter',
      );
    });

    testWidgets('a single character is not sent to the server', (tester) async {
      final calls = _Calls();
      await _pump(tester, calls);
      await tester.tap(find.byKey(const Key('property-context-switch')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('property-search-field')),
        'g',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(calls.searchTerms, <String?>[null]);
      expect(find.textContaining('Mindestens 2 Zeichen'), findsOneWidget);
    });

    testWidgets('a search with no match says so, and does not claim the '
        'workspace is empty', (tester) async {
      final calls = _Calls();
      await _pump(tester, calls);
      await tester.tap(find.byKey(const Key('property-context-switch')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('property-search-field')),
        'lissabon',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('property-switcher-search-empty')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('property-switcher-empty')), findsNothing);
    });

    testWidgets('clearing the search restores the browse list at once', (
      tester,
    ) async {
      final calls = _Calls();
      await _pump(tester, calls);
      await tester.tap(find.byKey(const Key('property-context-switch')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('property-search-field')),
        'gamma',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('property-search-clear')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(calls.searchTerms, <String?>[null, 'gamma', null]);
      expect(
        find.byKey(const Key('property-switcher-item-property-b')),
        findsOneWidget,
      );
    });

    testWidgets('pages forward with the keyset cursor', (tester) async {
      final calls = _Calls();
      await _pump(tester, calls);
      await tester.tap(find.byKey(const Key('property-context-switch')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('property-switcher-load-more')));
      await tester.pumpAndSettle();

      expect(calls.cursors, <String?>[null, 'property-c']);
      expect(
        find.byKey(const Key('property-switcher-item-property-d')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-switcher-load-more')),
        findsNothing,
        reason: 'the last page has no cursor',
      );
    });

    testWidgets('the open property is shown but cannot be chosen', (
      tester,
    ) async {
      final calls = _Calls()..includeCurrent = true;
      await _pump(tester, calls);
      await tester.tap(find.byKey(const Key('property-context-switch')));
      await tester.pumpAndSettle();

      final current = find.byKey(
        const Key('property-switcher-item-property-a'),
      );
      expect(current, findsOneWidget);
      expect(tester.widget<ListTile>(current).enabled, isFalse);
      expect(find.text('Geöffnet'), findsOneWidget);
    });

    testWidgets('choosing a property opens it canonically and keeps the '
        'domain', (tester) async {
      final calls = _Calls();
      await _pump(tester, calls);
      await tester.tap(find.byKey(const Key('property-context-switch')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('property-switcher-item-property-b')),
      );
      await tester.pumpAndSettle();

      expect(calls.opened, <String>[
        'property-b',
      ], reason: 'the switch goes through the canonical getById');
      expect(find.byKey(const Key('property-switcher-dialog')), findsNothing);
      expect(find.byKey(const Key('property-workspace')), findsOneWidget);
    });

    testWidgets('a failed open falls back to the list rather than an empty '
        'workspace', (tester) async {
      final calls = _Calls()..openSucceeds = false;
      await _pump(tester, calls);
      await tester.tap(find.byKey(const Key('property-context-switch')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('property-switcher-item-property-b')),
      );
      await tester.pumpAndSettle();

      expect(calls.opened, <String>['property-b']);
      expect(find.byKey(const Key('property-workspace')), findsNothing);
      expect(find.byKey(const Key('property-list')), findsOneWidget);
    });

    testWidgets('unsaved edits gate the switch', (tester) async {
      final calls = _Calls();
      await _pump(tester, calls);
      await tester.tap(find.byKey(const Key('property-workspace-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('property-asset-edit-name')),
        'Atlas Tower',
      );

      await tester.tap(find.byKey(const Key('property-context-switch')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('property-workspace-unsaved-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-switcher-dialog')),
        findsNothing,
        reason: 'the switcher waits for the decision',
      );
      await tester.tap(
        find.byKey(const Key('property-workspace-unsaved-cancel')),
      );
      await tester.pumpAndSettle();
      expect(calls.cursors, isEmpty, reason: 'nothing was even loaded');
    });

    testWidgets('a load failure offers a retry instead of an empty list', (
      tester,
    ) async {
      final calls = _Calls()..fail = true;
      await _pump(tester, calls);
      await tester.tap(find.byKey(const Key('property-context-switch')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('property-switcher-error')), findsOneWidget);
      expect(find.byKey(const Key('property-switcher-empty')), findsNothing);

      calls.fail = false;
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('property-switcher-item-property-b')),
        findsOneWidget,
      );
    });

    testWidgets('no switch affordance without a readable list', (tester) async {
      await _pump(tester, _Calls(), withSwitcher: false);

      expect(find.byKey(const Key('property-context-switch')), findsNothing);
    });

    for (final viewport in const <Size>[Size(390, 844), Size(1440, 900)]) {
      testWidgets('has no overflow at $viewport', (tester) async {
        final calls = _Calls();
        await _pump(tester, calls, viewport: viewport);
        await tester.tap(find.byKey(const Key('property-context-switch')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('property-switcher-dialog')),
          findsOneWidget,
        );
      });
    }
  });
}

class _Calls {
  final List<String?> cursors = <String?>[];
  final List<String?> searchTerms = <String?>[];
  final List<String> opened = <String>[];
  bool openSucceeds = true;
  bool fail = false;
  bool includeCurrent = false;

  /// The one property the scripted search matches.
  static const String searchMatch = 'property-c';
}

Future<void> _pump(
  WidgetTester tester,
  _Calls calls, {
  bool withSwitcher = true,
  Size viewport = const Size(1440, 900),
}) async {
  setViewport(tester, viewport);
  await tester.pumpWidget(
    wrapApp(
      PropertyWorkspaceView(
        state: detailState(),
        onOpenProperty: (id) async {
          calls.opened.add(id);
          return calls.openSucceeds;
        },
        onCloseProperty: () {},
        onLoadMore: () async {},
        onReload: () async {},
        onSetIncludeArchived: (_) async {},
        onRefreshWorkspaces: () async {},
        onUpdateProperty: (_, {expectedVersion}) async => true,
        onRetryUpdate: () async {},
        onLoadSwitcherPage:
            withSwitcher
                ? ({String? cursor, String? searchTerm}) async {
                  calls.cursors.add(cursor);
                  calls.searchTerms.add(searchTerm);
                  if (calls.fail) {
                    return const PropertyRepositoryFailure<PropertyPageResult>(
                      kind: PropertyRepositoryFailureKind.infrastructureFailure,
                      message: 'Serverfehler.',
                    );
                  }
                  if (searchTerm != null) {
                    // The server answers the search, not the loaded page: only
                    // rows that match come back, and there is no next cursor.
                    return PropertyRepositorySuccess<PropertyPageResult>(
                      PropertyPageResult(
                        items:
                            searchTerm.contains('gamma')
                                ? <PropertySummaryDto>[
                                  property(
                                    id: _Calls.searchMatch,
                                    name: 'Gamma Center',
                                  ),
                                ]
                                : const <PropertySummaryDto>[],
                      ),
                    );
                  }
                  if (cursor == null) {
                    return PropertyRepositorySuccess<PropertyPageResult>(
                      PropertyPageResult(
                        items: <PropertySummaryDto>[
                          if (calls.includeCurrent) property(),
                          property(id: 'property-b', name: 'Beta Offices'),
                          property(id: 'property-c', name: 'Gamma Center'),
                        ],
                        nextCursor: 'property-c',
                      ),
                    );
                  }
                  return PropertyRepositorySuccess<PropertyPageResult>(
                    PropertyPageResult(
                      items: <PropertySummaryDto>[
                        property(id: 'property-d', name: 'Delta House'),
                      ],
                    ),
                  );
                }
                : null,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
