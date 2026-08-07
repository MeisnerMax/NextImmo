import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_repository.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leases_controller.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_query_invalidation_source.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';

const String _workspace = 'workspace-a';
const String _property = 'property-a';

void main() {
  group('STM-005 — the local mirror', () {
    test('every non-terminal state has exactly one forward step', () {
      expect(LeaseStatus.draft.nextStatus, LeaseStatus.reviewed);
      expect(LeaseStatus.reviewed.nextStatus, LeaseStatus.sent);
      expect(LeaseStatus.sent.nextStatus, LeaseStatus.tenantSigned);
      expect(LeaseStatus.tenantSigned.nextStatus, LeaseStatus.landlordSigned);
      expect(LeaseStatus.landlordSigned.nextStatus, LeaseStatus.active);
      expect(LeaseStatus.active.nextStatus, LeaseStatus.ended);
      expect(LeaseStatus.ended.nextStatus, isNull);
      expect(LeaseStatus.cancelled.nextStatus, isNull);
    });

    test('there is no backward edge anywhere', () {
      for (final from in LeaseStatus.values) {
        for (final to in LeaseStatus.values) {
          if (to == LeaseStatus.cancelled || to == from.nextStatus) {
            continue;
          }
          expect(
            from.canTransitionTo(to),
            isFalse,
            reason: '$from -> $to must not be offered',
          );
        }
      }
    });

    test('cancelling is allowed from every non-terminal state and nowhere else',
        () {
      for (final from in LeaseStatus.values) {
        expect(
          from.canTransitionTo(LeaseStatus.cancelled),
          !from.isTerminal,
          reason: 'cancel from $from',
        );
      }
    });

    test('editability stops at the first signature', () {
      // Mirrors update_lease's v_editable_states.
      expect(LeaseStatus.draft.isEditable, isTrue);
      expect(LeaseStatus.reviewed.isEditable, isTrue);
      expect(LeaseStatus.sent.isEditable, isTrue);
      expect(LeaseStatus.tenantSigned.isEditable, isFalse);
      expect(LeaseStatus.landlordSigned.isEditable, isFalse);
      expect(LeaseStatus.active.isEditable, isFalse);
      expect(LeaseStatus.ended.isEditable, isFalse);
      expect(LeaseStatus.cancelled.isEditable, isFalse);
    });
  });

  group('list phases', () {
    test('an empty result is its own phase, not an error', () async {
      final controller = _controller();
      await controller.load();

      expect(controller.state.listPhase, LeasesListPhase.empty);
      expect(controller.state.leases, isEmpty);
    });

    test('forbidden is distinct from error', () async {
      final search = _FakeLeaseSearch()
        ..failure = LeasingRepositoryFailureKind.forbidden;
      final controller = _controller(search: search);
      await controller.load();

      expect(controller.state.listPhase, LeasesListPhase.forbidden);
    });

    test('an infrastructure failure lands in error with a message', () async {
      final search = _FakeLeaseSearch()
        ..failure = LeasingRepositoryFailureKind.infrastructureFailure;
      final controller = _controller(search: search);
      await controller.load();

      expect(controller.state.listPhase, LeasesListPhase.error);
      expect(controller.state.message, isNotNull);
    });

    test('an unresolved scope stays idle instead of calling the backend',
        () async {
      final search = _FakeLeaseSearch();
      final controller = _controller(
        search: search,
        scope: const WorkspaceSessionScope.unresolved(),
      );
      await controller.load();

      expect(controller.state.listPhase, LeasesListPhase.idle);
      expect(search.calls, 0);
    });

    test('every filter reaches the server rather than filtering locally',
        () async {
      final search = _FakeLeaseSearch()..leases = <LeaseSummaryDto>[_summary('l1')];
      final controller = _controller(search: search);
      await controller.load();

      await controller.setStatusFilter(LeaseStatus.active);
      await controller.setEffectiveOnly(true);
      await controller.setUnitFilter('u1');
      await controller.setTenantFilter('party-1');

      final last = search.queries.last;
      expect(last.propertyId, _property);
      expect(last.status, LeaseStatus.active);
      expect(last.effectiveOnly, isTrue);
      expect(last.unitId, 'u1');
      expect(last.tenantPartyId, 'party-1');
    });

    test('loadMore appends the next keyset page', () async {
      final search = _FakeLeaseSearch()
        ..leases = <LeaseSummaryDto>[_summary('l1')]
        ..nextCursor = 'l1';
      final controller = _controller(search: search);
      await controller.load();

      search
        ..leases = <LeaseSummaryDto>[_summary('l2')]
        ..nextCursor = null;
      await controller.loadMore();

      expect(controller.state.leases.map((lease) => lease.id), <String>[
        'l1',
        'l2',
      ]);
      expect(controller.state.hasMore, isFalse);
    });
  });

  group('companion reads', () {
    test('resolve the unit code and the tenant name for the list', () async {
      final units = _FakeUnitSearch()
        ..units = <UnitSummaryDto>[_unitSummary('u1', 'A-01')];
      final parties = _FakePartySearch()
        ..parties = <PartySummaryDto>[_party('party-1', 'Meier GmbH')];
      final controller = _controller(unitSearch: units, partySearch: parties);
      await controller.load();

      expect(controller.state.unitCodeFor('u1'), 'A-01');
      expect(controller.state.tenantNameFor('party-1'), 'Meier GmbH');
      // AGG-005: tenants are parties holding the tenant role, filtered
      // server-side — there is no tenants table to read instead.
      expect(parties.lastQuery?.roleType, PartyRoleType.tenant);
    });

    test('a failing companion read degrades to unresolved, not to a failed list',
        () async {
      final search = _FakeLeaseSearch()..leases = <LeaseSummaryDto>[_summary('l1')];
      final units = _FakeUnitSearch()
        ..failure = LeasingRepositoryFailureKind.infrastructureFailure;
      final parties = _FakePartySearch()..fails = true;
      final controller = _controller(
        search: search,
        unitSearch: units,
        partySearch: parties,
      );
      await controller.load();

      expect(controller.state.listPhase, LeasesListPhase.ready);
      expect(controller.state.unitCodeFor('u1'), isNull);
      expect(controller.state.tenantNameFor('party-1'), isNull);
    });
  });

  group('mutation gate', () {
    test('a read-only backend answers readOnly, not a failed mutation',
        () async {
      final repository = _FakeLeaseRepository();
      final controller = _controller(
        repository: repository,
        scope: _scope(mutationsSupported: false),
      );

      await controller.createLease(_draft());

      expect(controller.state.actionPhase, LeasesActionPhase.readOnly);
      expect(controller.state.actionMessage, contains('schreibgeschützt'));
      expect(repository.createCalls, 0);
    });

    test('a missing permission answers forbidden, distinct from readOnly',
        () async {
      final repository = _FakeLeaseRepository();
      final controller = _controller(
        repository: repository,
        scope: _scope(permissions: const <String>{'lease.read'}),
      );

      await controller.createLease(_draft());

      expect(controller.state.actionPhase, LeasesActionPhase.forbidden);
      expect(repository.createCalls, 0);
    });

    test('a version conflict carries the current lease for the resolve dialog',
        () async {
      // The likeliest real failure here: two sessions on the same lease.
      final repository = _FakeLeaseRepository()
        ..transitionResult = LeasingRepositoryFailure<LeaseDto>(
          kind: LeasingRepositoryFailureKind.versionConflict,
          message: 'stale',
          versionConflict: LeasingVersionConflict(
            expectedVersion: 1,
            actualVersion: 2,
            currentLease: _lease('l1', status: LeaseStatus.sent, version: 2),
          ),
        );
      final controller = _controller(repository: repository);

      await controller.advanceLease(lease: _lease('l1'));

      expect(controller.state.actionPhase, LeasesActionPhase.conflict);
      expect(controller.state.versionConflict?.currentLease?.version, 2);
    });
  });

  group('transitions', () {
    test('advancing sends the one lawful next step, never a chosen target',
        () async {
      final repository = _FakeLeaseRepository();
      final controller = _controller(repository: repository);

      await controller.advanceLease(
        lease: _lease('l1', status: LeaseStatus.landlordSigned),
      );

      expect(repository.lastTransition?.targetStatus, LeaseStatus.active);
      expect(repository.lastTransition?.moveOutDate, isNull);
      expect(controller.state.actionPhase, LeasesActionPhase.succeeded);
      expect(controller.state.actionMessage, contains('vermietet'));
    });

    test('a terminal lease offers no step and never reaches the server',
        () async {
      final repository = _FakeLeaseRepository();
      final controller = _controller(repository: repository);

      await controller.advanceLease(
        lease: _lease('l1', status: LeaseStatus.ended),
      );

      expect(controller.state.actionPhase, LeasesActionPhase.notAllowed);
      expect(controller.state.rejection?.from, LeaseStatus.ended);
      expect(repository.transitionCalls, 0);
    });

    test('a move-out date is only sent when ending the lease', () async {
      final repository = _FakeLeaseRepository();
      final controller = _controller(repository: repository);

      await controller.advanceLease(
        lease: _lease('l1', status: LeaseStatus.active),
        moveOutDate: DateTime.utc(2026, 9, 30),
      );

      expect(repository.lastTransition?.targetStatus, LeaseStatus.ended);
      expect(repository.lastTransition?.moveOutDate, DateTime.utc(2026, 9, 30));
    });

    test('a move-out date on any other step is refused before the round trip',
        () async {
      final repository = _FakeLeaseRepository();
      final controller = _controller(repository: repository);

      await controller.advanceLease(
        lease: _lease('l1', status: LeaseStatus.draft),
        moveOutDate: DateTime.utc(2026, 9, 30),
      );

      expect(controller.state.actionPhase, LeasesActionPhase.failed);
      expect(controller.state.actionMessage, contains('Auszugsdatum'));
      expect(repository.transitionCalls, 0);
    });

    test('cancelling without a reason never reaches the server', () async {
      final repository = _FakeLeaseRepository();
      final controller = _controller(repository: repository);

      await controller.cancelLease(lease: _lease('l1'), reason: '   ');

      expect(controller.state.actionPhase, LeasesActionPhase.failed);
      expect(controller.state.actionMessage, contains('Grund'));
      expect(repository.transitionCalls, 0);
    });

    test('the cancellation reason travels as the command reason', () async {
      final repository = _FakeLeaseRepository();
      final controller = _controller(repository: repository);

      await controller.cancelLease(
        lease: _lease('l1'),
        reason: '  Mieter zurückgetreten  ',
      );

      expect(repository.lastTransition?.targetStatus, LeaseStatus.cancelled);
      expect(
        repository.lastTransition?.context.reason,
        'Mieter zurückgetreten',
      );
    });

    test('a refused transition becomes an explained rejection, not an error',
        () async {
      final repository = _FakeLeaseRepository()
        ..transitionResult = const LeasingRepositoryFailure<LeaseDto>(
          kind: LeasingRepositoryFailureKind.validationFailed,
          message: 'STM-005 does not allow draft -> reviewed',
        );
      final controller = _controller(repository: repository);

      await controller.advanceLease(
        lease: _lease('l1', status: LeaseStatus.draft),
      );

      expect(controller.state.actionPhase, LeasesActionPhase.notAllowed);
      expect(controller.state.rejection?.from, LeaseStatus.draft);
      expect(controller.state.rejection?.attempted, LeaseStatus.reviewed);
      expect(controller.state.rejection?.serverMessage, isNotNull);
      // The view renders the rejection; there is deliberately no snackbar text.
      expect(controller.state.actionMessage, isNull);
    });
  });

  group('editing a binding lease', () {
    test('is refused locally with the reason, not attempted', () async {
      final repository = _FakeLeaseRepository();
      final controller = _controller(repository: repository);

      await controller.updateLease(
        lease: _lease('l1', status: LeaseStatus.active),
        changes: _changes(),
      );

      expect(controller.state.actionPhase, LeasesActionPhase.notAllowed);
      expect(controller.state.actionMessage, contains('neuer Vertrag'));
      expect(repository.updateCalls, 0);
    });

    test('is attempted while the lease is still a draft', () async {
      final repository = _FakeLeaseRepository();
      final controller = _controller(repository: repository);

      await controller.updateLease(
        lease: _lease('l1', status: LeaseStatus.draft),
        changes: _changes(),
      );

      expect(repository.updateCalls, 1);
      expect(controller.state.actionPhase, LeasesActionPhase.succeeded);
    });
  });

  group('realtime', () {
    test('one lease activation causes one refetch, not two', () async {
      // The migration publishes both tables on purpose: activating a lease
      // writes the lease and, via sync_unit_occupancy, its unit. The screen
      // must collapse that burst into a single refetch.
      final source = _FakeInvalidationSource();
      final search = _FakeLeaseSearch();
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

    test('a burst of lease events still causes one refetch', () async {
      final source = _FakeInvalidationSource();
      final search = _FakeLeaseSearch();
      final controller = _controller(
        search: search,
        invalidationSource: source,
        coalesceWindow: const Duration(milliseconds: 20),
      );
      await controller.load();
      final before = search.calls;

      for (var index = 0; index < 3; index++) {
        source.emit(
          LeasingQueryInvalidation(
            workspaceId: _workspace,
            aggregate: LeasingAggregate.lease,
            entityId: 'l$index',
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(search.calls - before, 1);
    });

    test('ignores another workspace entirely', () async {
      final source = _FakeInvalidationSource();
      final search = _FakeLeaseSearch();
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
          aggregate: LeasingAggregate.lease,
          entityId: 'l1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(search.calls - before, 0);
    });
  });

  group('detail', () {
    test('a missing lease is notFound, not a generic error', () async {
      final repository = _FakeLeaseRepository()
        ..getResult = const LeasingRepositoryFailure<LeaseDto>(
          kind: LeasingRepositoryFailureKind.notFound,
          message: 'gone',
        );
      final controller = _controller(repository: repository);

      await controller.select('l1');

      expect(controller.state.detailPhase, LeasesDetailPhase.notFound);
    });

    test('deselecting clears the panel and any pending rejection', () async {
      final repository = _FakeLeaseRepository()
        ..transitionResult = const LeasingRepositoryFailure<LeaseDto>(
          kind: LeasingRepositoryFailureKind.validationFailed,
          message: 'no',
        );
      final controller = _controller(repository: repository);
      await controller.select('l1');
      await controller.advanceLease(lease: _lease('l1'));
      await controller.select(null);

      expect(controller.state.detailPhase, LeasesDetailPhase.idle);
      expect(controller.state.selectedLease, isNull);
      expect(controller.state.rejection, isNull);
    });
  });
}

LeasesController _controller({
  _FakeLeaseRepository? repository,
  _FakeLeaseSearch? search,
  _FakeUnitSearch? unitSearch,
  _FakePartySearch? partySearch,
  WorkspaceSessionScope? scope,
  LeasingQueryInvalidationSource? invalidationSource,
  Duration coalesceWindow = const Duration(milliseconds: 250),
}) {
  var counter = 0;
  final controller = LeasesController(
    repository: repository ?? _FakeLeaseRepository(),
    search: search ?? _FakeLeaseSearch(),
    unitSearch: unitSearch ?? _FakeUnitSearch(),
    partySearch: partySearch ?? _FakePartySearch(),
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

LeaseDraft _draft() => LeaseDraft(
  unitId: 'u1',
  leaseName: 'Vertrag',
  startDate: DateTime.utc(2026, 1, 1),
  baseRentMonthly: 1000,
  currencyCode: 'EUR',
);

LeaseUpdateDto _changes() => LeaseUpdateDto(
  leaseName: 'Vertrag',
  startDate: DateTime.utc(2026, 1, 1),
  baseRentMonthly: 1100,
  billingFrequency: LeaseBillingFrequency.monthly,
);

LeaseSummaryDto _summary(String id) => LeaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitId: 'u1',
  leaseName: id.toUpperCase(),
  status: LeaseStatus.draft,
  startDate: DateTime.utc(2026, 1, 1),
  baseRentMonthly: 1000,
  currencyCode: 'EUR',
  version: 1,
);

LeaseDto _lease(
  String id, {
  LeaseStatus status = LeaseStatus.draft,
  int version = 1,
}) => LeaseDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitId: 'u1',
  leaseName: id.toUpperCase(),
  status: status,
  startDate: DateTime.utc(2026, 1, 1),
  baseRentMonthly: 1000,
  currencyCode: 'EUR',
  version: version,
  billingFrequency: LeaseBillingFrequency.monthly,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  createdBy: 'actor-1',
  updatedBy: 'actor-1',
);

UnitSummaryDto _unitSummary(String id, String code) => UnitSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitCode: code,
  status: UnitStatus.vacant,
  version: 1,
);

PartySummaryDto _party(String id, String name) => PartySummaryDto(
  id: id,
  workspaceId: _workspace,
  type: PartyType.organization,
  displayName: name,
  version: 1,
);

class _FakeLeaseSearch implements LeaseSearchPort {
  List<LeaseSummaryDto> leases = const <LeaseSummaryDto>[];
  String? nextCursor;
  LeasingRepositoryFailureKind? failure;
  final List<LeaseListQuery> queries = <LeaseListQuery>[];
  int calls = 0;

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
      LeasingPageResult<LeaseSummaryDto>(
        items: leases,
        nextCursor: nextCursor,
      ),
    );
  }
}

class _FakeUnitSearch implements UnitSearchPort {
  List<UnitSummaryDto> units = const <UnitSummaryDto>[];
  LeasingRepositoryFailureKind? failure;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<UnitSummaryDto>>> search(
    UnitListQuery query,
  ) async {
    final kind = failure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeasingPageResult<UnitSummaryDto>>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
      LeasingPageResult<UnitSummaryDto>(items: units),
    );
  }
}

class _FakePartySearch implements PartySearchPort {
  List<PartySummaryDto> parties = const <PartySummaryDto>[];
  bool fails = false;
  PartyListQuery? lastQuery;

  @override
  Future<PartyRepositoryResult<PartyPageResult>> search(
    PartyListQuery query,
  ) async {
    lastQuery = query;
    if (fails) {
      return const PartyRepositoryFailure<PartyPageResult>(
        kind: PartyRepositoryFailureKind.infrastructureFailure,
        message: 'failed',
      );
    }
    return PartyRepositorySuccess<PartyPageResult>(
      PartyPageResult(items: parties),
    );
  }
}

class _FakeLeaseRepository implements LeaseRepository {
  LeasingRepositoryResult<LeaseDto>? getResult;
  LeasingRepositoryResult<LeaseDto>? transitionResult;
  int createCalls = 0;
  int updateCalls = 0;
  int transitionCalls = 0;
  TransitionLeaseStatusCommand? lastTransition;

  @override
  Future<LeasingRepositoryResult<LeaseDto>> getById({
    required String workspaceId,
    required String leaseId,
  }) async {
    return getResult ?? LeasingRepositorySuccess<LeaseDto>(_lease(leaseId));
  }

  @override
  Future<LeasingRepositoryResult<LeaseDto>> create(
    CreateLeaseCommand command,
  ) async {
    createCalls++;
    return LeasingRepositorySuccess<LeaseDto>(_lease('l-new'));
  }

  @override
  Future<LeasingRepositoryResult<LeaseDto>> update(
    UpdateLeaseCommand command,
  ) async {
    updateCalls++;
    return LeasingRepositorySuccess<LeaseDto>(_lease(command.leaseId));
  }

  @override
  Future<LeasingRepositoryResult<LeaseDto>> transitionStatus(
    TransitionLeaseStatusCommand command,
  ) async {
    transitionCalls++;
    lastTransition = command;
    return transitionResult ??
        LeasingRepositorySuccess<LeaseDto>(
          _lease(command.leaseId, status: command.targetStatus),
        );
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
