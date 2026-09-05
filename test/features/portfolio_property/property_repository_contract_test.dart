import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_overview_dto.dart';

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

    // PROPERTY-DATA-02: creation is part of the same contract, with the same
    // idempotency rule and one behaviour of its own -- a new property is a
    // draft, never active, and never carries a tombstone marker.
    test(
      'creates a workspace-scoped draft and deduplicates mutation id',
      () async {
        const command = PropertyCreateCommand(
          context: PropertyCreateContext(
            workspaceId: 'workspace-a',
            actorId: 'actor-a',
            mutationId: 'mutation-create-1',
            correlationId: 'correlation-create-1',
          ),
          draft: PropertyCreateDto(
            name: 'Neubau',
            addressLine1: 'Baustelle 1',
            zip: '10115',
            city: 'Berlin',
            country: 'de',
            propertyType: 'residential',
            units: 4,
          ),
        );

        final created = await repository.create(command);
        final retry = await repository.create(command);

        final property =
            (created as PropertyRepositorySuccess<PropertyDto>).value;
        expect(property.workspaceId, 'workspace-a');
        expect(property.status, PropertyStatus.draft);
        expect(property.version, 1);
        expect(property.createdBy, 'actor-a');
        expect(
          (retry as PropertyRepositorySuccess<PropertyDto>).value.id,
          property.id,
          reason: 'a replayed mutation id returns the same property',
        );
        expect(repository.committedCreates, 1);

        // The created property is immediately readable in its own workspace and
        // invisible in another.
        final readBack = await repository.getById(
          workspaceId: 'workspace-a',
          propertyId: property.id,
        );
        expect(readBack, isA<PropertyRepositorySuccess<PropertyDto>>());
        final foreign = await repository.getById(
          workspaceId: 'workspace-b',
          propertyId: property.id,
        );
        expect(
          (foreign as PropertyRepositoryFailure<PropertyDto>).kind,
          PropertyRepositoryFailureKind.notFound,
        );
      },
    );

    test(
      'increments version exactly once and deduplicates mutation id',
      () async {
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
      },
    );

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
  int committedCreates = 0;

  @override
  Future<PropertyRepositoryResult<PropertyDto>> create(
    PropertyCreateCommand command,
  ) async {
    final replayed = _mutationResults[command.context.mutationId];
    if (replayed != null) {
      return PropertyRepositorySuccess<PropertyDto>(replayed);
    }
    final draft = command.draft;
    final created = PropertyDto(
      id: 'created-${_properties.length + 1}',
      workspaceId: command.context.workspaceId,
      name: draft.name,
      addressLine1: draft.addressLine1,
      addressLine2: draft.addressLine2,
      zip: draft.zip,
      city: draft.city,
      country: draft.country,
      propertyType: draft.propertyType,
      units: draft.units,
      sqft: draft.sqft,
      yearBuilt: draft.yearBuilt,
      notes: draft.notes,
      // The contract fixes this: a new property is a draft, never active.
      status: PropertyStatus.draft,
      createdAt: DateTime.utc(2026, 9, 5),
      updatedAt: DateTime.utc(2026, 9, 5),
      createdBy: command.context.actorId,
      updatedBy: command.context.actorId,
      version: 1,
    );
    _properties[created.id] = created;
    _mutationResults[command.context.mutationId] = created;
    committedCreates++;
    return PropertyRepositorySuccess<PropertyDto>(created);
  }

  @override
  Future<PropertyRepositoryResult<PropertyOverviewDto>> overview({
    required String workspaceId,
    required String propertyId,
  }) async => const PropertyRepositoryFailure<PropertyOverviewDto>(
    kind: PropertyRepositoryFailureKind.forbidden,
    message: 'not used by this screen',
  );

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
              query.includeArchived ||
              property.status != PropertyStatus.archived,
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
