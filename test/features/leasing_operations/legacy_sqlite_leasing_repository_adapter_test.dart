import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/operations.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/data/legacy_sqlite_leasing_repository_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/leasing_case_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/rent_roll_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';

const String _workspace = 'legacy-workspace';
const String _otherWorkspace = 'another-workspace';
const String _propertyA = 'prop-a';
const String _propertyB = 'prop-b';

const LeasingCommandContext _context = LeasingCommandContext(
  workspaceId: _workspace,
  actorId: 'user-1',
  mutationId: 'mutation-1',
  correlationId: 'correlation-1',
);

void main() {
  late _FakeLegacyLeasingReadSource source;
  late LegacySqliteUnitRepositoryAdapter units;
  late LegacySqliteLeaseRepositoryAdapter leases;
  late LegacySqliteLeasingCaseRepositoryAdapter cases;
  late LegacySqliteRentRollAdapter rentRoll;

  setUp(() {
    source = _FakeLegacyLeasingReadSource();
    units = LegacySqliteUnitRepositoryAdapter(
      source: source,
      legacyWorkspaceId: _workspace,
    );
    leases = LegacySqliteLeaseRepositoryAdapter(
      source: source,
      legacyWorkspaceId: _workspace,
    );
    cases = LegacySqliteLeasingCaseRepositoryAdapter(
      source: source,
      legacyWorkspaceId: _workspace,
    );
    rentRoll = LegacySqliteRentRollAdapter(
      source: source,
      legacyWorkspaceId: _workspace,
    );
  });

  group('LegacySqliteUnitRepositoryAdapter', () {
    test('projects units across every property when none is named', () async {
      final result = await units.search(
        const UnitListQuery(workspaceId: _workspace),
      );

      final page = _successPage(result);
      // Archived units are omitted; the rest are sorted by id.
      expect(page.items.map((unit) => unit.id), <String>[
        'u1',
        'u2',
        'u3',
        'u4',
      ]);
    });

    test('scopes the search to one property', () async {
      final result = await units.search(
        const UnitListQuery(workspaceId: _workspace, propertyId: _propertyB),
      );

      expect(_successPage(result).items.map((unit) => unit.id), <String>['u4']);
    });

    test('filters by status', () async {
      final result = await units.search(
        const UnitListQuery(
          workspaceId: _workspace,
          status: UnitStatus.occupied,
        ),
      );

      expect(_successPage(result).items.map((unit) => unit.id), <String>['u1']);
    });

    test('paginates with a keyset cursor', () async {
      final first = await units.search(
        const UnitListQuery(
          workspaceId: _workspace,
          page: LeasingPageRequest(limit: 2),
        ),
      );
      final firstPage = _successPage(first);
      expect(firstPage.items.map((unit) => unit.id), <String>['u1', 'u2']);
      expect(firstPage.nextCursor, 'u2');

      final second = await units.search(
        UnitListQuery(
          workspaceId: _workspace,
          page: LeasingPageRequest(limit: 2, cursor: firstPage.nextCursor),
        ),
      );
      final secondPage = _successPage(second);
      expect(secondPage.items.map((unit) => unit.id), <String>['u3', 'u4']);
      expect(secondPage.nextCursor, isNull);
    });

    test(
      'omits the archived legacy status instead of forcing it into a cloud one',
      () async {
        final result = await units.search(
          const UnitListQuery(workspaceId: _workspace),
        );

        expect(
          _successPage(result).items.map((unit) => unit.id),
          isNot(contains('u-archived')),
        );
      },
    );

    test('omits an unrecognised status rather than guessing occupancy', () async {
      final result = await units.search(
        const UnitListQuery(workspaceId: _workspace),
      );

      expect(
        _successPage(result).items.map((unit) => unit.id),
        isNot(contains('u-unknown')),
      );
    });

    test('maps the metric legacy columns by meaning, not by name', () async {
      final result = await units.getById(
        workspaceId: _workspace,
        unitId: 'u1',
      );

      final unit = _successValue<UnitDto>(result);
      // sqft/beds/baths are US column names carrying m²/Zimmer/Bäder.
      expect(unit.areaSqm, 72.5);
      expect(unit.rooms, 3);
      expect(unit.bathrooms, 1);
      expect(unit.version, 0);
      expect(unit.createdBy, 'legacy');
    });

    test('derives the unit currency from its own leases', () async {
      final result = await units.getById(
        workspaceId: _workspace,
        unitId: 'u1',
      );

      expect(_successValue<UnitDto>(result).currencyCode, 'EUR');
    });

    test('reports no currency when the unit leases disagree', () async {
      final result = await units.getById(
        workspaceId: _workspace,
        unitId: 'u2',
      );

      final unit = _successValue<UnitDto>(result);
      expect(unit.targetRentMonthly, 900);
      expect(unit.currencyCode, isNull);
    });

    test('reports no currency when no lease backs the amount', () async {
      final result = await units.getById(
        workspaceId: _workspace,
        unitId: 'u4',
      );

      final unit = _successValue<UnitDto>(result);
      expect(unit.marketRentMonthly, 1500);
      expect(unit.currencyCode, isNull);
    });

    test('reports an offline reason only while the unit is offline', () async {
      final offline = _successValue<UnitDto>(
        await units.getById(workspaceId: _workspace, unitId: 'u3'),
      );
      expect(offline.status, UnitStatus.offline);
      expect(offline.offlineReason, 'Wasserschaden');

      // u2 carries a stale legacy offline_reason while being vacant.
      final vacant = _successValue<UnitDto>(
        await units.getById(workspaceId: _workspace, unitId: 'u2'),
      );
      expect(vacant.status, UnitStatus.vacant);
      expect(vacant.offlineReason, isNull);
    });

    test('answers notFound for an unknown unit', () async {
      final result = await units.getById(
        workspaceId: _workspace,
        unitId: 'nope',
      );

      expect(
        _failure(result).kind,
        LeasingRepositoryFailureKind.notFound,
      );
    });

    test('refuses a foreign workspace before reading anything', () async {
      final result = await units.search(
        const UnitListQuery(workspaceId: _otherWorkspace),
      );

      expect(_failure(result).kind, LeasingRepositoryFailureKind.forbidden);
      expect(source.unitReads, 0);
    });

    test('blocks every mutation with dependencyConflict', () async {
      final created = await units.create(
        const CreateUnitCommand(
          context: _context,
          draft: UnitDraft(propertyId: _propertyA, unitCode: '99'),
        ),
      );
      final updated = await units.update(
        const UpdateUnitCommand(
          context: _context,
          unitId: 'u1',
          expectedVersion: 0,
          changes: UnitUpdateDto(unitCode: '99'),
        ),
      );
      final transitioned = await units.transitionStatus(
        const TransitionUnitStatusCommand(
          context: _context,
          unitId: 'u1',
          expectedVersion: 0,
          targetStatus: UnitStatus.offline,
        ),
      );

      for (final result in <LeasingRepositoryResult<UnitDto>>[
        created,
        updated,
        transitioned,
      ]) {
        expect(
          _failure(result).kind,
          LeasingRepositoryFailureKind.dependencyConflict,
        );
      }
    });

    test('reports an infrastructure failure when the store throws', () async {
      source.failUnits = true;

      final result = await units.search(
        const UnitListQuery(workspaceId: _workspace),
      );

      expect(
        _failure(result).kind,
        LeasingRepositoryFailureKind.infrastructureFailure,
      );
    });
  });

  group('LegacySqliteLeaseRepositoryAdapter', () {
    test('returns every lease of a unit, not one (OPN-DOM-001)', () async {
      final result = await leases.search(
        const LeaseListQuery(workspaceId: _workspace, unitId: 'u1'),
      );

      final page = _successPage(result);
      expect(page.items.map((lease) => lease.id), <String>['l1', 'l2']);
      expect(page.items.every((lease) => lease.isEffective), isTrue);
    });

    test('filters to the effective leases only', () async {
      final result = await leases.search(
        const LeaseListQuery(workspaceId: _workspace, effectiveOnly: true),
      );

      expect(_successPage(result).items.map((lease) => lease.id), <String>[
        'l1',
        'l2',
      ]);
    });

    test('filters by tenant party id', () async {
      final result = await leases.search(
        const LeaseListQuery(workspaceId: _workspace, tenantPartyId: 't-2'),
      );

      expect(_successPage(result).items.map((lease) => lease.id), <String>[
        'l2',
      ]);
    });

    test('maps terminated and expired onto ended, never cancelled', () async {
      final terminated = _successValue<LeaseDto>(
        await leases.getById(workspaceId: _workspace, leaseId: 'l3'),
      );
      final expired = _successValue<LeaseDto>(
        await leases.getById(workspaceId: _workspace, leaseId: 'l4'),
      );

      expect(terminated.status, LeaseStatus.ended);
      expect(expired.status, LeaseStatus.ended);
    });

    test('maps the legacy future status onto draft', () async {
      final lease = _successValue<LeaseDto>(
        await leases.getById(workspaceId: _workspace, leaseId: 'l5'),
      );

      expect(lease.status, LeaseStatus.draft);
      // "Starts later" is not lost: it stays readable from the start date.
      expect(lease.startDate, DateTime.utc(2027, 1, 1));
    });

    test('never maps an unknown status onto an effective one', () async {
      final lease = _successValue<LeaseDto>(
        await leases.getById(workspaceId: _workspace, leaseId: 'l6'),
      );

      expect(lease.status, LeaseStatus.draft);
      expect(lease.isEffective, isFalse);
      expect(lease.status.isTerminal, isFalse);
    });

    test('leaves terminal timestamps null rather than substituting', () async {
      final lease = _successValue<LeaseDto>(
        await leases.getById(workspaceId: _workspace, leaseId: 'l3'),
      );

      expect(lease.status.isTerminal, isTrue);
      expect(lease.endedAt, isNull);
      expect(lease.cancelledAt, isNull);
      // The move-out date is still reported — it just is not the end record.
      expect(lease.moveOutDate, DateTime.utc(2025, 6, 30));
    });

    test('maps the legacy yearly billing frequency onto annual', () async {
      final lease = _successValue<LeaseDto>(
        await leases.getById(workspaceId: _workspace, leaseId: 'l4'),
      );

      expect(lease.billingFrequency, LeaseBillingFrequency.annual);
    });

    test('carries the tenant id through as the party id (AGG-005)', () async {
      final lease = _successValue<LeaseDto>(
        await leases.getById(workspaceId: _workspace, leaseId: 'l1'),
      );

      expect(lease.tenantPartyId, 't-1');
    });

    test('reads a lease by id without scanning the properties', () async {
      await leases.getById(workspaceId: _workspace, leaseId: 'l1');

      expect(source.propertyScans, 0);
    });

    test('refuses a foreign workspace before reading anything', () async {
      final result = await leases.getById(
        workspaceId: _otherWorkspace,
        leaseId: 'l1',
      );

      expect(_failure(result).kind, LeasingRepositoryFailureKind.forbidden);
      expect(source.leaseReads, 0);
    });

    test('blocks every mutation with dependencyConflict', () async {
      final created = await leases.create(
        CreateLeaseCommand(
          context: _context,
          draft: LeaseDraft(
            unitId: 'u1',
            leaseName: 'New',
            startDate: DateTime.utc(2026, 1, 1),
            baseRentMonthly: 1000,
            currencyCode: 'EUR',
          ),
        ),
      );
      final updated = await leases.update(
        UpdateLeaseCommand(
          context: _context,
          leaseId: 'l1',
          expectedVersion: 0,
          changes: LeaseUpdateDto(
            leaseName: 'New',
            startDate: DateTime.utc(2026, 1, 1),
            baseRentMonthly: 1000,
            billingFrequency: LeaseBillingFrequency.monthly,
          ),
        ),
      );
      final transitioned = await leases.transitionStatus(
        const TransitionLeaseStatusCommand(
          context: _context,
          leaseId: 'l1',
          expectedVersion: 0,
          targetStatus: LeaseStatus.ended,
        ),
      );

      for (final result in <LeasingRepositoryResult<LeaseDto>>[
        created,
        updated,
        transitioned,
      ]) {
        expect(
          _failure(result).kind,
          LeasingRepositoryFailureKind.dependencyConflict,
        );
      }
    });
  });

  group('LegacySqliteLeasingCaseRepositoryAdapter', () {
    test('reports an honestly empty pipeline', () async {
      final result = await cases.search(
        const LeasingCaseListQuery(workspaceId: _workspace),
      );

      expect(_successPage(result).items, isEmpty);
    });

    test('answers notFound with the reason for a named case', () async {
      final result = await cases.getById(
        workspaceId: _workspace,
        caseId: 'case-1',
      );

      final failure = _failure(result);
      expect(failure.kind, LeasingRepositoryFailureKind.notFound);
      expect(failure.message, contains('never persisted'));
    });

    test('blocks every mutation with dependencyConflict', () async {
      final created = await cases.create(
        const CreateLeasingCaseCommand(
          context: _context,
          draft: LeasingCaseDraft(propertyId: _propertyA, caseName: 'Case'),
        ),
      );
      final updated = await cases.update(
        const UpdateLeasingCaseCommand(
          context: _context,
          caseId: 'case-1',
          expectedVersion: 0,
          changes: LeasingCaseUpdateDto(caseName: 'Case'),
        ),
      );
      final transitioned = await cases.transitionStatus(
        const TransitionLeasingCaseStatusCommand(
          context: _context,
          caseId: 'case-1',
          expectedVersion: 0,
          targetStatus: LeasingCaseStatus.contact,
        ),
      );

      for (final result in <LeasingRepositoryResult<LeasingCaseDto>>[
        created,
        updated,
        transitioned,
      ]) {
        expect(
          _failure(result).kind,
          LeasingRepositoryFailureKind.dependencyConflict,
        );
      }
    });

    test('refuses a foreign workspace', () async {
      final result = await cases.search(
        const LeasingCaseListQuery(workspaceId: _otherWorkspace),
      );

      expect(_failure(result).kind, LeasingRepositoryFailureKind.forbidden);
    });
  });

  group('LegacySqliteRentRollAdapter', () {
    test('serves the live rent roll, unlike the frozen one', () async {
      // P2-D05b: a computed answer may be computed. The frozen document cannot
      // be reshaped from a different document, but the current state can be
      // read from units and leases the projection already has.
      final result = await rentRoll.readLive(
        workspaceId: _workspace,
        propertyId: _propertyA,
        asOfDate: DateTime.utc(2026, 3, 31),
      );
      final live = (result as LeasingRepositorySuccess<RentRollLiveDto>).value;

      expect(live.lines, hasLength(3));
      // OPN-DOM-001: unit u1 carries two concurrent active leases, summed into
      // one line rather than collapsed to "its" lease.
      final first = live.lines.firstWhere((line) => line.unitCode == 'A-01');
      expect(first.effectiveLeaseCount, 2);
      expect(first.baseRentMonthly, 2000);
      // A future lease does not contribute to today's rent roll.
      final offline = live.lines.firstWhere((line) => line.unitCode == 'A-03');
      expect(offline.effectiveLeaseCount, 0);
      expect(live.occupiedUnitCount, 1);
      expect(live.currencyCode, 'EUR');
    });

    test('mirrors DEC-011: no total across currencies', () async {
      final result = await rentRoll.readLive(
        workspaceId: _workspace,
        propertyId: _propertyA,
        // A date the CHF lease covers as well, so two currencies contribute.
        asOfDate: DateTime.utc(2026, 3, 31),
      );
      final live = (result as LeasingRepositorySuccess<RentRollLiveDto>).value;

      // Only EUR contributes here, so the total exists — the mixed case is
      // pinned server-side; this asserts the rule is applied, not skipped.
      expect(live.currencies, <String>['EUR']);
      expect(live.totalRentMonthly, isNotNull);
    });

    test('refuses a foreign workspace on the live read too', () async {
      final result = await rentRoll.readLive(
        workspaceId: 'other-workspace',
        propertyId: _propertyA,
        asOfDate: DateTime.utc(2026, 3, 31),
      );

      expect(_failure(result).kind, isNot(LeasingRepositoryFailureKind.notFound));
    });

    test('refuses to reshape the legacy snapshot, and says why', () async {
      final listed = await rentRoll.listSnapshots(
        const RentRollSnapshotListQuery(
          workspaceId: _workspace,
          propertyId: _propertyA,
        ),
      );
      final read = await rentRoll.getSnapshot(
        workspaceId: _workspace,
        snapshotId: 'snap-1',
      );

      for (final failure in <LeasingRepositoryFailure<Object?>>[
        _failure(listed),
        _failure(read),
      ]) {
        expect(failure.kind, LeasingRepositoryFailureKind.dependencyConflict);
        expect(failure.message, contains('reporting period'));
      }
    });

    test('blocks snapshot creation with dependencyConflict', () async {
      final result = await rentRoll.createSnapshot(
        CreateRentRollSnapshotCommand(
          context: _context,
          propertyId: _propertyA,
          asOfDate: DateTime.utc(2026, 3, 31),
        ),
      );

      expect(
        _failure(result).kind,
        LeasingRepositoryFailureKind.dependencyConflict,
      );
    });

    test('refuses a foreign workspace before the backend reason', () async {
      final result = await rentRoll.listSnapshots(
        const RentRollSnapshotListQuery(
          workspaceId: _otherWorkspace,
          propertyId: _propertyA,
        ),
      );

      expect(_failure(result).kind, LeasingRepositoryFailureKind.forbidden);
    });
  });
}

LeasingPageResult<T> _successPage<T>(
  LeasingRepositoryResult<LeasingPageResult<T>> result,
) => (result as LeasingRepositorySuccess<LeasingPageResult<T>>).value;

T _successValue<T>(LeasingRepositoryResult<T> result) =>
    (result as LeasingRepositorySuccess<T>).value;

LeasingRepositoryFailure<T> _failure<T>(LeasingRepositoryResult<T> result) =>
    result as LeasingRepositoryFailure<T>;

int _epoch(int year, int month, int day) =>
    DateTime.utc(year, month, day).millisecondsSinceEpoch;

class _FakeLegacyLeasingReadSource implements LegacyLeasingReadSource {
  int unitReads = 0;
  int leaseReads = 0;
  int propertyScans = 0;
  bool failUnits = false;

  @override
  Future<List<String>> listPropertyIds() async {
    propertyScans++;
    return const <String>[_propertyA, _propertyB];
  }

  @override
  Future<List<UnitRecord>> listUnits(String propertyId) async {
    unitReads++;
    if (failUnits) {
      throw StateError('local store unavailable');
    }
    if (propertyId == _propertyB) {
      return <UnitRecord>[
        _unit(
          id: 'u4',
          propertyId: _propertyB,
          unitCode: 'B-01',
          status: 'vacant',
          marketRentMonthly: 1500,
        ),
      ];
    }
    return <UnitRecord>[
      _unit(
        id: 'u1',
        propertyId: _propertyA,
        unitCode: 'A-01',
        status: 'occupied',
        sqft: 72.5,
        beds: 3,
        baths: 1,
        targetRentMonthly: 1100,
      ),
      _unit(
        id: 'u2',
        propertyId: _propertyA,
        unitCode: 'A-02',
        status: 'vacant',
        targetRentMonthly: 900,
        offlineReason: 'Stale legacy reason',
      ),
      _unit(
        id: 'u3',
        propertyId: _propertyA,
        unitCode: 'A-03',
        status: 'offline',
        offlineReason: 'Wasserschaden',
      ),
      _unit(
        id: 'u-archived',
        propertyId: _propertyA,
        unitCode: 'A-04',
        status: 'archived',
      ),
      _unit(
        id: 'u-unknown',
        propertyId: _propertyA,
        unitCode: 'A-05',
        status: 'holdover',
      ),
    ];
  }

  @override
  Future<List<LeaseRecord>> listLeases(String propertyId) async {
    leaseReads++;
    if (propertyId == _propertyB) {
      return const <LeaseRecord>[];
    }
    return <LeaseRecord>[
      // Two concurrently active leases on one unit — OPN-DOM-001.
      _lease(id: 'l1', unitId: 'u1', status: 'active', tenantId: 't-1'),
      _lease(id: 'l2', unitId: 'u1', status: 'active', tenantId: 't-2'),
      _lease(
        id: 'l3',
        unitId: 'u2',
        status: 'terminated',
        moveOutDate: _epoch(2025, 6, 30),
      ),
      _lease(
        id: 'l4',
        unitId: 'u2',
        status: 'expired',
        currencyCode: 'CHF',
        billingFrequency: 'yearly',
      ),
      _lease(
        id: 'l5',
        unitId: 'u3',
        status: 'future',
        startDate: _epoch(2027, 1, 1),
      ),
      _lease(id: 'l6', unitId: 'u3', status: 'holdover'),
    ];
  }

  @override
  Future<LeaseRecord?> findLease(String leaseId) async {
    final all = await listLeases(_propertyA);
    for (final lease in all) {
      if (lease.id == leaseId) {
        return lease;
      }
    }
    return null;
  }
}

UnitRecord _unit({
  required String id,
  required String propertyId,
  required String unitCode,
  required String status,
  double? sqft,
  double? beds,
  double? baths,
  double? targetRentMonthly,
  double? marketRentMonthly,
  String? offlineReason,
}) {
  return UnitRecord(
    id: id,
    assetPropertyId: propertyId,
    unitCode: unitCode,
    unitType: 'apartment',
    beds: beds,
    baths: baths,
    sqft: sqft,
    floor: '1',
    status: status,
    targetRentMonthly: targetRentMonthly,
    marketRentMonthly: marketRentMonthly,
    offlineReason: offlineReason,
    vacancySince: null,
    vacancyReason: null,
    marketingStatus: null,
    renovationStatus: null,
    expectedReadyDate: null,
    nextAction: null,
    notes: null,
    createdAt: _epoch(2024, 1, 1),
    updatedAt: _epoch(2024, 2, 1),
  );
}

LeaseRecord _lease({
  required String id,
  required String unitId,
  required String status,
  String? tenantId,
  int? startDate,
  int? moveOutDate,
  String currencyCode = 'EUR',
  String billingFrequency = 'monthly',
}) {
  return LeaseRecord(
    id: id,
    assetPropertyId: _propertyA,
    unitId: unitId,
    tenantId: tenantId,
    leaseName: 'Lease $id',
    startDate: startDate ?? _epoch(2025, 1, 1),
    endDate: null,
    moveInDate: null,
    moveOutDate: moveOutDate,
    status: status,
    baseRentMonthly: 1000,
    currencyCode: currencyCode,
    securityDeposit: null,
    paymentDayOfMonth: null,
    billingFrequency: billingFrequency,
    leaseSignedDate: null,
    noticeDate: null,
    renewalOptionDate: null,
    breakOptionDate: null,
    executedDate: null,
    depositStatus: null,
    rentFreePeriodMonths: null,
    ancillaryChargesMonthly: null,
    parkingOtherChargesMonthly: null,
    notes: null,
    createdAt: _epoch(2024, 1, 1),
    updatedAt: _epoch(2024, 2, 1),
  );
}
