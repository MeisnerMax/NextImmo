/// The resolved "who is acting, where, with what rights" seam every
/// backend-selected screen needs before it can call a feature contract.
///
/// Introduced with Wave 2: the contracts take `workspaceId`/`actorId` on every
/// command, but the two hosts resolve them differently — locally from the
/// SQLite security context, in cloud mode from the authenticated reference
/// session. The composition root (`lib/app_backend_wiring.dart`) binds
/// [workspaceSessionScopeProvider] per `DataBackend`; screens depend on this
/// seam instead of learning which host they run in.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'authorization_port.dart';

class WorkspaceSessionScope {
  WorkspaceSessionScope({
    required this.workspaceId,
    required this.actorId,
    required Set<String> permissions,
    required this.mutationsSupported,
  }) : permissions = Set<String>.unmodifiable(permissions);

  /// Fail-closed default: no workspace, no actor, no rights, no mutations.
  const WorkspaceSessionScope.unresolved()
    : workspaceId = null,
      actorId = null,
      permissions = const <String>{},
      mutationsSupported = false;

  final String? workspaceId;
  final String? actorId;
  final Set<String> permissions;

  /// False while the bound backend cannot honour the audited, versioned,
  /// idempotent command envelope — today the read-only legacy SQLite adapters.
  /// Screens render the mandatory "read-only until migrated" state instead of
  /// firing a mutation that is certain to fail.
  final bool mutationsSupported;

  bool get isResolved => workspaceId != null && actorId != null;

  AuthorizationPort get authorization =>
      PermissionSetAuthorizationPort(permissions);

  @override
  bool operator ==(Object other) {
    return other is WorkspaceSessionScope &&
        other.workspaceId == workspaceId &&
        other.actorId == actorId &&
        other.mutationsSupported == mutationsSupported &&
        other.permissions.length == permissions.length &&
        other.permissions.containsAll(permissions);
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    actorId,
    mutationsSupported,
    Object.hashAllUnordered(permissions),
  );
}

final workspaceSessionScopeProvider = Provider<WorkspaceSessionScope>(
  (ref) => const WorkspaceSessionScope.unresolved(),
);
