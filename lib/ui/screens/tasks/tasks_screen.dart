import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/task.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../state/app_state.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<TaskWorkflowRecord> _tasks = const [];
  String _statusFilter = 'todo';
  String _entityTypeFilter = 'all';
  String _priorityFilter = 'all';
  String _dueFilter = 'all';
  TaskWorkflowRecord? _selectedTask;
  List<TaskChecklistItemRecord> _checklist = const [];
  String? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestedDueFilter = ref.watch(tasksRequestedDueFilterProvider);
    if (requestedDueFilter != null && requestedDueFilter != _dueFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _dueFilter = requestedDueFilter;
          _statusFilter = 'all';
        });
        ref.read(tasksRequestedDueFilterProvider.notifier).state = null;
        _reload();
      });
    }
    final filteredTasks = _filteredTasks();
    final criticalTasks = filteredTasks
        .where((task) => _isOverdue(task.task) || _isCritical(task.task))
        .toList(growable: false);
    final queueTasks = filteredTasks
        .where((task) => !_isOverdue(task.task) && !_isCritical(task.task))
        .toList(growable: false);

    return ListFilterTemplate(
      title: 'Tasks',
      breadcrumbs: const ['Operations', 'Tasks'],
      subtitle:
          'Run the work queue with visible context, urgency and direct navigation into the related workflow.',
      primaryAction: ElevatedButton.icon(
        onPressed: _createTaskDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
      secondaryActions: [
        OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
      ],
      contextBar: ListFilterBar(
        children: [
          NxStatusBadge(
            label: '${criticalTasks.length} critical / overdue',
            kind:
                criticalTasks.isEmpty ? NxBadgeKind.neutral : NxBadgeKind.error,
          ),
          NxStatusBadge(
            label: '${queueTasks.length} in queue',
            kind: NxBadgeKind.info,
          ),
          if (_status != null)
            Text(_status!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      filters: ListFilterBar(
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search tasks',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          _filterField(
            width: 160,
            value: _statusFilter,
            label: 'Status',
            items: const [
              DropdownMenuItem(value: 'todo', child: Text('To do')),
              DropdownMenuItem(
                value: 'in_progress',
                child: Text('In progress'),
              ),
              DropdownMenuItem(value: 'done', child: Text('Done')),
              DropdownMenuItem(value: 'all', child: Text('All')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _statusFilter = value);
              _reload();
            },
          ),
          _filterField(
            width: 180,
            value: _priorityFilter,
            label: 'Priority',
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All priorities')),
              DropdownMenuItem(value: 'low', child: Text('Low')),
              DropdownMenuItem(value: 'normal', child: Text('Normal')),
              DropdownMenuItem(value: 'high', child: Text('High')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _priorityFilter = value);
            },
          ),
          _filterField(
            width: 180,
            value: _dueFilter,
            label: 'Due',
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All due dates')),
              DropdownMenuItem(value: 'overdue', child: Text('Overdue')),
              DropdownMenuItem(value: 'today', child: Text('Today')),
              DropdownMenuItem(
                value: 'next_7_days',
                child: Text('Next 7 days'),
              ),
              DropdownMenuItem(
                value: 'no_due_date',
                child: Text('No due date'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _dueFilter = value);
            },
          ),
          _filterField(
            width: 190,
            value: _entityTypeFilter,
            label: 'Context',
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All contexts')),
              DropdownMenuItem(value: 'property', child: Text('Property')),
              DropdownMenuItem(value: 'asset_property', child: Text('Asset')),
              DropdownMenuItem(value: 'unit', child: Text('Unit')),
              DropdownMenuItem(value: 'tenant', child: Text('Tenant')),
              DropdownMenuItem(value: 'lease', child: Text('Lease')),
              DropdownMenuItem(value: 'document', child: Text('Document')),
              DropdownMenuItem(
                value: 'maintenance_ticket',
                child: Text('Maintenance'),
              ),
              DropdownMenuItem(value: 'portfolio', child: Text('Portfolio')),
              DropdownMenuItem(value: 'none', child: Text('No context')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _entityTypeFilter = value);
              _reload();
            },
          ),
        ],
      ),
      content:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : filteredTasks.isEmpty
              ? const NxEmptyState(
                title: 'No tasks found',
                description:
                    'Create a task or widen the filters to inspect more work items.',
                icon: Icons.checklist_outlined,
              )
              : LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 1080;
                  if (stacked) {
                    return Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildTaskList(
                            criticalTasks: criticalTasks,
                            queueTasks: queueTasks,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.component),
                        Expanded(flex: 2, child: _buildTaskDetail()),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: _buildTaskList(
                          criticalTasks: criticalTasks,
                          queueTasks: queueTasks,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.component),
                      Expanded(child: _buildTaskDetail()),
                    ],
                  );
                },
              ),
    );
  }

  Widget _buildTaskList({
    required List<TaskWorkflowRecord> criticalTasks,
    required List<TaskWorkflowRecord> queueTasks,
  }) {
    return NxCard(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        children: [
          if (criticalTasks.isNotEmpty) ...[
            Text(
              'Critical / Overdue',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...criticalTasks.map(_buildTaskTile),
            const SizedBox(height: AppSpacing.section),
          ],
          Text('Queue', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (queueTasks.isEmpty)
            Text(
              'All remaining tasks are either completed or currently filtered out.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ...queueTasks.map(_buildTaskTile),
        ],
      ),
    );
  }

  Widget _buildTaskTile(TaskWorkflowRecord workflow) {
    final task = workflow.task;
    final selected = _selectedTask?.task.id == task.id;
    final overdue = _isOverdue(task);
    final critical = _isCritical(task);
    final badgeKind =
        overdue
            ? NxBadgeKind.error
            : critical
            ? NxBadgeKind.warning
            : task.status == 'done'
            ? NxBadgeKind.success
            : NxBadgeKind.info;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color:
            selected
                ? context.semanticColors.surfaceAlt
                : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          onTap: () => _selectTask(workflow),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(task.title),
                          const SizedBox(height: 4),
                          Text(
                            '${workflow.contextTitle} · ${workflow.contextSubtitle}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    NxStatusBadge(
                      label:
                          overdue ? 'Overdue' : _priorityLabel(task.priority),
                      kind: badgeKind,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${_statusLabel(task.status)}${task.dueAt == null ? ' · No due date' : ' · Due ${_formatDate(task.dueAt)}'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed:
                          task.status == 'todo'
                              ? () => _updateTaskStatus(task.id, 'in_progress')
                              : null,
                      child: const Text('Start'),
                    ),
                    TextButton(
                      onPressed:
                          task.status == 'done'
                              ? null
                              : () => _updateTaskStatus(task.id, 'done'),
                      child: const Text('Mark Done'),
                    ),
                    TextButton(
                      onPressed:
                          workflow.propertyId == null
                              ? null
                              : () => _openContext(workflow),
                      child: const Text('Open Context'),
                    ),
                    TextButton(
                      onPressed: () => _editTaskDialog(task),
                      child: const Text('Edit'),
                    ),
                    TextButton(
                      onPressed: () => _deleteTask(task.id),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskDetail() {
    final selected = _selectedTask;
    return NxCard(
      child:
          selected == null
              ? const Center(child: Text('Select a task'))
              : ListView(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selected.task.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${selected.contextTitle} · ${selected.contextSubtitle}',
                            ),
                            if (selected.propertyName != null) ...[
                              const SizedBox(height: 4),
                              Text('Asset: ${selected.propertyName}'),
                            ],
                          ],
                        ),
                      ),
                      NxStatusBadge(
                        label: _statusLabel(selected.task.status),
                        kind:
                            selected.task.status == 'done'
                                ? NxBadgeKind.success
                                : _isOverdue(selected.task)
                                ? NxBadgeKind.error
                                : NxBadgeKind.info,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      NxStatusBadge(
                        label: _priorityLabel(selected.task.priority),
                        kind:
                            _isCritical(selected.task)
                                ? NxBadgeKind.warning
                                : NxBadgeKind.neutral,
                      ),
                      NxStatusBadge(
                        label:
                            selected.task.dueAt == null
                                ? 'No due date'
                                : 'Due ${_formatDate(selected.task.dueAt)}',
                        kind:
                            _isOverdue(selected.task)
                                ? NxBadgeKind.error
                                : NxBadgeKind.info,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed:
                            selected.propertyId == null
                                ? null
                                : () => _openContext(selected),
                        child: const Text('Open Context'),
                      ),
                      OutlinedButton(
                        onPressed: () => _addChecklistDialog(selected.task.id),
                        child: const Text('Add Checklist Item'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Checklist',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_checklist.isEmpty)
                    const Text('No checklist items.')
                  else
                    ..._checklist.map(
                      (item) => CheckboxListTile(
                        value: item.done,
                        onChanged: (value) async {
                          await ref
                              .read(tasksRepositoryProvider)
                              .toggleChecklistItem(
                                id: item.id,
                                done: value ?? false,
                              );
                          final current = _selectedTask;
                          if (current != null) {
                            await _selectTask(current);
                          }
                        },
                        title: Text(item.text),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
    );
  }

  Widget _filterField({
    required double width,
    required String value,
    required String label,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        items: items,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  List<TaskWorkflowRecord> _filteredTasks() {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    final next7Days = endOfToday.add(const Duration(days: 6));

    return _tasks
        .where((workflow) {
          final task = workflow.task;
          final matchesPriority =
              _priorityFilter == 'all' || task.priority == _priorityFilter;
          final dueAt =
              task.dueAt == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(task.dueAt!);
          final matchesDue = switch (_dueFilter) {
            'overdue' => _isOverdue(task),
            'today' =>
              dueAt != null &&
                  !dueAt.isBefore(startOfToday) &&
                  dueAt.isBefore(endOfToday),
            'next_7_days' =>
              dueAt != null &&
                  !dueAt.isBefore(startOfToday) &&
                  dueAt.isBefore(next7Days),
            'no_due_date' => task.dueAt == null,
            _ => true,
          };
          final matchesQuery =
              query.isEmpty ||
              task.title.toLowerCase().contains(query) ||
              workflow.contextSubtitle.toLowerCase().contains(query) ||
              workflow.contextTitle.toLowerCase().contains(query) ||
              (workflow.propertyName?.toLowerCase().contains(query) ?? false);
          return matchesPriority && matchesDue && matchesQuery;
        })
        .toList(growable: false);
  }

  bool _isOverdue(TaskRecord task) {
    if (task.dueAt == null || task.status == 'done') {
      return false;
    }
    return task.dueAt! < DateTime.now().millisecondsSinceEpoch;
  }

  bool _isCritical(TaskRecord task) {
    return task.priority == 'high' && task.status != 'done';
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
    });
    final tasks = await ref
        .read(tasksRepositoryProvider)
        .listWorkflowTasks(
          status: _statusFilter == 'all' ? null : _statusFilter,
          entityType: _entityTypeFilter == 'all' ? null : _entityTypeFilter,
        );
    if (!mounted) return;
    TaskWorkflowRecord? selectedTask;
    if (_selectedTask != null) {
      for (final task in tasks) {
        if (task.task.id == _selectedTask!.task.id) {
          selectedTask = task;
          break;
        }
      }
    }
    setState(() {
      _tasks = tasks;
      _loading = false;
      _selectedTask = selectedTask;
    });
    if (selectedTask != null) {
      await _selectTask(selectedTask);
    }
  }

  Future<void> _selectTask(TaskWorkflowRecord workflow) async {
    final checklist = await ref
        .read(tasksRepositoryProvider)
        .listChecklistItems(workflow.task.id);
    if (!mounted) return;
    setState(() {
      _selectedTask = workflow;
      _checklist = checklist;
    });
  }

  Future<void> _updateTaskStatus(String id, String status) async {
    await ref
        .read(tasksRepositoryProvider)
        .updateTaskStatus(id: id, status: status);
    await _reload();
  }

  Future<void> _createTaskDialog() async {
    await _taskDialog();
  }

  Future<void> _editTaskDialog(TaskRecord task) async {
    await _taskDialog(existing: task);
  }

  Future<void> _taskDialog({TaskRecord? existing}) async {
    final isEdit = existing != null;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final dueAtController = TextEditingController(
      text: existing?.dueAt?.toString() ?? '',
    );
    var status = existing?.status ?? 'todo';
    var priority = existing?.priority ?? 'normal';
    var entityType = existing?.entityType ?? 'none';
    final entityIdController = TextEditingController(
      text: existing?.entityId ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit Task' : 'Create Task'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: status,
                        items: const [
                          DropdownMenuItem(value: 'todo', child: Text('To do')),
                          DropdownMenuItem(
                            value: 'in_progress',
                            child: Text('In progress'),
                          ),
                          DropdownMenuItem(value: 'done', child: Text('Done')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => status = value);
                        },
                        decoration: const InputDecoration(labelText: 'Status'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: priority,
                        items: const [
                          DropdownMenuItem(value: 'low', child: Text('Low')),
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text('Normal'),
                          ),
                          DropdownMenuItem(value: 'high', child: Text('High')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => priority = value);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: entityType,
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('None')),
                          DropdownMenuItem(
                            value: 'property',
                            child: Text('Property'),
                          ),
                          DropdownMenuItem(
                            value: 'asset_property',
                            child: Text('Asset'),
                          ),
                          DropdownMenuItem(value: 'unit', child: Text('Unit')),
                          DropdownMenuItem(
                            value: 'tenant',
                            child: Text('Tenant'),
                          ),
                          DropdownMenuItem(
                            value: 'lease',
                            child: Text('Lease'),
                          ),
                          DropdownMenuItem(
                            value: 'document',
                            child: Text('Document'),
                          ),
                          DropdownMenuItem(
                            value: 'maintenance_ticket',
                            child: Text('Maintenance'),
                          ),
                          DropdownMenuItem(
                            value: 'portfolio',
                            child: Text('Portfolio'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => entityType = value);
                        },
                        decoration: const InputDecoration(labelText: 'Context'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: entityIdController,
                        decoration: const InputDecoration(
                          labelText: 'Context ID',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: dueAtController,
                        decoration: const InputDecoration(
                          labelText: 'Due at (epoch ms, optional)',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;
                    final dueAt =
                        dueAtController.text.trim().isEmpty
                            ? null
                            : int.tryParse(dueAtController.text.trim());

                    final repo = ref.read(tasksRepositoryProvider);
                    if (isEdit) {
                      await repo.updateTask(
                        TaskRecord(
                          id: existing.id,
                          entityType: entityType,
                          entityId:
                              entityIdController.text.trim().isEmpty
                                  ? null
                                  : entityIdController.text.trim(),
                          title: title,
                          status: status,
                          priority: priority,
                          dueAt: dueAt,
                          createdAt: existing.createdAt,
                          updatedAt: DateTime.now().millisecondsSinceEpoch,
                          createdBy: existing.createdBy,
                        ),
                      );
                    } else {
                      await repo.createTask(
                        entityType: entityType,
                        entityId:
                            entityIdController.text.trim().isEmpty
                                ? null
                                : entityIdController.text.trim(),
                        title: title,
                        status: status,
                        priority: priority,
                        dueAt: dueAt,
                      );
                    }
                    if (context.mounted) Navigator.of(context).pop();
                    await _reload();
                  },
                  child: Text(isEdit ? 'Save' : 'Create'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    dueAtController.dispose();
    entityIdController.dispose();
  }

  Future<void> _deleteTask(String id) async {
    await ref.read(tasksRepositoryProvider).deleteTask(id);
    await _reload();
  }

  Future<void> _addChecklistDialog(String taskId) async {
    final textController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Checklist Item'),
            content: TextField(
              controller: textController,
              decoration: const InputDecoration(labelText: 'Text'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final text = textController.text.trim();
                  if (text.isEmpty) {
                    return;
                  }
                  await ref
                      .read(tasksRepositoryProvider)
                      .addChecklistItem(
                        taskId: taskId,
                        text: text,
                        position: _checklist.length,
                      );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  final selected = _selectedTask;
                  if (selected != null) {
                    await _selectTask(selected);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
    textController.dispose();
  }

  void _openContext(TaskWorkflowRecord workflow) {
    final propertyId = workflow.propertyId;
    if (propertyId == null) {
      return;
    }
    ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
    ref.read(selectedPropertyIdProvider.notifier).state = propertyId;

    final task = workflow.task;
    switch (task.entityType) {
      case 'unit':
        ref.read(selectedOperationsUnitIdProvider.notifier).state =
            task.entityId;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.units;
        break;
      case 'tenant':
        ref.read(selectedOperationsTenantIdProvider.notifier).state =
            task.entityId;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.tenants;
        break;
      case 'lease':
        ref.read(selectedOperationsLeaseIdProvider.notifier).state =
            task.entityId;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.leases;
        break;
      case 'document':
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.documents;
        break;
      case 'maintenance_ticket':
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.maintenance;
        break;
      case 'property':
      case 'asset_property':
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.tasks;
        break;
      default:
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.overview;
        break;
    }
  }

  String _priorityLabel(String value) {
    switch (value) {
      case 'low':
        return 'Low';
      case 'high':
        return 'High';
      default:
        return 'Normal';
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'todo':
        return 'To do';
      case 'in_progress':
        return 'In progress';
      case 'done':
        return 'Done';
      default:
        return value;
    }
  }

  String _formatDate(int? value) {
    if (value == null) {
      return '-';
    }
    return DateTime.fromMillisecondsSinceEpoch(
      value,
    ).toIso8601String().substring(0, 10);
  }
}
