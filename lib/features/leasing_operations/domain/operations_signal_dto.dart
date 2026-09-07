/// Domain shape for P2-D05a `operations_signals` — the server-computed
/// operational alerts and data-quality signals (Wave 3, Befund 1 + 3 in
/// `04c_wave3_leasing_operations.md`).
///
/// [type], [severity] and [status] are deliberately plain strings, not enums:
/// the legacy `OperationsAlertRecord`/`OperationsDataQualityIssue` already use
/// this exact vocabulary (`'critical'`/`'warning'`/`'info'`,
/// `'open'`/`'dismissed'`/`'resolved'`), and the legacy adapter maps its
/// output onto this DTO close to 1:1. Closing the type down to an enum here
/// would force a translation layer that the parity test (comparing the legacy
/// engine's output to this DTO) would then have to see through.
library;

class OperationsSignalDto {
  const OperationsSignalDto({
    required this.signalKey,
    required this.type,
    required this.severity,
    required this.message,
    required this.recommendedAction,
    required this.propertyId,
    this.propertyName,
    this.unitId,
    this.leaseId,
    this.tenantPartyId,
    required this.status,
    this.resolutionNote,
    this.statusVersion,
    this.statusUpdatedAt,
  });

  /// Stable identity: `type` + entity ids, never the message text (Befund 1,
  /// point 2). Two signals never share a key.
  final String signalKey;
  final String type;
  final String severity;
  final String message;
  final String recommendedAction;
  final String propertyId;

  /// The property's name, present only on the workspace-wide read
  /// (`ALERT-READER-01`). Null on the property-scoped read, where the screen
  /// already knows which building it is looking at -- and a workspace list
  /// without it is unusable, because "Lease 4B expires in 12 days" says
  /// nothing when forty buildings are in scope.
  final String? propertyName;

  final String? unitId;
  final String? leaseId;
  final String? tenantPartyId;

  /// `'open'` when no acknowledgement exists yet.
  final String status;
  final String? resolutionNote;

  /// Null exactly when [status] is the unacknowledged default — there is no
  /// row to version yet. Pass `null` as `expectedVersion` on the first
  /// [UpdateOperationsSignalStatusCommand] for this signal.
  final int? statusVersion;
  final DateTime? statusUpdatedAt;
}

/// The persisted acknowledgement row itself, returned by a successful
/// [UpdateOperationsSignalStatusCommand].
class OperationsSignalStateDto {
  const OperationsSignalStateDto({
    required this.id,
    required this.workspaceId,
    required this.propertyId,
    required this.signalType,
    this.unitId,
    this.leaseId,
    this.tenantPartyId,
    required this.signalKey,
    required this.status,
    this.resolutionNote,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  final String id;
  final String workspaceId;
  final String propertyId;
  final String signalType;
  final String? unitId;
  final String? leaseId;
  final String? tenantPartyId;
  final String signalKey;
  final String status;
  final String? resolutionNote;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;
}

/// The whole workspace's signals in one answer (`ALERT-READER-01`, P-10).
///
/// Capped rather than paged, and the cap is stated. The signal set is computed
/// at read time rather than stored, so a cursor would page over a moving
/// target: a lease renewed between two pages shifts every later signal, and
/// the reader would skip or repeat entries with no way to tell.
class WorkspaceOperationsSignalsDto {
  const WorkspaceOperationsSignalsDto({
    required this.computedAt,
    required this.signals,
    required this.total,
    required this.truncated,
    required this.limit,
    this.totalBySeverity = const <String, int>{},
  });

  /// When the server judged the deadlines. There is no scheduler, so this is
  /// the only thing that says how fresh the answer is.
  final DateTime computedAt;

  /// Severity first, then by property so one building reads together.
  final List<OperationsSignalDto> signals;

  /// How many matched, which is not how many came back. Counted before the
  /// cap, so it describes what exists rather than what fitted.
  final int total;

  final bool truncated;
  final int limit;

  /// Counts per severity over the matched set, also before the cap. A summary
  /// of the visible page would be a summary of nothing.
  final Map<String, int> totalBySeverity;

  int get criticalCount => totalBySeverity['critical'] ?? 0;
  int get warningCount => totalBySeverity['warning'] ?? 0;
  int get infoCount => totalBySeverity['info'] ?? 0;
}
