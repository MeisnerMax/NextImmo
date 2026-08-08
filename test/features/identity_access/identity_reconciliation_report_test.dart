import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_reconciliation_report.dart';

void main() {
  group('buildIdentityReconciliationReport', () {
    IdentityReconciliationRecord record(
      String userId,
      String role, {
      String? email,
    }) {
      return IdentityReconciliationRecord(
        userId: userId,
        role: role,
        displayName: userId,
        email: email,
      );
    }

    test('summarizes counts, role distribution and missing emails', () {
      final report = buildIdentityReconciliationReport(
        workspaceId: 'workspace-a',
        records: <IdentityReconciliationRecord>[
          record('user-2', 'viewer'),
          record('user-1', 'admin', email: 'admin@example.test'),
          record('user-3', 'viewer', email: 'v@example.test'),
        ],
      );

      expect(report.totalUsers, 3);
      expect(report.roleCounts, <String, int>{'admin': 1, 'viewer': 2});
      expect(report.usersMissingEmail, 1);
      expect(report.isFullyProvisionable, isFalse);
    });

    test('is deterministic and order-independent', () {
      final a = buildIdentityReconciliationReport(
        workspaceId: 'workspace-a',
        records: <IdentityReconciliationRecord>[
          record('user-1', 'admin', email: 'a@example.test'),
          record('user-2', 'viewer', email: 'b@example.test'),
        ],
      );
      final b = buildIdentityReconciliationReport(
        workspaceId: 'workspace-a',
        records: <IdentityReconciliationRecord>[
          record('user-2', 'viewer', email: 'b@example.test'),
          record('user-1', 'admin', email: 'a@example.test'),
        ],
      );

      expect(a.checksum, b.checksum);
      expect(a.isFullyProvisionable, isTrue);
    });

    test('a different workspace yields a different checksum', () {
      final records = <IdentityReconciliationRecord>[
        record('user-1', 'admin', email: 'a@example.test'),
      ];
      final a = buildIdentityReconciliationReport(
        workspaceId: 'workspace-a',
        records: records,
      );
      final b = buildIdentityReconciliationReport(
        workspaceId: 'workspace-b',
        records: records,
      );

      expect(a.checksum, isNot(b.checksum));
    });
  });
}
