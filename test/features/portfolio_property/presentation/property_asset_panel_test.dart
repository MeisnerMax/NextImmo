import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_workspace_host_state.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_asset_panel.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';

import 'property_workspace_fixtures.dart';

void main() {
  group('PropertyAssetPanel read mode', () {
    testWidgets('shows the contract fields in groups, optional fields as not '
        'provided and no actor ids', (tester) async {
      await _pump(tester, detailState(), editing: false);

      for (final key in const <String>[
        'property-asset-group-identity',
        'property-asset-group-address',
        'property-asset-group-physical',
        'property-asset-group-system',
        'property-asset-group-notes',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget);
      }
      expect(find.text('Atlas House'), findsOneWidget);
      expect(find.text('mixed_use'), findsOneWidget);
      expect(find.text('Aktiv'), findsNWidgets(2));
      expect(find.text('Long Street 123'), findsOneWidget);
      expect(find.text('—'), findsOneWidget, reason: 'empty addressLine2');
      expect(find.text('10115'), findsOneWidget);
      expect(find.text('Berlin'), findsOneWidget);
      expect(find.text('de'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(
        find.text(PropertyAssetPanel.notProvided),
        findsNWidgets(2),
        reason: 'sqft and yearBuilt are not provided; notes are',
      );
      expect(find.text('Reference fixture'), findsOneWidget);
      expect(find.text('Version 1'), findsOneWidget);
      expect(
        find.byKey(const Key('property-asset-updated-at')),
        findsOneWidget,
      );
      expect(find.textContaining('.07.2026'), findsWidgets);
      expect(find.textContaining('actor-created-uuid'), findsNothing);
      expect(find.textContaining('actor-updated-uuid'), findsNothing);
      expect(find.byKey(const Key('property-asset-form')), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('renders sqft in the stored unit without conversion', (
      tester,
    ) async {
      await _pump(
        tester,
        detailState(selected: property(sqft: 1250.5, yearBuilt: 1998)),
        editing: false,
      );

      expect(find.text('1250,5 ft²'), findsOneWidget);
      expect(find.textContaining('m²'), findsNothing);
      expect(find.text('1998'), findsOneWidget);
      expect(find.text(PropertyAssetPanel.notProvided), findsNothing);
    });

    testWidgets('stays read-only without the update capability even if edit '
        'is requested', (tester) async {
      await _pump(
        tester,
        detailState(permissions: const <String>{'property.read'}),
        editing: true,
        canEdit: false,
      );

      expect(find.byKey(const Key('property-asset-read')), findsOneWidget);
      expect(find.byKey(const Key('property-asset-form')), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('follows canonical refreshes while reading', (tester) async {
      await _pump(tester, detailState(), editing: false);
      await _pump(
        tester,
        detailState(selected: property(name: 'Renamed remotely', version: 2)),
        editing: false,
      );

      expect(find.text('Renamed remotely'), findsOneWidget);
      expect(find.text('Version 2'), findsOneWidget);
    });
  });

  group('PropertyAssetPanel edit mode', () {
    testWidgets('maps every editable field into the full-record update and '
        'keeps status and type unchanged', (tester) async {
      final updates = <PropertyUpdateDto>[];
      final versions = <int?>[];
      await _pump(
        tester,
        detailState(selected: property(status: PropertyStatus.draft)),
        editing: true,
        onUpdate: (changes, {expectedVersion}) async {
          updates.add(changes);
          versions.add(expectedVersion);
          return true;
        },
      );

      expect(find.byKey(const Key('property-asset-form')), findsOneWidget);
      // status and propertyType have no input.
      expect(
        find.byType(DropdownButtonFormField<PropertyStatus>),
        findsNothing,
      );
      expect(find.text('Typ (nicht änderbar)'), findsOneWidget);
      expect(find.text('Status (nicht änderbar)'), findsOneWidget);

      await _enter(tester, 'property-asset-edit-name', '  Atlas Tower ');
      await _enter(
        tester,
        'property-asset-edit-address-line1',
        'Long Street 1',
      );
      await _enter(tester, 'property-asset-edit-address-line2', 'Hinterhaus');
      await _enter(tester, 'property-asset-edit-zip', '10117');
      await _enter(tester, 'property-asset-edit-city', 'Berlin-Mitte');
      await _enter(tester, 'property-asset-edit-country', 'at');
      await _enter(tester, 'property-asset-edit-units', '14');
      await _enter(tester, 'property-asset-edit-sqft', '1.250,5');
      await _enter(tester, 'property-asset-edit-year-built', '1998');
      await _enter(tester, 'property-asset-edit-notes', '   ');

      await _tap(tester, 'property-asset-save');

      expect(updates, hasLength(1));
      final changes = updates.single;
      expect(changes.name, 'Atlas Tower');
      expect(changes.addressLine1, 'Long Street 1');
      expect(changes.addressLine2, 'Hinterhaus');
      expect(changes.zip, '10117');
      expect(changes.city, 'Berlin-Mitte');
      expect(changes.country, 'at');
      expect(changes.units, 14);
      expect(changes.sqft, 1250.5);
      expect(changes.yearBuilt, 1998);
      expect(changes.notes, isNull, reason: 'blank notes travel as null');
      expect(changes.propertyType, 'mixed_use');
      expect(changes.status, PropertyStatus.draft);
      expect(versions, <int?>[1]);
    });

    testWidgets('clears optional fields to null and keeps required ones', (
      tester,
    ) async {
      final updates = <PropertyUpdateDto>[];
      await _pump(
        tester,
        detailState(
          selected: property(
            addressLine2: 'Hinterhaus',
            sqft: 900,
            yearBuilt: 1960,
          ),
        ),
        editing: true,
        onUpdate: (changes, {expectedVersion}) async {
          updates.add(changes);
          return true;
        },
      );

      await _enter(tester, 'property-asset-edit-address-line2', '');
      await _enter(tester, 'property-asset-edit-sqft', '');
      await _enter(tester, 'property-asset-edit-year-built', '');
      await _tap(tester, 'property-asset-save');

      expect(updates.single.addressLine2, isNull);
      expect(updates.single.sqft, isNull);
      expect(updates.single.yearBuilt, isNull);
      expect(updates.single.units, 12);
    });

    testWidgets('validates field-near, mirroring the server contract, and '
        'sends nothing', (tester) async {
      var updateCalls = 0;
      await _pump(
        tester,
        detailState(),
        editing: true,
        onUpdate: (changes, {expectedVersion}) async {
          updateCalls++;
          return true;
        },
      );

      await _enter(tester, 'property-asset-edit-name', '   ');
      await _enter(tester, 'property-asset-edit-units', '-1');
      await _enter(tester, 'property-asset-edit-sqft', '0');
      await _enter(tester, 'property-asset-edit-year-built', '900');
      await _enter(tester, 'property-asset-edit-country', 'DE');
      await _tap(tester, 'property-asset-save');

      expect(updateCalls, 0);
      expect(find.text('Pflichtfeld'), findsOneWidget);
      expect(find.text('Ganze Zahl ab 0 erforderlich.'), findsOneWidget);
      expect(find.text('Fläche muss größer als 0 sein.'), findsOneWidget);
      expect(
        find.text('Ganze Jahreszahl zwischen 1000 und 2100.'),
        findsOneWidget,
      );
      expect(find.textContaining('Normalisierter Code'), findsOneWidget);

      await _enter(tester, 'property-asset-edit-units', '1,5');
      await _enter(tester, 'property-asset-edit-sqft', 'abc');
      await _tap(tester, 'property-asset-save');
      expect(find.text('Ganze Zahl ab 0 erforderlich.'), findsOneWidget);
      expect(find.text('Zahl erforderlich (z. B. 1250,5).'), findsOneWidget);
      expect(updateCalls, 0);
    });

    testWidgets('accepts the full server range for yearBuilt without a '
        'stricter local rule', (tester) async {
      final updates = <PropertyUpdateDto>[];
      await _pump(
        tester,
        detailState(),
        editing: true,
        onUpdate: (changes, {expectedVersion}) async {
          updates.add(changes);
          return true;
        },
      );

      await _enter(tester, 'property-asset-edit-year-built', '1000');
      await _tap(tester, 'property-asset-save');
      await _enter(tester, 'property-asset-edit-year-built', '2100');
      await _tap(tester, 'property-asset-save');

      expect(updates.map((u) => u.yearBuilt), <int?>[1000, 2100]);
    });

    testWidgets('reports dirty state through the host contract and discards '
        'to the canonical record', (tester) async {
      final registry = PropertyWorkspaceDirtyRegistry();
      final editingChanges = <bool>[];
      await _pump(
        tester,
        detailState(),
        editing: true,
        registry: registry,
        onEditingChanged: editingChanges.add,
      );

      expect(registry.child, isNotNull);
      expect(registry.hasUnsavedChanges, isFalse);

      await _enter(tester, 'property-asset-edit-name', 'Atlas House ');
      expect(
        registry.hasUnsavedChanges,
        isFalse,
        reason: 'normalized comparison ignores whitespace-only changes',
      );
      await _enter(tester, 'property-asset-edit-sqft', '');
      expect(registry.hasUnsavedChanges, isFalse, reason: 'null stays null');

      await _enter(tester, 'property-asset-edit-name', 'Atlas Tower');
      expect(registry.hasUnsavedChanges, isTrue);

      registry.child!.discardChanges();
      await tester.pumpAndSettle();
      expect(_text(tester, 'property-asset-edit-name'), 'Atlas House');
      expect(registry.hasUnsavedChanges, isFalse);
      expect(editingChanges, <bool>[false]);
    });

    testWidgets('cancel with dirty input asks before discarding', (
      tester,
    ) async {
      final editingChanges = <bool>[];
      await _pump(
        tester,
        detailState(),
        editing: true,
        onEditingChanged: editingChanges.add,
      );
      await _enter(tester, 'property-asset-edit-name', 'Atlas Tower');

      await _tap(tester, 'property-asset-cancel');
      expect(
        find.byKey(const Key('property-asset-discard-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('property-asset-discard-cancel')));
      await tester.pumpAndSettle();
      expect(_text(tester, 'property-asset-edit-name'), 'Atlas Tower');
      expect(editingChanges, isEmpty);

      await _tap(tester, 'property-asset-cancel');
      await tester.tap(find.byKey(const Key('property-asset-discard-confirm')));
      await tester.pumpAndSettle();
      expect(editingChanges, <bool>[false]);
    });

    testWidgets('a successful save reseeds the record and ends edit mode', (
      tester,
    ) async {
      final editingChanges = <bool>[];
      await _pump(
        tester,
        detailState(),
        editing: true,
        onEditingChanged: editingChanges.add,
      );
      await _enter(tester, 'property-asset-edit-name', 'Atlas Tower');

      await _pump(
        tester,
        detailState(
          selected: property(name: 'Atlas Tower', version: 2),
          mutationPhase: PropertyMutationPhase.succeeded,
        ),
        editing: true,
        onEditingChanged: editingChanges.add,
      );

      expect(editingChanges, <bool>[false]);
      expect(find.byKey(const Key('property-asset-saved')), findsOneWidget);
    });

    testWidgets('a version conflict keeps the input, shows the server version '
        'and re-saves against it', (tester) async {
      final versions = <int?>[];
      Future<bool> onUpdate(
        PropertyUpdateDto changes, {
        int? expectedVersion,
      }) async {
        versions.add(expectedVersion);
        return false;
      }

      await _pump(tester, detailState(), editing: true, onUpdate: onUpdate);
      await _enter(tester, 'property-asset-edit-name', 'Local edit');
      await _tap(tester, 'property-asset-save');
      expect(versions, <int?>[1]);

      final server = property(name: 'Server value', version: 4);
      await _pump(
        tester,
        detailState(
          selected: server,
          mutationPhase: PropertyMutationPhase.conflict,
          failureKind: PropertyRepositoryFailureKind.versionConflict,
          message: 'Stale version.',
          versionConflict: PropertyVersionConflict(
            expectedVersion: 1,
            actualVersion: 4,
            currentProperty: server,
          ),
        ),
        editing: true,
        onUpdate: onUpdate,
      );

      expect(_text(tester, 'property-asset-edit-name'), 'Local edit');
      // The save tap scrolled the lazy list down; the notices sit at the top.
      await tester.drag(
        find.byKey(const Key('property-asset-scroll')),
        const Offset(0, 3000),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('property-asset-conflict')), findsOneWidget);
      expect(find.textContaining('Serverversion 4'), findsOneWidget);
      expect(find.text('Erneut speichern'), findsOneWidget);
      expect(
        find.byKey(const Key('property-asset-remote-newer')),
        findsNothing,
        reason: 'the conflict notice owns this situation',
      );

      await _tap(tester, 'property-asset-save');
      expect(versions, <int?>[1, 4]);
    });

    testWidgets('a remote update never overwrites a dirty form and offers a '
        'deliberate reload', (tester) async {
      await _pump(tester, detailState(), editing: true);
      await _enter(tester, 'property-asset-edit-name', 'Local edit');

      await _pump(
        tester,
        detailState(selected: property(name: 'Remote value', version: 2)),
        editing: true,
      );

      expect(_text(tester, 'property-asset-edit-name'), 'Local edit');
      expect(
        find.byKey(const Key('property-asset-remote-newer')),
        findsOneWidget,
      );
      expect(find.textContaining('auf Version 2 geändert'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('property-asset-remote-newer-reload')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('property-asset-discard-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('property-asset-discard-confirm')));
      await tester.pumpAndSettle();

      expect(_text(tester, 'property-asset-edit-name'), 'Remote value');
      expect(
        find.byKey(const Key('property-asset-remote-newer')),
        findsNothing,
      );
    });

    testWidgets('a clean form follows a canonical refresh while editing', (
      tester,
    ) async {
      await _pump(tester, detailState(), editing: true);
      await _pump(
        tester,
        detailState(selected: property(name: 'Remote value', version: 2)),
        editing: true,
      );

      expect(_text(tester, 'property-asset-edit-name'), 'Remote value');
      expect(
        find.byKey(const Key('property-asset-remote-newer')),
        findsNothing,
      );
    });

    testWidgets('save failures keep the form, map server validation to the '
        'form and retry transient failures', (tester) async {
      var retries = 0;
      await _pump(
        tester,
        detailState(
          mutationPhase: PropertyMutationPhase.failed,
          failureKind: PropertyRepositoryFailureKind.validationFailed,
          message: 'Units must be a non-negative integer',
        ),
        editing: true,
        onRetry: () => retries++,
      );

      expect(find.byKey(const Key('property-asset-failed')), findsOneWidget);
      expect(find.text('Servervalidierung fehlgeschlagen'), findsOneWidget);
      expect(find.text('Units must be a non-negative integer'), findsOneWidget);
      expect(find.byKey(const Key('property-asset-retry')), findsNothing);
      expect(find.byKey(const Key('property-asset-form')), findsOneWidget);

      await _pump(
        tester,
        detailState(
          mutationPhase: PropertyMutationPhase.failed,
          failureKind: PropertyRepositoryFailureKind.infrastructureFailure,
          message: 'Temporary failure.',
        ),
        editing: true,
        onRetry: () => retries++,
      );
      await tester.tap(find.byKey(const Key('property-asset-retry')));
      expect(retries, 1);

      await _pump(
        tester,
        detailState(
          mutationPhase: PropertyMutationPhase.forbidden,
          failureKind: PropertyRepositoryFailureKind.forbidden,
          message: 'Property updates are not permitted.',
        ),
        editing: true,
      );
      expect(find.byKey(const Key('property-asset-forbidden')), findsOneWidget);
    });

    testWidgets('save is blocked while a mutation is in flight', (
      tester,
    ) async {
      await _pump(
        tester,
        detailState(mutationPhase: PropertyMutationPhase.submitting),
        editing: true,
      );

      expect(find.byKey(const Key('property-asset-saving')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('property-asset-save')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('property-asset-cancel')))
            .onPressed,
        isNull,
      );
    });

    for (final viewport in goldenViewports) {
      testWidgets('read and edit have no overflow at $viewport', (
        tester,
      ) async {
        final longProperty = property(
          name:
              'Ein außerordentlich langer Objektname der auf keinen Fall in '
              'eine Zeile passt und deshalb umbrechen muss',
          addressLine1:
              'Sehr lange Straße mit vielen Wörtern und Zusätzen 1234a',
          addressLine2: 'Hinterhaus, 3. Obergeschoss links, Aufgang B',
          sqft: 123456.75,
          yearBuilt: 1875,
          notes: List<String>.filled(
            12,
            'Sehr lange interne Hinweise ohne horizontales Scrollen.',
          ).join(' '),
        );
        await _pump(
          tester,
          detailState(selected: longProperty, liveUpdatesDegraded: true),
          editing: false,
          viewport: viewport,
        );
        expect(tester.takeException(), isNull);

        await _pump(
          tester,
          detailState(
            selected: longProperty,
            mutationPhase: PropertyMutationPhase.conflict,
            failureKind: PropertyRepositoryFailureKind.versionConflict,
            versionConflict: PropertyVersionConflict(
              expectedVersion: 1,
              actualVersion: 2,
              currentProperty: longProperty,
            ),
          ),
          editing: true,
          viewport: viewport,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('property-asset-form')), findsOneWidget);
      });
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  ReferenceSliceState state, {
  required bool editing,
  bool canEdit = true,
  PropertyWorkspaceDirtyRegistry? registry,
  ValueChanged<bool>? onEditingChanged,
  PropertyAssetUpdate? onUpdate,
  VoidCallback? onRetry,
  Size viewport = const Size(1440, 900),
}) async {
  setViewport(tester, viewport);
  await tester.pumpWidget(
    wrapApp(
      PropertyAssetPanel(
        state: state,
        canEdit: canEdit,
        editing: editing,
        onEditingChanged: onEditingChanged ?? (_) {},
        dirtyRegistry: registry ?? _sharedRegistry,
        onUpdate: onUpdate ?? (_, {expectedVersion}) async => true,
        onRetry: onRetry ?? () {},
      ),
    ),
  );
  // Not pumpAndSettle: in-flight states carry indeterminate progress
  // indicators, which never settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

final PropertyWorkspaceDirtyRegistry _sharedRegistry =
    PropertyWorkspaceDirtyRegistry();

/// The form extends below a 900px viewport; scroll the control into view
/// before tapping so the tap is never silently missed.
Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

String? _text(WidgetTester tester, String key) {
  return tester.widget<TextFormField>(find.byKey(Key(key))).controller?.text;
}
