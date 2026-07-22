/// Backend-agnostic capability check: "may the current actor perform this
/// action in the resolved scope?".
///
/// Introduced with P2-D01 so the membership admin surface stops scattering ad
/// hoc permission-set lookups (`access.allows('security.manage')`) across
/// widgets. Guardrail 6 of the enterprise target architecture asks for
/// fine-grained capabilities aggregated into roles; this port is the seam
/// screens depend on. The app-wide sweep of every screen onto this port is
/// deliberately deferred to later waves — P2-D01 only introduces it and uses
/// it for the members console.
library;

abstract interface class AuthorizationPort {
  /// Whether the resolved actor holds [permission] in the current scope.
  /// Missing/unknown state must deny (fail closed).
  bool can(String permission);
}

/// [AuthorizationPort] backed by a resolved workspace permission set — the
/// capabilities aggregated from the actor's role for the selected workspace.
class PermissionSetAuthorizationPort implements AuthorizationPort {
  PermissionSetAuthorizationPort(Set<String> permissions)
    : _permissions = Set<String>.unmodifiable(permissions);

  /// A port that denies everything — the fail-closed default when no workspace
  /// access has been resolved yet.
  PermissionSetAuthorizationPort.denyAll() : _permissions = const <String>{};

  final Set<String> _permissions;

  @override
  bool can(String permission) => _permissions.contains(permission);
}
