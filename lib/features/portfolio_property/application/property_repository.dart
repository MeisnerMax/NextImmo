import '../domain/property_dto.dart';

class CommandContext {
  const CommandContext({
    required this.workspaceId,
    required this.actorId,
    required this.mutationId,
    required this.expectedVersion,
    required this.correlationId,
    this.reason,
  });

  final String workspaceId;
  final String actorId;
  final String mutationId;
  final int expectedVersion;
  final String correlationId;
  final String? reason;
}

class PropertyPageRequest {
  const PropertyPageRequest({this.limit = 50, this.cursor})
    : assert(limit > 0 && limit <= 100);

  final int limit;
  final String? cursor;
}

class PropertyListQuery {
  const PropertyListQuery({
    required this.workspaceId,
    this.page = const PropertyPageRequest(),
    this.includeArchived = false,
  });

  final String workspaceId;
  final PropertyPageRequest page;
  final bool includeArchived;
}

class PropertyPageResult {
  const PropertyPageResult({required this.items, this.nextCursor});

  final List<PropertySummaryDto> items;
  final String? nextCursor;
}

class PropertyUpdateCommand {
  const PropertyUpdateCommand({
    required this.propertyId,
    required this.context,
    required this.changes,
  });

  final String propertyId;
  final CommandContext context;
  final PropertyUpdateDto changes;
}

enum PropertyRepositoryFailureKind {
  notFound,
  forbidden,
  validationFailed,
  versionConflict,
  mutationConflict,
  mutationInProgress,
  dependencyConflict,
  infrastructureFailure,
}

class PropertyVersionConflict {
  const PropertyVersionConflict({
    required this.expectedVersion,
    required this.actualVersion,
    required this.currentProperty,
  });

  final int expectedVersion;
  final int actualVersion;
  final PropertyDto currentProperty;
}

sealed class PropertyRepositoryResult<T> {
  const PropertyRepositoryResult();
}

class PropertyRepositorySuccess<T> extends PropertyRepositoryResult<T> {
  const PropertyRepositorySuccess(this.value);

  final T value;
}

class PropertyRepositoryFailure<T> extends PropertyRepositoryResult<T> {
  const PropertyRepositoryFailure({
    required this.kind,
    required this.message,
    this.versionConflict,
  }) : assert(
         kind == PropertyRepositoryFailureKind.versionConflict
             ? versionConflict != null
             : versionConflict == null,
       );

  final PropertyRepositoryFailureKind kind;
  final String message;
  final PropertyVersionConflict? versionConflict;
}

/// Backend-agnostic property contract.
///
/// The property tombstone (DEBT-012) is expressed through the archived status,
/// not a dedicated delete verb: `update` with [PropertyStatus.archived] is the
/// restorable soft-delete (it sets the `deleted_at`/`deleted_by` marker, keeps
/// the row and its children, is hidden from active reads, and is audited
/// append-only), and `update` back to [PropertyStatus.active] is the restore.
/// Active reads exclude tombstoned rows by the marker; pass
/// [PropertyListQuery.includeArchived] to surface them for the archive view.
abstract interface class PropertyRepository {
  Future<PropertyRepositoryResult<PropertyPageResult>> list(
    PropertyListQuery query,
  );

  Future<PropertyRepositoryResult<PropertyDto>> getById({
    required String workspaceId,
    required String propertyId,
  });

  Future<PropertyRepositoryResult<PropertyDto>> update(
    PropertyUpdateCommand command,
  );
}
