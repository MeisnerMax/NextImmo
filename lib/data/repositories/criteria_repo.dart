import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/criteria.dart';

class CriteriaRepository {
  const CriteriaRepository(this._db);

  final Database _db;

  Future<List<CriteriaSet>> listSets() async {
    final rows = await _db.query(
      'criteria_sets',
      orderBy: 'is_default DESC, updated_at DESC',
    );
    return rows.map(CriteriaSet.fromMap).toList();
  }

  Future<CriteriaSet?> getSetById(String id) async {
    final rows = await _db.query(
      'criteria_sets',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return CriteriaSet.fromMap(rows.first);
  }

  Future<CriteriaSet?> getDefaultSet() async {
    final rows = await _db.query(
      'criteria_sets',
      where: 'is_default = 1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return CriteriaSet.fromMap(rows.first);
  }

  Future<List<CriteriaRule>> listRules(String criteriaSetId) async {
    final rows = await _db.query(
      'criteria_rules',
      where: 'criteria_set_id = ?',
      whereArgs: <Object?>[criteriaSetId],
      orderBy: 'field_key ASC',
    );
    return rows.map(CriteriaRule.fromMap).toList();
  }

  Future<CriteriaSet> createSet({
    required String name,
    bool isDefault = false,
  }) async {
    await _assertUniqueSetName(name: name, excludeId: null);

    final now = DateTime.now().millisecondsSinceEpoch;
    final set = CriteriaSet(
      id: const Uuid().v4(),
      name: name,
      isDefault: isDefault,
      createdAt: now,
      updatedAt: now,
    );

    await _db.transaction((txn) async {
      if (isDefault) {
        await txn.update('criteria_sets', <String, Object?>{'is_default': 0});
      }
      await txn.insert(
        'criteria_sets',
        set.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });

    return set;
  }

  Future<CriteriaRule> addRule({
    required String criteriaSetId,
    required String fieldKey,
    required String operator,
    required double targetValue,
    required String unit,
    required String severity,
    bool enabled = true,
  }) async {
    final rule = CriteriaRule(
      id: const Uuid().v4(),
      criteriaSetId: criteriaSetId,
      fieldKey: fieldKey,
      operator: operator,
      targetValue: targetValue,
      unit: unit,
      severity: severity,
      enabled: enabled,
    );

    await _db.insert(
      'criteria_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return rule;
  }

  Future<void> updateSet({required String id, required String name}) async {
    await _assertUniqueSetName(name: name, excludeId: id);
    await _db.update(
      'criteria_sets',
      <String, Object?>{
        'name': name.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteSet(String id) async {
    final set = await getSetById(id);
    if (set == null) {
      return;
    }
    if (set.isDefault) {
      throw StateError('Cannot delete active default criteria set.');
    }

    await _db.delete(
      'criteria_sets',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> setDefault(String criteriaSetId) async {
    await _db.transaction((txn) async {
      await txn.update('criteria_sets', <String, Object?>{'is_default': 0});
      await txn.update(
        'criteria_sets',
        <String, Object?>{
          'is_default': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[criteriaSetId],
      );
    });
  }

  Future<void> updateRule(CriteriaRule rule) async {
    await _db.update(
      'criteria_rules',
      rule.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[rule.id],
    );
  }

  Future<void> deleteRule(String id) async {
    await _db.delete(
      'criteria_rules',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<String?> getPropertyOverride(String propertyId) async {
    final rows = await _db.query(
      'property_criteria_overrides',
      columns: const ['criteria_set_id'],
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['criteria_set_id'] as String?;
  }

  Future<void> setPropertyOverride({
    required String propertyId,
    required String criteriaSetId,
  }) async {
    await _db.insert('property_criteria_overrides', <String, Object?>{
      'property_id': propertyId,
      'criteria_set_id': criteriaSetId,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearPropertyOverride(String propertyId) async {
    await _db.delete(
      'property_criteria_overrides',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
    );
  }

  Future<void> _assertUniqueSetName({
    required String name,
    required String? excludeId,
  }) async {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw StateError('Criteria set name is required.');
    }

    final where =
        excludeId == null ? 'LOWER(name) = ?' : 'LOWER(name) = ? AND id != ?';
    final whereArgs =
        excludeId == null
            ? <Object?>[normalized]
            : <Object?>[normalized, excludeId];

    final rows = await _db.query(
      'criteria_sets',
      columns: const ['id'],
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw StateError('Criteria set name already exists.');
    }
  }
}
