import '../../../core/models/property.dart';
import '../../../data/repositories/property_repo.dart' as legacy;
import '../application/property_repository.dart';
import '../domain/property_dto.dart';

class LegacySqlitePropertyRepositoryAdapter implements PropertyRepository {
  LegacySqlitePropertyRepositoryAdapter({
    required legacy.PropertyRepository legacyRepository,
    required String legacyWorkspaceId,
    this.legacyActorId = 'legacy-local',
  }) : _legacyRepository = legacyRepository,
       _legacyWorkspaceId = legacyWorkspaceId;

  static const int unsupportedVersion = 0;

  final legacy.PropertyRepository _legacyRepository;
  final String _legacyWorkspaceId;
  final String legacyActorId;

  @override
  Future<PropertyRepositoryResult<PropertyPageResult>> list(
    PropertyListQuery query,
  ) async {
    final scopeFailure = _scopeFailure<PropertyPageResult>(query.workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final records = await _legacyRepository.list(
        includeArchived: query.includeArchived,
      );
      var start = 0;
      final cursor = query.page.cursor;
      if (cursor != null) {
        final cursorIndex = records.indexWhere((record) => record.id == cursor);
        if (cursorIndex < 0) {
          return const PropertyRepositoryFailure<PropertyPageResult>(
            kind: PropertyRepositoryFailureKind.validationFailed,
            message: 'Legacy property cursor is invalid.',
          );
        }
        start = cursorIndex + 1;
      }

      final end = (start + query.page.limit).clamp(0, records.length);
      final pageRecords = records.sublist(start, end);
      return PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(
          items: pageRecords.map(_mapProperty).toList(growable: false),
          nextCursor:
              end < records.length && pageRecords.isNotEmpty
                  ? pageRecords.last.id
                  : null,
        ),
      );
    } catch (_) {
      return const PropertyRepositoryFailure<PropertyPageResult>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'Legacy SQLite properties could not be loaded.',
      );
    }
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> getById({
    required String workspaceId,
    required String propertyId,
  }) async {
    final scopeFailure = _scopeFailure<PropertyDto>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final record = await _legacyRepository.getById(propertyId);
      if (record == null) {
        return const PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.notFound,
          message: 'Property not found.',
        );
      }
      return PropertyRepositorySuccess<PropertyDto>(_mapProperty(record));
    } catch (_) {
      return const PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'Legacy SQLite property could not be loaded.',
      );
    }
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> update(
    PropertyUpdateCommand command,
  ) async {
    final scopeFailure = _scopeFailure<PropertyDto>(
      command.context.workspaceId,
    );
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final record = await _legacyRepository.getById(command.propertyId);
      if (record == null) {
        return const PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.notFound,
          message: 'Property not found.',
        );
      }
    } catch (_) {
      return const PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'Legacy SQLite property could not be loaded.',
      );
    }

    return const PropertyRepositoryFailure<PropertyDto>(
      kind: PropertyRepositoryFailureKind.dependencyConflict,
      message:
          'Legacy SQLite property updates are blocked: the schema has no '
          'durable version or unique mutation id.',
    );
  }

  PropertyRepositoryFailure<T>? _scopeFailure<T>(String workspaceId) {
    if (workspaceId == _legacyWorkspaceId) {
      return null;
    }
    return PropertyRepositoryFailure<T>(
      kind: PropertyRepositoryFailureKind.forbidden,
      message: 'The legacy SQLite database is bound to another workspace.',
    );
  }

  PropertyDto _mapProperty(PropertyRecord record) {
    return PropertyDto(
      id: record.id,
      workspaceId: _legacyWorkspaceId,
      name: record.name,
      addressLine1: record.addressLine1,
      addressLine2: record.addressLine2,
      zip: record.zip,
      city: record.city,
      country: record.country,
      propertyType: record.propertyType,
      units: record.units,
      sqft: record.sqft,
      yearBuilt: record.yearBuilt,
      notes: record.notes,
      status: record.archived ? PropertyStatus.archived : PropertyStatus.active,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        record.createdAt,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        record.updatedAt,
        isUtc: true,
      ),
      createdBy: legacyActorId,
      updatedBy: legacyActorId,
      version: unsupportedVersion,
    );
  }
}
