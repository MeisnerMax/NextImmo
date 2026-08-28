import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/navigation/app_navigation.dart';
import 'package:neximmo_app/ui/state/app_state.dart';

/// ADMIN-AREA-01 A1 / Foundation-AMD-001: the `adminUsers` destination is
/// renamed from "Benutzer" to "Mitglieder" while route, routeKey and the
/// permission mapping stay untouched.
void main() {
  test('adminUsers destination is labelled Mitglieder (AMD-001)', () {
    final destination = _adminUsersDestination();
    expect(destination.label, 'Mitglieder');
    expect(destination.title, 'Mitglieder');
  });

  test('adminUsers routeKey stays stable across the rename', () {
    final destination = _adminUsersDestination();
    expect(destination.routeKey, 'setup_administration.users');
  });

  test('adminUsers keeps its security.manage read permission', () {
    expect(
      cloudReadPermissionForPage(GlobalPage.adminUsers),
      'security.manage',
    );
    expect(
      isPageAllowedForPermissions(GlobalPage.adminUsers, const <String>{}),
      isFalse,
    );
    expect(
      isPageAllowedForPermissions(GlobalPage.adminUsers, const <String>{
        'security.manage',
      }),
      isTrue,
    );
  });

  test('/members still resolves to the adminUsers members surface', () {
    final target = cloudRouteTargetFromName(referenceMembersRoute);
    expect(target?.page, GlobalPage.adminUsers);
    expect(target?.surface, CloudRouteSurface.members);
  });
}

GlobalNavigationDestination _adminUsersDestination() {
  return appNavigationGroups
      .expand((group) => group.items)
      .singleWhere((destination) => destination.page == GlobalPage.adminUsers);
}
