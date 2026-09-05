import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';

/// PROPERTY-DATA-02 in the controller: creating a property and the named
/// archive/restore actions.
///
/// The gates proven here are the client half of a server-enforced rule — the
/// RPC refuses the same cases (pgTAP 031). The point is that the client never
/// sends a command it knows is not permitted, and never invents local state
/// when one fails.
void main() {
  group('ReferenceSliceController property lifecycle', () {
    late _FakeIdentityRepository identity;
    late _FakePropertyRepository properties;
    late ReferenceSliceController controller;
    late Queue<String> ids;

    setUp(() {
      identity = _FakeIdentityRepository();
      properties = _FakePropertyRepository();
      ids = Queue<String>.of(<String>[
        'mutation-a',
        'correlation-a',
        'mutation-b',
        'correlation-b',
      ]);
      controller = ReferenceSliceController(
        identityRepository: identity,
        propertyRepository: properties,
        entitlementRevalidationInterval: const Duration(hours: 1),
        idFactory: () => ids.removeFirst(),
      );
    });

    tearDown(() async {
      controller.dispose();
      await _flush();
      await identity.close();
    });

    Future<void> start({
      Set<String> permissions = const <String>{
        'property.read',
        'property.create',
        'property.update',
      },
      AuthenticationAssuranceLevel level = AuthenticationAssuranceLevel.aal2,
      List<PropertyDto> listItems = const <PropertyDto>[],
      String? nextCursor,
    }) async {
      identity.authenticate(level: level);
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[_access(permissions: permissions)],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: listItems, nextCursor: nextCursor),
      );
      await controller.start();
    }

    test('creates a property, selects it and inserts it in keyset order', () async {
      await start(
        listItems: <PropertyDto>[
          _property(id: 'property-a'),
          _property(id: 'property-c'),
        ],
      );
      properties.createResults.add(
        PropertyRepositorySuccess<PropertyDto>(
          _property(
            id: 'property-b',
            name: 'Neubau',
            status: PropertyStatus.draft,
          ),
        ),
      );

      await controller.createProperty(
        const PropertyCreateDto(
          name: 'Neubau',
          addressLine1: 'Baustelle 1',
          zip: '10115',
          city: 'Berlin',
          country: 'de',
          propertyType: 'residential',
          units: 4,
        ),
        reason: 'Bestandsaufnahme',
      );

      expect(controller.state.mutationPhase, PropertyMutationPhase.succeeded);
      // The command carries workspace, actor, a fresh mutation id and the reason.
      final command = properties.createCommands.single;
      expect(command.context.workspaceId, 'workspace-a');
      expect(command.context.actorId, 'user-a');
      expect(command.context.mutationId, 'mutation-a');
      expect(command.context.correlationId, 'correlation-a');
      expect(command.context.reason, 'Bestandsaufnahme');
      expect(command.draft.name, 'Neubau');

      // The created draft becomes the canonical selection without a second read.
      expect(controller.state.selectedProperty?.id, 'property-b');
      expect(controller.state.selectedProperty?.status, PropertyStatus.draft);
      expect(controller.state.propertyDetailPhase, PropertyDetailPhase.ready);
      expect(properties.detailPropertyIds, isEmpty);
      // Inserted at its keyset position, not appended.
      expect(
        controller.state.properties.map((property) => property.id),
        <String>['property-a', 'property-b', 'property-c'],
      );
    });

    test('does not claim a created row beyond the loaded page range', () async {
      // The loaded page ends before the new id and more pages exist, so listing
      // it here would assert a row the user has not paged to.
      await start(
        listItems: <PropertyDto>[_property(id: 'property-a')],
        nextCursor: 'property-a',
      );
      properties.createResults.add(
        PropertyRepositorySuccess<PropertyDto>(_property(id: 'property-z')),
      );

      await controller.createProperty(_draft());

      expect(controller.state.mutationPhase, PropertyMutationPhase.succeeded);
      expect(controller.state.selectedProperty?.id, 'property-z');
      expect(
        controller.state.properties.map((property) => property.id),
        <String>['property-a'],
        reason: 'the list still shows exactly the loaded page',
      );
    });

    test('refuses to send a creation without property.create', () async {
      await start(
        permissions: const <String>{'property.read', 'property.update'},
      );

      await controller.createProperty(_draft());

      expect(
        properties.createCommands,
        isEmpty,
        reason: 'never reaches backend',
      );
      expect(controller.state.mutationPhase, PropertyMutationPhase.forbidden);
      expect(
        controller.state.failureKind,
        PropertyRepositoryFailureKind.forbidden,
      );
      expect(controller.state.selectedProperty, isNull);
    });

    test('refuses to send a creation below aal2', () async {
      // An aal1 session never reaches the authenticated business phase, so the
      // guard has to hold there too.
      await start(level: AuthenticationAssuranceLevel.aal1);

      await controller.createProperty(_draft());

      expect(properties.createCommands, isEmpty);
      expect(controller.state.mutationPhase, PropertyMutationPhase.forbidden);
    });

    test(
      'a failed creation changes no selection and carries the field',
      () async {
        await start(listItems: <PropertyDto>[_property(id: 'property-a')]);
        properties.createResults.add(
          const PropertyRepositoryFailure<PropertyDto>(
            kind: PropertyRepositoryFailureKind.validationFailed,
            message: 'Country must be a normalized code',
            field: 'country',
          ),
        );

        await controller.createProperty(_draft());

        expect(controller.state.mutationPhase, PropertyMutationPhase.failed);
        expect(controller.state.validationField, 'country');
        expect(controller.state.selectedProperty, isNull);
        expect(
          controller.state.properties.map((property) => property.id),
          <String>['property-a'],
          reason: 'no local shadow row is invented',
        );
      },
    );

    test(
      'a later successful creation clears the stale validation field',
      () async {
        await start();
        properties.createResults
          ..add(
            const PropertyRepositoryFailure<PropertyDto>(
              kind: PropertyRepositoryFailureKind.validationFailed,
              message: 'nope',
              field: 'zip',
            ),
          )
          ..add(
            PropertyRepositorySuccess<PropertyDto>(_property(id: 'property-b')),
          );

        await controller.createProperty(_draft());
        expect(controller.state.validationField, 'zip');

        await controller.createProperty(_draft());
        expect(controller.state.mutationPhase, PropertyMutationPhase.succeeded);
        expect(controller.state.validationField, isNull);
      },
    );

    test('archiving sends the full record with the tombstone status', () async {
      await start(listItems: <PropertyDto>[_property(id: 'property-a')]);
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(
          id: 'property-a',
          notes: 'Bestandsnotiz',
          sqft: 1250.5,
          yearBuilt: 1998,
        ),
      );
      await controller.openProperty('property-a');
      properties.updateResults.add(
        PropertyRepositorySuccess<PropertyDto>(
          _property(
            id: 'property-a',
            version: 2,
            status: PropertyStatus.archived,
          ),
        ),
      );

      await controller.setSelectedPropertyArchived(
        archived: true,
        reason: 'Verkauft',
      );

      final command = properties.updateCommands.single;
      expect(command.changes.status, PropertyStatus.archived);
      // Every other field travels unchanged: this is a full-record contract.
      expect(command.changes.name, 'Atlas House');
      expect(command.changes.notes, 'Bestandsnotiz');
      expect(command.changes.sqft, 1250.5);
      expect(command.changes.yearBuilt, 1998);
      expect(command.changes.propertyType, 'mixed_use');
      expect(command.context.expectedVersion, 1);
      expect(command.context.reason, 'Verkauft');
      expect(controller.state.mutationPhase, PropertyMutationPhase.succeeded);
      // Archived rows leave the active list (DEBT-012 tombstone).
      expect(controller.state.properties, isEmpty);
    });

    test('restoring sends the active status back', () async {
      await start();
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(id: 'property-a', status: PropertyStatus.archived),
      );
      await controller.openProperty('property-a');
      properties.updateResults.add(
        PropertyRepositorySuccess<PropertyDto>(
          _property(id: 'property-a', version: 2),
        ),
      );

      await controller.setSelectedPropertyArchived(archived: false);

      expect(
        properties.updateCommands.single.changes.status,
        PropertyStatus.active,
      );
    });

    test('an unchanged status sends nothing', () async {
      await start();
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(id: 'property-a'),
      );
      await controller.openProperty('property-a');

      await controller.setSelectedPropertyArchived(archived: false);

      expect(properties.updateCommands, isEmpty);
    });

    test('archiving without a selected property sends nothing', () async {
      await start();

      await controller.setSelectedPropertyArchived(archived: true);

      expect(properties.updateCommands, isEmpty);
    });
  });
}

PropertyCreateDto _draft() {
  return const PropertyCreateDto(
    name: 'Neubau',
    addressLine1: 'Baustelle 1',
    zip: '10115',
    city: 'Berlin',
    country: 'de',
    propertyType: 'residential',
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

WorkspaceAccess _access({required Set<String> permissions}) {
  return WorkspaceAccess(
    workspace: const WorkspaceSummary(
      id: 'workspace-a',
      key: 'workspace-a',
      name: 'Workspace A',
      version: 1,
    ),
    membership: const MembershipSummary(
      id: 'membership-a',
      workspaceId: 'workspace-a',
      userId: 'user-a',
      roleId: 'manager',
      version: 1,
    ),
    permissions: permissions,
  );
}

PropertyDto _property({
  String id = 'property-a',
  String name = 'Atlas House',
  PropertyStatus status = PropertyStatus.active,
  int version = 1,
  String? notes,
  double? sqft,
  int? yearBuilt,
}) {
  return PropertyDto(
    id: id,
    workspaceId: 'workspace-a',
    name: name,
    addressLine1: 'Long Street 123',
    zip: '10115',
    city: 'Berlin',
    country: 'de',
    propertyType: 'mixed_use',
    units: 12,
    sqft: sqft,
    yearBuilt: yearBuilt,
    notes: notes,
    status: status,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 5),
    createdBy: 'user-a',
    updatedBy: 'user-a',
    version: version,
  );
}

class _FakePropertyRepository implements PropertyRepository {
  PropertyRepositoryResult<PropertyPageResult> listResult =
      const PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[]),
      );
  PropertyRepositoryResult<PropertyDto> detailResult =
      const PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.notFound,
        message: 'Not found.',
      );
  final Queue<PropertyRepositoryResult<PropertyDto>> createResults =
      Queue<PropertyRepositoryResult<PropertyDto>>();
  final Queue<PropertyRepositoryResult<PropertyDto>> updateResults =
      Queue<PropertyRepositoryResult<PropertyDto>>();
  final List<PropertyCreateCommand> createCommands = <PropertyCreateCommand>[];
  final List<PropertyUpdateCommand> updateCommands = <PropertyUpdateCommand>[];
  final List<String> detailPropertyIds = <String>[];

  @override
  Future<PropertyRepositoryResult<PropertyPageResult>> list(
    PropertyListQuery query,
  ) async => listResult;

  @override
  Future<PropertyRepositoryResult<PropertyDto>> create(
    PropertyCreateCommand command,
  ) async {
    createCommands.add(command);
    return createResults.removeFirst();
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> getById({
    required String workspaceId,
    required String propertyId,
  }) async {
    detailPropertyIds.add(propertyId);
    return detailResult;
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> update(
    PropertyUpdateCommand command,
  ) async {
    updateCommands.add(command);
    return updateResults.removeFirst();
  }
}

class _FakeIdentityRepository implements IdentityAccessRepository {
  final StreamController<AuthenticatedSession?> _sessions =
      StreamController<AuthenticatedSession?>.broadcast();
  AuthenticatedSession? currentSessionValue;
  IdentityAccessResult<List<WorkspaceAccess>> result =
      const IdentityAccessSuccess<List<WorkspaceAccess>>(<WorkspaceAccess>[]);

  void authenticate({
    AuthenticationAssuranceLevel level = AuthenticationAssuranceLevel.aal2,
  }) {
    currentSessionValue = AuthenticatedSession(
      userId: 'user-a',
      currentAssuranceLevel: level,
      nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
    );
  }

  Future<void> close() => _sessions.close();

  @override
  AuthenticatedSession? get currentSession => currentSessionValue;

  @override
  Stream<AuthenticatedSession?> watchSession() => _sessions.stream;

  @override
  Future<IdentityAccessResult<List<WorkspaceAccess>>> listWorkspaceAccesses({
    required String userId,
  }) async => result;

  @override
  Future<IdentityAccessResult<TotpFactorInventory>>
  listTotpFactorInventory() async =>
      const IdentityAccessSuccess<TotpFactorInventory>(
        TotpFactorInventory.empty(),
      );

  @override
  Future<IdentityAccessResult<TotpChallenge>> challengeTotp({
    required String factorId,
  }) async => throw UnimplementedError();

  @override
  Future<IdentityAccessResult<TotpEnrollment>> enrollTotp() async =>
      throw UnimplementedError();

  @override
  Future<IdentityAccessResult<void>> unenrollTotpFactor({
    required String factorId,
  }) async => throw UnimplementedError();

  @override
  Future<IdentityAccessResult<void>> signInWithPassword({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<IdentityAccessResult<void>> requestPasswordlessSignIn({
    required String email,
  }) async => throw UnimplementedError();

  @override
  Future<IdentityAccessResult<void>> signOut() async =>
      const IdentityAccessSuccess<void>(null);

  @override
  Future<IdentityAccessResult<AuthenticatedSession>> verifyTotp({
    required TotpChallenge challenge,
    required String code,
  }) async => throw UnimplementedError();
}
