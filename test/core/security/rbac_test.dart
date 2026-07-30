import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/security/rbac.dart';

void main() {
  test('rbac matrix covers enterprise roles and fine grained permissions', () {
    const rbac = Rbac();

    expect(
      rbac.canPermission(role: 'viewer', permission: Permission.scenarioRead),
      isTrue,
    );
    expect(
      rbac.canPermission(role: 'viewer', permission: Permission.scenarioCreate),
      isFalse,
    );
    expect(
      rbac.canPermission(role: 'viewer', permission: Permission.auditRead),
      isTrue,
    );

    expect(
      rbac.canPermission(role: 'analyst', permission: Permission.scenarioUpdate),
      isTrue,
    );
    expect(
      rbac.canPermission(role: 'analyst', permission: Permission.scenarioApprove),
      isFalse,
    );
    expect(
      rbac.canPermission(role: 'analyst', permission: Permission.importExecute),
      isTrue,
    );

    expect(
      rbac.canPermission(role: 'manager', permission: Permission.scenarioApprove),
      isTrue,
    );
    expect(
      rbac.canPermission(role: 'manager', permission: Permission.securityManage),
      isFalse,
    );

    expect(
      rbac.canPermission(
        role: 'operations',
        permission: Permission.operationsManage,
      ),
      isTrue,
    );
    expect(
      rbac.canPermission(role: 'operations', permission: Permission.scenarioCreate),
      isFalse,
    );

    expect(rbac.can(action: RbacAction.workspaceManage, role: 'admin'), isTrue);
    expect(
      rbac.canPermission(role: 'admin', permission: Permission.securityManage),
      isTrue,
    );
    expect(
      rbac.canPermission(
        role: 'unknown',
        permission: Permission.propertyRead,
      ),
      isFalse,
    );
  });

  test('every scenario reader can read valuations', () {
    const rbac = Rbac();

    // The valuation screens gate on valuation.read. A role that may look at a
    // scenario but not at its valuation would see "kein Zugriff" on the
    // Wertermittlung tab — the gap this locks shut.
    for (final role in const <String>[
      'viewer',
      'analyst',
      'manager',
      'operations',
      'letting',
      'admin',
    ]) {
      expect(
        rbac.canPermission(role: role, permission: Permission.scenarioRead) &&
            !rbac.canPermission(
              role: role,
              permission: Permission.valuationRead,
            ),
        isFalse,
        reason: '$role darf Szenarien lesen, aber keine Bewertung',
      );
    }
  });

  test('building a valuation and releasing it are separate rights', () {
    const rbac = Rbac();

    expect(
      rbac.canPermission(role: 'analyst', permission: Permission.valuationManage),
      isTrue,
    );
    expect(
      rbac.canPermission(
        role: 'analyst',
        permission: Permission.valuationApprove,
      ),
      isFalse,
    );
    expect(
      rbac.canPermission(
        role: 'manager',
        permission: Permission.valuationApprove,
      ),
      isTrue,
    );
    expect(
      rbac.canPermission(role: 'viewer', permission: Permission.valuationManage),
      isFalse,
    );
  });
}
