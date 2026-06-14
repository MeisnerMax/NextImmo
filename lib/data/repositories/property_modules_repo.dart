import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/models/property_modules.dart';

class PropertyModulesRepo {
  const PropertyModulesRepo(this._db);

  final Database _db;

  Future<PropertySaleDetailsRecord?> getSaleDetails(String propertyId) async {
    final rows = await _db.query(
      'property_sale_details',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PropertySaleDetailsRecord.fromMap(rows.first);
  }

  Future<List<ContactRecord>> listContactsForProperty({
    required String propertyId,
    required String role,
  }) async {
    final rows = await _db.rawQuery(
      '''
      SELECT DISTINCT c.*
      FROM contacts c
      LEFT JOIN buyer_interests bi ON bi.contact_id = c.id
      LEFT JOIN unit_sale_details usd ON usd.buyer_contact_id = c.id
      LEFT JOIN reservations r ON r.guest_contact_id = c.id
      WHERE c.role = ?
        AND (
          bi.property_id = ?
          OR usd.property_id = ?
          OR r.property_id = ?
        )
      ORDER BY c.display_name COLLATE NOCASE
      ''',
      <Object?>[role, propertyId, propertyId, propertyId],
    );
    return rows.map(ContactRecord.fromMap).toList(growable: false);
  }

  Future<List<BuyerInterestRecord>> listBuyerInterests(
    String propertyId,
  ) async {
    final rows = await _db.query(
      'buyer_interests',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(BuyerInterestRecord.fromMap).toList(growable: false);
  }

  Future<List<ReservationRecord>> listReservations(String propertyId) async {
    final rows = await _db.query(
      'reservations',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'check_in DESC',
    );
    return rows.map(ReservationRecord.fromMap).toList(growable: false);
  }

  Future<List<UnitSaleDetailsRecord>> listUnitSaleDetails(
    String propertyId,
  ) async {
    final rows = await _db.query(
      'unit_sale_details',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(UnitSaleDetailsRecord.fromMap).toList(growable: false);
  }

  Future<bool> hasHotelModules(String propertyId) async {
    final reservationRows = await _db.query(
      'reservations',
      columns: const <String>['id'],
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      limit: 1,
    );
    if (reservationRows.isNotEmpty) {
      return true;
    }

    final roomRows = await _db.query(
      'units',
      columns: const <String>['id'],
      where: 'asset_property_id = ? AND unit_type = ?',
      whereArgs: <Object?>[propertyId, 'hotel_room'],
      limit: 1,
    );
    return roomRows.isNotEmpty;
  }
}

