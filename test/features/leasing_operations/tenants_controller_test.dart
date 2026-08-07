import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_repository.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/application/tenants_controller.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';

const String _workspace = 'workspace-a';

void main() {
  group('the list is the party directory scoped to a role', () {
    test('reads parties with the tenant role, server-side', () async {
      final search = _FakePartySearch()
        ..parties = <PartySummaryDto>[_party('p1', 'Meier')];
      final controller = _controller(partySearch: search);
      await controller.load();

      expect(search.lastQuery?.roleType, PartyRoleType.tenant);
      expect(controller.state.listPhase, TenantsListPhase.ready);
    });

    test('an empty result is its own phase, not an error', () async {
      final controller = _controller();
      await controller.load();

      expect(controller.state.listPhase, TenantsListPhase.empty);
    });

    test('forbidden is distinct from error', () async {
      final search = _FakePartySearch()
        ..failure = PartyRepositoryFailureKind.forbidden;
      final controller = _controller(partySearch: search);
      await controller.load();

      expect(controller.state.listPhase, TenantsListPhase.forbidden);
    });

    test('an unresolved scope stays idle instead of calling the backend',
        () async {
      final search = _FakePartySearch();
      final controller = _controller(
        partySearch: search,
        scope: const WorkspaceSessionScope.unresolved(),
      );
      await controller.load();

      expect(controller.state.listPhase, TenantsListPhase.idle);
      expect(search.calls, 0);
    });
  });

  group('detail — two contracts, read separately', () {
    test('loads identity, all roles and the leases of the party', () async {
      final roles = _FakePartyRoles()
        ..roles = <PartyRoleDto>[
          _role('r1', PartyRoleType.tenant),
          _role('r2', PartyRoleType.contractor),
        ];
      final leases = _FakeLeaseSearch()
        ..leases = <LeaseSummaryDto>[_lease('l1')];
      final controller = _controller(partyRoles: roles, leaseSearch: leases);

      await controller.select('p1');

      expect(controller.state.detailPhase, TenantsDetailPhase.ready);
      // All roles, not only the tenant one: one identity, several roles.
      expect(controller.state.selectedRoles, hasLength(2));
      expect(controller.state.leasesPhase, TenantLeasesPhase.ready);
      expect(leases.lastQuery?.tenantPartyId, 'p1');
    });

    test('unreadable leases are their own forbidden state, not "no leases"',
        () async {
      final leases = _FakeLeaseSearch()
        ..failure = LeasingRepositoryFailureKind.forbidden;
      final controller = _controller(leaseSearch: leases);

      await controller.select('p1');

      // The identity still loaded — only the leasing half is blocked.
      expect(controller.state.detailPhase, TenantsDetailPhase.ready);
      expect(controller.state.leasesPhase, TenantLeasesPhase.forbidden);
      expect(controller.state.selectedLeases, isEmpty);
    });

    test('a missing party is notFound, not a generic error', () async {
      final repository = _FakePartyRepository()
        ..getResult = const PartyRepositoryFailure<PartyDto>(
          kind: PartyRepositoryFailureKind.notFound,
          message: 'gone',
        );
      final controller = _controller(partyRepository: repository);

      await controller.select('p1');

      expect(controller.state.detailPhase, TenantsDetailPhase.notFound);
    });

    test('openTenantRole ignores closed roles and other role types', () async {
      final roles = _FakePartyRoles()
        ..roles = <PartyRoleDto>[
          _role('r1', PartyRoleType.tenant, closed: true),
          _role('r2', PartyRoleType.contractor),
        ];
      final controller = _controller(partyRoles: roles);

      await controller.select('p1');

      expect(controller.state.openTenantRole, isNull);
    });
  });

  group('creating a tenant is two commands', () {
    test('creates the party and assigns the tenant role', () async {
      final repository = _FakePartyRepository();
      final roles = _FakePartyRoles();
      final controller = _controller(
        partyRepository: repository,
        partyRoles: roles,
      );

      await controller.createTenant(_draft());

      expect(repository.createCalls, 1);
      expect(roles.assignedRole, PartyRoleType.tenant);
      expect(controller.state.actionPhase, TenantsActionPhase.succeeded);
    });

    test('a failed role assignment is reported as partially applied', () async {
      // There is no transaction across two RPCs: the party exists. Saying
      // "created" would hide a record the user cannot find, and rolling back
      // would need a delete path this domain does not have.
      final repository = _FakePartyRepository();
      final roles = _FakePartyRoles()
        ..assignFailure = PartyRepositoryFailureKind.validationFailed;
      final controller = _controller(
        partyRepository: repository,
        partyRoles: roles,
      );

      await controller.createTenant(_draft());

      expect(controller.state.actionPhase, TenantsActionPhase.partiallyApplied);
      expect(controller.state.actionMessage, contains('als Partei angelegt'));
      expect(controller.state.actionMessage, contains('Rolle'));
    });

    test('a failed party creation never reaches the role assignment', () async {
      final repository = _FakePartyRepository()
        ..createResult = const PartyRepositoryFailure<PartyDto>(
          kind: PartyRepositoryFailureKind.validationFailed,
          message: 'invalid',
        );
      final roles = _FakePartyRoles();
      final controller = _controller(
        partyRepository: repository,
        partyRoles: roles,
      );

      await controller.createTenant(_draft());

      expect(controller.state.actionPhase, TenantsActionPhase.failed);
      expect(roles.assignCalls, 0);
    });
  });

  group('mutation gate', () {
    test('a read-only backend answers readOnly, not a failed mutation',
        () async {
      final repository = _FakePartyRepository();
      final controller = _controller(
        partyRepository: repository,
        scope: _scope(mutationsSupported: false),
      );

      await controller.createTenant(_draft());

      expect(controller.state.actionPhase, TenantsActionPhase.readOnly);
      expect(repository.createCalls, 0);
    });

    test('a missing party.manage answers forbidden, distinct from readOnly',
        () async {
      final repository = _FakePartyRepository();
      final controller = _controller(
        partyRepository: repository,
        scope: _scope(permissions: const <String>{'party.read', 'lease.read'}),
      );

      await controller.createTenant(_draft());

      expect(controller.state.actionPhase, TenantsActionPhase.forbidden);
      expect(repository.createCalls, 0);
    });

    test('a version conflict carries the current party for the dialog',
        () async {
      final repository = _FakePartyRepository()
        ..updateResult = PartyRepositoryFailure<PartyDto>(
          kind: PartyRepositoryFailureKind.versionConflict,
          message: 'stale',
          versionConflict: PartyVersionConflict(
            expectedVersion: 1,
            actualVersion: 3,
            currentParty: _partyDto('p1', version: 3),
          ),
        );
      final controller = _controller(partyRepository: repository);

      await controller.updateTenant(
        party: _partyDto('p1'),
        changes: const PartyUpdateDto(
          type: PartyType.person,
          displayName: 'Meier',
        ),
      );

      expect(controller.state.actionPhase, TenantsActionPhase.conflict);
      expect(controller.state.versionConflict?.currentParty?.version, 3);
    });
  });

  group('ending the tenant role', () {
    test('ends the role and clears the selection instead of deleting', () async {
      final roles = _FakePartyRoles();
      final controller = _controller(partyRoles: roles);

      await controller.endTenantRole(role: _role('r1', PartyRoleType.tenant));

      expect(roles.endedRoleId, 'r1');
      expect(controller.state.actionPhase, TenantsActionPhase.succeeded);
      expect(controller.state.actionMessage, contains('bleibt im Verzeichnis'));
      // The party is no longer a tenant, so it left this role-scoped list.
      expect(controller.state.selectedPartyId, isNull);
    });

    test('passes the optional end date through', () async {
      final roles = _FakePartyRoles();
      final controller = _controller(partyRoles: roles);

      await controller.endTenantRole(
        role: _role('r1', PartyRoleType.tenant),
        validUntil: DateTime.utc(2026, 12, 31),
      );

      expect(roles.endedValidUntil, DateTime.utc(2026, 12, 31));
    });
  });
}

TenantsController _controller({
  _FakePartyRepository? partyRepository,
  _FakePartySearch? partySearch,
  _FakePartyRoles? partyRoles,
  _FakeLeaseSearch? leaseSearch,
  WorkspaceSessionScope? scope,
}) {
  var counter = 0;
  final controller = TenantsController(
    partyRepository: partyRepository ?? _FakePartyRepository(),
    partySearch: partySearch ?? _FakePartySearch(),
    partyRoles: partyRoles ?? _FakePartyRoles(),
    leaseSearch: leaseSearch ?? _FakeLeaseSearch(),
    scope: scope ?? _scope(),
    idFactory: () => 'id-${counter++}',
  );
  addTearDown(controller.dispose);
  return controller;
}

WorkspaceSessionScope _scope({
  bool mutationsSupported = true,
  Set<String> permissions = const <String>{
    'party.read',
    'party.manage',
    'lease.read',
  },
}) {
  return WorkspaceSessionScope(
    workspaceId: _workspace,
    actorId: 'actor-1',
    permissions: permissions,
    mutationsSupported: mutationsSupported,
  );
}

PartyDraft _draft() => const PartyDraft(
  type: PartyType.person,
  displayName: 'Meier',
);

PartySummaryDto _party(String id, String name) => PartySummaryDto(
  id: id,
  workspaceId: _workspace,
  type: PartyType.person,
  displayName: name,
  version: 1,
);

PartyDto _partyDto(String id, {int version = 1}) => PartyDto(
  id: id,
  workspaceId: _workspace,
  type: PartyType.person,
  displayName: 'Meier',
  version: version,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  createdBy: 'actor-1',
  updatedBy: 'actor-1',
);

PartyRoleDto _role(String id, PartyRoleType type, {bool closed = false}) =>
    PartyRoleDto(
  id: id,
  workspaceId: _workspace,
  partyId: 'p1',
  roleType: type,
  validFrom: DateTime.utc(2026, 1, 1),
  validUntil: closed ? DateTime.utc(2026, 6, 30) : null,
  version: 1,
);

LeaseSummaryDto _lease(String id) => LeaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: 'property-a',
  unitId: 'u1',
  leaseName: id.toUpperCase(),
  status: LeaseStatus.active,
  startDate: DateTime.utc(2026, 1, 1),
  baseRentMonthly: 1000,
  currencyCode: 'EUR',
  version: 1,
  tenantPartyId: 'p1',
);

class _FakePartySearch implements PartySearchPort {
  List<PartySummaryDto> parties = const <PartySummaryDto>[];
  PartyRepositoryFailureKind? failure;
  PartyListQuery? lastQuery;
  int calls = 0;

  @override
  Future<PartyRepositoryResult<PartyPageResult>> search(
    PartyListQuery query,
  ) async {
    calls++;
    lastQuery = query;
    final kind = failure;
    if (kind != null) {
      return PartyRepositoryFailure<PartyPageResult>(
        kind: kind,
        message: 'failed',
      );
    }
    return PartyRepositorySuccess<PartyPageResult>(
      PartyPageResult(items: parties),
    );
  }
}

class _FakePartyRepository implements PartyRepository {
  PartyRepositoryResult<PartyDto>? getResult;
  PartyRepositoryResult<PartyDto>? createResult;
  PartyRepositoryResult<PartyDto>? updateResult;
  int createCalls = 0;

  @override
  Future<PartyRepositoryResult<PartyDto>> getById({
    required String workspaceId,
    required String partyId,
  }) async => getResult ?? PartyRepositorySuccess<PartyDto>(_partyDto(partyId));

  @override
  Future<PartyRepositoryResult<PartyDto>> create(
    CreatePartyCommand command,
  ) async {
    createCalls++;
    return createResult ?? PartyRepositorySuccess<PartyDto>(_partyDto('p-new'));
  }

  @override
  Future<PartyRepositoryResult<PartyDto>> update(
    UpdatePartyCommand command,
  ) async =>
      updateResult ?? PartyRepositorySuccess<PartyDto>(_partyDto(command.partyId));

  @override
  Future<PartyRepositoryResult<PartyDto>> merge(
    MergePartiesCommand command,
  ) async => PartyRepositorySuccess<PartyDto>(_partyDto(command.targetPartyId));
}

class _FakePartyRoles implements PartyRoleRepository {
  List<PartyRoleDto> roles = const <PartyRoleDto>[];
  PartyRepositoryFailureKind? assignFailure;
  PartyRoleType? assignedRole;
  int assignCalls = 0;
  String? endedRoleId;
  DateTime? endedValidUntil;

  @override
  Future<PartyRepositoryResult<List<PartyRoleDto>>> listForParty({
    required String workspaceId,
    required String partyId,
  }) async => PartyRepositorySuccess<List<PartyRoleDto>>(roles);

  @override
  Future<PartyRepositoryResult<ContractorDetailsDto?>> getContractorDetails({
    required String workspaceId,
    required String partyId,
  }) async => const PartyRepositorySuccess<ContractorDetailsDto?>(null);

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> assign(
    AssignPartyRoleCommand command,
  ) async {
    assignCalls++;
    assignedRole = command.roleType;
    final kind = assignFailure;
    if (kind != null) {
      return PartyRepositoryFailure<PartyRoleDto>(
        kind: kind,
        message: 'role refused',
      );
    }
    return PartyRepositorySuccess<PartyRoleDto>(
      _role('r-new', command.roleType),
    );
  }

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> end(
    EndPartyRoleCommand command,
  ) async {
    endedRoleId = command.partyRoleId;
    endedValidUntil = command.validUntil;
    return PartyRepositorySuccess<PartyRoleDto>(
      _role(command.partyRoleId, PartyRoleType.tenant, closed: true),
    );
  }
}

class _FakeLeaseSearch implements LeaseSearchPort {
  List<LeaseSummaryDto> leases = const <LeaseSummaryDto>[];
  LeasingRepositoryFailureKind? failure;
  LeaseListQuery? lastQuery;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeaseSummaryDto>>> search(
    LeaseListQuery query,
  ) async {
    lastQuery = query;
    final kind = failure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeasingPageResult<LeaseSummaryDto>>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
      LeasingPageResult<LeaseSummaryDto>(items: leases),
    );
  }
}
