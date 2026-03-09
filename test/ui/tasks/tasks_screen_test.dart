import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/task.dart';
import 'package:neximmo_app/data/repositories/tasks_repo.dart';
import 'package:neximmo_app/ui/screens/tasks/tasks_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('renders list template with filters and detail panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(_FakeTasksRepo()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: TasksScreen()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Context'), findsOneWidget);
    expect(find.text('Review lease rollover'), findsOneWidget);

    await tester.tap(find.text('Review lease rollover'));
    await tester.pumpAndSettle();

    expect(find.text('Add Checklist Item'), findsOneWidget);
    expect(find.text('Select a task'), findsNothing);
  });
}

class _FakeTasksRepo extends TasksRepo {
  _FakeTasksRepo() : super(_NoopDatabase());

  @override
  Future<List<TaskRecord>> listTasks({
    String? status,
    int? dueFrom,
    int? dueTo,
    String? entityType,
    String? entityId,
  }) async {
    return const <TaskRecord>[
      TaskRecord(
        id: 't1',
        entityType: 'property',
        entityId: 'p1',
        title: 'Review lease rollover',
        status: 'todo',
        priority: 'high',
        dueAt: 1735603200000,
        createdAt: 1,
        updatedAt: 1,
        createdBy: null,
      ),
    ];
  }

  @override
  Future<List<TaskChecklistItemRecord>> listChecklistItems(
    String taskId,
  ) async {
    return const <TaskChecklistItemRecord>[
      TaskChecklistItemRecord(
        id: 'c1',
        taskId: 't1',
        text: 'Check draft lease',
        position: 0,
        done: false,
      ),
    ];
  }
}

class _NoopDatabase extends Fake implements Database {}
