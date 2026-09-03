/// The one task dialog (Shared §5.2, `task_center.md` §12) plus the small
/// confirmation dialogs of the Task Center. Every surface that creates or
/// edits a task goes through [showTaskCreateDialog]/[showTaskEditDialog] —
/// the three divergent legacy dialogs converge here, and `OperationsAlertsPanel`
/// binds the same create dialog with a preset entity.
///
/// The dialog owns its `mutationId`: created once when it opens, kept across
/// every submit attempt (validation fixes, conflict re-saves — the server
/// releases the receipt on failure), renewed only by cancel + reopen.
library;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../ui/components/nx_notice.dart';
import '../../application/platform_repository.dart';
import '../../domain/platform_entity_type.dart';
import '../../domain/task_category.dart';
import '../../domain/task_dto.dart';
import '../platform_error_presentation.dart';
import '../task_badges.dart';
import '../task_formatting.dart';
import 'entity_ref_chip.dart';

/// Executes a create against the contract; null means success (the dialog
/// closes), a failure keeps the dialog open and is mapped per Shared §12.
typedef TaskCreateSubmit =
    Future<PlatformRepositoryFailure<TaskDto>?> Function(
      TaskDraft draft,
      String mutationId,
    );

/// Executes an edit with the version the dialog currently trusts.
typedef TaskEditSubmit =
    Future<PlatformRepositoryFailure<TaskDto>?> Function(
      TaskUpdateDto changes,
      int expectedVersion,
      String mutationId,
    );

/// Opens the shared create dialog. [presetEntity] locks the context
/// (property workspace, operations alerts); without it the context row
/// states the V1 gap honestly instead of offering a picker that could not
/// name anything (`TASK-QUERY-01`). [selfAssignActorId] enables
/// "Mir zuweisen" — the only assignment V1 supports (B6).
Future<bool?> showTaskCreateDialog(
  BuildContext context, {
  required TaskCreateSubmit onSubmit,
  PlatformEntityRef? presetEntity,
  String? selfAssignActorId,
  String? initialTitle,
  String? initialDescription,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _TaskFormDialog(
      onCreate: onSubmit,
      presetEntity: presetEntity,
      selfAssignActorId: selfAssignActorId,
      initialTitle: initialTitle,
      initialDescription: initialDescription,
    ),
  );
}

/// Opens the shared edit dialog for [task]. Status is deliberately absent —
/// it moves only through the transition actions (§6.2).
Future<bool?> showTaskEditDialog(
  BuildContext context, {
  required TaskDto task,
  required TaskEditSubmit onSubmit,
  String? selfAssignActorId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _TaskFormDialog(
      onEdit: onSubmit,
      task: task,
      selfAssignActorId: selfAssignActorId,
    ),
  );
}

enum _AssignSelection { unchanged, self, none }

class _TaskFormDialog extends StatefulWidget {
  const _TaskFormDialog({
    this.onCreate,
    this.onEdit,
    this.task,
    this.presetEntity,
    this.selfAssignActorId,
    this.initialTitle,
    this.initialDescription,
  }) : assert((onCreate != null) != (onEdit != null)),
       assert(onEdit == null || task != null);

  final TaskCreateSubmit? onCreate;
  final TaskEditSubmit? onEdit;
  final TaskDto? task;
  final PlatformEntityRef? presetEntity;
  final String? selfAssignActorId;
  final String? initialTitle;
  final String? initialDescription;

  bool get isEdit => onEdit != null;

  @override
  State<_TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<_TaskFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// One intent, one id — for the whole life of this dialog (§12).
  final String _mutationId = const Uuid().v4();

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;

  /// The category as a wire value; null = no category. An unknown server
  /// value stays representable as itself so an untouched edit preserves it.
  String? _categoryWire;
  late final String? _initialCategoryWire;

  late TaskPriority _priority;
  DateTime? _dueAt;
  _AssignSelection _assign = _AssignSelection.unchanged;

  bool _submitting = false;
  String? _bannerError;
  Map<String, String> _fieldErrors = const <String, String>{};
  PlatformVersionConflict? _conflict;

  /// The version the next save is made against; a conflict's "Neu laden"
  /// advances it to the server's.
  late int _expectedVersion;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleCtrl = TextEditingController(
      text: task?.title ?? widget.initialTitle ?? '',
    );
    _descriptionCtrl = TextEditingController(
      text: task?.description ?? widget.initialDescription ?? '',
    );
    _initialCategoryWire = widget.isEdit
        ? task!.category
        : TaskCategory.general.wireName;
    _categoryWire = _initialCategoryWire;
    _priority = task?.priority ?? TaskPriority.normal;
    _dueAt = task?.dueAt;
    _assign = widget.isEdit ? _AssignSelection.unchanged : _AssignSelection.none;
    _expectedVersion = task?.version ?? 0;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  PlatformEntityRef? get _entity => widget.isEdit
      ? widget.task!.entity
      : widget.presetEntity;

  bool get _dirty {
    final task = widget.task;
    if (!widget.isEdit) {
      return _titleCtrl.text != (widget.initialTitle ?? '') ||
          _descriptionCtrl.text != (widget.initialDescription ?? '') ||
          _categoryWire != _initialCategoryWire ||
          _priority != TaskPriority.normal ||
          _dueAt != null ||
          _assign != _AssignSelection.none;
    }
    return _titleCtrl.text != task!.title ||
        _descriptionCtrl.text != (task.description ?? '') ||
        _categoryWire != _initialCategoryWire ||
        _priority != task.priority ||
        _dueAt != task.dueAt ||
        _assign != _AssignSelection.unchanged;
  }

  Future<void> _close() async {
    if (_submitting) {
      return;
    }
    if (!_dirty) {
      Navigator.of(context).pop(false);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('task-dialog-discard'),
        title: const Text('Änderungen verwerfen?'),
        content: const Text(
          'Die Eingaben in diesem Dialog gehen verloren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('task-dialog-discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt?.toLocal() ?? DateTime.now(),
      // The one unified range (§12); no past-date lock — backfilling is real.
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _dueAt = picked);
    }
  }

  TaskDraft _buildDraft() {
    final actorId = widget.selfAssignActorId;
    return TaskDraft(
      title: _titleCtrl.text.trim(),
      description: _descriptionCtrl.text.trim().isEmpty
          ? null
          : _descriptionCtrl.text.trim(),
      category: _categoryWire,
      priority: _priority,
      dueAt: _dueAt,
      assignedTo: _assign == _AssignSelection.self ? actorId : null,
      entity: _entity,
    );
  }

  /// Sparse edit: only fields that differ from the loaded task are sent, so
  /// an untouched unknown category (or anything else) survives the cycle
  /// (§7.5, Shared §17).
  TaskUpdateDto _buildChanges() {
    final task = widget.task!;
    final title = _titleCtrl.text.trim();
    final description = _descriptionCtrl.text.trim();
    return TaskUpdateDto(
      title: title == task.title ? null : title,
      description: description == (task.description ?? '')
          ? const TaskFieldEdit<String>.absent()
          : (description.isEmpty
                ? const TaskFieldEdit<String>.clear()
                : TaskFieldEdit<String>.set(description)),
      category: _categoryWire == _initialCategoryWire
          ? const TaskFieldEdit<String>.absent()
          : (_categoryWire == null
                ? const TaskFieldEdit<String>.clear()
                : TaskFieldEdit<String>.set(_categoryWire!)),
      priority: _priority == task.priority ? null : _priority,
      dueAt: _dueAt == task.dueAt
          ? const TaskFieldEdit<DateTime>.absent()
          : (_dueAt == null
                ? const TaskFieldEdit<DateTime>.clear()
                : TaskFieldEdit<DateTime>.set(_dueAt!)),
      assignedTo: switch (_assign) {
        _AssignSelection.unchanged => const TaskFieldEdit<String>.absent(),
        _AssignSelection.self => TaskFieldEdit<String>.set(
          widget.selfAssignActorId!,
        ),
        _AssignSelection.none => const TaskFieldEdit<String>.clear(),
      },
    );
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _submitting = true;
      _bannerError = null;
      _fieldErrors = const <String, String>{};
      _conflict = null;
    });
    final failure = widget.isEdit
        ? await widget.onEdit!(_buildChanges(), _expectedVersion, _mutationId)
        : await widget.onCreate!(_buildDraft(), _mutationId);
    if (!mounted) {
      return;
    }
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      switch (platformErrorDispositionOf(failure)) {
        case PlatformErrorDisposition.fieldValidation:
          if (failure.validationFields.isEmpty) {
            _bannerError = platformErrorMessageOf(failure);
          } else {
            _fieldErrors = <String, String>{
              for (final field in failure.validationFields)
                field: failure.message,
            };
          }
        case PlatformErrorDisposition.versionConflict:
          _conflict = failure.versionConflict;
        case PlatformErrorDisposition.mutationConflict:
        case PlatformErrorDisposition.retryInProgress:
        case PlatformErrorDisposition.notFound:
        case PlatformErrorDisposition.aalStepUpRequired:
        case PlatformErrorDisposition.forbidden:
        case PlatformErrorDisposition.infrastructure:
          _bannerError = platformErrorMessageOf(failure);
      }
    });
  }

  /// "Neu laden" after a conflict: reseeds every field from the server's
  /// `current_entity` and trusts its version — nothing of the user's input
  /// survives this deliberate choice, which is why it is a button and not
  /// automatic (Foundation §10).
  void _reseedFromConflict() {
    final current = _conflict?.currentTask;
    if (current == null) {
      return;
    }
    setState(() {
      _titleCtrl.text = current.title;
      _descriptionCtrl.text = current.description ?? '';
      _categoryWire = current.category;
      _priority = current.priority;
      _dueAt = current.dueAt;
      _assign = _AssignSelection.unchanged;
      _expectedVersion = current.version;
      _conflict = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.isEdit;
    final actorId = widget.selfAssignActorId;
    final knownCategory = _categoryWire == null
        ? null
        : TaskCategory.tryFromWire(_categoryWire);
    final unknownRaw =
        _categoryWire != null && knownCategory == null ? _categoryWire : null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _close();
        }
      },
      child: AlertDialog(
        key: const Key('task-form-dialog'),
        title: Text(isEdit ? 'Aufgabe bearbeiten' : 'Neue Aufgabe'),
        content: SizedBox(
          width: 480,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_conflict != null) ...[
                    NxNotice(
                      key: const Key('task-detail-conflict'),
                      kind: NxNoticeKind.warning,
                      title: 'Zwischenzeitlich geändert',
                      message:
                          'Diese Aufgabe wurde in Version '
                          '${_conflict!.actualVersion} geändert, während du '
                          'Version $_expectedVersion bearbeitet hast. Deine '
                          'Eingaben sind erhalten.',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          key: const Key('task-dialog-conflict-reload'),
                          onPressed: _reseedFromConflict,
                          child: const Text('Neu laden'),
                        ),
                        FilledButton(
                          key: const Key('task-dialog-conflict-retry'),
                          onPressed: () {
                            setState(() {
                              _expectedVersion = _conflict!.actualVersion;
                              _conflict = null;
                            });
                            _submit();
                          },
                          child: const Text('Erneut speichern'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_bannerError != null) ...[
                    NxNotice(
                      key: const Key('task-dialog-error'),
                      kind: NxNoticeKind.error,
                      message: _bannerError!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    key: const Key('task-form-title'),
                    controller: _titleCtrl,
                    maxLength: 300,
                    decoration: InputDecoration(
                      labelText: 'Titel',
                      errorText: _fieldErrors['title'],
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Pflichtfeld'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('task-form-description'),
                    controller: _descriptionCtrl,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 10000,
                    decoration: InputDecoration(
                      labelText: 'Beschreibung',
                      errorText: _fieldErrors['description'],
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    key: const Key('task-form-category'),
                    value: _categoryWire,
                    decoration: InputDecoration(
                      labelText: 'Kategorie',
                      errorText: _fieldErrors['category'],
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('—'),
                      ),
                      for (final category in TaskCategory.values)
                        DropdownMenuItem<String?>(
                          value: category.wireName,
                          child: Text(taskCategoryLabel(category)),
                        ),
                      // An unknown server value stays selectable as itself:
                      // displayed and preserved, never silently rewritten
                      // (§7.5).
                      if (unknownRaw != null)
                        DropdownMenuItem<String?>(
                          value: unknownRaw,
                          child: Text(unknownRaw),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _categoryWire = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<TaskPriority>(
                    key: const Key('task-form-priority'),
                    value: _priority,
                    decoration: InputDecoration(
                      labelText: 'Priorität',
                      errorText: _fieldErrors['priority'],
                    ),
                    items: [
                      for (final priority in TaskPriority.values)
                        DropdownMenuItem<TaskPriority>(
                          value: priority,
                          child: Text(taskPriorityLabel(priority)),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _priority = value);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Zuständig',
                      errorText: _fieldErrors['assigned_to'],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          switch (_assign) {
                            _AssignSelection.self => 'Mir zugewiesen',
                            _AssignSelection.none => '—',
                            _AssignSelection.unchanged =>
                              widget.task?.assignedTo == null
                                  ? '—'
                                  : (widget.task!.assignedTo == actorId
                                        ? 'Mir zugewiesen'
                                        // Never the raw uuid (§7): the name
                                        // resolution is TASK-QUERY-01.
                                        : 'Zugewiesen'),
                          },
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              key: const Key('task-form-assign-self'),
                              onPressed: _submitting || actorId == null
                                  ? null
                                  : () => setState(
                                      () => _assign = _AssignSelection.self,
                                    ),
                              child: const Text('Mir zuweisen'),
                            ),
                            TextButton(
                              key: const Key('task-form-unassign'),
                              onPressed: _submitting
                                  ? null
                                  : () => setState(
                                      () => _assign = _AssignSelection.none,
                                    ),
                              child: const Text('Zuweisung entfernen'),
                            ),
                          ],
                        ),
                        Text(
                          'Zuweisung an andere Personen ist noch nicht '
                          'verfügbar.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Fälligkeit',
                      errorText: _fieldErrors['due_at'],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _dueAt == null ? '—' : formatTaskDate(_dueAt!),
                          ),
                        ),
                        TextButton(
                          key: const Key('task-form-due-pick'),
                          onPressed: _submitting ? null : _pickDueDate,
                          child: const Text('Wählen'),
                        ),
                        if (_dueAt != null)
                          TextButton(
                            key: const Key('task-form-due-clear'),
                            onPressed: _submitting
                                ? null
                                : () => setState(() => _dueAt = null),
                            child: const Text('Löschen'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Kontext',
                      errorText:
                          _fieldErrors['entity_type'] ??
                          _fieldErrors['entity_id'],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_entity != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: EntityRefChip(entity: _entity!),
                          )
                        else
                          const Text('Kein Kontext'),
                        Text(
                          isEdit
                              ? 'Der Kontext wird beim Anlegen gesetzt und '
                                    'ist danach unveränderlich.'
                              : (_entity != null
                                    ? 'Vorbelegt durch die aufrufende Fläche.'
                                    : 'Eine freie Kontextauswahl benötigt '
                                          'die Namensauflösung aus '
                                          'TASK-QUERY-01; aus Objekt- und '
                                          'Vorgangsflächen wird der Kontext '
                                          'vorbelegt. Dokumente und '
                                          'Bewertungsfälle folgen mit '
                                          'TASK-ENTITY-REGISTRY-01.'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('task-form-cancel'),
            onPressed: _submitting ? null : _close,
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('task-form-submit'),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isEdit ? 'Speichern' : 'Anlegen'),
          ),
        ],
      ),
    );
  }
}

/// §6.3: a transition into `blocked` demands an individual reason (1–2000),
/// sent as the RPC's `reason`.
Future<String?> showTaskBlockReasonDialog(BuildContext context) {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('task-block-dialog'),
      title: const Text('Aufgabe blockieren'),
      content: Form(
        key: formKey,
        child: TextFormField(
          key: const Key('task-block-reason'),
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: 'Grund',
            helperText: 'Warum ist diese Aufgabe blockiert?',
          ),
          validator: (value) =>
              (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('task-block-confirm'),
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(controller.text.trim());
            }
          },
          child: const Text('Blockieren'),
        ),
      ],
    ),
  ).whenComplete(() {
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  });
}

/// §6.5: archiving replaces deletion, is terminal, and names both the task
/// and — for generated tasks — the AGG-019 consequence before confirming.
Future<bool?> showTaskArchiveDialog(BuildContext context, {
  required TaskDto task,
}) {
  final theme = Theme.of(context);
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('task-archive-dialog'),
      title: const Text('Aufgabe archivieren'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '„${task.title}“ wird archiviert. Archivierte Aufgaben können '
            'nicht wieder geöffnet werden.',
          ),
          if (task.isGenerated) ...[
            const SizedBox(height: 8),
            Text(
              key: const Key('task-archive-generated-hint'),
              'Diese Aufgabe stammt aus einer Vorlage. Nach dem Archivieren '
              'wird sie für diesen Zeitraum nicht erneut erzeugt.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('task-archive-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Archivieren'),
        ),
      ],
    ),
  );
}
