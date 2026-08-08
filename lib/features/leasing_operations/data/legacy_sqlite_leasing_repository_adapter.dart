/// Read-only projection of the legacy `units` / `leases` tables onto the
/// canonical `leasing_operations` contract (P2-D05 increment 3, mirroring the
/// P2-D02 party adapter and the P2-D03 document adapter).
///
/// All mutations answer [LeasingRepositoryFailureKind.dependencyConflict]: the
/// local schema has no version token, no mutation receipt and no audited
/// command envelope, so it cannot honour the contract's mutation shape.
///
/// **`OPN-DOM-001` is respected here, and the local store is not.**
/// `LeaseRepo._validateLease` still enforces "at most one overlapping active
/// lease per unit" on writes — precisely the assumption the 2026-07-29 decision
/// overruled. These adapters never write, so they cannot inherit the rule, and
/// they deliberately do not present it as truth either: a lease query filtered
/// by unit returns **every** matching lease, and nothing here collapses a unit
/// to "its" lease.
///
/// **Rent roll snapshots are refused, not projected.** The local store does
/// have `rent_roll_snapshots`/`rent_roll_lines`, but they are a different
/// document: keyed by period (`'2026-03'`) rather than a reporting date, with
/// no currency, no unit-status partition and no base/ancillary/parking split.
/// Producing an `AGG-007` snapshot from one would mean inventing four fields
/// inside a document whose entire purpose is that it was frozen, not computed
/// later — see [LegacySqliteRentRollAdapter].
///
/// Four classes rather than one, for the same reason the Supabase adapter has
/// four: the aggregates deliberately share the natural method names
/// (`getById`/`create`/`update`/`transitionStatus`/`search`), which one class
/// cannot implement four times. They share [_LegacyLeasingBase] and one read
/// source.
library;

import '../../../core/models/operations.dart';
import '../../../data/repositories/lease_repo.dart';
import '../../../data/repositories/property_repo.dart';
import '../../../data/repositories/rent_roll_repo.dart';
import '../application/leasing_repository.dart';
import '../domain/lease_dto.dart';
import '../domain/leasing_case_dto.dart';
import '../domain/rent_roll_dto.dart';
import '../domain/unit_dto.dart';

/// Read source of the legacy leasing projection. It returns the legacy records
/// verbatim; every interpretation lives in the adapters below, so a test can
/// drive the whole projection without a database.
///
/// Deliberately narrow: there is nothing here for leasing cases (the local
/// store has no such table — the legacy pipeline was UI-only status strings,
/// which is exactly the `FTR-024` debt P2-D05 pays off) and nothing for rent
/// roll snapshots (the local ones exist but are a different document).
abstract interface class LegacyLeasingReadSource {
  /// Every property the local store holds. Needed because the legacy unit and
  /// lease reads are per property only, while the contract's queries may be
  /// workspace-wide.
  Future<List<String>> listPropertyIds();

  Future<List<UnitRecord>> listUnits(String propertyId);

  Future<List<LeaseRecord>> listLeases(String propertyId);

  /// The one legacy lookup that is already global, so a lease read by id costs
  /// one query instead of a scan.
  Future<LeaseRecord?> findLease(String leaseId);
}

/// [LegacyLeasingReadSource] backed by the concrete local repositories.
///
/// Unit and lease enumeration fans out over the properties, which is the same
/// access pattern `AssetWorkbookRepo.loadPortfolioOverview` already uses on the
/// portfolio screen — the local store simply has no workspace-wide unit or
/// lease read. Archived properties are included: a lease of an archived
/// property is still a lease, and hiding it here would quietly change what a
/// portfolio-wide query answers.
class RepositoryLegacyLeasingReadSource implements LegacyLeasingReadSource {
  const RepositoryLegacyLeasingReadSource({
    required PropertyRepository propertyRepo,
    required RentRollRepo rentRollRepo,
    required LeaseRepo leaseRepo,
  }) : _propertyRepo = propertyRepo,
       _rentRollRepo = rentRollRepo,
       _leaseRepo = leaseRepo;

  final PropertyRepository _propertyRepo;
  final RentRollRepo _rentRollRepo;
  final LeaseRepo _leaseRepo;

  @override
  Future<List<String>> listPropertyIds() async {
    final properties = await _propertyRepo.list(includeArchived: true);
    return properties.map((property) => property.id).toList(growable: false);
  }

  @override
  Future<List<UnitRecord>> listUnits(String propertyId) =>
      _rentRollRepo.listUnitsByAsset(propertyId, includeArchived: true);

  @override
  Future<List<LeaseRecord>> listLeases(String propertyId) =>
      _leaseRepo.listLeasesByAsset(propertyId);

  @override
  Future<LeaseRecord?> findLease(String leaseId) =>
      _leaseRepo.getLeaseById(leaseId);
}

/// Shared projection, paging and failure shapes of the four legacy adapters.
abstract class _LegacyLeasingBase {
  _LegacyLeasingBase({required this.source, required this.legacyWorkspaceId});

  /// The local rows carry no optimistic-concurrency token. Reporting `0` says
  /// "there is no version here" rather than inventing one that a later
  /// `expectedVersion` could accidentally satisfy.
  static const int unsupportedVersion = 0;

  static const String legacyActor = 'legacy';

  /// The legacy soft-delete. It has no [UnitStatus] counterpart — `offline`
  /// claims a deliberate, reasoned takedown, which an archived unit is not — so
  /// archived units are omitted from the projection. That also matches what the
  /// V1 units screen shows by default.
  static const String archivedUnitStatus = 'archived';

  final LegacyLeasingReadSource source;
  final String legacyWorkspaceId;

  /// Units of one property, or of every property when [propertyId] is null.
  ///
  /// The leases of each property are loaded alongside because a [UnitDto] needs
  /// a currency for its rent figures and the legacy `units` table stores none —
  /// see [_unitCurrency].
  Future<List<UnitDto>> loadUnits({String? propertyId}) async {
    final propertyIds = await _propertyScope(propertyId);
    final units = <UnitDto>[];
    for (final id in propertyIds) {
      final records = await source.listUnits(id);
      final leases = await source.listLeases(id);
      for (final record in records) {
        final status = _unitStatus(record.status);
        if (status == null) {
          continue;
        }
        units.add(_mapUnit(record, status, leases));
      }
    }
    units.sort((a, b) => a.id.compareTo(b.id));
    return units;
  }

  Future<List<LeaseDto>> loadLeases({String? propertyId}) async {
    final propertyIds = await _propertyScope(propertyId);
    final leases = <LeaseDto>[];
    for (final id in propertyIds) {
      final records = await source.listLeases(id);
      leases.addAll(records.map(mapLease));
    }
    leases.sort((a, b) => a.id.compareTo(b.id));
    return leases;
  }

  Future<List<String>> _propertyScope(String? propertyId) async {
    if (propertyId != null) {
      return <String>[propertyId];
    }
    return source.listPropertyIds();
  }

  /// Legacy column names are US leftovers; the app's semantics are metric and
  /// German throughout. The V1 unit dialog labels `sqft` as `m²`, `beds` as
  /// "Zimmer" and `baths` as "Bäder", and `calculation_datasheet_repo.dart`
  /// already maps `sqft` onto `area_sqm`. The projection follows the meaning,
  /// not the column name — a unit conversion here would be the actual bug.
  UnitDto _mapUnit(
    UnitRecord record,
    UnitStatus status,
    List<LeaseRecord> propertyLeases,
  ) {
    return UnitDto(
      id: record.id,
      workspaceId: legacyWorkspaceId,
      propertyId: record.assetPropertyId,
      unitCode: record.unitCode,
      status: status,
      version: unsupportedVersion,
      unitType: record.unitType,
      floor: record.floor,
      areaSqm: record.sqft,
      rooms: record.beds,
      vacancySince: dateFromEpoch(record.vacancySince),
      bathrooms: record.baths,
      targetRentMonthly: record.targetRentMonthly,
      marketRentMonthly: record.marketRentMonthly,
      currencyCode: _unitCurrency(record, propertyLeases),
      vacancyReason: record.vacancyReason,
      // The legacy column is not status-scoped, so a stale reason can outlive
      // the offline state. The contract says the field describes the current
      // state, so it is only reported while that state holds.
      offlineReason: status == UnitStatus.offline ? record.offlineReason : null,
      marketingStatus: record.marketingStatus,
      renovationStatus: record.renovationStatus,
      expectedReadyDate: dateFromEpoch(record.expectedReadyDate),
      nextAction: record.nextAction,
      notes: record.notes,
      createdAt: dateFromEpoch(record.createdAt)!,
      updatedAt: dateFromEpoch(record.updatedAt)!,
      createdBy: legacyActor,
      updatedBy: legacyActor,
    );
  }

  LeaseDto mapLease(LeaseRecord record) {
    return LeaseDto(
      id: record.id,
      workspaceId: legacyWorkspaceId,
      propertyId: record.assetPropertyId,
      unitId: record.unitId,
      leaseName: record.leaseName,
      status: _leaseStatus(record.status),
      startDate: dateFromEpoch(record.startDate)!,
      baseRentMonthly: record.baseRentMonthly,
      currencyCode: record.currencyCode,
      version: unsupportedVersion,
      // AGG-005: the legacy `tenants` table projects onto parties keyed by the
      // same id (see `legacy_sqlite_party_repository_adapter.dart`), so the
      // tenant id *is* the party id in local mode. The two legacy adapters have
      // to agree on this or a lease would point at nothing.
      tenantPartyId: record.tenantId,
      endDate: dateFromEpoch(record.endDate),
      billingFrequency: _billingFrequency(record.billingFrequency),
      moveInDate: dateFromEpoch(record.moveInDate),
      moveOutDate: dateFromEpoch(record.moveOutDate),
      signedDate: dateFromEpoch(record.leaseSignedDate),
      noticeDate: dateFromEpoch(record.noticeDate),
      renewalOptionDate: dateFromEpoch(record.renewalOptionDate),
      breakOptionDate: dateFromEpoch(record.breakOptionDate),
      ancillaryChargesMonthly: record.ancillaryChargesMonthly,
      parkingOtherChargesMonthly: record.parkingOtherChargesMonthly,
      securityDeposit: record.securityDeposit,
      paymentDayOfMonth: record.paymentDayOfMonth,
      rentFreePeriodMonths: record.rentFreePeriodMonths,
      // Left null on purpose even for a terminal lease: the local store records
      // no termination timestamp. `moveOutDate` is when the tenant left and
      // `updatedAt` is when the row was last touched — neither is "when this
      // lease ended", and substituting one would fabricate a fact. The exact
      // terminal test is `status.isTerminal`, which holds in both backends.
      endedAt: null,
      cancelledAt: null,
      notes: record.notes,
      createdAt: dateFromEpoch(record.createdAt)!,
      updatedAt: dateFromEpoch(record.updatedAt)!,
      createdBy: legacyActor,
      updatedBy: legacyActor,
    );
  }

  /// The legacy `units` table stores rent amounts without a currency. Rather
  /// than dropping the amounts or guessing a code, the currency is derived from
  /// the unit's own leases when they agree on one — the same rule the server
  /// applies to a rent roll (DEC-011: derive from the contributing leases,
  /// never guess). Disagreement or no lease at all yields null, so a consumer
  /// sees "amount without currency" instead of a wrong currency.
  String? _unitCurrency(UnitRecord record, List<LeaseRecord> propertyLeases) {
    if (record.targetRentMonthly == null && record.marketRentMonthly == null) {
      return null;
    }
    final currencies = propertyLeases
        .where((lease) => lease.unitId == record.id)
        .map((lease) => lease.currencyCode)
        .toSet();
    return currencies.length == 1 ? currencies.first : null;
  }

  /// Legacy vocabulary: `vacant` / `occupied` / `offline` / `archived`, plus
  /// whatever an older row happens to carry — the column is free text.
  ///
  /// Null means "do not project this unit". `archived` is the legacy
  /// soft-delete; an unrecognised value cannot be turned into any of the three
  /// cloud states without asserting something the record does not say, and
  /// guessing `vacant` or `occupied` would move the occupancy rate. Reporting
  /// fewer units is recoverable; reporting a wrong occupancy is not.
  static UnitStatus? _unitStatus(String value) {
    switch (value.trim().toLowerCase()) {
      case 'vacant':
        return UnitStatus.vacant;
      case 'occupied':
        return UnitStatus.occupied;
      case 'offline':
        return UnitStatus.offline;
      case archivedUnitStatus:
      default:
        return null;
    }
  }

  /// Legacy vocabulary: `draft` / `future` / `active` / `terminated` /
  /// `expired`, again on a free-text column.
  ///
  /// `future` maps to [LeaseStatus.draft] rather than to a signature stage: the
  /// local schema tracks no signature chain, so `landlordSigned` would invent
  /// two signing events. Nothing is lost — "starts later" is still readable
  /// from `startDate`. `terminated` and `expired` both mean "was effective, now
  /// over", which is [LeaseStatus.ended]; the projection never produces
  /// [LeaseStatus.cancelled].
  ///
  /// An unrecognised value also becomes [LeaseStatus.draft]. That is the one
  /// choice that cannot do damage: `draft` is neither effective nor terminal,
  /// so an unmapped lease can never inflate occupancy or a rent roll.
  static LeaseStatus _leaseStatus(String value) {
    switch (value.trim().toLowerCase()) {
      case 'active':
        return LeaseStatus.active;
      case 'terminated':
      case 'expired':
        return LeaseStatus.ended;
      case 'draft':
      case 'future':
      default:
        return LeaseStatus.draft;
    }
  }

  /// Legacy vocabulary: `monthly` / `quarterly` / `yearly`. There is no legacy
  /// value for [LeaseBillingFrequency.semiannual]. Unknown falls back to
  /// monthly, which is what `LeaseRecord.fromMap` already defaults to.
  static LeaseBillingFrequency _billingFrequency(String value) {
    switch (value.trim().toLowerCase()) {
      case 'quarterly':
        return LeaseBillingFrequency.quarterly;
      case 'semiannual':
        return LeaseBillingFrequency.semiannual;
      case 'yearly':
      case 'annual':
        return LeaseBillingFrequency.annual;
      case 'monthly':
      default:
        return LeaseBillingFrequency.monthly;
    }
  }

  static DateTime? dateFromEpoch(int? value) {
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  /// Keyset paging over the id, matching the cloud adapter's `afterId` cursor
  /// so a caller can page the same way against either backend.
  LeasingPageResult<T> page<T>({
    required List<T> items,
    required String Function(T item) idOf,
    required LeasingPageRequest request,
  }) {
    final cursor = request.cursor;
    final result = <T>[];
    var reachedCursor = cursor == null;
    String? nextCursor;
    for (final item in items) {
      if (!reachedCursor) {
        if (idOf(item) == cursor) {
          reachedCursor = true;
        }
        continue;
      }
      if (result.length == request.limit) {
        nextCursor = idOf(result.last);
        break;
      }
      result.add(item);
    }
    return LeasingPageResult<T>(items: result, nextCursor: nextCursor);
  }

  Future<LeasingRepositoryResult<T>> blockedMutation<T>(
    String workspaceId,
  ) async {
    final failure = scopeFailure<T>(workspaceId);
    if (failure != null) {
      return failure;
    }
    return const LeasingRepositoryFailure(
      kind: LeasingRepositoryFailureKind.dependencyConflict,
      message:
          'The local SQLite backend is read-only for the leasing_operations '
          'contract: it has no unit or lease version token, no mutation '
          'receipt and no audited command envelope.',
    );
  }

  LeasingRepositoryFailure<T>? scopeFailure<T>(String workspaceId) {
    if (workspaceId == legacyWorkspaceId) {
      return null;
    }
    return LeasingRepositoryFailure<T>(
      kind: LeasingRepositoryFailureKind.forbidden,
      message: 'The legacy SQLite database is bound to another workspace.',
    );
  }

  LeasingRepositoryFailure<T> loadFailure<T>() {
    return const LeasingRepositoryFailure(
      kind: LeasingRepositoryFailureKind.infrastructureFailure,
      message: 'Legacy SQLite units and leases could not be loaded.',
    );
  }
}

/// Units, read-only.
class LegacySqliteUnitRepositoryAdapter extends _LegacyLeasingBase
    implements UnitRepository, UnitSearchPort {
  LegacySqliteUnitRepositoryAdapter({
    required super.source,
    required super.legacyWorkspaceId,
  });

  // --- UnitSearchPort ---

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<UnitSummaryDto>>> search(
    UnitListQuery query,
  ) async {
    final failure = scopeFailure<LeasingPageResult<UnitSummaryDto>>(
      query.workspaceId,
    );
    if (failure != null) {
      return failure;
    }

    try {
      final units = await loadUnits(propertyId: query.propertyId);
      final filtered = units
          .where((unit) => query.status == null || unit.status == query.status)
          .toList(growable: false);
      return LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
        page<UnitSummaryDto>(
          items: filtered
              .map((unit) => unit.toSummary())
              .toList(growable: false),
          idOf: (unit) => unit.id,
          request: query.page,
        ),
      );
    } catch (_) {
      return loadFailure<LeasingPageResult<UnitSummaryDto>>();
    }
  }

  // --- UnitRepository ---

  @override
  Future<LeasingRepositoryResult<UnitDto>> getById({
    required String workspaceId,
    required String unitId,
  }) async {
    final failure = scopeFailure<UnitDto>(workspaceId);
    if (failure != null) {
      return failure;
    }

    try {
      final units = await loadUnits();
      for (final unit in units) {
        if (unit.id == unitId) {
          return LeasingRepositorySuccess<UnitDto>(unit);
        }
      }
      return const LeasingRepositoryFailure<UnitDto>(
        kind: LeasingRepositoryFailureKind.notFound,
        message: 'Unit not found in the local store.',
      );
    } catch (_) {
      return loadFailure<UnitDto>();
    }
  }

  @override
  Future<LeasingRepositoryResult<UnitDto>> create(CreateUnitCommand command) =>
      blockedMutation<UnitDto>(command.context.workspaceId);

  @override
  Future<LeasingRepositoryResult<UnitDto>> update(UpdateUnitCommand command) =>
      blockedMutation<UnitDto>(command.context.workspaceId);

  @override
  Future<LeasingRepositoryResult<UnitDto>> transitionStatus(
    TransitionUnitStatusCommand command,
  ) => blockedMutation<UnitDto>(command.context.workspaceId);
}

/// Leases, read-only. Several concurrently effective leases per unit are
/// projected as several leases — see the library comment on `OPN-DOM-001`.
class LegacySqliteLeaseRepositoryAdapter extends _LegacyLeasingBase
    implements LeaseRepository, LeaseSearchPort {
  LegacySqliteLeaseRepositoryAdapter({
    required super.source,
    required super.legacyWorkspaceId,
  });

  // --- LeaseSearchPort ---

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeaseSummaryDto>>> search(
    LeaseListQuery query,
  ) async {
    final failure = scopeFailure<LeasingPageResult<LeaseSummaryDto>>(
      query.workspaceId,
    );
    if (failure != null) {
      return failure;
    }

    try {
      final leases = await loadLeases(propertyId: query.propertyId);
      final filtered = leases.where((lease) {
        if (query.unitId != null && lease.unitId != query.unitId) {
          return false;
        }
        if (query.tenantPartyId != null &&
            lease.tenantPartyId != query.tenantPartyId) {
          return false;
        }
        if (query.status != null && lease.status != query.status) {
          return false;
        }
        if (query.effectiveOnly && !lease.isEffective) {
          return false;
        }
        return true;
      }).toList(growable: false);
      return LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
        page<LeaseSummaryDto>(
          items: filtered
              .map((lease) => lease.toSummary())
              .toList(growable: false),
          idOf: (lease) => lease.id,
          request: query.page,
        ),
      );
    } catch (_) {
      return loadFailure<LeasingPageResult<LeaseSummaryDto>>();
    }
  }

  // --- LeaseRepository ---

  @override
  Future<LeasingRepositoryResult<LeaseDto>> getById({
    required String workspaceId,
    required String leaseId,
  }) async {
    final failure = scopeFailure<LeaseDto>(workspaceId);
    if (failure != null) {
      return failure;
    }

    try {
      final record = await source.findLease(leaseId);
      if (record == null) {
        return const LeasingRepositoryFailure<LeaseDto>(
          kind: LeasingRepositoryFailureKind.notFound,
          message: 'Lease not found in the local store.',
        );
      }
      return LeasingRepositorySuccess<LeaseDto>(mapLease(record));
    } catch (_) {
      return loadFailure<LeaseDto>();
    }
  }

  @override
  Future<LeasingRepositoryResult<LeaseDto>> create(CreateLeaseCommand command) =>
      blockedMutation<LeaseDto>(command.context.workspaceId);

  @override
  Future<LeasingRepositoryResult<LeaseDto>> update(UpdateLeaseCommand command) =>
      blockedMutation<LeaseDto>(command.context.workspaceId);

  @override
  Future<LeasingRepositoryResult<LeaseDto>> transitionStatus(
    TransitionLeaseStatusCommand command,
  ) => blockedMutation<LeaseDto>(command.context.workspaceId);
}

/// Leasing cases, of which the local store has none.
///
/// The legacy pipeline was a set of UI-only status strings that were never
/// persisted (`FTR-024`), so "no cases" is the true answer rather than a gap
/// being papered over — [search] therefore succeeds with an empty page instead
/// of failing.
class LegacySqliteLeasingCaseRepositoryAdapter extends _LegacyLeasingBase
    implements LeasingCaseRepository, LeasingCaseSearchPort {
  LegacySqliteLeasingCaseRepositoryAdapter({
    required super.source,
    required super.legacyWorkspaceId,
  });

  // --- LeasingCaseSearchPort ---

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeasingCaseSummaryDto>>>
  search(LeasingCaseListQuery query) async {
    final failure = scopeFailure<LeasingPageResult<LeasingCaseSummaryDto>>(
      query.workspaceId,
    );
    if (failure != null) {
      return failure;
    }
    return const LeasingRepositorySuccess<
      LeasingPageResult<LeasingCaseSummaryDto>
    >(
      LeasingPageResult<LeasingCaseSummaryDto>(
        items: <LeasingCaseSummaryDto>[],
      ),
    );
  }

  // --- LeasingCaseRepository ---

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> getById({
    required String workspaceId,
    required String caseId,
  }) async {
    final failure = scopeFailure<LeasingCaseDto>(workspaceId);
    if (failure != null) {
      return failure;
    }
    return const LeasingRepositoryFailure<LeasingCaseDto>(
      kind: LeasingRepositoryFailureKind.notFound,
      message:
          'The local SQLite store has no leasing cases: the legacy pipeline '
          'was a set of UI-only status strings and was never persisted.',
    );
  }

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> create(
    CreateLeasingCaseCommand command,
  ) => blockedMutation<LeasingCaseDto>(command.context.workspaceId);

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> update(
    UpdateLeasingCaseCommand command,
  ) => blockedMutation<LeasingCaseDto>(command.context.workspaceId);

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> transitionStatus(
    TransitionLeasingCaseStatusCommand command,
  ) => blockedMutation<LeasingCaseDto>(command.context.workspaceId);
}

/// Rent roll snapshots, which the local store holds in an incompatible shape.
///
/// Every method fails with [LeasingRepositoryFailureKind.dependencyConflict]
/// and says why, so a screen can render the documented "read-only until
/// migrated" state. An empty list would have been the dishonest option: it
/// reads as "this property has no rent roll", when the truth is "this backend
/// cannot express the one it has".
class LegacySqliteRentRollAdapter extends _LegacyLeasingBase
    implements RentRollPort {
  LegacySqliteRentRollAdapter({
    required super.source,
    required super.legacyWorkspaceId,
  });

  /// The live rent roll **is** served locally (P2-D05b), unlike the frozen
  /// document: it needs only units and leases, which this projection already
  /// reads, and it invents nothing — a computed answer is allowed to be
  /// computed. The rule below mirrors `private.rent_roll_unit_rows`: a lease
  /// contributes when it is effective *and* its term covers the reporting date.
  /// This mirror exists only until the local backend is gone; the cloud adapter
  /// asks Postgres instead.
  @override
  Future<LeasingRepositoryResult<RentRollLiveDto>> readLive({
    required String workspaceId,
    required String propertyId,
    required DateTime asOfDate,
  }) async {
    final failure = scopeFailure<RentRollLiveDto>(workspaceId);
    if (failure != null) {
      return failure;
    }
    final units = await loadUnits(propertyId: propertyId);
    final leases = await loadLeases(propertyId: propertyId);
    final date = DateTime.utc(asOfDate.year, asOfDate.month, asOfDate.day);

    final lines = <RentRollLiveLineDto>[];
    for (final unit in units) {
      final contributing = leases
          .where(
            (lease) =>
                lease.unitId == unit.id &&
                lease.isEffective &&
                lease.coversDate(date),
          )
          .toList(growable: false);
      final currencies =
          contributing.map((lease) => lease.currencyCode).toSet().toList()
            ..sort();
      final base = contributing.fold<double>(
        0,
        (sum, lease) => sum + lease.baseRentMonthly,
      );
      final ancillary = contributing.fold<double>(
        0,
        (sum, lease) => sum + (lease.ancillaryChargesMonthly ?? 0),
      );
      final parking = contributing.fold<double>(
        0,
        (sum, lease) => sum + (lease.parkingOtherChargesMonthly ?? 0),
      );
      lines.add(
        RentRollLiveLineDto(
          unitId: unit.id,
          unitCode: unit.unitCode,
          unitStatus: unit.status,
          effectiveLeaseCount: contributing.length,
          baseRentMonthly: base,
          ancillaryChargesMonthly: ancillary,
          parkingOtherChargesMonthly: parking,
          totalRentMonthly: base + ancillary + parking,
          currencies: currencies,
          areaSqm: unit.areaSqm,
        ),
      );
    }
    lines.sort((a, b) => a.unitCode.compareTo(b.unitCode));

    final currencies = lines.expand((line) => line.currencies).toSet().toList()
      ..sort();
    final leaseCount = lines.fold<int>(
      0,
      (sum, line) => sum + line.effectiveLeaseCount,
    );
    // DEC-011, same rule as the server: totals only exist when one currency
    // does. Null says "not summable"; zero would say something false.
    final summable = currencies.length == 1 || leaseCount == 0;

    return LeasingRepositorySuccess<RentRollLiveDto>(
      RentRollLiveDto(
        workspaceId: workspaceId,
        propertyId: propertyId,
        asOfDate: date,
        computedAt: DateTime.now().toUtc(),
        currencies: currencies,
        unitCount: units.length,
        occupiedUnitCount: units
            .where((unit) => unit.status == UnitStatus.occupied)
            .length,
        vacantUnitCount: units
            .where((unit) => unit.status == UnitStatus.vacant)
            .length,
        offlineUnitCount: units
            .where((unit) => unit.status == UnitStatus.offline)
            .length,
        effectiveLeaseCount: leaseCount,
        totalBaseRentMonthly: summable
            ? lines.fold<double>(0, (sum, line) => sum + line.baseRentMonthly)
            : null,
        totalAncillaryChargesMonthly: summable
            ? lines.fold<double>(
                0,
                (sum, line) => sum + line.ancillaryChargesMonthly,
              )
            : null,
        totalParkingOtherChargesMonthly: summable
            ? lines.fold<double>(
                0,
                (sum, line) => sum + line.parkingOtherChargesMonthly,
              )
            : null,
        totalRentMonthly: summable
            ? lines.fold<double>(0, (sum, line) => sum + line.totalRentMonthly)
            : null,
        lines: lines,
      ),
    );
  }

  @override
  Future<LeasingRepositoryResult<RentRollSnapshotDto>> getSnapshot({
    required String workspaceId,
    required String snapshotId,
  }) => _blockedSnapshot<RentRollSnapshotDto>(workspaceId);

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<RentRollSnapshotDto>>>
  listSnapshots(RentRollSnapshotListQuery query) =>
      _blockedSnapshot<LeasingPageResult<RentRollSnapshotDto>>(
        query.workspaceId,
      );

  @override
  Future<LeasingRepositoryResult<RentRollSnapshotDto>> createSnapshot(
    CreateRentRollSnapshotCommand command,
  ) => blockedMutation<RentRollSnapshotDto>(command.context.workspaceId);

  Future<LeasingRepositoryResult<T>> _blockedSnapshot<T>(
    String workspaceId,
  ) async {
    final failure = scopeFailure<T>(workspaceId);
    if (failure != null) {
      return failure;
    }
    return const LeasingRepositoryFailure(
      kind: LeasingRepositoryFailureKind.dependencyConflict,
      message:
          'Local rent roll snapshots are a different document: they are keyed '
          'by reporting period rather than by date and carry no currency, no '
          'unit-status partition and no base/ancillary/parking split. '
          'Reshaping one into an AGG-007 snapshot would invent figures inside '
          'a document whose purpose is to be frozen.',
    );
  }
}
