import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/contractor.dart';

class ContractorRepository {
  const ContractorRepository(this._db);

  final Database _db;

  Future<List<ContractorRecord>> listContractors() async {
    final rows = await _db.query(
      'contractors',
      orderBy: 'company_name ASC',
    );
    return rows.map(ContractorRecord.fromMap).toList();
  }

  Future<ContractorRecord?> getContractor(String id) async {
    final rows = await _db.query(
      'contractors',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (rows.isEmpty) return null;
    return ContractorRecord.fromMap(rows.first);
  }

  Future<ContractorRecord> createContractor({
    required String companyName,
    required String tradeCategory,
    required String contactName,
    required String phone,
    required String email,
    required String address,
    double? hourlyRate,
    List<String> serviceAreas = const [],
    String? notes,
    double? ratingPrice,
    double? ratingQuality,
    double? ratingSpeed,
    double? ratingCommunication,
    double? ratingPunctuality,
    int? insuranceCertExpiry,
    bool isActive = true,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final contractor = ContractorRecord(
      id: const Uuid().v4(),
      companyName: companyName,
      tradeCategory: tradeCategory,
      contactName: contactName,
      phone: phone,
      email: email,
      address: address,
      hourlyRate: hourlyRate,
      serviceAreas: serviceAreas,
      notes: notes,
      createdAt: now,
      updatedAt: now,
      ratingPrice: ratingPrice,
      ratingQuality: ratingQuality,
      ratingSpeed: ratingSpeed,
      ratingCommunication: ratingCommunication,
      ratingPunctuality: ratingPunctuality,
      insuranceCertExpiry: insuranceCertExpiry,
      isActive: isActive,
    );
    await _db.insert(
      'contractors',
      contractor.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return contractor;
  }

  Future<ContractorRecord> updateContractor(ContractorRecord contractor) async {
    final updated = ContractorRecord(
      id: contractor.id,
      companyName: contractor.companyName,
      tradeCategory: contractor.tradeCategory,
      contactName: contractor.contactName,
      phone: contractor.phone,
      email: contractor.email,
      address: contractor.address,
      hourlyRate: contractor.hourlyRate,
      serviceAreas: contractor.serviceAreas,
      notes: contractor.notes,
      createdAt: contractor.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      ratingPrice: contractor.ratingPrice,
      ratingQuality: contractor.ratingQuality,
      ratingSpeed: contractor.ratingSpeed,
      ratingCommunication: contractor.ratingCommunication,
      ratingPunctuality: contractor.ratingPunctuality,
      insuranceCertExpiry: contractor.insuranceCertExpiry,
      isActive: contractor.isActive,
    );
    await _db.update(
      'contractors',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[contractor.id],
    );
    return updated;
  }

  Future<void> deleteContractor(String id) async {
    await _db.delete('contractors', where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
