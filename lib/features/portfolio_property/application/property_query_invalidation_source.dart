class PropertyQueryInvalidation {
  const PropertyQueryInvalidation({
    required this.workspaceId,
    required this.propertyId,
  });

  const PropertyQueryInvalidation.reconcile({required this.workspaceId})
    : propertyId = null;

  final String workspaceId;
  final String? propertyId;

  bool get isReconciliation => propertyId == null;
}

abstract interface class PropertyQueryInvalidationSource {
  Stream<PropertyQueryInvalidation> watchWorkspace({
    required String workspaceId,
  });
}
