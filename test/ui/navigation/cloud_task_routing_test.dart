import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/navigation/app_navigation.dart';
import 'package:neximmo_app/ui/state/app_state.dart';

void main() {
  test('operational Tasks are a cloud-ready task.read destination', () {
    expect(
      cloudReadinessForPage(GlobalPage.tasks),
      CloudDestinationReadiness.ready,
    );
    expect(cloudReadPermissionForPage(GlobalPage.tasks), 'task.read');
    expect(
      isPageAllowedForPermissions(GlobalPage.tasks, const <String>{'task.read'}),
      isTrue,
    );
    expect(
      isPageAllowedForPermissions(GlobalPage.tasks, const <String>{}),
      isFalse,
    );
    expect(navigationDestinationForPage(GlobalPage.tasks).label, 'Aufgaben');
    expect(navigationGroupForPage(GlobalPage.tasks).routeKey, 'daily_business');
  });

  test('Task templates stay migration-gated in this phase', () {
    expect(
      cloudReadinessForPage(GlobalPage.taskTemplates),
      CloudDestinationReadiness.migrationRequired,
    );
    expect(cloudReadPermissionForPage(GlobalPage.taskTemplates), 'task.read');
  });
}
