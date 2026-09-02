import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_workspace_host_state.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_workspace_screen.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';

import 'property_workspace_fixtures.dart';

void main() {
  group('PropertyWorkspaceView', () {
    testWidgets('starts on the list and opens a property only after the '
        'canonical read succeeded', (tester) async {
      final calls = _Calls();
      final pending = Completer<void>();
      calls.openResult = pending.future;
      await _pump(tester, sliceState(), calls);

      expect(find.byKey(const Key('property-list')), findsOneWidget);
      expect(find.byKey(const Key('property-workspace')), findsNothing);

      await tester.tap(find.byKey(const Key('property-list-open-property-a')));
      await tester.pump();
      expect(calls.opened, <String>['property-a']);
      // Still the list while getById is in flight.
      expect(find.byKey(const Key('property-workspace')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      _update(tester, detailState());
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('property-workspace')), findsOneWidget);
      expect(find.byKey(const Key('property-list')), findsNothing);
      expect(find.byKey(const Key('property-asset')), findsOneWidget);
      final hostState = _hostState(tester);
      expect(hostState.openPropertyId, 'property-a');
      expect(hostState.domain, PropertyWorkspaceDomain.asset);
      expect(hostState.list.focusedPropertyId, 'property-a');
      expect(hostState.toJson()['openPropertyId'], 'property-a');
    });

    testWidgets('shows the property context header, breadcrumb and only the '
        'implemented Objekt domain', (tester) async {
      await _pump(
        tester,
        detailState(),
        _Calls(),
        initialPropertyId: 'property-a',
      );

      expect(find.byKey(const Key('property-context-header')), findsOneWidget);
      expect(find.text('OBJEKTE'), findsOneWidget);
      expect(find.text('ATLAS HOUSE'), findsOneWidget);
      expect(find.text('OBJEKT'), findsOneWidget);
      expect(find.text('Atlas House'), findsWidgets);
      expect(find.text('Long Street 123, 10115 Berlin'), findsOneWidget);
      expect(find.byKey(const Key('property-context-status')), findsOneWidget);
      expect(find.text('Aktiv'), findsWidgets);
      expect(find.byKey(const Key('property-context-back')), findsOneWidget);
      expect(find.byKey(const Key('property-workspace-edit')), findsOneWidget);

      expect(find.byKey(const Key('property-workspace-nav')), findsOneWidget);
      expect(
        find.byKey(const Key('property-workspace-nav-asset')),
        findsOneWidget,
      );
      expect(find.byType(ChoiceChip), findsOneWidget);
      for (final hidden in const <String>[
        'Übersicht',
        'Vermietung',
        'Betrieb',
        'Dokumente',
        'Investment',
        'Aktivität',
      ]) {
        expect(find.text(hidden), findsNothing);
      }
    });

    testWidgets('a failed open keeps the list: notFound and forbidden stay '
        'distinct', (tester) async {
      final calls = _Calls();
      await _pump(tester, sliceState(), calls);

      final pending = Completer<void>();
      calls.openResult = pending.future;
      await tester.tap(find.byKey(const Key('property-list-open-property-a')));
      await tester.pump();
      _update(tester, sliceState(detailPhase: PropertyDetailPhase.notFound));
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('property-list')), findsOneWidget);
      expect(find.byKey(const Key('property-open-not-found')), findsOneWidget);
      expect(find.byKey(const Key('property-workspace')), findsNothing);
      expect(_hostState(tester).isPropertyOpen, isFalse);

      final forbidden = Completer<void>();
      calls.openResult = forbidden.future;
      await tester.tap(find.byKey(const Key('property-list-open-property-a')));
      await tester.pump();
      _update(tester, sliceState(detailPhase: PropertyDetailPhase.forbidden));
      await tester.pump();
      forbidden.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('property-open-forbidden')), findsOneWidget);
      expect(find.byKey(const Key('property-open-not-found')), findsNothing);
    });

    testWidgets('back returns to the list, closes the context and restores '
        'focus to the opened row', (tester) async {
      final calls = _Calls();
      await _pump(
        tester,
        detailState(
          properties: <PropertySummaryDto>[
            property(),
            property(id: 'property-b', name: 'Beta Offices'),
          ],
        ),
        calls,
      );
      expect(find.byKey(const Key('property-workspace')), findsOneWidget);

      await tester.tap(find.byKey(const Key('property-context-back')));
      await tester.pumpAndSettle();

      expect(calls.closeCalls, 1);
      expect(find.byKey(const Key('property-list')), findsOneWidget);
      expect(_hostState(tester).isPropertyOpen, isFalse);
      expect(_hostState(tester).list.focusedPropertyId, 'property-a');
      final focused = FocusManager.instance.primaryFocus;
      expect(
        focused?.context?.findAncestorWidgetOfExactType<IconButton>()?.key,
        const Key('property-list-open-property-a'),
      );
    });

    testWidgets('unsaved edits gate the way back with Speichern / Verwerfen / '
        'Abbrechen', (tester) async {
      final calls = _Calls();
      await _pump(tester, detailState(), calls);

      await tester.tap(find.byKey(const Key('property-workspace-edit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('property-asset-form')), findsOneWidget);
      expect(
        find.byKey(const Key('property-workspace-edit')),
        findsNothing,
        reason: 'one primary action per page state',
      );
      await tester.enterText(
        find.byKey(const Key('property-asset-edit-name')),
        'Atlas Tower',
      );

      // Abbrechen keeps the workspace and the input.
      await tester.tap(find.byKey(const Key('property-context-back')));
      await tester.pumpAndSettle();
      final dialog = find.byKey(const Key('property-workspace-unsaved-dialog'));
      expect(dialog, findsOneWidget);
      expect(find.textContaining('Atlas House'), findsWidgets);
      await tester.tap(
        find.byKey(const Key('property-workspace-unsaved-cancel')),
      );
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(find.byKey(const Key('property-workspace')), findsOneWidget);
      expect(calls.closeCalls, 0);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('property-asset-edit-name')),
            )
            .controller
            ?.text,
        'Atlas Tower',
      );

      // Speichern persists first, then leaves.
      await tester.tap(find.byKey(const Key('property-context-back')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('property-workspace-unsaved-save')),
      );
      await tester.pumpAndSettle();
      expect(calls.updates, hasLength(1));
      expect(calls.updates.single.name, 'Atlas Tower');
      expect(calls.updates.single.status, PropertyStatus.active);
      expect(calls.updates.single.propertyType, 'mixed_use');
      expect(calls.expectedVersions, <int?>[1]);
      expect(calls.closeCalls, 1);
      expect(find.byKey(const Key('property-list')), findsOneWidget);
    });

    testWidgets('Verwerfen drops the input and leaves without a save', (
      tester,
    ) async {
      final calls = _Calls();
      await _pump(tester, detailState(), calls);
      await tester.tap(find.byKey(const Key('property-workspace-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('property-asset-edit-name')),
        'Atlas Tower',
      );

      await tester.tap(find.byKey(const Key('property-context-back')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('property-workspace-unsaved-discard')),
      );
      await tester.pumpAndSettle();

      expect(calls.updates, isEmpty);
      expect(calls.closeCalls, 1);
      expect(find.byKey(const Key('property-list')), findsOneWidget);
    });

    testWidgets('a failed save from the dialog keeps the workspace open', (
      tester,
    ) async {
      final calls = _Calls()..updateSucceeds = false;
      await _pump(tester, detailState(), calls);
      await tester.tap(find.byKey(const Key('property-workspace-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('property-asset-edit-name')),
        'Atlas Tower',
      );

      await tester.tap(find.byKey(const Key('property-context-back')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('property-workspace-unsaved-save')),
      );
      await tester.pumpAndSettle();

      expect(calls.updates, hasLength(1));
      expect(calls.closeCalls, 0);
      expect(find.byKey(const Key('property-workspace')), findsOneWidget);
    });

    testWidgets('clean edits leave without a dialog', (tester) async {
      final calls = _Calls();
      await _pump(tester, detailState(), calls);
      await tester.tap(find.byKey(const Key('property-workspace-edit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('property-context-back')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('property-workspace-unsaved-dialog')),
        findsNothing,
      );
      expect(calls.closeCalls, 1);
    });

    testWidgets('edit is disabled with a capability tooltip without '
        'property.update', (tester) async {
      await _pump(
        tester,
        detailState(permissions: const <String>{'property.read'}),
        _Calls(),
      );

      final button = find.byKey(const Key('property-workspace-edit'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: button, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, contains('property.update'));
      expect(find.byKey(const Key('property-asset-read')), findsOneWidget);
      expect(find.byKey(const Key('property-asset-form')), findsNothing);
    });

    testWidgets('a deep link starts in the workspace and shows loading, then '
        'the asset', (tester) async {
      final calls = _Calls();
      await _pump(
        tester,
        sliceState(
          detailPhase: PropertyDetailPhase.loading,
          properties: const <PropertySummaryDto>[],
        ),
        calls,
        initialPropertyId: 'property-a',
      );

      expect(find.byKey(const Key('property-workspace')), findsOneWidget);
      expect(
        find.byKey(const Key('property-workspace-loading')),
        findsOneWidget,
      );
      expect(find.text('Objekt wird geladen …'), findsWidgets);
      expect(find.byKey(const Key('property-list')), findsNothing);

      _update(tester, detailState());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('property-asset')), findsOneWidget);
    });

    testWidgets('a deep link to a missing or forbidden property shows the '
        'distinct state with a way back', (tester) async {
      final calls = _Calls();
      await _pump(
        tester,
        sliceState(
          detailPhase: PropertyDetailPhase.notFound,
          properties: const <PropertySummaryDto>[],
        ),
        calls,
        initialPropertyId: 'property-x',
      );
      expect(
        find.byKey(const Key('property-workspace-not-found')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('property-asset')), findsNothing);

      _update(
        tester,
        sliceState(
          detailPhase: PropertyDetailPhase.forbidden,
          properties: const <PropertySummaryDto>[],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('property-workspace-forbidden')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-workspace-not-found')),
        findsNothing,
      );
      expect(find.textContaining('(property.read)'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('property-workspace-forbidden-back')),
      );
      await tester.pumpAndSettle();
      expect(calls.closeCalls, 1);
      expect(find.byKey(const Key('property-list')), findsOneWidget);
    });

    testWidgets('a permission revoke removes the canonical data and shows '
        'forbidden; a torn-down context falls back to the list', (
      tester,
    ) async {
      await _pump(tester, detailState(), _Calls());
      expect(find.text('Long Street 123, 10115 Berlin'), findsOneWidget);

      _update(
        tester,
        sliceState(
          permissions: const <String>{},
          listPhase: PropertyListPhase.forbidden,
          properties: const <PropertySummaryDto>[],
          detailPhase: PropertyDetailPhase.forbidden,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('property-workspace-forbidden')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('property-asset')), findsNothing);
      expect(find.text('Long Street 123, 10115 Berlin'), findsNothing);
      expect(find.text('Reference fixture'), findsNothing);

      _update(
        tester,
        sliceState(
          workspacePhase: WorkspacePhase.loading,
          listPhase: PropertyListPhase.idle,
          properties: const <PropertySummaryDto>[],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('property-list')), findsOneWidget);
      expect(_hostState(tester).isPropertyOpen, isFalse);
    });

    testWidgets('degraded live updates are shown passively in the workspace', (
      tester,
    ) async {
      await _pump(tester, detailState(liveUpdatesDegraded: true), _Calls());

      expect(
        find.byKey(const Key('property-workspace-live-degraded')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('property-asset')), findsOneWidget);
    });

    testWidgets('mobile uses the compact header and the detail replaces the '
        'list', (tester) async {
      final calls = _Calls();
      await _pump(tester, detailState(), calls, viewport: const Size(390, 844));

      expect(
        find.byKey(const Key('property-context-header-compact')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('property-context-header')), findsNothing);
      expect(find.byKey(const Key('property-list')), findsNothing);
      expect(find.byKey(const Key('property-asset')), findsOneWidget);

      await tester.tap(find.byKey(const Key('property-context-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('property-list-cards')), findsOneWidget);
      expect(calls.closeCalls, 1);
    });

    testWidgets('tablet condenses the location to the city', (tester) async {
      await _pump(
        tester,
        detailState(),
        _Calls(),
        viewport: const Size(1024, 768),
      );

      expect(find.byKey(const Key('property-context-header')), findsOneWidget);
      expect(find.text('Berlin'), findsWidgets);
      expect(find.text('Long Street 123, 10115 Berlin'), findsNothing);
    });

    for (final viewport in goldenViewports) {
      testWidgets('workspace has no overflow at $viewport', (tester) async {
        await _pump(
          tester,
          detailState(
            liveUpdatesDegraded: true,
            selected: property(
              name:
                  'Ein außerordentlich langer Objektname der auf keinen Fall '
                  'in eine Zeile passt',
              addressLine1:
                  'Sehr lange Straße mit vielen Wörtern und Zusätzen 1234a',
              addressLine2: 'Hinterhaus, 3. Obergeschoss links',
              sqft: 1250.5,
              yearBuilt: 1998,
              notes:
                  'Sehr lange interne Hinweise, die über mehrere Zeilen laufen '
                  'und auf keinem Gerät horizontal scrollen dürfen.',
            ),
          ),
          _Calls(),
          viewport: viewport,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('property-workspace-edit')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('property-asset-form')), findsOneWidget);
      });
    }
  });
}

class _Calls {
  final List<String> opened = <String>[];
  final List<PropertyUpdateDto> updates = <PropertyUpdateDto>[];
  final List<int?> expectedVersions = <int?>[];
  int closeCalls = 0;
  Future<void>? openResult;
  bool updateSucceeds = true;
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.initial,
    required this.calls,
    this.initialPropertyId,
  });

  final ReferenceSliceState initial;
  final _Calls calls;
  final String? initialPropertyId;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late ReferenceSliceState state = widget.initial;

  void update(ReferenceSliceState next) => setState(() => state = next);

  @override
  Widget build(BuildContext context) {
    final calls = widget.calls;
    return PropertyWorkspaceView(
      state: state,
      initialPropertyId: widget.initialPropertyId,
      onOpenProperty: (id) {
        calls.opened.add(id);
        return calls.openResult ?? Future<void>.value();
      },
      onCloseProperty: () => calls.closeCalls++,
      onLoadMore: () async {},
      onReload: () async {},
      onSetIncludeArchived: (_) async {},
      onRefreshWorkspaces: () async {},
      onUpdateProperty: (changes, {expectedVersion}) async {
        calls.updates.add(changes);
        calls.expectedVersions.add(expectedVersion);
        return calls.updateSucceeds;
      },
      onRetryUpdate: () async {},
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  ReferenceSliceState state,
  _Calls calls, {
  Size viewport = const Size(1440, 900),
  String? initialPropertyId,
}) async {
  setViewport(tester, viewport);
  await tester.pumpWidget(
    wrapApp(
      _Harness(
        initial: state,
        calls: calls,
        initialPropertyId: initialPropertyId,
      ),
    ),
  );
  // Not pumpAndSettle: loading states carry indeterminate progress
  // indicators, which never settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void _update(WidgetTester tester, ReferenceSliceState state) {
  tester.state<_HarnessState>(find.byType(_Harness)).update(state);
}

PropertyWorkspaceHostState _hostState(WidgetTester tester) {
  // ignore: avoid_dynamic_calls
  return (tester.state(find.byType(PropertyWorkspaceView)) as dynamic).hostState
      as PropertyWorkspaceHostState;
}
