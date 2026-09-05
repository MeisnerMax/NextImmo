import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_workspace_screen.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';

import 'property_workspace_fixtures.dart';

/// PROPERTY-DATA-02 / PROPERTY-CREATE-01 in the workspace: creating a property
/// and the named archive/restore actions.
void main() {
  group('Create property', () {
    testWidgets('the action is disabled with a capability tooltip without '
        'property.create', (tester) async {
      await _pump(tester, sliceState(), _Calls(), canCreate: false);

      final button = find.byKey(const Key('property-list-create'));
      expect(button, findsOneWidget, reason: 'discoverable, not hidden');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: button, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, contains('property.create'));
      expect(tooltip.message, contains('AAL2'));
    });

    testWidgets('the action is disabled below AAL2 even with the capability', (
      tester,
    ) async {
      // The host derives canCreateProperty from permission AND assurance; this
      // pins that a permitted-but-unelevated session cannot create.
      await _pump(
        tester,
        sliceState(assuranceLevel: AuthenticationAssuranceLevel.aal1),
        _Calls(),
        canCreate: false,
      );

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('property-list-create')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('submits the whole draft and normalizes the codes', (
      tester,
    ) async {
      final calls = _Calls();
      await _pump(tester, sliceState(), calls);

      await tester.tap(find.byKey(const Key('property-list-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('property-create-dialog')), findsOneWidget);

      await _enter(tester, 'property-create-name', '  Neubau Nord ');
      await _enter(tester, 'property-create-address-line1', 'Baustelle 1');
      await _enter(tester, 'property-create-zip', '10115');
      await _enter(tester, 'property-create-city', 'Berlin');
      await _enter(tester, 'property-create-country', 'DE');
      await _enter(tester, 'property-create-property-type', 'Mixed_Use');
      await _enter(tester, 'property-create-units', '12');
      await _enter(tester, 'property-create-sqft', '1.250,5');
      await _enter(tester, 'property-create-year-built', '1998');
      await _enter(tester, 'property-create-reason', 'Bestandsaufnahme');

      await tester.tap(find.byKey(const Key('property-create-submit')));
      await tester.pumpAndSettle();

      expect(calls.drafts, hasLength(1));
      final draft = calls.drafts.single;
      expect(draft.name, 'Neubau Nord');
      expect(draft.addressLine1, 'Baustelle 1');
      expect(draft.country, 'de', reason: 'normalized client-side');
      expect(draft.propertyType, 'mixed_use');
      expect(draft.units, 12);
      expect(draft.sqft, 1250.5);
      expect(draft.yearBuilt, 1998);
      expect(draft.addressLine2, isNull);
      expect(draft.notes, isNull);
      expect(calls.reasons.single, 'Bestandsaufnahme');
      // Status is never part of a creation: the server decides draft.
      expect(find.byKey(const Key('property-create-dialog')), findsNothing);
    });

    testWidgets('validates locally and sends nothing', (tester) async {
      final calls = _Calls();
      await _pump(tester, sliceState(), calls);
      await tester.tap(find.byKey(const Key('property-list-create')));
      await tester.pumpAndSettle();

      await _enter(tester, 'property-create-name', '   ');
      await _enter(tester, 'property-create-units', '-3');
      await _enter(tester, 'property-create-country', 'de!');
      await tester.tap(find.byKey(const Key('property-create-submit')));
      await tester.pumpAndSettle();

      expect(calls.drafts, isEmpty);
      expect(find.text('Pflichtfeld'), findsWidgets);
      expect(find.text('Ganze Zahl ab 0 erforderlich.'), findsOneWidget);
      expect(find.byKey(const Key('property-create-dialog')), findsOneWidget);
    });

    testWidgets('a server rejection keeps the dialog and the input, and marks '
        'the named field', (tester) async {
      final calls = _Calls()..failure = 'zip';
      await _pump(tester, sliceState(), calls);
      await tester.tap(find.byKey(const Key('property-list-create')));
      await tester.pumpAndSettle();

      await _enter(tester, 'property-create-name', 'Neubau Nord');
      await _enter(tester, 'property-create-address-line1', 'Baustelle 1');
      await _enter(tester, 'property-create-zip', '00000');
      await _enter(tester, 'property-create-city', 'Berlin');
      await tester.tap(find.byKey(const Key('property-create-submit')));
      await tester.pumpAndSettle();

      expect(calls.drafts, hasLength(1));
      expect(find.byKey(const Key('property-create-dialog')), findsOneWidget);
      expect(find.byKey(const Key('property-create-error')), findsOneWidget);
      expect(find.text('Vom Server abgelehnt.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('property-create-name')),
            )
            .controller
            ?.text,
        'Neubau Nord',
        reason: 'user input survives a failed save',
      );
    });

    testWidgets('a form-level failure reports without naming a field', (
      tester,
    ) async {
      final calls = _Calls()..failure = '';
      await _pump(tester, sliceState(), calls);
      await tester.tap(find.byKey(const Key('property-list-create')));
      await tester.pumpAndSettle();

      await _enter(tester, 'property-create-name', 'Neubau Nord');
      await _enter(tester, 'property-create-address-line1', 'Baustelle 1');
      await _enter(tester, 'property-create-zip', '10115');
      await _enter(tester, 'property-create-city', 'Berlin');
      await tester.tap(find.byKey(const Key('property-create-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('property-create-error')), findsOneWidget);
      expect(find.text('Vom Server abgelehnt.'), findsNothing);
      expect(find.byKey(const Key('property-create-dialog')), findsOneWidget);
    });

    testWidgets('cancel sends nothing', (tester) async {
      final calls = _Calls();
      await _pump(tester, sliceState(), calls);
      await tester.tap(find.byKey(const Key('property-list-create')));
      await tester.pumpAndSettle();
      await _enter(tester, 'property-create-name', 'Verworfen');
      await tester.tap(find.byKey(const Key('property-create-cancel')));
      await tester.pumpAndSettle();

      expect(calls.drafts, isEmpty);
      expect(find.byKey(const Key('property-create-dialog')), findsNothing);
    });

    testWidgets('the empty workspace offers the same action', (tester) async {
      await _pump(
        tester,
        sliceState(
          listPhase: PropertyListPhase.empty,
          properties: const <PropertySummaryDto>[],
          includeArchived: true,
        ),
        _Calls(),
      );

      expect(find.byKey(const Key('property-list-empty')), findsOneWidget);
      expect(
        find.byKey(const Key('property-list-empty-create')),
        findsOneWidget,
      );
    });
  });

  group('Archive and restore', () {
    testWidgets('an active property offers archiving, never deleting', (
      tester,
    ) async {
      await _pump(tester, detailState(), _Calls());

      expect(
        find.byKey(const Key('property-workspace-archive')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('property-workspace-restore')), findsNothing);
      for (final forbidden in const <String>['Löschen', 'Endgültig löschen']) {
        expect(find.text(forbidden), findsNothing);
      }
    });

    testWidgets('archiving is confirmed, names the object and states that it '
        'stays restorable', (tester) async {
      final calls = _Calls();
      await _pump(tester, detailState(), calls);

      await tester.tap(find.byKey(const Key('property-workspace-archive')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('property-archive-dialog')), findsOneWidget);
      expect(find.textContaining('Atlas House'), findsWidgets);
      expect(find.textContaining('wiederherstellen'), findsOneWidget);

      await tester.tap(find.byKey(const Key('property-archive-cancel')));
      await tester.pumpAndSettle();
      expect(calls.archiveCalls, isEmpty, reason: 'cancel changes nothing');

      await tester.tap(find.byKey(const Key('property-workspace-archive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('property-archive-confirm')));
      await tester.pumpAndSettle();
      expect(calls.archiveCalls, <bool>[true]);
    });

    testWidgets('an archived property offers restoring instead', (
      tester,
    ) async {
      final calls = _Calls();
      await _pump(
        tester,
        detailState(selected: property(status: PropertyStatus.archived)),
        calls,
      );

      expect(find.byKey(const Key('property-workspace-archive')), findsNothing);
      await tester.tap(find.byKey(const Key('property-workspace-restore')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('property-archive-confirm')));
      await tester.pumpAndSettle();

      expect(calls.archiveCalls, <bool>[false]);
    });

    testWidgets('without property.update the action is disabled with a '
        'capability tooltip', (tester) async {
      await _pump(
        tester,
        detailState(permissions: const <String>{'property.read'}),
        _Calls(),
      );

      final button = find.byKey(const Key('property-workspace-archive'));
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: button, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, contains('property.update'));
    });

    testWidgets('the action stands down while the master data is being '
        'edited', (tester) async {
      await _pump(tester, detailState(), _Calls());

      await tester.tap(find.byKey(const Key('property-workspace-edit')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('property-workspace-archive')),
        findsNothing,
        reason: 'a half-finished form must not compete with a status change',
      );
    });
  });
}

class _Calls {
  final List<PropertyCreateDto> drafts = <PropertyCreateDto>[];
  final List<String?> reasons = <String?>[];
  final List<bool> archiveCalls = <bool>[];

  /// null = success, '' = form-level failure, otherwise the rejected field.
  String? failure;
}

Future<void> _pump(
  WidgetTester tester,
  ReferenceSliceState state,
  _Calls calls, {
  bool canCreate = true,
  Size viewport = const Size(1440, 900),
}) async {
  setViewport(tester, viewport);
  await tester.pumpWidget(
    wrapApp(
      PropertyWorkspaceView(
        state: state,
        onOpenProperty: (_) async => true,
        onCloseProperty: () {},
        onLoadMore: () async {},
        onReload: () async {},
        onSetIncludeArchived: (_) async {},
        onRefreshWorkspaces: () async {},
        onUpdateProperty: (_, {expectedVersion}) async => true,
        onRetryUpdate: () async {},
        canCreateProperty: canCreate,
        onCreateProperty: (draft, {reason}) async {
          calls.drafts.add(draft);
          calls.reasons.add(reason);
          return calls.failure;
        },
        onSetArchived: (archived, {reason}) async {
          calls.archiveCalls.add(archived);
          return true;
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.enterText(finder, text);
  await tester.pump();
}
