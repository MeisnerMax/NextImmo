import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_providers.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/maintenance_capex/application/maintenance_capex_providers.dart';
import 'package:neximmo_app/features/maintenance_capex/application/maintenance_capex_repository.dart';
import 'package:neximmo_app/features/maintenance_capex/domain/capex_project_dto.dart';
import 'package:neximmo_app/features/maintenance_capex/domain/maintenance_ticket_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_providers.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';
import 'package:neximmo_app/ui/screens/property_detail/property_maintenance_capex_panel.dart';

const String _workspace = 'workspace-a';
const String _property = 'property-a';

/// PROPERTY-OPERATIONS-LINKS-01: the evidence and follow-up work beside a
/// ticket.
///
/// The two zones are separately permissioned and separately loaded, so what
/// matters is that one missing capability costs only its own zone — and that a
/// zone the caller may not read says which capability it needs rather than
/// rendering as "nothing linked".
void main() {
  testWidgets('shows the linked documents and tasks of the selected ticket', (
    tester,
  ) async {
    final links = _Links();
    await _pump(tester, links);

    await tester.tap(find.text('Wasserschaden'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('record-links')), findsOneWidget);
    expect(find.text('Rechnung Klempner.pdf'), findsOneWidget);
    expect(find.text('Nachkontrolle vereinbaren'), findsOneWidget);
    // Both reads are scoped to the ticket, not to the property.
    expect(
      links.documentQueries.single.entityType,
      DocumentLinkEntityType.maintenanceTicket,
    );
    expect(links.documentQueries.single.entityId, 't1');
    expect(
      links.taskQueries.single.entity?.type,
      PlatformEntityType.maintenanceTicket,
    );
    expect(links.taskQueries.single.entity?.id, 't1');
  });

  testWidgets('without document.read only that zone is withheld, and it says '
      'which capability it needs', (tester) async {
    final links = _Links();
    await _pump(
      tester,
      links,
      permissions: const <String>{
        'maintenance.read',
        'maintenance.manage',
        'capex.read',
        'task.read',
      },
    );

    await tester.tap(find.text('Wasserschaden'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('record-links-documents-forbidden')),
      findsOneWidget,
    );
    expect(find.textContaining('document.read'), findsOneWidget);
    expect(
      links.documentQueries,
      isEmpty,
      reason: 'a read the caller may not make is not made',
    );
    // The task zone is unaffected.
    expect(find.text('Nachkontrolle vereinbaren'), findsOneWidget);
  });

  testWidgets('nothing linked is stated, not left blank', (tester) async {
    final links =
        _Links()
          ..documents = const <DocumentDto>[]
          ..tasks = const <TaskDto>[];
    await _pump(tester, links);

    await tester.tap(find.text('Wasserschaden'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('record-links-documents-empty')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('record-links-tasks-empty')), findsOneWidget);
  });

  testWidgets(
    'a failed zone reports itself without taking the record with it',
    (tester) async {
      final links = _Links()..documentFailure = true;
      await _pump(tester, links);

      await tester.tap(find.text('Wasserschaden'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('record-links-documents-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('maintenance-ticket-detail')),
        findsOneWidget,
      );
      expect(find.text('Nachkontrolle vereinbaren'), findsOneWidget);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Links links, {
  Set<String> permissions = const <String>{
    'maintenance.read',
    'maintenance.manage',
    'capex.read',
    'capex.manage',
    'document.read',
    'task.read',
  },
}) async {
  tester.view.physicalSize = const Size(1400, 900);
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
        maintenanceTicketSearchProvider.overrideWithValue(_Tickets()),
        maintenanceTicketRepositoryProvider.overrideWithValue(_Tickets()),
        capexProjectSearchProvider.overrideWithValue(_Projects()),
        capexProjectRepositoryProvider.overrideWithValue(_Projects()),
        documentRepositoryProvider.overrideWithValue(links),
        taskRepositoryProvider.overrideWithValue(links),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: PropertyMaintenanceCapexPanel(
            propertyId: _property,
            section: PropertyMaintenanceCapexSection.maintenance,
            embedded: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MaintenanceTicketDto _fullTicket() => MaintenanceTicketDto(
  id: 't1',
  workspaceId: _workspace,
  propertyId: _property,
  title: 'Wasserschaden',
  status: MaintenanceTicketStatus.newTicket,
  priority: MaintenanceTicketPriority.normal,
  reportedAt: DateTime.utc(2026, 1, 1),
  version: 3,
  category: 'plumbing',
  insuranceCase: false,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 2),
  createdBy: 'actor-1',
  updatedBy: 'actor-1',
);

class _Tickets
    implements MaintenanceTicketSearchPort, MaintenanceTicketRepository {
  @override
  Future<MaintenanceCapexRepositoryResult<List<MaintenanceTicketSummaryDto>>>
  search(MaintenanceTicketListQuery query) async {
    return MaintenanceCapexRepositorySuccess<List<MaintenanceTicketSummaryDto>>(
      <MaintenanceTicketSummaryDto>[_fullTicket().toSummary()],
    );
  }

  @override
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> getById({
    required String workspaceId,
    required String ticketId,
  }) async =>
      MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>(_fullTicket());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used by the links test');
}

class _Projects implements CapexProjectSearchPort, CapexProjectRepository {
  @override
  Future<MaintenanceCapexRepositoryResult<List<CapexProjectSummaryDto>>> search(
    CapexProjectListQuery query,
  ) async =>
      const MaintenanceCapexRepositorySuccess<List<CapexProjectSummaryDto>>(
        <CapexProjectSummaryDto>[],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used by the links test');
}

class _Links implements DocumentRepository, TaskRepository {
  final List<DocumentListQuery> documentQueries = <DocumentListQuery>[];
  final List<TaskListQuery> taskQueries = <TaskListQuery>[];
  bool documentFailure = false;

  List<DocumentDto> documents = <DocumentDto>[
    DocumentDto(
      id: 'document-1',
      workspaceId: _workspace,
      title: 'Rechnung Klempner.pdf',
      status: DocumentStatus.verified,
      currentVersionNo: 1,
      version: 1,
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
      createdBy: 'actor-1',
      updatedBy: 'actor-1',
    ),
  ];

  List<TaskDto> tasks = <TaskDto>[
    TaskDto(
      id: 'task-1',
      workspaceId: _workspace,
      title: 'Nachkontrolle vereinbaren',
      status: TaskStatus.open,
      priority: TaskPriority.normal,
      version: 1,
      createdAt: DateTime.utc(2026, 1, 3),
      updatedAt: DateTime.utc(2026, 1, 3),
      createdBy: 'actor-1',
      updatedBy: 'actor-1',
    ),
  ];

  @override
  Future<DocumentRepositoryResult<DocumentPageResult>> search(
    DocumentListQuery query,
  ) async {
    documentQueries.add(query);
    if (documentFailure) {
      return const DocumentRepositoryFailure<DocumentPageResult>(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'offline',
      );
    }
    return DocumentRepositorySuccess<DocumentPageResult>(
      DocumentPageResult(items: documents),
    );
  }

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<TaskDto>>> searchTasks(
    TaskListQuery query,
  ) async {
    taskQueries.add(query);
    return PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(
      PlatformPageResult<TaskDto>(items: tasks),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used by the links test');
}
