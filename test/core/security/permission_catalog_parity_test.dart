import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/security/rbac.dart';

/// PERMISSION-CATALOG-02: the client's typed vocabulary and the server's
/// enforced catalog must be the same truth.
///
/// The canonical list below mirrors, key for key, what the server seeds and
/// enforces (`supabase/migrations/*_permission_catalog.sql`, pinned again in
/// pgTAP 030). Every key except `reporting.generate` is enforced today by an
/// RLS policy or RPC gate through `private.has_workspace_permission`;
/// `reporting.generate` is the documented navigation-only gate awaiting its
/// server surface. Changing either side without the other fails here or in
/// pgTAP — never silently.
const List<String> canonicalServerCatalog = <String>[
  'workspace.read',
  'security.manage',
  'audit.read',
  'property.read',
  // PROPERTY-DATA-02 added the creation verb (create_property + the
  // admin/manager role bundle).
  'property.create',
  'property.update',
  'party.read',
  'party.manage',
  'document.read',
  'document.manage',
  'document.verify',
  'task.read',
  'task.manage',
  'notification.read',
  'notification.manage',
  'import.read',
  'import.manage',
  'search.read',
  'search.reindex',
  'lease.read',
  'lease.manage',
  'valuation.read',
  'valuation.manage',
  'valuation.approve',
  'maintenance.read',
  'maintenance.manage',
  'capex.read',
  'capex.manage',
  'capex.approve',
  'reporting.generate',
  // FINANCE-01a added the ledger foundation: three keys, because reading a
  // figure, booking one and declaring a period final differ in consequence.
  'finance.read',
  'finance.manage',
  'finance.close',
];

void main() {
  test('every canonical server key has a typed client representation', () {
    expect(
      Permission.serverCatalog,
      canonicalServerCatalog.toSet(),
      reason:
          'Permission.serverCatalog must carry exactly the keys the server '
          'seeds and enforces — one vocabulary, no drift.',
    );
    // The canonical subset is part of the general client vocabulary.
    expect(
      Permission.all.containsAll(Permission.serverCatalog),
      isTrue,
      reason: 'Every server-enforced key must be valid client vocabulary.',
    );
  });

  test('no client capability claims server granularity that does not exist',
      () {
    // The server enforces one task mutation capability: task.manage. The
    // legacy trio pretended a finer split the server never had.
    expect(
      Permission.all.intersection(const <String>{
        'task.create',
        'task.assign',
        'task.resolve',
      }),
      isEmpty,
      reason:
          'task.create/task.assign/task.resolve are not server capabilities; '
          'the real mutation capability is task.manage.',
    );
    expect(Permission.all, contains(Permission.taskManage));
  });

  test('the cloud surfaces gate on typed canonical keys', () {
    // The keys the cloud shell actually gates on (navigation, task center,
    // inbox, workspace host) must exist as typed constants inside the
    // canonical subset — no ad hoc strings claiming rights.
    for (final key in <String>{
      Permission.taskRead,
      Permission.taskManage,
      Permission.notificationRead,
      Permission.searchRead,
      Permission.securityManage,
      Permission.auditRead,
      Permission.propertyRead,
      Permission.leaseRead,
      Permission.partyRead,
      Permission.documentRead,
      Permission.importRead,
      Permission.valuationRead,
      Permission.workspaceRead,
      Permission.reportingGenerate,
    }) {
      expect(
        Permission.serverCatalog,
        contains(key),
        reason: '$key gates a cloud surface and must be canonical.',
      );
    }
  });
}
