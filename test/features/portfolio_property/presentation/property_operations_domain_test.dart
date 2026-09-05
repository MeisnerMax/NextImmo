import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_workspace_host_state.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_workspace_screen.dart';

import 'property_workspace_fixtures.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Set<String> permissions,
  Widget Function(BuildContext, String)? operationsTasksBuilder,
  Widget Function(BuildContext, String, PropertyOperationsSubArea)?
  operationsBuilder,
}) async {
  setViewport(tester, const Size(1440, 900));
  await tester.pumpWidget(
    wrapApp(
      PropertyWorkspaceView(
        state: detailState(permissions: permissions),
        initialPropertyId: 'property-a',
        onOpenProperty: (_) async => true,
        onCloseProperty: () {},
        onLoadMore: () async {},
        onReload: () async {},
        onSetIncludeArchived: (_) async {},
        onRefreshWorkspaces: () async {},
        onUpdateProperty: (changes, {expectedVersion}) async => true,
        onRetryUpdate: () async {},
        operationsTasksBuilder: operationsTasksBuilder,
        operationsBuilder: operationsBuilder,
      ),
    ),
  );
  await tester.pump();
}

/// Marks which sub-area was built, so a test can tell them apart.
Widget Function(BuildContext, String, PropertyOperationsSubArea) _builder(
  List<PropertyOperationsSubArea> built,
) {
  return (context, propertyId, subArea) {
    built.add(subArea);
    return SizedBox(key: Key('fake-${subArea.name}-surface'));
  };
}

void main() {
  group('Betrieb registration', () {
    test('any one of its three read capabilities makes it visible', () {
      for (final permission in const <String>[
        'task.read',
        'maintenance.read',
        'capex.read',
      ]) {
        expect(
          visiblePropertyWorkspaceDomains(<String>{
            'property.read',
            permission,
          }).map((registration) => registration.domain),
          contains(PropertyWorkspaceDomain.operations),
          reason: '$permission alone opens a readable sub-area',
        );
      }
      expect(
        visiblePropertyWorkspaceDomains(const <String>{
              'property.read',
              'task.read',
            })
            .singleWhere(
              (registration) =>
                  registration.domain == PropertyWorkspaceDomain.operations,
            )
            .label,
        'Betrieb',
      );
    });

    test('none of them means the domain is absent, never disabled', () {
      // Foundation §3 / PROPERTY_OPERATIONS_V2 §8.
      expect(
        visiblePropertyWorkspaceDomains(const <String>{
          'property.read',
        }).map((registration) => registration.domain),
        isNot(contains(PropertyWorkspaceDomain.operations)),
      );
    });

    test('each sub-area carries its own read capability', () {
      expect(
        visiblePropertyOperationsSubAreas(const <String>{
          'maintenance.read',
          'task.read',
        }),
        <PropertyOperationsSubArea>[
          PropertyOperationsSubArea.maintenance,
          PropertyOperationsSubArea.tasks,
        ],
        reason: 'CapEx is missing because capex.read is, and order is spec '
            'order',
      );
      expect(
        visiblePropertyOperationsSubAreas(const <String>{'property.read'}),
        isEmpty,
      );
    });
  });

  group('Betrieb sub-navigation', () {
    testWidgets('shows Wartung, CapEx and Aufgaben, and mounts the selected '
        'one', (tester) async {
      final built = <PropertyOperationsSubArea>[];
      await _pump(
        tester,
        permissions: const <String>{
          'property.read',
          'property.update',
          'maintenance.read',
          'capex.read',
          'task.read',
        },
        operationsTasksBuilder:
            (context, propertyId) =>
                const SizedBox(key: Key('fake-tasks-surface')),
        operationsBuilder: _builder(built),
      );

      await tester.tap(
        find.byKey(const Key('property-workspace-nav-operations')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('property-operations')), findsOneWidget);
      for (final name in const <String>['maintenance', 'capex', 'tasks']) {
        expect(
          find.byKey(Key('property-operations-sub-$name')),
          findsOneWidget,
        );
      }
      // Wartung leads, because disruption comes before planned investment.
      expect(find.byKey(const Key('fake-maintenance-surface')), findsOneWidget);
      expect(built, <PropertyOperationsSubArea>[
        PropertyOperationsSubArea.maintenance,
      ]);

      await tester.tap(find.byKey(const Key('property-operations-sub-capex')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake-capex-surface')), findsOneWidget);
      expect(
        find.byKey(const Key('fake-maintenance-surface')),
        findsNothing,
        reason: 'one sub-area at a time, each with its own state',
      );

      await tester.tap(find.byKey(const Key('property-operations-sub-tasks')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake-tasks-surface')), findsOneWidget);
    });

    testWidgets('a sub-area the membership cannot read is not offered', (
      tester,
    ) async {
      final built = <PropertyOperationsSubArea>[];
      await _pump(
        tester,
        permissions: const <String>{
          'property.read',
          'property.update',
          'maintenance.read',
        },
        operationsTasksBuilder:
            (context, propertyId) =>
                const SizedBox(key: Key('fake-tasks-surface')),
        operationsBuilder: _builder(built),
      );

      await tester.tap(
        find.byKey(const Key('property-workspace-nav-operations')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('property-operations-sub-maintenance')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-operations-sub-capex')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('property-operations-sub-tasks')),
        findsNothing,
      );
      expect(find.byKey(const Key('fake-maintenance-surface')), findsOneWidget);
    });

    testWidgets('a sub-area this host cannot build is not offered either', (
      tester,
    ) async {
      // The permission is there, the builder is not: offering the chip would
      // lead to an empty frame, which is what the registry rule prevents.
      await _pump(
        tester,
        permissions: const <String>{
          'property.read',
          'property.update',
          'maintenance.read',
          'task.read',
        },
        operationsTasksBuilder:
            (context, propertyId) =>
                const SizedBox(key: Key('fake-tasks-surface')),
      );

      await tester.tap(
        find.byKey(const Key('property-workspace-nav-operations')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('property-operations-sub-maintenance')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('property-operations-sub-tasks')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('fake-tasks-surface')), findsOneWidget);
    });

    testWidgets('the last sub-area is remembered across a domain switch', (
      tester,
    ) async {
      final built = <PropertyOperationsSubArea>[];
      await _pump(
        tester,
        permissions: const <String>{
          'property.read',
          'property.update',
          'maintenance.read',
          'capex.read',
          'task.read',
        },
        operationsTasksBuilder:
            (context, propertyId) =>
                const SizedBox(key: Key('fake-tasks-surface')),
        operationsBuilder: _builder(built),
      );

      await tester.tap(
        find.byKey(const Key('property-workspace-nav-operations')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('property-operations-sub-capex')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('property-workspace-nav-asset')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('property-workspace-nav-operations')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('fake-capex-surface')),
        findsOneWidget,
        reason: 'returning to a domain lands where the user left it',
      );
    });

    testWidgets('the asset edit action stays with the Objekt domain', (
      tester,
    ) async {
      await _pump(
        tester,
        permissions: const <String>{
          'property.read',
          'property.update',
          'task.read',
        },
        operationsTasksBuilder:
            (context, propertyId) =>
                const SizedBox(key: Key('fake-tasks-surface')),
      );

      await tester.tap(
        find.byKey(const Key('property-workspace-nav-operations')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('property-workspace-edit')), findsNothing);
    });

    testWidgets('without any of the three there is no Betrieb entry at all', (
      tester,
    ) async {
      await _pump(tester, permissions: fullPermissions);

      expect(
        find.byKey(const Key('property-workspace-nav-operations')),
        findsNothing,
      );
      expect(find.text('Betrieb'), findsNothing);
    });

    for (final viewport in const <Size>[Size(390, 844), Size(1440, 900)]) {
      testWidgets('has no overflow at $viewport', (tester) async {
        final built = <PropertyOperationsSubArea>[];
        setViewport(tester, viewport);
        await tester.pumpWidget(
          wrapApp(
            PropertyWorkspaceView(
              state: detailState(
                permissions: const <String>{
                  'property.read',
                  'property.update',
                  'maintenance.read',
                  'capex.read',
                  'task.read',
                },
              ),
              initialPropertyId: 'property-a',
              onOpenProperty: (_) async => true,
              onCloseProperty: () {},
              onLoadMore: () async {},
              onReload: () async {},
              onSetIncludeArchived: (_) async {},
              onRefreshWorkspaces: () async {},
              onUpdateProperty: (changes, {expectedVersion}) async => true,
              onRetryUpdate: () async {},
              operationsTasksBuilder:
                  (context, propertyId) =>
                      const SizedBox(key: Key('fake-tasks-surface')),
              operationsBuilder: _builder(built),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const Key('property-workspace-nav-operations')),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('property-operations')), findsOneWidget);
      });
    }
  });
}
