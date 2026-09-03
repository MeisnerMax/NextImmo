import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/widgets/task_dialogs.dart';

TaskDto _task({
  String? category,
  DateTime? dueAt,
  int version = 3,
}) {
  return TaskDto(
    id: 'task-a',
    workspaceId: 'workspace-a',
    title: 'Heizung prüfen',
    priority: TaskPriority.normal,
    status: TaskStatus.open,
    createdAt: DateTime.utc(2026, 8, 1),
    updatedAt: DateTime.utc(2026, 8, 1),
    createdBy: 'user-1',
    updatedBy: 'user-1',
    version: version,
    category: category,
    dueAt: dueAt,
    description: 'Wartung',
  );
}

Future<void> _pumpOpener(
  WidgetTester tester,
  Future<void> Function(BuildContext context) open,
) async {
  // The form dialog is taller than the default 600px test surface; a tap on
  // an off-screen control would silently miss.
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open-dialog'),
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-dialog')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create validates the title and never submits without one', (
    tester,
  ) async {
    var submits = 0;
    await _pumpOpener(
      tester,
      (context) => showTaskCreateDialog(
        context,
        onSubmit: (draft, mutationId) async {
          submits++;
          return null;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('task-form-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Pflichtfeld'), findsOneWidget);
    expect(submits, 0);
  });

  testWidgets('one intent, one mutationId — across failing retries, renewed '
      'on reopen (§12)', (tester) async {
    final submitted = <String>[];
    var failNext = true;
    await _pumpOpener(
      tester,
      (context) => showTaskCreateDialog(
        context,
        onSubmit: (draft, mutationId) async {
          submitted.add(mutationId);
          if (failNext) {
            failNext = false;
            return const PlatformRepositoryFailure<TaskDto>(
              kind: PlatformRepositoryFailureKind.infrastructureFailure,
              message: 'Supabase platform command failed.',
            );
          }
          return null;
        },
      ),
    );

    await tester.enterText(
      find.byKey(const Key('task-form-title')),
      'Neue Aufgabe',
    );
    await tester.tap(find.byKey(const Key('task-form-submit')));
    await tester.pumpAndSettle();
    // The failure keeps the dialog open with the §12 copy for infrastructure.
    expect(find.byKey(const Key('task-dialog-error')), findsOneWidget);
    expect(
      find.text('Aktion konnte nicht ausgeführt werden.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('task-form-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-form-dialog')), findsNothing);

    expect(submitted, hasLength(2));
    expect(submitted[0], submitted[1]);

    // Cancel + reopen is a new intent with a new id.
    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-form-title')),
      'Zweite Aufgabe',
    );
    await tester.tap(find.byKey(const Key('task-form-submit')));
    await tester.pumpAndSettle();

    expect(submitted, hasLength(3));
    expect(submitted[2], isNot(submitted[0]));
  });

  testWidgets('create submits the trimmed draft with the §12 defaults', (
    tester,
  ) async {
    TaskDraft? captured;
    await _pumpOpener(
      tester,
      (context) => showTaskCreateDialog(
        context,
        presetEntity: const PlatformEntityRef(
          type: PlatformEntityType.property,
          id: 'property-1',
        ),
        onSubmit: (draft, mutationId) async {
          captured = draft;
          return null;
        },
      ),
    );

    await tester.enterText(
      find.byKey(const Key('task-form-title')),
      '  Heizung prüfen  ',
    );
    await tester.tap(find.byKey(const Key('task-form-submit')));
    await tester.pumpAndSettle();

    expect(captured!.title, 'Heizung prüfen');
    expect(captured!.category, 'general');
    expect(captured!.priority, TaskPriority.normal);
    expect(captured!.entity?.id, 'property-1');
    expect(captured!.assignedTo, isNull);
  });

  testWidgets('an untouched unknown category survives the edit cycle (§7.5)', (
    tester,
  ) async {
    TaskUpdateDto? captured;
    await _pumpOpener(
      tester,
      (context) => showTaskEditDialog(
        context,
        task: _task(category: 'sonderpruefung'),
        onSubmit: (changes, expectedVersion, mutationId) async {
          captured = changes;
          return null;
        },
      ),
    );

    // The raw value is displayed as itself, not rewritten to a known label.
    expect(find.text('sonderpruefung'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('task-form-title')),
      'Heizung prüfen (aktualisiert)',
    );
    await tester.tap(find.byKey(const Key('task-form-submit')));
    await tester.pumpAndSettle();

    expect(captured!.title, 'Heizung prüfen (aktualisiert)');
    // Untouched fields stay absent — including the unknown category, which a
    // fromWire fallback would have silently rewritten to `general`.
    expect(captured!.category.isPresent, isFalse);
    expect(captured!.description.isPresent, isFalse);
    expect(captured!.dueAt.isPresent, isFalse);
    expect(captured!.assignedTo.isPresent, isFalse);
    expect(captured!.priority, isNull);
  });

  testWidgets('removing the due date sends an explicit clear', (tester) async {
    TaskUpdateDto? captured;
    await _pumpOpener(
      tester,
      (context) => showTaskEditDialog(
        context,
        task: _task(dueAt: DateTime(2026, 9, 10)),
        onSubmit: (changes, expectedVersion, mutationId) async {
          captured = changes;
          return null;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('task-form-due-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-form-submit')));
    await tester.pumpAndSettle();

    expect(captured!.dueAt.isPresent, isTrue);
    expect(captured!.dueAt.value, isNull);
  });

  testWidgets('a version conflict keeps input, offers reload and retry '
      '(Foundation §10)', (tester) async {
    final versions = <int>[];
    var conflictOnce = true;
    await _pumpOpener(
      tester,
      (context) => showTaskEditDialog(
        context,
        task: _task(version: 3),
        onSubmit: (changes, expectedVersion, mutationId) async {
          versions.add(expectedVersion);
          if (conflictOnce) {
            conflictOnce = false;
            return PlatformRepositoryFailure<TaskDto>(
              kind: PlatformRepositoryFailureKind.versionConflict,
              message: 'Task version is stale',
              versionConflict: PlatformVersionConflict(
                expectedVersion: expectedVersion,
                actualVersion: 7,
                currentTask: _task(version: 7),
              ),
            );
          }
          return null;
        },
      ),
    );

    await tester.enterText(
      find.byKey(const Key('task-form-title')),
      'Mein neuer Titel',
    );
    await tester.tap(find.byKey(const Key('task-form-submit')));
    await tester.pumpAndSettle();

    // §10: the conflict banner appears, the input survives.
    expect(find.byKey(const Key('task-detail-conflict')), findsOneWidget);
    expect(find.text('Mein neuer Titel'), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-dialog-conflict-retry')));
    await tester.pumpAndSettle();

    expect(versions, <int>[3, 7]);
    expect(find.byKey(const Key('task-form-dialog')), findsNothing);
  });

  testWidgets('validation failures with a named field keep the dialog open', (
    tester,
  ) async {
    await _pumpOpener(
      tester,
      (context) => showTaskCreateDialog(
        context,
        onSubmit: (draft, mutationId) async =>
            const PlatformRepositoryFailure<TaskDto>(
              kind: PlatformRepositoryFailureKind.validationFailed,
              message: 'Title is required',
              validationFields: <String>['title'],
            ),
      ),
    );

    await tester.enterText(find.byKey(const Key('task-form-title')), 'x');
    await tester.tap(find.byKey(const Key('task-form-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-form-dialog')), findsOneWidget);
    expect(find.text('Title is required'), findsOneWidget);
  });

  testWidgets('the block dialog demands a reason', (tester) async {
    String? reason;
    await _pumpOpener(tester, (context) async {
      reason = await showTaskBlockReasonDialog(context);
    });

    await tester.tap(find.byKey(const Key('task-block-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Pflichtfeld'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('task-block-reason')),
      '  Wartet auf Ersatzteil  ',
    );
    await tester.tap(find.byKey(const Key('task-block-confirm')));
    await tester.pumpAndSettle();

    expect(reason, 'Wartet auf Ersatzteil');
  });

  testWidgets('the archive dialog names the AGG-019 consequence only for '
      'generated tasks (§6.5)', (tester) async {
    await _pumpOpener(tester, (context) async {
      await showTaskArchiveDialog(context, task: _task());
    });
    expect(find.byKey(const Key('task-archive-dialog')), findsOneWidget);
    expect(
      find.byKey(const Key('task-archive-generated-hint')),
      findsNothing,
    );
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    final generated = TaskDto(
      id: 'task-b',
      workspaceId: 'workspace-a',
      title: 'Heizungswartung',
      priority: TaskPriority.normal,
      status: TaskStatus.open,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      createdBy: 'user-1',
      updatedBy: 'user-1',
      version: 1,
      generatedKey: 'heating:2026',
    );
    await tester.tap(find.byKey(const Key('open-dialog')));
    // Reopen with the generated task via a fresh pump.
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    await _pumpOpener(tester, (context) async {
      await showTaskArchiveDialog(context, task: generated);
    });
    expect(
      find.byKey(const Key('task-archive-generated-hint')),
      findsOneWidget,
    );
  });
}
