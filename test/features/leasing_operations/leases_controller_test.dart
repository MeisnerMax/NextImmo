import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_repository.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leases_controller.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_query_invalidation_source.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_component_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/warm_rent_dto.dart';
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

    test(
      'cancelling is allowed from every non-terminal state and nowhere else',
      () {
        for (final from in LeaseStatus.values) {
          expect(
            from.canTransitionTo(LeaseStatus.cancelled),
            !from.isTerminal,
            reason: 'cancel from $from',
          );
        }
      },
    );

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
      final search =
          _FakeLeaseSearch()..failure = LeasingRepositoryFailureKind.forbidden;
      final controller = _controller(search: search);
      await controller.load();

      expect(controller.state.listPhase, LeasesListPhase.forbidden);
    });

    test('an infrastructure failure lands in error with a message', () async {
      final search =
          _FakeLeaseSearch()
            ..failure = LeasingRepositoryFailureKind.infrastructureFailure;
      final controller = _controller(search: search);
      await controller.load();

      expect(controller.state.listPhase, LeasesListPhase.error);
      expect(controller.state.message, isNotNull);
    });

    test(
      'an unresolved scope stays idle instead of calling the backend',
      () async {
        final search = _FakeLeaseSearch();
        final controller = _controller(
          search: search,
          scope: const WorkspaceSessionScope.unresolved(),
        );
        await controller.load();

        expect(controller.state.listPhase, LeasesListPhase.idle);
        expect(search.calls, 0);
      },
    );

    test(
      'every filter reaches the server rather than filtering locally',
      () async {
        final search =
            _FakeLeaseSearch()..leases = <LeaseSummaryDto>[_summary('l1')];
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
      },
    );

    test('loadMore appends the next keyset page', () async {
      final search =
          _FakeLeaseSearch()
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
      final units =
          _FakeUnitSearch()
            ..units = <UnitSummaryDto>[_unitSummary('u1', 'A-01')];
      final parties =
          _FakePartySearch()
            ..parties = <PartySummaryDto>[_party('party-1', 'Meier GmbH')];
      final controller = _controller(unitSearch: units, partySearch: parties);
      await controller.load();

      expect(controller.state.unitCodeFor('u1'), 'A-01');
      expect(controller.state.tenantNameFor('party-1'), 'Meier GmbH');
      // AGG-005: tenants are parties holding the tenant role, filtered
      // server-side — there is no tenants table to read instead.
      expect(parties.lastQuery?.roleType, PartyRoleType.tenant);
    });

    test(
      'a failing companion read degrades to unresolved, not to a failed list',
      () async {
        final search =
            _FakeLeaseSearch()..leases = <LeaseSummaryDto>[_summary('l1')];
        final units =
            _FakeUnitSearch()
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
      },
    );
  });

  group('mutation gate', () {
    test(
      'a read-only backend answers readOnly, not a failed mutation',
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
      },
    );

    test(
      'a missing permission answers forbidden, distinct from readOnly',
      () async {
        final repository = _FakeLeaseRepository();
        final controller = _controller(
          repository: repository,
          scope: _scope(permissions: const <String>{'lease.read'}),
        );

        await controller.createLease(_draft());

        expect(controller.state.actionPhase, LeasesActionPhase.forbidden);
        expect(repository.createCalls, 0);
      },
    );

    test(
      'a version conflict carries the current lease for the resolve dialog',
      () async {
        // The likeliest real failure here: two sessions on the same lease.
        final repository =
            _FakeLeaseRepository()
              ..transitionResult = LeasingRepositoryFailure<LeaseDto>(
                kind: LeasingRepositoryFailureKind.versionConflict,
                message: 'stale',
                versionConflict: LeasingVersionConflict(
                  expectedVersion: 1,
                  actualVersion: 2,
                  currentLease: _lease(
                    'l1',
                    status: LeaseStatus.sent,
                    version: 2,
                  ),
                ),
              );
        final controller = _controller(repository: repository);

        await controller.advanceLease(lease: _lease('l1'));

        expect(controller.state.actionPhase, LeasesActionPhase.conflict);
        expect(controller.state.versionConflict?.currentLease?.version, 2);
      },
    );
  });

  group('transitions', () {
    test(
      'advancing sends the one lawful next step, never a chosen target',
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
      },
    );

    test(
      'a terminal lease offers no step and never reaches the server',
      () async {
        final repository = _FakeLeaseRepository();
        final controller = _controller(repository: repository);

        await controller.advanceLease(
          lease: _lease('l1', status: LeaseStatus.ended),
        );

        expect(controller.state.actionPhase, LeasesActionPhase.notAllowed);
        expect(controller.state.rejection?.from, LeaseStatus.ended);
        expect(repository.transitionCalls, 0);
      },
    );

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

    test(
      'a move-out date on any other step is refused before the round trip',
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
      },
    );

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

    test(
      'a refused transition becomes an explained rejection, not an error',
      () async {
        final repository =
            _FakeLeaseRepository()
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
      },
    );
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
      final repository =
          _FakeLeaseRepository()
            ..getResult = const LeasingRepositoryFailure<LeaseDto>(
              kind: LeasingRepositoryFailureKind.notFound,
              message: 'gone',
            );
      final controller = _controller(repository: repository);

      await controller.select('l1');

      expect(controller.state.detailPhase, LeasesDetailPhase.notFound);
    });

    test('deselecting clears the panel and any pending rejection', () async {
      final repository =
          _FakeLeaseRepository()
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

    test(
      'selecting a lease loads its components, scoped to that lease',
      () async {
        final componentPort = _FakeLeaseComponents(
          components: <LeaseComponentDto>[
            LeaseComponentDto(
              id: 'k1',
              leaseId: 'l1',
              propertyId: _property,
              componentType: LeaseComponentType.baseRent,
              amount: 1000,
              currencyCode: 'EUR',
              vatMode: LeaseComponentVatMode.exempt,
              validFrom: DateTime(2026, 1, 1),
              version: 1,
            ),
          ],
        );
        final controller = _controller(componentPort: componentPort);

        await controller.select('l1');

        expect(controller.state.componentsPhase, LeaseComponentsPhase.ready);
        expect(controller.state.components?.components, hasLength(1));
        // Scoped to the lease, never to the workspace: an unscoped read would be
        // refused by the server and would be the wrong question anyway.
        expect(componentPort.queries.single.leaseId, 'l1');
        expect(componentPort.queries.single.propertyId, isNull);
      },
    );

    test('nothing recorded is a ready state, not an empty one', () async {
      final controller = _controller(componentPort: _FakeLeaseComponents());

      await controller.select('l1');

      // DEC-029: the read succeeded and the answer is "no component covers
      // today". Calling that a failure would invite the screen to fall back to
      // the flat inception figures, which is the confusion this package exists
      // to remove.
      expect(controller.state.componentsPhase, LeaseComponentsPhase.ready);
      expect(controller.state.components?.components, isEmpty);
    });

    test('a refused component read leaves the contract readable', () async {
      final controller = _controller(
        componentPort: _FakeLeaseComponents(
          failure: LeasingRepositoryFailureKind.forbidden,
        ),
      );

      await controller.select('l1');

      expect(controller.state.detailPhase, LeasesDetailPhase.ready);
      expect(controller.state.selectedLease, isNotNull);
      expect(controller.state.componentsPhase, LeaseComponentsPhase.forbidden);
    });

    test('a broken component read is an error, not a refusal', () async {
      final controller = _controller(
        componentPort: _FakeLeaseComponents(
          failure: LeasingRepositoryFailureKind.infrastructureFailure,
        ),
      );

      await controller.select('l1');

      // The two are different things to tell someone: one is "you may not",
      // the other is "try again".
      expect(controller.state.componentsPhase, LeaseComponentsPhase.error);
      expect(controller.state.detailPhase, LeasesDetailPhase.ready);
    });

    test('a lease that could not be read leaves components idle', () async {
      final repository =
          _FakeLeaseRepository()
            ..getResult = const LeasingRepositoryFailure<LeaseDto>(
              kind: LeasingRepositoryFailureKind.forbidden,
              message: 'no',
            );
      final componentPort = _FakeLeaseComponents();
      final controller = _controller(
        repository: repository,
        componentPort: componentPort,
      );

      await controller.select('l1');

      // No second message competing with the first, and no read fired for a
      // lease this member cannot see.
      expect(controller.state.componentsPhase, LeaseComponentsPhase.idle);
      expect(componentPort.queries, isEmpty);
    });

    test('deselecting clears the components too', () async {
      final controller = _controller(componentPort: _FakeLeaseComponents());
      await controller.select('l1');
      await controller.select(null);

      expect(controller.state.componentsPhase, LeaseComponentsPhase.idle);
      expect(controller.state.components, isNull);
    });

    test(
      'creating a component reloads the components, not the lease list',
      () async {
        final componentPort = _FakeLeaseComponents();
        final controller = _controller(componentPort: componentPort);
        await controller.select('l1');
        final readsBefore = componentPort.queries.length;

        await controller.createComponent(
          leaseId: 'l1',
          componentType: LeaseComponentType.baseRent,
          validFrom: DateTime(2026, 1, 1),
          amount: 1000,
        );

        expect(componentPort.created, hasLength(1));
        expect(
          componentPort.created.single.componentType,
          LeaseComponentType.baseRent,
        );
        // The read is the only thing that knows what is in force today.
        // Reproducing that decision in the controller is how two answers start
        // disagreeing.
        expect(componentPort.queries.length, readsBefore + 1);
        expect(controller.state.actionPhase, LeasesActionPhase.succeeded);
      },
    );

    test('an update with nothing changed is refused, not silently reported '
        'as saved', () async {
      final componentPort = _FakeLeaseComponents();
      final controller = _controller(componentPort: componentPort);
      await controller.select('l1');

      await controller.updateComponent(
        component: _componentDto(),
        changes: const <String, Object?>{},
      );

      expect(controller.state.actionPhase, LeasesActionPhase.notAllowed);
      expect(controller.state.actionMessage, 'Es wurde nichts geändert.');
      expect(
        componentPort.updated,
        isEmpty,
        reason:
            'a form that closes on Speichern while nothing was saved is '
            'the same lie whether or not a request was sent',
      );
    });

    test(
      'an update sends the expected version, so a stale form conflicts',
      () async {
        final componentPort = _FakeLeaseComponents();
        final controller = _controller(componentPort: componentPort);
        await controller.select('l1');

        await controller.updateComponent(
          component: _componentDto(version: 4),
          changes: const <String, Object?>{'amount': '1200'},
        );

        expect(componentPort.updated.single.expectedVersion, 4);
        expect(componentPort.updated.single.changes, <String, Object?>{
          'amount': '1200',
        });
      },
    );

    test('closing goes through the close command, not an update', () async {
      final componentPort = _FakeLeaseComponents();
      final controller = _controller(componentPort: componentPort);
      await controller.select('l1');

      await controller.closeComponent(
        component: _componentDto(),
        validTo: DateTime(2026, 4, 30),
      );

      // Ending a component and correcting its end date are different events,
      // and the audit trail only says so if the client calls the command that
      // means it.
      expect(componentPort.closed.single.validTo, DateTime(2026, 4, 30));
      expect(componentPort.updated, isEmpty);
      expect(
        controller.state.actionMessage,
        'Mietbestandteil beendet — er bleibt in der Historie.',
      );
    });

    test('warm rent is loaded beside the components, for the same date', () async {
      final componentPort = _FakeLeaseComponents();
      final warmRentPort = _FakeWarmRent(
        rows: <WarmRentDto>[
          const WarmRentDto(
            leaseId: 'l1',
            propertyId: _property,
            currencyCode: 'EUR',
            isWarm: true,
            netMonthly: 1040,
          ),
        ],
      );
      final controller = _controller(
        componentPort: componentPort,
        warmRentPort: warmRentPort,
      );

      await controller.select('l1');

      expect(controller.state.warmRent?.netMonthly, 1040);
      expect(controller.state.warmRent?.isWarm, isTrue);
      // The same date the components were read for. Two reads answering about
      // two different days would produce a total that does not match the rows
      // above it.
      expect(
        warmRentPort.queries.single.asOfDate,
        componentPort.queries.single.asOfDate,
      );
      expect(warmRentPort.queries.single.leaseId, 'l1');
    });

    test('deselecting clears the warm rent too', () async {
      final controller = _controller(
        warmRentPort: _FakeWarmRent(
          rows: <WarmRentDto>[
            const WarmRentDto(
              leaseId: 'l1',
              propertyId: _property,
              currencyCode: 'EUR',
              isWarm: true,
              netMonthly: 1040,
            ),
          ],
        ),
      );
      await controller.select('l1');
      expect(controller.state.warmRent, isNotNull);

      await controller.select(null);

      // Otherwise the next lease opens showing the previous lease's rent.
      expect(controller.state.warmRent, isNull);
    });

    test('a refused write becomes a typed action phase', () async {
      final componentPort = _FakeLeaseComponents(
        writeFailure: LeasingRepositoryFailureKind.dependencyConflict,
      );
      final controller = _controller(componentPort: componentPort);
      await controller.select('l1');

      await controller.createComponent(
        leaseId: 'l1',
        componentType: LeaseComponentType.baseRent,
        validFrom: DateTime(2026, 1, 1),
        amount: 1000,
      );

      // An overlapping period is a dependency conflict, which this controller
      // already maps to readOnly rather than to a generic failure.
      expect(controller.state.actionPhase, LeasesActionPhase.readOnly);
    });
  });

  group('component history (LEASING-COMPONENTS-02, V-2b)', () {
    test('is not loaded beside the contract', () async {
      final componentPort = _FakeLeaseComponents();
      final controller = _controller(componentPort: componentPort);

      await controller.select('l1');

      expect(
        componentPort.historyQueries,
        isEmpty,
        reason:
            'the history carries every period ever recorded and nobody '
            'needs it to see what is payable now',
      );
      expect(
        controller.state.componentHistoryPhase,
        LeaseComponentHistoryPhase.idle,
      );
      // The as-of read did run, so "isEmpty" above is about the history and
      // not about the fake never being called at all.
      expect(componentPort.queries, hasLength(1));
    });

    test('loads on demand and reaches the selected lease', () async {
      final componentPort = _FakeLeaseComponents();
      final controller = _controller(componentPort: componentPort);
      await controller.select('l1');

      await controller.loadComponentHistory();

      expect(componentPort.historyQueries.single.leaseId, 'l1');
      expect(
        controller.state.componentHistoryPhase,
        LeaseComponentHistoryPhase.ready,
      );
      expect(controller.state.componentHistory?.timelines, hasLength(1));
    });

    test('re-reads on every call rather than caching', () async {
      final componentPort = _FakeLeaseComponents();
      final controller = _controller(componentPort: componentPort);
      await controller.select('l1');

      await controller.loadComponentHistory();
      await controller.loadComponentHistory();

      expect(
        componentPort.historyQueries,
        hasLength(2),
        reason:
            'a component written since the dialog last opened would '
            'otherwise be missing from the very view whose job is to show the '
            'whole record',
      );
    });

    test(
      'a refused history is typed, and does not touch the components',
      () async {
        final componentPort =
            _FakeLeaseComponents()
              ..historyFailure = LeasingRepositoryFailureKind.forbidden;
        final controller = _controller(componentPort: componentPort);
        await controller.select('l1');

        await controller.loadComponentHistory();

        expect(
          controller.state.componentHistoryPhase,
          LeaseComponentHistoryPhase.forbidden,
        );
        expect(controller.state.componentHistory, isNull);
        expect(
          controller.state.componentsPhase,
          LeaseComponentsPhase.ready,
          reason:
              'the contract view keeps the components in force. A failed '
              'history must cost the dialog, not the screen behind it',
        );
      },
    );

    test('selecting another lease drops the history of the last one', () async {
      final componentPort = _FakeLeaseComponents();
      final controller = _controller(componentPort: componentPort);
      await controller.select('l1');
      await controller.loadComponentHistory();
      expect(controller.state.componentHistory, isNotNull);

      await controller.select('l2');

      expect(
        controller.state.componentHistory,
        isNull,
        reason:
            'a history belonging to the lease being left must not survive '
            'into the one being opened',
      );
      expect(
        controller.state.componentHistoryPhase,
        LeaseComponentHistoryPhase.idle,
      );
    });

    test('nothing is asked for when no lease is selected', () async {
      final componentPort = _FakeLeaseComponents();
      final controller = _controller(componentPort: componentPort);

      await controller.loadComponentHistory();

      expect(componentPort.historyQueries, isEmpty);
    });
  });
}

LeaseComponentDto _componentDto({int version = 1}) => LeaseComponentDto(
  id: 'k1',
  leaseId: 'l1',
  propertyId: _property,
  componentType: LeaseComponentType.baseRent,
  amount: 1000,
  currencyCode: 'EUR',
  vatMode: LeaseComponentVatMode.exempt,
  validFrom: DateTime(2026, 1, 1),
  version: version,
);

LeasesController _controller({
  _FakeLeaseRepository? repository,
  _FakeLeaseSearch? search,
  _FakeLeaseComponents? componentPort,
  _FakeWarmRent? warmRentPort,
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
    componentPort: componentPort ?? _FakeLeaseComponents(),
    warmRentPort: warmRentPort ?? _FakeWarmRent(),
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
      LeasingPageResult<LeaseSummaryDto>(items: leases, nextCursor: nextCursor),
    );
  }
}

/// Answers with nothing recorded unless a test says otherwise, which is the
/// state most leases are in until someone enters a component.
class _FakeLeaseComponents implements LeaseComponentPort {
  _FakeLeaseComponents({
    this.failure,
    this.writeFailure,
    this.components = const <LeaseComponentDto>[],
  });

  final LeasingRepositoryFailureKind? failure;
  final LeasingRepositoryFailureKind? writeFailure;
  final List<LeaseComponentDto> components;
  final List<LeaseComponentListQuery> queries = <LeaseComponentListQuery>[];
  final List<CreateLeaseComponentCommand> created =
      <CreateLeaseComponentCommand>[];
  final List<UpdateLeaseComponentCommand> updated =
      <UpdateLeaseComponentCommand>[];
  final List<CloseLeaseComponentCommand> closed =
      <CloseLeaseComponentCommand>[];

  LeasingRepositoryResult<LeaseComponentDto> _write() {
    final kind = writeFailure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeaseComponentDto>(
        kind: kind,
        message: 'write refused',
      );
    }
    return LeasingRepositorySuccess<LeaseComponentDto>(
      LeaseComponentDto(
        id: 'k1',
        leaseId: 'l1',
        propertyId: _property,
        componentType: LeaseComponentType.baseRent,
        amount: 1000,
        currencyCode: 'EUR',
        vatMode: LeaseComponentVatMode.exempt,
        validFrom: DateTime(2026, 1, 1),
        version: 1,
      ),
    );
  }

  final List<LeaseComponentHistoryQuery> historyQueries =
      <LeaseComponentHistoryQuery>[];
  LeasingRepositoryFailureKind? historyFailure;

  @override
  Future<LeasingRepositoryResult<LeaseComponentHistoryDto>> readHistory(
    LeaseComponentHistoryQuery query,
  ) async {
    historyQueries.add(query);
    final kind = historyFailure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeaseComponentHistoryDto>(
        kind: kind,
        message: 'history refused',
      );
    }
    return LeasingRepositorySuccess<LeaseComponentHistoryDto>(
      LeaseComponentHistoryDto(
        leaseId: query.leaseId,
        asOfDate: query.asOfDate ?? DateTime(2026, 9, 7),
        timelines: <LeaseComponentTimelineDto>[
          LeaseComponentTimelineDto(
            componentType: LeaseComponentType.baseRent,
            periods: <LeaseComponentPeriodDto>[
              LeaseComponentPeriodDto(
                id: 'h1',
                validFrom: DateTime(2025, 1, 1),
                amount: 900,
                currencyCode: 'EUR',
                vatMode: LeaseComponentVatMode.exempt,
                version: 1,
                inForce: true,
              ),
            ],
            gaps: const <LeaseComponentGap>[],
          ),
        ],
      ),
    );
  }

  @override
  Future<LeasingRepositoryResult<LeaseComponentsAsOfDto>> readAsOf(
    LeaseComponentListQuery query,
  ) async {
    queries.add(query);
    final kind = failure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeaseComponentsAsOfDto>(
        kind: kind,
        message: 'components failed',
      );
    }
    return LeasingRepositorySuccess<LeaseComponentsAsOfDto>(
      LeaseComponentsAsOfDto(asOfDate: query.asOfDate, components: components),
    );
  }

  @override
  Future<LeasingRepositoryResult<LeaseComponentDto>> create(
    CreateLeaseComponentCommand command,
  ) async {
    created.add(command);
    return _write();
  }

  @override
  Future<LeasingRepositoryResult<LeaseComponentDto>> update(
    UpdateLeaseComponentCommand command,
  ) async {
    updated.add(command);
    return _write();
  }

  @override
  Future<LeasingRepositoryResult<LeaseComponentDto>> close(
    CloseLeaseComponentCommand command,
  ) async {
    closed.add(command);
    return _write();
  }
}

/// Answers with nothing. Warm rent is the server's composition rule and has
/// its own tests; here it only has to exist, so a controller test never
/// accidentally asserts on a figure this fake invented.
class _FakeWarmRent implements WarmRentPort {
  _FakeWarmRent({this.rows = const <WarmRentDto>[]});

  final List<WarmRentDto> rows;
  final List<LeaseComponentListQuery> queries = <LeaseComponentListQuery>[];

  @override
  Future<LeasingRepositoryResult<List<WarmRentDto>>> readAsOf(
    LeaseComponentListQuery query,
  ) async {
    queries.add(query);
    return LeasingRepositorySuccess<List<WarmRentDto>>(rows);
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
