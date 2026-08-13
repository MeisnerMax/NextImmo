import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/maintenance_capex/application/maintenance_capex_repository.dart';
import 'package:neximmo_app/features/maintenance_capex/data/supabase_maintenance_capex_repository_adapter.dart';
import 'package:neximmo_app/features/maintenance_capex/domain/capex_project_dto.dart';
import 'package:neximmo_app/features/maintenance_capex/domain/maintenance_ticket_dto.dart';

import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const workspaceId = 'e1000000-0000-0000-0000-000000000001';
  const propertyId = 'e5000000-0000-0000-0000-000000000001';
  const managerId = 'ea000000-0000-0000-0000-000000000001';
  const approverId = 'ea000000-0000-0000-0000-000000000002';
  const contractorPartyId = 'e6000000-0000-0000-0000-000000000001';
  const nonContractorPartyId = 'e6000000-0000-0000-0000-000000000002';

  var mutationCounter = 0;
  MaintenanceCapexCommandContext context({
    String actorId = managerId,
    String? reason,
  }) {
    mutationCounter++;
    final suffix = mutationCounter.toString().padLeft(3, '0');
    return MaintenanceCapexCommandContext(
      workspaceId: workspaceId,
      actorId: actorId,
      mutationId: 'e8000000-0000-0000-0000-000000000$suffix',
      correlationId: 'e9000000-0000-0000-0000-000000000$suffix',
      reason: reason,
    );
  }

  test(
    'real client drives the maintenance_capex lifecycle end to end',
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
      final approverClient = createSupabaseTestClient(url, publishableKey);
      final viewerClient = createSupabaseTestClient(url, publishableKey);
      try {
        await managerClient.auth.signInWithPassword(
          email: 'p2-d06-manager@example.test',
          password: 'NexImmo-Test-2026!',
        );
        await elevateSupabaseTestClientToAal2(managerClient);
        final tickets = SupabaseMaintenanceTicketRepositoryAdapter(
          client: managerClient,
        );
        final projects = SupabaseCapexProjectRepositoryAdapter(
          client: managerClient,
        );

        // --- Maintenance tickets (STM-006, AGG-008) -----------------------

        final ticket = _success<MaintenanceTicketDto>(
          await tickets.create(
            CreateMaintenanceTicketCommand(
              context: context(),
              draft: const MaintenanceTicketDraft(
                propertyId: propertyId,
                title: 'Wasserschaden Bad',
                priority: MaintenanceTicketPriority.high,
                costEstimate: 800,
                currencyCode: 'EUR',
                contractorPartyId: contractorPartyId,
                damageLocation: 'Badezimmer EG',
                insuranceCase: true,
              ),
            ),
          ),
        );
        expect(ticket.version, 1);
        expect(ticket.status, MaintenanceTicketStatus.newTicket);
        expect(ticket.contractorPartyId, contractorPartyId);

        // A contractor party without an open contractor role is refused.
        final invalidContractor = await tickets.create(
          CreateMaintenanceTicketCommand(
            context: context(),
            draft: const MaintenanceTicketDraft(
              propertyId: propertyId,
              title: 'Fenster undicht',
              contractorPartyId: nonContractorPartyId,
            ),
          ),
        );
        expect(
          _failure(invalidContractor).kind,
          MaintenanceCapexRepositoryFailureKind.dependencyConflict,
        );

        // STM-006 moves one step at a time; skipping is refused.
        final skipped = await tickets.transitionStatus(
          TransitionMaintenanceTicketStatusCommand(
            context: context(),
            ticketId: ticket.id,
            expectedVersion: ticket.version,
            targetStatus: MaintenanceTicketStatus.commissioned,
          ),
        );
        expect(
          _failure(skipped).kind,
          MaintenanceCapexRepositoryFailureKind.validationFailed,
        );

        var current = await _walk(tickets, context, ticket, <
          MaintenanceTicketStatus
        >[
          MaintenanceTicketStatus.triage,
          MaintenanceTicketStatus.quoteRequested,
          MaintenanceTicketStatus.commissioned,
          MaintenanceTicketStatus.scheduled,
          MaintenanceTicketStatus.inProgress,
          MaintenanceTicketStatus.waiting,
          MaintenanceTicketStatus.inProgress,
        ]);
        expect(current.resolvedAt, isNull);

        final resolved = _success<MaintenanceTicketDto>(
          await tickets.transitionStatus(
            TransitionMaintenanceTicketStatusCommand(
              context: context(),
              ticketId: current.id,
              expectedVersion: current.version,
              targetStatus: MaintenanceTicketStatus.resolved,
              costActual: 750,
            ),
          ),
        );
        expect(resolved.status, MaintenanceTicketStatus.resolved);
        expect(resolved.resolvedAt, isNotNull);
        expect(resolved.costActual, 750);

        // The one reopen edge STM-006 allows clears resolved_at again.
        final reopened = _success<MaintenanceTicketDto>(
          await tickets.transitionStatus(
            TransitionMaintenanceTicketStatusCommand(
              context: context(),
              ticketId: resolved.id,
              expectedVersion: resolved.version,
              targetStatus: MaintenanceTicketStatus.inProgress,
            ),
          ),
        );
        expect(reopened.resolvedAt, isNull);

        current = await _walk(tickets, context, reopened, <
          MaintenanceTicketStatus
        >[
          MaintenanceTicketStatus.resolved,
          MaintenanceTicketStatus.invoiced,
          MaintenanceTicketStatus.archived,
        ]);
        expect(current.status, MaintenanceTicketStatus.archived);
        expect(current.resolvedAt, isNotNull);

        // A terminal ticket has no forward edge left.
        final pastArchived = await tickets.transitionStatus(
          TransitionMaintenanceTicketStatusCommand(
            context: context(),
            ticketId: current.id,
            expectedVersion: current.version,
            targetStatus: MaintenanceTicketStatus.invoiced,
          ),
        );
        expect(
          _failure(pastArchived).kind,
          MaintenanceCapexRepositoryFailureKind.validationFailed,
        );

        // A sparse patch only changes what it sends.
        final patched = _success<MaintenanceTicketDto>(
          await tickets.update(
            UpdateMaintenanceTicketCommand(
              context: context(),
              ticketId: current.id,
              expectedVersion: current.version,
              changes: const MaintenanceTicketUpdateDto(
                insuranceStatus: 'eingereicht',
              ),
            ),
          ),
        );
        expect(patched.insuranceStatus, 'eingereicht');
        expect(patched.title, current.title);
        expect(patched.priority, current.priority);

        // A stale expected version returns a structured conflict carrying the
        // current ticket, not a bare error.
        final stale = await tickets.update(
          UpdateMaintenanceTicketCommand(
            context: context(),
            ticketId: current.id,
            expectedVersion: current.version,
            changes: const MaintenanceTicketUpdateDto(title: 'Umbenannt'),
          ),
        );
        final ticketConflict = _failure(stale);
        expect(
          ticketConflict.kind,
          MaintenanceCapexRepositoryFailureKind.versionConflict,
        );
        expect(
          ticketConflict.versionConflict?.currentTicket?.version,
          patched.version,
        );
        expect(ticketConflict.versionConflict?.currentProject, isNull);

        // --- Idempotency -----------------------------------------------

        final replayContext = context();
        final firstTicket = _success<MaintenanceTicketDto>(
          await tickets.create(
            CreateMaintenanceTicketCommand(
              context: replayContext,
              draft: const MaintenanceTicketDraft(
                propertyId: propertyId,
                title: 'Idempotenz-Test',
              ),
            ),
          ),
        );
        final replay = _success<MaintenanceTicketDto>(
          await tickets.create(
            CreateMaintenanceTicketCommand(
              context: replayContext,
              draft: const MaintenanceTicketDraft(
                propertyId: propertyId,
                title: 'Idempotenz-Test',
              ),
            ),
          ),
        );
        expect(replay.id, firstTicket.id);
        expect(replay.version, firstTicket.version);

        // --- Search ------------------------------------------------------

        final searched = _successList<MaintenanceTicketSummaryDto>(
          await tickets.search(
            const MaintenanceTicketListQuery(
              workspaceId: workspaceId,
              propertyId: propertyId,
              priority: MaintenanceTicketPriority.high,
            ),
          ),
        );
        expect(searched.map((t) => t.id), contains(ticket.id));

        // The workspace-wide read (P2-D06 follow-up) needs no property id at
        // all and still finds the same ticket.
        final workspaceSearched = _successList<MaintenanceTicketSummaryDto>(
          await tickets.searchWorkspace(
            const WorkspaceMaintenanceTicketListQuery(
              workspaceId: workspaceId,
              priority: MaintenanceTicketPriority.high,
            ),
          ),
        );
        expect(workspaceSearched.map((t) => t.id), contains(ticket.id));

        // --- CapEx projects (STM-007, AGG-009) ----------------------------

        final project = _success<CapexProjectDto>(
          await projects.create(
            CreateCapexProjectCommand(
              context: context(),
              draft: const CapexProjectDraft(
                propertyId: propertyId,
                projectCode: 'CX-2026-01',
                budgetAmount: 20000,
                currencyCode: 'EUR',
                contractorPartyId: contractorPartyId,
              ),
            ),
          ),
        );
        expect(project.status, CapexProjectStatus.idea);
        expect(project.version, 1);

        // STM-007 is strictly linear; skipping straight to quoteRequested
        // (past planned) is refused. Skipping to `approved` is tested
        // separately below — that target hits the `capex.approve` permission
        // gate before the STM-007 check even runs, which is a different
        // failure kind and not what this case is about.
        final skippedCapex = await projects.transitionStatus(
          TransitionCapexProjectStatusCommand(
            context: context(),
            projectId: project.id,
            expectedVersion: project.version,
            targetStatus: CapexProjectStatus.quoteRequested,
          ),
        );
        expect(
          _failure(skippedCapex).kind,
          MaintenanceCapexRepositoryFailureKind.validationFailed,
        );

        final quoteRequested = await _walkProject(projects, context, project, <
          CapexProjectStatus
        >[CapexProjectStatus.planned, CapexProjectStatus.quoteRequested]);

        // The manager holds capex.manage but not capex.approve: the gate is
        // its own permission, not folded into capex.manage.
        final managerApproveAttempt = await projects.transitionStatus(
          TransitionCapexProjectStatusCommand(
            context: context(),
            projectId: quoteRequested.id,
            expectedVersion: quoteRequested.version,
            targetStatus: CapexProjectStatus.approved,
          ),
        );
        expect(
          _failure(managerApproveAttempt).kind,
          MaintenanceCapexRepositoryFailureKind.forbidden,
        );

        await approverClient.auth.signInWithPassword(
          email: 'p2-d06-approver@example.test',
          password: 'NexImmo-Test-2026!',
        );
        await elevateSupabaseTestClientToAal2(approverClient);
        final approverProjects = SupabaseCapexProjectRepositoryAdapter(
          client: approverClient,
        );
        final approved = _success<CapexProjectDto>(
          await approverProjects.transitionStatus(
            TransitionCapexProjectStatusCommand(
              context: context(actorId: approverId),
              projectId: quoteRequested.id,
              expectedVersion: quoteRequested.version,
              targetStatus: CapexProjectStatus.approved,
            ),
          ),
        );
        expect(approved.approvedBy, approverId);
        expect(approved.approvedAt, isNotNull);

        final completed = await _walkProject(projects, context, approved, <
          CapexProjectStatus
        >[CapexProjectStatus.inProgress, CapexProjectStatus.completed]);
        // Auto-stamped the first time status enters completed.
        expect(completed.actualEndDate, isNotNull);

        // A project with no currency yet cannot record an actual amount.
        final bareProject = _success<CapexProjectDto>(
          await projects.create(
            CreateCapexProjectCommand(
              context: context(),
              draft: const CapexProjectDraft(
                propertyId: propertyId,
                projectCode: 'CX-2026-02',
              ),
            ),
          ),
        );
        expect(bareProject.currencyCode, isNull);
        final bareProjectPlanned = _success<CapexProjectDto>(
          await projects.transitionStatus(
            TransitionCapexProjectStatusCommand(
              context: context(),
              projectId: bareProject.id,
              expectedVersion: bareProject.version,
              targetStatus: CapexProjectStatus.planned,
            ),
          ),
        );
        final rejectedActualAmount = await projects.transitionStatus(
          TransitionCapexProjectStatusCommand(
            context: context(),
            projectId: bareProjectPlanned.id,
            expectedVersion: bareProjectPlanned.version,
            targetStatus: CapexProjectStatus.quoteRequested,
            actualAmount: 100,
          ),
        );
        expect(
          _failure(rejectedActualAmount).kind,
          MaintenanceCapexRepositoryFailureKind.validationFailed,
        );

        final projectsSearch = _successList<CapexProjectSummaryDto>(
          await projects.search(
            const CapexProjectListQuery(
              workspaceId: workspaceId,
              propertyId: propertyId,
            ),
          ),
        );
        expect(
          projectsSearch.map((p) => p.id),
          containsAll(<String>[project.id, bareProject.id]),
        );

        // --- Server-side authorization -------------------------------------

        await viewerClient.auth.signInWithPassword(
          email: 'p2-d06-viewer@example.test',
          password: 'NexImmo-Test-2026!',
        );
        await elevateSupabaseTestClientToAal2(viewerClient);
        final viewerTickets = SupabaseMaintenanceTicketRepositoryAdapter(
          client: viewerClient,
        );

        // No maintenance.read: unlike the leasing/party list reads (a raw
        // table select gated by RLS, which silently returns no rows), the
        // maintenance_capex list RPC checks `maintenance.read` explicitly and
        // answers `forbidden` — a real difference from the RLS-only domains,
        // not an oversight (see the RPC surface in the migration).
        final viewerSearch = await viewerTickets.search(
          const MaintenanceTicketListQuery(
            workspaceId: workspaceId,
            propertyId: propertyId,
          ),
        );
        expect(
          _failure(viewerSearch).kind,
          MaintenanceCapexRepositoryFailureKind.forbidden,
        );

        // No maintenance.manage: the mutation is refused as forbidden, a
        // different answer from "there is nothing here".
        final viewerMutation = await viewerTickets.transitionStatus(
          TransitionMaintenanceTicketStatusCommand(
            context: MaintenanceCapexCommandContext(
              workspaceId: workspaceId,
              actorId: 'ea000000-0000-0000-0000-000000000003',
              mutationId: 'e8000000-0000-0000-0000-000000000900',
              correlationId: 'e9000000-0000-0000-0000-000000000900',
            ),
            ticketId: current.id,
            expectedVersion: current.version,
            targetStatus: MaintenanceTicketStatus.archived,
          ),
        );
        expect(
          _failure(viewerMutation).kind,
          MaintenanceCapexRepositoryFailureKind.forbidden,
        );
      } finally {
        await viewerClient.auth.signOut();
        await approverClient.auth.signOut();
        await managerClient.auth.signOut();
      }
    },
    skip: url.isEmpty || publishableKey.isEmpty
        ? 'Requires the local Supabase integration harness.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Walks a ticket through a sequence of lawful STM-006 steps.
Future<MaintenanceTicketDto> _walk(
  SupabaseMaintenanceTicketRepositoryAdapter tickets,
  MaintenanceCapexCommandContext Function({String actorId, String? reason})
  context,
  MaintenanceTicketDto ticket,
  List<MaintenanceTicketStatus> path,
) async {
  var current = ticket;
  for (final target in path) {
    current = _success<MaintenanceTicketDto>(
      await tickets.transitionStatus(
        TransitionMaintenanceTicketStatusCommand(
          context: context(),
          ticketId: current.id,
          expectedVersion: current.version,
          targetStatus: target,
        ),
      ),
    );
  }
  return current;
}

/// Walks a project through a sequence of lawful STM-007 steps (never into
/// `approved`, which needs the separate `capex.approve` actor).
Future<CapexProjectDto> _walkProject(
  SupabaseCapexProjectRepositoryAdapter projects,
  MaintenanceCapexCommandContext Function({String actorId, String? reason})
  context,
  CapexProjectDto project,
  List<CapexProjectStatus> path,
) async {
  var current = project;
  for (final target in path) {
    current = _success<CapexProjectDto>(
      await projects.transitionStatus(
        TransitionCapexProjectStatusCommand(
          context: context(),
          projectId: current.id,
          expectedVersion: current.version,
          targetStatus: target,
        ),
      ),
    );
  }
  return current;
}

T _success<T>(MaintenanceCapexRepositoryResult<T> result) {
  if (result is MaintenanceCapexRepositoryFailure<T>) {
    fail('Expected success but got ${result.kind}: ${result.message}');
  }
  return (result as MaintenanceCapexRepositorySuccess<T>).value;
}

List<T> _successList<T>(
  MaintenanceCapexRepositoryResult<List<T>> result,
) => _success<List<T>>(result);

MaintenanceCapexRepositoryFailure<T> _failure<T>(
  MaintenanceCapexRepositoryResult<T> result,
) {
  if (result is MaintenanceCapexRepositorySuccess<T>) {
    fail('Expected a failure but the command succeeded.');
  }
  return result as MaintenanceCapexRepositoryFailure<T>;
}
