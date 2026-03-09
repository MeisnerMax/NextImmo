import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/audit_log_repo.dart';
import 'package:neximmo_app/data/repositories/imports_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('imports properties from csv via saved mapping', () async {
    final repo = ImportsRepository(db, auditLogRepo: AuditLogRepo(db));
    final csvFile = await File(
      '${Directory.systemTemp.path}/neximmo_import_test_${DateTime.now().millisecondsSinceEpoch}.csv',
    ).create(recursive: true);
    await csvFile.writeAsString(
      'name,address,zip,city,country,type,units\n'
      'Demo House,Street 1,10115,Berlin,DE,single_family,1\n',
    );

    final job = await repo.createJob(kind: 'csv', targetScope: 'global');
    await repo.saveMapping(
      importJobId: job.id,
      targetTable: 'properties',
      mapping: const <String, String>{
        'name': 'name',
        'address_line1': 'address',
        'zip': 'zip',
        'city': 'city',
        'country': 'country',
        'property_type': 'type',
        'units': 'units',
      },
    );

    final imported = await repo.runCsvImport(
      jobId: job.id,
      csvPath: csvFile.path,
    );
    expect(imported, 1);

    final rows = await db.query('properties');
    expect(rows.length, 1);
    expect(rows.first['name'], 'Demo House');

    await csvFile.delete();
  });

  test('imports ledger entries and auto-creates unknown accounts', () async {
    final auditRepo = AuditLogRepo(db);
    final repo = ImportsRepository(db, auditLogRepo: auditRepo);
    final csvFile = await File(
      '${Directory.systemTemp.path}/neximmo_ledger_import_test_${DateTime.now().millisecondsSinceEpoch}.csv',
    ).create(recursive: true);
    await csvFile.writeAsString(
      'posted,account,kind,direction,amount,currency,entity_type,entity_id,memo\n'
      '2026-03-01,Rent,income,in,1500,EUR,property,p1,March rent\n',
    );

    final job = await repo.createJob(kind: 'csv', targetScope: 'global');
    await repo.saveMapping(
      importJobId: job.id,
      targetTable: 'ledger_entries',
      mapping: const <String, String>{
        'posted_at': 'posted',
        'account_name': 'account',
        'account_kind': 'kind',
        'direction': 'direction',
        'amount': 'amount',
        'currency_code': 'currency',
        'entity_type': 'entity_type',
        'entity_id': 'entity_id',
        'memo': 'memo',
        '__auto_create_accounts': '1',
      },
    );

    final imported = await repo.runCsvImport(
      jobId: job.id,
      csvPath: csvFile.path,
    );
    expect(imported, 1);

    final accounts = await db.query('ledger_accounts');
    expect(accounts.length, 1);
    expect(accounts.first['name'], 'Rent');
    final entries = await db.query('ledger_entries');
    expect(entries.length, 1);
    expect(entries.first['direction'], 'in');
    expect(entries.first['period_key'], '2026-03');
    final audits = await auditRepo.list(entityType: 'import_job');
    expect(audits.where((e) => e.action == 'import'), isNotEmpty);
    expect(
      audits.any(
        (event) =>
            event.action == 'create' || event.entityType == 'import_mapping',
      ),
      isTrue,
    );

    await csvFile.delete();
  });

  test('failed import writes structured audit failure event', () async {
    final auditRepo = AuditLogRepo(db);
    final repo = ImportsRepository(db, auditLogRepo: auditRepo);

    final job = await repo.createJob(kind: 'csv', targetScope: 'global');

    await expectLater(
      repo.runCsvImport(jobId: job.id, csvPath: 'C:/does/not/exist.csv'),
      throwsA(isA<StateError>()),
    );

    final audits = await auditRepo.list(entityType: 'import_job', entityId: job.id);
    final failure = audits.firstWhere((event) => event.action == 'import');
    expect(failure.source, 'import');
    expect(failure.newValues?['status'], 'failed');
  });
}
