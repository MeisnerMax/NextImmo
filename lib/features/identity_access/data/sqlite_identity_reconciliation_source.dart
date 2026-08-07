import '../../../data/repositories/security_repo.dart';
import '../application/identity_reconciliation_report.dart';

/// Read-only source for the identity reconciliation report (P2-D01 step 7):
/// projects the local `SecurityRepo` users of a workspace onto
/// [IdentityReconciliationRecord]s and builds the deterministic report. It
/// never mutates the source and never creates cloud identities — it only
/// summarizes what a future identity migration would carry, mirroring the
/// read-only spirit of the P1-012 dry-run mapper for the identity domain.
class SqliteIdentityReconciliationSource {
  const SqliteIdentityReconciliationSource({required SecurityRepo securityRepo})
    : _securityRepo = securityRepo;

  final SecurityRepo _securityRepo;

  Future<IdentityReconciliationReport> buildReport({
    required String workspaceId,
  }) async {
    final users = await _securityRepo.listUsers(workspaceId);
    final records = users
        .map(
          (user) => IdentityReconciliationRecord(
            userId: user.id,
            role: user.role,
            displayName: user.displayName,
            email: user.email,
          ),
        )
        .toList(growable: false);
    return buildIdentityReconciliationReport(
      workspaceId: workspaceId,
      records: records,
    );
  }
}
