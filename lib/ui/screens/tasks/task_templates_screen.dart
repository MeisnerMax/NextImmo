import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/task.dart';
import '../../components/nx_card.dart';
import '../../components/nx_status_badge.dart';
import '../../state/app_state.dart';
import '../../templates/list_filter_template.dart';
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
    return ListFilterTemplate(
      title: 'Aufgabenvorlagen',
      breadcrumbs: const ['Administration', 'Aufgabenvorlagen'],
      subtitle:
          'Wiederkehrende Aufgaben mit Standardpriorität, Rhythmus und Checkliste steuern.',
      primaryAction: ElevatedButton.icon(
        onPressed: _createTemplateDialog,
        icon: const Icon(Icons.add_outlined),
        label: const Text('Vorlage erstellen'),
      ),
      secondaryActions: [
        OutlinedButton.icon(
          onPressed: _generateNow,
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('Jetzt erzeugen'),
        ),
        OutlinedButton.icon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Aktualisieren'),
        ),
      ],
      contextBar:
          _status == null
              ? null
              : NxCard(
                padding: const EdgeInsets.all(AppSpacing.component),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_status!)),
                  ],
                ),
              ),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _templatesPane(context)),
                const SizedBox(width: AppSpacing.component),
                Expanded(child: _detailPane(context)),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 420, child: _templatesPane(context)),
                const SizedBox(height: AppSpacing.component),
                SizedBox(height: 420, child: _detailPane(context)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _templatesPane(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PaneHeader(
            icon: Icons.fact_check_outlined,
            title: 'Vorlagen',
            badge: '${_templates.length}',
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child:
                _templates.isEmpty
                    ? const _TemplateEmptyState(
                      title: 'Keine Vorlagen',
                      description: 'Neue Vorlage erstellen, um Aufgaben automatisch zu erzeugen.',
                      icon: Icons.fact_check_outlined,
                    )
                    : ListView.separated(
                      itemCount: _templates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final template = _templates[index];
                        final selected = _selected?.id == template.id;
                        return ListTile(
                          selected: selected,
                          selectedTileColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                          title: Text(template.name),
                          subtitle: Text(
                            '${_entityTypeLabel(template.entityType)} | '
                            '${_recurrenceLabel(template.recurrenceRule)} '
                            'x${template.recurrenceInterval}',
                          ),
                          onTap: () => _selectTemplate(template),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Bearbeiten',
                                onPressed: () => _editTemplateDialog(template),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Löschen',
                                onPressed:
                                    () => _confirmDeleteTemplate(template),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _detailPane(BuildContext context) {
    final selected = _selected;
    return NxCard(
      child:
          selected == null
              ? const _TemplateEmptyState(
                title: 'Vorlage auswählen',
                description: 'Links eine Vorlage auswählen, um Details und Checkliste zu bearbeiten.',
                icon: Icons.rule_folder_outlined,
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PaneHeader(
                    icon: Icons.rule_folder_outlined,
                    title: selected.name,
                    badge: _priorityLabel(selected.defaultPriority),
                  ),
                  const SizedBox(height: AppSpacing.component),
                  Wrap(
                    spacing: AppSpacing.component,
                    runSpacing: AppSpacing.component,
                    children: [
                      _TemplateFact(
                        label: 'Titel',
                        value: selected.defaultTitle,
                      ),
                      _TemplateFact(
                        label: 'Bereich',
                        value: _entityTypeLabel(selected.entityType),
                      ),
                      _TemplateFact(
                        label: 'Rhythmus',
                        value:
                            '${_recurrenceLabel(selected.recurrenceRule)} x${selected.recurrenceInterval}',
                      ),
                      _TemplateFact(
                        label: 'Fälligkeit',
                        value:
                            selected.defaultDueDaysOffset == null
                                ? 'Nicht gesetzt'
                                : '+${selected.defaultDueDaysOffset} Tage',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.component),
                  OutlinedButton.icon(
                    onPressed: () => _addChecklistDialog(selected.id),
                    icon: const Icon(Icons.playlist_add_outlined),
                    label: const Text('Checklistenpunkt hinzufügen'),
                  ),
                  const SizedBox(height: AppSpacing.component),
                  Expanded(
                    child:
                        _checklist.isEmpty
                            ? const _TemplateEmptyState(
                              title: 'Keine Checkliste',
                              description: 'Checklistenpunkte strukturieren die automatisch erzeugten Aufgaben.',
                              icon: Icons.checklist_outlined,
                            )
                            : ListView.separated(
                              itemCount: _checklist.length,
                              separatorBuilder:
                                  (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _checklist[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 13,
                                    child: Text('${index + 1}'),
                                  ),
                                  title: Text(item.text),
                                  trailing: IconButton(
                                    tooltip: 'Löschen',
                                    onPressed:
                                        () => _deleteChecklistItem(item.id),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                );
                              },
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
              title: Text(isEdit ? 'Vorlage bearbeiten' : 'Vorlage erstellen'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Standardtitel',
                          prefixIcon: Icon(Icons.title_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: entityType,
                        items: const [
                          DropdownMenuItem(
                            value: 'none',
                            child: Text('Ohne festen Bereich'),
                          ),
                          DropdownMenuItem(
                            value: 'property',
                            child: Text('Objekt'),
                          ),
                          DropdownMenuItem(
                            value: 'portfolio',
                            child: Text('Portfolio'),
                          ),
                          DropdownMenuItem(
                            value: 'asset_property',
                            child: Text('Objekt (Asset)'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => entityType = value);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Bereich',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: priority,
                        items: const [
                          DropdownMenuItem(
                            value: 'low',
                            child: Text('Niedrig'),
                          ),
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text('Normal'),
                          ),
                          DropdownMenuItem(
                            value: 'high',
                            child: Text('Hoch'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => priority = value);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Standardpriorität',
                          prefixIcon: Icon(Icons.priority_high_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: dueOffsetController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Fällig nach Tagen',
                          prefixIcon: Icon(Icons.event_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: recurrence,
                        items: const [
                          DropdownMenuItem(
                            value: 'none',
                            child: Text('Einmalig'),
                          ),
                          DropdownMenuItem(
                            value: 'daily',
                            child: Text('Täglich'),
                          ),
                          DropdownMenuItem(
                            value: 'weekly',
                            child: Text('Wöchentlich'),
                          ),
                          DropdownMenuItem(
                            value: 'monthly',
                            child: Text('Monatlich'),
                          ),
                          DropdownMenuItem(
                            value: 'quarterly',
                            child: Text('Quartalsweise'),
                          ),
                          DropdownMenuItem(
                            value: 'yearly',
                            child: Text('Jährlich'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => recurrence = value);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Rhythmus',
                          prefixIcon: Icon(Icons.repeat_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: intervalController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Intervall',
                          prefixIcon: Icon(Icons.numbers_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
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
                  child: Text(isEdit ? 'Speichern' : 'Erstellen'),
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

  Future<void> _confirmDeleteTemplate(TaskTemplateRecord template) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Vorlage löschen'),
            content: Text(
              '"${template.name}" wird inklusive Checkliste gelöscht.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Löschen'),
              ),
            ],
          ),
    );
    if (shouldDelete != true || !mounted) {
      return;
    }
    await ref.read(tasksRepositoryProvider).deleteTemplate(template.id);
    await _reload();
  }

  Future<void> _addChecklistDialog(String templateId) async {
    final textController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Checklistenpunkt hinzufügen'),
            content: TextField(
              controller: textController,
              decoration: const InputDecoration(
                labelText: 'Text',
                prefixIcon: Icon(Icons.checklist_outlined),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Abbrechen'),
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
                child: const Text('Hinzufügen'),
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
          '${summary.generatedTasks} Aufgabe(n) und ${summary.generatedNotifications} Benachrichtigung(en) erzeugt.';
    });
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({
    required this.icon,
    required this.title,
    required this.badge,
  });

  final IconData icon;
  final String title;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        NxStatusBadge(label: badge, kind: NxBadgeKind.info),
      ],
    );
  }
}

class _TemplateFact extends StatelessWidget {
  const _TemplateFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.viewport == AppViewport.mobile ? double.infinity : 220,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _TemplateEmptyState extends StatelessWidget {
  const _TemplateEmptyState({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          border: Border.all(color: context.semanticColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: context.semanticColors.textSecondary),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _entityTypeLabel(String value) {
  switch (value) {
    case 'property':
    case 'asset_property':
      return 'Objekt';
    case 'portfolio':
      return 'Portfolio';
    case 'document':
      return 'Dokument';
    default:
      return 'Ohne festen Bereich';
  }
}

String _recurrenceLabel(String value) {
  switch (value) {
    case 'daily':
      return 'Täglich';
    case 'weekly':
      return 'Wöchentlich';
    case 'monthly':
      return 'Monatlich';
    case 'quarterly':
      return 'Quartalsweise';
    case 'yearly':
      return 'Jährlich';
    default:
      return 'Einmalig';
  }
}

String _priorityLabel(String value) {
  switch (value) {
    case 'low':
      return 'Niedrig';
    case 'high':
      return 'Hoch';
    default:
      return 'Normal';
  }
}
