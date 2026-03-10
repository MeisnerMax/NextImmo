import 'package:flutter_test/flutter_test.dart';
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

  test('creates v2 property criteria override table', () async {
    final rows = await db.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: <Object?>['table', 'property_criteria_overrides'],
    );

    expect(rows, isNotEmpty);
  });

  test(
    'creates v3 settings columns for compare and finance defaults',
    () async {
      final columns = await db.rawQuery('PRAGMA table_info(app_settings)');
      final names = columns.map((row) => row['name']).toSet();

      expect(names.contains('default_down_payment_percent'), isTrue);
      expect(names.contains('default_interest_rate_percent'), isTrue);
      expect(names.contains('default_term_years'), isTrue);
      expect(names.contains('compare_visible_metrics'), isTrue);
      expect(names.contains('default_report_template_id'), isTrue);
    },
  );

  test('creates v4 portfolio and data management tables', () async {
    Future<bool> tableExists(String name) async {
      final rows = await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: <Object?>['table', name],
      );
      return rows.isNotEmpty;
    }

    expect(await tableExists('portfolios'), isTrue);
    expect(await tableExists('portfolio_properties'), isTrue);
    expect(await tableExists('property_profiles'), isTrue);
    expect(await tableExists('property_kpi_snapshots'), isTrue);
    expect(await tableExists('esg_profiles'), isTrue);
    expect(await tableExists('notes'), isTrue);
    expect(await tableExists('notifications'), isTrue);
    expect(await tableExists('import_jobs'), isTrue);
    expect(await tableExists('import_mappings'), isTrue);
  });

  test('creates v5 backup, ledger, search and task tables', () async {
    Future<bool> tableExists(String name) async {
      final rows = await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: <Object?>['table', name],
      );
      return rows.isNotEmpty;
    }

    expect(await tableExists('ledger_accounts'), isTrue);
    expect(await tableExists('ledger_entries'), isTrue);
    expect(await tableExists('search_index'), isTrue);
    expect(await tableExists('tasks'), isTrue);
    expect(await tableExists('task_checklist_items'), isTrue);
    expect(await tableExists('task_templates'), isTrue);
    expect(await tableExists('task_template_checklist_items'), isTrue);
    expect(await tableExists('task_generated_instances'), isTrue);

    final columns = await db.rawQuery('PRAGMA table_info(app_settings)');
    final names = columns.map((row) => row['name']).toSet();
    expect(names.contains('workspace_root_path'), isTrue);
    expect(names.contains('last_backup_at'), isTrue);
    expect(names.contains('last_backup_path'), isTrue);
    expect(names.contains('last_task_generation_at'), isTrue);
    expect(names.contains('task_due_soon_days'), isTrue);
    expect(names.contains('enable_task_notifications'), isTrue);
  });

  test(
    'creates v6-v10 operations, budget, maintenance and covenant tables',
    () async {
      Future<bool> tableExists(String name) async {
        final rows = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: <Object?>['table', name],
        );
        return rows.isNotEmpty;
      }

      expect(await tableExists('units'), isTrue);
      expect(await tableExists('tenants'), isTrue);
      expect(await tableExists('leases'), isTrue);
      expect(await tableExists('lease_rent_schedule'), isTrue);
      expect(await tableExists('rent_roll_snapshots'), isTrue);
      expect(await tableExists('rent_roll_lines'), isTrue);
      expect(await tableExists('lease_indexation_rules'), isTrue);
      expect(await tableExists('budgets'), isTrue);
      expect(await tableExists('budget_lines'), isTrue);
      expect(await tableExists('maintenance_tickets'), isTrue);
      expect(await tableExists('loans'), isTrue);
      expect(await tableExists('loan_periods'), isTrue);
      expect(await tableExists('covenants'), isTrue);
      expect(await tableExists('covenant_checks'), isTrue);

      final columns = await db.rawQuery('PRAGMA table_info(app_settings)');
      final names = columns.map((row) => row['name']).toSet();
      expect(names.contains('default_market_rent_mode'), isTrue);
      expect(names.contains('budget_default_year_start_month'), isTrue);
      expect(names.contains('maintenance_due_soon_days'), isTrue);
      expect(names.contains('covenant_due_soon_days'), isTrue);
    },
  );

  test(
    'creates v11 valuation, capital events and quality settings columns',
    () async {
      Future<bool> tableExists(String name) async {
        final rows = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: <Object?>['table', name],
        );
        return rows.isNotEmpty;
      }

      expect(await tableExists('capital_events'), isTrue);
      expect(await tableExists('scenario_valuation'), isTrue);

      final columns = await db.rawQuery('PRAGMA table_info(app_settings)');
      final names = columns.map((row) => row['name']).toSet();
      expect(names.contains('quality_epc_expiry_warning_days'), isTrue);
      expect(names.contains('quality_rent_roll_stale_months'), isTrue);
      expect(names.contains('quality_ledger_stale_days'), isTrue);
    },
  );

  test(
    'creates v12-v17 governance, docs, workspace, security and ui schema',
    () async {
      Future<bool> tableExists(String name) async {
        final rows = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: <Object?>['table', name],
        );
        return rows.isNotEmpty;
      }

      expect(await tableExists('scenario_versions'), isTrue);
      expect(await tableExists('scenario_version_blobs'), isTrue);
      expect(await tableExists('audit_log'), isTrue);
      expect(await tableExists('document_types'), isTrue);
      expect(await tableExists('documents'), isTrue);
      expect(await tableExists('document_metadata'), isTrue);
      expect(await tableExists('required_documents'), isTrue);
      expect(await tableExists('workspaces'), isTrue);
      expect(await tableExists('local_users'), isTrue);
      expect(await tableExists('user_sessions'), isTrue);

      final columns = await db.rawQuery('PRAGMA table_info(app_settings)');
      final names = columns.map((row) => row['name']).toSet();
      expect(names.contains('scenario_auto_daily_versions_enabled'), isTrue);
      expect(names.contains('scenario_auto_daily_versions_user_id'), isTrue);
      expect(names.contains('active_workspace_id'), isTrue);
      expect(names.contains('active_user_id'), isTrue);
      expect(names.contains('security_app_lock_enabled'), isTrue);
      expect(names.contains('security_password_hash'), isTrue);
      expect(names.contains('security_password_salt'), isTrue);
      expect(names.contains('security_password_updated_at'), isTrue);
      expect(names.contains('ui_theme_mode'), isTrue);
      expect(names.contains('ui_density_mode'), isTrue);
      expect(names.contains('ui_chart_animations_enabled'), isTrue);
      expect(names.contains('ui_language_code'), isTrue);
    },
  );

  test('creates v19 operations alert state table', () async {
    final rows = await db.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: <Object?>['table', 'operations_alert_states'],
    );

    expect(rows, isNotEmpty);
  });

  test('creates v20 audit enterprise columns and v21 scenario workflow columns', () async {
    final auditColumns = await db.rawQuery('PRAGMA table_info(audit_log)');
    final auditNames = auditColumns.map((row) => row['name']).toSet();
    expect(auditNames.contains('occurred_at'), isTrue);
    expect(auditNames.contains('workspace_id'), isTrue);
    expect(auditNames.contains('actor_user_id'), isTrue);
    expect(auditNames.contains('actor_role'), isTrue);
    expect(auditNames.contains('parent_entity_type'), isTrue);
    expect(auditNames.contains('parent_entity_id'), isTrue);
    expect(auditNames.contains('old_values_json'), isTrue);
    expect(auditNames.contains('new_values_json'), isTrue);
    expect(auditNames.contains('correlation_id'), isTrue);
    expect(auditNames.contains('reason'), isTrue);
    expect(auditNames.contains('is_system_event'), isTrue);

    final scenarioColumns = await db.rawQuery('PRAGMA table_info(scenarios)');
    final scenarioNames = scenarioColumns.map((row) => row['name']).toSet();
    expect(scenarioNames.contains('workflow_status'), isTrue);
    expect(scenarioNames.contains('approved_by'), isTrue);
    expect(scenarioNames.contains('approved_at'), isTrue);
    expect(scenarioNames.contains('rejected_by'), isTrue);
    expect(scenarioNames.contains('rejected_at'), isTrue);
    expect(scenarioNames.contains('review_comment'), isTrue);
    expect(scenarioNames.contains('changed_since_approval'), isTrue);
  });
}
