class EntitlementInvalidation {
  const EntitlementInvalidation({
    required this.userId,
    required this.workspaceId,
  });

  const EntitlementInvalidation.reconcile({required this.userId})
    : workspaceId = null;

  final String userId;
  final String? workspaceId;

  bool get isReconciliation => workspaceId == null;
}

abstract interface class EntitlementInvalidationSource {
  Stream<EntitlementInvalidation> watchUser({required String userId});
}
