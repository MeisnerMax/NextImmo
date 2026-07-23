/// Workspace-scoped realtime invalidation for the document read models
/// (P2-D03 step 6), following the P1-011 property and P2-D02 party pattern.
///
/// Coverage note, matching the migration: the signal is emitted for changes to
/// the document aggregate itself (content confirmation, verification, a new
/// version, supersede, archive). Link and requirement-rule changes do NOT emit
/// one — see `20260723110000_p2_d03_document_realtime.sql` for why, and P2-D04
/// for where cross-table invalidation belongs.
library;

class DocumentQueryInvalidation {
  const DocumentQueryInvalidation({
    required this.workspaceId,
    required this.documentId,
  });

  /// Emitted once the subscription is (re)established, so a listener refreshes
  /// whatever it missed while the channel was down instead of trusting a
  /// possibly stale cache.
  const DocumentQueryInvalidation.reconcile({required this.workspaceId})
    : documentId = null;

  final String workspaceId;
  final String? documentId;

  bool get isReconciliation => documentId == null;
}

abstract interface class DocumentQueryInvalidationSource {
  Stream<DocumentQueryInvalidation> watchWorkspace({
    required String workspaceId,
  });
}
