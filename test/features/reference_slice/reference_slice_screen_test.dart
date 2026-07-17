import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';
import 'package:neximmo_app/features/reference_slice/presentation/reference_slice_screen.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

void main() {
  group('ReferenceSliceView', () {
    testWidgets('renders unauthenticated and MFA states without data actions', (
      tester,
    ) async {
      await _pumpView(
        tester,
        state: _state(authPhase: ReferenceAuthPhase.unauthenticated),
      );

      expect(find.text('Sign in required'), findsOneWidget);
      expect(find.byKey(const Key('reference-list-pane')), findsNothing);

      await _pumpView(
        tester,
        state: _state(authPhase: ReferenceAuthPhase.mfaRequired),
      );

      expect(find.text('Multi-factor authentication required'), findsOneWidget);
      expect(find.byKey(const Key('reference-list-pane')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('filters the property list without losing workspace scope', (
      tester,
    ) async {
      await _pumpView(tester, state: _readyState(twoProperties: true));

      expect(find.text('Atlas House'), findsWidgets);
      expect(find.text('Beta Offices'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('reference-property-search')),
        'beta',
      );
      await tester.pump();

      expect(
        find.byKey(const Key('reference-property-property-a')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('reference-property-property-b')),
        findsOneWidget,
      );
      expect(find.text('Workspace A'), findsOneWidget);
    });

    testWidgets('phone switches between list and vertically stacked detail', (
      tester,
    ) async {
      _setViewport(tester, const Size(390, 844));
      var showDetail = false;

      await tester.pumpWidget(
        StatefulBuilder(
          builder:
              (context, setState) => _app(
                ReferenceSliceView(
                  state: _readyState(),
                  showCompactDetail: showDetail,
                  onBackToList: () => setState(() => showDetail = false),
                  onOpenProperty:
                      (_) async => setState(() => showDetail = true),
                  onRefreshWorkspaces: _noop,
                  onSelectWorkspace: _noopString,
                  onReloadProperties: _noop,
                  onLoadNextPage: _noop,
                  onUpdateProperty: (_) async {},
                  onRetryUpdate: _noop,
                ),
              ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reference-list-pane')), findsOneWidget);
      expect(find.byKey(const Key('reference-detail-pane')), findsNothing);

      await tester.tap(find.byKey(const Key('reference-property-property-a')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reference-list-pane')), findsNothing);
      expect(find.byKey(const Key('reference-detail-pane')), findsOneWidget);
      expect(find.byKey(const Key('reference-edit-form')), findsOneWidget);
      expect(find.byKey(const Key('reference-compact-back')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('reference-compact-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reference-list-pane')), findsOneWidget);
    });

    for (final viewport in const <Size>[
      Size(390, 844),
      Size(767, 900),
      Size(768, 900),
      Size(1024, 768),
      Size(1199, 900),
      Size(1200, 900),
      Size(1440, 900),
    ]) {
      testWidgets('has no overflow at $viewport', (tester) async {
        await _pumpView(tester, state: _readyState(), viewport: viewport);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('reference-list-pane')), findsOneWidget);
        if (viewport.width > 1199) {
          expect(
            find.byKey(const Key('reference-detail-pane')),
            findsOneWidget,
          );
        } else {
          expect(find.byKey(const Key('reference-detail-pane')), findsNothing);
        }
      });
    }

    testWidgets('shows conflict feedback and retryable failure action', (
      tester,
    ) async {
      await _pumpView(
        tester,
        state: _readyState(
          mutationPhase: PropertyMutationPhase.conflict,
          versionConflict: PropertyVersionConflict(
            expectedVersion: 1,
            actualVersion: 2,
            currentProperty: _property(version: 2),
          ),
        ),
        viewport: const Size(1440, 900),
      );

      expect(find.textContaining('Version conflict'), findsOneWidget);

      await _pumpView(
        tester,
        state: _readyState(
          mutationPhase: PropertyMutationPhase.failed,
          failureKind: PropertyRepositoryFailureKind.infrastructureFailure,
          message: 'Temporary failure.',
        ),
        viewport: const Size(1440, 900),
      );

      expect(find.text('Temporary failure.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    for (final golden in const <(String, Size)>[
      ('phone', Size(390, 844)),
      ('tablet', Size(1024, 768)),
      ('desktop', Size(1440, 900)),
    ]) {
      testWidgets('matches ready $golden golden', (tester) async {
        await _pumpView(
          tester,
          state: _readyState(twoProperties: true),
          viewport: golden.$2,
        );

        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/reference_slice_ready_${golden.$1}.png'),
        );
      });
    }
  });
}

Future<void> _pumpView(
  WidgetTester tester, {
  required ReferenceSliceState state,
  Size viewport = const Size(1440, 900),
}) async {
  _setViewport(tester, viewport);
  await tester.pumpWidget(
    _app(
      ReferenceSliceView(
        state: state,
        showCompactDetail: false,
        onBackToList: () {},
        onRefreshWorkspaces: _noop,
        onSelectWorkspace: _noopString,
        onReloadProperties: _noop,
        onLoadNextPage: _noop,
        onOpenProperty: _noopString,
        onUpdateProperty: (_) async {},
        onRetryUpdate: _noop,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _app(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );
}

void _setViewport(WidgetTester tester, Size viewport) {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _noop() async {}

Future<void> _noopString(String _) async {}

ReferenceSliceState _state({required ReferenceAuthPhase authPhase}) {
  return ReferenceSliceState(
    authPhase: authPhase,
    workspacePhase: WorkspacePhase.idle,
    propertyListPhase: PropertyListPhase.idle,
    propertyDetailPhase: PropertyDetailPhase.idle,
    mutationPhase: PropertyMutationPhase.idle,
  );
}

ReferenceSliceState _readyState({
  bool twoProperties = false,
  PropertyMutationPhase mutationPhase = PropertyMutationPhase.idle,
  PropertyRepositoryFailureKind? failureKind,
  PropertyVersionConflict? versionConflict,
  String? message,
}) {
  final property = _property();
  return ReferenceSliceState(
    authPhase: ReferenceAuthPhase.authenticated,
    workspacePhase: WorkspacePhase.selected,
    propertyListPhase: PropertyListPhase.ready,
    propertyDetailPhase: PropertyDetailPhase.ready,
    mutationPhase: mutationPhase,
    userId: 'user-a',
    workspaces: <WorkspaceAccess>[_access()],
    selectedWorkspaceId: 'workspace-a',
    properties: <PropertyDto>[
      property,
      if (twoProperties)
        _property(
          id: 'property-b',
          name: 'Beta Offices',
          address: 'Office Road 2',
        ),
    ],
    selectedProperty: property,
    failureKind: failureKind,
    versionConflict: versionConflict,
    message: message,
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
  String name = 'Atlas House',
  String address = 'Long Street 123',
  int version = 1,
}) {
  return PropertyDto(
    id: id,
    workspaceId: 'workspace-a',
    name: name,
    addressLine1: address,
    zip: '10115',
    city: 'Berlin',
    country: 'DE',
    propertyType: 'mixed_use',
    units: 12,
    notes: 'Reference slice fixture',
    status: PropertyStatus.active,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 17),
    createdBy: 'user-a',
    updatedBy: 'user-a',
    version: version,
  );
}
