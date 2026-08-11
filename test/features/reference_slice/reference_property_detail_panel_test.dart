import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';
import 'package:neximmo_app/features/reference_slice/presentation/reference_property_detail_panel.dart';

// Regression tests for GP-STAGING-WEB-FIX-01: unsaved form input must survive
// state churn (entitlement revalidation notifies, realtime refreshes) while
// clean forms keep following the canonical record and concurrent remote
// changes stay protected by the expectedVersion conflict mechanism.
void main() {
  late List<({PropertyUpdateDto changes, int? expectedVersion})> updates;

  setUp(() {
    updates = <({PropertyUpdateDto changes, int? expectedVersion})>[];
  });

  Future<void> pumpPanel(WidgetTester tester, ReferenceSliceState state) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReferencePropertyDetailPanel(
            state: state,
            canUpdate: true,
            showBack: false,
            onBack: () {},
            onUpdate: (changes, {int? expectedVersion}) async {
              updates.add((changes: changes, expectedVersion: expectedVersion));
            },
            onRetry: () async {},
          ),
        ),
      ),
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('reference-save-property')));
    await tester.tap(find.byKey(const Key('reference-save-property')));
    await tester.pump();
  }

  String notesText(WidgetTester tester) {
    return tester
        .widget<TextFormField>(find.byKey(const Key('reference-edit-notes')))
        .controller!
        .text;
  }

  testWidgets('clean form follows a canonical refresh', (tester) async {
    await pumpPanel(tester, _state(property: _property(version: 1)));
    expect(notesText(tester), 'Seeded notes');

    // A remote actor changed the property; the form is untouched, so the
    // fields follow the canonical record.
    await pumpPanel(
      tester,
      _state(property: _property(version: 2, notes: 'Remote notes')),
    );

    expect(notesText(tester), 'Remote notes');

    await submit(tester);
    expect(updates.single.expectedVersion, 2);
  });

  testWidgets('dirty input survives state churn without a property change', (
    tester,
  ) async {
    final property = _property(version: 1);
    await pumpPanel(tester, _state(property: property));
    await tester.enterText(
      find.byKey(const Key('reference-edit-notes')),
      'Unsaved local input',
    );

    // An entitlement revalidation republishes state objects without changing
    // the property. Repeated ticks must not clear the input.
    for (var round = 0; round < 3; round++) {
      await pumpPanel(tester, _state(property: property));
      expect(notesText(tester), 'Unsaved local input');
    }
  });

  testWidgets(
    'dirty input survives a remote refresh and saves against its base version',
    (tester) async {
      await pumpPanel(tester, _state(property: _property(version: 1)));
      await tester.enterText(
        find.byKey(const Key('reference-edit-notes')),
        'Unsaved local input',
      );

      // A concurrent remote update arrives via realtime while the form is
      // dirty: the input is not silently overwritten...
      await pumpPanel(
        tester,
        _state(property: _property(version: 2, notes: 'Remote notes')),
      );
      expect(notesText(tester), 'Unsaved local input');

      // ...and the save is based on the version the edits were made on, so
      // the server surfaces a version conflict instead of losing the remote
      // change.
      await submit(tester);
      expect(updates.single.expectedVersion, 1);
      expect(updates.single.changes.notes, 'Unsaved local input');
    },
  );

  testWidgets('a successful save reseeds the form as clean', (tester) async {
    await pumpPanel(tester, _state(property: _property(version: 1)));
    await tester.enterText(
      find.byKey(const Key('reference-edit-notes')),
      'Saved notes',
    );

    // The controller reports success with the canonical result of this save.
    await pumpPanel(
      tester,
      _state(
        property: _property(version: 2, notes: 'Saved notes'),
        mutationPhase: PropertyMutationPhase.succeeded,
      ),
    );
    expect(notesText(tester), 'Saved notes');

    // The form is clean again: a later canonical refresh is followed.
    await pumpPanel(
      tester,
      _state(property: _property(version: 3, notes: 'Third notes')),
    );
    expect(notesText(tester), 'Third notes');

    await submit(tester);
    expect(updates.single.expectedVersion, 3);
  });

  testWidgets(
    'a surfaced conflict keeps the input and re-saves against the shown version',
    (tester) async {
      await pumpPanel(tester, _state(property: _property(version: 1)));
      await tester.enterText(
        find.byKey(const Key('reference-edit-notes')),
        'Conflicting input',
      );

      // The stale save came back as a version conflict; the controller now
      // shows the server's current record while the banner promises that the
      // form input is preserved.
      final current = _property(version: 4, notes: 'Remote winner');
      await pumpPanel(
        tester,
        _state(
          property: current,
          mutationPhase: PropertyMutationPhase.conflict,
          versionConflict: PropertyVersionConflict(
            expectedVersion: 1,
            actualVersion: 4,
            currentProperty: current,
          ),
        ),
      );
      expect(notesText(tester), 'Conflicting input');

      // Re-saving after the surfaced conflict proceeds against the version
      // the user has been shown.
      await submit(tester);
      expect(updates.single.expectedVersion, 4);
    },
  );

  testWidgets('switching properties reseeds the form', (tester) async {
    await pumpPanel(tester, _state(property: _property(version: 1)));
    await tester.enterText(
      find.byKey(const Key('reference-edit-notes')),
      'Input for property-a',
    );

    await pumpPanel(
      tester,
      _state(
        property: _property(
          id: 'property-b',
          version: 7,
          notes: 'Notes of property-b',
        ),
      ),
    );

    // No dirty input leaks across the entity switch, and saves are based on
    // the new property's version.
    expect(notesText(tester), 'Notes of property-b');
    await submit(tester);
    expect(updates.single.expectedVersion, 7);
  });

  testWidgets('no dirty input leaks across a cleared selection', (
    tester,
  ) async {
    await pumpPanel(tester, _state(property: _property(version: 1)));
    await tester.enterText(
      find.byKey(const Key('reference-edit-notes')),
      'Input before reset',
    );

    // Session/workspace reset: the selection is cleared, then a property is
    // loaded again (same id, fresh context). The form seeds canonically.
    await pumpPanel(tester, _state(property: null));
    await pumpPanel(tester, _state(property: _property(version: 5)));

    expect(notesText(tester), 'Seeded notes');
    await submit(tester);
    expect(updates.single.expectedVersion, 5);
  });
}

ReferenceSliceState _state({
  required PropertyDto? property,
  PropertyMutationPhase mutationPhase = PropertyMutationPhase.idle,
  PropertyVersionConflict? versionConflict,
}) {
  return ReferenceSliceState(
    authPhase: ReferenceAuthPhase.authenticated,
    assuranceLevel: AuthenticationAssuranceLevel.aal2,
    workspacePhase: WorkspacePhase.selected,
    propertyListPhase: PropertyListPhase.ready,
    propertyDetailPhase:
        property == null ? PropertyDetailPhase.idle : PropertyDetailPhase.ready,
    mutationPhase: mutationPhase,
    userId: 'user-a',
    workspaces: <WorkspaceAccess>[_access()],
    selectedWorkspaceId: 'workspace-a',
    properties: const <PropertySummaryDto>[],
    selectedProperty: property,
    versionConflict: versionConflict,
  );
}

WorkspaceAccess _access() {
  return WorkspaceAccess(
    workspace: const WorkspaceSummary(
      id: 'workspace-a',
      key: 'workspace-a',
      name: 'Workspace A',
      version: 1,
    ),
    membership: const MembershipSummary(
      id: 'membership-a',
      workspaceId: 'workspace-a',
      userId: 'user-a',
      roleId: 'manager',
      version: 1,
    ),
    permissions: <String>{'property.read', 'property.update'},
  );
}

PropertyDto _property({
  String id = 'property-a',
  int version = 1,
  String notes = 'Seeded notes',
}) {
  return PropertyDto(
    id: id,
    workspaceId: 'workspace-a',
    name: 'Atlas House',
    addressLine1: 'Long Street 123',
    zip: '10115',
    city: 'Berlin',
    country: 'DE',
    propertyType: 'mixed_use',
    units: 12,
    notes: notes,
    status: PropertyStatus.active,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 17),
    createdBy: 'user-a',
    updatedBy: 'user-a',
    version: version,
  );
}
