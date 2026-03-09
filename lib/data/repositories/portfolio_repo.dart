import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/portfolio.dart';
import '../../core/models/property.dart';
import 'search_repo.dart';

class PortfolioRepository {
  const PortfolioRepository(this._db, {SearchRepo? searchRepo}) : _searchRepo = searchRepo;

  final Database _db;
  final SearchRepo? _searchRepo;

  Future<List<PortfolioRecord>> listPortfolios() async {
    final rows = await _db.query('portfolios', orderBy: 'updated_at DESC');
    return rows.map(PortfolioRecord.fromMap).toList();
  }

  Future<PortfolioRecord?> getById(String id) async {
    final rows = await _db.query(
      'portfolios',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PortfolioRecord.fromMap(rows.first);
  }

  Future<PortfolioRecord> createPortfolio({
    required String name,
    String? description,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = PortfolioRecord(
      id: const Uuid().v4(),
      name: name,
      description: description,
      createdAt: now,
      updatedAt: now,
    );

    await _db.insert(
      'portfolios',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildPortfolioRecord(record));
    }
    return record;
  }

  Future<void> renamePortfolio({
    required String id,
    required String name,
  }) async {
    await _db.update(
      'portfolios',
      <String, Object?>{
        'name': name,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    final updated = await getById(id);
    final searchRepo = _searchRepo;
    if (updated != null && searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildPortfolioRecord(updated));
    }
  }

  Future<void> deletePortfolio(String id) async {
    await _db.delete('portfolios', where: 'id = ?', whereArgs: <Object?>[id]);
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.deleteIndexEntryByEntity(
        entityType: 'portfolio',
        entityId: id,
      );
    }
  }

  Future<List<PropertyRecord>> listPortfolioProperties(
    String portfolioId,
  ) async {
    final rows = await _db.rawQuery(
      '''
      SELECT p.*
      FROM properties p
      INNER JOIN portfolio_properties pp ON pp.property_id = p.id
      WHERE pp.portfolio_id = ? AND p.archived = 0
      ORDER BY p.updated_at DESC
    ''',
      <Object?>[portfolioId],
    );
    return rows.map(PropertyRecord.fromMap).toList();
  }

  Future<List<PropertyRecord>> listUnassignedProperties(
    String portfolioId,
  ) async {
    final rows = await _db.rawQuery(
      '''
      SELECT p.*
      FROM properties p
      WHERE p.archived = 0
        AND p.id NOT IN (
          SELECT property_id FROM portfolio_properties WHERE portfolio_id = ?
        )
      ORDER BY p.updated_at DESC
    ''',
      <Object?>[portfolioId],
    );
    return rows.map(PropertyRecord.fromMap).toList();
  }

  Future<void> attachProperty({
    required String portfolioId,
    required String propertyId,
  }) async {
    await _db.insert('portfolio_properties', <String, Object?>{
      'portfolio_id': portfolioId,
      'property_id': propertyId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> detachProperty({
    required String portfolioId,
    required String propertyId,
  }) async {
    await _db.delete(
      'portfolio_properties',
      where: 'portfolio_id = ? AND property_id = ?',
      whereArgs: <Object?>[portfolioId, propertyId],
    );
  }

  Future<List<String>> listPortfolioIdsByProperty(String propertyId) async {
    final rows = await _db.query(
      'portfolio_properties',
      columns: const <String>['portfolio_id'],
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
    );
    return rows.map((row) => row['portfolio_id']! as String).toList();
  }
}
