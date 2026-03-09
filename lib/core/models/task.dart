class TaskRecord {
  const TaskRecord({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.status,
    required this.priority,
    required this.dueAt,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  final String id;
  final String entityType;
  final String? entityId;
  final String title;
  final String status;
  final String priority;
  final int? dueAt;
  final int createdAt;
  final int updatedAt;
  final String? createdBy;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'title': title,
      'status': status,
      'priority': priority,
      'due_at': dueAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'created_by': createdBy,
    };
  }

  factory TaskRecord.fromMap(Map<String, Object?> map) {
    return TaskRecord(
      id: map['id']! as String,
      entityType: map['entity_type']! as String,
      entityId: map['entity_id'] as String?,
      title: map['title']! as String,
      status: map['status']! as String,
      priority: map['priority']! as String,
      dueAt: (map['due_at'] as num?)?.toInt(),
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
      createdBy: map['created_by'] as String?,
    );
  }
}

class TaskChecklistItemRecord {
  const TaskChecklistItemRecord({
    required this.id,
    required this.taskId,
    required this.text,
    required this.position,
    required this.done,
  });

  final String id;
  final String taskId;
  final String text;
  final int position;
  final bool done;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'task_id': taskId,
      'text': text,
      'position': position,
      'done': done ? 1 : 0,
    };
  }

  factory TaskChecklistItemRecord.fromMap(Map<String, Object?> map) {
    return TaskChecklistItemRecord(
      id: map['id']! as String,
      taskId: map['task_id']! as String,
      text: map['text']! as String,
      position: (map['position']! as num).toInt(),
      done: ((map['done'] as num?) ?? 0) == 1,
    );
  }
}

class TaskTemplateRecord {
  const TaskTemplateRecord({
    required this.id,
    required this.name,
    required this.entityType,
    required this.defaultTitle,
    required this.defaultPriority,
    required this.defaultDueDaysOffset,
    required this.recurrenceRule,
    required this.recurrenceInterval,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String entityType;
  final String defaultTitle;
  final String defaultPriority;
  final int? defaultDueDaysOffset;
  final String recurrenceRule;
  final int recurrenceInterval;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'entity_type': entityType,
      'default_title': defaultTitle,
      'default_priority': defaultPriority,
      'default_due_days_offset': defaultDueDaysOffset,
      'recurrence_rule': recurrenceRule,
      'recurrence_interval': recurrenceInterval,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory TaskTemplateRecord.fromMap(Map<String, Object?> map) {
    return TaskTemplateRecord(
      id: map['id']! as String,
      name: map['name']! as String,
      entityType: map['entity_type']! as String,
      defaultTitle: map['default_title']! as String,
      defaultPriority: map['default_priority']! as String,
      defaultDueDaysOffset: (map['default_due_days_offset'] as num?)?.toInt(),
      recurrenceRule: map['recurrence_rule']! as String,
      recurrenceInterval: (map['recurrence_interval']! as num).toInt(),
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class TaskTemplateChecklistItemRecord {
  const TaskTemplateChecklistItemRecord({
    required this.id,
    required this.templateId,
    required this.text,
    required this.position,
  });

  final String id;
  final String templateId;
  final String text;
  final int position;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'template_id': templateId,
      'text': text,
      'position': position,
    };
  }

  factory TaskTemplateChecklistItemRecord.fromMap(Map<String, Object?> map) {
    return TaskTemplateChecklistItemRecord(
      id: map['id']! as String,
      templateId: map['template_id']! as String,
      text: map['text']! as String,
      position: (map['position']! as num).toInt(),
    );
  }
}

class TaskGeneratedInstanceRecord {
  const TaskGeneratedInstanceRecord({
    required this.id,
    required this.generatedKey,
    required this.templateId,
    required this.entityType,
    required this.entityId,
    required this.periodKey,
    required this.createdAt,
  });

  final String id;
  final String generatedKey;
  final String templateId;
  final String entityType;
  final String entityId;
  final String periodKey;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'generated_key': generatedKey,
      'template_id': templateId,
      'entity_type': entityType,
      'entity_id': entityId,
      'period_key': periodKey,
      'created_at': createdAt,
    };
  }

  factory TaskGeneratedInstanceRecord.fromMap(Map<String, Object?> map) {
    return TaskGeneratedInstanceRecord(
      id: map['id']! as String,
      generatedKey: map['generated_key']! as String,
      templateId: map['template_id']! as String,
      entityType: map['entity_type']! as String,
      entityId: map['entity_id']! as String,
      periodKey: map['period_key']! as String,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}
