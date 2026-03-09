import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_writer.dart';
import '../../core/models/import_job.dart';
import '../../core/services/ledger_service.dart';
import 'audit_log_repo.dart';

class ImportsRepository {
  const ImportsRepository(this._db, {this.auditLogRepo, this.auditWriter});

  final Database _db;
  final AuditLogRepo? auditLogRepo;
  final AuditWriter? auditWriter;
  static const LedgerService _ledgerService = LedgerService();

  Future<ImportJobRecord> createJob({
    required String kind,
    required String targetScope,
  }) async {
    final record = ImportJobRecord(
      id: const Uuid().v4(),
      kind: kind,
      status: 'pending',
      targetScope: targetScope,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      finishedAt: null,
      error: null,
    );
    await _db.insert(
      'import_jobs',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _recordAudit(
      entityType: 'import_job',
      entityId: record.id,
      action: 'create',
      summary: 'Import job created for $targetScope',
      newValues: record.toMap(),
      source: 'import',
    );
    return record;
  }

  Future<void> saveMapping({
    required String importJobId,
    required String targetTable,
    required Map<String, String> mapping,
  }) async {
    final record = ImportMappingRecord(
      id: const Uuid().v4(),
      importJobId: importJobId,
      targetTable: targetTable,
      mappingJson: jsonEncode(mapping),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insert(
      'import_mappings',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _recordAudit(
      entityType: 'import_mapping',
      entityId: record.id,
      action: 'create',
      summary: 'Import mapping saved for $targetTable',
      newValues: record.toMap(),
      parentEntityType: 'import_job',
      parentEntityId: importJobId,
      source: 'import',
    );
  }

  Future<ImportJobRecord?> getJob(String id) async {
    final rows = await _db.query(
      'import_jobs',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ImportJobRecord.fromMap(rows.first);
  }

  Future<List<ImportJobRecord>> listJobs() async {
    final rows = await _db.query('import_jobs', orderBy: 'created_at DESC');
    return rows.map(ImportJobRecord.fromMap).toList();
  }

  Future<int> runCsvImport({
    required String jobId,
    required String csvPath,
  }) async {
    await _db.update(
      'import_jobs',
      <String, Object?>{'status': 'running', 'error': null},
      where: 'id = ?',
      whereArgs: <Object?>[jobId],
    );

    try {
      final mappingRows = await _db.query(
        'import_mappings',
        where: 'import_job_id = ?',
        whereArgs: <Object?>[jobId],
        orderBy: 'created_at DESC',
        limit: 1,
      );
      if (mappingRows.isEmpty) {
        throw StateError('No mapping configured for import job.');
      }

      final mapping = ImportMappingRecord.fromMap(mappingRows.first);
      final mappingJson =
          jsonDecode(mapping.mappingJson) as Map<String, dynamic>;
      final fieldToCsv = mappingJson.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      );

      final file = File(csvPath);
      if (!file.existsSync()) {
        throw StateError('CSV file not found.');
      }
      final text = await file.readAsString();
      final rows = const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(text);
      if (rows.length < 2) {
        throw StateError('CSV must include header and at least one data row.');
      }

      final headers = rows.first.map((e) => e.toString()).toList();
      final headerIndex = <String, int>{
        for (var i = 0; i < headers.length; i++) headers[i]: i,
      };

      final dataRows = rows.skip(1).toList();
      final imported = await _db.transaction((txn) async {
        switch (mapping.targetTable) {
          case 'properties':
            return _importProperties(
              txn: txn,
              dataRows: dataRows,
              headerIndex: headerIndex,
              fieldToCsv: fieldToCsv,
            );
          case 'esg_profiles':
            return _importEsgProfiles(
              txn: txn,
              dataRows: dataRows,
              headerIndex: headerIndex,
              fieldToCsv: fieldToCsv,
            );
          case 'property_kpi_snapshots':
            return _importSnapshots(
              txn: txn,
              dataRows: dataRows,
              headerIndex: headerIndex,
              fieldToCsv: fieldToCsv,
            );
          case 'ledger_entries':
            return _importLedgerEntries(
              txn: txn,
              dataRows: dataRows,
              headerIndex: headerIndex,
              fieldToCsv: fieldToCsv,
            );
          default:
            throw StateError(
              'Unsupported target table: ${mapping.targetTable}',
            );
        }
      });

      await _db.update(
        'import_jobs',
        <String, Object?>{
          'status': 'succeeded',
          'finished_at': DateTime.now().millisecondsSinceEpoch,
          'error': null,
        },
        where: 'id = ?',
        whereArgs: <Object?>[jobId],
      );
      await _recordAudit(
        entityType: 'import_job',
        entityId: jobId,
        action: 'import',
        summary: 'Import succeeded for ${mapping.targetTable}: $imported rows',
        source: 'import',
        newValues: <String, Object?>{
          'status': 'succeeded',
          'target_table': mapping.targetTable,
          'imported_rows': imported,
        },
        reason: csvPath,
      );
      return imported;
    } catch (error) {
      await _db.update(
        'import_jobs',
        <String, Object?>{
          'status': 'failed',
          'finished_at': DateTime.now().millisecondsSinceEpoch,
          'error': error.toString(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[jobId],
      );
      await _recordAudit(
        entityType: 'import_job',
        entityId: jobId,
        action: 'import',
        summary: 'Import failed: $error',
        source: 'import',
        newValues: <String, Object?>{
          'status': 'failed',
          'error': error.toString(),
        },
        reason: csvPath,
      );
      rethrow;
    }
  }

  Future<int> _importProperties({
    required Transaction txn,
    required List<List<dynamic>> dataRows,
    required Map<String, int> headerIndex,
    required Map<String, String> fieldToCsv,
  }) async {
    const requiredFields = <String>[
      'name',
      'address_line1',
      'zip',
      'city',
      'country',
      'property_type',
      'units',
    ];
    _assertRequiredMappings(requiredFields, fieldToCsv);

    final now = DateTime.now().millisecondsSinceEpoch;
    var count = 0;
    for (final row in dataRows) {
      final id = _get(row, headerIndex, fieldToCsv['id']) ?? const Uuid().v4();
      final name = _requiredValue(row, headerIndex, fieldToCsv['name']);
      final addressLine1 = _requiredValue(
        row,
        headerIndex,
        fieldToCsv['address_line1'],
      );
      final zip = _requiredValue(row, headerIndex, fieldToCsv['zip']);
      final city = _requiredValue(row, headerIndex, fieldToCsv['city']);
      final country = _requiredValue(row, headerIndex, fieldToCsv['country']);
      final propertyType = _requiredValue(
        row,
        headerIndex,
        fieldToCsv['property_type'],
      );
      final units = int.tryParse(
        _requiredValue(row, headerIndex, fieldToCsv['units']),
      );
      if (units == null) {
        throw StateError('Invalid units value in CSV.');
      }

      await txn.insert('properties', <String, Object?>{
        'id': id,
        'name': name,
        'address_line1': addressLine1,
        'address_line2': _get(row, headerIndex, fieldToCsv['address_line2']),
        'zip': zip,
        'city': city,
        'country': country,
        'property_type': propertyType,
        'units': units,
        'sqft': double.tryParse(
          _get(row, headerIndex, fieldToCsv['sqft']) ?? '',
        ),
        'year_built': int.tryParse(
          _get(row, headerIndex, fieldToCsv['year_built']) ?? '',
        ),
        'notes': _get(row, headerIndex, fieldToCsv['notes']),
        'created_at': now,
        'updated_at': now,
        'archived': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }
    return count;
  }

  Future<int> _importEsgProfiles({
    required Transaction txn,
    required List<List<dynamic>> dataRows,
    required Map<String, int> headerIndex,
    required Map<String, String> fieldToCsv,
  }) async {
    _assertRequiredMappings(const <String>['property_id'], fieldToCsv);
    final now = DateTime.now().millisecondsSinceEpoch;
    var count = 0;
    for (final row in dataRows) {
      final propertyId = _requiredValue(
        row,
        headerIndex,
        fieldToCsv['property_id'],
      );

      await txn.insert('esg_profiles', <String, Object?>{
        'property_id': propertyId,
        'epc_rating': _get(row, headerIndex, fieldToCsv['epc_rating']),
        'epc_valid_until': int.tryParse(
          _get(row, headerIndex, fieldToCsv['epc_valid_until']) ?? '',
        ),
        'emissions_kgco2_m2': double.tryParse(
          _get(row, headerIndex, fieldToCsv['emissions_kgco2_m2']) ?? '',
        ),
        'last_audit_date': int.tryParse(
          _get(row, headerIndex, fieldToCsv['last_audit_date']) ?? '',
        ),
        'target_rating': _get(row, headerIndex, fieldToCsv['target_rating']),
        'notes': _get(row, headerIndex, fieldToCsv['notes']),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }
    return count;
  }

  Future<int> _importSnapshots({
    required Transaction txn,
    required List<List<dynamic>> dataRows,
    required Map<String, int> headerIndex,
    required Map<String, String> fieldToCsv,
  }) async {
    _assertRequiredMappings(const <String>[
      'property_id',
      'period_date',
    ], fieldToCsv);
    final now = DateTime.now().millisecondsSinceEpoch;
    var count = 0;
    for (final row in dataRows) {
      await txn.insert('property_kpi_snapshots', <String, Object?>{
        'id': const Uuid().v4(),
        'property_id': _requiredValue(
          row,
          headerIndex,
          fieldToCsv['property_id'],
        ),
        'scenario_id': _get(row, headerIndex, fieldToCsv['scenario_id']),
        'period_date': _requiredValue(
          row,
          headerIndex,
          fieldToCsv['period_date'],
        ),
        'noi': double.tryParse(_get(row, headerIndex, fieldToCsv['noi']) ?? ''),
        'occupancy': double.tryParse(
          _get(row, headerIndex, fieldToCsv['occupancy']) ?? '',
        ),
        'capex': double.tryParse(
          _get(row, headerIndex, fieldToCsv['capex']) ?? '',
        ),
        'valuation': double.tryParse(
          _get(row, headerIndex, fieldToCsv['valuation']) ?? '',
        ),
        'source': _get(row, headerIndex, fieldToCsv['source']) ?? 'import',
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      count++;
    }
    return count;
  }

  Future<int> _importLedgerEntries({
    required Transaction txn,
    required List<List<dynamic>> dataRows,
    required Map<String, int> headerIndex,
    required Map<String, String> fieldToCsv,
  }) async {
    _assertRequiredMappings(const <String>[
      'posted_at',
      'account_name',
      'direction',
      'amount',
    ], fieldToCsv);
    final autoCreateUnknownAccounts =
        (fieldToCsv['__auto_create_accounts'] ?? '0').trim() == '1';
    final now = DateTime.now().millisecondsSinceEpoch;
    var count = 0;
    for (final row in dataRows) {
      final postedAtRaw = _requiredValue(
        row,
        headerIndex,
        fieldToCsv['posted_at'],
      );
      final postedAt = _parseDateToEpochMs(postedAtRaw);
      if (postedAt == null) {
        throw StateError('Invalid posted_at value: $postedAtRaw');
      }
      final direction =
          _requiredValue(
            row,
            headerIndex,
            fieldToCsv['direction'],
          ).trim().toLowerCase();
      if (direction != 'in' && direction != 'out') {
        throw StateError('Direction must be "in" or "out".');
      }
      final amountRaw = _requiredValue(row, headerIndex, fieldToCsv['amount']);
      final amount = double.tryParse(amountRaw);
      if (amount == null || amount <= 0) {
        throw StateError('Amount must be numeric > 0.');
      }

      final accountName =
          _requiredValue(row, headerIndex, fieldToCsv['account_name']).trim();
      String? accountId = await _findLedgerAccountId(txn, accountName);
      if (accountId == null) {
        if (!autoCreateUnknownAccounts) {
          throw StateError('Unknown account: $accountName');
        }
        accountId = const Uuid().v4();
        await txn.insert('ledger_accounts', <String, Object?>{
          'id': accountId,
          'name': accountName,
          'kind':
              (_get(row, headerIndex, fieldToCsv['account_kind']) ?? 'other')
                  .trim()
                  .toLowerCase(),
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      await txn.insert('ledger_entries', <String, Object?>{
        'id': const Uuid().v4(),
        'entity_type':
            (_get(row, headerIndex, fieldToCsv['entity_type']) ?? 'none')
                .trim(),
        'entity_id': _get(row, headerIndex, fieldToCsv['entity_id']),
        'account_id': accountId,
        'posted_at': postedAt,
        'period_key': _ledgerService.derivePeriodKey(postedAt),
        'direction': direction,
        'amount': amount.abs(),
        'currency_code':
            (_get(row, headerIndex, fieldToCsv['currency_code']) ?? 'EUR')
                .trim(),
        'counterparty': _get(row, headerIndex, fieldToCsv['counterparty']),
        'memo': _get(row, headerIndex, fieldToCsv['memo']),
        'document_id': _get(row, headerIndex, fieldToCsv['document_id']),
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      count++;
    }
    return count;
  }

  void _assertRequiredMappings(
    List<String> requiredFields,
    Map<String, String> mapping,
  ) {
    for (final field in requiredFields) {
      if ((mapping[field] ?? '').trim().isEmpty) {
        throw StateError('Missing mapping for required field "$field".');
      }
    }
  }

  String _requiredValue(
    List<dynamic> row,
    Map<String, int> headerIndex,
    String? columnName,
  ) {
    final value = _get(row, headerIndex, columnName);
    if (value == null || value.trim().isEmpty) {
      throw StateError('Missing required CSV value for "$columnName".');
    }
    return value.trim();
  }

  String? _get(
    List<dynamic> row,
    Map<String, int> headerIndex,
    String? columnName,
  ) {
    if (columnName == null || columnName.trim().isEmpty) {
      return null;
    }
    final index = headerIndex[columnName];
    if (index == null || index < 0 || index >= row.length) {
      return null;
    }
    final value = row[index].toString();
    return value;
  }

  Future<String?> _findLedgerAccountId(Transaction txn, String name) async {
    final rows = await txn.query(
      'ledger_accounts',
      columns: const <String>['id'],
      where: 'name = ? COLLATE NOCASE',
      whereArgs: <Object?>[name],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['id']! as String;
  }

  int? _parseDateToEpochMs(String raw) {
    final numeric = int.tryParse(raw.trim());
    if (numeric != null) {
      return numeric;
    }
    final parsed = DateTime.tryParse(raw.trim());
    return parsed?.millisecondsSinceEpoch;
  }

  Future<void> _recordAudit({
    required String entityType,
    required String entityId,
    required String action,
    String? summary,
    String source = 'ui',
    String? parentEntityType,
    String? parentEntityId,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
    String? reason,
  }) async {
    final writer = auditWriter;
    if (writer != null) {
      await writer.record(
        entityType: entityType,
        entityId: entityId,
        action: action,
        summary: summary,
        source: source,
        parentEntityType: parentEntityType,
        parentEntityId: parentEntityId,
        oldValues: oldValues,
        newValues: newValues,
        reason: reason,
        isSystemEvent: source != 'ui',
      );
      return;
    }
    await auditLogRepo?.recordEvent(
      entityType: entityType,
      entityId: entityId,
      action: action,
      summary: summary,
      source: source,
      parentEntityType: parentEntityType,
      parentEntityId: parentEntityId,
      oldValues: oldValues,
      newValues: newValues,
      reason: reason,
      isSystemEvent: source != 'ui',
    );
  }
}
