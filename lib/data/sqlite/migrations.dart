import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DbMigrations {
  static const int currentVersion = 21;

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
        status TEXT NOT NULL,
        priority TEXT NOT NULL,
        reported_at INTEGER NOT NULL,
        due_at INTEGER,
        resolved_at INTEGER,
        cost_estimate REAL,
        cost_actual REAL,
        vendor_name TEXT,
        document_id TEXT,
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
