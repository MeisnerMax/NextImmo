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
