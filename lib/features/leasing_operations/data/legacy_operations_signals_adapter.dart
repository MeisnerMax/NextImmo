/// Legacy SQLite projection of P2-D05a `operations_signals` onto the
/// canonical contract.
///
/// Unlike the other four legacy leasing adapters, this one does not re-derive
/// anything from raw records: `OperationsRepo` / `OperationsDataQualityEngine`
/// already compute the full legacy alert + data-quality signal set for SQLite
/// mode, and keep doing so — Befund 1 in `04c_wave3_leasing_operations.md`
/// decided the derivation moves server-side for the *cloud* schema, not that
/// the legacy engine is retired. This adapter is a thin projection of that
/// existing output onto [OperationsSignalDto], plus write-through to the
/// existing `operations_alert_states` table.
///
/// [OperationsSignalDto.signalKey] here is whatever `OperationsRepo` already
/// computes (`OperationsAlertRecord.id`, i.e. `_buildAlertId` — a
/// message-text-derived id). That is the exact fragility Befund 1 named for
/// the legacy engine and deliberately did not carry into the Postgres side;
/// it is left as-is here, matching "the legacy engine keeps running unchanged"
/// (RISK-QA-001 is accepted, not silently fixed by rewriting the local store).
///
/// Because the legacy store carries no optimistic-concurrency token, an
/// acknowledged signal reports `statusVersion == 1` and an unacknowledged one
/// `null` — not a real version, only "has this been acknowledged before".
/// [UpdateOperationsSignalStatusCommand.expectedVersion] must therefore be
/// `null`; any other value is refused as `mutationConflict` because there is
/// nothing here to compare it against.
library;

import '../../../core/models/operations.dart';
import '../../../data/repositories/operations_repo.dart';
import '../application/operations_signals_contract.dart';
import '../domain/operations_signal_dto.dart';

class LegacySqliteOperationsSignalsAdapter implements OperationsSignalsPort {
  const LegacySqliteOperationsSignalsAdapter({
    required OperationsRepo repo,
    required this.legacyWorkspaceId,
  }) : _repo = repo;

  final OperationsRepo _repo;
  final String legacyWorkspaceId;

  @override
  Future<OperationsSignalsResult<List<OperationsSignalDto>>> list(
    OperationsSignalsQuery query,
  ) async {
    if (legacyWorkspaceId.isEmpty || query.workspaceId != legacyWorkspaceId) {
      return const OperationsSignalsFailure<List<OperationsSignalDto>>(
        kind: OperationsSignalsFailureKind.forbidden,
        message: 'Operations signals are not available for this workspace.',
      );
    }
    try {
      final alerts = await _repo.loadAlerts(query.propertyId);
      return OperationsSignalsSuccess<List<OperationsSignalDto>>(
        alerts
            .map((alert) => _toSignal(alert, query.propertyId))
            .toList(growable: false),
      );
    } catch (_) {
      return const OperationsSignalsFailure<List<OperationsSignalDto>>(
        kind: OperationsSignalsFailureKind.infrastructureFailure,
        message: 'Legacy operations signals could not be loaded.',
      );
    }
  }

  @override
  Future<OperationsSignalsResult<OperationsSignalStateDto>> updateStatus(
    UpdateOperationsSignalStatusCommand command,
  ) async {
    if (legacyWorkspaceId.isEmpty ||
        command.context.workspaceId != legacyWorkspaceId) {
      return const OperationsSignalsFailure<OperationsSignalStateDto>(
        kind: OperationsSignalsFailureKind.forbidden,
        message: 'Operations signals are not available for this workspace.',
      );
    }
    if (command.expectedVersion != null) {
      return const OperationsSignalsFailure<OperationsSignalStateDto>(
        kind: OperationsSignalsFailureKind.mutationConflict,
        message:
            'Legacy acknowledgements carry no version to compare against.',
      );
    }
    try {
      await _repo.updateAlertStatus(
        alertId: command.signalKey,
        propertyId: command.propertyId,
        status: command.status,
        resolutionNote: command.resolutionNote,
      );
      final now = DateTime.now();
      return OperationsSignalsSuccess<OperationsSignalStateDto>(
        OperationsSignalStateDto(
          id: command.signalKey,
          workspaceId: command.context.workspaceId,
          propertyId: command.propertyId,
          signalType: command.signalType,
          unitId: command.unitId,
          leaseId: command.leaseId,
          tenantPartyId: command.tenantPartyId,
          signalKey: command.signalKey,
          status: command.status,
          resolutionNote: command.resolutionNote,
          version: 1,
          createdAt: now,
          updatedAt: now,
          createdBy: command.context.actorId,
          updatedBy: command.context.actorId,
        ),
      );
    } catch (_) {
      return const OperationsSignalsFailure<OperationsSignalStateDto>(
        kind: OperationsSignalsFailureKind.infrastructureFailure,
        message: 'Legacy operations signal acknowledgement failed.',
      );
    }
  }

  OperationsSignalDto _toSignal(
    OperationsAlertRecord alert,
    String propertyId,
  ) {
    final createdAt = alert.createdAt;
    return OperationsSignalDto(
      signalKey:
          alert.id ??
          _fallbackKey(alert.type, alert.unitId, alert.leaseId, alert.tenantId),
      type: alert.type,
      severity: alert.severity,
      message: alert.message,
      recommendedAction: alert.recommendedAction ?? '',
      propertyId: propertyId,
      unitId: alert.unitId,
      leaseId: alert.leaseId,
      tenantPartyId: alert.tenantId,
      status: alert.status,
      resolutionNote: alert.resolutionNote,
      statusVersion: alert.status == 'open' ? null : 1,
      statusUpdatedAt: createdAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdAt),
    );
  }

  /// `OperationsRepo.loadAlerts` always sets an id, so this only guards a
  /// future change to that contract from producing a null key silently.
  String _fallbackKey(
    String type,
    String? unitId,
    String? leaseId,
    String? tenantId,
  ) {
    return <String>[
      type,
      unitId ?? '-',
      leaseId ?? '-',
      tenantId ?? '-',
    ].join(':');
  }
}
