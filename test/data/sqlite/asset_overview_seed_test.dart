import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/data/sqlite/seed/asset_overview_seed_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the portfolio baseline that migration V48 seeds from
/// `Asset_Overview_v4.xlsx`. The expectations below are transcribed from the
/// workbook's Dashboard and master sheets, so a regenerated seed that silently
/// drops or duplicates rows fails here.
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

  Future<int> countOf(String table, {String? where, List<Object?>? args}) async {
    final rows = await db.query(table, where: where, whereArgs: args);
    return rows.length;
  }

  test('seeds every asset from the workbook master sheet', () async {
    final rows = await db.query('properties', orderBy: 'id');
    final ids = rows.map((row) => row['id']).toList();

    expect(ids, hasLength(19));
    expect(ids.first, 'A001');
    expect(ids, contains('A022'));

    // The Dashboard counts nine active assets.
    final active = rows.where((row) => row['archived'] == 0);
    expect(active, hasLength(9));
  });

  test('drops assets that the current workbook no longer lists', () async {
    for (final retired in AssetOverviewSeedData.retiredPropertyIds) {
      expect(
        await countOf('properties', where: 'id = ?', args: <Object?>[retired]),
        0,
        reason: '$retired was retired by the v4 workbook',
      );
    }
  });

  test('maps asset master data onto the property record', () async {
    final rows = await db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>['A001'],
    );
    expect(rows, hasLength(1));

    final property = rows.single;
    expect(property['name'], 'Allee 7');
    expect(property['property_type'], 'multifamily');
    expect(property['address_line1'], 'Allee 7');
    expect(property['zip'], '96450');
    expect(property['city'], 'Coburg');
    expect(property['country'], 'Germany');
    expect(property['year_built'], 1862);
    expect(property['units'], 16);
    expect((property['sqft']! as num).toDouble(), closeTo(2050.84, 0.001));
    expect(property['archived'], 0);
    expect(property['deleted_at'], isNull);
  });

  test('stores property types the app recognises, never "other"', () async {
    final rows = await db.query('properties', columns: <String>['id', 'property_type']);
    final byId = <String, String>{
      for (final row in rows) row['id']! as String: row['property_type']! as String,
    };

    // These must match the canonical values in propertyKindFromType so the UI
    // shows Vermietungsobjekt / Gemischt genutzt / Hotel instead of "Sonstiges".
    expect(byId['A001'], 'multifamily'); // Apartment building
    expect(byId['A002'], 'residential'); // Residential building
    expect(byId['A003'], 'mixed'); // Mixed object
    expect(byId['A004'], 'hotel'); // Hotel
    expect(byId['A017'], 'commercial'); // Commercial building
    expect(byId['A019'], 'commercial'); // Commercial (Kiosk)

    const recognised = <String>{
      'multifamily',
      'residential',
      'mixed',
      'hotel',
      'commercial',
    };
    expect(
      byId.values.every(recognised.contains),
      isTrue,
      reason: 'no asset should fall back to the generic "other" type',
    );
  });

  test('fills the structured overview fields from the workbook', () async {
    final rows = await db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>['A003'],
    );
    final property = rows.single;

    // A003 is a mixed object: 983.5 m² residential + 312 m² commercial from the
    // rent roll, purchased for 214,331 € by the portfolio company.
    expect(property['owner_company'], '613 Investment Group GmbH');
    expect((property['purchase_price']! as num).toDouble(), closeTo(214331, 0.001));
    expect((property['residential_area']! as num).toDouble(), closeTo(983.5, 0.01));
    expect((property['commercial_area']! as num).toDouble(), closeTo(312, 0.01));

    // A commercial object records its area on the commercial side only.
    final commercial = (await db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>['A017'],
    )).single;
    expect((commercial['commercial_area']! as num).toDouble(), closeTo(6620, 0.01));
    expect(commercial['residential_area'], isNull);
  });

  test('seeds the rent roll with the workbook occupancy split', () async {
    // Dashboard: 12 rented units, 6 empty.
    expect(await countOf('units'), 18);
    expect(await countOf('units', where: "status = 'occupied'"), 12);
    expect(await countOf('units', where: "status = 'vacant'"), 6);
  });

  test('derives lease charges so warm rent reconciles', () async {
    final rows = await db.query(
      'leases',
      where: 'unit_id = ?',
      whereArgs: <Object?>['asset_overview_unit_006'],
    );
    expect(rows, hasLength(1));

    // A003 / 3. OG Left: 440 cold + 56 ancillary + 112 heating = 608 warm.
    final lease = rows.single;
    expect((lease['base_rent_monthly']! as num).toDouble(), closeTo(440, 0.001));
    expect(
      (lease['ancillary_charges_monthly']! as num).toDouble(),
      closeTo(56, 0.001),
    );
    expect(
      (lease['parking_other_charges_monthly']! as num).toDouble(),
      closeTo(112, 0.001),
    );
  });

  test('every lease points at a seeded unit and tenant', () async {
    final orphans = await db.rawQuery('''
      SELECT l.id FROM leases l
      LEFT JOIN units u ON u.id = l.unit_id
      LEFT JOIN tenants t ON t.id = l.tenant_id
      WHERE u.id IS NULL OR t.id IS NULL
    ''');
    expect(orphans, isEmpty);
    expect(await countOf('leases'), 12);
  });

  test('records 2026 rent payments against the rent roll', () async {
    final rows = await db.query(
      'rental_income_plans',
      where: 'property_id = ? AND unit_code = ?',
      whereArgs: <Object?>['A002', 'Flat 8'],
    );
    expect(rows, hasLength(1));

    // Steen paid 302.76 for May, June and July 2026.
    final plan = rows.single;
    expect((plan['month_5']! as num).toDouble(), closeTo(302.76, 0.001));
    expect((plan['month_7']! as num).toDouble(), closeTo(302.76, 0.001));
    expect((plan['month_8']! as num).toDouble(), 0);
    expect(plan['year'], 2026);
  });

  test('splits operating costs across the three workbook scopes', () async {
    expect(await countOf('asset_operating_costs', where: "scope = 'unit'"),
        greaterThan(0));
    expect(await countOf('asset_operating_costs', where: "scope = 'building'"),
        greaterThan(0));
    expect(await countOf('asset_operating_costs', where: "scope = 'insurance'"),
        greaterThan(0));

    final buildingInsurance = await db.query(
      'asset_operating_costs',
      where: 'property_id = ? AND scope = ? AND cost_type = ?',
      whereArgs: <Object?>['A001', 'insurance', 'Gebäudeversicherung'],
    );
    expect(buildingInsurance, hasLength(1));
    expect(
      (buildingInsurance.single['yearly_amount']! as num).toDouble(),
      closeTo(14797.24, 0.001),
    );
  });

  test('seeds hotel KPIs only for periods that carry data', () async {
    final rows = await db.query(
      'hotel_kpis',
      where: 'property_id = ?',
      whereArgs: <Object?>['A005'],
      orderBy: 'period_key',
    );

    // Hahnmühle reported January through June 2026.
    expect(rows, hasLength(6));
    expect(rows.first['period_key'], '2026-01');
    expect(rows.first['rooms_total'], 19);
    expect((rows.first['adr']! as num).toDouble(), closeTo(69.07, 0.001));
  });

  test('seeds the monthly hotel P&L (revenue, costs, profit)', () async {
    final january = (await db.query(
      'hotel_kpis',
      where: 'property_id = ? AND period_key = ?',
      whereArgs: <Object?>['A005', '2026-01'],
    )).single;

    // Hahnmühle January: 15,747.96 € revenue − 8,510.00 € costs = 7,237.97 €.
    expect(
      (january['total_revenue']! as num).toDouble(),
      closeTo(15747.96, 0.01),
    );
    expect((january['total_costs']! as num).toDouble(), closeTo(8510.00, 0.01));
    expect((january['profit_loss']! as num).toDouble(), closeTo(7237.97, 0.01));

    // Profit must reconcile with revenue minus costs for every seeded period.
    final all = await db.query('hotel_kpis');
    for (final kpi in all) {
      final revenue = (kpi['total_revenue'] as num?)?.toDouble();
      final costs = (kpi['total_costs'] as num?)?.toDouble();
      final profit = (kpi['profit_loss'] as num?)?.toDouble();
      if (revenue != null && costs != null && profit != null) {
        expect(
          profit,
          closeTo(revenue - costs, 0.02),
          reason: 'P&L for ${kpi['id']} does not reconcile',
        );
      }
    }
  });

  test('seeds renovation projects with workbook status labels', () async {
    final rows = await db.query('renovation_projects', orderBy: 'project_code');
    expect(rows, hasLength(10));

    final first = rows.first;
    expect(first['project_code'], 'R001');
    expect(first['property_id'], 'A001');
    expect(first['status'], 'Gestartet');
  });

  test('records the workbook market values as KPI snapshots', () async {
    final rows = await db.query(
      'property_kpi_snapshots',
      where: 'property_id = ?',
      whereArgs: <Object?>['A001'],
      orderBy: 'period_date',
    );
    expect(rows, hasLength(2));
    expect(rows.first['period_date'], '2021-12-31');
    expect(
      (rows.first['valuation']! as num).toDouble(),
      closeTo(3200000, 0.001),
    );
    expect(
      (rows.last['valuation']! as num).toDouble(),
      closeTo(9330000, 0.001),
    );
  });

  group('reconciles with the workbook Dashboard', () {
    Future<double> sumOf(String sql, [List<Object?>? args]) async {
      final rows = await db.rawQuery(sql, args);
      return ((rows.single.values.first as num?) ?? 0).toDouble();
    }

    test('monthly cold and warm rent', () async {
      final cold = await sumOf(
        'SELECT SUM(base_rent_monthly) FROM leases',
      );
      expect(cold, closeTo(9853.21, 0.01));

      final warm = await sumOf('''
        SELECT SUM(
          base_rent_monthly
          + COALESCE(ancillary_charges_monthly, 0)
          + COALESCE(parking_other_charges_monthly, 0)
        ) FROM leases
      ''');
      expect(warm, closeTo(12881.31, 0.01));
    });

    test('monthly insurance and building side costs', () async {
      final insurance = await sumOf(
        "SELECT SUM(monthly_amount) FROM asset_operating_costs WHERE scope = 'insurance'",
      );
      expect(insurance, closeTo(4250.87, 0.01));

      final building = await sumOf(
        "SELECT SUM(monthly_amount) FROM asset_operating_costs WHERE scope = 'building'",
      );
      expect(building, closeTo(728.91, 0.01));
    });

    test('hotel year-to-date revenue', () async {
      // Hahnmühle 125,284.08 € and Square 118,342.06 € revenue YTD.
      final hahnmuehle = await sumOf(
        "SELECT SUM(total_revenue) FROM hotel_kpis WHERE property_id = 'A005'",
      );
      expect(hahnmuehle, closeTo(125284.08, 0.01));

      final square = await sumOf(
        "SELECT SUM(total_revenue) FROM hotel_kpis WHERE property_id = 'A010'",
      );
      expect(square, closeTo(118342.06, 0.01));
    });

    test('hotel year-to-date costs and profit', () async {
      // Dashboard: Hahnmühle 61,200.335 € costs / 64,083.745 € profit YTD;
      // Square 56,088.765 € costs / 62,253.295 € profit YTD.
      final hahnCosts = await sumOf(
        "SELECT SUM(total_costs) FROM hotel_kpis WHERE property_id = 'A005'",
      );
      expect(hahnCosts, closeTo(61200.34, 0.01));
      final hahnProfit = await sumOf(
        "SELECT SUM(profit_loss) FROM hotel_kpis WHERE property_id = 'A005'",
      );
      expect(hahnProfit, closeTo(64083.75, 0.02));

      final squareCosts = await sumOf(
        "SELECT SUM(total_costs) FROM hotel_kpis WHERE property_id = 'A010'",
      );
      expect(squareCosts, closeTo(56088.77, 0.01));
      final squareProfit = await sumOf(
        "SELECT SUM(profit_loss) FROM hotel_kpis WHERE property_id = 'A010'",
      );
      expect(squareProfit, closeTo(62253.30, 0.01));
    });
  });

  test('leaves no rows behind from earlier workbook revisions', () async {
    // The pre-v4 seed used these ids; the purge in V48 must have removed them.
    for (final staleId in <String>[
      'asset_overview_cost_001',
      'asset_overview_reno_001',
      'asset_overview_unit_020',
    ]) {
      expect(
        await countOf(
          'asset_operating_costs',
          where: 'id = ?',
          args: <Object?>[staleId],
        ),
        0,
      );
    }

    final seededCosts = await countOf(
      'asset_operating_costs',
      where: "id LIKE 'asset_overview_%'",
    );
    expect(seededCosts, AssetOverviewSeedData.operatingCosts.length);
  });
}
