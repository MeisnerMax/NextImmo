/// Read-only projection of the legacy `maintenance_tickets` /
/// `renovation_projects` tables onto the canonical `maintenance_capex`
/// contract (P2-D06, mirroring the P2-D05 leasing adapter and the P2-D02
/// party adapter).
///
/// All mutations answer [MaintenanceCapexRepositoryFailureKind.dependencyConflict]:
/// the local schema has no version token, no mutation receipt and no audited
/// command envelope, so it cannot honour the contract's mutation shape.
///
/// Unlike `leasing_operations`, this is **not** a green-field cloud schema —
/// both local tables carry real, actively-used data with their own free-text
/// vocabularies that predate STM-006/STM-007. Two honest gaps follow from
/// that, both documented at the point they are dropped rather than silently
/// papered over:
///
///   * **Status is a best-effort mapping, not a lossless one.** The legacy
///     columns are free text (`maintenance_screen.dart`'s filter carries ten
///     English values; the renovation dialog carries two German ones) and
///     none of them was ever validated against STM-006/STM-007. See
///     [_ticketStatus]/[_projectStatus] for the exact table and the
///     reasoning behind each row.
///   * **`contractorPartyId` is always null.** The legacy schema has no
///     contractor-as-party-role concept at all (P2-D02 is cloud-only) — a
///     ticket's `vendor_name` is free text with no party behind it, and a
///     renovation project has no vendor field whatsoever. Inventing a party
///     id here would assert a relationship that does not exist locally, so
///     [MaintenanceTicketRecord.vendorName] has no home in the projection and
///     is dropped, not renamed.
///
/// Two classes rather than one, for the same reason the Supabase adapter has
/// two: the ports deliberately share the natural method names (`getById`/
/// `create`/`update`/`transitionStatus`/`search`), which one class cannot
/// implement twice.
library;

import '../../../core/models/asset_workbook.dart';
import '../../../core/models/maintenance.dart';
import '../../../data/repositories/asset_workbook_repo.dart';
import '../../../data/repositories/maintenance_repo.dart';
import '../../../data/repositories/property_repo.dart';
import '../application/maintenance_capex_repository.dart';
import '../domain/capex_project_dto.dart';
import '../domain/maintenance_ticket_dto.dart';

/// Read source of the legacy projection. It returns the legacy records
/// verbatim; every interpretation lives in the adapters below, so a test can
/// drive the whole projection without a database.
abstract interface class LegacyMaintenanceCapexReadSource {
  /// Every property the local store holds. Needed because
  /// [listCapexProjects] is per-property only (`AssetWorkbookRepo.listRenovations`
  /// has no workspace-wide read), while a `getById` lookup may not know which
  /// property a project belongs to.
  Future<List<String>> listPropertyIds();

  /// Tickets of one property, or of every property when [propertyId] is
  /// null — `MaintenanceRepo.listTickets` supports both directly, unlike the
  /// renovation read below, so `getById` needs no property fan-out here.
  Future<List<MaintenanceTicketRecord>> listMaintenanceTickets({
    String? propertyId,
  });

  Future<List<RenovationProjectRecord>> listCapexProjects(String propertyId);
}

/// [LegacyMaintenanceCapexReadSource] backed by the concrete local
/// repositories.
class RepositoryLegacyMaintenanceCapexReadSource
    implements LegacyMaintenanceCapexReadSource {
  const RepositoryLegacyMaintenanceCapexReadSource({
    required PropertyRepository propertyRepo,
    required MaintenanceRepo maintenanceRepo,
    required AssetWorkbookRepo assetWorkbookRepo,
  }) : _propertyRepo = propertyRepo,
       _maintenanceRepo = maintenanceRepo,
       _assetWorkbookRepo = assetWorkbookRepo;

  final PropertyRepository _propertyRepo;
  final MaintenanceRepo _maintenanceRepo;
  final AssetWorkbookRepo _assetWorkbookRepo;

  @override
  Future<List<String>> listPropertyIds() async {
    final properties = await _propertyRepo.list(includeArchived: true);
    return properties.map((property) => property.id).toList(growable: false);
  }

  @override
  Future<List<MaintenanceTicketRecord>> listMaintenanceTickets({
    String? propertyId,
  }) => _maintenanceRepo.listTickets(assetPropertyId: propertyId);

  @override
  Future<List<RenovationProjectRecord>> listCapexProjects(
    String propertyId,
  ) => _assetWorkbookRepo.listRenovations(propertyId);
}

/// Shared projection and failure shapes of the two legacy adapters.
abstract class _LegacyMaintenanceCapexBase {
  _LegacyMaintenanceCapexBase({
    required this.source,
    required this.legacyWorkspaceId,
  });

  /// The local rows carry no optimistic-concurrency token. Reporting `0` says
  /// "there is no version here" rather than inventing one that a later
  /// `expectedVersion` could accidentally satisfy.
  static const int unsupportedVersion = 0;

  static const String legacyActor = 'legacy';

  final LegacyMaintenanceCapexReadSource source;
  final String legacyWorkspaceId;

  MaintenanceTicketDto mapTicket(MaintenanceTicketRecord record) {
    return MaintenanceTicketDto(
      id: record.id,
      workspaceId: legacyWorkspaceId,
      propertyId: record.assetPropertyId,
      title: record.title,
      status: _ticketStatus(record.status),
      priority: _ticketPriority(record.priority),
      reportedAt: dateFromEpoch(record.reportedAt)!,
      version: unsupportedVersion,
      unitId: record.unitId,
      dueAt: dateFromEpoch(record.dueAt),
      costEstimate: record.costEstimate,
      costActual: record.costActual,
      // No local currency column exists at all — unlike the unit adapter's
      // rent figures, there is not even a lease to derive one from, so this
      // is always null rather than guessed.
      currencyCode: null,
      // The legacy schema has no contractor-as-party-role concept; see the
      // library comment. `record.vendorName` (free text) is dropped, not
      // mapped, because there is no party id to attach it to.
      contractorPartyId: null,
      category: record.category,
      description: record.description,
      resolvedAt: dateFromEpoch(record.resolvedAt),
      damageLocation: record.damageLocation,
      insuranceCase: record.insuranceCase,
      insuranceStatus: record.insuranceStatus,
      insuranceClaimNumber: record.insuranceClaimNumber,
      createdAt: dateFromEpoch(record.createdAt)!,
      updatedAt: dateFromEpoch(record.updatedAt)!,
      createdBy: legacyActor,
      updatedBy: legacyActor,
    );
  }

  CapexProjectDto mapProject(RenovationProjectRecord record) {
    return CapexProjectDto(
      id: record.id,
      workspaceId: legacyWorkspaceId,
      propertyId: record.propertyId,
      projectCode: record.projectCode,
      status: _projectStatus(record.status),
      version: unsupportedVersion,
      // No local currency column, no forecast column — both budget and
      // actual are still reported (see [_projectStatus]'s neighbour comment
      // on `owner`), just without a currency to label them or a forecast to
      // compare them against.
      currencyCode: null,
      budgetAmount: record.budgetAmount,
      forecastAmount: null,
      actualAmount: record.actualAmount,
      plannedEndDate: dateFromEpoch(record.plannedEndDate),
      contractorPartyId: null,
      category: record.category,
      measure: record.measure,
      startDate: dateFromEpoch(record.startDate),
      actualEndDate: dateFromEpoch(record.actualEndDate),
      owner: record.owner,
      nextStep: record.nextStep,
      // The legacy schema records no approval step at all — STM-007's
      // `capex.approve` gate is new. Reporting these as unset is honest:
      // nothing in the local row claims a project was ever approved.
      approvedBy: null,
      approvedAt: null,
      createdAt: dateFromEpoch(record.createdAt)!,
      updatedAt: dateFromEpoch(record.updatedAt)!,
      createdBy: legacyActor,
      updatedBy: legacyActor,
    );
  }

  /// Legacy vocabulary (`maintenance_screen.dart`'s filter dropdown, the
  /// fullest enumeration in the app): `open`, `planned`, `commissioned`,
  /// `in_progress`, `waiting_material`, `waiting_reply`, `completed`,
  /// `billed`, `resolved`, `closed`, plus whatever an older row happens to
  /// carry — the column is free text and was never validated against a state
  /// machine.
  ///
  /// The mapping preserves every exact vocabulary match
  /// (`commissioned`/`in_progress`/`resolved`) and otherwise picks the
  /// closest STM-006 stage by what the legacy label actually asserts, not by
  /// list position:
  ///
  ///   * `open` — nothing has happened yet, the STM-006 start.
  ///   * `planned` — assessed and slated for work, but no contractor
  ///     commissioned yet: `triage`, the stage immediately before
  ///     `quote_requested`/`commissioned`.
  ///   * `waiting_material` / `waiting_reply` — STM-006 does not distinguish
  ///     what a ticket is waiting on, only that it is; both collapse to the
  ///     one `waiting` state.
  ///   * `completed` — work is done but the legacy schema's `billed` is a
  ///     separate later state, so `completed` cannot mean STM-006's
  ///     `invoiced` (that would skip a step the legacy data never asserted):
  ///     `resolved`.
  ///   * `billed` — money has changed hands: `invoiced`.
  ///   * `closed` — the legacy terminal state: `archived`.
  ///
  /// An unrecognised value becomes [MaintenanceTicketStatus.newTicket]. That
  /// is the one choice that cannot mislead a consumer into thinking closed
  /// work is still open, or vice versa: `newTicket` is neither a completion
  /// claim nor a "nothing to do" claim, unlike guessing `resolved` or
  /// `archived` would be.
  static MaintenanceTicketStatus _ticketStatus(String value) {
    switch (value.trim().toLowerCase()) {
      case 'open':
        return MaintenanceTicketStatus.newTicket;
      case 'planned':
        return MaintenanceTicketStatus.triage;
      case 'commissioned':
        return MaintenanceTicketStatus.commissioned;
      case 'in_progress':
        return MaintenanceTicketStatus.inProgress;
      case 'waiting_material':
      case 'waiting_reply':
        return MaintenanceTicketStatus.waiting;
      case 'completed':
        return MaintenanceTicketStatus.resolved;
      case 'billed':
        return MaintenanceTicketStatus.invoiced;
      case 'resolved':
        return MaintenanceTicketStatus.resolved;
      case 'closed':
        return MaintenanceTicketStatus.archived;
      default:
        return MaintenanceTicketStatus.newTicket;
    }
  }

  /// Legacy vocabulary matches the cloud one exactly (`low`/`normal`/`high`/
  /// `urgent` — `maintenance_screen.dart`'s priority dropdown), so this is a
  /// direct parse rather than a judgement call. An unrecognised value falls
  /// back to `normal`, matching `MaintenanceTicketRecord`'s own SQL default.
  static MaintenanceTicketPriority _ticketPriority(String value) {
    switch (value.trim().toLowerCase()) {
      case 'low':
        return MaintenanceTicketPriority.low;
      case 'high':
        return MaintenanceTicketPriority.high;
      case 'urgent':
        return MaintenanceTicketPriority.urgent;
      case 'normal':
      default:
        return MaintenanceTicketPriority.normal;
    }
  }

  /// Legacy vocabulary (`asset_workbook_screen.dart`'s renovation dialog, the
  /// only place the local app writes this column): German free text, and
  /// only two values are ever offered — `Geplant` (the `createRenovation`
  /// default) and `Abgeschlossen`.
  ///
  /// `Geplant` maps to [CapexProjectStatus.planned] — the exact next STM-007
  /// stage after `idea`, and the legacy row already carries a project code,
  /// which `idea` (STM-007's true start, before there is enough to name)
  /// would understate. `Abgeschlossen` maps to [CapexProjectStatus.completed]
  /// rather than `invoiced`/`archived`: nothing in the local schema records a
  /// billing or archival step, so claiming either would assert a fact the row
  /// does not carry.
  ///
  /// An unrecognised value becomes [CapexProjectStatus.idea], STM-007's own
  /// start — the one choice that cannot claim progress the row never
  /// asserted.
  static CapexProjectStatus _projectStatus(String value) {
    switch (value.trim().toLowerCase()) {
      case 'geplant':
        return CapexProjectStatus.planned;
      case 'abgeschlossen':
        return CapexProjectStatus.completed;
      default:
        return CapexProjectStatus.idea;
    }
  }

  static DateTime? dateFromEpoch(int? value) {
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  Future<MaintenanceCapexRepositoryResult<T>> blockedMutation<T>(
    String workspaceId,
  ) async {
    final failure = scopeFailure<T>(workspaceId);
    if (failure != null) {
      return failure;
    }
    return const MaintenanceCapexRepositoryFailure(
      kind: MaintenanceCapexRepositoryFailureKind.dependencyConflict,
      message:
          'The local SQLite backend is read-only for the maintenance_capex '
          'contract: it has no version token, no mutation receipt and no '
          'audited command envelope.',
    );
  }

  MaintenanceCapexRepositoryFailure<T>? scopeFailure<T>(String workspaceId) {
    if (workspaceId == legacyWorkspaceId) {
      return null;
    }
    return MaintenanceCapexRepositoryFailure<T>(
      kind: MaintenanceCapexRepositoryFailureKind.forbidden,
      message: 'The legacy SQLite database is bound to another workspace.',
    );
  }

  MaintenanceCapexRepositoryFailure<T> loadFailure<T>() {
    return const MaintenanceCapexRepositoryFailure(
      kind: MaintenanceCapexRepositoryFailureKind.infrastructureFailure,
      message: 'Legacy SQLite maintenance tickets or CapEx projects could '
          'not be loaded.',
    );
  }
}

/// Maintenance tickets, read-only.
class LegacySqliteMaintenanceTicketRepositoryAdapter
    extends _LegacyMaintenanceCapexBase
    implements MaintenanceTicketRepository, MaintenanceTicketSearchPort {
  LegacySqliteMaintenanceTicketRepositoryAdapter({
    required super.source,
    required super.legacyWorkspaceId,
  });

  // --- MaintenanceTicketSearchPort ---

  @override
  Future<MaintenanceCapexRepositoryResult<List<MaintenanceTicketSummaryDto>>>
  search(MaintenanceTicketListQuery query) async {
    final failure = scopeFailure<List<MaintenanceTicketSummaryDto>>(
      query.workspaceId,
    );
    if (failure != null) {
      return failure;
    }

    try {
      final records = await source.listMaintenanceTickets(
        propertyId: query.propertyId,
      );
      final tickets = records.map(mapTicket).where((ticket) {
        if (query.unitId != null && ticket.unitId != query.unitId) {
          return false;
        }
        if (query.status != null && ticket.status != query.status) {
          return false;
        }
        if (query.priority != null && ticket.priority != query.priority) {
          return false;
        }
        return true;
      }).toList(growable: false)
        ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
      return MaintenanceCapexRepositorySuccess<
        List<MaintenanceTicketSummaryDto>
      >(tickets.map((ticket) => ticket.toSummary()).toList(growable: false));
    } catch (_) {
      return loadFailure<List<MaintenanceTicketSummaryDto>>();
    }
  }

  @override
  Future<MaintenanceCapexRepositoryResult<List<MaintenanceTicketSummaryDto>>>
  searchWorkspace(WorkspaceMaintenanceTicketListQuery query) async {
    final failure = scopeFailure<List<MaintenanceTicketSummaryDto>>(
      query.workspaceId,
    );
    if (failure != null) {
      return failure;
    }

    try {
      // Unlike the cloud RPC this replaces (which needed a dedicated
      // workspace-wide RPC because the per-property one refuses a null
      // property id), the legacy read source already scans every property
      // when none is named — no equivalent backend gap exists locally.
      final records = await source.listMaintenanceTickets();
      final tickets = records.map(mapTicket).where((ticket) {
        if (query.status != null && ticket.status != query.status) {
          return false;
        }
        if (query.priority != null && ticket.priority != query.priority) {
          return false;
        }
        return true;
      }).toList(growable: false)
        ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
      return MaintenanceCapexRepositorySuccess<
        List<MaintenanceTicketSummaryDto>
      >(tickets.map((ticket) => ticket.toSummary()).toList(growable: false));
    } catch (_) {
      return loadFailure<List<MaintenanceTicketSummaryDto>>();
    }
  }

  // --- MaintenanceTicketRepository ---

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> getById({
    required String workspaceId,
    required String ticketId,
  }) async {
    final failure = scopeFailure<MaintenanceTicketDto>(workspaceId);
    if (failure != null) {
      return failure;
    }

    try {
      final records = await source.listMaintenanceTickets();
      for (final record in records) {
        if (record.id == ticketId) {
          return MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>(
            mapTicket(record),
          );
        }
      }
      return const MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>(
        kind: MaintenanceCapexRepositoryFailureKind.notFound,
        message: 'Ticket not found in the local store.',
      );
    } catch (_) {
      return loadFailure<MaintenanceTicketDto>();
    }
  }

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> create(
    CreateMaintenanceTicketCommand command,
  ) => blockedMutation<MaintenanceTicketDto>(command.context.workspaceId);

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> update(
    UpdateMaintenanceTicketCommand command,
  ) => blockedMutation<MaintenanceTicketDto>(command.context.workspaceId);

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>>
  transitionStatus(TransitionMaintenanceTicketStatusCommand command) =>
      blockedMutation<MaintenanceTicketDto>(command.context.workspaceId);
}

/// CapEx projects, read-only.
class LegacySqliteCapexProjectRepositoryAdapter
    extends _LegacyMaintenanceCapexBase
    implements CapexProjectRepository, CapexProjectSearchPort {
  LegacySqliteCapexProjectRepositoryAdapter({
    required super.source,
    required super.legacyWorkspaceId,
  });

  // --- CapexProjectSearchPort ---

  @override
  Future<MaintenanceCapexRepositoryResult<List<CapexProjectSummaryDto>>>
  search(CapexProjectListQuery query) async {
    final failure = scopeFailure<List<CapexProjectSummaryDto>>(
      query.workspaceId,
    );
    if (failure != null) {
      return failure;
    }

    try {
      final records = await source.listCapexProjects(query.propertyId);
      final projects = records.map(mapProject).where((project) {
        if (query.status != null && project.status != query.status) {
          return false;
        }
        return true;
      }).toList(growable: false)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return MaintenanceCapexRepositorySuccess<List<CapexProjectSummaryDto>>(
        projects.map((project) => project.toSummary()).toList(growable: false),
      );
    } catch (_) {
      return loadFailure<List<CapexProjectSummaryDto>>();
    }
  }

  // --- CapexProjectRepository ---

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> getById({
    required String workspaceId,
    required String projectId,
  }) async {
    final failure = scopeFailure<CapexProjectDto>(workspaceId);
    if (failure != null) {
      return failure;
    }

    try {
      for (final propertyId in await source.listPropertyIds()) {
        final records = await source.listCapexProjects(propertyId);
        for (final record in records) {
          if (record.id == projectId) {
            return MaintenanceCapexRepositorySuccess<CapexProjectDto>(
              mapProject(record),
            );
          }
        }
      }
      return const MaintenanceCapexRepositoryFailure<CapexProjectDto>(
        kind: MaintenanceCapexRepositoryFailureKind.notFound,
        message: 'Project not found in the local store.',
      );
    } catch (_) {
      return loadFailure<CapexProjectDto>();
    }
  }

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> create(
    CreateCapexProjectCommand command,
  ) => blockedMutation<CapexProjectDto>(command.context.workspaceId);

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> update(
    UpdateCapexProjectCommand command,
  ) => blockedMutation<CapexProjectDto>(command.context.workspaceId);

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> transitionStatus(
    TransitionCapexProjectStatusCommand command,
  ) => blockedMutation<CapexProjectDto>(command.context.workspaceId);
}
