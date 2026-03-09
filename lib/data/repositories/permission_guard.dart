import '../../core/security/rbac.dart';

class PermissionDenied implements Exception {
  const PermissionDenied(this.message);

  final String message;

  @override
  String toString() => 'PermissionDenied: $message';
}

class PermissionGuard {
  const PermissionGuard(this._rbac);

  final Rbac _rbac;

  bool can({
    required String role,
    required RbacAction action,
    PermissionContext? context,
  }) {
    return _rbac.can(action: action, role: role, context: context);
  }

  bool canPermission({
    required String role,
    required String permission,
    PermissionContext? context,
  }) {
    return _rbac.canPermission(
      role: role,
      permission: permission,
      context: context,
    );
  }

  void ensure({
    required String role,
    required RbacAction action,
    required String message,
    PermissionContext? context,
  }) {
    if (!_rbac.can(action: action, role: role, context: context)) {
      throw PermissionDenied(message);
    }
  }

  void ensurePermission({
    required String role,
    required String permission,
    required String message,
    PermissionContext? context,
  }) {
    if (
        !_rbac.canPermission(
          role: role,
          permission: permission,
          context: context,
        )) {
      throw PermissionDenied(message);
    }
  }
}
