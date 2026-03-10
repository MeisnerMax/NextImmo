import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/documents.dart';
import '../../../core/models/task.dart';
import '../../components/nx_form_section_card.dart';
import '../../state/app_state.dart';

String formatDateMillis(int? value) {
  if (value == null) {
    return '-';
  }
  return DateTime.fromMillisecondsSinceEpoch(
    value,
  ).toIso8601String().substring(0, 10);
}

class OperationsSectionCard extends StatelessWidget {
  const OperationsSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return NxFormSectionCard(title: title, trailing: action, children: [child]);
  }
}

class OperationsTasksPanel extends StatelessWidget {
  const OperationsTasksPanel({
    super.key,
    required this.tasks,
    required this.emptyHint,
  });

  final List<TaskRecord> tasks;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Text(emptyHint);
    }
    return Column(
      children: tasks
          .map(
            (task) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(task.title),
              subtitle: Text(
                '${task.status} · ${task.priority}${task.dueAt == null ? '' : ' · due ${formatDateMillis(task.dueAt)}'}',
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class OperationsDocumentsPanel extends StatelessWidget {
  const OperationsDocumentsPanel({
    super.key,
    required this.documents,
    required this.emptyHint,
  });

  final List<DocumentRecord> documents;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return Text(emptyHint);
    }
    return Column(
      children: documents
          .map(
            (document) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(document.fileName),
              subtitle: Text(
                '${document.typeId ?? 'untyped'} · ${document.filePath}',
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

Future<void> showCreateTaskDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String entityType,
  required String entityId,
  required String defaultTitle,
}) async {
  final titleCtrl = TextEditingController(text: defaultTitle);
  String priority = 'normal';
  DateTime? dueDate;
  await showDialog<void>(
    context: context,
    builder:
        (context) => StatefulBuilder(
          builder:
              (context, setDialogState) => AlertDialog(
                title: const Text('Create Task'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(labelText: 'Title'),
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
                          if (value != null) {
                            setDialogState(() => priority = value);
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                      ),
                      const SizedBox(height: 8),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Due Date',
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatDateMillis(
                                  dueDate?.millisecondsSinceEpoch,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: dueDate ?? DateTime.now(),
                                  firstDate: DateTime.now().subtract(
                                    const Duration(days: 365),
                                  ),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 3650),
                                  ),
                                );
                                if (picked != null && context.mounted) {
                                  setDialogState(() => dueDate = picked);
                                }
                              },
                              child: const Text('Select'),
                            ),
                            if (dueDate != null)
                              TextButton(
                                onPressed:
                                    () => setDialogState(() => dueDate = null),
                                child: const Text('Clear'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final title = titleCtrl.text.trim();
                      if (title.isEmpty) {
                        return;
                      }
                      await ref
                          .read(tasksRepositoryProvider)
                          .createTask(
                            entityType: entityType,
                            entityId: entityId,
                            title: title,
                            priority: priority,
                            dueAt: dueDate?.millisecondsSinceEpoch,
                          );
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Text('Create'),
                  ),
                ],
              ),
        ),
  );
  titleCtrl.dispose();
}

Future<void> showCreateDocumentHookDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String entityType,
  required String entityId,
}) async {
  final fileNameCtrl = TextEditingController();
  final filePathCtrl = TextEditingController();
  final typeCtrl = TextEditingController();
  await showDialog<void>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: const Text('Add Document Hook'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fileNameCtrl,
                  decoration: const InputDecoration(labelText: 'File Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: filePathCtrl,
                  decoration: const InputDecoration(labelText: 'File Path'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Type Id (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final fileName = fileNameCtrl.text.trim();
                final filePath = filePathCtrl.text.trim();
                if (fileName.isEmpty || filePath.isEmpty) {
                  return;
                }
                await ref
                    .read(documentsRepositoryProvider)
                    .createDocument(
                      entityType: entityType,
                      entityId: entityId,
                      typeId:
                          typeCtrl.text.trim().isEmpty
                              ? null
                              : typeCtrl.text.trim(),
                      filePath: filePath,
                      fileName: fileName,
                    );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
  );
  fileNameCtrl.dispose();
  filePathCtrl.dispose();
  typeCtrl.dispose();
}
