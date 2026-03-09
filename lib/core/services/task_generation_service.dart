import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../models/task.dart';
import '../../data/repositories/tasks_repo.dart';

class TaskGenerationSummary {
  const TaskGenerationSummary({
    required this.generatedTasks,
    required this.generatedNotifications,
  });

  final int generatedTasks;
  final int generatedNotifications;
}

class TaskGenerationService {
  const TaskGenerationService(this._db, this._tasksRepo);

  final Database _db;
  final TasksRepo _tasksRepo;

  Future<TaskGenerationSummary> generate({
    required int now,
    required int dueSoonDays,
    required bool enableNotifications,
  }) async {
    var generatedTasks = 0;
    var generatedNotifications = 0;
    final templates = await _tasksRepo.listTemplates();

    for (final template in templates) {
      if (template.recurrenceRule == 'none') {
        continue;
      }
      if (!_isDueForInterval(template, now)) {
        continue;
      }
      final periodKey = _periodKeyForRule(template.recurrenceRule, now);
      if (periodKey == null) {
        continue;
      }

      final entityRefs = await _entityRefs(template.entityType);
      for (final entityRef in entityRefs) {
        final generatedKey =
            '${template.id}:${entityRef.entityType}:${entityRef.entityId}:$periodKey';
        if (await _tasksRepo.hasGeneratedKey(generatedKey)) {
          continue;
        }

        final periodStart = _periodStartForRule(template.recurrenceRule, now);
        final dueAt =
            template.defaultDueDaysOffset == null
                ? null
                : periodStart
                    .add(Duration(days: template.defaultDueDaysOffset!))
                    .millisecondsSinceEpoch;

        final task = await _tasksRepo.createTask(
          entityType: entityRef.entityType,
          entityId: entityRef.entityId,
          title: template.defaultTitle,
          priority: template.defaultPriority,
          dueAt: dueAt,
          status: 'todo',
        );

        final checklist = await _tasksRepo.listTemplateChecklistItems(
          template.id,
        );
        for (final item in checklist) {
          await _tasksRepo.addChecklistItem(
            taskId: task.id,
            text: item.text,
            position: item.position,
          );
        }

        await _tasksRepo.addGeneratedInstance(
          TaskGeneratedInstanceRecord(
            id: const Uuid().v4(),
            generatedKey: generatedKey,
            templateId: template.id,
            entityType: entityRef.entityType,
            entityId: entityRef.entityId,
            periodKey: periodKey,
            createdAt: now,
          ),
        );
        generatedTasks++;

        if (enableNotifications &&
            dueAt != null &&
            dueAt <=
                DateTime.fromMillisecondsSinceEpoch(
                  now,
                ).add(Duration(days: dueSoonDays)).millisecondsSinceEpoch) {
          final created = await _createNotificationIfMissing(
            kind: 'task_due_soon',
            entityId: task.id,
            message: 'Task due soon: ${task.title}',
            dueAt: dueAt,
            now: now,
          );
          if (created) {
            generatedNotifications++;
          }
        }
      }
    }

    if (enableNotifications) {
      final overdueTasks = await _db.query(
        'tasks',
        where: 'status != ? AND due_at IS NOT NULL AND due_at < ?',
        whereArgs: <Object?>['done', now],
      );
      for (final row in overdueTasks) {
        final task = TaskRecord.fromMap(row);
        final created = await _createNotificationIfMissing(
          kind: 'task_overdue',
          entityId: task.id,
          message: 'Task overdue: ${task.title}',
          dueAt: task.dueAt,
          now: now,
        );
        if (created) {
          generatedNotifications++;
        }
      }
    }

    return TaskGenerationSummary(
      generatedTasks: generatedTasks,
      generatedNotifications: generatedNotifications,
    );
  }

  Future<bool> _createNotificationIfMissing({
    required String kind,
    required String entityId,
    required String message,
    required int? dueAt,
    required int now,
  }) async {
    final existing = _firstIntValue(
      await _db.rawQuery(
        'SELECT COUNT(*) FROM notifications WHERE entity_type = ? AND entity_id = ? AND kind = ?',
        <Object?>['task', entityId, kind],
      ),
    );
    if (existing > 0) {
      return false;
    }
    await _db.insert('notifications', <String, Object?>{
      'id': const Uuid().v4(),
      'entity_type': 'task',
      'entity_id': entityId,
      'kind': kind,
      'message': message,
      'due_at': dueAt,
      'read_at': null,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
    return true;
  }

  Future<List<_EntityRef>> _entityRefs(String entityType) async {
    switch (entityType) {
      case 'none':
        return const <_EntityRef>[
          _EntityRef(entityType: 'none', entityId: 'global'),
        ];
      case 'property':
      case 'asset_property':
        final properties = await _db.query('properties', columns: const ['id']);
        return properties
            .map(
              (row) => _EntityRef(
                entityType: entityType,
                entityId: row['id']! as String,
              ),
            )
            .toList();
      case 'portfolio':
        final portfolios = await _db.query('portfolios', columns: const ['id']);
        return portfolios
            .map(
              (row) => _EntityRef(
                entityType: entityType,
                entityId: row['id']! as String,
              ),
            )
            .toList();
      default:
        return const <_EntityRef>[
          _EntityRef(entityType: 'none', entityId: 'global'),
        ];
    }
  }

  String? _periodKeyForRule(String rule, int now) {
    final date = DateTime.fromMillisecondsSinceEpoch(now);
    switch (rule) {
      case 'daily':
        return _formatDate(date);
      case 'weekly':
        final week = ((date.day - 1) ~/ 7) + 1;
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-W$week';
      case 'monthly':
        return '${date.year}-${date.month.toString().padLeft(2, '0')}';
      case 'quarterly':
        final quarter = ((date.month - 1) ~/ 3) + 1;
        return '${date.year}-Q$quarter';
      case 'yearly':
        return '${date.year}';
      default:
        return null;
    }
  }

  DateTime _periodStartForRule(String rule, int now) {
    final date = DateTime.fromMillisecondsSinceEpoch(now);
    switch (rule) {
      case 'daily':
        return DateTime(date.year, date.month, date.day);
      case 'weekly':
        final weekday = date.weekday;
        return DateTime(
          date.year,
          date.month,
          date.day,
        ).subtract(Duration(days: weekday - 1));
      case 'monthly':
        return DateTime(date.year, date.month, 1);
      case 'quarterly':
        final quarterStartMonth = (((date.month - 1) ~/ 3) * 3) + 1;
        return DateTime(date.year, quarterStartMonth, 1);
      case 'yearly':
        return DateTime(date.year, 1, 1);
      default:
        return DateTime(date.year, date.month, date.day);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool _isDueForInterval(TaskTemplateRecord template, int now) {
    final interval =
        template.recurrenceInterval <= 0 ? 1 : template.recurrenceInterval;
    if (interval == 1) {
      return true;
    }
    final nowDate = DateTime.fromMillisecondsSinceEpoch(now);
    final baseDate = DateTime.fromMillisecondsSinceEpoch(template.createdAt);
    switch (template.recurrenceRule) {
      case 'daily':
        return nowDate.difference(baseDate).inDays % interval == 0;
      case 'weekly':
        return (nowDate.difference(baseDate).inDays ~/ 7) % interval == 0;
      case 'monthly':
        final months =
            (nowDate.year - baseDate.year) * 12 +
            (nowDate.month - baseDate.month);
        return months % interval == 0;
      case 'quarterly':
        final months =
            (nowDate.year - baseDate.year) * 12 +
            (nowDate.month - baseDate.month);
        final quarters = months ~/ 3;
        return quarters % interval == 0;
      case 'yearly':
        return (nowDate.year - baseDate.year) % interval == 0;
      default:
        return true;
    }
  }

  int _firstIntValue(List<Map<String, Object?>> rows) {
    if (rows.isEmpty || rows.first.isEmpty) {
      return 0;
    }
    final value = rows.first.values.first;
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString()) ?? 0;
  }
}

class _EntityRef {
  const _EntityRef({required this.entityType, required this.entityId});

  final String entityType;
  final String entityId;
}
