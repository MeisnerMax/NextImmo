enum RbacAction {
  create,
  update,
  delete,
  import,
  export,
  backupRestore,
  settingsEdit,
  workspaceManage,
}

enum PermissionScopeType { global, workspace, property, portfolio, region }

class Permission {
  const Permission._();

  static const String propertyRead = 'property.read';
  static const String propertyCreate = 'property.create';
  static const String propertyUpdate = 'property.update';
  static const String propertyDelete = 'property.delete';
  static const String propertyExport = 'property.export';
  static const String scenarioRead = 'scenario.read';
  static const String scenarioCreate = 'scenario.create';
  static const String scenarioUpdate = 'scenario.update';
  static const String scenarioDelete = 'scenario.delete';
  static const String scenarioApprove = 'scenario.approve';
  static const String documentRead = 'document.read';
  static const String documentCreate = 'document.create';
  static const String documentUpdate = 'document.update';
  static const String documentDelete = 'document.delete';
  static const String documentVerify = 'document.verify';
  static const String taskRead = 'task.read';
  static const String taskCreate = 'task.create';
  static const String taskAssign = 'task.assign';
  static const String taskResolve = 'task.resolve';
  static const String auditRead = 'audit.read';
  static const String securityManage = 'security.manage';
  static const String settingsEdit = 'settings.edit';
  static const String importExecute = 'import.execute';
  static const String exportExecute = 'export.execute';
  static const String workspaceManage = 'workspace.manage';
  static const String operationsManage = 'operations.manage';
  static const String reportingGenerate = 'reporting.generate';
  static const String reportingApprove = 'reporting.approve';

  static const Set<String> all = <String>{
    propertyRead,
    propertyCreate,
    propertyUpdate,
    propertyDelete,
    propertyExport,
    scenarioRead,
    scenarioCreate,
    scenarioUpdate,
    scenarioDelete,
    scenarioApprove,
    documentRead,
    documentCreate,
    documentUpdate,
    documentDelete,
    documentVerify,
    taskRead,
    taskCreate,
    taskAssign,
    taskResolve,
    auditRead,
    securityManage,
    settingsEdit,
    importExecute,
    exportExecute,
    workspaceManage,
    operationsManage,
    reportingGenerate,
    reportingApprove,
  };
}

class PermissionContext {
  const PermissionContext({
    this.scopeType = PermissionScopeType.global,
    this.scopeId,
    this.workspaceId,
    this.propertyId,
    this.portfolioId,
    this.regionId,
  });

  final PermissionScopeType scopeType;
  final String? scopeId;
  final String? workspaceId;
  final String? propertyId;
  final String? portfolioId;
  final String? regionId;
}

class Rbac {
  const Rbac();

  bool can({
    required RbacAction action,
    required String role,
    PermissionContext? context,
  }) {
    return canPermission(
      role: role,
      permission: permissionForAction(action),
      context: context,
    );
  }

  bool canPermission({
    required String role,
    required String permission,
    PermissionContext? context,
  }) {
    if (!Permission.all.contains(permission.trim().toLowerCase())) {
      return false;
    }
    final permissions = permissionsForRole(role, context: context);
    return permissions.contains(permission.trim().toLowerCase());
  }

  Set<String> permissionsForRole(
    String role, {
    PermissionContext? context,
  }) {
    final normalizedRole = role.trim().toLowerCase();
    switch (normalizedRole) {
      case 'admin':
        return Permission.all;
      case 'manager':
        return _managerPermissions;
      case 'analyst':
        return _analystPermissions;
      case 'operations':
        return _operationsPermissions;
      case 'viewer':
        return _viewerPermissions;
      default:
        return const <String>{};
    }
  }

  static String permissionForAction(RbacAction action) {
    switch (action) {
      case RbacAction.create:
        return Permission.propertyCreate;
      case RbacAction.update:
        return Permission.propertyUpdate;
      case RbacAction.delete:
        return Permission.propertyDelete;
      case RbacAction.import:
        return Permission.importExecute;
      case RbacAction.export:
        return Permission.exportExecute;
      case RbacAction.backupRestore:
        return Permission.securityManage;
      case RbacAction.settingsEdit:
        return Permission.settingsEdit;
      case RbacAction.workspaceManage:
        return Permission.workspaceManage;
    }
  }

  static const Set<String> _managerPermissions = <String>{
    Permission.propertyRead,
    Permission.propertyCreate,
    Permission.propertyUpdate,
    Permission.propertyDelete,
    Permission.propertyExport,
    Permission.scenarioRead,
    Permission.scenarioCreate,
    Permission.scenarioUpdate,
    Permission.scenarioDelete,
    Permission.scenarioApprove,
    Permission.documentRead,
    Permission.documentCreate,
    Permission.documentUpdate,
    Permission.documentDelete,
    Permission.documentVerify,
    Permission.taskRead,
    Permission.taskCreate,
    Permission.taskAssign,
    Permission.taskResolve,
    Permission.auditRead,
    Permission.importExecute,
    Permission.exportExecute,
    Permission.workspaceManage,
    Permission.operationsManage,
    Permission.reportingGenerate,
    Permission.reportingApprove,
  };

  static const Set<String> _analystPermissions = <String>{
    Permission.propertyRead,
    Permission.propertyCreate,
    Permission.propertyUpdate,
    Permission.propertyExport,
    Permission.scenarioRead,
    Permission.scenarioCreate,
    Permission.scenarioUpdate,
    Permission.documentRead,
    Permission.documentCreate,
    Permission.documentUpdate,
    Permission.taskRead,
    Permission.taskCreate,
    Permission.taskResolve,
    Permission.auditRead,
    Permission.importExecute,
    Permission.exportExecute,
    Permission.reportingGenerate,
  };

  static const Set<String> _operationsPermissions = <String>{
    Permission.propertyRead,
    Permission.propertyUpdate,
    Permission.scenarioRead,
    Permission.documentRead,
    Permission.documentCreate,
    Permission.documentUpdate,
    Permission.taskRead,
    Permission.taskCreate,
    Permission.taskAssign,
    Permission.taskResolve,
    Permission.auditRead,
    Permission.exportExecute,
    Permission.operationsManage,
    Permission.reportingGenerate,
  };

  static const Set<String> _viewerPermissions = <String>{
    Permission.propertyRead,
    Permission.propertyExport,
    Permission.scenarioRead,
    Permission.documentRead,
    Permission.taskRead,
    Permission.auditRead,
    Permission.exportExecute,
    Permission.reportingGenerate,
  };
}
