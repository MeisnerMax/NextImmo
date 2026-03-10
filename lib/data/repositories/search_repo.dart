import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/models/documents.dart';
import '../../core/models/ledger.dart';
import '../../core/models/note.dart';
import '../../core/models/notification.dart';
import '../../core/models/portfolio.dart';
import '../../core/models/property.dart';
import '../../core/models/scenario.dart';
import '../../core/models/search.dart';
import '../../core/models/task.dart';

class SearchRepo {
  SearchRepo(this._db);

  final Database _db;
  bool _indexInitialized = false;

  Future<List<SearchIndexRecord>> search({
    required String query,
    List<String>? entityTypes,
    int limit = 30,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return const <SearchIndexRecord>[];
    }
    final where = <String>[
      '(LOWER(title) LIKE ? OR LOWER(COALESCE(subtitle, \'\')) LIKE ? OR LOWER(COALESCE(body, \'\')) LIKE ?)',
    ];
    final args = <Object?>['%$q%', '%$q%', '%$q%'];
    if (entityTypes != null && entityTypes.isNotEmpty) {
      final placeholders = List<String>.filled(
        entityTypes.length,
        '?',
      ).join(',');
      where.add('entity_type IN ($placeholders)');
      args.addAll(entityTypes);
    }
    final rows = await _db.query(
      'search_index',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows.map(SearchIndexRecord.fromMap).toList();
  }

  Future<void> upsertIndexEntry(SearchIndexRecord record) async {
    _indexInitialized = true;
    await _db.insert(
      'search_index',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteIndexEntryByEntity({
    required String entityType,
    required String entityId,
  }) async {
    _indexInitialized = true;
    await _db.delete(
      'search_index',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[entityType, entityId],
    );
  }

  Future<void> ensureIndexInitialized() async {
    if (_indexInitialized) {
      return;
    }
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM search_index',
    );
    final count = ((rows.first['count'] as num?) ?? 0).toInt();
    if (count == 0) {
      await rebuildIndex();
      return;
    }
    _indexInitialized = true;
  }

  Future<void> rebuildIndex() async {
    await _db.transaction((txn) async {
      await txn.delete('search_index');
      await _insertAll(
        txn,
        (await txn.query(
          'properties',
          where: 'archived = 0',
        )).map(PropertyRecord.fromMap).map(buildPropertyRecord),
      );
      await _insertAll(
        txn,
        (await txn.query(
          'scenarios',
        )).map(ScenarioRecord.fromMap).map(buildScenarioRecord),
      );
      await _insertAll(
        txn,
        (await txn.query(
          'portfolios',
        )).map(PortfolioRecord.fromMap).map(buildPortfolioRecord),
      );
      await _insertAll(
        txn,
        (await txn.query('notes')).map(NoteRecord.fromMap).map(buildNoteRecord),
      );
      await _insertAll(
        txn,
        (await txn.query(
          'notifications',
        )).map(NotificationRecord.fromMap).map(buildNotificationRecord),
      );
      await _insertAll(
        txn,
        (await txn.query(
          'ledger_entries',
        )).map(LedgerEntryRecord.fromMap).map(buildLedgerEntryRecord),
      );
      await _insertAll(
        txn,
        (await txn.query('tasks')).map(TaskRecord.fromMap).map(buildTaskRecord),
      );
      await _insertAll(
        txn,
        (await txn.query(
          'documents',
        )).map(DocumentRecord.fromMap).map(buildDocumentRecord),
      );
    });
    _indexInitialized = true;
  }

  SearchIndexRecord buildPropertyRecord(PropertyRecord property) {
    return SearchIndexRecord(
      id: _stableId(entityType: 'property', entityId: property.id),
      entityType: 'property',
      entityId: property.id,
      title: property.name,
      subtitle: '${property.addressLine1}, ${property.city}',
      body: property.notes,
      updatedAt: property.updatedAt,
    );
  }

  SearchIndexRecord buildScenarioRecord(ScenarioRecord scenario) {
    return SearchIndexRecord(
      id: _stableId(entityType: 'scenario', entityId: scenario.id),
      entityType: 'scenario',
      entityId: scenario.id,
      title: scenario.name,
      subtitle: scenario.strategyType,
      body: 'property_id:${scenario.propertyId}',
      updatedAt: scenario.updatedAt,
    );
  }

  SearchIndexRecord buildPortfolioRecord(PortfolioRecord portfolio) {
    return SearchIndexRecord(
      id: _stableId(entityType: 'portfolio', entityId: portfolio.id),
      entityType: 'portfolio',
      entityId: portfolio.id,
      title: portfolio.name,
      subtitle: portfolio.description,
      body: null,
      updatedAt: portfolio.updatedAt,
    );
  }

  SearchIndexRecord buildNoteRecord(NoteRecord note) {
    return SearchIndexRecord(
      id: _stableId(entityType: 'note', entityId: note.id),
      entityType: 'note',
      entityId: note.id,
      title: note.text,
      subtitle: '${note.entityType}:${note.entityId}',
      body: note.createdBy,
      updatedAt: note.createdAt,
    );
  }

  SearchIndexRecord buildNotificationRecord(NotificationRecord notification) {
    return SearchIndexRecord(
      id: _stableId(entityType: 'notification', entityId: notification.id),
      entityType: 'notification',
      entityId: notification.id,
      title: notification.message,
      subtitle: notification.kind,
      body: '${notification.entityType}:${notification.entityId}',
      updatedAt: notification.readAt ?? notification.createdAt,
    );
  }

  SearchIndexRecord buildLedgerEntryRecord(LedgerEntryRecord entry) {
    return SearchIndexRecord(
      id: _stableId(entityType: 'ledger_entry', entityId: entry.id),
      entityType: 'ledger_entry',
      entityId: entry.id,
      title: '${entry.direction} ${entry.amount.toStringAsFixed(2)}',
      subtitle: entry.counterparty,
      body: entry.memo,
      updatedAt: entry.createdAt,
    );
  }

  SearchIndexRecord buildTaskRecord(TaskRecord task) {
    return SearchIndexRecord(
      id: _stableId(entityType: 'task', entityId: task.id),
      entityType: 'task',
      entityId: task.id,
      title: task.title,
      subtitle: task.status,
      body:
          task.entityId == null
              ? task.entityType
              : '${task.entityType}:${task.entityId}',
      updatedAt: task.updatedAt,
    );
  }

  SearchIndexRecord buildDocumentRecord(DocumentRecord document) {
    return SearchIndexRecord(
      id: _stableId(entityType: 'document', entityId: document.id),
      entityType: 'document',
      entityId: document.id,
      title: document.fileName,
      subtitle: document.typeId ?? document.entityType,
      body:
          'entity_type:${document.entityType}|entity_id:${document.entityId}|property_id:${document.entityType == 'property' || document.entityType == 'asset_property' ? document.entityId : ''}|file_path:${document.filePath}',
      updatedAt: document.updatedAt,
    );
  }

  Future<void> _insertAll(
    Transaction txn,
    Iterable<SearchIndexRecord> records,
  ) async {
    for (final record in records) {
      await txn.insert(
        'search_index',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  String _stableId({required String entityType, required String entityId}) {
    return '$entityType:$entityId';
  }
}
