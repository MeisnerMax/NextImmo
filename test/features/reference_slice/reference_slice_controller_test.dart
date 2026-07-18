import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_query_invalidation_source.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';

void main() {
  group('ReferenceSliceController', () {
    late _FakeIdentityRepository identity;
    late _FakePropertyRepository properties;
    late _FakePropertyInvalidationSource invalidations;
    late ReferenceSliceController controller;
    late Queue<String> ids;

    setUp(() {
      identity = _FakeIdentityRepository();
      properties = _FakePropertyRepository();
      invalidations = _FakePropertyInvalidationSource();
      ids = Queue<String>.of(<String>['mutation-a', 'correlation-a']);
      controller = ReferenceSliceController(
        identityRepository: identity,
        propertyRepository: properties,
        propertyInvalidationSource: invalidations,
        idFactory: () => ids.removeFirst(),
      );
    });

    tearDown(() async {
      controller.dispose();
      await _flushEvents();
      await identity.close();
      await invalidations.close();
    });

    test('stays unprivileged without an authenticated session', () async {
      await controller.start();

      expect(controller.state.authPhase, ReferenceAuthPhase.unauthenticated);
      expect(controller.state.workspacePhase, WorkspacePhase.idle);
      expect(properties.listCalls, 0);
      expect(identity.listCalls, 0);
    });

    test('blocks all data while an enrolled MFA factor is pending', () async {
      identity.currentSession = const AuthenticatedSession(
        userId: 'user-a',
        currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
        nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
      );

      await controller.start();

      expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
      expect(controller.state.workspacePhase, WorkspacePhase.idle);
      expect(identity.listCalls, 0);
      expect(properties.listCalls, 0);
    });

    test('loads the only active workspace and explicit empty list', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );

      await controller.start();

      expect(controller.state.authPhase, ReferenceAuthPhase.authenticated);
      expect(controller.state.workspacePhase, WorkspacePhase.selected);
      expect(controller.state.selectedWorkspaceId, 'workspace-a');
      expect(controller.state.propertyListPhase, PropertyListPhase.empty);
      expect(properties.listWorkspaceIds, <String>['workspace-a']);
    });

    test(
      'requires selection with multiple workspaces and rejects foreign id',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read'}),
            _access(
              workspaceId: 'workspace-b',
              permissions: <String>{'property.read'},
            ),
          ],
        );

        await controller.start();
        expect(
          controller.state.workspacePhase,
          WorkspacePhase.selectionRequired,
        );
        expect(properties.listCalls, 0);

        await controller.selectWorkspace('foreign-workspace');
        expect(controller.state.propertyListPhase, PropertyListPhase.forbidden);
        expect(controller.state.selectedWorkspaceId, isNull);
        expect(properties.listCalls, 0);

        await controller.selectWorkspace('workspace-b');
        expect(controller.state.selectedWorkspaceId, 'workspace-b');
        expect(properties.listWorkspaceIds, <String>['workspace-b']);
      },
    );

    test(
      'derives forbidden list state before calling the repository',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[_access(permissions: <String>{})],
        );

        await controller.start();

        expect(controller.state.propertyListPhase, PropertyListPhase.forbidden);
        expect(
          controller.state.failureKind,
          PropertyRepositoryFailureKind.forbidden,
        );
        expect(properties.listCalls, 0);
      },
    );

    test('loads stable-id detail and applies a successful update', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read', 'property.update'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );
      properties.updateResults.add(
        PropertyRepositorySuccess<PropertyDto>(
          _property(version: 2, name: 'After'),
        ),
      );

      await controller.start();
      await controller.openProperty('property-a');
      await controller.updateSelectedProperty(_changes(name: 'After'));

      expect(properties.detailPropertyIds, <String>['property-a']);
      expect(controller.state.propertyDetailPhase, PropertyDetailPhase.ready);
      expect(controller.state.mutationPhase, PropertyMutationPhase.succeeded);
      expect(controller.state.selectedProperty?.version, 2);
      expect(properties.updateCommands.single.context.actorId, 'user-a');
      expect(
        properties.updateCommands.single.context.workspaceId,
        'workspace-a',
      );
      expect(properties.updateCommands.single.context.expectedVersion, 1);
    });

    test('retries a transient failure with the identical command', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read', 'property.update'}),
        ],
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );
      properties.updateResults
        ..add(
          const PropertyRepositoryFailure<PropertyDto>(
            kind: PropertyRepositoryFailureKind.infrastructureFailure,
            message: 'Temporary failure.',
          ),
        )
        ..add(PropertyRepositorySuccess<PropertyDto>(_property(version: 2)));

      await controller.start();
      await controller.openProperty('property-a');
      await controller.updateSelectedProperty(_changes());
      expect(controller.state.mutationPhase, PropertyMutationPhase.failed);

      await controller.retryUpdate();

      expect(properties.updateCommands, hasLength(2));
      expect(
        identical(properties.updateCommands[0], properties.updateCommands[1]),
        isTrue,
      );
      expect(properties.updateCommands[1].context.mutationId, 'mutation-a');
      expect(controller.state.mutationPhase, PropertyMutationPhase.succeeded);
    });

    test(
      'surfaces version conflict and replaces stale detail safely',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read', 'property.update'}),
          ],
        );
        properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
          _property(),
        );
        final current = _property(version: 4, name: 'Server value');
        properties.updateResults.add(
          PropertyRepositoryFailure<PropertyDto>(
            kind: PropertyRepositoryFailureKind.versionConflict,
            message: 'Stale version.',
            versionConflict: PropertyVersionConflict(
              expectedVersion: 1,
              actualVersion: 4,
              currentProperty: current,
            ),
          ),
        );

        await controller.start();
        await controller.openProperty('property-a');
        await controller.updateSelectedProperty(_changes());

        expect(controller.state.mutationPhase, PropertyMutationPhase.conflict);
        expect(controller.state.versionConflict?.actualVersion, 4);
        expect(controller.state.selectedProperty?.name, 'Server value');
        await controller.retryUpdate();
        expect(properties.updateCommands, hasLength(1));
      },
    );

    test('session loss invalidates a late property response', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      final pendingList =
          Completer<PropertyRepositoryResult<PropertyPageResult>>();
      properties.listHandler = (_) => pendingList.future;

      final start = controller.start();
      await _flushEvents();
      identity.emit(null);
      await _flushEvents();
      pendingList.complete(
        PropertyRepositorySuccess<PropertyPageResult>(
          PropertyPageResult(items: <PropertyDto>[_property()]),
        ),
      );
      await start;
      await _flushEvents();

      expect(controller.state.authPhase, ReferenceAuthPhase.unauthenticated);
      expect(controller.state.properties, isEmpty);
      expect(controller.state.selectedWorkspaceId, isNull);
    });

    test('Realtime refreshes the active list and matching detail', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );

      await controller.start();
      await controller.openProperty('property-a');
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property(version: 2)]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(version: 2, name: 'Realtime'),
      );

      invalidations.emit(
        const PropertyQueryInvalidation(
          workspaceId: 'workspace-a',
          propertyId: 'property-a',
        ),
      );
      await _flushEvents();
      await _flushEvents();

      expect(invalidations.workspaceIds, <String>['workspace-a']);
      expect(properties.listCalls, 2);
      expect(properties.detailPropertyIds, <String>[
        'property-a',
        'property-a',
      ]);
      expect(controller.state.selectedProperty?.name, 'Realtime');
      expect(controller.state.selectedProperty?.version, 2);
    });

    test('Realtime refresh preserves already loaded property pages', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      var call = 0;
      properties.listHandler = (query) async {
        call++;
        return switch (call) {
          1 => PropertyRepositorySuccess<PropertyPageResult>(
            PropertyPageResult(
              items: <PropertyDto>[
                _property(id: 'property-a'),
                _property(id: 'property-b'),
              ],
              nextCursor: 'property-b',
            ),
          ),
          2 => PropertyRepositorySuccess<PropertyPageResult>(
            PropertyPageResult(
              items: <PropertyDto>[_property(id: 'property-c')],
            ),
          ),
          _ => PropertyRepositorySuccess<PropertyPageResult>(
            PropertyPageResult(
              items: <PropertyDto>[
                _property(id: 'property-a', version: 2),
                _property(id: 'property-b'),
              ],
              nextCursor: 'property-b',
            ),
          ),
        };
      };

      await controller.start();
      await controller.loadNextPropertyPage();
      invalidations.emit(
        const PropertyQueryInvalidation(
          workspaceId: 'workspace-a',
          propertyId: 'property-a',
        ),
      );
      await _flushEvents();
      await _flushEvents();

      expect(
        controller.state.properties.map((property) => property.id),
        <String>['property-a', 'property-b', 'property-c'],
      );
      expect(controller.state.properties.first.version, 2);
      expect(controller.state.nextCursor, isNull);
    });

    test('Realtime burst is coalesced to one pending refresh', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      await controller.start();

      final firstRefresh =
          Completer<PropertyRepositoryResult<PropertyPageResult>>();
      var refreshCalls = 0;
      properties.listHandler = (_) {
        refreshCalls++;
        if (refreshCalls == 1) {
          return firstRefresh.future;
        }
        return Future<PropertyRepositoryResult<PropertyPageResult>>.value(
          PropertyRepositorySuccess<PropertyPageResult>(
            PropertyPageResult(items: <PropertyDto>[_property(version: 2)]),
          ),
        );
      };

      for (var index = 0; index < 20; index++) {
        invalidations.emit(
          const PropertyQueryInvalidation(
            workspaceId: 'workspace-a',
            propertyId: 'property-a',
          ),
        );
      }
      await _flushEvents();
      expect(refreshCalls, 1);

      firstRefresh.complete(
        PropertyRepositorySuccess<PropertyPageResult>(
          PropertyPageResult(items: <PropertyDto>[_property(version: 2)]),
        ),
      );
      await _flushEvents();
      await _flushEvents();

      expect(refreshCalls, 2);
      expect(properties.listCalls, 3);
      expect(controller.state.properties.single.version, 2);
    });

    test('Realtime forbidden response clears cached property data', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
        ],
      );
      properties.listResult = PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(items: <PropertyDto>[_property()]),
      );
      properties.detailResult = PropertyRepositorySuccess<PropertyDto>(
        _property(),
      );

      await controller.start();
      await controller.openProperty('property-a');
      properties
          .listResult = const PropertyRepositoryFailure<PropertyPageResult>(
        kind: PropertyRepositoryFailureKind.forbidden,
        message: 'Access revoked.',
      );
      invalidations.emit(
        const PropertyQueryInvalidation(
          workspaceId: 'workspace-a',
          propertyId: 'property-a',
        ),
      );
      await _flushEvents();
      await _flushEvents();

      expect(controller.state.propertyListPhase, PropertyListPhase.forbidden);
      expect(
        controller.state.propertyDetailPhase,
        PropertyDetailPhase.forbidden,
      );
      expect(controller.state.properties, isEmpty);
      expect(controller.state.selectedProperty, isNull);
    });

    test('workspace switch cancels the old Realtime scope', () async {
      identity.authenticate();
      identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
        <WorkspaceAccess>[
          _access(permissions: <String>{'property.read'}),
          _access(
            workspaceId: 'workspace-b',
            permissions: <String>{'property.read'},
          ),
        ],
      );

      await controller.start();
      await controller.selectWorkspace('workspace-a');
      await controller.selectWorkspace('workspace-b');
      final callsBeforeLateEvent = properties.listCalls;

      invalidations.emit(
        const PropertyQueryInvalidation(
          workspaceId: 'workspace-a',
          propertyId: 'property-a',
        ),
      );
      await _flushEvents();

      expect(invalidations.workspaceIds, <String>[
        'workspace-a',
        'workspace-b',
      ]);
      expect(invalidations.cancelCalls['workspace-a'], 1);
      expect(properties.listCalls, callsBeforeLateEvent);
      expect(controller.state.selectedWorkspaceId, 'workspace-b');
    });

    test(
      'session downgrade cancels Realtime and ignores late events',
      () async {
        identity.authenticate();
        identity.result = IdentityAccessSuccess<List<WorkspaceAccess>>(
          <WorkspaceAccess>[
            _access(permissions: <String>{'property.read'}),
          ],
        );

        await controller.start();
        identity.emit(
          const AuthenticatedSession(
            userId: 'user-a',
            currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
            nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
          ),
        );
        await _flushEvents();
        final callsAfterDowngrade = properties.listCalls;

        invalidations.emit(
          const PropertyQueryInvalidation(
            workspaceId: 'workspace-a',
            propertyId: 'property-a',
          ),
        );
        await _flushEvents();

        expect(controller.state.authPhase, ReferenceAuthPhase.mfaRequired);
        expect(invalidations.cancelCalls['workspace-a'], 1);
        expect(properties.listCalls, callsAfterDowngrade);
      },
    );
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

WorkspaceAccess _access({
  String workspaceId = 'workspace-a',
  required Set<String> permissions,
}) {
  return WorkspaceAccess(
    workspace: WorkspaceSummary(
      id: workspaceId,
      key: workspaceId,
      name: workspaceId,
      version: 1,
    ),
    membership: MembershipSummary(
      id: 'membership-$workspaceId',
      workspaceId: workspaceId,
      userId: 'user-a',
      roleId: 'role-$workspaceId',
      version: 1,
    ),
    permissions: permissions,
  );
}

PropertyDto _property({
  String id = 'property-a',
  int version = 1,
  String name = 'Property',
}) {
  return PropertyDto(
    id: id,
    workspaceId: 'workspace-a',
    name: name,
    addressLine1: 'Street 1',
    zip: '10115',
    city: 'Berlin',
    country: 'de',
    propertyType: 'office',
    units: 1,
    status: PropertyStatus.active,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
    createdBy: 'user-a',
    updatedBy: 'user-a',
    version: version,
  );
}

PropertyUpdateDto _changes({String name = 'Updated'}) {
  return PropertyUpdateDto(
    name: name,
    addressLine1: 'Street 2',
    zip: '10117',
    city: 'Berlin',
    country: 'de',
    propertyType: 'office',
    units: 2,
    status: PropertyStatus.active,
  );
}

class _FakeIdentityRepository implements IdentityAccessRepository {
  final StreamController<AuthenticatedSession?> _sessions =
      StreamController<AuthenticatedSession?>.broadcast();

  @override
  AuthenticatedSession? currentSession;

  IdentityAccessResult<List<WorkspaceAccess>> result =
      const IdentityAccessSuccess<List<WorkspaceAccess>>(<WorkspaceAccess>[]);
  int listCalls = 0;

  @override
  Stream<AuthenticatedSession?> watchSession() => _sessions.stream;

  @override
  Future<IdentityAccessResult<List<WorkspaceAccess>>> listWorkspaceAccesses({
    required String userId,
  }) async {
    listCalls++;
    return result;
  }

  void authenticate() {
    currentSession = const AuthenticatedSession(
      userId: 'user-a',
      currentAssuranceLevel: AuthenticationAssuranceLevel.aal1,
      nextAssuranceLevel: AuthenticationAssuranceLevel.aal1,
    );
  }

  void emit(AuthenticatedSession? session) {
    currentSession = session;
    _sessions.add(session);
  }

  Future<void> close() => _sessions.close();
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
  Future<PropertyRepositoryResult<PropertyPageResult>> Function(
    PropertyListQuery query,
  )?
  listHandler;
  final Queue<PropertyRepositoryResult<PropertyDto>> updateResults =
      Queue<PropertyRepositoryResult<PropertyDto>>();
  final List<String> listWorkspaceIds = <String>[];
  final List<PropertyListQuery> listQueries = <PropertyListQuery>[];
  final List<String> detailPropertyIds = <String>[];
  final List<PropertyUpdateCommand> updateCommands = <PropertyUpdateCommand>[];

  int get listCalls => listWorkspaceIds.length;

  @override
  Future<PropertyRepositoryResult<PropertyPageResult>> list(
    PropertyListQuery query,
  ) async {
    listWorkspaceIds.add(query.workspaceId);
    listQueries.add(query);
    final handler = listHandler;
    return handler == null ? listResult : handler(query);
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

class _FakePropertyInvalidationSource
    implements PropertyQueryInvalidationSource {
  final Map<String, StreamController<PropertyQueryInvalidation>> _controllers =
      <String, StreamController<PropertyQueryInvalidation>>{};
  final List<String> workspaceIds = <String>[];
  final Map<String, int> cancelCalls = <String, int>{};

  @override
  Stream<PropertyQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) {
    workspaceIds.add(workspaceId);
    final controller = StreamController<PropertyQueryInvalidation>.broadcast(
      onCancel: () {
        cancelCalls.update(
          workspaceId,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      },
    );
    _controllers[workspaceId] = controller;
    return controller.stream;
  }

  void emit(PropertyQueryInvalidation invalidation) {
    _controllers[invalidation.workspaceId]?.add(invalidation);
  }

  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}
