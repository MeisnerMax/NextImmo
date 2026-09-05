import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/data/supabase_property_repository_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';

/// PROPERTY-DATA-02: the adapter side of `create_property`.
///
/// Pins the wire contract the RPC expects (parameter names, normalized
/// payload), the typed failure mapping including the server-named field, and
/// the guards the adapter owns: the command actor must be the authenticated
/// user, and a created property outside the commanded workspace is never
/// handed back as a success.
void main() {
  group('SupabasePropertyRepositoryAdapter.create', () {
    late _FakeGateway gateway;
    late SupabasePropertyRepositoryAdapter repository;

    setUp(() {
      gateway = _FakeGateway();
      repository = SupabasePropertyRepositoryAdapter.withGateway(gateway);
    });

    test('sends the full draft under the RPC parameter names', () async {
      gateway.createResult = <String, dynamic>{
        'ok': true,
        'property': _propertyJson(),
      };

      final result = await repository.create(
        PropertyCreateCommand(
          context: const PropertyCreateContext(
            workspaceId: 'workspace-a',
            actorId: 'actor-a',
            mutationId: 'mutation-a',
            correlationId: 'correlation-a',
            reason: 'Portfolio-Aufnahme',
          ),
          draft: const PropertyCreateDto(
            name: 'Atlas House',
            addressLine1: 'Long Street 123',
            addressLine2: 'Hinterhaus',
            zip: '10115',
            city: 'Berlin',
            country: 'de',
            propertyType: 'mixed_use',
            units: 12,
            sqft: 1250.5,
            yearBuilt: 1998,
            notes: 'Erstaufnahme',
          ),
        ),
      );

      expect(gateway.createCalls, 1);
      expect(gateway.createParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_name': 'Atlas House',
        'p_address_line1': 'Long Street 123',
        'p_zip': '10115',
        'p_city': 'Berlin',
        'p_country': 'de',
        'p_property_type': 'mixed_use',
        'p_address_line2': 'Hinterhaus',
        'p_units': 12,
        'p_sqft': 1250.5,
        'p_year_built': 1998,
        'p_notes': 'Erstaufnahme',
        'p_reason': 'Portfolio-Aufnahme',
      });
      final property = (result as PropertyRepositorySuccess<PropertyDto>).value;
      expect(property.id, 'property-a');
      expect(property.status, PropertyStatus.draft);
    });

    test('omits optional fields as null rather than empty strings', () async {
      gateway.createResult = <String, dynamic>{
        'ok': true,
        'property': _propertyJson(),
      };

      await repository.create(
        PropertyCreateCommand(
          context: const PropertyCreateContext(
            workspaceId: 'workspace-a',
            actorId: 'actor-a',
            mutationId: 'mutation-a',
            correlationId: 'correlation-a',
          ),
          draft: const PropertyCreateDto(
            name: 'Atlas House',
            addressLine1: 'Long Street 123',
            zip: '10115',
            city: 'Berlin',
            country: 'de',
            propertyType: 'mixed_use',
          ),
        ),
      );

      final parameters = gateway.createParameters!;
      expect(parameters['p_address_line2'], isNull);
      expect(parameters['p_sqft'], isNull);
      expect(parameters['p_year_built'], isNull);
      expect(parameters['p_notes'], isNull);
      expect(parameters['p_reason'], isNull);
      expect(parameters['p_units'], 0);
    });

    test(
      'refuses a command whose actor is not the authenticated user',
      () async {
        gateway.currentUserId = 'actor-b';

        final result = await repository.create(_command());

        expect(gateway.createCalls, 0, reason: 'never reaches the backend');
        final failure = result as PropertyRepositoryFailure<PropertyDto>;
        expect(failure.kind, PropertyRepositoryFailureKind.forbidden);
      },
    );

    test('maps a validation failure with the server-named field', () async {
      gateway.createResult = <String, dynamic>{
        'ok': false,
        'error': <String, dynamic>{
          'code': 'validation_failed',
          'message': 'Country must be a normalized code',
          'field': 'country',
        },
      };

      final result = await repository.create(_command());

      final failure = result as PropertyRepositoryFailure<PropertyDto>;
      expect(failure.kind, PropertyRepositoryFailureKind.validationFailed);
      expect(failure.field, 'country');
      expect(failure.message, 'Country must be a normalized code');
    });

    test('maps the remaining contract codes', () async {
      for (final mapping in const <(String, PropertyRepositoryFailureKind)>[
        ('forbidden', PropertyRepositoryFailureKind.forbidden),
        ('mutation_conflict', PropertyRepositoryFailureKind.mutationConflict),
        ('in_progress', PropertyRepositoryFailureKind.mutationInProgress),
        ('not_found', PropertyRepositoryFailureKind.notFound),
        (
          'infrastructure_failure',
          PropertyRepositoryFailureKind.infrastructureFailure,
        ),
        ('something_new', PropertyRepositoryFailureKind.infrastructureFailure),
      ]) {
        gateway.createResult = <String, dynamic>{
          'ok': false,
          'error': <String, dynamic>{'code': mapping.$1, 'message': 'nope'},
        };

        final result = await repository.create(_command());

        expect(
          (result as PropertyRepositoryFailure<PropertyDto>).kind,
          mapping.$2,
          reason: 'code ${mapping.$1}',
        );
      }
    });

    test('rejects a created property from another workspace', () async {
      gateway.createResult = <String, dynamic>{
        'ok': true,
        'property': _propertyJson(workspaceId: 'workspace-b'),
      };

      final result = await repository.create(_command());

      final failure = result as PropertyRepositoryFailure<PropertyDto>;
      expect(failure.kind, PropertyRepositoryFailureKind.infrastructureFailure);
    });

    test('turns a transport error into an infrastructure failure', () async {
      gateway.createError = StateError('socket closed');

      final result = await repository.create(_command());

      final failure = result as PropertyRepositoryFailure<PropertyDto>;
      expect(failure.kind, PropertyRepositoryFailureKind.infrastructureFailure);
      // The raw error never reaches the user-facing message.
      expect(failure.message, isNot(contains('socket')));
    });

    test('refuses a malformed RPC envelope', () async {
      gateway.createResult = <String, dynamic>{'property': _propertyJson()};

      final result = await repository.create(_command());

      expect(
        (result as PropertyRepositoryFailure<PropertyDto>).kind,
        PropertyRepositoryFailureKind.infrastructureFailure,
      );
    });
  });
}

PropertyCreateCommand _command() {
  return const PropertyCreateCommand(
    context: PropertyCreateContext(
      workspaceId: 'workspace-a',
      actorId: 'actor-a',
      mutationId: 'mutation-a',
      correlationId: 'correlation-a',
    ),
    draft: PropertyCreateDto(
      name: 'Atlas House',
      addressLine1: 'Long Street 123',
      zip: '10115',
      city: 'Berlin',
      country: 'de',
      propertyType: 'mixed_use',
    ),
  );
}

Map<String, dynamic> _propertyJson({
  String id = 'property-a',
  String workspaceId = 'workspace-a',
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'name': 'Atlas House',
    'address_line1': 'Long Street 123',
    'address_line2': null,
    'zip': '10115',
    'city': 'Berlin',
    'country': 'de',
    'property_type': 'mixed_use',
    'units': 12,
    'sqft': null,
    'year_built': null,
    'notes': null,
    'status': 'draft',
    'created_at': '2026-09-05T08:00:00.000Z',
    'updated_at': '2026-09-05T08:00:00.000Z',
    'created_by': 'actor-a',
    'updated_by': 'actor-a',
    'version': 1,
    'deleted_at': null,
    'deleted_by': null,
  };
}

class _FakeGateway implements PropertySupabaseGateway {
  @override
  String? currentUserId = 'actor-a';

  Object? createResult;
  Object? createError;
  int createCalls = 0;
  Map<String, Object?>? createParameters;

  @override
  Future<Object?> createProperty(Map<String, Object?> parameters) async {
    createCalls++;
    createParameters = parameters;
    if (createError != null) {
      throw createError!;
    }
    return createResult;
  }

  @override
  Future<List<Map<String, dynamic>>> listProperties({
    required String workspaceId,
    required String? afterId,
    required int limit,
    required bool includeArchived,
  }) async => <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> getProperty({
    required String workspaceId,
    required String propertyId,
  }) async => <Map<String, dynamic>>[];

  @override
  Future<Object?> updateProperty(Map<String, Object?> parameters) async => null;
}
