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
  bool _loading = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
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
                    _reload();
                  },
                ),
              ),
              if (_status != null)
                Text(_status!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child:
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 980;
                        if (stacked) {
                          return ListView(
                            children: [
                              SizedBox(
                                height: 320,
                                child: _buildTaskList(context),
                              ),
                              const SizedBox(height: AppSpacing.component),
                              SizedBox(
                                height: 320,
                                child: _buildTaskDetail(context),
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: _buildTaskList(context)),
                            const SizedBox(width: AppSpacing.component),
                            Expanded(child: _buildTaskDetail(context)),
                          ],
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(BuildContext context) {
    if (_tasks.isEmpty) {
      return const Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.section),
            child: Text('No property tasks found.'),
          ),
        ),
      );
    }
    return Card(
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        itemCount: _tasks.length,
        separatorBuilder: (_, __) => const Divider(height: 16),
        itemBuilder: (context, index) {
          final task = _tasks[index];
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
                    if (selectedTask.dueAt != null) ...[
                      const SizedBox(height: 4),
                      Text('Due date: ${formatDateMillis(selectedTask.dueAt)}'),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _addChecklistDialog(selectedTask.id),
                      child: const Text('Add Checklist Item'),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child:
                          _checklist.isEmpty
                              ? const Center(
                                child: Text('No checklist items yet.'),
                              )
                              : ListView.builder(
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
          status: _statusFilter == 'all' ? null : _statusFilter,
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

  Future<void> _createTaskDialog() async {
    await _taskDialog();
  }

  Future<void> _taskDialog({TaskRecord? existing}) async {
    final isEdit = existing != null;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final dueAtController = TextEditingController(
      text: existing?.dueAt?.toString() ?? '',
    );
    var status = existing?.status ?? 'todo';
    var priority = existing?.priority ?? 'normal';

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
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const [
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
                          setDialogState(() => status = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'low', child: Text('Low')),
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text('Normal'),
                          ),
                          DropdownMenuItem(value: 'high', child: Text('High')),
                        ],
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
                        decoration: const InputDecoration(
                          labelText: 'Due date (epoch ms, optional)',
                        ),
                        keyboardType: TextInputType.number,
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
                    final dueAt =
                        dueAtController.text.trim().isEmpty
                            ? null
                            : int.tryParse(dueAtController.text.trim());
                    final repo = ref.read(tasksRepositoryProvider);
                    if (isEdit) {
                      await repo.updateTask(
                        TaskRecord(
                          id: existing.id,
                          entityType: 'property',
                          entityId: widget.propertyId,
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
                        entityType: 'property',
                        entityId: widget.propertyId,
                        title: title,
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
