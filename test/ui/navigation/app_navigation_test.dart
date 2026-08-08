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
    expect(cloudRouteTargetFromName('/')?.page, GlobalPage.dashboard);
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
