import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/data/repositories/inputs_repo.dart';
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

  test('saving and reloading settings keeps values', () async {
    final repo = InputsRepository(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    final settings = AppSettingsRecord(
      id: 1,
      currencyCode: 'USD',
      locale: 'en_US',
      uiLanguageCode: 'de',
      defaultHorizonYears: 12,
      defaultVacancyPercent: 0.07,
      defaultManagementPercent: 0.09,
      defaultMaintenancePercent: 0.06,
      defaultCapexPercent: 0.04,
      defaultAppreciationPercent: 0.03,
      defaultRentGrowthPercent: 0.025,
      defaultExpenseGrowthPercent: 0.02,
      defaultSaleCostPercent: 0.05,
      defaultClosingCostBuyPercent: 0.02,
      defaultClosingCostSellPercent: 0.015,
      defaultDownPaymentPercent: 0.3,
      defaultInterestRatePercent: 0.055,
      defaultTermYears: 25,
      defaultReportTemplateId: 'template-1',
      compareVisibleMetrics: const <String>['cap_rate', 'cash_on_cash'],
      updatedAt: now,
    );

    await repo.updateSettings(settings);
    final loaded = await repo.getSettings();

    expect(loaded.currencyCode, settings.currencyCode);
    expect(loaded.locale, settings.locale);
    expect(loaded.uiLanguageCode, settings.uiLanguageCode);
    expect(loaded.defaultHorizonYears, settings.defaultHorizonYears);
    expect(
      loaded.defaultDownPaymentPercent,
      settings.defaultDownPaymentPercent,
    );
    expect(
      loaded.defaultInterestRatePercent,
      settings.defaultInterestRatePercent,
    );
    expect(loaded.defaultTermYears, settings.defaultTermYears);
    expect(
      loaded.compareVisibleMetrics,
      equals(settings.compareVisibleMetrics),
    );
    expect(loaded.defaultReportTemplateId, settings.defaultReportTemplateId);
  });
}
