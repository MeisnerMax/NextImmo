import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/task.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'operations_detail_support.dart';

class PropertyTasksScreen extends ConsumerStatefulWidget {
  const PropertyTasksScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<PropertyTasksScreen> createState() =>
      _PropertyTasksScreenState();
}

class _PropertyTasksScreenState extends ConsumerState<PropertyTasksScreen> {
  List<TaskRecord> _tasks = const <TaskRecord>[];
  List<TaskChecklistItemRecord> _checklist = const <TaskChecklistItemRecord>[];
  TaskRecord? _selectedTask;
  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  String _categoryFilter = 'all';
  String _assigneeFilter = 'all';
  String _dueFilter = 'all';
  String _viewMode = 'list';
  bool _loading = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final visibleTasks = _visibleTasks();
    final dashboardTasks = _visibleTasks(ignoreStatus: true);
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _createTaskDialog,
                icon: const Icon(Icons.add),
                label: const Text('New Task'),
              ),
              OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'todo', child: Text('To do')),
                    DropdownMenuItem(
                      value: 'in_progress',
                      child: Text('In progress'),
                    ),
                    DropdownMenuItem(value: 'done', child: Text('Done')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _statusFilter = value);
                  },
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  value: _priorityFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Priorität'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Alle')),
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _priorityFilter = value);
                  },
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  value: _categoryFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kategorie'),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('Alle')),
                    for (final category in _categoryOptions)
                      DropdownMenuItem(value: category, child: Text(category)),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _categoryFilter = value);
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _assigneeFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Bearbeiter'),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('Alle')),
                    const DropdownMenuItem(
                      value: 'unassigned',
                      child: Text('Nicht zugewiesen'),
                    ),
                    for (final assignee in _assigneeOptions)
                      DropdownMenuItem(value: assignee, child: Text(assignee)),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _assigneeFilter = value);
                  },
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  value: _dueFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Termin'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Alle')),
                    DropdownMenuItem(value: 'overdue', child: Text('Überfällig')),
                    DropdownMenuItem(value: 'today', child: Text('Heute')),
                    DropdownMenuItem(value: 'next_7_days', child: Text('7 Tage')),
                    DropdownMenuItem(value: 'later', child: Text('Später')),
                    DropdownMenuItem(value: 'no_due_date', child: Text('Ohne Termin')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _dueFilter = value);
                  },
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  value: _viewMode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Ansicht'),
                  items: const [
                    DropdownMenuItem(value: 'list', child: Text('Liste')),
                    DropdownMenuItem(value: 'board', child: Text('Board')),
                    DropdownMenuItem(value: 'calendar', child: Text('Termine')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _viewMode = value);
                  },
                ),
              ),
              TextButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Reset'),
              ),
              if (_status != null)
                Text(_status!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          _loading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 980;
                  if (_viewMode == 'board') {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PropertyTasksDashboard(
                          tasks: dashboardTasks,
                          onStatusFilter: (status) {
                            setState(() {
                              _statusFilter = status;
                              _viewMode = 'list';
                            });
                          },
                          onDueFilter: (filter) {
                            setState(() {
                              _statusFilter = 'all';
                              _dueFilter = filter;
                              _viewMode = 'list';
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.component),
                        _buildTaskBoard(dashboardTasks),
                      ],
                    );
                  }
                  if (_viewMode == 'calendar') {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PropertyTasksDashboard(
                          tasks: dashboardTasks,
                          onStatusFilter: (status) {
                            setState(() {
                              _statusFilter = status;
                              _viewMode = 'list';
                            });
                          },
                          onDueFilter: (filter) {
                            setState(() {
                              _statusFilter = 'all';
                              _dueFilter = filter;
                              _viewMode = 'list';
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.component),
                        _buildDuePlan(dashboardTasks),
                      ],
                    );
                  }
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PropertyTasksDashboard(
                          tasks: dashboardTasks,
                          onStatusFilter: (status) {
                            setState(() => _statusFilter = status);
                          },
                          onDueFilter: (filter) {
                            setState(() {
                              _statusFilter = 'all';
                              _dueFilter = filter;
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.component),
                        _buildTaskList(context, visibleTasks),
                        const SizedBox(height: AppSpacing.component),
                        _buildTaskDetail(context),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _PropertyTasksDashboard(
                              tasks: dashboardTasks,
                              onStatusFilter: (status) {
                                setState(() => _statusFilter = status);
                              },
                              onDueFilter: (filter) {
                                setState(() {
                                  _statusFilter = 'all';
                                  _dueFilter = filter;
                                });
                              },
                            ),
                            const SizedBox(height: AppSpacing.component),
                            _buildTaskList(context, visibleTasks),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.component),
                      Expanded(child: _buildTaskDetail(context)),
                    ],
                  );
                },
              ),
        ],
      ),
    );
  }

  List<TaskRecord> _visibleTasks({bool ignoreStatus = false}) {
    return _tasks.where((task) {
      if (!ignoreStatus &&
          _statusFilter != 'all' &&
          task.status != _statusFilter) {
        return false;
      }
      if (_priorityFilter != 'all' && task.priority != _priorityFilter) {
        return false;
      }
      if (_categoryFilter != 'all' && task.category != _categoryFilter) {
        return false;
      }
      final assignee = task.assignedTo?.trim();
      if (_assigneeFilter == 'unassigned') {
        if (assignee != null && assignee.isNotEmpty) {
          return false;
        }
      } else if (_assigneeFilter != 'all' && assignee != _assigneeFilter) {
        return false;
      }
      return _matchesDueFilter(task);
    }).toList(growable: false);
  }

  bool _matchesDueFilter(TaskRecord task) {
    return _matchesDueKey(task, _dueFilter);
  }

  bool _matchesDueKey(TaskRecord task, String dueKey) {
    if (dueKey == 'all') {
      return true;
    }
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    final next7Days = endOfToday.add(const Duration(days: 6));
    final dueAt =
        task.dueAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(task.dueAt!);
    switch (dueKey) {
      case 'overdue':
        return task.dueAt != null &&
            task.dueAt! < DateTime.now().millisecondsSinceEpoch &&
            task.status != 'done';
      case 'today':
        return dueAt != null &&
            !dueAt.isBefore(startOfToday) &&
            dueAt.isBefore(endOfToday);
      case 'next_7_days':
        return dueAt != null &&
            !dueAt.isBefore(startOfToday) &&
            dueAt.isBefore(next7Days);
      case 'later':
        return dueAt != null && !dueAt.isBefore(next7Days);
      case 'no_due_date':
        return task.dueAt == null;
      default:
        return true;
    }
  }

  List<String> get _categoryOptions {
    final values = _tasks
        .map((task) => task.category?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<String> get _assigneeOptions {
    final values = _tasks
        .map((task) => task.assignedTo?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  void _resetFilters() {
    setState(() {
      _statusFilter = 'all';
      _priorityFilter = 'all';
      _categoryFilter = 'all';
      _assigneeFilter = 'all';
      _dueFilter = 'all';
      _viewMode = 'list';
    });
  }

  Widget _buildTaskList(BuildContext context, List<TaskRecord> tasks) {
    if (tasks.isEmpty) {
      return const Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.section),
            child: Text('No property tasks found for current filters.'),
          ),
        ),
      );
    }
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const Divider(height: 16),
        itemBuilder: (context, index) {
          final task = tasks[index];
          final selected = _selectedTask?.id == task.id;
          return Material(
            color:
                selected
                    ? context.semanticColors.surfaceAlt
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadiusTokens.md),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadiusTokens.md),
              ),
              title: Text(task.title),
              subtitle: Text(
                '${_statusLabel(task.status)} · ${_priorityLabel(task.priority)}${task.dueAt == null ? '' : ' · due ${formatDateMillis(task.dueAt)}'}',
              ),
              onTap: () => _selectTask(task),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _taskDialog(existing: task),
                    child: const Text('Edit'),
                  ),
                  TextButton(
                    onPressed: () => _deleteTask(task.id),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTaskBoard(List<TaskRecord> tasks) {
    const statuses = <String>['todo', 'in_progress', 'done'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in statuses)
            _PropertyTaskBoardColumn(
              title: _statusLabel(status),
              tasks:
                  tasks.where((task) => task.status == status).toList(growable: false),
              selectedId: _selectedTask?.id,
              onOpen: (task) {
                _selectTask(task);
                setState(() => _viewMode = 'list');
              },
              onEdit: (task) => _taskDialog(existing: task),
              onAdvance: _advanceTask,
            ),
        ],
      ),
    );
  }

  Widget _buildDuePlan(List<TaskRecord> tasks) {
    const buckets = <_PropertyTaskDueBucket>[
      _PropertyTaskDueBucket('Überfällig', 'overdue'),
      _PropertyTaskDueBucket('Heute', 'today'),
      _PropertyTaskDueBucket('Nächste 7 Tage', 'next_7_days'),
      _PropertyTaskDueBucket('Später', 'later'),
      _PropertyTaskDueBucket('Ohne Termin', 'no_due_date'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 760 ? constraints.maxWidth : 260.0;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            for (final bucket in buckets)
              _PropertyTaskDuePanel(
                width: width,
                title: bucket.label,
                tasks: tasks
                    .where((task) => _matchesTaskDueBucket(task, bucket.key))
                    .toList(growable: false),
                onOpen: (task) {
                  _selectTask(task);
                  setState(() => _viewMode = 'list');
                },
                onEdit: (task) => _taskDialog(existing: task),
                onAdvance: _advanceTask,
              ),
          ],
        );
      },
    );
  }

  Widget _buildTaskDetail(BuildContext context) {
    final selectedTask = _selectedTask;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child:
            selectedTask == null
                ? const Center(child: Text('Select a task to inspect details.'))
                : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedTask.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status: ${_statusLabel(selectedTask.status)} · Priority: ${_priorityLabel(selectedTask.priority)}',
                    ),
                    if (selectedTask.category != null ||
                        selectedTask.assignedTo != null ||
                        selectedTask.estimatedCost != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (selectedTask.category != null)
                            selectedTask.category!,
                          if (selectedTask.assignedTo != null)
                            'Bearbeiter: ${selectedTask.assignedTo}',
                          if (selectedTask.estimatedCost != null)
                            'Kosten: ${selectedTask.estimatedCost!.toStringAsFixed(2)}',
                        ].join(' · '),
                      ),
                    ],
                    if (selectedTask.description != null &&
                        selectedTask.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(selectedTask.description!),
                    ],
                    if (selectedTask.dueAt != null) ...[
                      const SizedBox(height: 4),
                      Text('Due date: ${formatDateMillis(selectedTask.dueAt)}'),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _taskDialog(existing: selectedTask),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Bearbeiten'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              selectedTask.status == 'done'
                                  ? null
                                  : () => _advanceTask(selectedTask),
                          icon: const Icon(Icons.arrow_forward_outlined),
                          label: const Text('Status weiter'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _addChecklistDialog(selectedTask.id),
                          icon: const Icon(Icons.playlist_add_outlined),
                          label: const Text('Checkliste'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _checklist.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: AppSpacing.component),
                              child: Text('No checklist items yet.'),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _checklist.length,
                            itemBuilder: (context, index) {
                              final item = _checklist[index];
                              return CheckboxListTile(
                                value: item.done,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: (value) async {
                                  await ref
                                      .read(tasksRepositoryProvider)
                                      .toggleChecklistItem(
                                        id: item.id,
                                        done: value ?? false,
                                      );
                                  await _selectTask(selectedTask);
                                },
                                title: Text(item.text),
                              );
                            },
                          ),
                  ],
                ),
      ),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _status = null;
    });
    final tasks = await ref
        .read(tasksRepositoryProvider)
        .listTasks(
          entityType: 'property',
          entityId: widget.propertyId,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _tasks = tasks;
      _loading = false;
      if (_selectedTask != null) {
        _selectedTask =
            tasks.where((task) => task.id == _selectedTask!.id).isEmpty
                ? null
                : tasks.firstWhere((task) => task.id == _selectedTask!.id);
      }
    });
    final selectedTask = _selectedTask;
    if (selectedTask != null) {
      await _selectTask(selectedTask);
    }
  }

  Future<void> _selectTask(TaskRecord task) async {
    final checklist = await ref
        .read(tasksRepositoryProvider)
        .listChecklistItems(task.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedTask = task;
      _checklist = checklist;
    });
  }

  bool _matchesTaskDueBucket(TaskRecord task, String bucket) {
    return _matchesDueKey(task, bucket);
  }

  Future<void> _advanceTask(TaskRecord task) async {
    if (task.status == 'done') {
      return;
    }
    final nextStatus =
        task.status == 'todo'
            ? 'in_progress'
            : 'done';
    await ref
        .read(tasksRepositoryProvider)
        .updateTaskStatus(id: task.id, status: nextStatus);
    await _reload();
  }

  Future<void> _createTaskDialog() async {
    await _taskDialog();
  }

  Future<void> _taskDialog({TaskRecord? existing}) async {
    final isEdit = existing != null;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    final categoryController = TextEditingController(
      text: existing?.category ?? 'general',
    );
    final assignedToController = TextEditingController(
      text: existing?.assignedTo ?? '',
    );
    final estimatedCostController = TextEditingController(
      text: existing?.estimatedCost?.toStringAsFixed(2) ?? '',
    );
    final dueAtController = TextEditingController(
      text: existing?.dueAt == null ? '' : formatDateMillis(existing?.dueAt),
    );
    var status = existing?.status ?? 'todo';
    var priority = existing?.priority ?? 'normal';
    DateTime? dueDate =
        existing?.dueAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(existing!.dueAt!);
    const allowedStatuses = <String>['todo', 'in_progress', 'done'];
    final statusItems = <DropdownMenuItem<String>>[
      if (!allowedStatuses.contains(status))
        DropdownMenuItem(value: status, child: Text(status)),
      const DropdownMenuItem(value: 'todo', child: Text('To do')),
      const DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
      const DropdownMenuItem(value: 'done', child: Text('Done')),
    ];
    const allowedPriorities = <String>['low', 'normal', 'high'];
    final priorityItems = <DropdownMenuItem<String>>[
      if (!allowedPriorities.contains(priority))
        DropdownMenuItem(value: priority, child: Text(priority)),
      const DropdownMenuItem(value: 'low', child: Text('Low')),
      const DropdownMenuItem(value: 'normal', child: Text('Normal')),
      const DropdownMenuItem(value: 'high', child: Text('High')),
    ];

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
                          labelText: 'Beschreibung',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: categoryController,
                        decoration: const InputDecoration(labelText: 'Kategorie'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: assignedToController,
                        decoration: const InputDecoration(labelText: 'Bearbeiter'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: estimatedCostController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Kostenschätzung',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: statusItems,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() => status = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                        items: priorityItems,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() => priority = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: dueAtController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Fälligkeit',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Termin löschen',
                                onPressed: () {
                                  setDialogState(() {
                                    dueDate = null;
                                    dueAtController.clear();
                                  });
                                },
                                icon: const Icon(Icons.clear),
                              ),
                              const Icon(Icons.calendar_today),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: dueDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked == null) {
                            return;
                          }
                          setDialogState(() {
                            dueDate = picked;
                            dueAtController.text =
                                formatDateMillis(picked.millisecondsSinceEpoch);
                          });
                        },
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
                    if (title.isEmpty) {
                      return;
                    }
                    final dueAt = dueDate?.millisecondsSinceEpoch;
                    final estimatedCost =
                        estimatedCostController.text.trim().isEmpty
                            ? null
                            : double.tryParse(
                              estimatedCostController.text
                                  .trim()
                                  .replaceAll(',', '.'),
                            );
                    final category =
                        categoryController.text.trim().isEmpty
                            ? null
                            : categoryController.text.trim();
                    final assignedTo =
                        assignedToController.text.trim().isEmpty
                            ? null
                            : assignedToController.text.trim();
                    final repo = ref.read(tasksRepositoryProvider);
                    if (isEdit) {
                      await repo.updateTask(
                        TaskRecord(
                          id: existing.id,
                          entityType: 'property',
                          entityId: widget.propertyId,
                          title: title,
                          description:
                              descriptionController.text.trim().isEmpty
                                  ? null
                                  : descriptionController.text.trim(),
                          category: category,
                          assignedTo: assignedTo,
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
                        entityType: 'property',
                        entityId: widget.propertyId,
                        title: title,
                        description:
                            descriptionController.text.trim().isEmpty
                                ? null
                                : descriptionController.text.trim(),
                        category: category,
                        assignedTo: assignedTo,
                        estimatedCost: estimatedCost,
                        status: status,
                        priority: priority,
                        dueAt: dueAt,
                      );
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
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
    categoryController.dispose();
    assignedToController.dispose();
    estimatedCostController.dispose();
    dueAtController.dispose();
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
                  final selectedTask = _selectedTask;
                  if (selectedTask != null) {
                    await _selectTask(selectedTask);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
    textController.dispose();
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
}

class _PropertyTasksDashboard extends StatelessWidget {
  const _PropertyTasksDashboard({
    required this.tasks,
    required this.onStatusFilter,
    required this.onDueFilter,
  });

  final List<TaskRecord> tasks;
  final ValueChanged<String> onStatusFilter;
  final ValueChanged<String> onDueFilter;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    final next7Days = endOfToday.add(const Duration(days: 6));
    final overdue = tasks.where((task) {
      return task.dueAt != null &&
          task.dueAt! < DateTime.now().millisecondsSinceEpoch &&
          task.status != 'done';
    }).length;
    final today = tasks.where((task) {
      if (task.dueAt == null) return false;
      final due = DateTime.fromMillisecondsSinceEpoch(task.dueAt!);
      return !due.isBefore(startOfToday) && due.isBefore(endOfToday);
    }).length;
    final next = tasks.where((task) {
      if (task.dueAt == null) return false;
      final due = DateTime.fromMillisecondsSinceEpoch(task.dueAt!);
      return !due.isBefore(endOfToday) && due.isBefore(next7Days);
    }).length;
    final inProgress = tasks.where((task) => task.status == 'in_progress').length;
    final done = tasks.where((task) => task.status == 'done').length;
    final cost = tasks.fold<double>(
      0,
      (sum, task) => sum + (task.estimatedCost ?? 0),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        final width = narrow ? constraints.maxWidth : 170.0;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _PropertyTaskSignal(
              width: width,
              label: 'Überfällig',
              value: overdue.toString(),
              icon: Icons.warning_amber_outlined,
              tone:
                  overdue == 0
                      ? context.semanticColors.success
                      : Theme.of(context).colorScheme.error,
              onTap: () => onDueFilter('overdue'),
            ),
            _PropertyTaskSignal(
              width: width,
              label: 'Heute',
              value: today.toString(),
              icon: Icons.today_outlined,
              onTap: () => onDueFilter('today'),
            ),
            _PropertyTaskSignal(
              width: width,
              label: '7 Tage',
              value: next.toString(),
              icon: Icons.event_available_outlined,
              onTap: () => onDueFilter('next_7_days'),
            ),
            _PropertyTaskSignal(
              width: width,
              label: 'In Arbeit',
              value: inProgress.toString(),
              icon: Icons.timelapse_outlined,
              onTap: () => onStatusFilter('in_progress'),
            ),
            _PropertyTaskSignal(
              width: width,
              label: 'Erledigt',
              value: done.toString(),
              icon: Icons.done_all_outlined,
              onTap: () => onStatusFilter('done'),
            ),
            _PropertyTaskSignal(
              width: narrow ? constraints.maxWidth : 210,
              label: 'Kosten',
              value: _propertyTaskCurrency(cost),
              icon: Icons.payments_outlined,
            ),
          ],
        );
      },
    );
  }
}

class _PropertyTaskSignal extends StatelessWidget {
  const _PropertyTaskSignal({
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

class _PropertyTaskBoardColumn extends StatelessWidget {
  const _PropertyTaskBoardColumn({
    required this.title,
    required this.tasks,
    required this.selectedId,
    required this.onOpen,
    required this.onEdit,
    required this.onAdvance,
  });

  final String title;
  final List<TaskRecord> tasks;
  final String? selectedId;
  final ValueChanged<TaskRecord> onOpen;
  final ValueChanged<TaskRecord> onEdit;
  final ValueChanged<TaskRecord> onAdvance;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 290,
      margin: const EdgeInsets.only(right: AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.component),
            child: Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                Text(tasks.length.toString()),
              ],
            ),
          ),
          Divider(height: 1, color: context.semanticColors.border),
          tasks.isEmpty
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.component),
                  child: Text(
                    'Keine Aufgaben',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
              : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.sm),
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return _PropertyTaskMiniCard(
                    task: task,
                    selected: task.id == selectedId,
                    onOpen: () => onOpen(task),
                    onEdit: () => onEdit(task),
                    onAdvance: () => onAdvance(task),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _PropertyTaskDuePanel extends StatelessWidget {
  const _PropertyTaskDuePanel({
    required this.width,
    required this.title,
    required this.tasks,
    required this.onOpen,
    required this.onEdit,
    required this.onAdvance,
  });

  final double width;
  final String title;
  final List<TaskRecord> tasks;
  final ValueChanged<TaskRecord> onOpen;
  final ValueChanged<TaskRecord> onEdit;
  final ValueChanged<TaskRecord> onAdvance;

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
              Text(tasks.length.toString()),
            ],
          ),
          const SizedBox(height: 10),
          if (tasks.isEmpty)
            Text('Keine Aufgaben', style: Theme.of(context).textTheme.bodySmall)
          else
            for (final task in tasks.take(5)) ...[
              _PropertyTaskMiniCard(
                task: task,
                selected: false,
                onOpen: () => onOpen(task),
                onEdit: () => onEdit(task),
                onAdvance: () => onAdvance(task),
              ),
            ],
        ],
      ),
    );
  }
}

class _PropertyTaskMiniCard extends StatelessWidget {
  const _PropertyTaskMiniCard({
    required this.task,
    required this.selected,
    required this.onOpen,
    required this.onEdit,
    required this.onAdvance,
  });

  final TaskRecord task;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
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
                '${task.priority}${task.assignedTo == null ? '' : ' · ${task.assignedTo}'}',
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
                          : formatDateMillis(task.dueAt),
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

class _PropertyTaskDueBucket {
  const _PropertyTaskDueBucket(this.label, this.key);

  final String label;
  final String key;
}

String _propertyTaskCurrency(double value) {
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
