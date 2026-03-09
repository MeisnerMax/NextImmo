import '../../data/repositories/audit_log_repo.dart';
import '../models/audit_log.dart';
import '../models/security.dart';
import 'audit_service.dart';

typedef AuditContextResolver = Future<SecurityContextRecord> Function();

class AuditWriter {
  const AuditWriter(this._repo, this._contextResolver);

  final AuditLogRepo _repo;
  final AuditContextResolver _contextResolver;
  static const AuditService _auditService = AuditService();

  Future<AuditLogRecord> record({
    required String entityType,
    required String entityId,
    required String action,
    String? summary,
    String source = 'ui',
    String? parentEntityType,
    String? parentEntityId,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
    List<AuditDiffItem>? diffItems,
    String? correlationId,
    String? reason,
    bool isSystemEvent = false,
    int? occurredAt,
  }) async {
    final context = await _contextResolver();
    return _repo.recordEvent(
      entityType: entityType,
      entityId: entityId,
      action: action,
      workspaceId: context.workspace.id,
      actorUserId: context.user.id,
      actorRole: context.user.role,
      summary: summary,
      source: source,
      parentEntityType: parentEntityType,
      parentEntityId: parentEntityId,
      oldValues: oldValues,
      newValues: newValues,
      diffItems:
          diffItems ?? _buildDiff(oldValues: oldValues, newValues: newValues),
      correlationId: correlationId,
      reason: reason,
      isSystemEvent: isSystemEvent,
      occurredAt: occurredAt,
    );
  }

  List<AuditDiffItem> _buildDiff({
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
  }) {
    if (oldValues == null || newValues == null) {
      return const <AuditDiffItem>[];
    }
    return _auditService.buildDiff(oldValues, newValues);
  }
}
