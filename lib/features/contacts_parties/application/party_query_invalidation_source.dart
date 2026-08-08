/// Workspace-scoped realtime invalidation for the party read models
/// (P2-D02 step 6), following the P1-011 property realtime pattern.
library;

class PartyQueryInvalidation {
  const PartyQueryInvalidation({
    required this.workspaceId,
    required this.partyId,
  });

  const PartyQueryInvalidation.reconcile({required this.workspaceId})
    : partyId = null;

  final String workspaceId;
  final String? partyId;

  bool get isReconciliation => partyId == null;
}

abstract interface class PartyQueryInvalidationSource {
  Stream<PartyQueryInvalidation> watchWorkspace({required String workspaceId});
}
