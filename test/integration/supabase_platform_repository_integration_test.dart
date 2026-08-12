import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_domain_event.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_query_invalidation_source.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/data/supabase_domain_event_consumer_adapter.dart';
import 'package:neximmo_app/features/platform_audit_jobs/data/supabase_outbox_adapter.dart';
import 'package:neximmo_app/features/platform_audit_jobs/data/supabase_platform_repository_adapter.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/import_job_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/notification_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/search_entry_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const workspaceId = 'f1000000-0000-0000-0000-000000000001';
  const foreignWorkspaceId = 'f1000000-0000-0000-0000-000000000002';
  const managerId = 'fa000000-0000-0000-0000-000000000001';
  const recipientId = 'fa000000-0000-0000-0000-000000000002';
  const propertyId = 'f5000000-0000-0000-0000-000000000001';
  const propertyRef = PlatformEntityRef(
    type: PlatformEntityType.property,
    id: propertyId,
  );

  var mutationCounter = 0;
  PlatformCommandContext context(
    String actorId, {
    String? reason,
    String workspace = workspaceId,
  }) {
    mutationCounter++;
    final suffix = mutationCounter.toString().padLeft(2, '0');
    return PlatformCommandContext(
      workspaceId: workspace,
      actorId: actorId,
      mutationId: 'f6000000-0000-0000-0000-0000000000$suffix',
      correlationId: 'f7000000-0000-0000-0000-0000000000$suffix',
      reason: reason,
    );
  }

  // These tests need the local Supabase harness (a running stack plus the
  // SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY dart-defines that `tool/
  // verify_p2_d04_integration.ps1` supplies). Under a plain `flutter test` the
  // defines are absent, so each test skips rather than failing — matching the
  // document integration test, and keeping the ordinary suite self-contained.
  final skipWithoutHarness = url.isEmpty || publishableKey.isEmpty
      ? 'Requires the local Supabase integration harness.'
      : false;

  void requireLocalStack() {
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
  }

  // Every test in this file signs the same two users in again, and GoTrue
  // refuses a second enrolment from an aal1 session once a factor is verified
  // (403 insufficient_aal). The first sign-in for an address therefore enrols,
  // and later ones challenge that factor -- the flow a user follows on a second
  // device. Sessions opened before the enrolment are revoked by the verify, so
  // each client is created fresh here rather than reused.
  final enrolledFactors = <String, TotpTestFactor>{};

  Future<SupabaseClient> signIn(String email) async {
    final client = createSupabaseTestClient(url, publishableKey);
    await client.auth.signInWithPassword(
      email: email,
      password: 'NexImmo-Test-2026!',
    );
    final existing = enrolledFactors[email];
    if (existing == null) {
      enrolledFactors[email] = await enrolSupabaseTestClientToAal2(client);
    } else {
      await elevateSupabaseTestClientWithFactor(client, existing);
    }
    return client;
  }

  test('real client drives the STM-012 task lifecycle and the notification '
      'fan-out end to end', () async {
    requireLocalStack();

    final managerClient = await signIn('p2-d04-manager@example.test');
    final recipientClient = await signIn('p2-d04-recipient@example.test');
    try {
      final manager = SupabasePlatformRepositoryAdapter(client: managerClient);
      final recipient = SupabasePlatformRepositoryAdapter(
        client: recipientClient,
      );

      // --- create, with a real entity link ---------------------------------
      final created =
          (await manager.createTask(
                CreateTaskCommand(
                  context: context(managerId, reason: 'integration create'),
                  draft: const TaskDraft(
                    title: 'Heizungswartung',
                    entity: propertyRef,
                    description: 'Jährliche Wartung',
                    category: 'maintenance',
                    priority: TaskPriority.high,
                  ),
                ),
              ))
              as PlatformRepositorySuccess<TaskDto>;
      expect(created.value.status, TaskStatus.open);
      expect(created.value.entity, propertyRef);
      expect(created.value.version, 1);
      final taskId = created.value.id;

      // --- sparse update: clear one field, leave the rest untouched --------
      final updated =
          (await manager.updateTask(
                UpdateTaskCommand(
                  context: context(managerId),
                  taskId: taskId,
                  expectedVersion: 1,
                  changes: const TaskUpdateDto(
                    title: 'Heizungswartung 2026',
                    category: TaskFieldEdit<String>.clear(),
                  ),
                ),
              ))
              as PlatformRepositorySuccess<TaskDto>;
      expect(updated.value.title, 'Heizungswartung 2026');
      expect(updated.value.category, isNull);
      expect(updated.value.description, 'Jährliche Wartung');
      expect(updated.value.priority, TaskPriority.high);
      expect(updated.value.version, 2);

      // --- a stale version conflict carries the current entity -------------
      final conflict =
          (await manager.updateTask(
                UpdateTaskCommand(
                  context: context(managerId),
                  taskId: taskId,
                  expectedVersion: 1,
                  changes: const TaskUpdateDto(title: 'Zu spät'),
                ),
              ))
              as PlatformRepositoryFailure<TaskDto>;
      expect(conflict.kind, PlatformRepositoryFailureKind.versionConflict);
      expect(conflict.versionConflict!.actualVersion, 2);
      expect(conflict.versionConflict!.currentTask!.title, 'Heizungswartung 2026');

      // --- STM-012 walk, including the audited reopen ----------------------
      var version = 2;
      Future<TaskDto> move(TaskStatus target) async {
        final result =
            (await manager.transitionTaskStatus(
                  TransitionTaskStatusCommand(
                    context: context(managerId),
                    taskId: taskId,
                    expectedVersion: version,
                    targetStatus: target,
                  ),
                ))
                as PlatformRepositorySuccess<TaskDto>;
        version = result.value.version;
        return result.value;
      }

      expect((await move(TaskStatus.inProgress)).status, TaskStatus.inProgress);
      expect((await move(TaskStatus.blocked)).status, TaskStatus.blocked);
      expect((await move(TaskStatus.done)).status, TaskStatus.done);
      expect((await move(TaskStatus.open)).status, TaskStatus.open);
      final archived = await move(TaskStatus.archived);
      expect(archived.status, TaskStatus.archived);
      expect(archived.archivedAt, isNotNull);

      // --- archived is terminal, server-side -------------------------------
      final afterTerminal =
          (await manager.transitionTaskStatus(
                TransitionTaskStatusCommand(
                  context: context(managerId),
                  taskId: taskId,
                  expectedVersion: version,
                  targetStatus: TaskStatus.open,
                ),
              ))
              as PlatformRepositoryFailure<TaskDto>;
      expect(
        afterTerminal.kind,
        PlatformRepositoryFailureKind.validationFailed,
      );
      // And the client-side mirror agrees with the server it mirrors.
      expect(TaskStatus.archived.canTransitionTo(TaskStatus.open), isFalse);

      // --- an archived task leaves the work list but stays auditable -------
      final workList =
          (await manager.searchTasks(
                const TaskListQuery(workspaceId: workspaceId),
              ))
              as PlatformRepositorySuccess<PlatformPageResult<TaskDto>>;
      expect(workList.value.items.map((task) => task.id), isNot(contains(taskId)));
      final auditView =
          (await manager.searchTasks(
                const TaskListQuery(
                  workspaceId: workspaceId,
                  includeArchived: true,
                ),
              ))
              as PlatformRepositorySuccess<PlatformPageResult<TaskDto>>;
      expect(auditView.value.items.map((task) => task.id), contains(taskId));

      // --- AGG-019: the same generated key converges on one task -----------
      final firstGeneration =
          (await manager.createTask(
                CreateTaskCommand(
                  context: context(managerId),
                  draft: const TaskDraft(
                    title: 'Monatliche Ablesung',
                    generatedKey: 'reading/2026-07',
                  ),
                ),
              ))
              as PlatformRepositorySuccess<TaskDto>;
      final secondGeneration =
          (await manager.createTask(
                CreateTaskCommand(
                  // A fresh mutation id: this is the business-level dedup
                  // layer, not the replay layer.
                  context: context(managerId),
                  draft: const TaskDraft(
                    title: 'Monatliche Ablesung',
                    generatedKey: 'reading/2026-07',
                  ),
                ),
              ))
              as PlatformRepositorySuccess<TaskDto>;
      expect(secondGeneration.value.id, firstGeneration.value.id);
      expect(secondGeneration.value.version, firstGeneration.value.version);

      // --- fan-out: one command, one row per recipient ---------------------
      final receipt =
          (await manager.fanOutNotification(
                CreateNotificationCommand(
                  context: context(managerId, reason: 'integration fan-out'),
                  draft: const NotificationDraft(
                    recipientUserIds: <String>[managerId, recipientId],
                    kind: 'task.assigned',
                    title: 'Neue Aufgabe',
                    body: 'Heizungswartung 2026',
                    entity: propertyRef,
                  ),
                ),
              ))
              as PlatformRepositorySuccess<NotificationFanOutReceipt>;
      expect(receipt.value.recipientCount, 2);
      expect(receipt.value.notificationIds.length, 2);

      // --- the recipient sees their own row and only their own -------------
      final recipientFeed =
          (await recipient.notificationFeed(
                const NotificationFeedQuery(workspaceId: workspaceId),
              ))
              as PlatformRepositorySuccess<
                PlatformPageResult<NotificationDto>
              >;
      expect(recipientFeed.value.items.length, 1);
      expect(recipientFeed.value.items.single.recipientUserId, recipientId);
      expect(recipientFeed.value.items.single.isRead, isFalse);
      final recipientNotificationId = recipientFeed.value.items.single.id;

      // The manager holds notification.read, so it sees the whole feed.
      final managerFeed =
          (await manager.notificationFeed(
                const NotificationFeedQuery(workspaceId: workspaceId),
              ))
              as PlatformRepositorySuccess<
                PlatformPageResult<NotificationDto>
              >;
      expect(managerFeed.value.items.length, 2);

      // --- marking read is recipient-scoped and idempotent -----------------
      final read =
          (await recipient.markNotificationRead(
                MarkNotificationReadCommand(
                  context: context(recipientId),
                  notificationId: recipientNotificationId,
                ),
              ))
              as PlatformRepositorySuccess<NotificationDto>;
      expect(read.value.isRead, isTrue);

      final readAgain =
          (await recipient.markNotificationRead(
                MarkNotificationReadCommand(
                  context: context(recipientId),
                  notificationId: recipientNotificationId,
                ),
              ))
              as PlatformRepositorySuccess<NotificationDto>;
      expect(readAgain.value.readAt, read.value.readAt);

      // A foreign notification must read as not_found, never forbidden: the
      // server must not even confirm that the row exists.
      final managerNotificationId = managerFeed.value.items
          .firstWhere(
            (notification) => notification.recipientUserId == managerId,
          )
          .id;
      final foreign =
          (await recipient.markNotificationRead(
                MarkNotificationReadCommand(
                  context: context(recipientId),
                  notificationId: managerNotificationId,
                ),
              ))
              as PlatformRepositoryFailure<NotificationDto>;
      expect(foreign.kind, PlatformRepositoryFailureKind.notFound);

      final unread =
          (await recipient.notificationFeed(
                const NotificationFeedQuery(
                  workspaceId: workspaceId,
                  unreadOnly: true,
                ),
              ))
              as PlatformRepositorySuccess<
                PlatformPageResult<NotificationDto>
              >;
      expect(unread.value.items, isEmpty);
    } finally {
      await managerClient.dispose();
      await recipientClient.dispose();
    }
  }, skip: skipWithoutHarness, timeout: const Timeout(Duration(minutes: 3)));

  test('real client enforces STM-013 and the AGG-020 commit evidence, and '
      'upserts the derived search index', () async {
    requireLocalStack();

    final managerClient = await signIn('p2-d04-manager@example.test');
    try {
      final manager = SupabasePlatformRepositoryAdapter(client: managerClient);

      final job =
          (await manager.createImportJob(
                CreateImportJobCommand(
                  context: context(managerId, reason: 'integration import'),
                  draft: const ImportJobDraft(
                    sourceKind: 'sqlite.legacy',
                    targetScope: 'tasks',
                    mapping: <String, Object?>{'tasks': 'p2-d04'},
                  ),
                ),
              ))
              as PlatformRepositorySuccess<ImportJobDto>;
      expect(job.value.status, ImportJobStatus.draft);
      expect(job.value.hasCommitEvidence, isFalse);
      final jobId = job.value.id;

      final edited =
          (await manager.updateImportJob(
                UpdateImportJobCommand(
                  context: context(managerId),
                  importJobId: jobId,
                  expectedVersion: 1,
                  changes: const ImportJobUpdateDto(
                    mapping: <String, Object?>{'tasks': 'p2-d04', 'rev': 2},
                  ),
                ),
              ))
              as PlatformRepositorySuccess<ImportJobDto>;
      expect(edited.value.mapping['rev'], 2);

      final validating =
          (await manager.transitionImportJobStatus(
                TransitionImportJobStatusCommand(
                  context: context(managerId),
                  importJobId: jobId,
                  expectedVersion: 2,
                  targetStatus: ImportJobStatus.validating,
                ),
              ))
              as PlatformRepositorySuccess<ImportJobDto>;
      expect(validating.value.status, ImportJobStatus.validating);

      // --- the mapping freezes once validation begins ----------------------
      final frozen =
          (await manager.updateImportJob(
                UpdateImportJobCommand(
                  context: context(managerId),
                  importJobId: jobId,
                  expectedVersion: 3,
                  changes: const ImportJobUpdateDto(targetScope: 'units'),
                ),
              ))
              as PlatformRepositoryFailure<ImportJobDto>;
      expect(frozen.kind, PlatformRepositoryFailureKind.validationFailed);

      // --- AGG-020: no commit path without dry-run AND reconciliation ------
      final withoutEvidence =
          (await manager.transitionImportJobStatus(
                TransitionImportJobStatusCommand(
                  context: context(managerId),
                  importJobId: jobId,
                  expectedVersion: 3,
                  targetStatus: ImportJobStatus.ready,
                ),
              ))
              as PlatformRepositoryFailure<ImportJobDto>;
      expect(
        withoutEvidence.kind,
        PlatformRepositoryFailureKind.validationFailed,
      );

      // --- an artifact may not ride the wrong transition -------------------
      final wrongArtifact =
          (await manager.transitionImportJobStatus(
                TransitionImportJobStatusCommand(
                  context: context(managerId),
                  importJobId: jobId,
                  expectedVersion: 3,
                  targetStatus: ImportJobStatus.failed,
                  evidence: const ImportJobTransitionEvidence.ready(
                    manifest: <String, Object?>{'manifest_checksum': 'abc'},
                    reconciled: <String, Object?>{'rows': 3},
                  ),
                ),
              ))
              as PlatformRepositoryFailure<ImportJobDto>;
      expect(
        wrongArtifact.kind,
        PlatformRepositoryFailureKind.validationFailed,
      );

      final ready =
          (await manager.transitionImportJobStatus(
                TransitionImportJobStatusCommand(
                  context: context(managerId),
                  importJobId: jobId,
                  expectedVersion: 3,
                  targetStatus: ImportJobStatus.ready,
                  evidence: const ImportJobTransitionEvidence.ready(
                    manifest: <String, Object?>{'manifest_checksum': 'abc'},
                    reconciled: <String, Object?>{'rows': 3},
                  ),
                ),
              ))
              as PlatformRepositorySuccess<ImportJobDto>;
      expect(ready.value.status, ImportJobStatus.ready);
      expect(ready.value.hasCommitEvidence, isTrue);

      final running =
          (await manager.transitionImportJobStatus(
                TransitionImportJobStatusCommand(
                  context: context(managerId),
                  importJobId: jobId,
                  expectedVersion: ready.value.version,
                  targetStatus: ImportJobStatus.running,
                ),
              ))
              as PlatformRepositorySuccess<ImportJobDto>;
      expect(running.value.startedAt, isNotNull);

      final completed =
          (await manager.transitionImportJobStatus(
                TransitionImportJobStatusCommand(
                  context: context(managerId),
                  importJobId: jobId,
                  expectedVersion: running.value.version,
                  targetStatus: ImportJobStatus.completed,
                ),
              ))
              as PlatformRepositorySuccess<ImportJobDto>;
      expect(completed.value.finishedAt, isNotNull);
      // Terminal: a retry is a new job, never a transition out of here.
      final afterTerminal =
          (await manager.transitionImportJobStatus(
                TransitionImportJobStatusCommand(
                  context: context(managerId),
                  importJobId: jobId,
                  expectedVersion: completed.value.version,
                  targetStatus: ImportJobStatus.running,
                ),
              ))
              as PlatformRepositoryFailure<ImportJobDto>;
      expect(
        afterTerminal.kind,
        PlatformRepositoryFailureKind.validationFailed,
      );

      // --- the derived index: content-addressed upsert, last writer wins ---
      const indexContext = SearchIndexCommandContext(
        workspaceId: workspaceId,
        actorId: managerId,
      );
      final indexed =
          (await manager.reindexSearchEntry(
                const ReindexSearchEntryCommand(
                  context: indexContext,
                  entity: propertyRef,
                  content: SearchEntryContent(
                    title: 'P2-D04 Objekt',
                    subtitle: 'Berlin',
                  ),
                ),
              ))
              as PlatformRepositorySuccess<SearchEntryDto>;
      expect(indexed.value.entity, propertyRef);

      final reindexed =
          (await manager.reindexSearchEntry(
                const ReindexSearchEntryCommand(
                  context: indexContext,
                  entity: propertyRef,
                  content: SearchEntryContent(
                    title: 'P2-D04 Objekt (umbenannt)',
                    body: 'Teststrasse 4',
                  ),
                ),
              ))
              as PlatformRepositorySuccess<SearchEntryDto>;
      // Same row, new content: idempotent by construction, no version, no
      // receipt — a second projection of the same entity must never conflict.
      expect(reindexed.value.id, indexed.value.id);
      expect(reindexed.value.title, 'P2-D04 Objekt (umbenannt)');
      expect(reindexed.value.subtitle, isNull);

      final entries =
          (await manager.searchIndex(
                const SearchIndexQuery(
                  workspaceId: workspaceId,
                  entityType: PlatformEntityType.property,
                ),
              ))
              as PlatformRepositorySuccess<
                PlatformPageResult<SearchEntryDto>
              >;
      expect(entries.value.items.length, 1);

      final removed =
          (await manager.removeSearchEntry(
                const RemoveSearchEntryCommand(
                  context: indexContext,
                  entity: propertyRef,
                ),
              ))
              as PlatformRepositorySuccess<SearchEntryRemoval>;
      expect(removed.value.removed, isTrue);

      final removedAgain =
          (await manager.removeSearchEntry(
                const RemoveSearchEntryCommand(
                  context: indexContext,
                  entity: propertyRef,
                ),
              ))
              as PlatformRepositorySuccess<SearchEntryRemoval>;
      // Idempotent: removing an absent entry is a success, not an error.
      expect(removedAgain.value.removed, isFalse);
    } finally {
      await managerClient.dispose();
    }
  }, skip: skipWithoutHarness, timeout: const Timeout(Duration(minutes: 3)));

  test('real client receives the CTR-005 broadcast, can replay it from the '
      'outbox, and stays inside its workspace and permissions', () async {
    requireLocalStack();

    final managerClient = await signIn('p2-d04-manager@example.test');
    final viewerClient = await signIn('p2-d04-viewer@example.test');
    StreamSubscription<PlatformQueryInvalidation>? subscription;
    try {
      final manager = SupabasePlatformRepositoryAdapter(client: managerClient);
      final viewer = SupabasePlatformRepositoryAdapter(client: viewerClient);
      final invalidations = SupabasePlatformQueryInvalidationAdapter(
        client: managerClient,
      );

      final reconciled = Completer<void>();
      final taskEvents = <String, PlatformQueryInvalidation>{};
      var readyTopics = 0;
      subscription = invalidations
          .watchWorkspace(workspaceId: workspaceId)
          .listen((invalidation) {
            if (invalidation.isReconciliation) {
              readyTopics++;
              // One signal per topic; all three means the transport is up.
              if (readyTopics ==
                      SupabasePlatformQueryInvalidationAdapter
                          .topicPermissions
                          .length &&
                  !reconciled.isCompleted) {
                reconciled.complete();
              }
              return;
            }
            final aggregateId = invalidation.aggregateId;
            if (invalidation.aggregate == PlatformAggregate.task &&
                aggregateId != null) {
              taskEvents[aggregateId] = invalidation;
            }
          });

      await reconciled.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => fail(
          'Only $readyTopics of '
          '${SupabasePlatformQueryInvalidationAdapter.topicPermissions.length} '
          'domain-event topics became ready.',
        ),
      );

      // `subscribed` is not the same as "the server will route database
      // broadcasts here": a channel that has just joined can miss a
      // `realtime.send` fired immediately afterwards, and the outbox row is
      // durable precisely because the transport is allowed to do that. So the
      // probe is repeated rather than fired once — a single-shot assertion here
      // tests the race, not the contract. Any one of the probes arriving proves
      // the delivery path; none arriving is a real failure.
      final probeIds = <String>[];
      PlatformQueryInvalidation? delivered;
      for (var attempt = 0; attempt < 6 && delivered == null; attempt++) {
        final probe =
            (await manager.createTask(
                  CreateTaskCommand(
                    context: context(managerId, reason: 'realtime probe'),
                    draft: TaskDraft(title: 'Realtime-Sonde $attempt'),
                  ),
                ))
                as PlatformRepositorySuccess<TaskDto>;
        probeIds.add(probe.value.id);

        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(deadline) && delivered == null) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          for (final id in probeIds) {
            delivered ??= taskEvents[id];
          }
        }
      }

      expect(
        delivered,
        isNotNull,
        reason:
            'No task invalidation arrived for any of $probeIds; the CTR-005 '
            'broadcast never reached the subscriber.',
      );
      final invalidation = delivered!;
      expect(invalidation.workspaceId, workspaceId);
      expect(invalidation.eventType, 'task.created');
      expect(probeIds, contains(invalidation.aggregateId));
      final broadcastTaskId = invalidation.aggregateId!;

      // --- the outbox is the truth; the broadcast was only transport -------
      final outbox = SupabaseOutboxAdapter(client: managerClient);
      final page = await outbox.read(
        const OutboxQuery(
          workspaceId: workspaceId,
          requiredPermission: 'task.read',
        ),
      );
      expect(
        page.events.where(
          (event) =>
              event.aggregateId == broadcastTaskId &&
              event.eventType == 'task.created',
        ),
        isNotEmpty,
      );
      expect(page.events.every((event) => event.workspaceId == workspaceId), isTrue);

      // A permission the caller does not hold yields nothing rather than
      // leaking envelope existence.
      final foreignScope = await outbox.read(
        const OutboxQuery(
          workspaceId: workspaceId,
          requiredPermission: 'document.read',
        ),
      );
      expect(foreignScope.events, isEmpty);

      // --- server-side denials for a workspace.read-only member ------------
      final viewerTasks =
          (await viewer.searchTasks(
                const TaskListQuery(workspaceId: workspaceId),
              ))
              as PlatformRepositorySuccess<PlatformPageResult<TaskDto>>;
      expect(viewerTasks.value.items, isEmpty);

      final viewerCreate =
          (await viewer.createTask(
                CreateTaskCommand(
                  context: context(
                    'fa000000-0000-0000-0000-000000000003',
                  ),
                  draft: const TaskDraft(title: 'Nicht erlaubt'),
                ),
              ))
              as PlatformRepositoryFailure<TaskDto>;
      expect(viewerCreate.kind, PlatformRepositoryFailureKind.forbidden);

      final viewerReindex =
          (await viewer.reindexSearchEntry(
                const ReindexSearchEntryCommand(
                  context: SearchIndexCommandContext(
                    workspaceId: workspaceId,
                    actorId: 'fa000000-0000-0000-0000-000000000003',
                  ),
                  entity: propertyRef,
                  content: SearchEntryContent(title: 'Nicht erlaubt'),
                ),
              ))
              as PlatformRepositoryFailure<SearchEntryDto>;
      expect(viewerReindex.kind, PlatformRepositoryFailureKind.forbidden);

      final viewerJobs =
          (await viewer.searchImportJobs(
                const ImportJobListQuery(workspaceId: workspaceId),
              ))
              as PlatformRepositorySuccess<PlatformPageResult<ImportJobDto>>;
      expect(viewerJobs.value.items, isEmpty);

      // --- workspace isolation, over the real API --------------------------
      final foreignWorkspace =
          (await manager.createTask(
                CreateTaskCommand(
                  context: context(managerId, workspace: foreignWorkspaceId),
                  draft: const TaskDraft(title: 'Fremder Workspace'),
                ),
              ))
              as PlatformRepositoryFailure<TaskDto>;
      expect(
        foreignWorkspace.kind,
        PlatformRepositoryFailureKind.forbidden,
      );

      final foreignRead =
          (await manager.searchTasks(
                const TaskListQuery(workspaceId: foreignWorkspaceId),
              ))
              as PlatformRepositorySuccess<PlatformPageResult<TaskDto>>;
      expect(foreignRead.value.items, isEmpty);
    } finally {
      await subscription?.cancel();
      await managerClient.dispose();
      await viewerClient.dispose();
    }
  }, skip: skipWithoutHarness, timeout: const Timeout(Duration(minutes: 3)));
}
