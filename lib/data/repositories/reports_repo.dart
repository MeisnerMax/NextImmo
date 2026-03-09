import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/report_templates.dart';

class ReportsRepository {
  const ReportsRepository(this._db);

  final Database _db;

  Future<List<ReportTemplateRecord>> listTemplates() async {
    final rows = await _db.query(
      'report_templates',
      orderBy: 'is_default DESC, updated_at DESC',
    );
    return rows.map(ReportTemplateRecord.fromMap).toList();
  }

  Future<void> upsertTemplate(ReportTemplateRecord template) async {
    await _assertUniqueName(name: template.name, excludeId: template.id);

    await _db.transaction((txn) async {
      if (template.isDefault) {
        await txn.update('report_templates', <String, Object?>{
          'is_default': 0,
        });
      }

      await txn.insert(
        'report_templates',
        template.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (template.isDefault) {
        await txn.update('app_settings', <String, Object?>{
          'default_report_template_id': template.id,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, where: 'id = 1');
      }
    });
  }

  Future<ReportTemplateRecord?> getTemplateById(String id) async {
    final rows = await _db.query(
      'report_templates',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ReportTemplateRecord.fromMap(rows.first);
  }

  Future<ReportTemplateRecord?> getDefaultTemplate() async {
    final settingsRows = await _db.query(
      'app_settings',
      columns: const ['default_report_template_id'],
      where: 'id = 1',
      limit: 1,
    );

    final fromSettings =
        settingsRows.isNotEmpty
            ? settingsRows.first['default_report_template_id'] as String?
            : null;
    if (fromSettings != null) {
      final byId = await getTemplateById(fromSettings);
      if (byId != null) {
        return byId;
      }
    }

    final rows = await _db.query(
      'report_templates',
      where: 'is_default = 1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return ReportTemplateRecord.fromMap(rows.first);
    }

    final fallback = await _db.query(
      'report_templates',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (fallback.isEmpty) {
      return null;
    }
    return ReportTemplateRecord.fromMap(fallback.first);
  }

  Future<void> setDefaultTemplate(String templateId) async {
    await _db.transaction((txn) async {
      await txn.update('report_templates', <String, Object?>{'is_default': 0});
      await txn.update(
        'report_templates',
        <String, Object?>{
          'is_default': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[templateId],
      );
      await txn.update('app_settings', <String, Object?>{
        'default_report_template_id': templateId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, where: 'id = 1');
    });
  }

  Future<void> deleteTemplate(String templateId) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'report_templates',
        columns: const ['is_default'],
        where: 'id = ?',
        whereArgs: <Object?>[templateId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return;
      }

      final wasDefault = ((rows.first['is_default'] as num?) ?? 0) == 1;
      await txn.delete(
        'report_templates',
        where: 'id = ?',
        whereArgs: <Object?>[templateId],
      );

      if (!wasDefault) {
        return;
      }

      final next = await txn.query(
        'report_templates',
        columns: const ['id'],
        orderBy: 'updated_at DESC',
        limit: 1,
      );
      if (next.isNotEmpty) {
        final nextId = next.first['id']! as String;
        await txn.update(
          'report_templates',
          <String, Object?>{'is_default': 1},
          where: 'id = ?',
          whereArgs: <Object?>[nextId],
        );
        await txn.update('app_settings', <String, Object?>{
          'default_report_template_id': nextId,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, where: 'id = 1');
      } else {
        await txn.update('app_settings', <String, Object?>{
          'default_report_template_id': null,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, where: 'id = 1');
      }
    });
  }

  Future<List<ReportRecord>> listReports(
    String propertyId,
    String scenarioId,
  ) async {
    final rows = await _db.query(
      'reports',
      where: 'property_id = ? AND scenario_id = ?',
      whereArgs: <Object?>[propertyId, scenarioId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ReportRecord.fromMap).toList();
  }

  Future<ReportRecord> insertReport({
    required String propertyId,
    required String scenarioId,
    required String templateId,
    required String pdfPath,
  }) async {
    final report = ReportRecord(
      id: const Uuid().v4(),
      propertyId: propertyId,
      scenarioId: scenarioId,
      templateId: templateId,
      pdfPath: pdfPath,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _db.insert(
      'reports',
      report.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return report;
  }

  Future<void> _assertUniqueName({
    required String name,
    required String excludeId,
  }) async {
    final normalized = name.trim().toLowerCase();
    final rows = await _db.query(
      'report_templates',
      columns: const ['id', 'name'],
      where: 'LOWER(name) = ? AND id != ?',
      whereArgs: <Object?>[normalized, excludeId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw StateError('Template name already exists.');
    }
  }
}
