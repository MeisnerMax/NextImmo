import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/task.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class TaskTemplatesScreen extends ConsumerStatefulWidget {
  const TaskTemplatesScreen({super.key});

  @override
  ConsumerState<TaskTemplatesScreen> createState() =>
      _TaskTemplatesScreenState();
}

class _TaskTemplatesScreenState extends ConsumerState<TaskTemplatesScreen> {
  List<TaskTemplateRecord> _templates = const [];
  TaskTemplateRecord? _selected;
  List<TaskTemplateChecklistItemRecord> _checklist = const [];
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _createTemplateDialog,
                icon: const Icon(Icons.add),
                label: const Text('New Template'),
              ),
              OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
              OutlinedButton.icon(
                onPressed: _generateNow,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Generate now'),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: Text(_status!)),
          ],
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child:
                      _templates.isEmpty
                          ? const Card(
                            child: Center(child: Text('No templates yet.')),
                          )
                          : ListView.builder(
                            itemCount: _templates.length,
                            itemBuilder: (context, index) {
                              final t = _templates[index];
                              final selected = _selected?.id == t.id;
                              return Card(
                                color:
                                    selected ? const Color(0xFFEAF1F8) : null,
                                child: ListTile(
                                  title: Text(t.name),
                                  subtitle: Text(
                                    '${t.entityType} | ${t.recurrenceRule}/${t.recurrenceInterval}',
                                  ),
                                  onTap: () => _selectTemplate(t),
                                  trailing: Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: () => _editTemplateDialog(t),
                                        child: const Text('Edit'),
                                      ),
                                      TextButton(
                                        onPressed: () => _deleteTemplate(t.id),
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
                          _selected == null
                              ? const Center(child: Text('Select a template'))
                              : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selected!.name,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Default title: ${_selected!.defaultTitle}',
                                  ),
                                  Text('Entity type: ${_selected!.entityType}'),
                                  Text(
                                    'Recurrence: ${_selected!.recurrenceRule} / ${_selected!.recurrenceInterval}',
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton(
                                    onPressed:
                                        () =>
                                            _addChecklistDialog(_selected!.id),
                                    child: const Text('Add Checklist Item'),
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
                                                return ListTile(
                                                  title: Text(item.text),
                                                  trailing: IconButton(
                                                    onPressed:
                                                        () =>
                                                            _deleteChecklistItem(
                                                              item.id,
                                                            ),
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                    ),
                                                  ),
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
    final templates = await ref.read(tasksRepositoryProvider).listTemplates();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      if (_selected != null) {
        final match = templates.where((t) => t.id == _selected!.id);
        _selected = match.isEmpty ? null : match.first;
      }
    });
    final selected = _selected;
    if (selected != null) {
      await _selectTemplate(selected);
    }
  }

  Future<void> _selectTemplate(TaskTemplateRecord template) async {
    final checklist = await ref
        .read(tasksRepositoryProvider)
        .listTemplateChecklistItems(template.id);
    if (!mounted) return;
    setState(() {
      _selected = template;
      _checklist = checklist;
    });
  }

  Future<void> _createTemplateDialog() async {
    await _templateDialog();
  }

  Future<void> _editTemplateDialog(TaskTemplateRecord template) async {
    await _templateDialog(existing: template);
  }

  Future<void> _templateDialog({TaskTemplateRecord? existing}) async {
    final isEdit = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final titleController = TextEditingController(
      text: existing?.defaultTitle ?? '',
    );
    final dueOffsetController = TextEditingController(
      text: existing?.defaultDueDaysOffset?.toString() ?? '',
    );
    final intervalController = TextEditingController(
      text: (existing?.recurrenceInterval ?? 1).toString(),
    );
    var entityType = existing?.entityType ?? 'none';
    var priority = existing?.defaultPriority ?? 'normal';
    var recurrence = existing?.recurrenceRule ?? 'monthly';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit Template' : 'Create Template'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Default title',
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
                          labelText: 'Default priority',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: dueOffsetController,
                        decoration: const InputDecoration(
                          labelText: 'Default due days offset',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: recurrence,
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('none')),
                          DropdownMenuItem(
                            value: 'daily',
                            child: Text('daily'),
                          ),
                          DropdownMenuItem(
                            value: 'weekly',
                            child: Text('weekly'),
                          ),
                          DropdownMenuItem(
                            value: 'monthly',
                            child: Text('monthly'),
                          ),
                          DropdownMenuItem(
                            value: 'quarterly',
                            child: Text('quarterly'),
                          ),
                          DropdownMenuItem(
                            value: 'yearly',
                            child: Text('yearly'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => recurrence = value);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Recurrence rule',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: intervalController,
                        decoration: const InputDecoration(
                          labelText: 'Recurrence interval',
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
                    final name = nameController.text.trim();
                    final defaultTitle = titleController.text.trim();
                    final interval =
                        int.tryParse(intervalController.text.trim()) ?? 1;
                    if (name.isEmpty || defaultTitle.isEmpty) {
                      return;
                    }
                    final dueOffset =
                        dueOffsetController.text.trim().isEmpty
                            ? null
                            : int.tryParse(dueOffsetController.text.trim());
                    final repo = ref.read(tasksRepositoryProvider);
                    if (isEdit) {
                      await repo.updateTemplate(
                        TaskTemplateRecord(
                          id: existing.id,
                          name: name,
                          entityType: entityType,
                          defaultTitle: defaultTitle,
                          defaultPriority: priority,
                          defaultDueDaysOffset: dueOffset,
                          recurrenceRule: recurrence,
                          recurrenceInterval: interval <= 0 ? 1 : interval,
                          createdAt: existing.createdAt,
                          updatedAt: DateTime.now().millisecondsSinceEpoch,
                        ),
                      );
                    } else {
                      await repo.createTemplate(
                        name: name,
                        entityType: entityType,
                        defaultTitle: defaultTitle,
                        defaultPriority: priority,
                        defaultDueDaysOffset: dueOffset,
                        recurrenceRule: recurrence,
                        recurrenceInterval: interval <= 0 ? 1 : interval,
                      );
                    }
                    if (mounted) {
                      Navigator.of(this.context, rootNavigator: true).pop();
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

    nameController.dispose();
    titleController.dispose();
    dueOffsetController.dispose();
    intervalController.dispose();
  }

  Future<void> _deleteTemplate(String id) async {
    await ref.read(tasksRepositoryProvider).deleteTemplate(id);
    await _reload();
  }

  Future<void> _addChecklistDialog(String templateId) async {
    final textController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Template Checklist Item'),
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
                  if (text.isEmpty) return;
                  await ref
                      .read(tasksRepositoryProvider)
                      .addTemplateChecklistItem(
                        templateId: templateId,
                        text: text,
                        position: _checklist.length,
                      );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  final selected = _selected;
                  if (selected != null) {
                    await _selectTemplate(selected);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
    textController.dispose();
  }

  Future<void> _deleteChecklistItem(String id) async {
    await ref.read(tasksRepositoryProvider).deleteTemplateChecklistItem(id);
    final selected = _selected;
    if (selected != null) {
      await _selectTemplate(selected);
    }
  }

  Future<void> _generateNow() async {
    final inputsRepo = ref.read(inputsRepositoryProvider);
    final settings = await inputsRepo.getSettings();
    final now = DateTime.now().millisecondsSinceEpoch;
    final summary = await ref
        .read(taskGenerationServiceProvider)
        .generate(
          now: now,
          dueSoonDays: settings.taskDueSoonDays,
          enableNotifications: settings.enableTaskNotifications,
        );
    await inputsRepo.updateSettings(
      settings.copyWith(
        lastTaskGenerationAt: now,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (!mounted) return;
    setState(() {
      _status =
          'Generated ${summary.generatedTasks} task(s), ${summary.generatedNotifications} notification(s).';
    });
  }
}
