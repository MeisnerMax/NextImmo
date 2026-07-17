import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/data/supabase_property_repository_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';

void main() {
  group('SupabasePropertyRepositoryAdapter', () {
    late _FakePropertySupabaseGateway gateway;
    late SupabasePropertyRepositoryAdapter repository;

    setUp(() {
      gateway = _FakePropertySupabaseGateway();
      repository = SupabasePropertyRepositoryAdapter.withGateway(gateway);
    });

    test(
      'lists with workspace keyset, archived filter, and limit plus one',
      () async {
        gateway.listResult = <Map<String, dynamic>>[
          _propertyJson(id: 'property-a'),
          _propertyJson(id: 'property-b', status: 'archived'),
          _propertyJson(id: 'property-c'),
        ];

        final result = await repository.list(
          const PropertyListQuery(
            workspaceId: 'workspace-a',
            page: PropertyPageRequest(limit: 2, cursor: 'property-before'),
          ),
        );

        expect(gateway.listWorkspaceId, 'workspace-a');
        expect(gateway.listAfterId, 'property-before');
        expect(gateway.listLimit, 3);
        expect(gateway.listIncludeArchived, isFalse);
        final page =
            (result as PropertyRepositorySuccess<PropertyPageResult>).value;
        expect(page.items.map((property) => property.id), <String>[
          'property-a',
          'property-b',
        ]);
        expect(page.nextCursor, 'property-b');
      },
    );

    test('forwards includeArchived and omits cursor on first page', () async {
      await repository.list(
        const PropertyListQuery(
          workspaceId: 'workspace-a',
          includeArchived: true,
        ),
      );

      expect(gateway.listAfterId, isNull);
      expect(gateway.listIncludeArchived, isTrue);
      expect(gateway.listLimit, 51);
    });

    test('gets detail only when id and workspace match', () async {
      gateway.getResult = <Map<String, dynamic>>[
        _propertyJson(id: 'foreign-property', workspaceId: 'workspace-b'),
      ];

      final result = await repository.getById(
        workspaceId: 'workspace-a',
        propertyId: 'property-a',
      );

      expect(gateway.getWorkspaceId, 'workspace-a');
      expect(gateway.getPropertyId, 'property-a');
      expect(
        (result as PropertyRepositoryFailure<PropertyDto>).kind,
        PropertyRepositoryFailureKind.notFound,
      );
    });

    test('returns not found for an empty scoped detail result', () async {
      final result = await repository.getById(
        workspaceId: 'workspace-a',
        propertyId: 'property-a',
      );

      expect(
        (result as PropertyRepositoryFailure<PropertyDto>).kind,
        PropertyRepositoryFailureKind.notFound,
      );
    });

    test('rejects actor mismatch before calling update RPC', () async {
      gateway.currentUserId = 'another-actor';

      final result = await repository.update(_command());

      expect(gateway.updateCalls, 0);
      expect(
        (result as PropertyRepositoryFailure<PropertyDto>).kind,
        PropertyRepositoryFailureKind.forbidden,
      );
    });

    test('updates only through RPC with the complete serialized DTO', () async {
      gateway.updateResult = <String, Object?>{
        'ok': true,
        'property': _propertyJson(version: 2),
      };

      final result = await repository.update(_command());

      expect(gateway.updateCalls, 1);
      expect(gateway.updateParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_property_id': 'property-a',
        'p_expected_version': 1,
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_changes': <String, Object?>{
          'name': 'Updated property',
          'address_line1': 'New street 2',
          'address_line2': 'Rear building',
          'zip': '20202',
          'city': 'Hamburg',
          'country': 'de',
          'property_type': 'mixed_use',
          'units': 8,
          'sqft': 1234.5,
          'year_built': 1999,
          'notes': 'Updated notes',
          'status': 'active',
        },
        'p_reason': 'Correction',
      });
      final property = (result as PropertyRepositorySuccess<PropertyDto>).value;
      expect(property.version, 2);
      expect(property.sqft, 2500.5);
      expect(property.deletedAt, DateTime.parse('2026-07-13T12:00:00Z'));
    });

    test('maps version conflict including current property', () async {
      gateway.updateResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'version_conflict',
          'message': 'Stale property',
          'expected_version': 1,
          'actual_version': 3,
          'current_property': _propertyJson(version: 3),
        },
      };

      final result = await repository.update(_command());
      final failure = result as PropertyRepositoryFailure<PropertyDto>;

      expect(failure.kind, PropertyRepositoryFailureKind.versionConflict);
      expect(failure.versionConflict?.expectedVersion, 1);
      expect(failure.versionConflict?.actualVersion, 3);
      expect(failure.versionConflict?.currentProperty.version, 3);
    });

    test('maps mutation conflict and in-progress separately', () async {
      for (final entry in <(String, PropertyRepositoryFailureKind)>[
        ('mutation_conflict', PropertyRepositoryFailureKind.mutationConflict),
        ('in_progress', PropertyRepositoryFailureKind.mutationInProgress),
      ]) {
        gateway.updateResult = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': entry.$1,
            'message': 'Mutation failed',
          },
        };

        final result = await repository.update(_command());

        expect(
          (result as PropertyRepositoryFailure<PropertyDto>).kind,
          entry.$2,
        );
      }
    });

    test('hides malformed response and gateway exception details', () async {
      gateway.listResult = <Map<String, dynamic>>[
        _propertyJson()..remove('created_at'),
      ];
      final malformed = await repository.list(
        const PropertyListQuery(workspaceId: 'workspace-a'),
      );

      gateway.getError = StateError('sensitive Postgrest detail');
      final failedRead = await repository.getById(
        workspaceId: 'workspace-a',
        propertyId: 'property-a',
      );

      for (final failure in <PropertyRepositoryFailure<dynamic>>[
        malformed as PropertyRepositoryFailure<PropertyPageResult>,
        failedRead as PropertyRepositoryFailure<PropertyDto>,
      ]) {
        expect(
          failure.kind,
          PropertyRepositoryFailureKind.infrastructureFailure,
        );
        expect(failure.message, isNot(contains('sensitive')));
      }
    });
  });
}

PropertyUpdateCommand _command() {
  return const PropertyUpdateCommand(
    propertyId: 'property-a',
    context: CommandContext(
      workspaceId: 'workspace-a',
      actorId: 'actor-a',
      mutationId: 'mutation-a',
      expectedVersion: 1,
      correlationId: 'correlation-a',
      reason: 'Correction',
    ),
    changes: PropertyUpdateDto(
      name: 'Updated property',
      addressLine1: 'New street 2',
      addressLine2: 'Rear building',
      zip: '20202',
      city: 'Hamburg',
      country: 'de',
      propertyType: 'mixed_use',
      units: 8,
      sqft: 1234.5,
      yearBuilt: 1999,
      notes: 'Updated notes',
      status: PropertyStatus.active,
    ),
  );
}

Map<String, dynamic> _propertyJson({
  String id = 'property-a',
  String workspaceId = 'workspace-a',
  String status = 'active',
  int version = 1,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'name': 'Property',
    'address_line1': 'Street 1',
    'address_line2': 'Building A',
    'zip': '10115',
    'city': 'Berlin',
    'country': 'de',
    'property_type': 'residential',
    'units': 4,
    'sqft': 2500.5,
    'year_built': 1985,
    'notes': 'Notes',
    'status': status,
    'created_at': '2026-07-12T10:00:00Z',
    'updated_at': '2026-07-13T11:00:00Z',
    'created_by': 'actor-a',
    'updated_by': 'actor-a',
    'version': version,
    'deleted_at': '2026-07-13T12:00:00Z',
  };
}

class _FakePropertySupabaseGateway implements PropertySupabaseGateway {
  @override
  String? currentUserId = 'actor-a';

  List<Map<String, dynamic>> listResult = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> getResult = <Map<String, dynamic>>[];
  Object? updateResult;
  Object? listError;
  Object? getError;
  Object? updateError;

  String? listWorkspaceId;
  String? listAfterId;
  int? listLimit;
  bool? listIncludeArchived;
  String? getWorkspaceId;
  String? getPropertyId;
  int updateCalls = 0;
  Map<String, Object?>? updateParameters;

  @override
  Future<List<Map<String, dynamic>>> listProperties({
    required String workspaceId,
    required String? afterId,
    required int limit,
    required bool includeArchived,
  }) async {
    if (listError != null) {
      throw listError!;
    }
    listWorkspaceId = workspaceId;
    listAfterId = afterId;
    listLimit = limit;
    listIncludeArchived = includeArchived;
    return listResult;
  }

  @override
  Future<List<Map<String, dynamic>>> getProperty({
    required String workspaceId,
    required String propertyId,
  }) async {
    if (getError != null) {
      throw getError!;
    }
    getWorkspaceId = workspaceId;
    getPropertyId = propertyId;
    return getResult;
  }

  @override
  Future<Object?> updateProperty(Map<String, Object?> parameters) async {
    updateCalls++;
    updateParameters = parameters;
    if (updateError != null) {
      throw updateError!;
    }
    return updateResult;
  }
}
