import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/inputs.dart';
import '../../core/models/scenario_valuation.dart';
import '../../core/models/scenario_version.dart';
import '../../core/versioning/scenario_diff.dart';
import '../../core/versioning/scenario_snapshot.dart';

class ScenarioVersionDetail {
  const ScenarioVersionDetail({
    required this.version,
    required this.blob,
    required this.snapshot,
  });

  final ScenarioVersionRecord version;
  final ScenarioVersionBlobRecord blob;
  final ScenarioSnapshot snapshot;
}

class ScenarioVersionRepo {
  const ScenarioVersionRepo(this._db);

  final Database _db;

  Future<ScenarioVersionRecord> saveVersion({
    required String scenarioId,
    required String label,
    String? notes,
    String? createdBy,
    String? parentVersionId,
  }) async {
    return _db.transaction((txn) async {
      final snapshot = await _loadCurrentSnapshot(txn, scenarioId: scenarioId);
      final now = DateTime.now().millisecondsSinceEpoch;
      final version = ScenarioVersionRecord(
        id: const Uuid().v4(),
        scenarioId: scenarioId,
        label: label.trim(),
        notes: notes?.trim().isEmpty ?? true ? null : notes!.trim(),
        archived: false,
        createdAt: now,
        createdBy: createdBy,
        baseHash: snapshot.computeHash(),
        parentVersionId: parentVersionId,
      );
      final blob = ScenarioVersionBlobRecord(
        id: const Uuid().v4(),
        versionId: version.id,
        snapshotJson: snapshot.toCanonicalJson(),
        createdAt: now,
      );
      await txn.insert(
        'scenario_versions',
        version.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await txn.insert(
        'scenario_version_blobs',
        blob.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return version;
    });
  }

  Future<List<ScenarioVersionRecord>> listVersions(String scenarioId) async {
    final rows = await _db.query(
      'scenario_versions',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[scenarioId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ScenarioVersionRecord.fromMap).toList(growable: false);
  }

  Future<void> updateVersionMetadata({
    required String versionId,
    String? label,
    String? notes,
  }) async {
    await _db.transaction((txn) async {
      final existing = await _getVersionRecordInTxn(txn, versionId);
      if (existing == null) {
        throw StateError('Version not found: $versionId');
      }
      final updated = existing.copyWith(
        label: label == null || label.trim().isEmpty ? null : label.trim(),
        notes:
            notes == null
                ? existing.notes
                : (notes.trim().isEmpty ? null : notes.trim()),
      );
      await txn.update(
        'scenario_versions',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[versionId],
      );
    });
  }

  Future<void> setArchived({
    required String versionId,
    required bool archived,
  }) async {
    await _db.transaction((txn) async {
      final existing = await _getVersionRecordInTxn(txn, versionId);
      if (existing == null) {
        throw StateError('Version not found: $versionId');
      }
      final updated = existing.copyWith(archived: archived);
      await txn.update(
        'scenario_versions',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[versionId],
      );
    });
  }

  Future<ScenarioVersionDetail?> getVersion(String versionId) async {
    final versionRows = await _db.query(
      'scenario_versions',
      where: 'id = ?',
      whereArgs: <Object?>[versionId],
      limit: 1,
    );
    if (versionRows.isEmpty) {
      return null;
    }
    final blobRows = await _db.query(
      'scenario_version_blobs',
      where: 'version_id = ?',
      whereArgs: <Object?>[versionId],
      limit: 1,
    );
    if (blobRows.isEmpty) {
      return null;
    }
    final version = ScenarioVersionRecord.fromMap(versionRows.first);
    final blob = ScenarioVersionBlobRecord.fromMap(blobRows.first);
    final map = (jsonDecode(blob.snapshotJson) as Map<String, dynamic>).map(
      (key, value) => MapEntry<String, Object?>(key, value),
    );
    final snapshot = ScenarioSnapshot.fromCanonicalMap(map);
    return ScenarioVersionDetail(
      version: version,
      blob: blob,
      snapshot: snapshot,
    );
  }

  Future<List<DiffItem>> diffVersions(
    String versionAId,
    String versionBId,
  ) async {
    final a = await getVersion(versionAId);
    final b = await getVersion(versionBId);
    if (a == null || b == null) {
      return const <DiffItem>[];
    }
    return const ScenarioDiff().computeDiff(a.snapshot, b.snapshot);
  }

  Future<void> rollbackToVersion({
    required String scenarioId,
    required String versionId,
    String? rollbackBy,
  }) async {
    await _db.transaction((txn) async {
      final target = await _getVersionInTxn(txn, versionId);
      if (target == null) {
        throw StateError('Version not found: $versionId');
      }
      if (target.version.scenarioId != scenarioId) {
        throw StateError('Version does not belong to scenario.');
      }

      await _createVersionInTxn(
        txn,
        scenarioId: scenarioId,
        label: 'Rollback from ${target.version.label}',
        notes:
            'Automatic safety snapshot before rollback to ${target.version.id}',
        createdBy: rollbackBy,
        parentVersionId: target.version.id,
      );

      final snapshot = target.snapshot;
      await txn.insert(
        'scenario_inputs',
        snapshot.inputs.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'income_lines',
        where: 'scenario_id = ?',
        whereArgs: <Object?>[scenarioId],
      );
      for (final line in snapshot.incomeLines) {
        await txn.insert(
          'income_lines',
          line.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      await txn.delete(
        'expense_lines',
        where: 'scenario_id = ?',
        whereArgs: <Object?>[scenarioId],
      );
      for (final line in snapshot.expenseLines) {
        await txn.insert(
          'expense_lines',
          line.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      await txn.insert(
        'scenario_valuation',
        snapshot.valuation.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        'scenarios',
        <String, Object?>{'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: <Object?>[scenarioId],
      );
    });
  }

  Future<ScenarioVersionDetail?> _getVersionInTxn(
    Transaction txn,
    String versionId,
  ) async {
    final versionRows = await txn.query(
      'scenario_versions',
      where: 'id = ?',
      whereArgs: <Object?>[versionId],
      limit: 1,
    );
    if (versionRows.isEmpty) {
      return null;
    }
    final blobRows = await txn.query(
      'scenario_version_blobs',
      where: 'version_id = ?',
      whereArgs: <Object?>[versionId],
      limit: 1,
    );
    if (blobRows.isEmpty) {
      return null;
    }
    final version = ScenarioVersionRecord.fromMap(versionRows.first);
    final blob = ScenarioVersionBlobRecord.fromMap(blobRows.first);
    final map = (jsonDecode(blob.snapshotJson) as Map<String, dynamic>).map(
      (key, value) => MapEntry<String, Object?>(key, value),
    );
    return ScenarioVersionDetail(
      version: version,
      blob: blob,
      snapshot: ScenarioSnapshot.fromCanonicalMap(map),
    );
  }

  Future<ScenarioVersionRecord> _createVersionInTxn(
    Transaction txn, {
    required String scenarioId,
    required String label,
    String? notes,
    String? createdBy,
    String? parentVersionId,
  }) async {
    final snapshot = await _loadCurrentSnapshot(txn, scenarioId: scenarioId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final version = ScenarioVersionRecord(
      id: const Uuid().v4(),
      scenarioId: scenarioId,
      label: label.trim(),
      notes: notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      archived: false,
      createdAt: now,
      createdBy: createdBy,
      baseHash: snapshot.computeHash(),
      parentVersionId: parentVersionId,
    );
    final blob = ScenarioVersionBlobRecord(
      id: const Uuid().v4(),
      versionId: version.id,
      snapshotJson: snapshot.toCanonicalJson(),
      createdAt: now,
    );
    await txn.insert(
      'scenario_versions',
      version.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await txn.insert(
      'scenario_version_blobs',
      blob.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return version;
  }

  Future<ScenarioVersionRecord?> _getVersionRecordInTxn(
    Transaction txn,
    String versionId,
  ) async {
    final rows = await txn.query(
      'scenario_versions',
      where: 'id = ?',
      whereArgs: <Object?>[versionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ScenarioVersionRecord.fromMap(rows.first);
  }

  Future<ScenarioSnapshot> _loadCurrentSnapshot(
    DatabaseExecutor db, {
    required String scenarioId,
  }) async {
    final inputRows = await db.query(
      'scenario_inputs',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (inputRows.isEmpty) {
      throw StateError('Scenario inputs not found: $scenarioId');
    }
    final incomeRows = await db.query(
      'income_lines',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[scenarioId],
      orderBy: 'id ASC',
    );
    final expenseRows = await db.query(
      'expense_lines',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[scenarioId],
      orderBy: 'id ASC',
    );
    final valuationRows = await db.query(
      'scenario_valuation',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    final valuation =
        valuationRows.isEmpty
            ? ScenarioValuationRecord.defaults(scenarioId: scenarioId)
            : ScenarioValuationRecord.fromMap(valuationRows.first);
    return ScenarioSnapshot(
      scenarioId: scenarioId,
      inputs: ScenarioInputs.fromMap(inputRows.first),
      incomeLines: incomeRows.map(IncomeLine.fromMap).toList(growable: false),
      expenseLines: expenseRows
          .map(ExpenseLine.fromMap)
          .toList(growable: false),
      valuation: valuation,
    );
  }
}
