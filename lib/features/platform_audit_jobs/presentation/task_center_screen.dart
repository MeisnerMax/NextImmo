/// The Task Center (TASK-CENTER-01, TASKS-V2): the one surface on which work
/// in NexImmo is created, tracked and closed — workspace-wide as
/// `GlobalPage.tasks` and property-scoped as the `Betrieb → Aufgaben`
/// embedding, with the same model and the same controls.
///
/// OD-2 governs the surface: it offers exactly what `TaskListQuery` carries —
/// no search field, no due or priority filter, no counters, no sort control,
/// no tab bar and no templates entry. The §17 pretense-regression tests pin
/// that absence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_live_updates_notice.dart';
import '../../../ui/components/nx_section_header.dart';
import '../../../ui/components/nx_split_view.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/navigation/app_navigation.dart';
import '../../../ui/templates/list_filter_template.dart';
import '../../../ui/theme/app_theme.dart';
import '../../identity_access/application/identity_access_repository.dart';
import '../../reference_slice/application/reference_slice_controller.dart';
import '../application/platform_repository.dart';
import '../application/task_center_controller.dart';
import '../domain/platform_entity_type.dart';
import '../domain/task_dto.dart';
import 'task_badges.dart';
import 'task_formatting.dart';
import 'task_status_actions.dart';
import 'widgets/entity_ref_chip.dart';
import 'widgets/task_dialogs.dart';
import 'widgets/task_row.dart';

export 'widgets/task_dialogs.dart'
    show
        TaskCreateSubmit,
        TaskEditSubmit,
        showTaskArchiveDialog,
        showTaskBlockReasonDialog,
        showTaskCreateDialog,
        showTaskEditDialog;

/// Connected entry: binds the session (auth, workspace, permissions, AAL) to
/// the task surface. [lockedContext]/[embedded] serve the Property
/// Workspace's `Betrieb → Aufgaben`; [initialTaskId] serves the
/// `/tasks/:taskId` deep link.
class TaskCenterScreen extends ConsumerStatefulWidget {
  const TaskCenterScreen({
    super.key,
    this.initialTaskId,
    this.lockedContext,
    this.embedded = false,
  });

  final String? initialTaskId;
  final PlatformEntityRef? lockedContext;
  final bool embedded;

  @override
  ConsumerState<TaskCenterScreen> createState() => _TaskCenterScreenState();
}

class _TaskCenterScreenState extends ConsumerState<TaskCenterScreen> {
  bool _initialTaskHandled = false;

  @override
  Widget build(BuildContext context) {
    final reference = ref.watch(referenceSliceControllerProvider);
    final padding = widget.embedded
        ? EdgeInsets.zero
        : EdgeInsets.all(context.adaptivePagePadding);

    final access = reference.selectedWorkspace;
    if (reference.authPhase != ReferenceAuthPhase.authenticated ||
        reference.userId == null ||
        access == null) {
      return Padding(
        padding: padding,
        child: const NxEmptyState(
          key: Key('task-center-idle'),
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Aufgaben werden nach Anmeldung und Workspace-Auswahl geladen.',
          icon: Icons.workspaces_outline,
        ),
      );
    }
    // DEC-025: every platform read and write is AAL2-gated server-side. An
    // aal1 session would see zero rows — which must render as this state,
    // never as an empty list (§10).
    if (reference.assuranceLevel != AuthenticationAssuranceLevel.aal2) {
      return Padding(
        padding: padding,
        child: const NxEmptyState(
          key: Key('task-center-aal-required'),
          title: 'Zweiter Faktor erforderlich',
          description:
              'Aufgaben sind erst nach der Zwei-Faktor-Anmeldung sichtbar.',
          icon: Icons.shield_outlined,
        ),
      );
    }

    final scope = TaskCenterScope(
      workspaceId: access.workspace.id,
      actorId: reference.userId,
      permissions: access.permissions,
      canMutate:
          reference.assuranceLevel == AuthenticationAssuranceLevel.aal2,
      lockedContext: widget.lockedContext,
    );
    if (!scope.canRead) {
      return Padding(
        padding: padding,
        child: const NxEmptyState(
          key: Key('task-center-forbidden'),
          title: 'Kein Zugriff auf Aufgaben',
          description:
              'Diese Fläche benötigt die Berechtigung (task.read).',
          icon: Icons.lock_outline,
        ),
      );
    }

    final state = ref.watch(taskCenterControllerProvider(scope));
    final controller = ref.read(taskCenterControllerProvider(scope).notifier);

    ref.listen<TaskCenterState>(taskCenterControllerProvider(scope), (
      previous,
      next,
    ) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      switch (next.actionPhase) {
        case TaskActionPhase.succeeded:
        case TaskActionPhase.failed:
          final message = next.actionMessage;
          if (message != null) {
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(message)));
          }
          controller.clearAction();
        case TaskActionPhase.idle:
        case TaskActionPhase.submitting:
          break;
      }
    });

    final initialTaskId = widget.initialTaskId;
    if (!_initialTaskHandled && initialTaskId != null) {
      _initialTaskHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          controller.openById(initialTaskId);
        }
      });
    }

    return TaskCenterView(
      state: state,
      embedded: widget.embedded,
      actorId: reference.userId,
      canManage: scope.canManage,
      onReload: () => controller.reload(),
      onLoadMore: controller.loadMore,
      onLoadMoreInColumn: controller.loadMoreInColumn,
      onSetStatusFilter: controller.setStatusFilter,
      onSetAssignedToMe: controller.setAssignedToMe,
      onSetIncludeArchived: controller.setIncludeArchived,
      onResetFilters: controller.resetFilters,
      onSetViewMode: controller.setViewMode,
      onSelectTask: controller.select,
      onCloseDetail: controller.closeDetail,
      onCreateSubmit: (draft, mutationId) => controller.createTask(
        draft: draft,
        mutationId: mutationId,
        reason: widget.embedded
            ? 'Manuell angelegt (Objekt-Aufgaben)'
            : 'Manuell angelegt (Task Center)',
      ),
      onEditSubmit: (task, changes, expectedVersion, mutationId) =>
          controller.updateTask(
            taskId: task.id,
            expectedVersion: expectedVersion,
            changes: changes,
            mutationId: mutationId,
            reason: 'Bearbeitet (Task Center)',
          ),
      onTransition: (task, target, {required mutationId, reason}) =>
          controller.transitionStatus(
            task: task,
            target: target,
            mutationId: mutationId,
            reason: reason,
          ),
      onAssignSelf: (task, assigned, mutationId) => controller
          .setAssignedToSelf(task: task, assigned: assigned, mutationId: mutationId),
      onSetSelecting: controller.setSelecting,
      onToggleSelected: controller.toggleSelected,
      onRunBulk: controller.runBulk,
      onCancelBulk: controller.cancelBulk,
      onDismissBulkReport: controller.dismissBulkReport,
      newMutationId: controller.newMutationId,
    );
  }
}

/// Presentation of the task surface, driven by state and callbacks so widget
/// tests pump it without a provider graph (Foundation/V2 convention).
class TaskCenterView extends StatefulWidget {
  const TaskCenterView({
    super.key,
    required this.state,
    required this.embedded,
    required this.actorId,
    required this.canManage,
    required this.onReload,
    required this.onLoadMore,
    required this.onLoadMoreInColumn,
    required this.onSetStatusFilter,
    required this.onSetAssignedToMe,
    required this.onSetIncludeArchived,
    required this.onResetFilters,
    required this.onSetViewMode,
    required this.onSelectTask,
    required this.onCloseDetail,
    required this.onCreateSubmit,
    required this.onEditSubmit,
    required this.onTransition,
    required this.onAssignSelf,
    required this.onSetSelecting,
    required this.onToggleSelected,
    required this.onRunBulk,
    required this.onCancelBulk,
    required this.onDismissBulkReport,
    required this.newMutationId,
    this.now,
  });

  final TaskCenterState state;
  final bool embedded;
  final String? actorId;

  /// `task.manage` (AAL is gated a level above). Without it the primary
  /// action is disabled with a tooltip and bulk is hidden entirely (§8).
  final bool canManage;

  final Future<void> Function() onReload;
  final Future<void> Function() onLoadMore;
  final Future<void> Function(TaskStatus status) onLoadMoreInColumn;
  final Future<void> Function(TaskStatus? status) onSetStatusFilter;
  final Future<void> Function(bool value) onSetAssignedToMe;
  final Future<void> Function(bool value) onSetIncludeArchived;
  final Future<void> Function() onResetFilters;
  final Future<void> Function(TaskCenterViewMode mode) onSetViewMode;
  final void Function(TaskDto task) onSelectTask;
  final VoidCallback onCloseDetail;
  final TaskCreateSubmit onCreateSubmit;
  final Future<PlatformRepositoryFailure<TaskDto>?> Function(
    TaskDto task,
    TaskUpdateDto changes,
    int expectedVersion,
    String mutationId,
  )
  onEditSubmit;
  final Future<PlatformRepositoryFailure<TaskDto>?> Function(
    TaskDto task,
    TaskStatus target, {
    required String mutationId,
    String? reason,
  })
  onTransition;
  final Future<PlatformRepositoryFailure<TaskDto>?> Function(
    TaskDto task,
    bool assigned,
    String mutationId,
  )
  onAssignSelf;
  final void Function(bool value) onSetSelecting;
  final void Function(String taskId) onToggleSelected;
  final Future<TaskBulkReport?> Function(TaskBulkAction action) onRunBulk;
  final VoidCallback onCancelBulk;
  final VoidCallback onDismissBulkReport;

  /// Intent-id factory for actions that are their own intent (status
  /// transitions, quick assign) — dialogs create their own.
  final String Function() newMutationId;

  /// Injectable clock for deterministic due chips in tests.
  final DateTime? now;

  @override
  State<TaskCenterView> createState() => _TaskCenterViewState();
}

class _TaskCenterViewState extends State<TaskCenterView> {
  bool _bulkReportFailedOnly = false;
  bool _mobileBoardCorrected = false;

  TaskCenterState get state => widget.state;

  Future<void> _openCreateDialog() async {
    await showTaskCreateDialog(
      context,
      onSubmit: widget.onCreateSubmit,
      presetEntity: state.filters.context,
      selfAssignActorId: widget.actorId,
    );
  }

  Future<void> _openEditDialog(TaskDto task) async {
    await showTaskEditDialog(
      context,
      task: task,
      selfAssignActorId: widget.actorId,
      onSubmit: (changes, expectedVersion, mutationId) =>
          widget.onEditSubmit(task, changes, expectedVersion, mutationId),
    );
  }

  Future<void> _runTransition(TaskDto task, TaskStatusAction action) async {
    String? reason;
    if (action.requiresReason) {
      reason = await showTaskBlockReasonDialog(context);
      if (reason == null) {
        return;
      }
    }
    if (action.isArchive) {
      if (!mounted) {
        return;
      }
      final confirmed = await showTaskArchiveDialog(context, task: task);
      if (confirmed != true) {
        return;
      }
    }
    await widget.onTransition(
      task,
      action.target,
      mutationId: widget.newMutationId(),
      reason: reason,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = AppLayout.viewportForWidth(constraints.maxWidth);
        final mobile = viewport == AppViewport.mobile;
        // The board is not available on mobile (§5): the toggle disappears
        // and a board state left over from a wider window falls back.
        if (mobile &&
            state.viewMode == TaskCenterViewMode.board &&
            !_mobileBoardCorrected) {
          _mobileBoardCorrected = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onSetViewMode(TaskCenterViewMode.list);
            }
          });
        }
        final body = Stack(
          children: [
            widget.embedded
                ? _buildEmbedded(context, mobile)
                : _buildStandalone(context, mobile),
            if (state.bulkRunning || state.bulkReport != null)
              _buildBulkOverlay(context),
          ],
        );
        return body;
      },
    );
  }

  Widget _buildStandalone(BuildContext context, bool mobile) {
    return ListFilterTemplate(
      title: 'Aufgaben',
      breadcrumbs: const <String>['Tagesgeschaeft', 'Aufgaben'],
      primaryAction: _newTaskButton(),
      secondaryActions: [
        OutlinedButton.icon(
          key: const Key('task-center-refresh'),
          onPressed: state.refreshing ? null : widget.onReload,
          icon: const Icon(Icons.refresh),
          label: const Text('Aktualisieren'),
        ),
      ],
      contextBar: _contextBar(context),
      filters: _filterBar(context, mobile),
      content: _content(context, mobile),
    );
  }

  Widget _buildEmbedded(BuildContext context, bool mobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxSectionHeader(
          title: 'Aufgaben',
          // §3: the property scope covers only tasks bound directly to this
          // object — tasks on its units, leases or tickets need the rollup
          // of TASK-QUERY-01 and are not silently included.
          description: 'Zeigt Aufgaben, die direkt an diesem Objekt hängen.',
          actions: [_newTaskButton()],
        ),
        if (state.liveUpdatesDegraded) ...[
          const SizedBox(height: AppSpacing.component),
          const NxLiveUpdatesNotice(key: Key('task-center-live-degraded')),
        ],
        const SizedBox(height: AppSpacing.component),
        _filterBar(context, mobile),
        const SizedBox(height: AppSpacing.component),
        Expanded(child: _content(context, mobile)),
      ],
    );
  }

  Widget _newTaskButton() {
    final button = FilledButton.icon(
      key: const Key('task-center-new'),
      onPressed: widget.canManage && !state.bulkRunning
          ? _openCreateDialog
          : null,
      icon: const Icon(Icons.add),
      label: const Text('Neue Aufgabe'),
    );
    if (widget.canManage) {
      return button;
    }
    return Tooltip(message: 'Benötigt task.manage', child: button);
  }

  Widget? _contextBar(BuildContext context) {
    final locked = state.filters.context;
    final degraded = state.liveUpdatesDegraded && !widget.embedded;
    if (locked == null && !degraded) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (degraded)
          const NxLiveUpdatesNotice(key: Key('task-center-live-degraded')),
        if (locked != null) ...[
          if (degraded) const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: EntityRefChip(entity: locked),
          ),
        ],
      ],
    );
  }

  Widget _filterBar(BuildContext context, bool mobile) {
    final isList = state.viewMode == TaskCenterViewMode.list;
    return ListFilterBar(
      trailing: mobile
          ? null
          : SegmentedButton<TaskCenterViewMode>(
              key: const Key('task-center-view-toggle'),
              segments: const [
                ButtonSegment<TaskCenterViewMode>(
                  value: TaskCenterViewMode.list,
                  label: Text('Liste'),
                  icon: Icon(Icons.view_list_outlined),
                ),
                ButtonSegment<TaskCenterViewMode>(
                  value: TaskCenterViewMode.board,
                  label: Text('Board'),
                  icon: Icon(Icons.view_kanban_outlined),
                ),
              ],
              selected: <TaskCenterViewMode>{state.viewMode},
              onSelectionChanged: (selection) =>
                  widget.onSetViewMode(selection.first),
            ),
      children: [
        if (isList)
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<TaskStatus?>(
              key: const Key('task-center-filter-status'),
              isExpanded: true,
              value: state.filters.status,
              decoration: const InputDecoration(
                labelText: 'Status',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<TaskStatus?>(
                  value: null,
                  child: Text('Alle'),
                ),
                for (final status in TaskStatus.values)
                  if (status != TaskStatus.archived)
                    DropdownMenuItem<TaskStatus?>(
                      value: status,
                      child: Text(taskStatusLabel(status)),
                    ),
              ],
              onChanged: (value) => widget.onSetStatusFilter(value),
            ),
          ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<bool>(
            key: const Key('task-center-filter-assigned'),
            isExpanded: true,
            value: state.filters.assignedToMe,
            decoration: const InputDecoration(
              labelText: 'Zuständig',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem<bool>(value: false, child: Text('Alle')),
              DropdownMenuItem<bool>(
                value: true,
                child: Text('Mir zugewiesen'),
              ),
            ],
            onChanged: (value) => widget.onSetAssignedToMe(value ?? false),
          ),
        ),
        if (isList)
          _LabeledSwitch(
            key: const Key('task-center-filter-archived'),
            label: 'Archivierte einbeziehen',
            value: state.filters.includeArchived,
            onChanged: (value) => widget.onSetIncludeArchived(value),
          ),
        if (widget.canManage && isList)
          TextButton.icon(
            key: const Key('task-center-select-toggle'),
            onPressed: state.bulkRunning
                ? null
                : () => widget.onSetSelecting(!state.selecting),
            icon: Icon(
              state.selecting
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
            ),
            label: Text(state.selecting ? 'Auswahl beenden' : 'Auswählen'),
          ),
      ],
    );
  }

  Widget _content(BuildContext context, bool mobile) {
    if (state.viewMode == TaskCenterViewMode.board && !mobile) {
      return _board(context);
    }
    final detailOpen = state.detailPhase != TaskDetailPhase.idle;
    return NxSplitView(
      list: _list(context),
      detail: _detail(context),
      showDetail: detailOpen,
      onBackToList: widget.onCloseDetail,
    );
  }

  Widget _list(BuildContext context) {
    switch (state.listPhase) {
      case TaskCenterListPhase.loading:
        return const NxCard(
          key: Key('task-center-loading'),
          child: NxListSkeleton(rows: 8, rowHeight: 56),
        );
      case TaskCenterListPhase.forbidden:
        return const NxEmptyState(
          key: Key('task-center-forbidden'),
          title: 'Kein Zugriff auf Aufgaben',
          description: 'Diese Fläche benötigt die Berechtigung (task.read).',
          icon: Icons.lock_outline,
        );
      case TaskCenterListPhase.error:
        return NxEmptyState.error(
          key: const Key('task-center-error'),
          description:
              state.message ?? 'Aufgaben sind derzeit nicht verfügbar.',
          onRetry: widget.onReload,
        );
      case TaskCenterListPhase.ready:
        break;
    }
    if (state.tasks.isEmpty) {
      if (state.hasActiveFilters) {
        return NxEmptyState(
          key: const Key('task-center-no-match'),
          title: 'Keine Treffer für diesen Filter.',
          description:
              'Kein Ergebnis in diesem Ausschnitt. Filter zurücksetzen, um '
              'alle offenen Aufgaben zu sehen.',
          icon: Icons.filter_alt_off_outlined,
          primaryAction: OutlinedButton(
            key: const Key('task-center-reset-filters'),
            onPressed: widget.onResetFilters,
            child: const Text('Filter zurücksetzen'),
          ),
        );
      }
      return NxEmptyState(
        key: const Key('task-center-empty'),
        title: 'Noch keine Aufgaben.',
        description: 'Lege die erste an.',
        icon: Icons.checklist_outlined,
        primaryAction: widget.canManage
            ? FilledButton.icon(
                key: const Key('task-center-empty-create'),
                onPressed: _openCreateDialog,
                icon: const Icon(Icons.add),
                label: const Text('Neue Aufgabe'),
              )
            : null,
      );
    }
    return NxCard(
      key: const Key('task-center-ready'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (state.refreshing)
                const Expanded(
                  child: LinearProgressIndicator(
                    key: Key('task-center-refreshing'),
                  ),
                )
              else
                Expanded(
                  // The one sort order is stated instead of offered as a
                  // control (§5/§11): a control with a single value would
                  // suggest a due sort that does not exist.
                  child: Text(
                    'Neueste zuerst',
                    key: const Key('task-center-sort-note'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              if (state.selecting)
                Text(
                  '${state.selectedIds.length}/$taskBulkLimit ausgewählt',
                  key: const Key('task-center-selected-count'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: ListView.separated(
              itemCount: state.tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                final task = state.tasks[index];
                return TaskRow(
                  task: task,
                  actorId: widget.actorId,
                  now: widget.now,
                  selected: state.selectedTask?.id == task.id,
                  selecting: state.selecting,
                  checked: state.selectedIds.contains(task.id),
                  onCheckedChanged: (_) => widget.onToggleSelected(task.id),
                  onTap: state.selecting
                      ? () => widget.onToggleSelected(task.id)
                      : () => widget.onSelectTask(task),
                );
              },
            ),
          ),
          if (state.selecting && state.selectedIds.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: _bulkActionMenu(),
            ),
          ],
          if (state.nextCursor != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Center(
              key: const Key('task-center-partial'),
              child: OutlinedButton.icon(
                key: const Key('task-center-load-more'),
                onPressed: state.loadingMore ? null : widget.onLoadMore,
                icon: const Icon(Icons.expand_more),
                label: Text(
                  state.loadingMore ? 'Lädt …' : 'Weitere Aufgaben laden',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bulkActionMenu() {
    return PopupMenuButton<TaskBulkAction>(
      key: const Key('task-center-bulk-menu'),
      onSelected: (action) => widget.onRunBulk(action),
      itemBuilder: (context) => [
        for (final action in TaskBulkAction.values)
          PopupMenuItem<TaskBulkAction>(
            key: Key('task-center-bulk-${action.name}'),
            value: action,
            child: Text(action.label),
          ),
      ],
      enabled: !state.bulkRunning,
      child: IgnorePointer(
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.playlist_add_check),
          label: Text('Massenaktion (${state.selectedIds.length})'),
        ),
      ),
    );
  }

  Widget _board(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('task-center-board'),
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final status in taskBoardStatuses) ...[
            SizedBox(width: 300, child: _boardColumn(context, status)),
            const SizedBox(width: AppSpacing.component),
          ],
        ],
      ),
    );
  }

  Widget _boardColumn(BuildContext context, TaskStatus status) {
    final column = state.board[status] ?? const TaskBoardColumn();
    // The header shows the *loaded* count, with "+" while another page
    // exists — never an invented total (§5, OD-2).
    final count = column.nextCursor == null
        ? '${column.tasks.length}'
        : '${column.tasks.length}+';
    return NxCard(
      key: Key('task-center-board-${status.wireName}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${taskStatusLabel(status)} ($count)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: switch (column.phase) {
              TaskCenterListPhase.loading => const NxListSkeleton(
                rows: 3,
                rowHeight: 48,
              ),
              TaskCenterListPhase.forbidden ||
              TaskCenterListPhase.error => Text(
                column.message ?? 'Spalte konnte nicht geladen werden.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TaskCenterListPhase.ready => ListView(
                children: [
                  if (column.tasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        'Keine Aufgaben.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  for (final task in column.tasks) ...[
                    _boardCard(context, task),
                    const SizedBox(height: 2),
                  ],
                  if (column.nextCursor != null)
                    OutlinedButton.icon(
                      key: Key(
                        'task-center-board-more-${status.wireName}',
                      ),
                      onPressed: column.loadingMore
                          ? null
                          : () => widget.onLoadMoreInColumn(status),
                      icon: const Icon(Icons.expand_more),
                      label: Text(
                        column.loadingMore ? 'Lädt …' : 'Weitere laden',
                      ),
                    ),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }

  /// Board card: the row plus an explicit "Status weiter" action — honest
  /// and testable where drag & drop would race the version token and STM-012
  /// (§5).
  Widget _boardCard(BuildContext context, TaskDto task) {
    final actions = widget.canManage
        ? taskStatusActions(task.status)
        : const <TaskStatusAction>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskRow(
          task: task,
          actorId: widget.actorId,
          now: widget.now,
          dense: true,
          selected: state.selectedTask?.id == task.id,
          onTap: () => widget.onSelectTask(task),
        ),
        if (actions.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: PopupMenuButton<TaskStatusAction>(
              key: Key('task-center-board-actions-${task.id}'),
              tooltip: 'Status ändern',
              onSelected: (action) => _runTransition(task, action),
              itemBuilder: (context) => [
                for (final action in actions)
                  PopupMenuItem<TaskStatusAction>(
                    value: action,
                    child: Text(action.label),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.more_horiz, size: 18),
              ),
            ),
          ),
      ],
    );
  }

  Widget _detail(BuildContext context) {
    switch (state.detailPhase) {
      case TaskDetailPhase.idle:
        return const NxEmptyState(
          key: Key('task-detail-idle'),
          title: 'Wähle eine Aufgabe.',
          description: 'Details erscheinen neben der Liste.',
          icon: Icons.checklist_outlined,
        );
      case TaskDetailPhase.loading:
        return const NxCard(
          key: Key('task-detail-loading'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(),
              SizedBox(height: AppSpacing.component),
              NxListSkeleton(rows: 4, rowHeight: 48),
            ],
          ),
        );
      case TaskDetailPhase.notFound:
        return const NxEmptyState(
          key: Key('task-detail-not-found'),
          title: 'Aufgabe nicht mehr verfügbar',
          description:
              'Diese Aufgabe wurde entfernt oder zusammengeführt, während '
              'die Liste geöffnet war.',
          icon: Icons.search_off_outlined,
        );
      case TaskDetailPhase.forbidden:
        return const NxEmptyState(
          key: Key('task-detail-forbidden'),
          title: 'Kein Zugriff auf diese Aufgabe',
          description: 'Das Öffnen benötigt die Berechtigung (task.read).',
          icon: Icons.lock_outline,
        );
      case TaskDetailPhase.error:
        return NxEmptyState.error(
          key: const Key('task-detail-error'),
          description:
              state.detailMessage ??
              'Die Aufgabe ist derzeit nicht verfügbar.',
          onRetry: state.selectedTask == null
              ? null
              : () => widget.onSelectTask(state.selectedTask!),
        );
      case TaskDetailPhase.ready:
        break;
    }
    final task = state.selectedTask;
    if (task == null) {
      return const SizedBox.shrink();
    }
    return _TaskDetailPanel(
      task: task,
      actorId: widget.actorId,
      canManage: widget.canManage,
      now: widget.now,
      onEdit: () => _openEditDialog(task),
      onTransition: (action) => _runTransition(task, action),
      onAssignSelf: (assigned) => widget.onAssignSelf(
        task,
        assigned,
        widget.newMutationId(),
      ),
    );
  }

  Widget _buildBulkOverlay(BuildContext context) {
    final report = state.bulkReport;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black38,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: NxCard(
              key: const Key('task-center-bulk-overlay'),
              child: state.bulkRunning
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Massenaktion läuft',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.component),
                        LinearProgressIndicator(
                          value: state.bulkTotal == 0
                              ? null
                              : state.bulkDone / state.bulkTotal,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${state.bulkDone} von ${state.bulkTotal} '
                          'verarbeitet',
                          key: const Key('task-center-bulk-progress'),
                        ),
                        const SizedBox(height: AppSpacing.component),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const Key('task-center-bulk-cancel'),
                            onPressed: widget.onCancelBulk,
                            child: const Text('Abbrechen'),
                          ),
                        ),
                      ],
                    )
                  : _bulkReport(context, report!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bulkReport(BuildContext context, TaskBulkReport report) {
    final conflicts = report.countOf(TaskBulkFailureKind.versionConflict);
    final invalid = report.countOf(TaskBulkFailureKind.invalidTransition);
    final other = report.countOf(TaskBulkFailureKind.failed);
    final skippedParts = <String>[
      if (conflicts > 0) '$conflicts Versionskonflikte',
      if (invalid > 0) '$invalid unzulässige Statuswechsel',
      if (other > 0) '$other Fehler',
    ];
    final entries = _bulkReportFailedOnly
        ? report.failures
              .map((failure) => (task: failure.task, failure: failure))
              .toList()
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Massenaktion abgeschlossen',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          key: const Key('task-center-bulk-report'),
          '${report.succeeded} von ${report.total} aktualisiert.'
          '${report.failures.isEmpty ? '' : ' ${report.failures.length} '
                'übersprungen (${skippedParts.join(', ')}).'}'
          '${report.cancelled ? ' Abgebrochen — nicht verarbeitete Zeilen '
                'blieben unverändert.' : ''}',
        ),
        if (report.failures.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          _LabeledSwitch(
            key: const Key('task-center-bulk-failed-only'),
            label: 'Nur fehlgeschlagene anzeigen',
            value: _bulkReportFailedOnly,
            onChanged: (value) =>
                setState(() => _bulkReportFailedOnly = value),
          ),
          if (entries != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in entries)
                    ListTile(
                      dense: true,
                      title: Text(
                        entry.task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry.failure.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.component),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const Key('task-center-bulk-close'),
            onPressed: () {
              setState(() => _bulkReportFailedOnly = false);
              widget.onDismissBulkReport();
            },
            child: const Text('Schließen'),
          ),
        ),
      ],
    );
  }
}

class _LabeledSwitch extends StatelessWidget {
  const _LabeledSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(value: value, onChanged: onChanged),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _TaskDetailPanel extends StatelessWidget {
  const _TaskDetailPanel({
    required this.task,
    required this.actorId,
    required this.canManage,
    required this.onEdit,
    required this.onTransition,
    required this.onAssignSelf,
    this.now,
  });

  final TaskDto task;
  final String? actorId;
  final bool canManage;
  final VoidCallback onEdit;
  final void Function(TaskStatusAction action) onTransition;
  final void Function(bool assigned) onAssignSelf;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = taskDueLabel(task.dueAt, now: now ?? DateTime.now());
    final actions = taskStatusActions(task.status);
    final archived = task.status == TaskStatus.archived;
    final editButton = OutlinedButton.icon(
      key: const Key('task-detail-edit'),
      // §6.2: an archived task cannot be edited — disabled instead of
      // provoking the server error.
      onPressed: canManage && !archived ? onEdit : null,
      icon: const Icon(Icons.edit_outlined),
      label: const Text('Bearbeiten'),
    );
    return NxCard(
      key: const Key('task-detail'),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TaskStatusBadge(status: task.status),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (task.entity != null)
                  EntityRefChip(
                    entity: task.entity!,
                    onOpen: task.entity!.type == PlatformEntityType.property
                        ? () => Navigator.of(context).pushNamed(
                            referencePropertyRoute(task.entity!.id),
                          )
                        : null,
                  ),
                if (task.priority == TaskPriority.high)
                  const NxStatusBadge(
                    label: 'Hoch',
                    kind: NxBadgeKind.warning,
                  ),
                if (due != null) NxStatusBadge(label: due.text, kind: due.kind),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            _fact(
              theme,
              'Zuständig',
              task.assignedTo == null
                  ? '—'
                  : (task.assignedTo == actorId ? 'Mir zugewiesen' : 'Zugewiesen'),
            ),
            _fact(
              theme,
              'Fälligkeit',
              task.dueAt == null ? '—' : formatTaskDate(task.dueAt!),
            ),
            _fact(theme, 'Priorität', taskPriorityLabel(task.priority)),
            _fact(
              theme,
              'Kategorie',
              taskCategoryDisplayLabel(task.category) ?? '—',
            ),
            if (archived && task.archivedAt != null)
              _fact(theme, 'Archiviert am', formatTaskDate(task.archivedAt!)),
            if (task.isGenerated)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  key: const Key('task-detail-generated'),
                  'Aus einer Vorlage erzeugt.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (task.description != null &&
                task.description!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.component),
              Text('Beschreibung', style: theme.textTheme.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(task.description!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.component),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                editButton,
                if (canManage)
                  task.assignedTo == actorId
                      ? OutlinedButton(
                          key: const Key('task-detail-unassign'),
                          onPressed: archived
                              ? null
                              : () => onAssignSelf(false),
                          child: const Text('Zuweisung entfernen'),
                        )
                      : OutlinedButton(
                          key: const Key('task-detail-assign-self'),
                          onPressed: archived ? null : () => onAssignSelf(true),
                          child: const Text('Mir zuweisen'),
                        ),
                for (final action in actions)
                  if (canManage)
                    action.isArchive
                        ? OutlinedButton(
                            key: Key('task-detail-action-${action.target.wireName}'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                            ),
                            onPressed: () => onTransition(action),
                            child: Text(action.label),
                          )
                        : FilledButton.tonal(
                            key: Key('task-detail-action-${action.target.wireName}'),
                            onPressed: () => onTransition(action),
                            child: Text(action.label),
                          ),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            Text(
              'Erstellt ${formatTaskDate(task.createdAt)} · Geändert '
              '${formatTaskDate(task.updatedAt)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fact(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: theme.textTheme.labelMedium),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
