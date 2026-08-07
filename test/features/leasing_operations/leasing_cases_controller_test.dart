import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_repository.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_cases_controller.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_query_invalidation_source.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/leasing_case_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';

const String _workspace = 'workspace-a';
const String _property = 'property-a';

void main() {
  group('list phases', () {
    test('an empty result is its own phase, not an error', () async {
      final controller = _controller();
      await controller.load();

      expect(controller.state.listPhase, LeasingCasesListPhase.empty);
    });

    test('forbidden is distinct from error', () async {
      final search = _FakeCaseSearch()
        ..failure = LeasingRepositoryFailureKind.forbidden;
      final controller = _controller(search: search);
      await controller.load();

      expect(controller.state.listPhase, LeasingCasesListPhase.forbidden);
    });

    test('the board reads open cases only, server-side', () async {
      final search = _FakeCaseSearch()
        ..cases = <LeasingCaseSummaryDto>[_summary('c1')];
      final controller = _controller(search: search);
      await controller.load();

      expect(search.queries.first.openOnly, isTrue);
      expect(search.queries.first.propertyId, _property);

      await controller.setOpenOnly(false);
      expect(search.queries.last.openOnly, isFalse);
    });

    test('the stage filter reaches the server rather than filtering locally',
        () async {
      final search = _FakeCaseSearch()
        ..cases = <LeasingCaseSummaryDto>[_summary('c1')];
      final controller = _controller(search: search);
      await controller.load();

      await controller.setStageFilter(LeasingCaseStatus.viewing);

      expect(search.queries.last.status, LeasingCaseStatus.viewing);
    });
  });

  group('companion reads', () {
    test('the prospect directory is read unfiltered by role', () async {
      // A prospect holds no `tenant` role — there is no `prospect` role type,
      // and stamping an enquiry as a tenant would assert a relationship that
      // does not exist yet.
      final parties = _FakePartySearch()
        ..parties = <PartySummaryDto>[_party('p1', 'Meier')];
      final controller = _controller(partySearch: parties);
      await controller.load();

      expect(parties.lastQuery?.roleType, isNull);
      expect(controller.state.partyNameFor('p1'), 'Meier');
    });

    test('resolve unit code and produced lease for the board and detail',
        () async {
      final units = _FakeUnitSearch()
        ..units = <UnitSummaryDto>[_unit('u1', 'A-01')];
      final leases = _FakeLeaseSearch()
        ..leases = <LeaseSummaryDto>[_lease('l1', 'Vertrag Eins')];
      final controller = _controller(unitSearch: units, leaseSearch: leases);
      await controller.load();

      expect(controller.state.unitCodeFor('u1'), 'A-01');
      expect(controller.state.leaseNameFor('l1'), 'Vertrag Eins');
    });

    test('the lease choice for a case is scoped to its unit', () async {
      final leases = _FakeLeaseSearch()
        ..leases = <LeaseSummaryDto>[
          _lease('l1', 'Einheit A', unitId: 'u1'),
          _lease('l2', 'Einheit B', unitId: 'u2'),
        ];
      final controller = _controller(leaseSearch: leases);
      await controller.load();

      final scoped = controller.state.leasesForCase(
        _case('c1', status: LeasingCaseStatus.contractDraft, unitId: 'u1'),
      );
      expect(scoped.map((lease) => lease.id), <String>['l1']);
    });
  });

  group('STM-004 — one step forward, never back', () {
    test('advancing sends exactly the next stage', () async {
      final repository = _FakeCaseRepository();
      final controller = _controller(repository: repository);

      await controller.advanceCase(
        leasingCase: _case('c1', status: LeasingCaseStatus.inquiry),
      );

      expect(repository.lastTransition?.targetStatus, LeasingCaseStatus.contact);
    });

    test('a terminal case offers no step and never reaches the server',
        () async {
      final repository = _FakeCaseRepository();
      final controller = _controller(repository: repository);

      await controller.advanceCase(
        leasingCase: _case('c1', status: LeasingCaseStatus.completed),
      );

      expect(controller.state.actionPhase, LeasingCasesActionPhase.blocked);
      expect(controller.state.refusal?.attempted, isNull);
      expect(repository.transitionCalls, 0);
    });

    test('a missing prospect blocks the step with its reason, not a rejection',
        () async {
      final repository = _FakeCaseRepository();
      final controller = _controller(repository: repository);

      await controller.advanceCase(
        // documentsPending -> screening needs a prospect.
        leasingCase: _case('c1', status: LeasingCaseStatus.documentsPending),
      );

      expect(controller.state.actionPhase, LeasingCasesActionPhase.blocked);
      expect(
        controller.state.refusal?.blockedReason,
        LeasingCaseBlockedReason.prospectRequired,
      );
      expect(repository.transitionCalls, 0);
    });

    test('a missing unit blocks the step into the offer stage', () async {
      final repository = _FakeCaseRepository();
      final controller = _controller(repository: repository);

      await controller.advanceCase(
        leasingCase: _case(
          'c1',
          status: LeasingCaseStatus.screening,
          prospectPartyId: 'p1',
        ),
      );

      expect(
        controller.state.refusal?.blockedReason,
        LeasingCaseBlockedReason.unitRequired,
      );
      expect(repository.transitionCalls, 0);
    });

    test('the step into signed carries the named lease and unblocks it',
        () async {
      final repository = _FakeCaseRepository();
      final controller = _controller(repository: repository);

      await controller.advanceCase(
        leasingCase: _case(
          'c1',
          status: LeasingCaseStatus.contractDraft,
          prospectPartyId: 'p1',
          unitId: 'u1',
        ),
        leaseId: 'l1',
      );

      expect(repository.lastTransition?.targetStatus, LeasingCaseStatus.signed);
      expect(repository.lastTransition?.leaseId, 'l1');
      expect(controller.state.actionPhase, LeasingCasesActionPhase.succeeded);
    });

    test('the step into signed without a lease is blocked before the round trip',
        () async {
      final repository = _FakeCaseRepository();
      final controller = _controller(repository: repository);

      await controller.advanceCase(
        leasingCase: _case(
          'c1',
          status: LeasingCaseStatus.contractDraft,
          prospectPartyId: 'p1',
          unitId: 'u1',
        ),
      );

      expect(
        controller.state.refusal?.blockedReason,
        LeasingCaseBlockedReason.leaseRequired,
      );
      expect(repository.transitionCalls, 0);
    });

    test('cancelling without a reason never reaches the server', () async {
      final repository = _FakeCaseRepository();
      final controller = _controller(repository: repository);

      await controller.cancelCase(leasingCase: _case('c1'), reason: '  ');

      expect(controller.state.actionPhase, LeasingCasesActionPhase.failed);
      expect(repository.transitionCalls, 0);
    });

    test('the cancellation reason travels as the command reason', () async {
      final repository = _FakeCaseRepository();
      final controller = _controller(repository: repository);

      await controller.cancelCase(
        leasingCase: _case('c1', status: LeasingCaseStatus.screening),
        reason: '  Bonität nicht ausreichend  ',
      );

      expect(
        repository.lastTransition?.targetStatus,
        LeasingCaseStatus.cancelled,
      );
      expect(
        repository.lastTransition?.context.reason,
        'Bonität nicht ausreichend',
      );
    });

    test('a server-refused step becomes an explained refusal', () async {
      final repository = _FakeCaseRepository()
        ..transitionResult = const LeasingRepositoryFailure<LeasingCaseDto>(
          kind: LeasingRepositoryFailureKind.validationFailed,
          message: 'STM-004 does not allow inquiry -> contact',
        );
      final controller = _controller(repository: repository);

      await controller.advanceCase(leasingCase: _case('c1'));

      expect(controller.state.actionPhase, LeasingCasesActionPhase.blocked);
      expect(controller.state.refusal?.from, LeasingCaseStatus.inquiry);
      expect(controller.state.refusal?.attempted, LeasingCaseStatus.contact);
      expect(controller.state.actionMessage, isNull);
    });
  });

  group('mutation gate', () {
    test('a read-only backend answers readOnly, not a failed mutation',
        () async {
      final repository = _FakeCaseRepository();
      final controller = _controller(
        repository: repository,
        scope: _scope(mutationsSupported: false),
      );

      await controller.createCase(
        const LeasingCaseDraft(propertyId: _property, caseName: 'Anfrage'),
      );

      expect(controller.state.actionPhase, LeasingCasesActionPhase.readOnly);
      expect(repository.createCalls, 0);
    });

    test('a missing permission answers forbidden, distinct from readOnly',
        () async {
      final repository = _FakeCaseRepository();
      final controller = _controller(
        repository: repository,
        scope: _scope(permissions: const <String>{'lease.read'}),
      );

      await controller.createCase(
        const LeasingCaseDraft(propertyId: _property, caseName: 'Anfrage'),
      );

      expect(controller.state.actionPhase, LeasingCasesActionPhase.forbidden);
      expect(repository.createCalls, 0);
    });

    test('a closed case is history and is not edited afterwards', () async {
      final repository = _FakeCaseRepository();
      final controller = _controller(repository: repository);

      await controller.updateCase(
        leasingCase: _case('c1', status: LeasingCaseStatus.cancelled),
        changes: const LeasingCaseUpdateDto(caseName: 'neu'),
      );

      expect(controller.state.actionPhase, LeasingCasesActionPhase.blocked);
      expect(repository.updateCalls, 0);
    });

    test('a version conflict carries the current case for the resolve dialog',
        () async {
      final repository = _FakeCaseRepository()
        ..transitionResult = LeasingRepositoryFailure<LeasingCaseDto>(
          kind: LeasingRepositoryFailureKind.versionConflict,
          message: 'stale',
          versionConflict: LeasingVersionConflict(
            expectedVersion: 1,
            actualVersion: 4,
            currentCase: _case('c1', version: 4),
          ),
        );
      final controller = _controller(repository: repository);

      await controller.advanceCase(leasingCase: _case('c1'));

      expect(controller.state.actionPhase, LeasingCasesActionPhase.conflict);
      expect(controller.state.versionConflict?.currentCase?.version, 4);
    });
  });

  group('realtime', () {
    test('a case reaching signed causes one refetch, not two', () async {
      // Naming the lease a case produced touches both published tables; the
      // migration says clients must collapse that.
      final source = _FakeInvalidationSource();
      final search = _FakeCaseSearch();
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
          aggregate: LeasingAggregate.leasingCase,
          entityId: 'c1',
        ),
      );
      source.emit(
        const LeasingQueryInvalidation(
          workspaceId: _workspace,
          aggregate: LeasingAggregate.lease,
          entityId: 'l1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(search.calls - before, 1);
    });

    test('ignores events that cannot change the pipeline', () async {
      final source = _FakeInvalidationSource();
      final search = _FakeCaseSearch();
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
  });

  group('detail', () {
    test('a missing case is notFound, not a generic error', () async {
      final repository = _FakeCaseRepository()
        ..getResult = const LeasingRepositoryFailure<LeasingCaseDto>(
          kind: LeasingRepositoryFailureKind.notFound,
          message: 'gone',
        );
      final controller = _controller(repository: repository);

      await controller.select('c1');

      expect(controller.state.detailPhase, LeasingCasesDetailPhase.notFound);
    });
  });
}

LeasingCasesController _controller({
  _FakeCaseRepository? repository,
  _FakeCaseSearch? search,
  _FakeUnitSearch? unitSearch,
  _FakeLeaseSearch? leaseSearch,
  _FakePartySearch? partySearch,
  WorkspaceSessionScope? scope,
  LeasingQueryInvalidationSource? invalidationSource,
  Duration coalesceWindow = const Duration(milliseconds: 250),
}) {
  var counter = 0;
  final controller = LeasingCasesController(
    repository: repository ?? _FakeCaseRepository(),
    search: search ?? _FakeCaseSearch(),
    unitSearch: unitSearch ?? _FakeUnitSearch(),
    leaseSearch: leaseSearch ?? _FakeLeaseSearch(),
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

LeasingCaseSummaryDto _summary(String id) => LeasingCaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  caseName: id.toUpperCase(),
  status: LeasingCaseStatus.inquiry,
  source: LeasingCaseSource.portal,
  openedAt: DateTime.utc(2026, 1, 1),
  version: 1,
);

LeasingCaseDto _case(
  String id, {
  LeasingCaseStatus status = LeasingCaseStatus.inquiry,
  String? unitId,
  String? prospectPartyId,
  String? leaseId,
  int version = 1,
}) => LeasingCaseDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  caseName: id.toUpperCase(),
  status: status,
  source: LeasingCaseSource.portal,
  openedAt: DateTime.utc(2026, 1, 1),
  version: version,
  unitId: unitId,
  prospectPartyId: prospectPartyId,
  leaseId: leaseId,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  createdBy: 'actor-1',
  updatedBy: 'actor-1',
);

UnitSummaryDto _unit(String id, String code) => UnitSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitCode: code,
  status: UnitStatus.vacant,
  version: 1,
);

LeaseSummaryDto _lease(String id, String name, {String unitId = 'u1'}) =>
    LeaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitId: unitId,
  leaseName: name,
  status: LeaseStatus.draft,
  startDate: DateTime.utc(2026, 1, 1),
  baseRentMonthly: 1000,
  currencyCode: 'EUR',
  version: 1,
);

PartySummaryDto _party(String id, String name) => PartySummaryDto(
  id: id,
  workspaceId: _workspace,
  type: PartyType.person,
  displayName: name,
  version: 1,
);

class _FakeCaseSearch implements LeasingCaseSearchPort {
  List<LeasingCaseSummaryDto> cases = const <LeasingCaseSummaryDto>[];
  LeasingRepositoryFailureKind? failure;
  final List<LeasingCaseListQuery> queries = <LeasingCaseListQuery>[];
  int calls = 0;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeasingCaseSummaryDto>>>
  search(LeasingCaseListQuery query) async {
    calls++;
    queries.add(query);
    final kind = failure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeasingPageResult<LeasingCaseSummaryDto>>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<LeasingPageResult<LeasingCaseSummaryDto>>(
      LeasingPageResult<LeasingCaseSummaryDto>(items: cases),
    );
  }
}

class _FakeUnitSearch implements UnitSearchPort {
  List<UnitSummaryDto> units = const <UnitSummaryDto>[];

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<UnitSummaryDto>>> search(
    UnitListQuery query,
  ) async {
    return LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
      LeasingPageResult<UnitSummaryDto>(items: units),
    );
  }
}

class _FakeLeaseSearch implements LeaseSearchPort {
  List<LeaseSummaryDto> leases = const <LeaseSummaryDto>[];

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeaseSummaryDto>>> search(
    LeaseListQuery query,
  ) async {
    return LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
      LeasingPageResult<LeaseSummaryDto>(items: leases),
    );
  }
}

class _FakePartySearch implements PartySearchPort {
  List<PartySummaryDto> parties = const <PartySummaryDto>[];
  PartyListQuery? lastQuery;

  @override
  Future<PartyRepositoryResult<PartyPageResult>> search(
    PartyListQuery query,
  ) async {
    lastQuery = query;
    return PartyRepositorySuccess<PartyPageResult>(
      PartyPageResult(items: parties),
    );
  }
}

class _FakeCaseRepository implements LeasingCaseRepository {
  LeasingRepositoryResult<LeasingCaseDto>? getResult;
  LeasingRepositoryResult<LeasingCaseDto>? transitionResult;
  int createCalls = 0;
  int updateCalls = 0;
  int transitionCalls = 0;
  TransitionLeasingCaseStatusCommand? lastTransition;

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> getById({
    required String workspaceId,
    required String caseId,
  }) async {
    return getResult ?? LeasingRepositorySuccess<LeasingCaseDto>(_case(caseId));
  }

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> create(
    CreateLeasingCaseCommand command,
  ) async {
    createCalls++;
    return LeasingRepositorySuccess<LeasingCaseDto>(_case('c-new'));
  }

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> update(
    UpdateLeasingCaseCommand command,
  ) async {
    updateCalls++;
    return LeasingRepositorySuccess<LeasingCaseDto>(_case(command.caseId));
  }

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> transitionStatus(
    TransitionLeasingCaseStatusCommand command,
  ) async {
    transitionCalls++;
    lastTransition = command;
    return transitionResult ??
        LeasingRepositorySuccess<LeasingCaseDto>(
          _case(command.caseId, status: command.targetStatus),
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
