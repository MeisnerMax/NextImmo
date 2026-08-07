import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/asset_workbook.dart';
import 'package:neximmo_app/core/models/maintenance.dart';
import 'package:neximmo_app/features/maintenance_capex/application/maintenance_capex_repository.dart';
import 'package:neximmo_app/features/maintenance_capex/data/legacy_sqlite_maintenance_capex_repository_adapter.dart';
import 'package:neximmo_app/features/maintenance_capex/domain/capex_project_dto.dart';
import 'package:neximmo_app/features/maintenance_capex/domain/maintenance_ticket_dto.dart';

const String _workspace = 'legacy-workspace';
const String _otherWorkspace = 'another-workspace';
const String _propertyA = 'prop-a';
const String _propertyB = 'prop-b';

const MaintenanceCapexCommandContext _context = MaintenanceCapexCommandContext(
  workspaceId: _workspace,
  actorId: 'user-1',
  mutationId: 'mutation-1',
  correlationId: 'correlation-1',
);

void main() {
  late _FakeLegacyMaintenanceCapexReadSource source;
  late LegacySqliteMaintenanceTicketRepositoryAdapter tickets;
  late LegacySqliteCapexProjectRepositoryAdapter projects;

  setUp(() {
    source = _FakeLegacyMaintenanceCapexReadSource();
    tickets = LegacySqliteMaintenanceTicketRepositoryAdapter(
      source: source,
      legacyWorkspaceId: _workspace,
    );
    projects = LegacySqliteCapexProjectRepositoryAdapter(
      source: source,
      legacyWorkspaceId: _workspace,
    );
  });

  group('LegacySqliteMaintenanceTicketRepositoryAdapter', () {
    test('scopes the search to one property', () async {
      final result = await tickets.search(
        const MaintenanceTicketListQuery(
          workspaceId: _workspace,
          propertyId: _propertyB,
        ),
      );

      expect(_successList(result).map((t) => t.id), <String>['t-b1']);
    });

    test('searches across every property when unscoped by the RPC shape', () async {
      // The legacy read source itself can list globally (unlike CapEx),
      // matching public.maintenance_tickets' own required-property shape only
      // at the query layer, not the source.
      final all = await source.listMaintenanceTickets();
      expect(all.map((t) => t.id), containsAll(<String>['t1', 't-b1']));
    });

    test('filters by unit, status and priority', () async {
      final byUnit = await tickets.search(
        const MaintenanceTicketListQuery(
          workspaceId: _workspace,
          propertyId: _propertyA,
          unitId: 'unit-1',
        ),
      );
      expect(_successList(byUnit).map((t) => t.id), <String>['t1']);

      final byStatus = await tickets.search(
        const MaintenanceTicketListQuery(
          workspaceId: _workspace,
          propertyId: _propertyA,
          status: MaintenanceTicketStatus.archived,
        ),
      );
      expect(_successList(byStatus).map((t) => t.id), <String>['t-closed']);

      final byPriority = await tickets.search(
        const MaintenanceTicketListQuery(
          workspaceId: _workspace,
          propertyId: _propertyA,
          priority: MaintenanceTicketPriority.urgent,
        ),
      );
      expect(_successList(byPriority).map((t) => t.id), <String>['t-urgent']);
    });

    test('sorts newest reported first', () async {
      final result = await tickets.search(
        const MaintenanceTicketListQuery(
          workspaceId: _workspace,
          propertyId: _propertyA,
        ),
      );

      final reportedDates = _successList(result).map((t) => t.reportedAt);
      expect(
        reportedDates,
        orderedEquals(reportedDates.toList()..sort((a, b) => b.compareTo(a))),
      );
    });

    group('status mapping (STM-006, best-effort)', () {
      const cases = <String, MaintenanceTicketStatus>{
        'open': MaintenanceTicketStatus.newTicket,
        'planned': MaintenanceTicketStatus.triage,
        'commissioned': MaintenanceTicketStatus.commissioned,
        'in_progress': MaintenanceTicketStatus.inProgress,
        'waiting_material': MaintenanceTicketStatus.waiting,
        'waiting_reply': MaintenanceTicketStatus.waiting,
        'completed': MaintenanceTicketStatus.resolved,
        'billed': MaintenanceTicketStatus.invoiced,
        'resolved': MaintenanceTicketStatus.resolved,
        'closed': MaintenanceTicketStatus.archived,
        'something-unrecognised': MaintenanceTicketStatus.newTicket,
      };

      for (final entry in cases.entries) {
        test('"${entry.key}" maps to ${entry.value}', () async {
          source.extraTickets = <MaintenanceTicketRecord>[
            _ticket(id: 't-map', propertyId: _propertyA, status: entry.key),
          ];
          final result = await tickets.getById(
            workspaceId: _workspace,
            ticketId: 't-map',
          );
          expect(_successValue<MaintenanceTicketDto>(result).status, entry.value);
        });
      }
    });

    test('priority matches the cloud vocabulary directly', () async {
      final result = await tickets.getById(
        workspaceId: _workspace,
        ticketId: 't1',
      );
      expect(
        _successValue<MaintenanceTicketDto>(result).priority,
        MaintenanceTicketPriority.normal,
      );
    });

    test('reports no currency and no contractor party: neither exists locally', () async {
      final result = await tickets.getById(
        workspaceId: _workspace,
        ticketId: 't1',
      );
      final ticket = _successValue<MaintenanceTicketDto>(result);
      expect(ticket.currencyCode, isNull);
      expect(ticket.contractorPartyId, isNull);
    });

    test('reports version 0: the local row carries no concurrency token', () async {
      final result = await tickets.getById(
        workspaceId: _workspace,
        ticketId: 't1',
      );
      expect(_successValue<MaintenanceTicketDto>(result).version, 0);
      expect(_successValue<MaintenanceTicketDto>(result).createdBy, 'legacy');
    });

    test('answers notFound for an unknown ticket', () async {
      final result = await tickets.getById(
        workspaceId: _workspace,
        ticketId: 'nope',
      );
      expect(_failure(result).kind, MaintenanceCapexRepositoryFailureKind.notFound);
    });

    test('answers forbidden for a foreign workspace', () async {
      final result = await tickets.getById(
        workspaceId: _otherWorkspace,
        ticketId: 't1',
      );
      expect(_failure(result).kind, MaintenanceCapexRepositoryFailureKind.forbidden);
    });

    test('every mutation answers dependencyConflict', () async {
      final create = await tickets.create(
        CreateMaintenanceTicketCommand(
          context: _context,
          draft: const MaintenanceTicketDraft(
            propertyId: _propertyA,
            title: 'New ticket',
          ),
        ),
      );
      expect(
        _failure(create).kind,
        MaintenanceCapexRepositoryFailureKind.dependencyConflict,
      );

      final update = await tickets.update(
        const UpdateMaintenanceTicketCommand(
          context: _context,
          ticketId: 't1',
          expectedVersion: 0,
          changes: MaintenanceTicketUpdateDto(),
        ),
      );
      expect(
        _failure(update).kind,
        MaintenanceCapexRepositoryFailureKind.dependencyConflict,
      );

      final transition = await tickets.transitionStatus(
        const TransitionMaintenanceTicketStatusCommand(
          context: _context,
          ticketId: 't1',
          expectedVersion: 0,
          targetStatus: MaintenanceTicketStatus.triage,
        ),
      );
      expect(
        _failure(transition).kind,
        MaintenanceCapexRepositoryFailureKind.dependencyConflict,
      );
    });
  });

  group('LegacySqliteCapexProjectRepositoryAdapter', () {
    test('scopes the search to one property', () async {
      final result = await projects.search(
        const CapexProjectListQuery(
          workspaceId: _workspace,
          propertyId: _propertyB,
        ),
      );
      expect(_successList(result).map((p) => p.id), <String>['p-b1']);
    });

    test('filters by status', () async {
      final result = await projects.search(
        const CapexProjectListQuery(
          workspaceId: _workspace,
          propertyId: _propertyA,
          status: CapexProjectStatus.completed,
        ),
      );
      expect(_successList(result).map((p) => p.id), <String>['p-done']);
    });

    group('status mapping (STM-007, best-effort)', () {
      const cases = <String, CapexProjectStatus>{
        'Geplant': CapexProjectStatus.planned,
        'geplant': CapexProjectStatus.planned,
        'Abgeschlossen': CapexProjectStatus.completed,
        'unknown-status': CapexProjectStatus.idea,
      };

      for (final entry in cases.entries) {
        test('"${entry.key}" maps to ${entry.value}', () async {
          source.extraProjects = <RenovationProjectRecord>[
            _renovation(id: 'p-map', propertyId: _propertyA, status: entry.key),
          ];
          final result = await projects.getById(
            workspaceId: _workspace,
            projectId: 'p-map',
          );
          expect(_successValue<CapexProjectDto>(result).status, entry.value);
        });
      }
    });

    test(
      'reports no currency, no forecast and no approval stamp: none exist locally',
      () async {
        final result = await projects.getById(
          workspaceId: _workspace,
          projectId: 'p1',
        );
        final project = _successValue<CapexProjectDto>(result);
        expect(project.currencyCode, isNull);
        expect(project.forecastAmount, isNull);
        expect(project.contractorPartyId, isNull);
        expect(project.approvedBy, isNull);
        expect(project.approvedAt, isNull);
        expect(project.version, 0);
      },
    );

    test('owner and budget/actual amounts still carry over', () async {
      final result = await projects.getById(
        workspaceId: _workspace,
        projectId: 'p1',
      );
      final project = _successValue<CapexProjectDto>(result);
      expect(project.owner, 'Hausmeister');
      expect(project.budgetAmount, 5000);
      expect(project.actualAmount, 4200);
    });

    test('getById scans every property', () async {
      final result = await projects.getById(
        workspaceId: _workspace,
        projectId: 'p-b1',
      );
      expect(_successValue<CapexProjectDto>(result).id, 'p-b1');
    });

    test('answers notFound for an unknown project', () async {
      final result = await projects.getById(
        workspaceId: _workspace,
        projectId: 'nope',
      );
      expect(_failure(result).kind, MaintenanceCapexRepositoryFailureKind.notFound);
    });

    test('answers forbidden for a foreign workspace', () async {
      final result = await projects.getById(
        workspaceId: _otherWorkspace,
        projectId: 'p1',
      );
      expect(_failure(result).kind, MaintenanceCapexRepositoryFailureKind.forbidden);
    });

    test('every mutation answers dependencyConflict', () async {
      final create = await projects.create(
        CreateCapexProjectCommand(
          context: _context,
          draft: const CapexProjectDraft(
            propertyId: _propertyA,
            projectCode: 'CX-1',
          ),
        ),
      );
      expect(
        _failure(create).kind,
        MaintenanceCapexRepositoryFailureKind.dependencyConflict,
      );

      final update = await projects.update(
        const UpdateCapexProjectCommand(
          context: _context,
          projectId: 'p1',
          expectedVersion: 0,
          changes: CapexProjectUpdateDto(),
        ),
      );
      expect(
        _failure(update).kind,
        MaintenanceCapexRepositoryFailureKind.dependencyConflict,
      );

      final transition = await projects.transitionStatus(
        const TransitionCapexProjectStatusCommand(
          context: _context,
          projectId: 'p1',
          expectedVersion: 0,
          targetStatus: CapexProjectStatus.planned,
        ),
      );
      expect(
        _failure(transition).kind,
        MaintenanceCapexRepositoryFailureKind.dependencyConflict,
      );
    });
  });
}

List<T> _successList<T>(MaintenanceCapexRepositoryResult<List<T>> result) =>
    (result as MaintenanceCapexRepositorySuccess<List<T>>).value;

T _successValue<T>(MaintenanceCapexRepositoryResult<T> result) =>
    (result as MaintenanceCapexRepositorySuccess<T>).value;

MaintenanceCapexRepositoryFailure<T> _failure<T>(
  MaintenanceCapexRepositoryResult<T> result,
) => result as MaintenanceCapexRepositoryFailure<T>;

int _epoch(int year, int month, int day) =>
    DateTime.utc(year, month, day).millisecondsSinceEpoch;

class _FakeLegacyMaintenanceCapexReadSource
    implements LegacyMaintenanceCapexReadSource {
  List<MaintenanceTicketRecord> extraTickets = <MaintenanceTicketRecord>[];
  List<RenovationProjectRecord> extraProjects = <RenovationProjectRecord>[];

  @override
  Future<List<String>> listPropertyIds() async =>
      const <String>[_propertyA, _propertyB];

  @override
  Future<List<MaintenanceTicketRecord>> listMaintenanceTickets({
    String? propertyId,
  }) async {
    final all = <MaintenanceTicketRecord>[
      _ticket(
        id: 't1',
        propertyId: _propertyA,
        unitId: 'unit-1',
        status: 'open',
        priority: 'normal',
        reportedAt: _epoch(2026, 1, 1),
        owner: 'Hausmeister',
      ),
      _ticket(
        id: 't-urgent',
        propertyId: _propertyA,
        status: 'in_progress',
        priority: 'urgent',
        reportedAt: _epoch(2026, 2, 1),
      ),
      _ticket(
        id: 't-closed',
        propertyId: _propertyA,
        status: 'closed',
        reportedAt: _epoch(2026, 3, 1),
      ),
      _ticket(
        id: 't-b1',
        propertyId: _propertyB,
        status: 'resolved',
        reportedAt: _epoch(2026, 1, 15),
      ),
      ...extraTickets,
    ];
    if (propertyId == null) {
      return all;
    }
    return all.where((t) => t.assetPropertyId == propertyId).toList();
  }

  @override
  Future<List<RenovationProjectRecord>> listCapexProjects(
    String propertyId,
  ) async {
    final all = <RenovationProjectRecord>[
      _renovation(
        id: 'p1',
        propertyId: _propertyA,
        status: 'Geplant',
        owner: 'Hausmeister',
        budgetAmount: 5000,
        actualAmount: 4200,
      ),
      _renovation(id: 'p-done', propertyId: _propertyA, status: 'Abgeschlossen'),
      _renovation(id: 'p-b1', propertyId: _propertyB, status: 'Geplant'),
      ...extraProjects,
    ];
    return all.where((p) => p.propertyId == propertyId).toList();
  }
}

MaintenanceTicketRecord _ticket({
  required String id,
  required String propertyId,
  String? unitId,
  String status = 'open',
  String priority = 'normal',
  int? reportedAt,
  String? owner,
}) {
  return MaintenanceTicketRecord(
    id: id,
    assetPropertyId: propertyId,
    unitId: unitId,
    title: 'Ticket $id',
    description: 'Description $id',
    category: 'general',
    status: status,
    priority: priority,
    reportedAt: reportedAt ?? _epoch(2026, 1, 1),
    dueAt: null,
    resolvedAt: null,
    costEstimate: null,
    costActual: null,
    vendorName: owner,
    documentId: null,
    damageLocation: null,
    insuranceCase: false,
    insuranceStatus: null,
    insuranceClaimNumber: null,
    createdAt: _epoch(2026, 1, 1),
    updatedAt: _epoch(2026, 1, 1),
  );
}

RenovationProjectRecord _renovation({
  required String id,
  required String propertyId,
  required String status,
  String? owner,
  double? budgetAmount,
  double? actualAmount,
}) {
  return RenovationProjectRecord(
    id: id,
    propertyId: propertyId,
    projectCode: 'CX-$id',
    category: 'roof',
    measure: 'Re-roofing',
    status: status,
    startDate: null,
    plannedEndDate: null,
    actualEndDate: null,
    budgetAmount: budgetAmount,
    actualAmount: actualAmount,
    owner: owner,
    nextStep: null,
    createdAt: _epoch(2026, 1, 1),
    updatedAt: _epoch(2026, 1, 1),
  );
}
