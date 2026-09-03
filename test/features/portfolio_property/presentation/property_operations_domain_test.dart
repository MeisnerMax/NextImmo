import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_workspace_host_state.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_workspace_screen.dart';

import 'property_workspace_fixtures.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Set<String> permissions,
  Widget Function(BuildContext, String)? operationsTasksBuilder,
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
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('Betrieb registers gated on task.read, its one implemented child', () {
    final withTasks = visiblePropertyWorkspaceDomains(const <String>{
      'property.read',
      'task.read',
    });
    expect(
      withTasks.map((registration) => registration.domain),
      contains(PropertyWorkspaceDomain.operations),
    );
    expect(
      withTasks
          .singleWhere(
            (registration) =>
                registration.domain == PropertyWorkspaceDomain.operations,
          )
          .label,
      'Betrieb',
    );

    // Without task.read the domain is absent — hidden, never disabled
    // (Foundation §3 / PROPERTY_OPERATIONS_V2 §8).
    final withoutTasks = visiblePropertyWorkspaceDomains(const <String>{
      'property.read',
    });
    expect(
      withoutTasks.map((registration) => registration.domain),
      isNot(contains(PropertyWorkspaceDomain.operations)),
    );
  });

  testWidgets('selecting Betrieb mounts the injected task surface with the '
      'Aufgaben sub-target', (tester) async {
    final boundPropertyIds = <String>[];
    await _pump(
      tester,
      permissions: const <String>{
        'property.read',
        'property.update',
        'task.read',
      },
      operationsTasksBuilder: (context, propertyId) {
        boundPropertyIds.add(propertyId);
        return const SizedBox(key: Key('fake-task-surface'));
      },
    );

    expect(
      find.byKey(const Key('property-workspace-nav-operations')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('property-workspace-nav-operations')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('property-operations')), findsOneWidget);
    expect(
      find.byKey(const Key('property-operations-sub-tasks')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('fake-task-surface')), findsOneWidget);
    expect(boundPropertyIds, contains('property-a'));
    // The asset edit action belongs to the Objekt domain only.
    expect(find.byKey(const Key('property-workspace-edit')), findsNothing);
  });

  testWidgets('without task.read the workspace shows no Betrieb entry at all', (
    tester,
  ) async {
    await _pump(tester, permissions: fullPermissions);

    expect(
      find.byKey(const Key('property-workspace-nav-operations')),
      findsNothing,
    );
    expect(find.text('Betrieb'), findsNothing);
  });
}
