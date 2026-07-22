import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Report-only reconciliation for identity migration (P2-D01 step 7).
///
/// The P1-012 dry-run *mapper* does not fit identity: local users have no
/// stable email for many rows and clients hold no service-role key, so
/// `auth.users` cannot be pre-created client-side. There is therefore no
/// deterministic UUIDv5 → Postgres-row mapping to emit. Instead this produces a
/// **read-only** reconciliation summary of the local identity data that would
/// migrate — counts, role distribution, and the rows that block automated
/// provisioning (missing email) — plus a deterministic checksum so the same
/// input always yields the same manifest. It never writes to the source and
/// never fabricates `auth.users` rows.
const _identityReconciliationHashDomain = 'neximmo.identity.reconcile.v1:';

/// One local identity row considered for migration. Backend-agnostic input so
/// the report logic never depends on the SQLite record type directly.
class IdentityReconciliationRecord {
  const IdentityReconciliationRecord({
    required this.userId,
    required this.role,
    required this.displayName,
    this.email,
  });

  final String userId;
  final String role;
  final String displayName;
  final String? email;

  bool get canProvisionAuthUser => email != null && email!.trim().isNotEmpty;
}

class IdentityReconciliationReport {
  const IdentityReconciliationReport({
    required this.workspaceId,
    required this.totalUsers,
    required this.roleCounts,
    required this.usersMissingEmail,
    required this.checksum,
  });

  final String workspaceId;
  final int totalUsers;

  /// Role key → member count, ordered by role key for determinism.
  final Map<String, int> roleCounts;

  /// Rows that cannot be auto-provisioned as `auth.users` (no email).
  final int usersMissingEmail;

  /// SHA-256 over the canonical, source-order-independent record set.
  final String checksum;

  /// True when every local user carries an email — the precondition for an
  /// automated identity migration once remote provisioning is authorized.
  bool get isFullyProvisionable => usersMissingEmail == 0;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': 'identity_reconciliation_report',
      'mode': 'report_only',
      'workspace_id': workspaceId,
      'total_users': totalUsers,
      'role_counts': roleCounts,
      'users_missing_email': usersMissingEmail,
      'is_fully_provisionable': isFullyProvisionable,
      'checksum': checksum,
    };
  }
}

/// Builds a deterministic, read-only reconciliation report for [records].
/// Records are canonicalized independent of source order, so re-running over
/// the same identity data reproduces the same [IdentityReconciliationReport].
IdentityReconciliationReport buildIdentityReconciliationReport({
  required String workspaceId,
  required List<IdentityReconciliationRecord> records,
}) {
  final sorted = <IdentityReconciliationRecord>[...records]
    ..sort((a, b) => a.userId.compareTo(b.userId));

  final roleCounts = <String, int>{};
  var usersMissingEmail = 0;
  for (final record in sorted) {
    roleCounts.update(record.role, (value) => value + 1, ifAbsent: () => 1);
    if (!record.canProvisionAuthUser) {
      usersMissingEmail++;
    }
  }
  final orderedRoleCounts = <String, int>{
    for (final key in roleCounts.keys.toList()..sort()) key: roleCounts[key]!,
  };

  final canonical = <String, Object?>{
    'domain': _identityReconciliationHashDomain,
    'workspace_id': workspaceId,
    'records': [
      for (final record in sorted)
        <String, Object?>{
          'user_id': record.userId,
          'role': record.role,
          'has_email': record.canProvisionAuthUser,
        },
    ],
  };
  final checksum = sha256
      .convert(
        utf8.encode('$_identityReconciliationHashDomain${jsonEncode(canonical)}'),
      )
      .toString();

  return IdentityReconciliationReport(
    workspaceId: workspaceId,
    totalUsers: sorted.length,
    roleCounts: orderedRoleCounts,
    usersMissingEmail: usersMissingEmail,
    checksum: checksum,
  );
}
