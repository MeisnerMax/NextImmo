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

void main() {
  testWidgets('renders the empty state on both tabs', (tester) async {
    await _pump(tester);

    expect(find.text('Noch keine Tickets'), findsOneWidget);

    await tester.tap(find.text('CapEx-Projekte'));
    await tester.pumpAndSettle();
    expect(find.text('Noch kein CapEx-Projekt'), findsOneWidget);
  });

  testWidgets('a ticket-read forbidden does not block the CapEx tab', (
    tester,
  ) async {
    await _pump(
      tester,
      ticketSearchFailure: MaintenanceCapexRepositoryFailureKind.forbidden,
      projects: <CapexProjectSummaryDto>[_project('p1')],
    );

    expect(find.text('Kein Zugriff auf Tickets'), findsOneWidget);

    await tester.tap(find.text('CapEx-Projekte'));
    await tester.pumpAndSettle();
    expect(find.text('CX-1'), findsOneWidget);
  });

  testWidgets('an infrastructure error offers a retry, not a raw exception', (
    tester,
  ) async {
    await _pump(
      tester,
      ticketSearchFailure:
          MaintenanceCapexRepositoryFailureKind.infrastructureFailure,
    );

    expect(
      find.text('Tickets konnten nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('lists tickets and CapEx projects with their status badges', (
    tester,
  ) async {
    await _pump(
      tester,
      tickets: <MaintenanceTicketSummaryDto>[
        _ticket('t1', status: MaintenanceTicketStatus.newTicket),
      ],
      projects: <CapexProjectSummaryDto>[
        _project('p1', status: CapexProjectStatus.planned),
      ],
    );

    expect(find.text('Wasserschaden'), findsOneWidget);
    expect(find.text('Neu'), findsOneWidget);

    await tester.tap(find.text('CapEx-Projekte'));
    await tester.pumpAndSettle();
    expect(find.text('CX-1'), findsOneWidget);
    expect(find.text('Geplant'), findsOneWidget);
  });

  testWidgets(
    'entering approved is disabled without capex.approve even with capex.manage',
    (tester) async {
      await _pump(
        tester,
        projects: <CapexProjectSummaryDto>[
          _project('p1', status: CapexProjectStatus.quoteRequested),
        ],
        permissions: const <String>{
          'maintenance.read',
          'maintenance.manage',
          'capex.read',
          'capex.manage',
        },
      );

      await tester.tap(find.text('CapEx-Projekte'));
      await tester.pumpAndSettle();

      final approveButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.textContaining('Freigeben'),
          matching: find.byWidgetPredicate((widget) => widget is TextButton),
        ),
      );
      expect(approveButton.onPressed, isNull);
    },
  );

  for (final size in const <Size>[
    Size(390, 844),
    Size(1024, 768),
    Size(1440, 900),
  ]) {
    testWidgets('lays out without overflow at $size', (tester) async {
      await _pump(
        tester,
        tickets: <MaintenanceTicketSummaryDto>[
          _ticket('t1', status: MaintenanceTicketStatus.newTicket),
        ],
        projects: <CapexProjectSummaryDto>[
          _project('p1', status: CapexProjectStatus.planned),
        ],
        size: size,
      );

      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  List<MaintenanceTicketSummaryDto> tickets = const <MaintenanceTicketSummaryDto>[],
  List<CapexProjectSummaryDto> projects = const <CapexProjectSummaryDto>[],
  MaintenanceCapexRepositoryFailureKind? ticketSearchFailure,
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
        maintenanceTicketSearchProvider.overrideWithValue(
          _FakeTicketSearch(tickets: tickets, failure: ticketSearchFailure),
        ),
        maintenanceTicketRepositoryProvider.overrideWithValue(
          _FakeTicketRepository(),
        ),
        capexProjectSearchProvider.overrideWithValue(
          _FakeProjectSearch(projects: projects),
        ),
        capexProjectRepositoryProvider.overrideWithValue(
          _FakeProjectRepository(),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: PropertyMaintenanceCapexPanel(propertyId: _property),
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

class _FakeTicketSearch implements MaintenanceTicketSearchPort {
  _FakeTicketSearch({required this.tickets, this.failure});

  final List<MaintenanceTicketSummaryDto> tickets;
  final MaintenanceCapexRepositoryFailureKind? failure;

  @override
  Future<MaintenanceCapexRepositoryResult<List<MaintenanceTicketSummaryDto>>>
  search(MaintenanceTicketListQuery query) async {
    final failure = this.failure;
    if (failure != null) {
      return MaintenanceCapexRepositoryFailure<List<MaintenanceTicketSummaryDto>>(
        kind: failure,
        message: 'fail',
      );
    }
    return MaintenanceCapexRepositorySuccess<List<MaintenanceTicketSummaryDto>>(
      tickets,
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<List<MaintenanceTicketSummaryDto>>>
  searchWorkspace(WorkspaceMaintenanceTicketListQuery query) async =>
      throw UnimplementedError();
}

class _FakeTicketRepository implements MaintenanceTicketRepository {
  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> getById({
    required String workspaceId,
    required String ticketId,
  }) async => throw UnimplementedError();

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> create(
    CreateMaintenanceTicketCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> update(
    UpdateMaintenanceTicketCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>>
  transitionStatus(TransitionMaintenanceTicketStatusCommand command) async =>
      throw UnimplementedError();
}

class _FakeProjectSearch implements CapexProjectSearchPort {
  _FakeProjectSearch({required this.projects});

  final List<CapexProjectSummaryDto> projects;

  @override
  Future<MaintenanceCapexRepositoryResult<List<CapexProjectSummaryDto>>>
  search(CapexProjectListQuery query) async {
    return MaintenanceCapexRepositorySuccess<List<CapexProjectSummaryDto>>(
      projects,
    );
  }
}

class _FakeProjectRepository implements CapexProjectRepository {
  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> getById({
    required String workspaceId,
    required String projectId,
  }) async => throw UnimplementedError();

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> create(
    CreateCapexProjectCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> update(
    UpdateCapexProjectCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> transitionStatus(
    TransitionCapexProjectStatusCommand command,
  ) async => throw UnimplementedError();
}
