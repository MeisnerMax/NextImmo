import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/navigation/app_navigation.dart';
import 'package:neximmo_app/ui/state/app_state.dart';

void main() {
  test('every GlobalPage has exactly one canonical navigation destination', () {
    final destinations = appNavigationGroups
        .expand((group) => group.items)
        .toList(growable: false);

    expect(
      destinations.map((item) => item.page).toSet(),
      GlobalPage.values.toSet(),
    );
    for (final page in GlobalPage.values) {
      expect(
        destinations.where((item) => item.page == page),
        hasLength(1),
        reason: page.name,
      );
      expect(navigationDestinationForPage(page).page, page);
      expect(
        navigationGroupForPage(page).items,
        contains(navigationDestinationForPage(page)),
      );
    }
  });

  test('reference property route round-trips a stable encoded id', () {
    final route = referencePropertyRoute('property / ä');

    expect(route, '/properties/property%20%2F%20%C3%A4');
    expect(referencePropertyIdFromRoute(route), 'property / ä');
    expect(referencePropertyIdFromRoute('/properties'), isNull);
    expect(referencePropertyIdFromRoute('/properties/'), isNull);
    expect(referencePropertyIdFromRoute('/other/property-a'), isNull);
    expect(() => referencePropertyRoute('  '), throwsArgumentError);
  });

  test('property documents route round-trips a stable encoded id', () {
    final route = propertyDocumentsRouteFor('property / ä');

    expect(route, '/property-documents/property%20%2F%20%C3%A4');
    expect(propertyDocumentsPropertyIdFromRoute(route), 'property / ä');
    expect(
      propertyDocumentsPropertyIdFromRoute(propertyDocumentsRoute),
      isNull,
    );
    expect(
      propertyDocumentsPropertyIdFromRoute('/property-documents/'),
      isNull,
    );
    expect(propertyDocumentsPropertyIdFromRoute('/properties/p-1'), isNull);
    expect(() => propertyDocumentsRouteFor('  '), throwsArgumentError);
  });

  test('cloud routes resolve to canonical shell targets', () {
    // UX-FOUNDATION-IMPL-01 (Foundation §2): until the dashboard is
    // cloud-ready, the post-login landing target is properties — landing on
    // the migrationRequired dashboard empty state helps nobody.
    expect(cloudRouteTargetFromName('/')?.page, GlobalPage.properties);
    expect(cloudRouteTargetFromName(null)?.page, GlobalPage.properties);
    expect(cloudRouteTargetFromName('')?.page, GlobalPage.properties);
    expect(
      cloudRouteTargetFromName(referencePropertyRoute('property-a'))?.surface,
      CloudRouteSurface.propertyDetail,
    );
    expect(
      cloudRouteTargetFromName(
        referencePropertyRoute('property-a'),
      )?.propertyId,
      'property-a',
    );
    expect(
      cloudRouteTargetFromName(referenceMembersRoute)?.page,
      GlobalPage.adminUsers,
    );
    expect(
      cloudRouteTargetFromName(propertyDocumentsRouteFor('property-a'))?.page,
      GlobalPage.documents,
    );
    expect(
      cloudRouteTargetFromName(
        operationsOverviewRouteFor('property-a'),
      )?.surface,
      CloudRouteSurface.operationsOverview,
    );
    expect(
      cloudRouteTargetFromName(
        operationsOverviewRouteFor('property-a'),
      )?.propertyId,
      'property-a',
    );
    expect(
      cloudRouteTargetFromName(operationsAlertsRouteFor('property-a'))?.surface,
      CloudRouteSurface.operationsAlerts,
    );
    expect(cloudRouteTargetFromName('/unknown'), isNull);
  });

  test('task and notification routes resolve to their shell targets (A15)', () {
    final tasks = cloudRouteTargetFromName(tasksRoute);
    expect(tasks?.page, GlobalPage.tasks);
    expect(tasks?.surface, CloudRouteSurface.tasks);

    final detail = cloudRouteTargetFromName(taskRouteFor('task-1'));
    expect(detail?.page, GlobalPage.tasks);
    expect(detail?.surface, CloudRouteSurface.taskDetail);
    expect(detail?.taskId, 'task-1');

    final inbox = cloudRouteTargetFromName(notificationsRoute);
    expect(inbox?.page, GlobalPage.notifications);
    expect(inbox?.surface, CloudRouteSurface.notifications);

    // `/tasks/` with an empty id stays unclaimed instead of resolving to a
    // detail without a task.
    expect(cloudRouteTargetFromName('/tasks/'), isNull);
  });

  test('task route round-trips a stable encoded id', () {
    final route = taskRouteFor('task / ä');

    expect(route, '/tasks/task%20%2F%20%C3%A4');
    expect(taskIdFromRoute(route), 'task / ä');
    expect(taskIdFromRoute(tasksRoute), isNull);
    expect(taskIdFromRoute('/tasks/'), isNull);
    expect(taskIdFromRoute('/other/task-1'), isNull);
    expect(taskIdFromRoute(null), isNull);
    expect(() => taskRouteFor('  '), throwsArgumentError);
  });

  test('tasks and notifications pin their cloud read permissions (A15)', () {
    // Shared §8.2: these pages ride the server permission vocabulary. The
    // determinism test below cannot catch a silently remapped key; these
    // pins can.
    expect(cloudReadPermissionForPage(GlobalPage.tasks), 'task.read');
    expect(cloudReadPermissionForPage(GlobalPage.taskTemplates), 'task.read');
    // PERMISSION-CATALOG-02: the inbox is the OWN feed and the server serves
    // it recipient-scoped without any permission
    // (notifications_select_own_or_read). notification.read is the
    // workspace-wide oversight capability and stays admin-only — gating the
    // page on it would hide members' own notifications for no server reason.
    expect(cloudReadPermissionForPage(GlobalPage.notifications), isNull);
    // TASK-CENTER-01 flipped `tasks`, NOTIFICATION-INBOX-01 flips
    // `notifications` — each wave independently. `taskTemplates` stays
    // migrationRequired until TASK-SCHEDULER-01 delivers a real templates
    // surface (B9) — flipping it early would expose an empty page.
    expect(
      cloudReadinessForPage(GlobalPage.tasks),
      CloudDestinationReadiness.ready,
    );
    expect(
      cloudReadinessForPage(GlobalPage.notifications),
      CloudDestinationReadiness.ready,
    );
    expect(
      cloudReadinessForPage(GlobalPage.taskTemplates),
      CloudDestinationReadiness.migrationRequired,
    );
  });

  test('every GlobalPage has deterministic cloud readiness and permission', () {
    for (final page in GlobalPage.values) {
      expect(cloudReadinessForPage(page), isA<CloudDestinationReadiness>());
      final permission = cloudReadPermissionForPage(page);
      expect(
        isPageAllowedForPermissions(
          page,
          permission == null ? const <String>{} : <String>{permission},
        ),
        isTrue,
        reason: page.name,
      );
    }
  });

  test('unknown or missing roles cannot access navigation pages', () {
    for (final page in GlobalPage.values) {
      expect(isPageAllowedForRole(page, ''), isFalse);
      expect(isPageAllowedForRole(page, 'unknown'), isFalse);
    }
  });

  test('valuation navigation exposes only the consolidated workflow', () {
    final group = appNavigationGroups.singleWhere(
      (item) => item.routeKey == 'valuation_scenarios',
    );

    expect(group.items.map((item) => item.page), <GlobalPage>[
      GlobalPage.valuations,
      GlobalPage.criteriaSets,
      GlobalPage.compare,
    ]);
    expect(group.items.map((item) => item.label), <String>[
      'Bewertungen',
      'Kriterien',
      'Szenariovergleich',
    ]);
  });
}
