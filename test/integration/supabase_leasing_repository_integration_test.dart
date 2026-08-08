import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_repository_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/leasing_case_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/rent_roll_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';

import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const workspaceId = 'e1000000-0000-0000-0000-000000000001';
  const propertyId = 'e5000000-0000-0000-0000-000000000001';
  const managerId = 'ea000000-0000-0000-0000-000000000001';
  const tenantOneId = 'e6000000-0000-0000-0000-000000000001';
  const tenantTwoId = 'e6000000-0000-0000-0000-000000000002';

  var mutationCounter = 0;
  LeasingCommandContext context({String? reason}) {
    mutationCounter++;
    final suffix = mutationCounter.toString().padLeft(3, '0');
    return LeasingCommandContext(
      workspaceId: workspaceId,
      actorId: managerId,
      mutationId: 'e8000000-0000-0000-0000-000000000$suffix',
      correlationId: 'e9000000-0000-0000-0000-000000000$suffix',
      reason: reason,
    );
  }

  test(
    'real client drives the leasing lifecycle end to end',
    () async {
      expect(url, isNotEmpty, reason: 'SUPABASE_URL dart define is required.');
      expect(
        publishableKey,
        isNotEmpty,
        reason: 'SUPABASE_PUBLISHABLE_KEY dart define is required.',
      );
      expect(
        Uri.tryParse(url)?.host,
        anyOf('127.0.0.1', 'localhost', '::1'),
        reason: 'This integration test is restricted to local Supabase.',
      );

      final managerClient = createSupabaseTestClient(url, publishableKey);
      final viewerClient = createSupabaseTestClient(url, publishableKey);
      try {
        await managerClient.auth.signInWithPassword(
          email: 'p2-d05-manager@example.test',
          password: 'NexImmo-Test-2026!',
        );
        final units = SupabaseUnitRepositoryAdapter(client: managerClient);
        final leases = SupabaseLeaseRepositoryAdapter(client: managerClient);
        final cases = SupabaseLeasingCaseRepositoryAdapter(
          client: managerClient,
        );
        final rentRoll = SupabaseRentRollAdapter(client: managerClient);

        // --- Units (STM-003, AGG-004) ------------------------------------

        final unitA = _success<UnitDto>(
          await units.create(
            CreateUnitCommand(
              context: context(reason: 'integration create'),
              draft: const UnitDraft(
                propertyId: propertyId,
                unitCode: 'A-01',
                areaSqm: 72.5,
                rooms: 3,
                targetRentMonthly: 1100,
                currencyCode: 'EUR',
              ),
            ),
          ),
        );
        expect(unitA.version, 1);
        // A unit with no lease is vacant, by AGG-004's definition.
        expect(unitA.status, UnitStatus.vacant);

        final unitB = _success<UnitDto>(
          await units.create(
            CreateUnitCommand(
              context: context(),
              draft: const UnitDraft(
                propertyId: propertyId,
                unitCode: 'A-02',
                areaSqm: 48,
                rooms: 2,
              ),
            ),
          ),
        );

        // Occupancy is derived, so asking for it directly is refused.
        final askedForOccupied = await units.transitionStatus(
          TransitionUnitStatusCommand(
            context: context(),
            unitId: unitB.id,
            expectedVersion: unitB.version,
            targetStatus: UnitStatus.occupied,
          ),
        );
        expect(
          _failure(askedForOccupied).kind,
          LeasingRepositoryFailureKind.validationFailed,
        );

        // Going offline is caller-driven and must carry a reason.
        final offlineWithoutReason = await units.transitionStatus(
          TransitionUnitStatusCommand(
            context: context(),
            unitId: unitB.id,
            expectedVersion: unitB.version,
            targetStatus: UnitStatus.offline,
          ),
        );
        expect(
          _failure(offlineWithoutReason).kind,
          LeasingRepositoryFailureKind.validationFailed,
        );

        final offline = _success<UnitDto>(
          await units.transitionStatus(
            TransitionUnitStatusCommand(
              context: context(reason: 'Wasserschaden'),
              unitId: unitB.id,
              expectedVersion: unitB.version,
              targetStatus: UnitStatus.offline,
            ),
          ),
        );
        expect(offline.status, UnitStatus.offline);
        // The command reason IS the offline reason — one value, one fact.
        expect(offline.offlineReason, 'Wasserschaden');

        // --- Leases (STM-005) --------------------------------------------

        final leaseOne = _success<LeaseDto>(
          await leases.create(
            CreateLeaseCommand(
              context: context(),
              draft: LeaseDraft(
                unitId: unitA.id,
                leaseName: 'Vertrag Eins',
                startDate: DateTime.utc(2026, 1, 1),
                baseRentMonthly: 1000,
                currencyCode: 'EUR',
                tenantPartyId: tenantOneId,
                ancillaryChargesMonthly: 150,
                parkingOtherChargesMonthly: 50,
              ),
            ),
          ),
        );
        expect(leaseOne.status, LeaseStatus.draft);
        expect(leaseOne.totalRentMonthly, 1200);

        // STM-005 moves one step at a time; skipping is refused.
        final skipped = await leases.transitionStatus(
          TransitionLeaseStatusCommand(
            context: context(),
            leaseId: leaseOne.id,
            expectedVersion: leaseOne.version,
            targetStatus: LeaseStatus.active,
          ),
        );
        expect(
          _failure(skipped).kind,
          LeasingRepositoryFailureKind.validationFailed,
        );

        final activeOne = await _walkToActive(leases, context, leaseOne);
        expect(activeOne.status, LeaseStatus.active);

        // AGG-004: the unit followed the lease without being asked to.
        final occupiedA = _success<UnitDto>(
          await units.getById(workspaceId: workspaceId, unitId: unitA.id),
        );
        expect(occupiedA.status, UnitStatus.occupied);

        // OPN-DOM-001: a second concurrently effective lease on the same unit
        // is allowed — this is the decision that was explicitly overridden.
        final leaseTwo = _success<LeaseDto>(
          await leases.create(
            CreateLeaseCommand(
              context: context(),
              draft: LeaseDraft(
                unitId: unitA.id,
                leaseName: 'Vertrag Zwei (Teilflaeche)',
                startDate: DateTime.utc(2026, 1, 1),
                baseRentMonthly: 400,
                currencyCode: 'EUR',
                tenantPartyId: tenantTwoId,
                ancillaryChargesMonthly: 30,
              ),
            ),
          ),
        );
        final activeTwo = await _walkToActive(leases, context, leaseTwo);
        expect(activeTwo.status, LeaseStatus.active);

        final unitLeases = _successPage<LeaseSummaryDto>(
          await leases.search(
            LeaseListQuery(
              workspaceId: workspaceId,
              unitId: unitA.id,
              effectiveOnly: true,
            ),
          ),
        );
        expect(unitLeases.items, hasLength(2));

        // A stale expected version returns a structured conflict carrying the
        // current lease, not a bare error.
        final stale = await leases.update(
          UpdateLeaseCommand(
            context: context(),
            leaseId: leaseOne.id,
            expectedVersion: leaseOne.version,
            changes: LeaseUpdateDto(
              leaseName: 'Umbenannt',
              startDate: DateTime.utc(2026, 1, 1),
              baseRentMonthly: 1000,
              billingFrequency: LeaseBillingFrequency.monthly,
            ),
          ),
        );
        final conflict = _failure(stale);
        expect(conflict.kind, LeasingRepositoryFailureKind.versionConflict);
        expect(
          conflict.versionConflict?.currentLease?.version,
          activeOne.version,
        );
        // The conflict names the entity it belongs to and only that one.
        expect(conflict.versionConflict?.currentUnit, isNull);
        expect(conflict.versionConflict?.currentCase, isNull);

        // --- Live rent roll (P2-D05b) ------------------------------------
        //
        // The golden path of the rent roll surface starts here: an operator
        // opens the property and sees the current state without freezing
        // anything first.

        final live = _success<RentRollLiveDto>(
          await rentRoll.readLive(
            workspaceId: workspaceId,
            propertyId: propertyId,
            asOfDate: DateTime.utc(2026, 3, 31),
          ),
        );
        expect(live.currencyCode, 'EUR');
        expect(live.unitCount, 2);
        expect(live.occupiedUnitCount, 1);
        expect(live.offlineUnitCount, 1);
        expect(live.effectiveLeaseCount, 2);
        // OPN-DOM-001: one line per unit, summed over both effective leases.
        final liveOccupied = live.lines.firstWhere(
          (line) => line.unitId == unitA.id,
        );
        expect(liveOccupied.effectiveLeaseCount, 2);
        expect(liveOccupied.totalRentMonthly, 1630);
        expect(live.occupancyRate, 0.5);

        // --- Rent roll (AGG-007) -----------------------------------------

        final snapshot = _success<RentRollSnapshotDto>(
          await rentRoll.createSnapshot(
            CreateRentRollSnapshotCommand(
              context: context(reason: 'integration rent roll'),
              propertyId: propertyId,
              asOfDate: DateTime.utc(2026, 3, 31),
            ),
          ),
        );
        expect(snapshot.currencyCode, 'EUR');
        expect(snapshot.unitCount, 2);
        expect(snapshot.occupiedUnitCount, 1);
        expect(snapshot.offlineUnitCount, 1);
        expect(snapshot.vacantUnitCount, 0);
        expect(snapshot.effectiveLeaseCount, 2);
        // OPN-DOM-001 again: one line per unit, summed over both leases.
        expect(snapshot.totalBaseRentMonthly, 1400);
        expect(snapshot.totalRentMonthly, 1630);
        final occupiedLine = snapshot.lines.firstWhere(
          (line) => line.unitId == unitA.id,
        );
        expect(occupiedLine.effectiveLeaseCount, 2);
        expect(occupiedLine.totalRentMonthly, 1630);
        expect(snapshot.occupancyRate, 0.5);

        // P2-D05b's load-bearing claim, over the real client this time: the
        // live read and the frozen document are built from the same helpers, so
        // for the same date on unchanged data they agree figure for figure. If
        // this ever diverges, one of the two has drifted.
        expect(live.unitCount, snapshot.unitCount);
        expect(live.occupiedUnitCount, snapshot.occupiedUnitCount);
        expect(live.vacantUnitCount, snapshot.vacantUnitCount);
        expect(live.offlineUnitCount, snapshot.offlineUnitCount);
        expect(live.effectiveLeaseCount, snapshot.effectiveLeaseCount);
        expect(live.totalBaseRentMonthly, snapshot.totalBaseRentMonthly);
        expect(live.totalRentMonthly, snapshot.totalRentMonthly);
        expect(
          live.lines.map((line) => line.unitCode).toList(),
          snapshot.lines.map((line) => line.unitCode).toList(),
        );

        // AGG-007 is immutable but deliberately NOT unique per period: a second
        // snapshot for the same date is lawful, and both are listed.
        final secondSnapshot = _success<RentRollSnapshotDto>(
          await rentRoll.createSnapshot(
            CreateRentRollSnapshotCommand(
              context: context(),
              propertyId: propertyId,
              asOfDate: DateTime.utc(2026, 3, 31),
            ),
          ),
        );
        expect(secondSnapshot.id, isNot(snapshot.id));

        final snapshots = _successPage<RentRollSnapshotDto>(
          await rentRoll.listSnapshots(
            const RentRollSnapshotListQuery(
              workspaceId: workspaceId,
              propertyId: propertyId,
            ),
          ),
        );
        expect(snapshots.items.map((item) => item.id), containsAll(<String>[
          snapshot.id,
          secondSnapshot.id,
        ]));
        // The list projection carries headers only.
        expect(snapshots.items.first.lines, isEmpty);

        final reread = _success<RentRollSnapshotDto>(
          await rentRoll.getSnapshot(
            workspaceId: workspaceId,
            snapshotId: snapshot.id,
          ),
        );
        expect(reread.lines, hasLength(2));

        // --- Leasing cases (STM-004) --------------------------------------

        final leasingCase = _success<LeasingCaseDto>(
          await cases.create(
            CreateLeasingCaseCommand(
              context: context(),
              draft: LeasingCaseDraft(
                propertyId: propertyId,
                caseName: 'Anfrage A-02',
                unitId: unitB.id,
                source: LeasingCaseSource.walkIn,
              ),
            ),
          ),
        );
        expect(leasingCase.status, LeasingCaseStatus.inquiry);
        expect(leasingCase.source, LeasingCaseSource.walkIn);

        final twoSteps = await cases.transitionStatus(
          TransitionLeasingCaseStatusCommand(
            context: context(),
            caseId: leasingCase.id,
            expectedVersion: leasingCase.version,
            targetStatus: LeasingCaseStatus.viewing,
          ),
        );
        expect(
          _failure(twoSteps).kind,
          LeasingRepositoryFailureKind.validationFailed,
        );

        final contacted = _success<LeasingCaseDto>(
          await cases.transitionStatus(
            TransitionLeasingCaseStatusCommand(
              context: context(),
              caseId: leasingCase.id,
              expectedVersion: leasingCase.version,
              targetStatus: LeasingCaseStatus.contact,
            ),
          ),
        );
        expect(contacted.status, LeasingCaseStatus.contact);

        final viewed = _success<LeasingCaseDto>(
          await cases.transitionStatus(
            TransitionLeasingCaseStatusCommand(
              context: context(),
              caseId: leasingCase.id,
              expectedVersion: contacted.version,
              targetStatus: LeasingCaseStatus.viewing,
            ),
          ),
        );
        final documentsPending = _success<LeasingCaseDto>(
          await cases.transitionStatus(
            TransitionLeasingCaseStatusCommand(
              context: context(),
              caseId: leasingCase.id,
              expectedVersion: viewed.version,
              targetStatus: LeasingCaseStatus.documentsPending,
            ),
          ),
        );
        // Screening needs a prospect; the client mirror says so before the call.
        expect(
          documentsPending.blockedReason,
          LeasingCaseBlockedReason.prospectRequired,
        );
        final withoutProspect = await cases.transitionStatus(
          TransitionLeasingCaseStatusCommand(
            context: context(),
            caseId: leasingCase.id,
            expectedVersion: documentsPending.version,
            targetStatus: LeasingCaseStatus.screening,
          ),
        );
        expect(
          _failure(withoutProspect).kind,
          LeasingRepositoryFailureKind.validationFailed,
        );

        final withProspect = _success<LeasingCaseDto>(
          await cases.update(
            UpdateLeasingCaseCommand(
              context: context(),
              caseId: leasingCase.id,
              expectedVersion: documentsPending.version,
              changes: const LeasingCaseUpdateDto(
                prospectPartyId: tenantTwoId,
              ),
            ),
          ),
        );
        expect(withProspect.blockedReason, isNull);

        final screening = _success<LeasingCaseDto>(
          await cases.transitionStatus(
            TransitionLeasingCaseStatusCommand(
              context: context(),
              caseId: leasingCase.id,
              expectedVersion: withProspect.version,
              targetStatus: LeasingCaseStatus.screening,
            ),
          ),
        );
        expect(screening.status, LeasingCaseStatus.screening);

        // Cancelling is the abort edge and must carry a reason.
        final cancelWithoutReason = await cases.transitionStatus(
          TransitionLeasingCaseStatusCommand(
            context: context(),
            caseId: leasingCase.id,
            expectedVersion: screening.version,
            targetStatus: LeasingCaseStatus.cancelled,
          ),
        );
        expect(
          _failure(cancelWithoutReason).kind,
          LeasingRepositoryFailureKind.validationFailed,
        );

        final cancelled = _success<LeasingCaseDto>(
          await cases.transitionStatus(
            TransitionLeasingCaseStatusCommand(
              context: context(reason: 'Bonitaet nicht ausreichend'),
              caseId: leasingCase.id,
              expectedVersion: screening.version,
              targetStatus: LeasingCaseStatus.cancelled,
            ),
          ),
        );
        expect(cancelled.status, LeasingCaseStatus.cancelled);
        expect(cancelled.cancelledAt, isNotNull);
        expect(cancelled.isOpen, isFalse);

        // A terminal case has no forward edge left, not even back to screening.
        final reopened = await cases.transitionStatus(
          TransitionLeasingCaseStatusCommand(
            context: context(reason: 'zweiter Versuch'),
            caseId: leasingCase.id,
            expectedVersion: cancelled.version,
            targetStatus: LeasingCaseStatus.screening,
          ),
        );
        expect(
          _failure(reopened).kind,
          LeasingRepositoryFailureKind.validationFailed,
        );

        final openCases = _successPage<LeasingCaseSummaryDto>(
          await cases.search(
            const LeasingCaseListQuery(
              workspaceId: workspaceId,
              openOnly: true,
            ),
          ),
        );
        expect(openCases.items, isEmpty);

        // --- Idempotency ---------------------------------------------------

        final replayContext = context();
        final firstUnit = _success<UnitDto>(
          await units.create(
            CreateUnitCommand(
              context: replayContext,
              draft: const UnitDraft(
                propertyId: propertyId,
                unitCode: 'A-03',
              ),
            ),
          ),
        );
        final replay = _success<UnitDto>(
          await units.create(
            CreateUnitCommand(
              context: replayContext,
              draft: const UnitDraft(
                propertyId: propertyId,
                unitCode: 'A-03',
              ),
            ),
          ),
        );
        expect(replay.id, firstUnit.id);
        expect(replay.version, firstUnit.version);

        // --- Server-side authorization -------------------------------------

        await viewerClient.auth.signInWithPassword(
          email: 'p2-d05-viewer@example.test',
          password: 'NexImmo-Test-2026!',
        );
        final viewerUnits = SupabaseUnitRepositoryAdapter(client: viewerClient);
        final viewerLeases = SupabaseLeaseRepositoryAdapter(
          client: viewerClient,
        );

        // No lease.read: RLS hides the rows entirely.
        final viewerSearch = _successPage<UnitSummaryDto>(
          await viewerUnits.search(
            const UnitListQuery(workspaceId: workspaceId),
          ),
        );
        expect(viewerSearch.items, isEmpty);

        // No lease.manage: the mutation is refused as forbidden, which is a
        // different answer from "there is nothing here".
        final viewerMutation = await viewerLeases.transitionStatus(
          TransitionLeaseStatusCommand(
            context: LeasingCommandContext(
              workspaceId: workspaceId,
              actorId: 'ea000000-0000-0000-0000-000000000002',
              mutationId: 'e8000000-0000-0000-0000-000000000900',
              correlationId: 'e9000000-0000-0000-0000-000000000900',
              reason: 'viewer attempt',
            ),
            leaseId: leaseOne.id,
            expectedVersion: activeOne.version,
            targetStatus: LeaseStatus.ended,
          ),
        );
        expect(
          _failure(viewerMutation).kind,
          LeasingRepositoryFailureKind.forbidden,
        );
      } finally {
        await viewerClient.auth.signOut();
        await managerClient.auth.signOut();
      }
    },
    skip: url.isEmpty || publishableKey.isEmpty
        ? 'Requires the local Supabase integration harness.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Walks a draft lease through STM-005 to `active`, one lawful step at a time.
Future<LeaseDto> _walkToActive(
  SupabaseLeaseRepositoryAdapter leases,
  LeasingCommandContext Function({String? reason}) context,
  LeaseDto lease,
) async {
  var current = lease;
  for (final target in <LeaseStatus>[
    LeaseStatus.reviewed,
    LeaseStatus.sent,
    LeaseStatus.tenantSigned,
    LeaseStatus.landlordSigned,
    LeaseStatus.active,
  ]) {
    current = _success<LeaseDto>(
      await leases.transitionStatus(
        TransitionLeaseStatusCommand(
          context: context(),
          leaseId: current.id,
          expectedVersion: current.version,
          targetStatus: target,
        ),
      ),
    );
  }
  return current;
}

T _success<T>(LeasingRepositoryResult<T> result) {
  if (result is LeasingRepositoryFailure<T>) {
    fail('Expected success but got ${result.kind}: ${result.message}');
  }
  return (result as LeasingRepositorySuccess<T>).value;
}

LeasingPageResult<T> _successPage<T>(
  LeasingRepositoryResult<LeasingPageResult<T>> result,
) => _success<LeasingPageResult<T>>(result);

LeasingRepositoryFailure<T> _failure<T>(LeasingRepositoryResult<T> result) {
  if (result is LeasingRepositorySuccess<T>) {
    fail('Expected a failure but the command succeeded.');
  }
  return result as LeasingRepositoryFailure<T>;
}
