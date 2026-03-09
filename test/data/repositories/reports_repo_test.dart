import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/report_templates.dart';
import 'package:neximmo_app/data/repositories/reports_repo.dart';
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

  test(
    'enforces unique template names and supports default template lookup',
    () async {
      final repo = ReportsRepository(db);
      final now = DateTime.now().millisecondsSinceEpoch;

      final first = ReportTemplateRecord(
        id: 't1',
        name: 'Investor Pack',
        includeOverview: true,
        includeInputs: true,
        includeCashflowTable: true,
        includeAmortization: true,
        includeSensitivity: false,
        includeEsg: false,
        includeComps: false,
        includeCriteria: true,
        includeOffer: true,
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      );
      await repo.upsertTemplate(first);
      await repo.setDefaultTemplate(first.id);

      final defaultTemplate = await repo.getDefaultTemplate();
      expect(defaultTemplate?.id, first.id);

      final duplicate = ReportTemplateRecord(
        id: 't2',
        name: 'investor pack',
        includeOverview: true,
        includeInputs: true,
        includeCashflowTable: true,
        includeAmortization: true,
        includeSensitivity: false,
        includeEsg: false,
        includeComps: false,
        includeCriteria: true,
        includeOffer: true,
        isDefault: false,
        createdAt: now,
        updatedAt: now,
      );

      expect(() => repo.upsertTemplate(duplicate), throwsA(isA<StateError>()));
    },
  );
}
