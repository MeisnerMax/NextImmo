import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/maintenance_capex/application/maintenance_capex_providers.dart';
import 'package:neximmo_app/features/maintenance_capex/application/maintenance_capex_repository.dart';
import 'package:neximmo_app/features/maintenance_capex/domain/maintenance_ticket_dto.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart'
    as portfolio;
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';
import 'package:neximmo_app/ui/screens/maintenance/maintenance_tickets_panel.dart';

const String _workspace = 'workspace-a';
const String _property = 'property-a';

void main() {
  testWidgets('renders the empty state', (tester) async {
    await _pump(tester);

    expect(find.text('Keine offenen Tickets'), findsOneWidget);
  });

  testWidgets('forbidden names the maintenance permission', (tester) async {
    await _pump(
      tester,
      searchFailure: MaintenanceCapexRepositoryFailureKind.forbidden,
    );

    expect(find.text('Kein Zugriff auf Wartungstickets'), findsOneWidget);
    expect(find.textContaining('maintenance.read'), findsOneWidget);
  });

  testWidgets('an infrastructure error offers a retry, not a raw exception', (
    tester,
  ) async {
    await _pump(
      tester,
      searchFailure: MaintenanceCapexRepositoryFailureKind.infrastructureFailure,
    );

    expect(find.text('Tickets konnten nicht geladen werden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('lists tickets across properties with status and priority badges', (
    tester,
  ) async {
    await _pump(
      tester,
      tickets: <MaintenanceTicketSummaryDto>[
        _ticket('t1', status: MaintenanceTicketStatus.newTicket),
      ],
    );

    expect(find.text('Wasserschaden'), findsOneWidget);
    expect(find.text('Neu'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    // Falls back to the raw id when no property list is loaded.
    expect(find.text(_property), findsOneWidget);
  });

  testWidgets('a version conflict surfaces its own dialog', (tester) async {
    await _pump(
      tester,
      tickets: <MaintenanceTicketSummaryDto>[
        _ticket('t1', status: MaintenanceTicketStatus.newTicket),
      ],
      transitionFailure: MaintenanceCapexRepositoryFailureKind.versionConflict,
    );

    await tester.tap(find.byType(PopupMenuButton<MaintenanceTicketStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sichtung').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Ticket wurde zwischenzeitlich geändert'),
      findsOneWidget,
    );
  });

  testWidgets('the object cell opens that property\'s maintenance panel', (
    tester,
  ) async {
    final pushed = <String>[];
    await _pump(
      tester,
      tickets: <MaintenanceTicketSummaryDto>[
        _ticket('t1', status: MaintenanceTicketStatus.newTicket),
      ],
      onPushRoute: pushed.add,
    );

    await tester.tap(find.widgetWithText(TextButton, _property));
    await tester.pumpAndSettle();

    // The property-scoped panel has no sidebar destination of its own, so
    // this list is its only in-app entry point.
    expect(pushed, <String>['/property-maintenance/$_property']);
  });

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
          _ticket('t2', status: MaintenanceTicketStatus.resolved),
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
  MaintenanceCapexRepositoryFailureKind? searchFailure,
  MaintenanceCapexRepositoryFailureKind? transitionFailure,
  ValueChanged<String>? onPushRoute,
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
            permissions: const <String>{
              'maintenance.read',
              'maintenance.manage',
            },
            mutationsSupported: true,
          ),
        ),
        maintenanceTicketSearchProvider.overrideWithValue(
          _FakeSearch(tickets: tickets, failure: searchFailure),
        ),
        maintenanceTicketRepositoryProvider.overrideWithValue(
          _FakeRepository(transitionFailure: transitionFailure),
        ),
        referenceSliceControllerProvider.overrideWith(
          (ref) => _FakeReferenceSliceController(),
        ),
      ],
      child: MaterialApp(
        home: const Scaffold(body: MaintenanceTicketsPanel()),
        onGenerateRoute: (settings) {
          onPushRoute?.call(settings.name ?? '');
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: SizedBox.shrink()),
          );
        },
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

class _FakeSearch implements MaintenanceTicketSearchPort {
  _FakeSearch({required this.tickets, this.failure});

  final List<MaintenanceTicketSummaryDto> tickets;
  final MaintenanceCapexRepositoryFailureKind? failure;

  @override
  Future<MaintenanceCapexRepositoryResult<List<MaintenanceTicketSummaryDto>>>
  search(MaintenanceTicketListQuery query) async {
    throw UnimplementedError();
  }

  @override
  Future<MaintenanceCapexRepositoryResult<List<MaintenanceTicketSummaryDto>>>
  searchWorkspace(WorkspaceMaintenanceTicketListQuery query) async {
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
}

class _FakeRepository implements MaintenanceTicketRepository {
  _FakeRepository({this.transitionFailure});

  final MaintenanceCapexRepositoryFailureKind? transitionFailure;

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
  transitionStatus(TransitionMaintenanceTicketStatusCommand command) async {
    final failure = transitionFailure;
    if (failure == MaintenanceCapexRepositoryFailureKind.versionConflict) {
      return MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>(
        kind: failure!,
        message: 'stale',
        versionConflict: MaintenanceCapexVersionConflict(
          expectedVersion: command.expectedVersion,
          actualVersion: command.expectedVersion + 1,
          currentTicket: MaintenanceTicketDto(
            id: command.ticketId,
            workspaceId: _workspace,
            propertyId: _property,
            title: 'Wasserschaden',
            status: MaintenanceTicketStatus.newTicket,
            priority: MaintenanceTicketPriority.normal,
            reportedAt: DateTime.utc(2026, 1, 1),
            version: command.expectedVersion + 1,
            category: 'general',
            insuranceCase: false,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
            createdBy: 'actor-1',
            updatedBy: 'actor-1',
          ),
        ),
      );
    }
    if (failure != null) {
      return MaintenanceCapexRepositoryFailure<MaintenanceTicketDto>(
        kind: failure,
        message: 'fail',
      );
    }
    return MaintenanceCapexRepositorySuccess<MaintenanceTicketDto>(
      MaintenanceTicketDto(
        id: command.ticketId,
        workspaceId: _workspace,
        propertyId: _property,
        title: 'Wasserschaden',
        status: command.targetStatus,
        priority: MaintenanceTicketPriority.normal,
        reportedAt: DateTime.utc(2026, 1, 1),
        version: command.expectedVersion + 1,
        category: 'general',
        insuranceCase: false,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        createdBy: 'actor-1',
        updatedBy: 'actor-1',
      ),
    );
  }
}

/// A `ReferenceSliceController` whose ports are never called: the state is
/// set directly, and this panel never triggers a load through it.
class _FakeReferenceSliceController extends ReferenceSliceController {
  _FakeReferenceSliceController()
    : super(
        identityRepository: _NoopIdentityAccessRepository(),
        propertyRepository: _NoopPortfolioPropertyRepository(),
      ) {
    state = const ReferenceSliceState(
      authPhase: ReferenceAuthPhase.authenticated,
      workspacePhase: WorkspacePhase.selected,
      propertyListPhase: PropertyListPhase.ready,
      propertyDetailPhase: PropertyDetailPhase.idle,
      mutationPhase: PropertyMutationPhase.idle,
      properties: <PropertySummaryDto>[],
    );
  }
}

class _NoopIdentityAccessRepository implements IdentityAccessRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopPortfolioPropertyRepository implements portfolio.PropertyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
