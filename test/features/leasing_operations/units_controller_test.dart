import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_query_invalidation_source.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/application/units_controller.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';

const String _workspace = 'workspace-a';
const String _property = 'property-a';

void main() {
  group('list phases', () {
    test('an empty result is its own phase, not an error', () async {
      final controller = _controller();
      await controller.load();

      expect(controller.state.listPhase, UnitsListPhase.empty);
      expect(controller.state.units, isEmpty);
    });

    test('forbidden is distinct from error', () async {
      final search = _FakeUnitSearch()
        ..failure = LeasingRepositoryFailureKind.forbidden;
      final controller = _controller(search: search);
      await controller.load();

      expect(controller.state.listPhase, UnitsListPhase.forbidden);
    });

    test('an infrastructure failure lands in error with a message', () async {
      final search = _FakeUnitSearch()
        ..failure = LeasingRepositoryFailureKind.infrastructureFailure;
      final controller = _controller(search: search);
      await controller.load();

      expect(controller.state.listPhase, UnitsListPhase.error);
      expect(controller.state.message, isNotNull);
    });

    test('an unresolved scope stays idle instead of calling the backend',
        () async {
      final search = _FakeUnitSearch();
      final controller = _controller(
        search: search,
        scope: const WorkspaceSessionScope.unresolved(),
      );
      await controller.load();

      expect(controller.state.listPhase, UnitsListPhase.idle);
      expect(search.calls, 0);
    });

    test('scopes every read to its property', () async {
      final search = _FakeUnitSearch()..units = <UnitSummaryDto>[_summary('u1')];
      final controller = _controller(search: search);
      await controller.load();

      expect(search.lastQuery?.propertyId, _property);
      expect(controller.state.listPhase, UnitsListPhase.ready);
    });

    test('the status filter reaches the server rather than filtering locally',
        () async {
      final search = _FakeUnitSearch()..units = <UnitSummaryDto>[_summary('u1')];
      final controller = _controller(search: search);
      await controller.load();

      await controller.setStatusFilter(UnitStatus.offline);

      expect(search.lastQuery?.status, UnitStatus.offline);
      expect(search.calls, 2);
    });

    test('loadMore appends the next keyset page', () async {
      final search = _FakeUnitSearch()
        ..units = <UnitSummaryDto>[_summary('u1')]
        ..nextCursor = 'u1';
      final controller = _controller(search: search);
      await controller.load();

      search
        ..units = <UnitSummaryDto>[_summary('u2')]
        ..nextCursor = null;
      await controller.loadMore();

      expect(controller.state.units.map((unit) => unit.id), <String>[
        'u1',
        'u2',
      ]);
      expect(controller.state.hasMore, isFalse);
    });
  });

  group('mutation gate', () {
    test('a read-only backend answers readOnly, not a failed mutation',
        () async {
      final repository = _FakeUnitRepository();
      final controller = _controller(
        repository: repository,
        scope: _scope(mutationsSupported: false),
      );

      await controller.createUnit(
        const UnitDraft(propertyId: _property, unitCode: 'A-01'),
      );

      expect(controller.state.actionPhase, UnitsActionPhase.readOnly);
      expect(controller.state.actionMessage, contains('schreibgeschützt'));
      // The command must not even be attempted.
      expect(repository.createCalls, 0);
    });

    test('a missing permission answers forbidden, distinct from readOnly',
        () async {
      final repository = _FakeUnitRepository();
      final controller = _controller(
        repository: repository,
        scope: _scope(permissions: const <String>{'lease.read'}),
      );

      await controller.createUnit(
        const UnitDraft(propertyId: _property, unitCode: 'A-01'),
      );

      expect(controller.state.actionPhase, UnitsActionPhase.forbidden);
      expect(repository.createCalls, 0);
    });

    test('a version conflict carries the current unit for the resolve dialog',
        () async {
      final repository = _FakeUnitRepository()
        ..updateResult = LeasingRepositoryFailure<UnitDto>(
          kind: LeasingRepositoryFailureKind.versionConflict,
          message: 'stale',
          versionConflict: LeasingVersionConflict(
            expectedVersion: 1,
            actualVersion: 2,
            currentUnit: _unit('u1', version: 2),
          ),
        );
      final controller = _controller(repository: repository);

      await controller.updateUnit(
        unitId: 'u1',
        expectedVersion: 1,
        changes: const UnitUpdateDto(unitCode: 'A-01'),
      );

      expect(controller.state.actionPhase, UnitsActionPhase.conflict);
      expect(controller.state.versionConflict?.currentUnit?.version, 2);
    });
  });

  group('STM-003 — offline is the only caller-driven edge', () {
    test('taking a unit offline without a reason never reaches the server',
        () async {
      final repository = _FakeUnitRepository();
      final controller = _controller(repository: repository);

      await controller.takeOffline(
        unitId: 'u1',
        expectedVersion: 1,
        reason: '   ',
      );

      expect(controller.state.actionPhase, UnitsActionPhase.failed);
      expect(controller.state.actionMessage, contains('Grund'));
      expect(repository.transitionCalls, 0);
    });

    test('the offline reason travels as the command reason, not a second field',
        () async {
      final repository = _FakeUnitRepository();
      final controller = _controller(repository: repository);

      await controller.takeOffline(
        unitId: 'u1',
        expectedVersion: 1,
        reason: '  Wasserschaden  ',
      );

      expect(repository.lastTransition?.targetStatus, UnitStatus.offline);
      expect(repository.lastTransition?.context.reason, 'Wasserschaden');
      expect(controller.state.actionPhase, UnitsActionPhase.succeeded);
    });

    test('returning from offline sends vacant when no lease is effective',
        () async {
      final repository = _FakeUnitRepository();
      final leases = _FakeLeaseSearch();
      final controller = _controller(repository: repository, leaseSearch: leases);

      await controller.returnFromOffline(unitId: 'u1', expectedVersion: 1);

      expect(repository.lastTransition?.targetStatus, UnitStatus.vacant);
    });

    test('returning from offline sends occupied when a lease is effective',
        () async {
      final repository = _FakeUnitRepository();
      final leases = _FakeLeaseSearch()
        ..leases = <LeaseSummaryDto>[_lease('l1')];
      final controller = _controller(repository: repository, leaseSearch: leases);

      await controller.returnFromOffline(unitId: 'u1', expectedVersion: 1);

      expect(repository.lastTransition?.targetStatus, UnitStatus.occupied);
      // The *deciding* read must be the effective-only one the server's rule
      // uses; the reload afterwards deliberately reads unfiltered (AP2).
      expect(leases.queries.first.effectiveOnly, isTrue);
      expect(leases.queries.first.unitId, 'u1');
    });

    test('an unreadable lease situation blocks the transition, not guesses it',
        () async {
      final repository = _FakeUnitRepository();
      final leases = _FakeLeaseSearch()
        ..failure = LeasingRepositoryFailureKind.infrastructureFailure;
      final controller = _controller(repository: repository, leaseSearch: leases);

      await controller.returnFromOffline(unitId: 'u1', expectedVersion: 1);

      expect(controller.state.actionPhase, UnitsActionPhase.failed);
      expect(repository.transitionCalls, 0);
    });

    test('a blocked backend skips the extra lease read entirely', () async {
      final leases = _FakeLeaseSearch();
      final controller = _controller(
        leaseSearch: leases,
        scope: _scope(mutationsSupported: false),
      );

      await controller.returnFromOffline(unitId: 'u1', expectedVersion: 1);

      expect(controller.state.actionPhase, UnitsActionPhase.readOnly);
      expect(leases.calls, 0);
    });
  });

  group('realtime', () {
    test('one lease activation causes one refetch, not two', () async {
      // The migration publishes both tables on purpose: activating a lease
      // writes the lease and, via sync_unit_occupancy, its unit. The screen
      // must collapse that burst.
      final source = _FakeInvalidationSource();
      final search = _FakeUnitSearch();
      final controller = _controller(
        search: search,
        invalidationSource: source,
        coalesceWindow: const Duration(milliseconds: 20),
      );
      await controller.load();
      final before = search.calls;

      source.emit(
        const LeasingQueryInvalidation(
          workspaceId: _workspace,
          aggregate: LeasingAggregate.lease,
          entityId: 'l1',
        ),
      );
      source.emit(
        const LeasingQueryInvalidation(
          workspaceId: _workspace,
          aggregate: LeasingAggregate.unit,
          entityId: 'u1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(search.calls - before, 1);
    });

    test('ignores events that cannot change a unit', () async {
      final source = _FakeInvalidationSource();
      final search = _FakeUnitSearch();
      final controller = _controller(
        search: search,
        invalidationSource: source,
        coalesceWindow: const Duration(milliseconds: 20),
      );
      await controller.load();
      final before = search.calls;

      source.emit(
        const LeasingQueryInvalidation(
          workspaceId: _workspace,
          aggregate: LeasingAggregate.rentRollSnapshot,
          entityId: 's1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(search.calls - before, 0);
    });

    test('ignores another workspace entirely', () async {
      final source = _FakeInvalidationSource();
      final search = _FakeUnitSearch();
      final controller = _controller(
        search: search,
        invalidationSource: source,
        coalesceWindow: const Duration(milliseconds: 20),
      );
      await controller.load();
      final before = search.calls;

      source.emit(
        const LeasingQueryInvalidation(
          workspaceId: 'other-workspace',
          aggregate: LeasingAggregate.unit,
          entityId: 'u1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(search.calls - before, 0);
    });
  });

  group('detail', () {
    test('a missing unit is notFound, not a generic error', () async {
      final repository = _FakeUnitRepository()
        ..getResult = const LeasingRepositoryFailure<UnitDto>(
          kind: LeasingRepositoryFailureKind.notFound,
          message: 'gone',
        );
      final controller = _controller(repository: repository);

      await controller.select('u1');

      expect(controller.state.detailPhase, UnitsDetailPhase.notFound);
    });

    test('loads every lease of the unit, effective or not (OPN-DOM-001)',
        () async {
      // AP2's load-bearing claim: the detail must never collapse a unit to
      // "its" lease. The read is deliberately unfiltered so history stays
      // visible, and isEffective marks the rows that count for occupancy.
      final leases = _FakeLeaseSearch()
        ..leases = <LeaseSummaryDto>[
          _lease('l1'),
          _lease('l2'),
          _lease('l3', status: LeaseStatus.ended),
        ];
      final controller = _controller(leaseSearch: leases);

      await controller.select('u1');

      expect(controller.state.selectedUnitLeases, hasLength(3));
      expect(
        controller.state.selectedUnitLeases.where((l) => l.isEffective).length,
        2,
      );
      expect(leases.lastQuery?.unitId, 'u1');
      // Unfiltered: history must not be hidden by an effective-only read.
      expect(leases.lastQuery?.effectiveOnly, isFalse);
    });

    test('an unreadable lease list degrades to empty, not to a failed detail',
        () async {
      final leases = _FakeLeaseSearch()
        ..failure = LeasingRepositoryFailureKind.infrastructureFailure;
      final controller = _controller(leaseSearch: leases);

      await controller.select('u1');

      expect(controller.state.detailPhase, UnitsDetailPhase.ready);
      expect(controller.state.selectedUnitLeases, isEmpty);
    });

    test('deselecting clears the lease list too', () async {
      final leases = _FakeLeaseSearch()..leases = <LeaseSummaryDto>[_lease('l1')];
      final controller = _controller(leaseSearch: leases);
      await controller.select('u1');
      await controller.select(null);

      expect(controller.state.selectedUnitLeases, isEmpty);
    });

    test('deselecting clears the panel', () async {
      final controller = _controller();
      await controller.select('u1');
      await controller.select(null);

      expect(controller.state.detailPhase, UnitsDetailPhase.idle);
      expect(controller.state.selectedUnit, isNull);
    });
  });
}

UnitsController _controller({
  _FakeUnitRepository? repository,
  _FakeUnitSearch? search,
  _FakeLeaseSearch? leaseSearch,
  WorkspaceSessionScope? scope,
  LeasingQueryInvalidationSource? invalidationSource,
  Duration coalesceWindow = const Duration(milliseconds: 250),
}) {
  var counter = 0;
  final controller = UnitsController(
    repository: repository ?? _FakeUnitRepository(),
    search: search ?? _FakeUnitSearch(),
    leaseSearch: leaseSearch ?? _FakeLeaseSearch(),
    scope: scope ?? _scope(),
    propertyId: _property,
    invalidationSource: invalidationSource,
    idFactory: () => 'id-${counter++}',
    invalidationCoalesceWindow: coalesceWindow,
  );
  addTearDown(controller.dispose);
  return controller;
}

WorkspaceSessionScope _scope({
  bool mutationsSupported = true,
  Set<String> permissions = const <String>{'lease.read', 'lease.manage'},
}) {
  return WorkspaceSessionScope(
    workspaceId: _workspace,
    actorId: 'actor-1',
    permissions: permissions,
    mutationsSupported: mutationsSupported,
  );
}

UnitSummaryDto _summary(String id) => UnitSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitCode: id.toUpperCase(),
  status: UnitStatus.vacant,
  version: 1,
);

UnitDto _unit(String id, {int version = 1}) => UnitDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitCode: id.toUpperCase(),
  status: UnitStatus.vacant,
  version: version,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  createdBy: 'actor-1',
  updatedBy: 'actor-1',
);

LeaseSummaryDto _lease(String id, {LeaseStatus status = LeaseStatus.active}) =>
    LeaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitId: 'u1',
  leaseName: id,
  status: status,
  startDate: DateTime.utc(2026, 1, 1),
  baseRentMonthly: 1000,
  currencyCode: 'EUR',
  version: 1,
);

class _FakeUnitSearch implements UnitSearchPort {
  List<UnitSummaryDto> units = const <UnitSummaryDto>[];
  String? nextCursor;
  LeasingRepositoryFailureKind? failure;
  UnitListQuery? lastQuery;
  int calls = 0;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<UnitSummaryDto>>> search(
    UnitListQuery query,
  ) async {
    calls++;
    lastQuery = query;
    final kind = failure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeasingPageResult<UnitSummaryDto>>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
      LeasingPageResult<UnitSummaryDto>(items: units, nextCursor: nextCursor),
    );
  }
}

class _FakeLeaseSearch implements LeaseSearchPort {
  List<LeaseSummaryDto> leases = const <LeaseSummaryDto>[];
  LeasingRepositoryFailureKind? failure;
  final List<LeaseListQuery> queries = <LeaseListQuery>[];
  int calls = 0;

  LeaseListQuery? get lastQuery => queries.isEmpty ? null : queries.last;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeaseSummaryDto>>> search(
    LeaseListQuery query,
  ) async {
    calls++;
    queries.add(query);
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

class _FakeUnitRepository implements UnitRepository {
  LeasingRepositoryResult<UnitDto>? getResult;
  LeasingRepositoryResult<UnitDto>? updateResult;
  int createCalls = 0;
  int transitionCalls = 0;
  TransitionUnitStatusCommand? lastTransition;

  @override
  Future<LeasingRepositoryResult<UnitDto>> getById({
    required String workspaceId,
    required String unitId,
  }) async {
    return getResult ?? LeasingRepositorySuccess<UnitDto>(_unit(unitId));
  }

  @override
  Future<LeasingRepositoryResult<UnitDto>> create(
    CreateUnitCommand command,
  ) async {
    createCalls++;
    return LeasingRepositorySuccess<UnitDto>(_unit('u-new'));
  }

  @override
  Future<LeasingRepositoryResult<UnitDto>> update(
    UpdateUnitCommand command,
  ) async {
    return updateResult ??
        LeasingRepositorySuccess<UnitDto>(_unit(command.unitId));
  }

  @override
  Future<LeasingRepositoryResult<UnitDto>> transitionStatus(
    TransitionUnitStatusCommand command,
  ) async {
    transitionCalls++;
    lastTransition = command;
    return LeasingRepositorySuccess<UnitDto>(_unit(command.unitId));
  }
}

class _FakeInvalidationSource implements LeasingQueryInvalidationSource {
  final StreamController<LeasingQueryInvalidation> _controller =
      StreamController<LeasingQueryInvalidation>.broadcast();

  void emit(LeasingQueryInvalidation invalidation) =>
      _controller.add(invalidation);

  @override
  Stream<LeasingQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) => _controller.stream;
}
