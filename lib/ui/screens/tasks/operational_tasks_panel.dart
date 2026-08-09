/// Cloud-native operational Tasks workplace.
///
/// Uses DOM-010 TaskRepository through [operationalTasksControllerProvider].
/// The legacy SQLite-backed TasksScreen remains untouched and is never mounted
/// by this panel.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/platform_audit_jobs/application/operational_tasks_controller.dart';
import '../../../features/platform_audit_jobs/domain/platform_entity_type.dart';
import '../../../features/platform_audit_jobs/domain/task_dto.dart';
import '../../../features/portfolio_property/domain/property_dto.dart';
import '../../../features/reference_slice/application/reference_slice_controller.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_status_badge.dart';
import '../../theme/app_theme.dart';

class OperationalTasksPanel extends ConsumerStatefulWidget {
  const OperationalTasksPanel({super.key});

  @override
  ConsumerState<OperationalTasksPanel> createState() =>
      _OperationalTasksPanelState();
}

class _OperationalTasksPanelState extends ConsumerState<OperationalTasksPanel> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedTaskId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(operationalTasksControllerProvider);
    final controller = ref.read(operationalTasksControllerProvider.notifier);
    final properties = ref.watch(referenceSliceControllerProvider).properties;
    final visible = controller.visibleTasks();
    final selected = _taskById(visible, _selectedTaskId);
    _listenForActionFeedback();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxPageHeader(
          title: 'Aufgaben',
          subtitle:
              'Operative Arbeit objektbezogen steuern: Verantwortlichkeit, '
              'Priorität, Fälligkeit und Status in einer gemeinsamen Queue.',
          primaryAction: FilledButton.icon(
            onPressed: controller.canMutate
                ? () => _createTask(controller, properties)
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Aufgabe anlegen'),
          ),
          secondaryActions: <Widget>[
            OutlinedButton.icon(
              onPressed: () => unawaited(controller.load()),
              icon: const Icon(Icons.refresh),
              label: const Text('Aktualisieren'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        _SummaryStrip(tasks: state.tasks),
        const SizedBox(height: AppSpacing.component),
        _Filters(
          state: state,
          searchController: _searchController,
          onSearchChanged: controller.setQuery,
          onStatusChanged: controller.setStatusFilter,
          onPriorityChanged: controller.setPriorityFilter,
          onAssignmentChanged: controller.setAssignmentFilter,
          onEntityChanged: controller.setEntityTypeFilter,
          onAttentionChanged: controller.setAttentionFilter,
          onClear: () {
            _searchController.clear();
            controller.clearFilters();
          },
        ),
        const SizedBox(height: AppSpacing.component),
        if (state.truncated) ...<Widget>[
          const _InfoBanner(
            message:
                'Es werden maximal 1.000 aktive Aufgaben geladen. Für größere '
                'Queues wird in einer späteren Ausbaustufe serverseitige Suche '
                'und Filter-Paginierung ergänzt.',
          ),
          const SizedBox(height: AppSpacing.component),
        ],
        Expanded(
          child: _buildContent(
            state: state,
            controller: controller,
            visible: visible,
            selected: selected,
            properties: properties,
          ),
        ),
      ],
    );
  }

  Widget _buildContent({
    required OperationalTasksState state,
    required OperationalTasksController controller,
    required List<TaskDto> visible,
    required TaskDto? selected,
    required List<PropertySummaryDto> properties,
  }) {
    switch (state.listPhase) {
      case OperationalTasksListPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Aufgaben werden je Arbeitsbereich geführt. Melde dich an oder '
              'wähle einen Arbeitsbereich.',
          icon: Icons.workspaces_outline,
        );
      case OperationalTasksListPhase.loading:
        return const _TasksSkeleton();
      case OperationalTasksListPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Aufgaben',
          description:
              'Für diesen Arbeitsbereich fehlt die Leseberechtigung '
              '(task.read).',
          icon: Icons.lock_outline,
        );
      case OperationalTasksListPhase.error:
        return NxEmptyState(
          title: 'Aufgaben konnten nicht geladen werden',
          description:
              state.message ?? 'Die Verbindung zur Datenquelle ist fehlgeschlagen.',
          icon: Icons.cloud_off_outlined,
          primaryAction: FilledButton.icon(
            onPressed: () => unawaited(controller.load()),
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case OperationalTasksListPhase.empty:
        return NxEmptyState(
          title: 'Noch keine Aufgaben',
          description: 'Lege die erste operative Aufgabe für den Arbeitsbereich an.',
          icon: Icons.checklist_outlined,
          primaryAction: controller.canMutate
              ? FilledButton.icon(
                  onPressed: () => _createTask(controller, properties),
                  icon: const Icon(Icons.add),
                  label: const Text('Aufgabe anlegen'),
                )
              : null,
        );
      case OperationalTasksListPhase.ready:
        if (visible.isEmpty) {
          return const NxEmptyState(
            title: 'Keine passenden Aufgaben',
            description: 'Für die gewählten Filter gibt es keine Treffer.',
            icon: Icons.filter_alt_off_outlined,
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 1050;
            final list = _TaskList(
              tasks: visible,
              selectedTaskId: selected?.id,
              actorId: controller.actorId,
              properties: properties,
              onSelect: (task) => setState(() => _selectedTaskId = task.id),
            );
            final detail = _TaskDetail(
              task: selected ?? visible.first,
              actorId: controller.actorId,
              properties: properties,
              canMutate: controller.canMutate,
              onEdit: (task) => _editTask(controller, task),
              onTransition: (task, target) =>
                  unawaited(controller.transitionStatus(task: task, target: target)),
            );
            if (stacked) {
              return Column(
                children: <Widget>[
                  Expanded(flex: 3, child: list),
                  const SizedBox(height: AppSpacing.component),
                  Expanded(flex: 2, child: detail),
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(flex: 3, child: list),
                const SizedBox(width: AppSpacing.component),
                Expanded(flex: 2, child: detail),
              ],
            );
          },
        );
    }
  }

  void _listenForActionFeedback() {
    ref.listen<OperationalTasksState>(operationalTasksControllerProvider, (
      previous,
      next,
    ) {
      if (previous?.actionPhase == next.actionPhase) return;
      final controller = ref.read(operationalTasksControllerProvider.notifier);
      switch (next.actionPhase) {
        case OperationalTasksActionPhase.conflict:
          unawaited(
            showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Aufgabe wurde zwischenzeitlich geändert'),
                content: Text(
                  next.versionConflict?.currentTask == null
                      ? 'Jemand anderes hat diese Aufgabe bearbeitet. Lade die '
                            'Liste neu und wiederhole deine Änderung.'
                      : 'Jemand anderes hat diese Aufgabe bearbeitet (jetzt '
                            'Version ${next.versionConflict!.currentTask!.version}). '
                            'Deine Änderung wurde nicht gespeichert.',
                ),
                actions: <Widget>[
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      controller.clearAction();
                      unawaited(controller.load());
                    },
                    child: const Text('Neu laden'),
                  ),
                ],
              ),
            ),
          );
        case OperationalTasksActionPhase.succeeded:
        case OperationalTasksActionPhase.forbidden:
        case OperationalTasksActionPhase.failed:
          final message = next.actionMessage;
          if (message != null) {
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(message)));
          }
          controller.clearAction();
        case OperationalTasksActionPhase.idle:
        case OperationalTasksActionPhase.submitting:
          return;
      }
    });
  }

  Future<void> _createTask(
    OperationalTasksController controller,
    List<PropertySummaryDto> properties,
  ) async {
    final draft = await showOperationalTaskCreateDialog(
      context,
      properties: properties,
      actorId: controller.actorId,
    );
    if (draft == null) return;
    await controller.createTask(draft);
  }

  Future<void> _editTask(
    OperationalTasksController controller,
    TaskDto task,
  ) async {
    final changes = await showOperationalTaskEditDialog(
      context,
      task: task,
      actorId: controller.actorId,
    );
    if (changes == null) return;
    await controller.updateTask(task: task, changes: changes);
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.tasks});

  final List<TaskDto> tasks;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final active = tasks.where(_isActive).toList(growable: false);
    final overdue = active
        .where((task) => task.dueAt?.toUtc().isBefore(now) ?? false)
        .length;
    final blocked = active.where((task) => task.status == TaskStatus.blocked).length;
    final dueSoon = active.where((task) {
      final due = task.dueAt?.toUtc();
      return due != null &&
          !due.isBefore(now) &&
          !due.isAfter(now.add(const Duration(days: 7)));
    }).length;

    return NxCard(
      child: Wrap(
        spacing: AppSpacing.section,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          _Metric(label: 'Aktiv', value: '${active.length}'),
          _Metric(label: 'Überfällig', value: '$overdue', critical: overdue > 0),
          _Metric(label: 'Blockiert', value: '$blocked', critical: blocked > 0),
          _Metric(label: 'Nächste 7 Tage', value: '$dueSoon'),
          _Metric(label: 'Gesamt geladen', value: '${tasks.length}'),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.critical = false});

  final String label;
  final String value;
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: critical ? semantic.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.state,
    required this.searchController,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onAssignmentChanged,
    required this.onEntityChanged,
    required this.onAttentionChanged,
    required this.onClear,
  });

  final OperationalTasksState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<TaskStatus?> onStatusChanged;
  final ValueChanged<TaskPriority?> onPriorityChanged;
  final ValueChanged<OperationalTaskAssignmentFilter> onAssignmentChanged;
  final ValueChanged<PlatformEntityType?> onEntityChanged;
  final ValueChanged<OperationalTaskAttentionFilter> onAttentionChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 250,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                labelText: 'Aufgaben durchsuchen',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          _dropdown<TaskStatus?>(
            width: 175,
            label: 'Status',
            value: state.statusFilter,
            items: <DropdownMenuItem<TaskStatus?>>[
              const DropdownMenuItem(value: null, child: Text('Alle Status')),
              for (final status in TaskStatus.values)
                if (status != TaskStatus.archived)
                  DropdownMenuItem(
                    value: status,
                    child: Text(taskStatusLabel(status)),
                  ),
            ],
            onChanged: onStatusChanged,
          ),
          _dropdown<TaskPriority?>(
            width: 165,
            label: 'Priorität',
            value: state.priorityFilter,
            items: <DropdownMenuItem<TaskPriority?>>[
              const DropdownMenuItem(value: null, child: Text('Alle')),
              for (final priority in TaskPriority.values)
                DropdownMenuItem(
                  value: priority,
                  child: Text(taskPriorityLabel(priority)),
                ),
            ],
            onChanged: onPriorityChanged,
          ),
          _dropdown<OperationalTaskAssignmentFilter>(
            width: 175,
            label: 'Zuweisung',
            value: state.assignmentFilter,
            items: const <DropdownMenuItem<OperationalTaskAssignmentFilter>>[
              DropdownMenuItem(
                value: OperationalTaskAssignmentFilter.all,
                child: Text('Alle'),
              ),
              DropdownMenuItem(
                value: OperationalTaskAssignmentFilter.mine,
                child: Text('Meine Aufgaben'),
              ),
              DropdownMenuItem(
                value: OperationalTaskAssignmentFilter.unassigned,
                child: Text('Nicht zugewiesen'),
              ),
            ],
            onChanged: (value) {
              if (value != null) onAssignmentChanged(value);
            },
          ),
          _dropdown<PlatformEntityType?>(
            width: 185,
            label: 'Kontext',
            value: state.entityTypeFilter,
            items: <DropdownMenuItem<PlatformEntityType?>>[
              const DropdownMenuItem(value: null, child: Text('Alle Kontexte')),
              for (final type in PlatformEntityType.values)
                DropdownMenuItem(
                  value: type,
                  child: Text(entityTypeLabel(type)),
                ),
            ],
            onChanged: onEntityChanged,
          ),
          _dropdown<OperationalTaskAttentionFilter>(
            width: 180,
            label: 'Attention',
            value: state.attentionFilter,
            items: const <DropdownMenuItem<OperationalTaskAttentionFilter>>[
              DropdownMenuItem(
                value: OperationalTaskAttentionFilter.all,
                child: Text('Alle'),
              ),
              DropdownMenuItem(
                value: OperationalTaskAttentionFilter.needsAttention,
                child: Text('Handlungsbedarf'),
              ),
              DropdownMenuItem(
                value: OperationalTaskAttentionFilter.overdue,
                child: Text('Überfällig'),
              ),
              DropdownMenuItem(
                value: OperationalTaskAttentionFilter.blocked,
                child: Text('Blockiert'),
              ),
              DropdownMenuItem(
                value: OperationalTaskAttentionFilter.dueSoon,
                child: Text('Nächste 7 Tage'),
              ),
            ],
            onChanged: (value) {
              if (value != null) onAttentionChanged(value);
            },
          ),
          if (state.hasActiveFilters)
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off, size: 18),
              label: const Text('Filter löschen'),
            ),
        ],
      ),
    );
  }

  static Widget _dropdown<T>({
    required double width,
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.tasks,
    required this.selectedTaskId,
    required this.actorId,
    required this.properties,
    required this.onSelect,
  });

  final List<TaskDto> tasks;
  final String? selectedTaskId;
  final String? actorId;
  final List<PropertySummaryDto> properties;
  final ValueChanged<TaskDto> onSelect;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        itemCount: tasks.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final task = tasks[index];
          final selected = task.id == selectedTaskId;
          return Material(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.22)
                : Colors.transparent,
            child: ListTile(
              selected: selected,
              onTap: () => onSelect(task),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              title: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TaskPriorityBadge(priority: task.priority),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _TaskStatusBadge(status: task.status),
                    Text(_assignmentLabel(task, actorId)),
                    Text(_contextLabel(task, properties)),
                    Text(_dueLabel(task)),
                  ],
                ),
              ),
              trailing: _attentionIcon(task),
            ),
          );
        },
      ),
    );
  }
}

class _TaskDetail extends StatelessWidget {
  const _TaskDetail({
    required this.task,
    required this.actorId,
    required this.properties,
    required this.canMutate,
    required this.onEdit,
    required this.onTransition,
  });

  final TaskDto task;
  final String? actorId;
  final List<PropertySummaryDto> properties;
  final bool canMutate;
  final ValueChanged<TaskDto> onEdit;
  final void Function(TaskDto task, TaskStatus target) onTransition;

  @override
  Widget build(BuildContext context) {
    final allowedNextStatuses = _allowedNextStatuses(task.status);
    return NxCard(
      child: ListView(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(task.title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _TaskStatusBadge(status: task.status),
                        _TaskPriorityBadge(priority: task.priority),
                      ],
                    ),
                  ],
                ),
              ),
              if (canMutate)
                IconButton(
                  tooltip: 'Aufgabe bearbeiten',
                  onPressed: () => onEdit(task),
                  icon: const Icon(Icons.edit_outlined),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.section),
          _DetailRow(label: 'Zuweisung', value: _assignmentLabel(task, actorId)),
          _DetailRow(label: 'Kontext', value: _contextLabel(task, properties)),
          _DetailRow(label: 'Kategorie', value: task.category ?? '—'),
          _DetailRow(label: 'Fälligkeit', value: _dueLabel(task)),
          _DetailRow(label: 'Version', value: '${task.version}'),
          const SizedBox(height: AppSpacing.section),
          Text('Beschreibung', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            task.description?.trim().isNotEmpty == true ? task.description! : '—',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (canMutate && allowedNextStatuses.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.section),
            Text('Status ändern', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final target in allowedNextStatuses)
                  OutlinedButton(
                    onPressed: () => onTransition(task, target),
                    child: Text(taskStatusLabel(target)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 105,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _TaskStatusBadge extends StatelessWidget {
  const _TaskStatusBadge({required this.status});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(label: taskStatusLabel(status), kind: _statusKind(status));
  }
}

class _TaskPriorityBadge extends StatelessWidget {
  const _TaskPriorityBadge({required this.priority});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: taskPriorityLabel(priority),
      kind: switch (priority) {
        TaskPriority.low => NxBadgeKind.neutral,
        TaskPriority.normal => NxBadgeKind.info,
        TaskPriority.high => NxBadgeKind.warning,
      },
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _TasksSkeleton extends StatelessWidget {
  const _TasksSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        for (var index = 0; index < 7; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
      ],
    );
  }
}

Future<TaskDraft?> showOperationalTaskCreateDialog(
  BuildContext context, {
  required List<PropertySummaryDto> properties,
  required String? actorId,
}) async {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final categoryController = TextEditingController();
  var priority = TaskPriority.normal;
  var assignment = actorId == null ? 'unassigned' : 'mine';
  var propertyContext = 'none';
  DateTime? dueDate;

  final result = await showDialog<TaskDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Aufgabe anlegen'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Titel *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Beschreibung'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(labelText: 'Kategorie'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<TaskPriority>(
                  value: priority,
                  decoration: const InputDecoration(labelText: 'Priorität'),
                  items: <DropdownMenuItem<TaskPriority>>[
                    for (final value in TaskPriority.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(taskPriorityLabel(value)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => priority = value);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: assignment,
                  decoration: const InputDecoration(labelText: 'Zuweisung'),
                  items: <DropdownMenuItem<String>>[
                    if (actorId != null)
                      const DropdownMenuItem(value: 'mine', child: Text('Mir zuweisen')),
                    const DropdownMenuItem(
                      value: 'unassigned',
                      child: Text('Nicht zugewiesen'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => assignment = value);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: propertyContext,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Objekt-Kontext'),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem(value: 'none', child: Text('Kein Objekt')),
                    for (final property in properties)
                      DropdownMenuItem(value: property.id, child: Text(property.name)),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => propertyContext = value);
                  },
                ),
                const SizedBox(height: 8),
                _DueDateField(
                  dueDate: dueDate,
                  onChanged: (value) => setDialogState(() => dueDate = value),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              Navigator.of(dialogContext).pop(
                TaskDraft(
                  title: title,
                  description: _nullableTrim(descriptionController.text),
                  category: _nullableTrim(categoryController.text),
                  assignedTo: assignment == 'mine' ? actorId : null,
                  priority: priority,
                  dueAt: dueDate,
                  entity: propertyContext == 'none'
                      ? null
                      : PlatformEntityRef(
                          type: PlatformEntityType.property,
                          id: propertyContext,
                        ),
                ),
              );
            },
            child: const Text('Anlegen'),
          ),
        ],
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    titleController.dispose();
    descriptionController.dispose();
    categoryController.dispose();
  });
  return result;
}

Future<TaskUpdateDto?> showOperationalTaskEditDialog(
  BuildContext context, {
  required TaskDto task,
  required String? actorId,
}) async {
  final titleController = TextEditingController(text: task.title);
  final descriptionController = TextEditingController(text: task.description ?? '');
  final categoryController = TextEditingController(text: task.category ?? '');
  var priority = task.priority;
  var dueDate = task.dueAt;
  final originalAssignment = task.assignedTo;
  var assignment = originalAssignment == null
      ? 'unassigned'
      : originalAssignment == actorId
      ? 'mine'
      : 'existing';

  final result = await showDialog<TaskUpdateDto>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Aufgabe bearbeiten'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Titel *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Beschreibung'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(labelText: 'Kategorie'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<TaskPriority>(
                  value: priority,
                  decoration: const InputDecoration(labelText: 'Priorität'),
                  items: <DropdownMenuItem<TaskPriority>>[
                    for (final value in TaskPriority.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(taskPriorityLabel(value)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => priority = value);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: assignment,
                  decoration: const InputDecoration(labelText: 'Zuweisung'),
                  items: <DropdownMenuItem<String>>[
                    if (originalAssignment != null && originalAssignment != actorId)
                      const DropdownMenuItem(
                        value: 'existing',
                        child: Text('Aktuelle Zuweisung beibehalten'),
                      ),
                    if (actorId != null)
                      const DropdownMenuItem(value: 'mine', child: Text('Mir zuweisen')),
                    const DropdownMenuItem(
                      value: 'unassigned',
                      child: Text('Nicht zugewiesen'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => assignment = value);
                  },
                ),
                const SizedBox(height: 8),
                _DueDateField(
                  dueDate: dueDate,
                  onChanged: (value) => setDialogState(() => dueDate = value),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              final description = _nullableTrim(descriptionController.text);
              final category = _nullableTrim(categoryController.text);
              final nextAssignedTo = switch (assignment) {
                'mine' => actorId,
                'unassigned' => null,
                _ => originalAssignment,
              };
              Navigator.of(dialogContext).pop(
                TaskUpdateDto(
                  title: title == task.title ? null : title,
                  description: _textEdit(task.description, description),
                  category: _textEdit(task.category, category),
                  assignedTo: _textEdit(task.assignedTo, nextAssignedTo),
                  priority: priority == task.priority ? null : priority,
                  dueAt: _dateEdit(task.dueAt, dueDate),
                ),
              );
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    titleController.dispose();
    descriptionController.dispose();
    categoryController.dispose();
  });
  return result;
}

class _DueDateField extends StatelessWidget {
  const _DueDateField({required this.dueDate, required this.onChanged});

  final DateTime? dueDate;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Fälligkeit'),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(dueDate == null ? '—' : _formatDate(dueDate!))),
          TextButton(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: dueDate ?? now,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 10),
              );
              if (picked != null) onChanged(picked);
            },
            child: const Text('Wählen'),
          ),
          if (dueDate != null)
            TextButton(
              onPressed: () => onChanged(null),
              child: const Text('Löschen'),
            ),
        ],
      ),
    );
  }
}

TaskDto? _taskById(List<TaskDto> tasks, String? id) {
  if (id == null) return null;
  for (final task in tasks) {
    if (task.id == id) return task;
  }
  return null;
}

List<TaskStatus> _allowedNextStatuses(TaskStatus status) => TaskStatus.values
    .where(status.canTransitionTo)
    .toList(growable: false);

bool _isActive(TaskDto task) =>
    task.status != TaskStatus.done && task.status != TaskStatus.archived;

Widget _attentionIcon(TaskDto task) {
  if (!_isActive(task)) return const SizedBox.shrink();
  final now = DateTime.now().toUtc();
  final due = task.dueAt?.toUtc();
  if (due != null && due.isBefore(now)) {
    return const Tooltip(message: 'Überfällig', child: Icon(Icons.error_outline));
  }
  if (task.status == TaskStatus.blocked) {
    return const Tooltip(message: 'Blockiert', child: Icon(Icons.block_outlined));
  }
  if (due != null && !due.isAfter(now.add(const Duration(days: 7)))) {
    return const Tooltip(
      message: 'In den nächsten 7 Tagen fällig',
      child: Icon(Icons.schedule_outlined),
    );
  }
  return const SizedBox.shrink();
}

String taskStatusLabel(TaskStatus status) => switch (status) {
  TaskStatus.open => 'Offen',
  TaskStatus.inProgress => 'In Bearbeitung',
  TaskStatus.blocked => 'Blockiert',
  TaskStatus.done => 'Erledigt',
  TaskStatus.archived => 'Archiviert',
};

String taskPriorityLabel(TaskPriority priority) => switch (priority) {
  TaskPriority.low => 'Niedrig',
  TaskPriority.normal => 'Normal',
  TaskPriority.high => 'Hoch',
};

String entityTypeLabel(PlatformEntityType type) => switch (type) {
  PlatformEntityType.workspace => 'Arbeitsbereich',
  PlatformEntityType.property => 'Objekt',
  PlatformEntityType.portfolio => 'Portfolio',
  PlatformEntityType.unit => 'Einheit',
  PlatformEntityType.lease => 'Mietvertrag',
  PlatformEntityType.party => 'Partei',
  PlatformEntityType.maintenanceTicket => 'Instandhaltung',
  PlatformEntityType.capexProject => 'CapEx-Projekt',
  PlatformEntityType.scenario => 'Szenario',
};

NxBadgeKind _statusKind(TaskStatus status) => switch (status) {
  TaskStatus.open => NxBadgeKind.neutral,
  TaskStatus.inProgress => NxBadgeKind.info,
  TaskStatus.blocked => NxBadgeKind.warning,
  TaskStatus.done => NxBadgeKind.success,
  TaskStatus.archived => NxBadgeKind.neutral,
};

String _assignmentLabel(TaskDto task, String? actorId) {
  if (task.assignedTo == null) return 'Nicht zugewiesen';
  if (task.assignedTo == actorId) return 'Mir zugewiesen';
  final value = task.assignedTo!;
  return 'Mitglied ${value.length > 8 ? value.substring(0, 8) : value}';
}

String _contextLabel(TaskDto task, List<PropertySummaryDto> properties) {
  final entity = task.entity;
  if (entity == null) return 'Kein Kontext';
  if (entity.type == PlatformEntityType.property) {
    for (final property in properties) {
      if (property.id == entity.id) return property.name;
    }
  }
  final id = entity.id.length > 8 ? entity.id.substring(0, 8) : entity.id;
  return '${entityTypeLabel(entity.type)} · $id';
}

String _dueLabel(TaskDto task) {
  final due = task.dueAt;
  if (due == null) return 'Keine Fälligkeit';
  final now = DateTime.now().toUtc();
  final prefix = _isActive(task) && due.toUtc().isBefore(now) ? 'Überfällig · ' : '';
  return '$prefix${_formatDate(due)}';
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day.$month.${local.year}';
}

String? _nullableTrim(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

TaskFieldEdit<String> _textEdit(String? current, String? next) {
  if (current == next) return const TaskFieldEdit<String>.absent();
  return next == null
      ? const TaskFieldEdit<String>.clear()
      : TaskFieldEdit<String>.set(next);
}

TaskFieldEdit<DateTime> _dateEdit(DateTime? current, DateTime? next) {
  if (_sameDateTime(current, next)) return const TaskFieldEdit<DateTime>.absent();
  return next == null
      ? const TaskFieldEdit<DateTime>.clear()
      : TaskFieldEdit<DateTime>.set(next);
}

bool _sameDateTime(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == b;
  return a.toUtc().isAtSameMomentAs(b.toUtc());
}
