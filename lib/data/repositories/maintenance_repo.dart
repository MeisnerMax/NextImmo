import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/maintenance.dart';

class MaintenanceRepo {
  const MaintenanceRepo(this._db);

  final Database _db;

  Future<List<MaintenanceTicketRecord>> listTickets({
    String? assetPropertyId,
    String? status,
    String? priority,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (assetPropertyId != null) {
      where.add('asset_property_id = ?');
      args.add(assetPropertyId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    if (priority != null) {
      where.add('priority = ?');
      args.add(priority);
    }

    final rows = await _db.query(
      'maintenance_tickets',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'reported_at DESC',
    );
    return rows.map(MaintenanceTicketRecord.fromMap).toList();
  }

  Future<List<MaintenanceWorkflowRecord>> listWorkflowTickets({
    String? assetPropertyId,
    String? status,
    String? priority,
  }) async {
    final tickets = await listTickets(
      assetPropertyId: assetPropertyId,
      status: status,
      priority: priority,
    );
    final records = <MaintenanceWorkflowRecord>[];
    for (final ticket in tickets) {
      records.add(await _buildWorkflowRecord(ticket));
    }
    return records;
  }

  Future<MaintenanceTicketRecord> createTicket({
    required String assetPropertyId,
    String? unitId,
    required String title,
    String? description,
    String status = 'open',
    String priority = 'normal',
    int? dueAt,
    double? costEstimate,
    String? vendorName,
    String? documentId,
    bool createTask = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ticket = MaintenanceTicketRecord(
      id: const Uuid().v4(),
      assetPropertyId: assetPropertyId,
      unitId: unitId,
      title: title,
      description: description,
      status: status,
      priority: priority,
      reportedAt: now,
      dueAt: dueAt,
      resolvedAt: null,
      costEstimate: costEstimate,
      costActual: null,
      vendorName: vendorName,
      documentId: documentId,
      createdAt: now,
      updatedAt: now,
    );

    await _db.transaction((txn) async {
      await txn.insert(
        'maintenance_tickets',
        ticket.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      if (createTask) {
        await txn.insert('tasks', <String, Object?>{
          'id': const Uuid().v4(),
          'entity_type': 'maintenance_ticket',
          'entity_id': ticket.id,
          'title': 'Maintenance: $title',
          'status': 'todo',
          'priority': priority == 'urgent' ? 'high' : priority,
          'due_at': dueAt,
          'created_at': now,
          'updated_at': now,
          'created_by': null,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }
    });

    return ticket;
  }

  Future<void> updateTicket(MaintenanceTicketRecord ticket) async {
    await _db.update(
      'maintenance_tickets',
      ticket.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[ticket.id],
    );
  }

  Future<void> deleteTicket(String id) async {
    await _db.delete(
      'maintenance_tickets',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> createDueNotifications({required int dueSoonDays}) async {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final soonLimit =
        now.add(Duration(days: dueSoonDays)).millisecondsSinceEpoch;

    final openRows = await _db.rawQuery('''
      SELECT * FROM maintenance_tickets
      WHERE status IN ('open', 'in_progress', 'waiting')
        AND due_at IS NOT NULL
      ''');

    var created = 0;
    for (final row in openRows) {
      final ticket = MaintenanceTicketRecord.fromMap(row);
      final dueAt = ticket.dueAt;
      if (dueAt == null) {
        continue;
      }

      String? kind;
      String? message;
      if (dueAt < nowMs) {
        kind = 'maintenance_overdue';
        message = 'Maintenance ticket overdue: ${ticket.title}';
      } else if (dueAt <= soonLimit) {
        kind = 'maintenance_due_soon';
        message = 'Maintenance ticket due soon: ${ticket.title}';
      }
      if (kind == null || message == null) {
        continue;
      }

      final existing = await _db.rawQuery(
        'SELECT COUNT(*) FROM notifications WHERE entity_type = ? AND entity_id = ? AND kind = ? AND read_at IS NULL',
        <Object?>['maintenance_ticket', ticket.id, kind],
      );
      final count = _firstInt(existing);
      if (count > 0) {
        continue;
      }

      await _db.insert('notifications', <String, Object?>{
        'id': const Uuid().v4(),
        'entity_type': 'maintenance_ticket',
        'entity_id': ticket.id,
        'kind': kind,
        'message': message,
        'due_at': dueAt,
        'read_at': null,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      created += 1;
    }

    return created;
  }

  int _firstInt(List<Map<String, Object?>> rows) {
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

  Future<MaintenanceWorkflowRecord> _buildWorkflowRecord(
    MaintenanceTicketRecord ticket,
  ) async {
    final propertyRows = await _db.query(
      'properties',
      columns: const <String>['name'],
      where: 'id = ?',
      whereArgs: <Object?>[ticket.assetPropertyId],
      limit: 1,
    );
    final documentRows =
        ticket.documentId == null
            ? const <Map<String, Object?>>[]
            : await _db.query(
              'documents',
              columns: const <String>['file_name'],
              where: 'id = ?',
              whereArgs: <Object?>[ticket.documentId],
              limit: 1,
            );
    final linkedTasks = await _db.rawQuery(
      'SELECT COUNT(*) FROM tasks WHERE entity_type = ? AND entity_id = ?',
      <Object?>['maintenance_ticket', ticket.id],
    );
    return MaintenanceWorkflowRecord(
      ticket: ticket,
      propertyName:
          propertyRows.isEmpty ? null : propertyRows.first['name'] as String?,
      documentName:
          documentRows.isEmpty
              ? null
              : documentRows.first['file_name'] as String?,
      linkedTaskCount: _firstInt(linkedTasks),
    );
  }
}
