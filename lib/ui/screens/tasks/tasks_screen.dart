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
  String _categoryFilter = 'all';
  String _assigneeFilter = 'all';
  String _viewMode = 'list';
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
    final dashboardTasks = _filteredTasks(ignoreStatus: true);
    final categoryOptions = _categoryOptions;
    final assigneeOptions = _assigneeOptions;
    final criticalTasks = filteredTasks
        .where((task) => _isOverdue(task.task) || _isCritical(task.task))
        .toList(growable: false);
    final queueTasks = filteredTasks
        .where((task) => !_isOverdue(task.task) && !_isCritical(task.task))
        .toList(growable: false);

    return ListFilterTemplate(
      title: 'Tasks',
      breadcrumbs: const ['Daily Business', 'Tasks'],
      subtitle:
          'Run the work queue with visible context, urgency and direct navigation into the related workflow.',
      primaryAction: ElevatedButton.icon(
        onPressed: _createTaskDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
      secondaryActions: [
        OutlinedButton.icon(
          onPressed:
              () => ref.read(globalPageProvider.notifier).state =
                  GlobalPage.taskTemplates,
          icon: const Icon(Icons.rule_folder_outlined),
          label: const Text('Templates'),
        ),
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
            width: 170,
            value: _categoryFilter,
            label: 'Category',
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All categories')),
              for (final category in categoryOptions)
                DropdownMenuItem(value: category, child: Text(category)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _categoryFilter = value);
            },
          ),
          _filterField(
            width: 190,
            value: _assigneeFilter,
            label: 'Assigned',
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All assignees')),
              const DropdownMenuItem(value: 'unassigned', child: Text('Unassigned')),
              for (final assignee in assigneeOptions)
                DropdownMenuItem(value: assignee, child: Text(assignee)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _assigneeFilter = value);
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
          _filterField(
            width: 150,
            value: _viewMode,
            label: 'View',
            items: const [
              DropdownMenuItem(value: 'list', child: Text('List')),
              DropdownMenuItem(value: 'board', child: Text('Board')),
              DropdownMenuItem(value: 'calendar', child: Text('Due plan')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _viewMode = value);
            },
          ),
          TextButton.icon(
            onPressed: _resetFilters,
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('Reset'),
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
                  if (_viewMode == 'board') {
                    return Column(
                      children: [
                        _TasksDashboard(
                          tasks: dashboardTasks,
                          onStatusFilter: (status) {
                            setState(() {
                              _statusFilter = status;
                              _viewMode = 'list';
                            });
                            _reload();
                          },
                          onDueFilter: (filter) {
                            setState(() {
                              _dueFilter = filter;
                              _statusFilter = 'all';
                              _viewMode = 'list';
                            });
                            _reload();
                          },
                        ),
                        const SizedBox(height: AppSpacing.component),
                        Expanded(child: _buildTaskBoard(dashboardTasks)),
                      ],
                    );
                  }
                  if (_viewMode == 'calendar') {
                    return Column(
                      children: [
                        _TasksDashboard(
                          tasks: dashboardTasks,
                          onStatusFilter: (status) {
                            setState(() {
                              _statusFilter = status;
                              _viewMode = 'list';
                            });
                            _reload();
                          },
                          onDueFilter: (filter) {
                            setState(() {
                              _dueFilter = filter;
                              _statusFilter = 'all';
                              _viewMode = 'list';
                            });
                            _reload();
                          },
                        ),
                        const SizedBox(height: AppSpacing.component),
                        Expanded(child: _buildDuePlan(dashboardTasks)),
                      ],
                    );
                  }
                  final stacked = constraints.maxWidth < 1080;
                  if (stacked) {
                    return Column(
                      children: [
                        _TasksDashboard(
                          tasks: dashboardTasks,
                          onStatusFilter: (status) {
                            setState(() => _statusFilter = status);
                            _reload();
                          },
                          onDueFilter: (filter) {
                            setState(() {
                              _dueFilter = filter;
                              _statusFilter = 'all';
                            });
                            _reload();
                          },
                        ),
                        const SizedBox(height: AppSpacing.component),
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
                        child: Column(
                          children: [
                            _TasksDashboard(
                              tasks: dashboardTasks,
                              onStatusFilter: (status) {
                                setState(() => _statusFilter = status);
                                _reload();
                              },
                              onDueFilter: (filter) {
                                setState(() {
                                  _dueFilter = filter;
                                  _statusFilter = 'all';
                                });
                                _reload();
                              },
                            ),
                            const SizedBox(height: AppSpacing.component),
                            Expanded(
                              child: _buildTaskList(
                                criticalTasks: criticalTasks,
                                queueTasks: queueTasks,
                              ),
                            ),
                          ],
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

  Widget _buildTaskBoard(List<TaskWorkflowRecord> tasks) {
    const columns = <String>['todo', 'in_progress', 'done'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in columns)
            _TaskBoardColumn(
              title: _statusLabel(status),
              tasks: tasks
                  .where((workflow) => workflow.task.status == status)
                  .toList(growable: false),
              selectedId: _selectedTask?.task.id,
              onOpen: (workflow) {
                _selectTask(workflow);
                setState(() => _viewMode = 'list');
              },
              onEdit: (workflow) => _editTaskDialog(workflow.task),
              onAdvance: (workflow) {
                if (workflow.task.status == 'done') {
                  return;
                }
                final nextStatus =
                    workflow.task.status == 'todo'
                        ? 'in_progress'
                        : 'done';
                _updateTaskStatus(workflow.task.id, nextStatus);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDuePlan(List<TaskWorkflowRecord> tasks) {
    final buckets = const <_TaskDueBucket>[
      _TaskDueBucket('Überfällig', 'overdue'),
      _TaskDueBucket('Heute', 'today'),
      _TaskDueBucket('Nächste 7 Tage', 'next_7_days'),
      _TaskDueBucket('Ohne Termin', 'no_due_date'),
      _TaskDueBucket('Später', 'later'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 760 ? constraints.maxWidth : 260.0;
        return SingleChildScrollView(
          child: Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              for (final bucket in buckets)
                _TaskDuePanel(
                  width: width,
                  title: bucket.label,
                  tasks: tasks
                      .where((workflow) => _matchesTaskDueBucket(workflow.task, bucket.key))
                      .toList(growable: false),
                  onOpen: (workflow) {
                    _selectTask(workflow);
                    setState(() => _viewMode = 'list');
                  },
                  onEdit: (workflow) => _editTaskDialog(workflow.task),
                  onAdvance: (workflow) {
                    if (workflow.task.status == 'done') {
                      return;
                    }
                    final nextStatus =
                        workflow.task.status == 'todo'
                            ? 'in_progress'
                            : 'done';
                    _updateTaskStatus(workflow.task.id, nextStatus);
                  },
                ),
            ],
          ),
        );
      },
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
                          if (task.category != null ||
                              task.assignedTo != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (task.category != null) task.category!,
                                if (task.assignedTo != null)
                                  'Assigned to ${task.assignedTo}',
                              ].join(' · '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
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
                            if (selected.task.description != null &&
                                selected.task.description!.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(selected.task.description!),
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
                      if (selected.task.category != null)
                        NxStatusBadge(
                          label: selected.task.category!,
                          kind: NxBadgeKind.neutral,
                        ),
                      if (selected.task.assignedTo != null)
                        NxStatusBadge(
                          label: 'Assigned: ${selected.task.assignedTo}',
                          kind: NxBadgeKind.info,
                        ),
                      if (selected.task.estimatedCost != null)
                        NxStatusBadge(
                          label:
                              'Est. cost ${selected.task.estimatedCost!.toStringAsFixed(2)}',
                          kind: NxBadgeKind.neutral,
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

  List<TaskWorkflowRecord> _filteredTasks({bool ignoreStatus = false}) {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    final next7Days = endOfToday.add(const Duration(days: 6));

    return _tasks
        .where((workflow) {
          final task = workflow.task;
          final matchesStatus =
              ignoreStatus || _statusFilter == 'all' || task.status == _statusFilter;
          final matchesPriority =
              _priorityFilter == 'all' || task.priority == _priorityFilter;
          final matchesCategory =
              _categoryFilter == 'all' || task.category == _categoryFilter;
          final assignee = task.assignedTo?.trim();
          final matchesAssignee =
              _assigneeFilter == 'all' ||
              (_assigneeFilter == 'unassigned' &&
                  (assignee == null || assignee.isEmpty)) ||
              assignee == _assigneeFilter;
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
          return matchesStatus &&
              matchesPriority &&
              matchesCategory &&
              matchesAssignee &&
              matchesDue &&
              matchesQuery;
        })
        .toList(growable: false);
  }

  List<String> get _categoryOptions {
    final values = _tasks
        .map((workflow) => workflow.task.category?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<String> get _assigneeOptions {
    final values = _tasks
        .map((workflow) => workflow.task.assignedTo?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _statusFilter = 'todo';
      _entityTypeFilter = 'all';
      _priorityFilter = 'all';
      _dueFilter = 'all';
      _categoryFilter = 'all';
      _assigneeFilter = 'all';
      _viewMode = 'list';
      _selectedTask = null;
      _checklist = const [];
    });
    _reload();
  }

  bool _matchesTaskDueBucket(TaskRecord task, String bucket) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    final next7Days = endOfToday.add(const Duration(days: 6));
    final dueAt =
        task.dueAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(task.dueAt!);
    switch (bucket) {
      case 'overdue':
        return _isOverdue(task);
      case 'today':
        return dueAt != null &&
            !dueAt.isBefore(startOfToday) &&
            dueAt.isBefore(endOfToday);
      case 'next_7_days':
        return dueAt != null &&
            !dueAt.isBefore(startOfToday) &&
            dueAt.isBefore(next7Days);
      case 'no_due_date':
        return task.dueAt == null;
      case 'later':
        return dueAt != null && !dueAt.isBefore(next7Days);
      default:
        return false;
    }
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
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    final assignedToController = TextEditingController(
      text: existing?.assignedTo ?? '',
    );
    final estimatedCostController = TextEditingController(
      text: existing?.estimatedCost?.toString() ?? '',
    );
    final existingDueAt = existing?.dueAt;
    final dueDateController = TextEditingController(
      text: existingDueAt == null ? '' : _formatDate(existingDueAt),
    );
    var status = existing?.status ?? 'todo';
    var priority = existing?.priority ?? 'normal';
    var category = existing?.category ?? 'general';
    var dueDate =
        existingDueAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(existingDueAt);
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
                      TextField(
                        controller: descriptionController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: category,
                        items: const [
                          DropdownMenuItem(
                            value: 'general',
                            child: Text('General'),
                          ),
                          DropdownMenuItem(
                            value: 'leasing',
                            child: Text('Leasing'),
                          ),
                          DropdownMenuItem(
                            value: 'maintenance',
                            child: Text('Maintenance'),
                          ),
                          DropdownMenuItem(
                            value: 'finance',
                            child: Text('Finance'),
                          ),
                          DropdownMenuItem(
                            value: 'documents',
                            child: Text('Documents'),
                          ),
                          DropdownMenuItem(
                            value: 'compliance',
                            child: Text('Compliance'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => category = value);
                        },
                        decoration: const InputDecoration(labelText: 'Category'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: assignedToController,
                        decoration: const InputDecoration(
                          labelText: 'Assigned to',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: estimatedCostController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Estimated cost',
                        ),
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
                        readOnly: true,
                        controller: dueDateController,
                        decoration: InputDecoration(
                          labelText: 'Due date',
                          suffixIcon: IconButton(
                            tooltip: 'Select date',
                            icon: const Icon(Icons.calendar_today_outlined),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: dueDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  dueDate = picked;
                                  dueDateController.text = _formatDate(
                                    picked.millisecondsSinceEpoch,
                                  );
                                });
                              }
                            },
                          ),
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
                    final dueAt = dueDate?.millisecondsSinceEpoch;
                    final estimatedCost =
                        estimatedCostController.text.trim().isEmpty
                            ? null
                            : double.tryParse(
                              estimatedCostController.text.trim(),
                            );

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
                          description:
                              descriptionController.text.trim().isEmpty
                                  ? null
                                  : descriptionController.text.trim(),
                          category: category,
                          assignedTo:
                              assignedToController.text.trim().isEmpty
                                  ? null
                                  : assignedToController.text.trim(),
                          estimatedCost: estimatedCost,
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
                        description:
                            descriptionController.text.trim().isEmpty
                                ? null
                                : descriptionController.text.trim(),
                        category: category,
                        assignedTo:
                            assignedToController.text.trim().isEmpty
                                ? null
                                : assignedToController.text.trim(),
                        estimatedCost: estimatedCost,
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
    descriptionController.dispose();
    assignedToController.dispose();
    estimatedCostController.dispose();
    dueDateController.dispose();
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

class _TasksDashboard extends StatelessWidget {
  const _TasksDashboard({
    required this.tasks,
    required this.onStatusFilter,
    required this.onDueFilter,
  });

  final List<TaskWorkflowRecord> tasks;
  final ValueChanged<String> onStatusFilter;
  final ValueChanged<String> onDueFilter;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    final next7Days = endOfToday.add(const Duration(days: 6));
    final overdue = tasks.where((item) {
      final dueAt = item.task.dueAt;
      return dueAt != null &&
          dueAt < DateTime.now().millisecondsSinceEpoch &&
          item.task.status != 'done';
    }).length;
    final today = tasks.where((item) {
      final dueAt = item.task.dueAt;
      if (dueAt == null) return false;
      final date = DateTime.fromMillisecondsSinceEpoch(dueAt);
      return !date.isBefore(startOfToday) && date.isBefore(endOfToday);
    }).length;
    final next = tasks.where((item) {
      final dueAt = item.task.dueAt;
      if (dueAt == null) return false;
      final date = DateTime.fromMillisecondsSinceEpoch(dueAt);
      return !date.isBefore(endOfToday) && date.isBefore(next7Days);
    }).length;
    final inProgress =
        tasks.where((item) => item.task.status == 'in_progress').length;
    final done = tasks.where((item) => item.task.status == 'done').length;
    final cost = tasks.fold<double>(
      0,
      (sum, item) => sum + (item.task.estimatedCost ?? 0),
    );
    final byStatus = <String, int>{};
    for (final item in tasks) {
      byStatus[item.task.status] = (byStatus[item.task.status] ?? 0) + 1;
    }
    final tileWidth = 170.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaskSignalTile(
            width: tileWidth,
            label: 'Überfällig',
            value: overdue.toString(),
            icon: Icons.warning_amber_outlined,
            tone: overdue == 0
                ? context.semanticColors.success
                : Theme.of(context).colorScheme.error,
            onTap: () => onDueFilter('overdue'),
          ),
          const SizedBox(width: AppSpacing.component),
          _TaskSignalTile(
            width: tileWidth,
            label: 'Heute',
            value: today.toString(),
            icon: Icons.today_outlined,
            onTap: () => onDueFilter('today'),
          ),
          const SizedBox(width: AppSpacing.component),
          _TaskSignalTile(
            width: tileWidth,
            label: 'Nächste 7 Tage',
            value: next.toString(),
            icon: Icons.event_available_outlined,
            onTap: () => onDueFilter('next_7_days'),
          ),
          const SizedBox(width: AppSpacing.component),
          _TaskSignalTile(
            width: tileWidth,
            label: 'In Arbeit',
            value: inProgress.toString(),
            icon: Icons.timelapse_outlined,
            onTap: () => onStatusFilter('in_progress'),
          ),
          const SizedBox(width: AppSpacing.component),
          _TaskSignalTile(
            width: tileWidth,
            label: 'Erledigt',
            value: done.toString(),
            icon: Icons.done_all_outlined,
            onTap: () => onStatusFilter('done'),
          ),
          const SizedBox(width: AppSpacing.component),
          _TaskSignalTile(
            width: 210,
            label: 'Kostenrahmen',
            value: _taskCurrency(cost),
            icon: Icons.payments_outlined,
          ),
          const SizedBox(width: AppSpacing.component),
          _TaskStatusBars(
            width: 320,
            values: byStatus,
            onStatusFilter: onStatusFilter,
          ),
        ],
      ),
    );
  }
}

class _TaskSignalTile extends StatelessWidget {
  const _TaskSignalTile({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
    this.onTap,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(AppSpacing.component),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: context.semanticColors.border),
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskStatusBars extends StatelessWidget {
  const _TaskStatusBars({
    required this.width,
    required this.values,
    required this.onStatusFilter,
  });

  final double width;
  final Map<String, int> values;
  final ValueChanged<String> onStatusFilter;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.values.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );
    final denominator = maxValue == 0 ? 1.0 : maxValue.toDouble();
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Statusverteilung', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Text('Keine Daten', style: Theme.of(context).textTheme.bodySmall)
          else
            for (final entry in entries) ...[
              InkWell(
                onTap: () => onStatusFilter(entry.key),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        entry.key.replaceAll('_', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: entry.value / denominator,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(entry.value.toString()),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _TaskBoardColumn extends StatelessWidget {
  const _TaskBoardColumn({
    required this.title,
    required this.tasks,
    required this.selectedId,
    required this.onOpen,
    required this.onEdit,
    required this.onAdvance,
  });

  final String title;
  final List<TaskWorkflowRecord> tasks;
  final String? selectedId;
  final ValueChanged<TaskWorkflowRecord> onOpen;
  final ValueChanged<TaskWorkflowRecord> onEdit;
  final ValueChanged<TaskWorkflowRecord> onAdvance;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.component),
            child: Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                NxStatusBadge(label: tasks.length.toString(), kind: NxBadgeKind.info),
              ],
            ),
          ),
          Divider(height: 1, color: context.semanticColors.border),
          Expanded(
            child:
                tasks.isEmpty
                    ? Center(
                      child: Text(
                        'Keine Aufgaben',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final workflow = tasks[index];
                        return _TaskMiniCard(
                          workflow: workflow,
                          selected: workflow.task.id == selectedId,
                          onOpen: () => onOpen(workflow),
                          onEdit: () => onEdit(workflow),
                          onAdvance: () => onAdvance(workflow),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _TaskDuePanel extends StatelessWidget {
  const _TaskDuePanel({
    required this.width,
    required this.title,
    required this.tasks,
    required this.onOpen,
    required this.onEdit,
    required this.onAdvance,
  });

  final double width;
  final String title;
  final List<TaskWorkflowRecord> tasks;
  final ValueChanged<TaskWorkflowRecord> onOpen;
  final ValueChanged<TaskWorkflowRecord> onEdit;
  final ValueChanged<TaskWorkflowRecord> onAdvance;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
              NxStatusBadge(label: tasks.length.toString(), kind: NxBadgeKind.info),
            ],
          ),
          const SizedBox(height: 10),
          if (tasks.isEmpty)
            Text('Keine Aufgaben', style: Theme.of(context).textTheme.bodySmall)
          else
            for (final workflow in tasks.take(5)) ...[
              _TaskMiniCard(
                workflow: workflow,
                selected: false,
                onOpen: () => onOpen(workflow),
                onEdit: () => onEdit(workflow),
                onAdvance: () => onAdvance(workflow),
              ),
            ],
        ],
      ),
    );
  }
}

class _TaskMiniCard extends StatelessWidget {
  const _TaskMiniCard({
    required this.workflow,
    required this.selected,
    required this.onOpen,
    required this.onEdit,
    required this.onAdvance,
  });

  final TaskWorkflowRecord workflow;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final task = workflow.task;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onOpen,
        onLongPress: onEdit,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color:
                selected
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
            border: Border.all(
              color:
                  selected
                      ? Theme.of(context).colorScheme.primary
                      : context.semanticColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bearbeiten',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${workflow.contextTitle} · ${task.priority}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.dueAt == null
                          ? 'Ohne Termin'
                          : _taskShortDate(task.dueAt!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Status weiter',
                    onPressed: onAdvance,
                    icon: const Icon(Icons.arrow_forward_outlined, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskDueBucket {
  const _TaskDueBucket(this.label, this.key);

  final String label;
  final String key;
}

String _taskShortDate(int value) {
  return DateTime.fromMillisecondsSinceEpoch(
    value,
  ).toIso8601String().substring(0, 10);
}

String _taskCurrency(double value) {
  final sign = value < 0 ? '-' : '';
  final absValue = value.abs();
  if (absValue >= 1000000) {
    return '$sign€ ${(absValue / 1000000).toStringAsFixed(1)} Mio.';
  }
  if (absValue >= 1000) {
    return '$sign€ ${(absValue / 1000).toStringAsFixed(1)} Tsd.';
  }
  return '$sign€ ${absValue.toStringAsFixed(0)}';
}
