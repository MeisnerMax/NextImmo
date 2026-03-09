import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/task.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  List<TaskRecord> _tasks = const [];
  String _statusFilter = 'todo';
  String _entityTypeFilter = 'all';
  TaskRecord? _selectedTask;
  List<TaskChecklistItemRecord> _checklist = const [];
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _createTaskDialog,
                icon: const Icon(Icons.add),
                label: const Text('New Task'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'todo', child: Text('todo')),
                    DropdownMenuItem(
                      value: 'in_progress',
                      child: Text('in_progress'),
                    ),
                    DropdownMenuItem(value: 'done', child: Text('done')),
                    DropdownMenuItem(value: 'all', child: Text('all')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _statusFilter = value);
                    _reload();
                  },
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _entityTypeFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('all')),
                    DropdownMenuItem(value: 'none', child: Text('none')),
                    DropdownMenuItem(
                      value: 'property',
                      child: Text('property'),
                    ),
                    DropdownMenuItem(
                      value: 'portfolio',
                      child: Text('portfolio'),
                    ),
                    DropdownMenuItem(
                      value: 'asset_property',
                      child: Text('asset_property'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _entityTypeFilter = value);
                    _reload();
                  },
                  decoration: const InputDecoration(labelText: 'Entity Type'),
                ),
              ),
              if (_status != null) ...[
                const SizedBox(width: 12),
                Expanded(child: Text(_status!)),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child:
                      _tasks.isEmpty
                          ? const Card(
                            child: Center(child: Text('No tasks found.')),
                          )
                          : ListView.builder(
                            itemCount: _tasks.length,
                            itemBuilder: (context, index) {
                              final task = _tasks[index];
                              final selected = _selectedTask?.id == task.id;
                              return Card(
                                color:
                                    selected ? const Color(0xFFEAF1F8) : null,
                                child: ListTile(
                                  title: Text(task.title),
                                  subtitle: Text(
                                    '${task.status} | ${task.priority}${task.dueAt == null ? '' : ' | due ${DateTime.fromMillisecondsSinceEpoch(task.dueAt!).toIso8601String().substring(0, 10)}'}',
                                  ),
                                  onTap: () => _selectTask(task),
                                  trailing: Wrap(
                                    spacing: 8,
                                    children: [
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
                                ),
                              );
                            },
                          ),
                ),
                const SizedBox(width: AppSpacing.component),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.cardPadding),
                      child:
                          _selectedTask == null
                              ? const Center(child: Text('Select a task'))
                              : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedTask!.title,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Status: ${_selectedTask!.status} | Priority: ${_selectedTask!.priority}',
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      OutlinedButton(
                                        onPressed:
                                            () => _addChecklistDialog(
                                              _selectedTask!.id,
                                            ),
                                        child: const Text('Add Checklist Item'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child:
                                        _checklist.isEmpty
                                            ? const Center(
                                              child: Text(
                                                'No checklist items.',
                                              ),
                                            )
                                            : ListView.builder(
                                              itemCount: _checklist.length,
                                              itemBuilder: (context, index) {
                                                final item = _checklist[index];
                                                return CheckboxListTile(
                                                  value: item.done,
                                                  onChanged: (value) async {
                                                    await ref
                                                        .read(
                                                          tasksRepositoryProvider,
                                                        )
                                                        .toggleChecklistItem(
                                                          id: item.id,
                                                          done: value ?? false,
                                                        );
                                                    await _selectTask(
                                                      _selectedTask!,
                                                    );
                                                  },
                                                  title: Text(item.text),
                                                  controlAffinity:
                                                      ListTileControlAffinity
                                                          .leading,
                                                );
                                              },
                                            ),
                                  ),
                                ],
                              ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reload() async {
    final tasks = await ref
        .read(tasksRepositoryProvider)
        .listTasks(
          status: _statusFilter == 'all' ? null : _statusFilter,
          entityType: _entityTypeFilter == 'all' ? null : _entityTypeFilter,
        );
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      if (_selectedTask != null) {
        _selectedTask =
            tasks.where((t) => t.id == _selectedTask!.id).isNotEmpty
                ? tasks.firstWhere((t) => t.id == _selectedTask!.id)
                : null;
      }
    });
    if (_selectedTask != null) {
      await _selectTask(_selectedTask!);
    }
  }

  Future<void> _selectTask(TaskRecord task) async {
    final checklist = await ref
        .read(tasksRepositoryProvider)
        .listChecklistItems(task.id);
    if (!mounted) return;
    setState(() {
      _selectedTask = task;
      _checklist = checklist;
    });
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
                          DropdownMenuItem(value: 'todo', child: Text('todo')),
                          DropdownMenuItem(
                            value: 'in_progress',
                            child: Text('in_progress'),
                          ),
                          DropdownMenuItem(value: 'done', child: Text('done')),
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
                          DropdownMenuItem(value: 'low', child: Text('low')),
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text('normal'),
                          ),
                          DropdownMenuItem(value: 'high', child: Text('high')),
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
                          DropdownMenuItem(value: 'none', child: Text('none')),
                          DropdownMenuItem(
                            value: 'property',
                            child: Text('property'),
                          ),
                          DropdownMenuItem(
                            value: 'portfolio',
                            child: Text('portfolio'),
                          ),
                          DropdownMenuItem(
                            value: 'asset_property',
                            child: Text('asset_property'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => entityType = value);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Entity type',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: entityIdController,
                        decoration: const InputDecoration(
                          labelText: 'Entity id',
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
}
