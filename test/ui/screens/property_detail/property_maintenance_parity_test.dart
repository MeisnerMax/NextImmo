import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/maintenance_capex/application/maintenance_capex_providers.dart';
import 'package:neximmo_app/features/maintenance_capex/application/maintenance_capex_repository.dart';
import 'package:neximmo_app/features/maintenance_capex/domain/capex_project_dto.dart';
import 'package:neximmo_app/features/maintenance_capex/domain/maintenance_ticket_dto.dart';
import 'package:neximmo_app/ui/screens/property_detail/property_maintenance_capex_panel.dart';

const String _workspace = 'workspace-a';
const String _property = 'property-a';

/// MAINTENANCE-PARITY-01: filters, canonical detail and edit.
///
/// Two properties of this surface are worth pinning above all others, because
/// both are easy to fake and hard to notice once faked:
///
///   * a filter is a **server** filter — it re-reads the list rather than
///     narrowing whatever page is in memory;
///   * a detail is a **canonical read by id** — not the list row, which is a
///     projection carrying a version that may already be stale.
void main() {
  group('Wartung', () {
    testWidgets('a status filter re-reads the list from the server', (
      tester,
    ) async {
      final tickets = _TicketFakes(<MaintenanceTicketSummaryDto>[
        _ticket('t1', status: MaintenanceTicketStatus.newTicket),
      ]);
      await _pump(tester, tickets: tickets);

      expect(tickets.queries, hasLength(1));
      expect(tickets.queries.single.status, isNull);

      await tester.tap(find.byKey(const Key('maintenance-filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('In Bearbeitung').last);
      await tester.pumpAndSettle();

      expect(
        tickets.queries,
        hasLength(2),
        reason: 'the filter goes to the server, not to the loaded page',
      );
      expect(tickets.queries.last.status, MaintenanceTicketStatus.inProgress);
      expect(tickets.queries.last.propertyId, _property);
    });

    testWidgets('a priority filter is sent too, and both clear together', (
      tester,
    ) async {
      final tickets = _TicketFakes(<MaintenanceTicketSummaryDto>[
        _ticket('t1', status: MaintenanceTicketStatus.newTicket),
      ]);
      await _pump(tester, tickets: tickets);

      await tester.tap(find.byKey(const Key('maintenance-filter-priority')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dringend').last);
      await tester.pumpAndSettle();

      expect(tickets.queries.last.priority, MaintenanceTicketPriority.urgent);

      await tester.tap(find.byKey(const Key('maintenance-filter-clear')));
      await tester.pumpAndSettle();

      expect(tickets.queries.last.priority, isNull);
      expect(tickets.queries.last.status, isNull);
    });

    testWidgets('an empty filtered list is not an empty property', (
      tester,
    ) async {
      final tickets = _TicketFakes(<MaintenanceTicketSummaryDto>[
        _ticket('t1', status: MaintenanceTicketStatus.newTicket),
      ]);
      await _pump(tester, tickets: tickets);

      tickets.results = const <MaintenanceTicketSummaryDto>[];
      await tester.tap(find.byKey(const Key('maintenance-filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archiviert').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('maintenance-tickets-filtered-empty')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('maintenance-tickets-empty')), findsNothing);

      await tester.tap(
        find.byKey(const Key('maintenance-tickets-filter-reset')),
      );
      await tester.pumpAndSettle();
      expect(tickets.queries.last.status, isNull);
    });

    testWidgets('selecting a ticket reads it canonically by id', (
      tester,
    ) async {
      final tickets = _TicketFakes(<MaintenanceTicketSummaryDto>[
        _ticket('t1', status: MaintenanceTicketStatus.newTicket),
      ]);
      await _pump(tester, tickets: tickets);

      await tester.tap(find.text('Wasserschaden'));
      await tester.pumpAndSettle();

      expect(
        tickets.readIds,
        <String>['t1'],
        reason: 'the row is a summary; the detail must be the server snapshot',
      );
      expect(
        find.byKey(const Key('maintenance-ticket-detail')),
        findsOneWidget,
      );
      // Fields the summary does not carry are visible now.
      expect(find.text('Rohrbruch im Keller'), findsOneWidget);
      expect(find.text('Kellerflur'), findsOneWidget);
    });

    testWidgets(
      'a detail read failure offers a retry instead of a blank pane',
      (tester) async {
        final tickets = _TicketFakes(<MaintenanceTicketSummaryDto>[
            _ticket('t1', status: MaintenanceTicketStatus.newTicket),
          ])
          ..detailFailure =
              MaintenanceCapexRepositoryFailureKind.infrastructureFailure;
        await _pump(tester, tickets: tickets);

        await tester.tap(find.text('Wasserschaden'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('maintenance-ticket-detail-error')),
          findsOneWidget,
        );
      },
    );

    testWidgets('editing sends only what changed, and shows the readback', (
      tester,
    ) async {
      final tickets = _TicketFakes(<MaintenanceTicketSummaryDto>[
        _ticket('t1', status: MaintenanceTicketStatus.newTicket),
      ]);
      await _pump(tester, tickets: tickets);
      await tester.tap(find.text('Wasserschaden'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('maintenance-ticket-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('maintenance-ticket-edit-title')),
        'Rohrbruch behoben',
      );
      await tester.tap(find.byKey(const Key('maintenance-ticket-edit-submit')));
      await tester.pumpAndSettle();

      final command = tickets.updates.single;
      expect(command.changes.title, 'Rohrbruch behoben');
      expect(
        command.changes.category,
        isNull,
        reason: 'an untouched field is not sent: the RPC coalesces per field',
      );
      expect(
        command.expectedVersion,
        7,
        reason: 'the version comes from the canonical read, not the row',
      );
      expect(find.text('Rohrbruch behoben'), findsWidgets);
    });

    testWidgets('without maintenance.manage the edit action is disabled', (
      tester,
    ) async {
      final tickets = _TicketFakes(<MaintenanceTicketSummaryDto>[
        _ticket('t1', status: MaintenanceTicketStatus.newTicket),
      ]);
      await _pump(
        tester,
        tickets: tickets,
        permissions: const <String>{'maintenance.read', 'capex.read'},
      );
      await tester.tap(find.text('Wasserschaden'));
      await tester.pumpAndSettle();

      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('maintenance-ticket-edit')),
      );
      expect(button.onPressed, isNull);
      // Disabled, not hidden, and the tooltip names what it would take.
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const Key('maintenance-ticket-edit')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, contains('maintenance.manage'));
    });
  });

  group('CapEx', () {
    testWidgets('a status filter re-reads the list from the server', (
      tester,
    ) async {
      final projects = _ProjectFakes(<CapexProjectSummaryDto>[_project('p1')]);
      await _pump(tester, projects: projects, section: _capex);

      expect(projects.queries.single.status, isNull);

      await tester.tap(find.byKey(const Key('capex-filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Geplant').last);
      await tester.pumpAndSettle();

      expect(projects.queries.last.status, CapexProjectStatus.planned);
    });

    testWidgets('selecting a project reads it canonically and shows the '
        'approval facts', (tester) async {
      final projects = _ProjectFakes(<CapexProjectSummaryDto>[_project('p1')]);
      await _pump(tester, projects: projects, section: _capex);

      await tester.tap(find.text('CX-1'));
      await tester.pumpAndSettle();

      expect(projects.readIds, <String>['p1']);
      expect(find.byKey(const Key('capex-project-detail')), findsOneWidget);
      expect(find.text('Dachsanierung'), findsOneWidget);
      // Approval is shown, never offered as an edit: it belongs to the
      // transition contract.
      expect(find.text('Freigegeben von'), findsOneWidget);
      expect(find.byKey(const Key('capex-project-edit-dialog')), findsNothing);
    });

    testWidgets('editing sends only what changed', (tester) async {
      final projects = _ProjectFakes(<CapexProjectSummaryDto>[_project('p1')]);
      await _pump(tester, projects: projects, section: _capex);
      await tester.tap(find.text('CX-1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('capex-project-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('capex-project-edit-code')),
        'CX-2',
      );
      await tester.tap(find.byKey(const Key('capex-project-edit-submit')));
      await tester.pumpAndSettle();

      final command = projects.updates.single;
      expect(command.changes.projectCode, 'CX-2');
      expect(command.changes.owner, isNull);
      expect(command.expectedVersion, 4);
    });
  });

  for (final size in const <Size>[Size(390, 844), Size(1400, 900)]) {
    testWidgets('the detail lays out without overflow at $size', (
      tester,
    ) async {
      final tickets = _TicketFakes(<MaintenanceTicketSummaryDto>[
        _ticket('t1', status: MaintenanceTicketStatus.newTicket),
      ]);
      await _pump(tester, tickets: tickets, size: size);

      await tester.tap(find.text('Wasserschaden'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('maintenance-ticket-detail')),
        findsOneWidget,
      );
    });
  }
}

const PropertyMaintenanceCapexSection _capex =
    PropertyMaintenanceCapexSection.capex;

Future<void> _pump(
  WidgetTester tester, {
  _TicketFakes? tickets,
  _ProjectFakes? projects,
  PropertyMaintenanceCapexSection section =
      PropertyMaintenanceCapexSection.maintenance,
  Set<String> permissions = const <String>{
    'maintenance.read',
    'maintenance.manage',
    'capex.read',
    'capex.manage',
    'capex.approve',
  },
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ticketFakes =
      tickets ?? _TicketFakes(const <MaintenanceTicketSummaryDto>[]);
  final projectFakes =
      projects ?? _ProjectFakes(const <CapexProjectSummaryDto>[]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: _workspace,
            actorId: 'actor-1',
            permissions: permissions,
            mutationsSupported: true,
          ),
        ),
        maintenanceTicketSearchProvider.overrideWithValue(ticketFakes),
        maintenanceTicketRepositoryProvider.overrideWithValue(ticketFakes),
        capexProjectSearchProvider.overrideWithValue(projectFakes),
        capexProjectRepositoryProvider.overrideWithValue(projectFakes),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PropertyMaintenanceCapexPanel(
            propertyId: _property,
            section: section,
            embedded: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MaintenanceTicketSummaryDto _ticket(
  String id, {
  required MaintenanceTicketStatus status,
}) => MaintenanceTicketSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  title: 'Wasserschaden',
  status: status,
  priority: MaintenanceTicketPriority.normal,
  reportedAt: DateTime.utc(2026, 1, 1),
  version: 1,
);

CapexProjectSummaryDto _project(
  String id, {
  CapexProjectStatus status = CapexProjectStatus.idea,
}) => CapexProjectSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  projectCode: 'CX-1',
  status: status,
  version: 1,
);

/// The canonical ticket carries what the summary drops, and a *different*
/// version — so a test can tell which of the two the surface used.
MaintenanceTicketDto _fullTicket({String title = 'Wasserschaden'}) =>
    MaintenanceTicketDto(
      id: 't1',
      workspaceId: _workspace,
      propertyId: _property,
      title: title,
      status: MaintenanceTicketStatus.newTicket,
      priority: MaintenanceTicketPriority.normal,
      reportedAt: DateTime.utc(2026, 1, 1),
      version: 7,
      category: 'plumbing',
      description: 'Rohrbruch im Keller',
      damageLocation: 'Kellerflur',
      insuranceCase: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      createdBy: 'actor-1',
      updatedBy: 'actor-1',
    );

CapexProjectDto _fullProject({String projectCode = 'CX-1'}) => CapexProjectDto(
  id: 'p1',
  workspaceId: _workspace,
  propertyId: _property,
  projectCode: projectCode,
  status: CapexProjectStatus.idea,
  version: 4,
  measure: 'Dachsanierung',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 2),
  createdBy: 'actor-1',
  updatedBy: 'actor-1',
);

class _TicketFakes
    implements MaintenanceTicketSearchPort, MaintenanceTicketRepository {
  _TicketFakes(this.results);

  List<MaintenanceTicketSummaryDto> results;
  final List<MaintenanceTicketListQuery> queries =
      <MaintenanceTicketListQuery>[];
  final List<String> readIds = <String>[];
  final List<UpdateMaintenanceTicketCommand> updates =
      <UpdateMaintenanceTicketCommand>[];
  MaintenanceCapexRepositoryFailureKind? detailFailure;

  @override
  Future<MaintenanceCapexRepositoryResult<List<MaintenanceTicketSummaryDto>>>
  search(MaintenanceTicketListQuery query) async {
    queries.add(query);
    return MaintenanceCapexRepositorySuccess<List<MaintenanceTicketSummaryDto>>(
      results,
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<List<MaintenanceTicketSummaryDto>>>
  searchWorkspace(WorkspaceMaintenanceTicketListQuery query) async =>
      throw UnimplementedError();

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> getById({
    required String workspaceId,
    required String ticketId,
  }) async {
    readIds.add(ticketId);
    final failure = detailFailure;
    if (failure != null) {
      return MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>(
        kind: failure,
        message: 'fail',
      );
    }
    return MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>(
      _fullTicket(),
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> create(
    CreateMaintenanceTicketCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> update(
    UpdateMaintenanceTicketCommand command,
  ) async {
    updates.add(command);
    return MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>(
      _fullTicket(title: command.changes.title ?? 'Wasserschaden'),
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>>
  transitionStatus(TransitionMaintenanceTicketStatusCommand command) async =>
      throw UnimplementedError();
}

class _ProjectFakes implements CapexProjectSearchPort, CapexProjectRepository {
  _ProjectFakes(this.results);

  List<CapexProjectSummaryDto> results;
  final List<CapexProjectListQuery> queries = <CapexProjectListQuery>[];
  final List<String> readIds = <String>[];
  final List<UpdateCapexProjectCommand> updates = <UpdateCapexProjectCommand>[];

  @override
  Future<MaintenanceCapexRepositoryResult<List<CapexProjectSummaryDto>>> search(
    CapexProjectListQuery query,
  ) async {
    queries.add(query);
    return MaintenanceCapexRepositorySuccess<List<CapexProjectSummaryDto>>(
      results,
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> getById({
    required String workspaceId,
    required String projectId,
  }) async {
    readIds.add(projectId);
    return MaintenanceCapexRepositorySuccess<CapexProjectDto>(_fullProject());
  }

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> create(
    CreateCapexProjectCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> update(
    UpdateCapexProjectCommand command,
  ) async {
    updates.add(command);
    return MaintenanceCapexRepositorySuccess<CapexProjectDto>(
      _fullProject(projectCode: command.changes.projectCode ?? 'CX-1'),
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> transitionStatus(
    TransitionCapexProjectStatusCommand command,
  ) async => throw UnimplementedError();
}
