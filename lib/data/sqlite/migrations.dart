import 'package:sqflite_common_ffi/sqflite_ffi.dart';


class DbMigrations {
  static const int currentVersion = 48;

  static Future<void> onCreate(Database db, int version) async {
    await _createV1(db);
    await _createV2(db);
    await _createV3(db);
    await _createV4(db);
    await _createV5(db);
    await _createV6(db);
    await _createV7(db);
    await _createV8(db);
    await _createV9(db);
    await _createV10(db);
    await _createV11(db);
    await _createV12(db);
    await _createV13(db);
    await _createV14(db);
    await _createV15(db);
    await _createV16(db);
    await _createV17(db);
    await _createV18(db);
    await _createV19(db);
    await _createV20(db);
    await _createV21(db);
    await _createV22(db);
    await _createV23(db);
    await _createV24(db);
    await _createV25(db);
    await _createV26(db);
    await _createV27(db);
    await _createV28(db);
    await _createV29(db);
    await _createV30(db);
    await _createV31(db);
    await _createV32(db);
    await _createV33(db);
    await _createV34(db);
    await _createV35(db);
    await _createV36(db);
    await _createV37(db);
    await _createV38(db);
    await _createV39(db);
    await _createV40(db);
    await _createV41(db);
    await _createV42(db);
    await _createV43(db);
    await _createV44(db);
    await _createV45(db);
    await _createV46(db);
    await _createV47(db);
    await _createV48(db);
  }

  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1) {
      await _createV1(db);
    }
    if (oldVersion < 2) {
      await _createV2(db);
    }
    if (oldVersion < 3) {
      await _createV3(db);
    }
    if (oldVersion < 4) {
      await _createV4(db);
    }
    if (oldVersion < 5) {
      await _createV5(db);
    }
    if (oldVersion < 6) {
      await _createV6(db);
    }
    if (oldVersion < 7) {
      await _createV7(db);
    }
    if (oldVersion < 8) {
      await _createV8(db);
    }
    if (oldVersion < 9) {
      await _createV9(db);
    }
    if (oldVersion < 10) {
      await _createV10(db);
    }
    if (oldVersion < 11) {
      await _createV11(db);
    }
    if (oldVersion < 12) {
      await _createV12(db);
    }
    if (oldVersion < 13) {
      await _createV13(db);
    }
    if (oldVersion < 14) {
      await _createV14(db);
    }
    if (oldVersion < 15) {
      await _createV15(db);
    }
    if (oldVersion < 16) {
      await _createV16(db);
    }
    if (oldVersion < 17) {
      await _createV17(db);
    }
    if (oldVersion < 18) {
      await _createV18(db);
    }
    if (oldVersion < 19) {
      await _createV19(db);
    }
    if (oldVersion < 20) {
      await _createV20(db);
    }
    if (oldVersion < 21) {
      await _createV21(db);
    }
    if (oldVersion < 22) {
      await _createV22(db);
    }
    if (oldVersion < 23) {
      await _createV23(db);
    }
    if (oldVersion < 24) {
      await _createV24(db);
    }
    if (oldVersion < 25) {
      await _createV25(db);
    }
    if (oldVersion < 26) {
      await _createV26(db);
    }
    if (oldVersion < 27) {
      await _createV27(db);
    }
    if (oldVersion < 28) {
      await _createV28(db);
    }
    if (oldVersion < 29) {
      await _createV29(db);
    }
    if (oldVersion < 30) {
      await _createV30(db);
    }
    if (oldVersion < 31) {
      await _createV31(db);
    }
    if (oldVersion < 32) {
      await _createV32(db);
    }
    if (oldVersion < 33) {
      await _createV33(db);
    }
    if (oldVersion < 34) {
      await _createV34(db);
    }
    if (oldVersion < 35) {
      await _createV35(db);
    }
    if (oldVersion < 36) {
      await _createV36(db);
    }
    if (oldVersion < 37) {
      await _createV37(db);
    }
    if (oldVersion < 38) {
      await _createV38(db);
    }
    if (oldVersion < 39) {
      await _createV39(db);
    }
    if (oldVersion < 40) {
      await _createV40(db);
    }
    if (oldVersion < 41) {
      await _createV41(db);
    }
    if (oldVersion < 42) {
      await _createV42(db);
    }
    if (oldVersion < 43) {
      await _createV43(db);
    }
    if (oldVersion < 44) {
      await _createV44(db);
    }
    if (oldVersion < 45) {
      await _createV45(db);
    }
    if (oldVersion < 46) {
      await _createV46(db);
    }
    if (oldVersion < 47) {
      await _createV47(db);
    }
    if (oldVersion < 48) {
      await _createV48(db);
    }
  }

  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        email TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        id INTEGER PRIMARY KEY,
        currency_code TEXT NOT NULL,
        locale TEXT NOT NULL,
        ui_language_code TEXT NOT NULL DEFAULT 'en',
        default_horizon_years INTEGER NOT NULL,
        default_vacancy_percent REAL NOT NULL,
        default_management_percent REAL NOT NULL,
        default_maintenance_percent REAL NOT NULL,
        default_capex_percent REAL NOT NULL,
        default_appreciation_percent REAL NOT NULL,
        default_rent_growth_percent REAL NOT NULL,
        default_expense_growth_percent REAL NOT NULL,
        default_sale_cost_percent REAL NOT NULL,
        default_closing_cost_buy_percent REAL NOT NULL,
        default_closing_cost_sell_percent REAL NOT NULL,
        default_down_payment_percent REAL NOT NULL,
        default_interest_rate_percent REAL NOT NULL,
        default_term_years INTEGER NOT NULL,
        default_report_template_id TEXT,
        compare_visible_metrics TEXT NOT NULL,
        enable_demo_seed INTEGER NOT NULL DEFAULT 0,
        notification_vacancy_threshold REAL,
        notification_noi_drop_threshold REAL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS properties (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        address_line1 TEXT NOT NULL,
        address_line2 TEXT,
        zip TEXT NOT NULL,
        city TEXT NOT NULL,
        country TEXT NOT NULL,
        property_type TEXT NOT NULL,
        units INTEGER NOT NULL,
        sqft REAL,
        year_built INTEGER,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS scenarios (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        name TEXT NOT NULL,
        strategy_type TEXT NOT NULL,
        scenario_case_type TEXT NOT NULL DEFAULT 'base',
        is_base INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS scenario_inputs (
        scenario_id TEXT PRIMARY KEY,
        purchase_price REAL NOT NULL,
        rehab_budget REAL NOT NULL,
        closing_cost_buy_percent REAL NOT NULL,
        closing_cost_buy_fixed REAL NOT NULL,
        hold_months INTEGER NOT NULL,
        rent_monthly_total REAL NOT NULL,
        gross_area_sqm REAL NOT NULL DEFAULT 0,
        lettable_area_sqm REAL NOT NULL DEFAULT 0,
        residential_area_sqm REAL NOT NULL DEFAULT 0,
        commercial_area_sqm REAL NOT NULL DEFAULT 0,
        other_income_monthly REAL NOT NULL,
        vacancy_percent REAL NOT NULL,
        property_tax_monthly REAL NOT NULL,
        insurance_monthly REAL NOT NULL,
        utilities_monthly REAL NOT NULL,
        hoa_monthly REAL NOT NULL,
        management_percent REAL NOT NULL,
        maintenance_percent REAL NOT NULL,
        capex_percent REAL NOT NULL,
        other_expenses_monthly REAL NOT NULL,
        financing_mode TEXT NOT NULL,
        down_payment_percent REAL NOT NULL,
        loan_amount REAL NOT NULL,
        interest_rate_percent REAL NOT NULL,
        term_years INTEGER NOT NULL,
        amortization_type TEXT NOT NULL,
        appreciation_percent REAL NOT NULL,
        rent_growth_percent REAL NOT NULL,
        expense_growth_percent REAL NOT NULL,
        sale_cost_percent REAL NOT NULL,
        closing_cost_sell_percent REAL NOT NULL,
        sell_after_years INTEGER NOT NULL,
        arv_override REAL,
        rent_override REAL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (scenario_id) REFERENCES scenarios(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS expense_lines (
        id TEXT PRIMARY KEY,
        scenario_id TEXT NOT NULL,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        amount_monthly REAL NOT NULL,
        percent REAL NOT NULL,
        enabled INTEGER NOT NULL,
        FOREIGN KEY (scenario_id) REFERENCES scenarios(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS income_lines (
        id TEXT PRIMARY KEY,
        scenario_id TEXT NOT NULL,
        name TEXT NOT NULL,
        amount_monthly REAL NOT NULL,
        enabled INTEGER NOT NULL,
        FOREIGN KEY (scenario_id) REFERENCES scenarios(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS comps_sales (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        address TEXT NOT NULL,
        price REAL NOT NULL,
        sqft REAL,
        beds REAL,
        baths REAL,
        distance_km REAL,
        sold_date INTEGER,
        selected INTEGER NOT NULL,
        weight REAL NOT NULL,
        source TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS comps_rentals (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        address TEXT NOT NULL,
        rent_monthly REAL NOT NULL,
        sqft REAL,
        beds REAL,
        baths REAL,
        distance_km REAL,
        listed_date INTEGER,
        selected INTEGER NOT NULL,
        weight REAL NOT NULL,
        source TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS criteria_sets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        is_default INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS criteria_rules (
        id TEXT PRIMARY KEY,
        criteria_set_id TEXT NOT NULL,
        field_key TEXT NOT NULL,
        operator TEXT NOT NULL,
        target_value REAL NOT NULL,
        unit TEXT NOT NULL,
        severity TEXT NOT NULL,
        enabled INTEGER NOT NULL,
        FOREIGN KEY (criteria_set_id) REFERENCES criteria_sets(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS report_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        include_overview INTEGER NOT NULL,
        include_inputs INTEGER NOT NULL,
        include_cashflow_table INTEGER NOT NULL,
        include_amortization INTEGER NOT NULL,
        include_sensitivity INTEGER NOT NULL,
        include_esg INTEGER NOT NULL,
        include_comps INTEGER NOT NULL,
        include_criteria INTEGER NOT NULL,
        include_offer INTEGER NOT NULL,
        report_title TEXT,
        report_disclaimer TEXT,
        investor_name TEXT,
        is_default INTEGER NOT NULL,
        branding_name TEXT,
        branding_company TEXT,
        branding_email TEXT,
        branding_phone TEXT,
        branding_logo_path TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS reports (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        scenario_id TEXT NOT NULL,
        template_id TEXT NOT NULL,
        pdf_path TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id),
        FOREIGN KEY (scenario_id) REFERENCES scenarios(id),
        FOREIGN KEY (template_id) REFERENCES report_templates(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scenarios_property_id ON scenarios(property_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_income_lines_scenario_id ON income_lines(scenario_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expense_lines_scenario_id ON expense_lines(scenario_id)',
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('app_settings', <String, Object?>{
      'id': 1,
      'currency_code': 'EUR',
      'locale': 'de_DE',
      'ui_language_code': 'en',
      'default_horizon_years': 10,
      'default_vacancy_percent': 0.05,
      'default_management_percent': 0.08,
      'default_maintenance_percent': 0.05,
      'default_capex_percent': 0.05,
      'default_appreciation_percent': 0.02,
      'default_rent_growth_percent': 0.02,
      'default_expense_growth_percent': 0.02,
      'default_sale_cost_percent': 0.06,
      'default_closing_cost_buy_percent': 0.03,
      'default_closing_cost_sell_percent': 0.02,
      'default_down_payment_percent': 0.25,
      'default_interest_rate_percent': 0.06,
      'default_term_years': 30,
      'default_report_template_id': null,
      'compare_visible_metrics':
          'monthly_cashflow,cap_rate,cash_on_cash,irr,dscr',
      'enable_demo_seed': 0,
      'notification_vacancy_threshold': null,
      'notification_noi_drop_threshold': null,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS property_criteria_overrides (
        property_id TEXT PRIMARY KEY,
        criteria_set_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE,
        FOREIGN KEY (criteria_set_id) REFERENCES criteria_sets(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_property_criteria_override_set ON property_criteria_overrides(criteria_set_id)',
    );
  }

  static Future<void> _createV3(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'default_down_payment_percent',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN default_down_payment_percent REAL NOT NULL DEFAULT 0.25',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'default_interest_rate_percent',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN default_interest_rate_percent REAL NOT NULL DEFAULT 0.06',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'default_term_years',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN default_term_years INTEGER NOT NULL DEFAULT 30',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'default_report_template_id',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN default_report_template_id TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'compare_visible_metrics',
      alterSql:
          "ALTER TABLE app_settings ADD COLUMN compare_visible_metrics TEXT NOT NULL DEFAULT 'monthly_cashflow,cap_rate,cash_on_cash,irr,dscr'",
    );

    await _addColumnIfMissing(
      db,
      table: 'report_templates',
      column: 'include_esg',
      alterSql:
          'ALTER TABLE report_templates ADD COLUMN include_esg INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      table: 'report_templates',
      column: 'include_sensitivity',
      alterSql:
          'ALTER TABLE report_templates ADD COLUMN include_sensitivity INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      table: 'report_templates',
      column: 'report_title',
      alterSql: 'ALTER TABLE report_templates ADD COLUMN report_title TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'report_templates',
      column: 'report_disclaimer',
      alterSql:
          'ALTER TABLE report_templates ADD COLUMN report_disclaimer TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'report_templates',
      column: 'investor_name',
      alterSql: 'ALTER TABLE report_templates ADD COLUMN investor_name TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'report_templates',
      column: 'is_default',
      alterSql:
          'ALTER TABLE report_templates ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0',
    );

    await _dedupeNames(db, table: 'criteria_sets');
    await _dedupeNames(db, table: 'report_templates');

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_criteria_sets_name_unique ON criteria_sets(name COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_report_templates_name_unique ON report_templates(name COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_criteria_sets_single_default ON criteria_sets(is_default) WHERE is_default = 1',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_report_templates_single_default ON report_templates(is_default) WHERE is_default = 1',
    );
  }

  static Future<void> _createV4(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'enable_demo_seed',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN enable_demo_seed INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'notification_vacancy_threshold',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN notification_vacancy_threshold REAL',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'notification_noi_drop_threshold',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN notification_noi_drop_threshold REAL',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS portfolios (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS portfolio_properties (
        portfolio_id TEXT NOT NULL,
        property_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (portfolio_id, property_id),
        FOREIGN KEY (portfolio_id) REFERENCES portfolios(id) ON DELETE CASCADE,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS property_profiles (
        property_id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        units_count_override INTEGER,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS property_kpi_snapshots (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        scenario_id TEXT,
        period_date TEXT NOT NULL,
        noi REAL,
        occupancy REAL,
        capex REAL,
        valuation REAL,
        source TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE,
        FOREIGN KEY (scenario_id) REFERENCES scenarios(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        text TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        created_by TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        message TEXT NOT NULL,
        due_at INTEGER,
        read_at INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS esg_profiles (
        property_id TEXT PRIMARY KEY,
        epc_rating TEXT,
        epc_valid_until INTEGER,
        emissions_kgco2_m2 REAL,
        last_audit_date INTEGER,
        target_rating TEXT,
        notes TEXT,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS import_jobs (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        target_scope TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        finished_at INTEGER,
        error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS import_mappings (
        id TEXT PRIMARY KEY,
        import_job_id TEXT NOT NULL,
        target_table TEXT NOT NULL,
        mapping_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (import_job_id) REFERENCES import_jobs(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_portfolios_name_unique ON portfolios(name COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_portfolio_properties_property ON portfolio_properties(property_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_property_kpi_snapshots_property ON property_kpi_snapshots(property_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_entity ON notes(entity_type, entity_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notifications_entity ON notifications(entity_type, entity_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notifications_read_at ON notifications(read_at)',
    );
  }

  static Future<void> _createV5(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'workspace_root_path',
      alterSql: 'ALTER TABLE app_settings ADD COLUMN workspace_root_path TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'last_backup_at',
      alterSql: 'ALTER TABLE app_settings ADD COLUMN last_backup_at INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'last_backup_path',
      alterSql: 'ALTER TABLE app_settings ADD COLUMN last_backup_path TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'last_task_generation_at',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN last_task_generation_at INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'task_due_soon_days',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN task_due_soon_days INTEGER NOT NULL DEFAULT 3',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'enable_task_notifications',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN enable_task_notifications INTEGER NOT NULL DEFAULT 1',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ledger_accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_ledger_accounts_name_unique ON ledger_accounts(name COLLATE NOCASE)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ledger_entries (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        account_id TEXT NOT NULL,
        posted_at INTEGER NOT NULL,
        period_key TEXT NOT NULL,
        direction TEXT NOT NULL,
        amount REAL NOT NULL,
        currency_code TEXT NOT NULL,
        counterparty TEXT,
        memo TEXT,
        document_id TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (account_id) REFERENCES ledger_accounts(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ledger_entries_entity_period ON ledger_entries(entity_type, entity_id, period_key)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ledger_entries_account_period ON ledger_entries(account_id, period_key)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ledger_entries_posted_at ON ledger_entries(posted_at)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS search_index (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        title TEXT NOT NULL,
        subtitle TEXT,
        body TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_search_index_type_entity ON search_index(entity_type, entity_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_search_index_updated_at ON search_index(updated_at)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        title TEXT NOT NULL,
        description TEXT,
        category TEXT,
        assigned_to TEXT,
        estimated_cost REAL,
        status TEXT NOT NULL,
        priority TEXT NOT NULL,
        due_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        created_by TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_status_due ON tasks(status, due_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_entity ON tasks(entity_type, entity_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_checklist_items (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        text TEXT NOT NULL,
        position INTEGER NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_task_checklist_task ON task_checklist_items(task_id, position)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'general',
        assignee_group TEXT NOT NULL DEFAULT 'asset_management',
        property_type TEXT NOT NULL DEFAULT 'all',
        default_title TEXT NOT NULL,
        default_priority TEXT NOT NULL,
        default_due_days_offset INTEGER,
        recurrence_rule TEXT NOT NULL,
        recurrence_interval INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_task_templates_name_unique ON task_templates(name COLLATE NOCASE)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_template_checklist_items (
        id TEXT PRIMARY KEY,
        template_id TEXT NOT NULL,
        text TEXT NOT NULL,
        position INTEGER NOT NULL,
        FOREIGN KEY (template_id) REFERENCES task_templates(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_task_template_checklist_template ON task_template_checklist_items(template_id, position)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_generated_instances (
        id TEXT PRIMARY KEY,
        generated_key TEXT NOT NULL,
        template_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        period_key TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (template_id) REFERENCES task_templates(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_task_generated_instances_key_unique ON task_generated_instances(generated_key)',
    );
  }

  static Future<void> _createV6(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS units (
        id TEXT PRIMARY KEY,
        asset_property_id TEXT NOT NULL,
        unit_code TEXT NOT NULL,
        unit_type TEXT,
        beds REAL,
        baths REAL,
        sqft REAL,
        floor TEXT,
        status TEXT NOT NULL,
        market_rent_monthly REAL,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (asset_property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_units_asset_code_unique ON units(asset_property_id, unit_code)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_units_asset_status ON units(asset_property_id, status)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tenants (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        legal_name TEXT,
        email TEXT,
        phone TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS leases (
        id TEXT PRIMARY KEY,
        asset_property_id TEXT NOT NULL,
        unit_id TEXT NOT NULL,
        tenant_id TEXT,
        lease_name TEXT NOT NULL,
        start_date INTEGER NOT NULL,
        end_date INTEGER,
        move_in_date INTEGER,
        move_out_date INTEGER,
        status TEXT NOT NULL,
        base_rent_monthly REAL NOT NULL,
        currency_code TEXT NOT NULL,
        security_deposit REAL,
        payment_day_of_month INTEGER,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (asset_property_id) REFERENCES properties(id) ON DELETE CASCADE,
        FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE,
        FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_leases_asset_status ON leases(asset_property_id, status)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lease_rent_schedule (
        id TEXT PRIMARY KEY,
        lease_id TEXT NOT NULL,
        period_key TEXT NOT NULL,
        rent_monthly REAL NOT NULL,
        source TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (lease_id) REFERENCES leases(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_lease_rent_schedule_unique ON lease_rent_schedule(lease_id, period_key)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS rent_roll_snapshots (
        id TEXT PRIMARY KEY,
        asset_property_id TEXT NOT NULL,
        period_key TEXT NOT NULL,
        snapshot_at INTEGER NOT NULL,
        occupancy_rate REAL NOT NULL,
        gpr_monthly REAL NOT NULL,
        vacancy_loss_monthly REAL NOT NULL,
        egi_monthly REAL NOT NULL,
        in_place_rent_monthly REAL NOT NULL,
        market_rent_monthly REAL,
        notes TEXT,
        FOREIGN KEY (asset_property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_rent_roll_snapshots_asset_period_unique ON rent_roll_snapshots(asset_property_id, period_key)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rent_roll_snapshots_asset_period ON rent_roll_snapshots(asset_property_id, period_key)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS rent_roll_lines (
        id TEXT PRIMARY KEY,
        snapshot_id TEXT NOT NULL,
        unit_id TEXT NOT NULL,
        lease_id TEXT,
        tenant_name TEXT,
        status TEXT NOT NULL,
        in_place_rent_monthly REAL NOT NULL,
        market_rent_monthly REAL,
        lease_end_date INTEGER,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (snapshot_id) REFERENCES rent_roll_snapshots(id) ON DELETE CASCADE,
        FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE,
        FOREIGN KEY (lease_id) REFERENCES leases(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rent_roll_lines_snapshot ON rent_roll_lines(snapshot_id)',
    );
  }

  static Future<void> _createV7(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lease_indexation_rules (
        id TEXT PRIMARY KEY,
        lease_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        effective_from_period_key TEXT NOT NULL,
        annual_percent REAL,
        fixed_step_amount REAL,
        cap_percent REAL,
        floor_percent REAL,
        notes TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (lease_id) REFERENCES leases(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_lease_indexation_rules_lease ON lease_indexation_rules(lease_id)',
    );
  }

  static Future<void> _createV8(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budgets (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        fiscal_year INTEGER NOT NULL,
        version_name TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_budgets_unique_version ON budgets(entity_type, entity_id, fiscal_year, version_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_budgets_entity ON budgets(entity_type, entity_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS budget_lines (
        id TEXT PRIMARY KEY,
        budget_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        period_key TEXT NOT NULL,
        direction TEXT NOT NULL,
        amount REAL NOT NULL,
        notes TEXT,
        FOREIGN KEY (budget_id) REFERENCES budgets(id) ON DELETE CASCADE,
        FOREIGN KEY (account_id) REFERENCES ledger_accounts(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_budget_lines_unique ON budget_lines(budget_id, account_id, period_key)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_budget_lines_budget ON budget_lines(budget_id)',
    );
  }

  static Future<void> _createV9(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS maintenance_tickets (
        id TEXT PRIMARY KEY,
        asset_property_id TEXT NOT NULL,
        unit_id TEXT,
        title TEXT NOT NULL,
        description TEXT,
        category TEXT NOT NULL DEFAULT 'general',
        status TEXT NOT NULL,
        priority TEXT NOT NULL,
        reported_at INTEGER NOT NULL,
        due_at INTEGER,
        resolved_at INTEGER,
        cost_estimate REAL,
        cost_actual REAL,
        vendor_name TEXT,
        document_id TEXT,
        damage_location TEXT,
        insurance_case INTEGER NOT NULL DEFAULT 0,
        insurance_status TEXT,
        insurance_claim_number TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (asset_property_id) REFERENCES properties(id) ON DELETE CASCADE,
        FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_maintenance_asset_status ON maintenance_tickets(asset_property_id, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_maintenance_priority_due ON maintenance_tickets(priority, due_at)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS maintenance_ticket_history (
        id TEXT PRIMARY KEY,
        ticket_id TEXT NOT NULL,
        action TEXT NOT NULL,
        note TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (ticket_id) REFERENCES maintenance_tickets(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_maintenance_ticket_history_ticket ON maintenance_ticket_history(ticket_id, created_at DESC)',
    );
  }

  static Future<void> _createV10(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loans (
        id TEXT PRIMARY KEY,
        asset_property_id TEXT NOT NULL,
        lender_name TEXT,
        principal REAL NOT NULL,
        interest_rate_percent REAL NOT NULL,
        term_years INTEGER NOT NULL,
        start_date INTEGER NOT NULL,
        amortization_type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (asset_property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loans_asset ON loans(asset_property_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_periods (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        period_key TEXT NOT NULL,
        balance_end REAL NOT NULL,
        debt_service REAL NOT NULL,
        FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_loan_periods_unique ON loan_periods(loan_id, period_key)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS covenants (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        threshold REAL NOT NULL,
        operator TEXT NOT NULL,
        severity TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_covenants_loan ON covenants(loan_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS covenant_checks (
        id TEXT PRIMARY KEY,
        covenant_id TEXT NOT NULL,
        period_key TEXT NOT NULL,
        actual_value REAL,
        pass INTEGER NOT NULL,
        checked_at INTEGER NOT NULL,
        notes TEXT,
        FOREIGN KEY (covenant_id) REFERENCES covenants(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_covenant_checks_unique ON covenant_checks(covenant_id, period_key)',
    );

    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'default_market_rent_mode',
      alterSql:
          "ALTER TABLE app_settings ADD COLUMN default_market_rent_mode TEXT",
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'budget_default_year_start_month',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN budget_default_year_start_month INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'maintenance_due_soon_days',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN maintenance_due_soon_days INTEGER NOT NULL DEFAULT 3',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'covenant_due_soon_days',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN covenant_due_soon_days INTEGER NOT NULL DEFAULT 7',
    );
  }

  static Future<void> _createV11(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS capital_events (
        id TEXT PRIMARY KEY,
        asset_property_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        posted_at INTEGER NOT NULL,
        period_key TEXT NOT NULL,
        direction TEXT NOT NULL,
        amount REAL NOT NULL,
        notes TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (asset_property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_capital_events_asset_period ON capital_events(asset_property_id, period_key)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_capital_events_posted_at ON capital_events(posted_at)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS scenario_valuation (
        scenario_id TEXT PRIMARY KEY,
        valuation_mode TEXT NOT NULL,
        exit_cap_rate_percent REAL,
        stabilized_noi_mode TEXT,
        stabilized_noi_manual REAL,
        stabilized_noi_avg_years INTEGER,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (scenario_id) REFERENCES scenarios(id) ON DELETE CASCADE
      )
    ''');

    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'quality_epc_expiry_warning_days',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN quality_epc_expiry_warning_days INTEGER NOT NULL DEFAULT 90',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'quality_rent_roll_stale_months',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN quality_rent_roll_stale_months INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'quality_ledger_stale_days',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN quality_ledger_stale_days INTEGER NOT NULL DEFAULT 30',
    );
  }

  static Future<void> _createV12(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scenario_versions (
        id TEXT PRIMARY KEY,
        scenario_id TEXT NOT NULL,
        label TEXT NOT NULL,
        notes TEXT,
        created_at INTEGER NOT NULL,
        created_by TEXT,
        base_hash TEXT NOT NULL,
        parent_version_id TEXT,
        FOREIGN KEY (scenario_id) REFERENCES scenarios(id) ON DELETE CASCADE,
        FOREIGN KEY (parent_version_id) REFERENCES scenario_versions(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scenario_versions_scenario_created ON scenario_versions(scenario_id, created_at)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scenario_version_blobs (
        id TEXT PRIMARY KEY,
        version_id TEXT NOT NULL UNIQUE,
        snapshot_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (version_id) REFERENCES scenario_versions(id) ON DELETE CASCADE
      )
    ''');
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'scenario_auto_daily_versions_enabled',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN scenario_auto_daily_versions_enabled INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'scenario_auto_daily_versions_user_id',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN scenario_auto_daily_versions_user_id TEXT',
    );
  }

  static Future<void> _createV13(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_log (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL,
        changed_at INTEGER NOT NULL,
        user_id TEXT,
        summary TEXT,
        diff_json TEXT,
        source TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON audit_log(entity_type, entity_id, changed_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_log_changed_at ON audit_log(changed_at)',
    );
  }

  static Future<void> _createV14(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_types (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        entity_type TEXT NOT NULL,
        required_fields_json TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        type_id TEXT,
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        mime_type TEXT,
        size_bytes INTEGER,
        sha256 TEXT,
        created_at INTEGER NOT NULL,
        created_by TEXT,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (type_id) REFERENCES document_types(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_documents_entity ON documents(entity_type, entity_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_documents_type ON documents(type_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_metadata (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_document_metadata_doc_key_unique ON document_metadata(document_id, key)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS required_documents (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        property_type TEXT,
        type_id TEXT NOT NULL,
        required INTEGER NOT NULL DEFAULT 1,
        expires_field_key TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (type_id) REFERENCES document_types(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_required_documents_unique ON required_documents(entity_type, property_type, type_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_required_documents_entity ON required_documents(entity_type, property_type)',
    );
  }

  static Future<void> _createV15(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workspaces (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        docs_root_path TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_users (
        id TEXT PRIMARY KEY,
        workspace_id TEXT NOT NULL,
        email TEXT,
        display_name TEXT NOT NULL,
        password_hash TEXT,
        password_salt TEXT,
        role TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_local_users_workspace_display_name_unique ON local_users(workspace_id, display_name COLLATE NOCASE)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_sessions (
        id TEXT PRIMARY KEY,
        workspace_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
        FOREIGN KEY (user_id) REFERENCES local_users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_sessions_workspace_user ON user_sessions(workspace_id, user_id, started_at)',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'active_workspace_id',
      alterSql: 'ALTER TABLE app_settings ADD COLUMN active_workspace_id TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'active_user_id',
      alterSql: 'ALTER TABLE app_settings ADD COLUMN active_user_id TEXT',
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('workspaces', <String, Object?>{
      'id': 'ws_default',
      'name': 'Default Workspace',
      'docs_root_path': 'workspace/docs',
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('local_users', <String, Object?>{
      'id': 'user_owner',
      'workspace_id': 'ws_default',
      'email': null,
      'display_name': 'Owner',
      'password_hash': null,
      'password_salt': null,
      'role': 'admin',
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.rawUpdate('''
      UPDATE app_settings
      SET active_workspace_id = COALESCE(active_workspace_id, 'ws_default'),
          active_user_id = COALESCE(active_user_id, 'user_owner')
      WHERE id = 1
      ''');
  }

  static Future<void> _createV16(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'security_app_lock_enabled',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN security_app_lock_enabled INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'security_password_hash',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN security_password_hash TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'security_password_salt',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN security_password_salt TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'security_password_updated_at',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN security_password_updated_at INTEGER',
    );
  }

  static Future<void> _createV17(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'ui_theme_mode',
      alterSql:
          "ALTER TABLE app_settings ADD COLUMN ui_theme_mode TEXT NOT NULL DEFAULT 'system'",
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'ui_density_mode',
      alterSql:
          "ALTER TABLE app_settings ADD COLUMN ui_density_mode TEXT NOT NULL DEFAULT 'comfort'",
    );
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'ui_chart_animations_enabled',
      alterSql:
          'ALTER TABLE app_settings ADD COLUMN ui_chart_animations_enabled INTEGER NOT NULL DEFAULT 1',
    );
  }

  static Future<void> _createV18(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'units',
      column: 'target_rent_monthly',
      alterSql: 'ALTER TABLE units ADD COLUMN target_rent_monthly REAL',
    );
    await _addColumnIfMissing(
      db,
      table: 'units',
      column: 'offline_reason',
      alterSql: 'ALTER TABLE units ADD COLUMN offline_reason TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'units',
      column: 'vacancy_since',
      alterSql: 'ALTER TABLE units ADD COLUMN vacancy_since INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'units',
      column: 'vacancy_reason',
      alterSql: 'ALTER TABLE units ADD COLUMN vacancy_reason TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'units',
      column: 'marketing_status',
      alterSql: 'ALTER TABLE units ADD COLUMN marketing_status TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'units',
      column: 'renovation_status',
      alterSql: 'ALTER TABLE units ADD COLUMN renovation_status TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'units',
      column: 'expected_ready_date',
      alterSql: 'ALTER TABLE units ADD COLUMN expected_ready_date INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'units',
      column: 'next_action',
      alterSql: 'ALTER TABLE units ADD COLUMN next_action TEXT',
    );

    await _addColumnIfMissing(
      db,
      table: 'tenants',
      column: 'alternative_contact',
      alterSql: 'ALTER TABLE tenants ADD COLUMN alternative_contact TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'tenants',
      column: 'billing_contact',
      alterSql: 'ALTER TABLE tenants ADD COLUMN billing_contact TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'tenants',
      column: 'status',
      alterSql:
          "ALTER TABLE tenants ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
    );
    await _addColumnIfMissing(
      db,
      table: 'tenants',
      column: 'move_in_reference',
      alterSql: 'ALTER TABLE tenants ADD COLUMN move_in_reference TEXT',
    );

    await _addColumnIfMissing(
      db,
      table: 'leases',
      column: 'billing_frequency',
      alterSql:
          "ALTER TABLE leases ADD COLUMN billing_frequency TEXT NOT NULL DEFAULT 'monthly'",
    );
    await _addColumnIfMissing(
      db,
      table: 'leases',
      column: 'lease_signed_date',
      alterSql: 'ALTER TABLE leases ADD COLUMN lease_signed_date INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'leases',
      column: 'notice_date',
      alterSql: 'ALTER TABLE leases ADD COLUMN notice_date INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'leases',
      column: 'renewal_option_date',
      alterSql: 'ALTER TABLE leases ADD COLUMN renewal_option_date INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'leases',
      column: 'break_option_date',
      alterSql: 'ALTER TABLE leases ADD COLUMN break_option_date INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'leases',
      column: 'executed_date',
      alterSql: 'ALTER TABLE leases ADD COLUMN executed_date INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'leases',
      column: 'deposit_status',
      alterSql:
          "ALTER TABLE leases ADD COLUMN deposit_status TEXT NOT NULL DEFAULT 'unknown'",
    );
    await _addColumnIfMissing(
      db,
      table: 'leases',
      column: 'rent_free_period_months',
      alterSql: 'ALTER TABLE leases ADD COLUMN rent_free_period_months INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'leases',
      column: 'ancillary_charges_monthly',
      alterSql: 'ALTER TABLE leases ADD COLUMN ancillary_charges_monthly REAL',
    );
    await _addColumnIfMissing(
      db,
      table: 'leases',
      column: 'parking_other_charges_monthly',
      alterSql:
          'ALTER TABLE leases ADD COLUMN parking_other_charges_monthly REAL',
    );
  }

  static Future<void> _createV19(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS operations_alert_states (
        alert_id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        status TEXT NOT NULL,
        resolution_note TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_operations_alert_states_property ON operations_alert_states(property_id, status)',
    );
  }

  static Future<void> _createV20(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'audit_log',
      column: 'occurred_at',
      alterSql: 'ALTER TABLE audit_log ADD COLUMN occurred_at INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'audit_log',
      column: 'workspace_id',
      alterSql: 'ALTER TABLE audit_log ADD COLUMN workspace_id TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'audit_log',
      column: 'actor_user_id',
      alterSql: 'ALTER TABLE audit_log ADD COLUMN actor_user_id TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'audit_log',
      column: 'actor_role',
      alterSql: 'ALTER TABLE audit_log ADD COLUMN actor_role TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'audit_log',
      column: 'parent_entity_type',
      alterSql: 'ALTER TABLE audit_log ADD COLUMN parent_entity_type TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'audit_log',
      column: 'parent_entity_id',
      alterSql: 'ALTER TABLE audit_log ADD COLUMN parent_entity_id TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'audit_log',
      column: 'old_values_json',
      alterSql: 'ALTER TABLE audit_log ADD COLUMN old_values_json TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'audit_log',
      column: 'new_values_json',
      alterSql: 'ALTER TABLE audit_log ADD COLUMN new_values_json TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'audit_log',
      column: 'correlation_id',
      alterSql: 'ALTER TABLE audit_log ADD COLUMN correlation_id TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'audit_log',
      column: 'reason',
      alterSql: 'ALTER TABLE audit_log ADD COLUMN reason TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'audit_log',
      column: 'is_system_event',
      alterSql:
          'ALTER TABLE audit_log ADD COLUMN is_system_event INTEGER NOT NULL DEFAULT 0',
    );
    await db.rawUpdate('''
      UPDATE audit_log
      SET occurred_at = COALESCE(occurred_at, changed_at),
          actor_user_id = COALESCE(actor_user_id, user_id)
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_log_workspace_changed ON audit_log(workspace_id, occurred_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_log_parent ON audit_log(parent_entity_type, parent_entity_id, occurred_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log(actor_user_id, occurred_at)',
    );
  }

  static Future<void> _createV21(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'scenarios',
      column: 'workflow_status',
      alterSql:
          "ALTER TABLE scenarios ADD COLUMN workflow_status TEXT NOT NULL DEFAULT 'draft'",
    );
    await _addColumnIfMissing(
      db,
      table: 'scenarios',
      column: 'approved_by',
      alterSql: 'ALTER TABLE scenarios ADD COLUMN approved_by TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'scenarios',
      column: 'approved_at',
      alterSql: 'ALTER TABLE scenarios ADD COLUMN approved_at INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'scenarios',
      column: 'rejected_by',
      alterSql: 'ALTER TABLE scenarios ADD COLUMN rejected_by TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'scenarios',
      column: 'rejected_at',
      alterSql: 'ALTER TABLE scenarios ADD COLUMN rejected_at INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'scenarios',
      column: 'review_comment',
      alterSql: 'ALTER TABLE scenarios ADD COLUMN review_comment TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'scenarios',
      column: 'changed_since_approval',
      alterSql:
          'ALTER TABLE scenarios ADD COLUMN changed_since_approval INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scenarios_property_status ON scenarios(property_id, workflow_status, updated_at)',
    );
  }

  static Future<void> _createV22(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'app_settings',
      column: 'ui_language_code',
      alterSql:
          "ALTER TABLE app_settings ADD COLUMN ui_language_code TEXT NOT NULL DEFAULT 'en'",
    );
  }

  static Future<void> _createV23(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'tasks',
      column: 'description',
      alterSql: 'ALTER TABLE tasks ADD COLUMN description TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'tasks',
      column: 'category',
      alterSql: 'ALTER TABLE tasks ADD COLUMN category TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'tasks',
      column: 'assigned_to',
      alterSql: 'ALTER TABLE tasks ADD COLUMN assigned_to TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'tasks',
      column: 'estimated_cost',
      alterSql: 'ALTER TABLE tasks ADD COLUMN estimated_cost REAL',
    );
    await _addColumnIfMissing(
      db,
      table: 'scenario_inputs',
      column: 'gross_area_sqm',
      alterSql:
          'ALTER TABLE scenario_inputs ADD COLUMN gross_area_sqm REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      table: 'scenario_inputs',
      column: 'lettable_area_sqm',
      alterSql:
          'ALTER TABLE scenario_inputs ADD COLUMN lettable_area_sqm REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      table: 'scenario_inputs',
      column: 'residential_area_sqm',
      alterSql:
          'ALTER TABLE scenario_inputs ADD COLUMN residential_area_sqm REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      table: 'scenario_inputs',
      column: 'commercial_area_sqm',
      alterSql:
          'ALTER TABLE scenario_inputs ADD COLUMN commercial_area_sqm REAL NOT NULL DEFAULT 0',
    );
  }

  static Future<void> _createV24(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'category',
      alterSql:
          "ALTER TABLE maintenance_tickets ADD COLUMN category TEXT NOT NULL DEFAULT 'general'",
    );
  }

  static Future<void> _createV25(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asset_operating_costs (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        scope TEXT NOT NULL,
        unit_code TEXT,
        cost_type TEXT NOT NULL,
        provider TEXT,
        contract_number TEXT,
        allocation_key TEXT,
        monthly_amount REAL,
        yearly_amount REAL,
        canceled INTEGER NOT NULL DEFAULT 0,
        start_date INTEGER,
        end_date INTEGER,
        next_due_date INTEGER,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_asset_operating_costs_property_scope ON asset_operating_costs(property_id, scope, cost_type)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS rental_income_plans (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        year INTEGER NOT NULL,
        unit_code TEXT NOT NULL,
        tenant_name TEXT,
        rent_type TEXT,
        target_rent_monthly REAL,
        side_costs_monthly REAL,
        month_1 REAL NOT NULL DEFAULT 0,
        month_2 REAL NOT NULL DEFAULT 0,
        month_3 REAL NOT NULL DEFAULT 0,
        month_4 REAL NOT NULL DEFAULT 0,
        month_5 REAL NOT NULL DEFAULT 0,
        month_6 REAL NOT NULL DEFAULT 0,
        month_7 REAL NOT NULL DEFAULT 0,
        month_8 REAL NOT NULL DEFAULT 0,
        month_9 REAL NOT NULL DEFAULT 0,
        month_10 REAL NOT NULL DEFAULT 0,
        month_11 REAL NOT NULL DEFAULT 0,
        month_12 REAL NOT NULL DEFAULT 0,
        status_note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rental_income_plans_property_year ON rental_income_plans(property_id, year, unit_code)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS hotel_kpis (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        period_key TEXT NOT NULL,
        rooms_total INTEGER,
        rooms_available INTEGER,
        rooms_occupied INTEGER,
        adr REAL,
        revpar REAL,
        fb_revenue REAL,
        room_revenue REAL,
        total_revenue REAL,
        gop_percent REAL,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_hotel_kpis_property_period ON hotel_kpis(property_id, period_key)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS renovation_projects (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        project_code TEXT NOT NULL,
        category TEXT,
        measure TEXT,
        status TEXT NOT NULL,
        start_date INTEGER,
        planned_end_date INTEGER,
        actual_end_date INTEGER,
        budget_amount REAL,
        actual_amount REAL,
        owner TEXT,
        next_step TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_renovation_projects_property_status ON renovation_projects(property_id, status, planned_end_date)',
    );

  }

  // V26..V32 each re-ran the Asset Overview seed against an earlier workbook
  // revision. Seeding now happens once in V48, after every table and column the
  // seed writes to exists, so these steps are intentionally empty.
  static Future<void> _createV26(Database db) async {}

  static Future<void> _createV27(Database db) async {}

  static Future<void> _createV28(Database db) async {}

  static Future<void> _createV29(Database db) async {}

  static Future<void> _createV30(Database db) async {}

  static Future<void> _createV31(Database db) async {}

  static Future<void> _createV32(Database db) async {}

  static Future<void> _createV33(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asset_operating_cost_history (
        id TEXT PRIMARY KEY,
        cost_id TEXT NOT NULL,
        property_id TEXT NOT NULL,
        action TEXT NOT NULL,
        scope TEXT NOT NULL,
        unit_code TEXT,
        cost_type TEXT NOT NULL,
        provider TEXT,
        contract_number TEXT,
        allocation_key TEXT,
        monthly_amount REAL,
        yearly_amount REAL,
        canceled INTEGER NOT NULL DEFAULT 0,
        start_date INTEGER,
        end_date INTEGER,
        next_due_date INTEGER,
        notes TEXT,
        changed_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_asset_operating_cost_history_cost ON asset_operating_cost_history(cost_id, changed_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_asset_operating_cost_history_property ON asset_operating_cost_history(property_id, changed_at DESC)',
    );
    await db.execute('''
      INSERT OR IGNORE INTO asset_operating_cost_history (
        id,
        cost_id,
        property_id,
        action,
        scope,
        unit_code,
        cost_type,
        provider,
        contract_number,
        allocation_key,
        monthly_amount,
        yearly_amount,
        canceled,
        start_date,
        end_date,
        next_due_date,
        notes,
        changed_at
      )
      SELECT
        id || '_initial_history',
        id,
        property_id,
        'imported',
        scope,
        unit_code,
        cost_type,
        provider,
        contract_number,
        allocation_key,
        monthly_amount,
        yearly_amount,
        canceled,
        start_date,
        end_date,
        next_due_date,
        notes,
        updated_at
      FROM asset_operating_costs
    ''');
  }

  static Future<void> _createV34(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'task_templates',
      column: 'category',
      alterSql:
          "ALTER TABLE task_templates ADD COLUMN category TEXT NOT NULL DEFAULT 'general'",
    );
    await _addColumnIfMissing(
      db,
      table: 'task_templates',
      column: 'assignee_group',
      alterSql:
          "ALTER TABLE task_templates ADD COLUMN assignee_group TEXT NOT NULL DEFAULT 'asset_management'",
    );
    await _addColumnIfMissing(
      db,
      table: 'task_templates',
      column: 'property_type',
      alterSql:
          "ALTER TABLE task_templates ADD COLUMN property_type TEXT NOT NULL DEFAULT 'all'",
    );
  }

  static Future<void> _createV35(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'local_users',
      column: 'password_salt',
      alterSql: 'ALTER TABLE local_users ADD COLUMN password_salt TEXT',
    );
  }

  static Future<void> _createV36(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'damage_location',
      alterSql: 'ALTER TABLE maintenance_tickets ADD COLUMN damage_location TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'insurance_case',
      alterSql:
          'ALTER TABLE maintenance_tickets ADD COLUMN insurance_case INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'insurance_status',
      alterSql: 'ALTER TABLE maintenance_tickets ADD COLUMN insurance_status TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'insurance_claim_number',
      alterSql:
          'ALTER TABLE maintenance_tickets ADD COLUMN insurance_claim_number TEXT',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS maintenance_ticket_history (
        id TEXT PRIMARY KEY,
        ticket_id TEXT NOT NULL,
        action TEXT NOT NULL,
        note TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (ticket_id) REFERENCES maintenance_tickets(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_maintenance_ticket_history_ticket ON maintenance_ticket_history(ticket_id, created_at DESC)',
    );
  }

  static Future<void> _createV37(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'start_date',
      alterSql: 'ALTER TABLE maintenance_tickets ADD COLUMN start_date INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'end_date',
      alterSql: 'ALTER TABLE maintenance_tickets ADD COLUMN end_date INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'assignee_type',
      alterSql: 'ALTER TABLE maintenance_tickets ADD COLUMN assignee_type TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'assignee_name',
      alterSql: 'ALTER TABLE maintenance_tickets ADD COLUMN assignee_name TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'building',
      alterSql: 'ALTER TABLE maintenance_tickets ADD COLUMN building TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'area',
      alterSql: 'ALTER TABLE maintenance_tickets ADD COLUMN area TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'technical',
      alterSql: 'ALTER TABLE maintenance_tickets ADD COLUMN technical TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'maintenance_tickets',
      column: 'outdoor',
      alterSql: 'ALTER TABLE maintenance_tickets ADD COLUMN outdoor TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'budgets',
      column: 'unit_id',
      alterSql: 'ALTER TABLE budgets ADD COLUMN unit_id TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'budgets',
      column: 'renovation_id',
      alterSql: 'ALTER TABLE budgets ADD COLUMN renovation_id TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'budgets',
      column: 'ticket_id',
      alterSql: 'ALTER TABLE budgets ADD COLUMN ticket_id TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'budgets',
      column: 'project_id',
      alterSql: 'ALTER TABLE budgets ADD COLUMN project_id TEXT',
    );
  }

  static Future<void> _createV38(Database db) async {
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'land_area',
        alterSql: 'ALTER TABLE properties ADD COLUMN land_area REAL');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'residential_area',
        alterSql: 'ALTER TABLE properties ADD COLUMN residential_area REAL');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'commercial_area',
        alterSql: 'ALTER TABLE properties ADD COLUMN commercial_area REAL');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'parking_spots',
        alterSql: 'ALTER TABLE properties ADD COLUMN parking_spots INTEGER');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'owner_company',
        alterSql: 'ALTER TABLE properties ADD COLUMN owner_company TEXT');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'purchase_date',
        alterSql: 'ALTER TABLE properties ADD COLUMN purchase_date INTEGER');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'purchase_price',
        alterSql: 'ALTER TABLE properties ADD COLUMN purchase_price REAL');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'notary',
        alterSql: 'ALTER TABLE properties ADD COLUMN notary TEXT');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'seller',
        alterSql: 'ALTER TABLE properties ADD COLUMN seller TEXT');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'land_registry_details',
        alterSql: 'ALTER TABLE properties ADD COLUMN land_registry_details TEXT');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'parcel',
        alterSql: 'ALTER TABLE properties ADD COLUMN parcel TEXT');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'energy_certificate',
        alterSql: 'ALTER TABLE properties ADD COLUMN energy_certificate TEXT');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'insurance_details',
        alterSql: 'ALTER TABLE properties ADD COLUMN insurance_details TEXT');
    await _addColumnIfMissing(db,
        table: 'properties',
        column: 'tax_assignment',
        alterSql: 'ALTER TABLE properties ADD COLUMN tax_assignment TEXT');
  }

  static Future<void> _createV39(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contractors (
        id TEXT PRIMARY KEY,
        company_name TEXT NOT NULL,
        trade_category TEXT NOT NULL,
        contact_name TEXT NOT NULL,
        phone TEXT NOT NULL,
        email TEXT NOT NULL,
        address TEXT NOT NULL,
        hourly_rate REAL,
        service_areas_json TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        rating_price REAL,
        rating_quality REAL,
        rating_speed REAL,
        rating_communication REAL,
        rating_punctuality REAL,
        insurance_cert_expiry INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  static Future<void> _createV40(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quick_screenings (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        source_label TEXT,
        address_text TEXT,
        property_type TEXT NOT NULL,
        units INTEGER NOT NULL DEFAULT 0,
        area_sqm REAL NOT NULL DEFAULT 0,
        purchase_price REAL NOT NULL DEFAULT 0,
        rent_monthly_total REAL NOT NULL DEFAULT 0,
        vacancy_percent REAL NOT NULL DEFAULT 0,
        operating_costs_monthly REAL NOT NULL DEFAULT 0,
        linked_property_id TEXT,
        linked_scenario_id TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (linked_property_id) REFERENCES properties(id) ON DELETE SET NULL,
        FOREIGN KEY (linked_scenario_id) REFERENCES scenarios(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_quick_screenings_updated ON quick_screenings(updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_quick_screenings_links ON quick_screenings(linked_property_id, linked_scenario_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS valuation_property_snapshots (
        scenario_id TEXT PRIMARY KEY,
        source_property_id TEXT NOT NULL,
        property_name TEXT NOT NULL,
        address_line1 TEXT NOT NULL,
        address_line2 TEXT,
        zip TEXT NOT NULL,
        city TEXT NOT NULL,
        country TEXT NOT NULL,
        property_type TEXT NOT NULL,
        units INTEGER NOT NULL,
        gross_area_sqm REAL,
        residential_area_sqm REAL,
        commercial_area_sqm REAL,
        year_built INTEGER,
        purchase_price REAL,
        rent_monthly_total REAL,
        vacancy_percent REAL,
        operating_costs_monthly REAL,
        document_status TEXT,
        technical_info TEXT,
        auto_imported_fields_json TEXT NOT NULL,
        manual_adjusted_fields_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (scenario_id) REFERENCES scenarios(id) ON DELETE CASCADE,
        FOREIGN KEY (source_property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_valuation_snapshots_property ON valuation_property_snapshots(source_property_id)',
    );
  }

  static Future<void> _createV41(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS property_creation_profiles (
        property_id TEXT PRIMARY KEY,
        creation_reason TEXT NOT NULL,
        creation_mode TEXT NOT NULL,
        object_status TEXT NOT NULL,
        external_reference TEXT,
        asset_manager TEXT,
        priority TEXT,
        tags TEXT,
        federal_state TEXT,
        location_quality TEXT,
        profile_json TEXT NOT NULL,
        metrics_json TEXT NOT NULL,
        data_quality_score INTEGER NOT NULL,
        data_quality_status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS property_document_checklist (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        document_key TEXT NOT NULL,
        label TEXT NOT NULL,
        status TEXT NOT NULL,
        upload_path TEXT,
        note TEXT,
        due_date INTEGER,
        owner TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_property_document_checklist_property ON property_document_checklist(property_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_property_document_checklist_unique ON property_document_checklist(property_id, document_key)',
    );
  }

  static Future<void> _createV42(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS acquisition_quick_evaluations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        property_id TEXT,
        scenario_id TEXT,
        scenario_type TEXT NOT NULL DEFAULT 'base',
        status TEXT NOT NULL,
        input_json TEXT NOT NULL,
        result_json TEXT NOT NULL,
        recommendation TEXT,
        score INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE SET NULL,
        FOREIGN KEY (scenario_id) REFERENCES scenarios(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_acquisition_quick_property ON acquisition_quick_evaluations(property_id, updated_at)',
    );
    await _addColumnIfMissing(
      db,
      table: 'acquisition_quick_evaluations',
      column: 'scenario_type',
      alterSql:
          "ALTER TABLE acquisition_quick_evaluations ADD COLUMN scenario_type TEXT NOT NULL DEFAULT 'base'",
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS acquisition_deep_evaluations (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        scenario_id TEXT,
        title TEXT NOT NULL,
        status TEXT NOT NULL,
        input_json TEXT NOT NULL,
        result_json TEXT NOT NULL,
        risk_score INTEGER,
        recommendation TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE,
        FOREIGN KEY (scenario_id) REFERENCES scenarios(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS acquisition_scenarios (
        id TEXT PRIMARY KEY,
        evaluation_id TEXT NOT NULL,
        scenario_name TEXT NOT NULL,
        scenario_type TEXT NOT NULL,
        input_json TEXT NOT NULL,
        result_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (evaluation_id) REFERENCES acquisition_deep_evaluations(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS acquisition_rent_roll_entries (
        id TEXT PRIMARY KEY,
        evaluation_id TEXT NOT NULL,
        unit_label TEXT,
        tenant_name TEXT,
        usage_type TEXT,
        area_sqm REAL,
        current_rent_monthly REAL,
        market_rent_monthly REAL,
        is_vacant INTEGER NOT NULL DEFAULT 0,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (evaluation_id) REFERENCES acquisition_deep_evaluations(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS acquisition_financing_assumptions (
        id TEXT PRIMARY KEY,
        evaluation_id TEXT NOT NULL,
        scenario_id TEXT,
        loan_amount REAL,
        equity REAL,
        interest_rate_percent REAL,
        amortization_percent REAL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (evaluation_id) REFERENCES acquisition_deep_evaluations(id) ON DELETE CASCADE,
        FOREIGN KEY (scenario_id) REFERENCES acquisition_scenarios(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS acquisition_market_comps (
        id TEXT PRIMARY KEY,
        evaluation_id TEXT NOT NULL,
        comp_type TEXT NOT NULL,
        address TEXT,
        price REAL,
        rent_monthly REAL,
        area_sqm REAL,
        adjustment_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (evaluation_id) REFERENCES acquisition_deep_evaluations(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS acquisition_risk_items (
        id TEXT PRIMARY KEY,
        evaluation_id TEXT NOT NULL,
        risk_category TEXT NOT NULL,
        title TEXT NOT NULL,
        severity INTEGER NOT NULL,
        mitigation TEXT,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (evaluation_id) REFERENCES acquisition_deep_evaluations(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS renovation_measures (
        id TEXT PRIMARY KEY,
        renovation_project_id TEXT,
        renovation_scenario_id TEXT,
        measure_type TEXT NOT NULL,
        category TEXT NOT NULL,
        trade TEXT,
        affected_area_sqm REAL,
        is_required INTEGER NOT NULL DEFAULT 0,
        is_value_add INTEGER NOT NULL DEFAULT 0,
        is_recoverable INTEGER NOT NULL DEFAULT 0,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (renovation_project_id) REFERENCES renovation_projects(id) ON DELETE SET NULL,
        FOREIGN KEY (renovation_scenario_id) REFERENCES renovation_scenarios(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS renovation_cost_items (
        id TEXT PRIMARY KEY,
        renovation_project_id TEXT,
        renovation_scenario_id TEXT,
        measure_id TEXT,
        label TEXT NOT NULL,
        budget_amount REAL,
        committed_amount REAL,
        actual_amount REAL,
        remaining_amount REAL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (renovation_project_id) REFERENCES renovation_projects(id) ON DELETE SET NULL,
        FOREIGN KEY (renovation_scenario_id) REFERENCES renovation_scenarios(id) ON DELETE CASCADE,
        FOREIGN KEY (measure_id) REFERENCES renovation_measures(id) ON DELETE SET NULL
      )
    ''');
    await _addColumnIfMissing(
      db,
      table: 'renovation_cost_items',
      column: 'renovation_scenario_id',
      alterSql: 'ALTER TABLE renovation_cost_items ADD COLUMN renovation_scenario_id TEXT',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS renovation_rent_impacts (
        id TEXT PRIMARY KEY,
        renovation_project_id TEXT NOT NULL,
        unit_id TEXT,
        current_rent_monthly REAL,
        target_rent_monthly REAL,
        vacancy_months REAL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (renovation_project_id) REFERENCES renovation_projects(id) ON DELETE CASCADE,
        FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS renovation_value_impacts (
        id TEXT PRIMARY KEY,
        renovation_project_id TEXT NOT NULL,
        noi_before REAL,
        noi_after REAL,
        cap_rate_before REAL,
        cap_rate_after REAL,
        result_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (renovation_project_id) REFERENCES renovation_projects(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS renovation_scenarios (
        id TEXT PRIMARY KEY,
        renovation_project_id TEXT,
        scenario_name TEXT NOT NULL,
        scenario_type TEXT NOT NULL,
        input_json TEXT NOT NULL,
        result_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (renovation_project_id) REFERENCES renovation_projects(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS disposition_cases (
        id TEXT PRIMARY KEY,
        property_id TEXT,
        title TEXT NOT NULL,
        status TEXT NOT NULL,
        input_json TEXT NOT NULL,
        result_json TEXT NOT NULL,
        recommendation TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS disposition_offers (
        id TEXT PRIMARY KEY,
        disposition_case_id TEXT NOT NULL,
        buyer_name TEXT NOT NULL,
        offer_price REAL NOT NULL,
        closing_probability REAL,
        risk_level TEXT,
        due_diligence_deadline TEXT,
        exclusivity_until TEXT,
        payment_target TEXT,
        offer_version TEXT,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (disposition_case_id) REFERENCES disposition_cases(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS disposition_cost_items (
        id TEXT PRIMARY KEY,
        disposition_case_id TEXT NOT NULL,
        label TEXT NOT NULL,
        amount REAL NOT NULL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (disposition_case_id) REFERENCES disposition_cases(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS disposition_valuation_methods (
        id TEXT PRIMARY KEY,
        disposition_case_id TEXT NOT NULL,
        method_name TEXT NOT NULL,
        value_low REAL,
        value_mid REAL,
        value_high REAL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (disposition_case_id) REFERENCES disposition_cases(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS disposition_scenarios (
        id TEXT PRIMARY KEY,
        disposition_case_id TEXT NOT NULL,
        scenario_name TEXT NOT NULL,
        scenario_type TEXT NOT NULL,
        input_json TEXT NOT NULL,
        result_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (disposition_case_id) REFERENCES disposition_cases(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS calculation_datasheets (
        id TEXT PRIMARY KEY,
        module TEXT NOT NULL,
        property_id TEXT,
        scenario_id TEXT,
        title TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        export_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS formula_audit_entries (
        id TEXT PRIMARY KEY,
        datasheet_id TEXT,
        module TEXT NOT NULL,
        property_id TEXT,
        scenario_id TEXT,
        formula_name TEXT NOT NULL,
        formula_description TEXT NOT NULL,
        input_json TEXT NOT NULL,
        result REAL,
        unit TEXT NOT NULL,
        calculated_at INTEGER NOT NULL,
        FOREIGN KEY (datasheet_id) REFERENCES calculation_datasheets(id) ON DELETE CASCADE,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_formula_audit_module_object ON formula_audit_entries(module, property_id, scenario_id)',
    );
  }

  static Future<void> _createV43(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'disposition_offers',
      column: 'due_diligence_deadline',
      alterSql:
          'ALTER TABLE disposition_offers ADD COLUMN due_diligence_deadline TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'disposition_offers',
      column: 'exclusivity_until',
      alterSql: 'ALTER TABLE disposition_offers ADD COLUMN exclusivity_until TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'disposition_offers',
      column: 'payment_target',
      alterSql: 'ALTER TABLE disposition_offers ADD COLUMN payment_target TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'disposition_offers',
      column: 'offer_version',
      alterSql: 'ALTER TABLE disposition_offers ADD COLUMN offer_version TEXT',
    );
  }

  static Future<void> _createV44(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS acquisition_valuation_methods (
        id TEXT PRIMARY KEY,
        evaluation_id TEXT NOT NULL,
        method_name TEXT NOT NULL,
        value_low REAL,
        value_mid REAL,
        value_high REAL,
        confidence TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (evaluation_id) REFERENCES acquisition_deep_evaluations(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_acquisition_valuation_methods_eval ON acquisition_valuation_methods(evaluation_id)',
    );
  }

  static Future<void> _createV45(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'scenarios',
      column: 'scenario_case_type',
      alterSql:
          "ALTER TABLE scenarios ADD COLUMN scenario_case_type TEXT NOT NULL DEFAULT 'base'",
    );
  }

  static Future<void> _createV46(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contacts (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        legal_name TEXT,
        role TEXT NOT NULL DEFAULT 'other',
        email TEXT,
        phone TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_contacts_role_name ON contacts(role, display_name)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS property_sale_details (
        property_id TEXT PRIMARY KEY,
        asking_price REAL,
        minimum_price REAL,
        sale_status TEXT NOT NULL DEFAULT 'draft',
        listed_at INTEGER,
        reserved_at INTEGER,
        sold_at INTEGER,
        notary_date INTEGER,
        notes TEXT,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS buyer_interests (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        unit_id TEXT,
        contact_id TEXT,
        interest_status TEXT NOT NULL DEFAULT 'active',
        budget_amount REAL,
        offer_amount REAL,
        viewing_at INTEGER,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE,
        FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE SET NULL,
        FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_buyer_interests_property ON buyer_interests(property_id, updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_buyer_interests_unit ON buyer_interests(unit_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_buyer_interests_contact ON buyer_interests(contact_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS reservations (
        id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        unit_id TEXT,
        guest_contact_id TEXT,
        check_in INTEGER NOT NULL,
        check_out INTEGER NOT NULL,
        reservation_status TEXT NOT NULL DEFAULT 'reserved',
        total_amount REAL,
        source TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE,
        FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE SET NULL,
        FOREIGN KEY (guest_contact_id) REFERENCES contacts(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reservations_property_dates ON reservations(property_id, check_in, check_out)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reservations_unit ON reservations(unit_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reservations_guest ON reservations(guest_contact_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS unit_sale_details (
        unit_id TEXT PRIMARY KEY,
        property_id TEXT NOT NULL,
        sale_status TEXT NOT NULL DEFAULT 'available',
        asking_price REAL,
        minimum_price REAL,
        reserved_at INTEGER,
        sold_at INTEGER,
        buyer_contact_id TEXT,
        notes TEXT,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE,
        FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE,
        FOREIGN KEY (buyer_contact_id) REFERENCES contacts(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_unit_sale_details_property ON unit_sale_details(property_id, sale_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_unit_sale_details_buyer ON unit_sale_details(buyer_contact_id)',
    );
  }

  static Future<void> _createV47(Database db) async {
    // DEBT-012 (STM-002): soft tombstone marker for properties. `deleted_at`
    // NULL means the property is live; a non-null epoch marks it tombstoned
    // (row and children kept for audit/restore, hidden from active views).
    // `deleted_by` records the actor. Tombstoning also sets `archived = 1`, so
    // every read that already filters `archived = 0` excludes tombstoned rows
    // without any query change.
    await db.execute('ALTER TABLE properties ADD COLUMN deleted_at INTEGER');
    await db.execute('ALTER TABLE properties ADD COLUMN deleted_by TEXT');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_properties_deleted_at ON properties(deleted_at)',
    );
  }

  static Future<void> _createV48(Database db) async {
    // Hotel P&L: the workbook tracks monthly operating costs and profit per
    // hotel, so `hotel_kpis` gains cost/profit columns before it is re-seeded.
    await _addColumnIfMissing(
      db,
      table: 'hotel_kpis',
      column: 'total_costs',
      alterSql: 'ALTER TABLE hotel_kpis ADD COLUMN total_costs REAL',
    );
    await _addColumnIfMissing(
      db,
      table: 'hotel_kpis',
      column: 'profit_loss',
      alterSql: 'ALTER TABLE hotel_kpis ADD COLUMN profit_loss REAL',
    );

  }

  static Future<void> _addColumnIfMissing(
    Database db, {
    required String table,
    required String column,
    required String alterSql,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final hasColumn = columns.any((row) => row['name'] == column);
    if (!hasColumn) {
      await db.execute(alterSql);
    }
  }

  static Future<void> _dedupeNames(Database db, {required String table}) async {
    final rows = await db.query(table, columns: const ['id', 'name']);
    if (rows.isEmpty) {
      return;
    }

    final counters = <String, int>{};
    for (final row in rows) {
      final id = row['id'] as String?;
      final rawName = (row['name'] as String?)?.trim();
      if (id == null || rawName == null || rawName.isEmpty) {
        continue;
      }

      final key = rawName.toLowerCase();
      final seen = counters[key] ?? 0;
      counters[key] = seen + 1;
      if (seen == 0) {
        continue;
      }

      final nextName = '$rawName (${seen + 1})';
      await db.update(
        table,
        <String, Object?>{
          'name': nextName,
          if (table == 'criteria_sets' || table == 'report_templates')
            'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    }
  }
}
