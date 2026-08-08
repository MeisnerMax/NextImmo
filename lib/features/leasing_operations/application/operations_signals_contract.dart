/// Backend-agnostic contract for P2-D05a `operations_signals` — a read
/// (compute + list) and a write (acknowledge) on top of the P2-D05
/// leasing_operations aggregates, kept in its own file/result hierarchy rather
/// than folded into [LeasingRepositoryResult] because a signal is not a fifth
/// leasing aggregate: it has no create/update/transition triple of its own,
/// only "read the computed list" and "acknowledge one entry". Reuses
/// [LeasingCommandContext] rather than duplicating it — same actor/mutation/
/// correlation/reason shape as every other P2-D05 command.
library;

import '../domain/operations_signal_dto.dart';
import 'leasing_repository.dart';

export 'leasing_repository.dart' show LeasingCommandContext;

class OperationsSignalsQuery {
  const OperationsSignalsQuery({
    required this.workspaceId,
    required this.propertyId,
  });

  final String workspaceId;
  final String propertyId;
}

/// [expectedVersion] is `null` exactly when acknowledging a signal that has no
/// acknowledgement row yet ([OperationsSignalDto.statusVersion] was `null`);
/// passing a version there is rejected as `versionConflict`, matching
/// `update_operations_signal_status`'s "does not exist yet" case.
///
/// [signalKey] is the value read off the [OperationsSignalDto] being
/// acknowledged. The Supabase adapter ignores it — the server recomputes the
/// key from [signalType]/[unitId]/[leaseId]/[tenantPartyId] itself rather than
/// trusting a client-supplied string, same reasoning as the RPC's own header
/// note. The legacy adapter needs it verbatim: the local engine's alert ids
/// are message-text-derived (the exact fragility Befund 1 named and did not
/// port), so only the id the caller actually read back can look the row up.
class UpdateOperationsSignalStatusCommand {
  const UpdateOperationsSignalStatusCommand({
    required this.context,
    required this.propertyId,
    required this.signalType,
    required this.signalKey,
    required this.status,
    this.unitId,
    this.leaseId,
    this.tenantPartyId,
    this.expectedVersion,
    this.resolutionNote,
  });

  final LeasingCommandContext context;
  final String propertyId;
  final String signalType;
  final String signalKey;
  final String status;
  final String? unitId;
  final String? leaseId;
  final String? tenantPartyId;
  final int? expectedVersion;
  final String? resolutionNote;
}

enum OperationsSignalsFailureKind {
  notFound,
  forbidden,
  validationFailed,
  versionConflict,
  mutationConflict,
  mutationInProgress,
  infrastructureFailure,
}

/// [actualVersion] and [currentState] are both null exactly when the conflict
/// is "an acknowledgement was expected not to exist yet, but does" without the
/// caller having supplied a version to fail against.
class OperationsSignalVersionConflict {
  const OperationsSignalVersionConflict({
    required this.expectedVersion,
    this.actualVersion,
    this.currentState,
  });

  final int? expectedVersion;
  final int? actualVersion;
  final OperationsSignalStateDto? currentState;
}

sealed class OperationsSignalsResult<T> {
  const OperationsSignalsResult();
}

class OperationsSignalsSuccess<T> extends OperationsSignalsResult<T> {
  const OperationsSignalsSuccess(this.value);

  final T value;
}

class OperationsSignalsFailure<T> extends OperationsSignalsResult<T> {
  const OperationsSignalsFailure({
    required this.kind,
    required this.message,
    this.versionConflict,
  }) : assert(
         kind == OperationsSignalsFailureKind.versionConflict
             ? versionConflict != null
             : versionConflict == null,
       );

  final OperationsSignalsFailureKind kind;
  final String message;
  final OperationsSignalVersionConflict? versionConflict;
}

abstract interface class OperationsSignalsPort {
  Future<OperationsSignalsResult<List<OperationsSignalDto>>> list(
    OperationsSignalsQuery query,
  );

  Future<OperationsSignalsResult<OperationsSignalStateDto>> updateStatus(
    UpdateOperationsSignalStatusCommand command,
  );
}
