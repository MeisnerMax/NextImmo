import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/comps.dart';

class CompsRepository {
  const CompsRepository(this._db);

  final Database _db;

  Future<List<CompSale>> listSales(String propertyId) async {
    final rows = await _db.query(
      'comps_sales',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
    );
    return rows.map(CompSale.fromMap).toList();
  }

  Future<List<CompRental>> listRentals(String propertyId) async {
    final rows = await _db.query(
      'comps_rentals',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
    );
    return rows.map(CompRental.fromMap).toList();
  }

  Future<void> addSale({
    required String propertyId,
    required String address,
    required double price,
    double? sqft,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('comps_sales', <String, Object?>{
      'id': const Uuid().v4(),
      'property_id': propertyId,
      'address': address,
      'price': price,
      'sqft': sqft,
      'selected': 1,
      'weight': 1.0,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> updateSale({
    required String id,
    bool? selected,
    double? weight,
  }) async {
    final values = <String, Object?>{};
    if (selected != null) {
      values['selected'] = selected ? 1 : 0;
    }
    if (weight != null) {
      values['weight'] = weight;
    }
    if (values.isEmpty) {
      return;
    }
    await _db.update(
      'comps_sales',
      values,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> addRental({
    required String propertyId,
    required String address,
    required double rentMonthly,
    double? sqft,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('comps_rentals', <String, Object?>{
      'id': const Uuid().v4(),
      'property_id': propertyId,
      'address': address,
      'rent_monthly': rentMonthly,
      'sqft': sqft,
      'selected': 1,
      'weight': 1.0,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> updateRental({
    required String id,
    bool? selected,
    double? weight,
  }) async {
    final values = <String, Object?>{};
    if (selected != null) {
      values['selected'] = selected ? 1 : 0;
    }
    if (weight != null) {
      values['weight'] = weight;
    }
    if (values.isEmpty) {
      return;
    }
    await _db.update(
      'comps_rentals',
      values,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
