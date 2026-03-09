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
  });
}
