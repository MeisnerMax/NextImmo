import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';

void main() {
  group('PropertyRepository contract', () {
    late _ContractRepository repository;

    setUp(() {
      repository = _ContractRepository(<PropertyDto>[
        _property(id: 'property-a', workspaceId: 'workspace-a'),
        _property(id: 'property-b', workspaceId: 'workspace-b'),
      ]);
    });

    test('scopes list and detail reads to the workspace', () async {
      final listResult = await repository.list(
        const PropertyListQuery(workspaceId: 'workspace-a'),
      );
      final detailResult = await repository.getById(
        workspaceId: 'workspace-a',
        propertyId: 'property-b',
      );

      expect(
        (listResult as PropertyRepositorySuccess<PropertyPageResult>)
            .value
            .items
            .map((property) => property.id),
        <String>['property-a'],
      );
      expect(
        (detailResult as PropertyRepositoryFailure<PropertyDto>).kind,
        PropertyRepositoryFailureKind.notFound,
      );
    });

    test('increments version exactly once and deduplicates mutation id', () async {
      final command = _updateCommand(mutationId: 'mutation-1');

      final first = await repository.update(command);
      final retry = await repository.update(command);

      expect(
        (first as PropertyRepositorySuccess<PropertyDto>).value.version,
        2,
      );
      expect(
        (retry as PropertyRepositorySuccess<PropertyDto>).value.version,
        2,
      );
      expect(repository.committedUpdates, 1);
    });

    test('returns current state for a stale expected version', () async {
      await repository.update(_updateCommand(mutationId: 'mutation-1'));

      final result = await repository.update(
        _updateCommand(mutationId: 'mutation-2'),
      );
      final failure = result as PropertyRepositoryFailure<PropertyDto>;

      expect(failure.kind, PropertyRepositoryFailureKind.versionConflict);
      expect(failure.versionConflict?.expectedVersion, 1);
      expect(failure.versionConflict?.actualVersion, 2);
      expect(failure.versionConflict?.currentProperty.version, 2);
      expect(repository.committedUpdates, 1);
    });
  });
}

PropertyDto _property({required String id, required String workspaceId}) {
  final timestamp = DateTime.utc(2026, 7, 12);
  return PropertyDto(
    id: id,
    workspaceId: workspaceId,
    name: 'Objekt',
    addressLine1: 'Musterstrasse 1',
    zip: '10115',
    city: 'Berlin',
    country: 'DE',
    propertyType: 'residential',
    units: 4,
    status: PropertyStatus.active,
    createdAt: timestamp,
    updatedAt: timestamp,
    createdBy: 'actor-1',
    updatedBy: 'actor-1',
    version: 1,
  );
}

PropertyUpdateCommand _updateCommand({required String mutationId}) {
  return PropertyUpdateCommand(
    propertyId: 'property-a',
    context: CommandContext(
      workspaceId: 'workspace-a',
      actorId: 'actor-1',
      mutationId: mutationId,
      expectedVersion: 1,
      correlationId: 'correlation-1',
    ),
    changes: const PropertyUpdateDto(
      name: 'Objekt aktualisiert',
      addressLine1: 'Musterstrasse 1',
      zip: '10115',
      city: 'Berlin',
      country: 'DE',
      propertyType: 'residential',
      units: 4,
      status: PropertyStatus.active,
    ),
  );
}

class _ContractRepository implements PropertyRepository {
  _ContractRepository(Iterable<PropertyDto> properties)
    : _properties = <String, PropertyDto>{
        for (final property in properties) property.id: property,
      };

  final Map<String, PropertyDto> _properties;
  final Map<String, PropertyDto> _mutationResults = <String, PropertyDto>{};
  int committedUpdates = 0;

  @override
  Future<PropertyRepositoryResult<PropertyDto>> getById({
    required String workspaceId,
    required String propertyId,
  }) async {
    final property = _properties[propertyId];
    if (property == null || property.workspaceId != workspaceId) {
      return const PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.notFound,
        message: 'Property not found.',
      );
    }
    return PropertyRepositorySuccess<PropertyDto>(property);
  }

  @override
  Future<PropertyRepositoryResult<PropertyPageResult>> list(
    PropertyListQuery query,
  ) async {
    final items = _properties.values
        .where((property) => property.workspaceId == query.workspaceId)
        .where(
          (property) =>
              query.includeArchived || property.status != PropertyStatus.archived,
        )
        .take(query.page.limit)
        .toList(growable: false);
    return PropertyRepositorySuccess<PropertyPageResult>(
      PropertyPageResult(items: items),
    );
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> update(
    PropertyUpdateCommand command,
  ) async {
    final cached = _mutationResults[command.context.mutationId];
    if (cached != null) {
      return PropertyRepositorySuccess<PropertyDto>(cached);
    }

    final current = _properties[command.propertyId];
    if (current == null || current.workspaceId != command.context.workspaceId) {
      return const PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.notFound,
        message: 'Property not found.',
      );
    }
    if (current.version != command.context.expectedVersion) {
      return PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.versionConflict,
        message: 'Property version conflict.',
        versionConflict: PropertyVersionConflict(
          expectedVersion: command.context.expectedVersion,
          actualVersion: current.version,
          currentProperty: current,
        ),
      );
    }

    final changes = command.changes;
    final updated = PropertyDto(
      id: current.id,
      workspaceId: current.workspaceId,
      name: changes.name,
      addressLine1: changes.addressLine1,
      addressLine2: changes.addressLine2,
      zip: changes.zip,
      city: changes.city,
      country: changes.country,
      propertyType: changes.propertyType,
      units: changes.units,
      sqft: changes.sqft,
      yearBuilt: changes.yearBuilt,
      notes: changes.notes,
      status: changes.status,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt.add(const Duration(seconds: 1)),
      createdBy: current.createdBy,
      updatedBy: command.context.actorId,
      version: current.version + 1,
      deletedAt: current.deletedAt,
    );
    _properties[current.id] = updated;
    _mutationResults[command.context.mutationId] = updated;
    committedUpdates++;
    return PropertyRepositorySuccess<PropertyDto>(updated);
  }
}
