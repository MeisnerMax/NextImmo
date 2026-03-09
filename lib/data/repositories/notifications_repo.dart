import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/notification.dart';
import 'search_repo.dart';

class NotificationsRepository {
  const NotificationsRepository(this._db, {SearchRepo? searchRepo})
    : _searchRepo = searchRepo;

  final Database _db;
  final SearchRepo? _searchRepo;

  Future<List<NotificationRecord>> listNotifications({
    String? entityType,
    String? entityId,
    bool unreadOnly = false,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];

    if (entityType != null) {
      conditions.add('entity_type = ?');
      args.add(entityType);
    }
    if (entityId != null) {
      conditions.add('entity_id = ?');
      args.add(entityId);
    }
    if (unreadOnly) {
      conditions.add('read_at IS NULL');
    }

    final rows = await _db.query(
      'notifications',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(NotificationRecord.fromMap).toList();
  }

  Future<NotificationRecord> createNotification({
    required String entityType,
    required String entityId,
    required String kind,
    required String message,
    int? dueAt,
  }) async {
    final record = NotificationRecord(
      id: const Uuid().v4(),
      entityType: entityType,
      entityId: entityId,
      kind: kind,
      message: message,
      dueAt: dueAt,
      readAt: null,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insert(
      'notifications',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(
        searchRepo.buildNotificationRecord(record),
      );
    }
    return record;
  }

  Future<void> markRead(String id) async {
    await _db.update(
      'notifications',
      <String, Object?>{'read_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> markAllRead({String? entityType, String? entityId}) async {
    final conditions = <String>['read_at IS NULL'];
    final args = <Object?>[];
    if (entityType != null) {
      conditions.add('entity_type = ?');
      args.add(entityType);
    }
    if (entityId != null) {
      conditions.add('entity_id = ?');
      args.add(entityId);
    }

    await _db.update(
      'notifications',
      <String, Object?>{'read_at': DateTime.now().millisecondsSinceEpoch},
      where: conditions.join(' AND '),
      whereArgs: args,
    );
  }
}
