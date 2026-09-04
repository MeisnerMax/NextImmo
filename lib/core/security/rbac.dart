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

  // Welle 5: the valuation engine is its own capability set, deliberately not
  // folded into scenario.* — reading a scenario and reading a market-value
  // opinion are different rights, and approving a valuation is final
  // (AGG-014), so it needs its own approval capability. The keys match the
  // permissions the P2-D07 RLS policies and RPCs check server-side.
  static const String valuationRead = 'valuation.read';
  static const String valuationManage = 'valuation.manage';
  static const String valuationApprove = 'valuation.approve';
  static const String documentRead = 'document.read';
  static const String documentCreate = 'document.create';
  static const String documentUpdate = 'document.update';
  static const String documentDelete = 'document.delete';
  static const String documentVerify = 'document.verify';
  static const String taskRead = 'task.read';

  // PERMISSION-CATALOG-02: the server enforces exactly ONE task mutation
  // capability. The former task.create/task.assign/task.resolve trio claimed
  // a granularity no RLS policy or RPC ever had and is deliberately gone.
  static const String taskManage = 'task.manage';
  static const String auditRead = 'audit.read';
  static const String securityManage = 'security.manage';
  static const String settingsEdit = 'settings.edit';
  static const String importExecute = 'import.execute';
  static const String exportExecute = 'export.execute';
  static const String workspaceManage = 'workspace.manage';
  static const String operationsManage = 'operations.manage';
  static const String reportingGenerate = 'reporting.generate';
  static const String reportingApprove = 'reporting.approve';

  // PERMISSION-CATALOG-02: typed representations of the remaining server
  // capabilities, so no cloud surface gates on an ad hoc string.
  static const String workspaceRead = 'workspace.read';
  static const String partyRead = 'party.read';
  static const String partyManage = 'party.manage';
  static const String documentManage = 'document.manage';
  static const String notificationRead = 'notification.read';
  static const String notificationManage = 'notification.manage';
  static const String importRead = 'import.read';
  static const String importManage = 'import.manage';
  static const String searchRead = 'search.read';
  static const String searchReindex = 'search.reindex';
  static const String leaseRead = 'lease.read';
  static const String leaseManage = 'lease.manage';
  static const String maintenanceRead = 'maintenance.read';
  static const String maintenanceManage = 'maintenance.manage';
  static const String capexRead = 'capex.read';
  static const String capexManage = 'capex.manage';
  static const String capexApprove = 'capex.approve';

  /// The canonical server catalog (PERMISSION-CATALOG-02): exactly the keys
  /// the permission-catalog migration seeds, pinned key for key by
  /// `permission_catalog_parity_test.dart` on this side and by pgTAP 030 on
  /// the server side. Every key except [reportingGenerate] is enforced today
  /// through `private.has_workspace_permission`; `reporting.generate` is the
  /// documented navigation-only gate awaiting its server surface.
  static const Set<String> serverCatalog = <String>{
    workspaceRead,
    securityManage,
    auditRead,
    propertyRead,
    propertyUpdate,
    partyRead,
    partyManage,
    documentRead,
    documentManage,
    documentVerify,
    taskRead,
    taskManage,
    notificationRead,
    notificationManage,
    importRead,
    importManage,
    searchRead,
    searchReindex,
    leaseRead,
    leaseManage,
    valuationRead,
    valuationManage,
    valuationApprove,
    maintenanceRead,
    maintenanceManage,
    capexRead,
    capexManage,
    capexApprove,
    reportingGenerate,
  };

  /// The complete client vocabulary: the canonical server catalog plus the
  /// legacy-only keys the not-yet-migrated local screens still gate on. The
  /// legacy keys claim no server enforcement — the cloud surfaces use only
  /// [serverCatalog] members.
  static const Set<String> all = <String>{
    ...serverCatalog,
    propertyCreate,
    propertyDelete,
    propertyExport,
    scenarioRead,
    scenarioCreate,
    scenarioUpdate,
    scenarioDelete,
    scenarioApprove,
    documentCreate,
    documentUpdate,
    documentDelete,
    settingsEdit,
    importExecute,
    exportExecute,
    workspaceManage,
    operationsManage,
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
      case 'administrator':
        return Permission.all;
      case 'manager':
      case 'asset_manager':
        return _managerPermissions;
      case 'analyst':
      case 'buchhaltung':
        return _analystPermissions;
      case 'operations':
      case 'hausmeister':
      case 'bauleiter':
      case 'bauarbeiter':
      case 'housekeeping':
      case 'externer_dienstleister':
        return _operationsPermissions;
      case 'vermietung':
      case 'buerokraft':
        return _lettingPermissions;
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
    Permission.valuationRead,
    Permission.valuationManage,
    Permission.valuationApprove,
    Permission.documentRead,
    Permission.documentCreate,
    Permission.documentUpdate,
    Permission.documentDelete,
    Permission.documentVerify,
    Permission.taskRead,
    Permission.taskManage,
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
    // An analyst builds valuations but does not release them — the same split
    // the role already has for scenario.update vs. scenario.approve.
    Permission.valuationRead,
    Permission.valuationManage,
    Permission.documentRead,
    Permission.documentCreate,
    Permission.documentUpdate,
    Permission.taskRead,
    Permission.taskManage,
    Permission.auditRead,
    Permission.importExecute,
    Permission.exportExecute,
    Permission.reportingGenerate,
  };

  static const Set<String> _operationsPermissions = <String>{
    Permission.propertyRead,
    Permission.propertyUpdate,
    Permission.scenarioRead,
    // Reading a valuation, not building one — same shape as scenario access.
    Permission.valuationRead,
    Permission.documentRead,
    Permission.documentCreate,
    Permission.documentUpdate,
    Permission.taskRead,
    Permission.taskManage,
    Permission.auditRead,
    Permission.exportExecute,
    Permission.operationsManage,
    Permission.reportingGenerate,
  };

  static const Set<String> _lettingPermissions = <String>{
    Permission.propertyRead,
    Permission.propertyUpdate,
    Permission.scenarioRead,
    Permission.valuationRead,
    Permission.documentRead,
    Permission.documentCreate,
    Permission.documentUpdate,
    Permission.taskRead,
    Permission.taskManage,
    Permission.auditRead,
    Permission.exportExecute,
    Permission.operationsManage,
    Permission.reportingGenerate,
  };

  static const Set<String> _viewerPermissions = <String>{
    Permission.propertyRead,
    Permission.propertyExport,
    Permission.scenarioRead,
    Permission.valuationRead,
    Permission.documentRead,
    Permission.taskRead,
    Permission.auditRead,
    Permission.exportExecute,
    Permission.reportingGenerate,
  };
}
