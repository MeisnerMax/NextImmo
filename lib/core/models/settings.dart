class AppSettingsRecord {
  static const Object _unset = Object();

  const AppSettingsRecord({
    this.id = 1,
    this.currencyCode = 'EUR',
    this.locale = 'de_DE',
    this.defaultHorizonYears = 10,
    this.defaultVacancyPercent = 0.05,
    this.defaultManagementPercent = 0.08,
    this.defaultMaintenancePercent = 0.05,
    this.defaultCapexPercent = 0.05,
    this.defaultAppreciationPercent = 0.02,
    this.defaultRentGrowthPercent = 0.02,
    this.defaultExpenseGrowthPercent = 0.02,
    this.defaultSaleCostPercent = 0.06,
    this.defaultClosingCostBuyPercent = 0.03,
    this.defaultClosingCostSellPercent = 0.02,
    this.defaultDownPaymentPercent = 0.25,
    this.defaultInterestRatePercent = 0.06,
    this.defaultTermYears = 30,
    this.defaultReportTemplateId,
    this.compareVisibleMetrics = const <String>[
      'monthly_cashflow',
      'cap_rate',
      'cash_on_cash',
      'irr',
      'dscr',
    ],
    this.enableDemoSeed = false,
    this.notificationVacancyThreshold,
    this.notificationNoiDropThreshold,
    this.workspaceRootPath,
    this.lastBackupAt,
    this.lastBackupPath,
    this.lastTaskGenerationAt,
    this.taskDueSoonDays = 3,
    this.enableTaskNotifications = true,
    this.defaultMarketRentMode,
    this.budgetDefaultYearStartMonth,
    this.maintenanceDueSoonDays = 3,
    this.covenantDueSoonDays = 7,
    this.qualityEpcExpiryWarningDays = 90,
    this.qualityRentRollStaleMonths = 1,
    this.qualityLedgerStaleDays = 30,
    this.scenarioAutoDailyVersionsEnabled = false,
    this.scenarioAutoDailyVersionsUserId,
    this.activeWorkspaceId,
    this.activeUserId,
    this.securityAppLockEnabled = false,
    this.securityPasswordHash,
    this.securityPasswordSalt,
    this.securityPasswordUpdatedAt,
    this.uiThemeMode = 'system',
    this.uiDensityMode = 'comfort',
    this.uiChartAnimationsEnabled = true,
    required this.updatedAt,
  });

  final int id;
  final String currencyCode;
  final String locale;
  final int defaultHorizonYears;
  final double defaultVacancyPercent;
  final double defaultManagementPercent;
  final double defaultMaintenancePercent;
  final double defaultCapexPercent;
  final double defaultAppreciationPercent;
  final double defaultRentGrowthPercent;
  final double defaultExpenseGrowthPercent;
  final double defaultSaleCostPercent;
  final double defaultClosingCostBuyPercent;
  final double defaultClosingCostSellPercent;
  final double defaultDownPaymentPercent;
  final double defaultInterestRatePercent;
  final int defaultTermYears;
  final String? defaultReportTemplateId;
  final List<String> compareVisibleMetrics;
  final bool enableDemoSeed;
  final double? notificationVacancyThreshold;
  final double? notificationNoiDropThreshold;
  final String? workspaceRootPath;
  final int? lastBackupAt;
  final String? lastBackupPath;
  final int? lastTaskGenerationAt;
  final int taskDueSoonDays;
  final bool enableTaskNotifications;
  final String? defaultMarketRentMode;
  final int? budgetDefaultYearStartMonth;
  final int maintenanceDueSoonDays;
  final int covenantDueSoonDays;
  final int qualityEpcExpiryWarningDays;
  final int qualityRentRollStaleMonths;
  final int qualityLedgerStaleDays;
  final bool scenarioAutoDailyVersionsEnabled;
  final String? scenarioAutoDailyVersionsUserId;
  final String? activeWorkspaceId;
  final String? activeUserId;
  final bool securityAppLockEnabled;
  final String? securityPasswordHash;
  final String? securityPasswordSalt;
  final int? securityPasswordUpdatedAt;
  final String uiThemeMode;
  final String uiDensityMode;
  final bool uiChartAnimationsEnabled;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'currency_code': currencyCode,
      'locale': locale,
      'default_horizon_years': defaultHorizonYears,
      'default_vacancy_percent': defaultVacancyPercent,
      'default_management_percent': defaultManagementPercent,
      'default_maintenance_percent': defaultMaintenancePercent,
      'default_capex_percent': defaultCapexPercent,
      'default_appreciation_percent': defaultAppreciationPercent,
      'default_rent_growth_percent': defaultRentGrowthPercent,
      'default_expense_growth_percent': defaultExpenseGrowthPercent,
      'default_sale_cost_percent': defaultSaleCostPercent,
      'default_closing_cost_buy_percent': defaultClosingCostBuyPercent,
      'default_closing_cost_sell_percent': defaultClosingCostSellPercent,
      'default_down_payment_percent': defaultDownPaymentPercent,
      'default_interest_rate_percent': defaultInterestRatePercent,
      'default_term_years': defaultTermYears,
      'default_report_template_id': defaultReportTemplateId,
      'compare_visible_metrics': compareVisibleMetrics.join(','),
      'enable_demo_seed': enableDemoSeed ? 1 : 0,
      'notification_vacancy_threshold': notificationVacancyThreshold,
      'notification_noi_drop_threshold': notificationNoiDropThreshold,
      'workspace_root_path': workspaceRootPath,
      'last_backup_at': lastBackupAt,
      'last_backup_path': lastBackupPath,
      'last_task_generation_at': lastTaskGenerationAt,
      'task_due_soon_days': taskDueSoonDays,
      'enable_task_notifications': enableTaskNotifications ? 1 : 0,
      'default_market_rent_mode': defaultMarketRentMode,
      'budget_default_year_start_month': budgetDefaultYearStartMonth,
      'maintenance_due_soon_days': maintenanceDueSoonDays,
      'covenant_due_soon_days': covenantDueSoonDays,
      'quality_epc_expiry_warning_days': qualityEpcExpiryWarningDays,
      'quality_rent_roll_stale_months': qualityRentRollStaleMonths,
      'quality_ledger_stale_days': qualityLedgerStaleDays,
      'scenario_auto_daily_versions_enabled':
          scenarioAutoDailyVersionsEnabled ? 1 : 0,
      'scenario_auto_daily_versions_user_id': scenarioAutoDailyVersionsUserId,
      'active_workspace_id': activeWorkspaceId,
      'active_user_id': activeUserId,
      'security_app_lock_enabled': securityAppLockEnabled ? 1 : 0,
      'security_password_hash': securityPasswordHash,
      'security_password_salt': securityPasswordSalt,
      'security_password_updated_at': securityPasswordUpdatedAt,
      'ui_theme_mode': uiThemeMode,
      'ui_density_mode': uiDensityMode,
      'ui_chart_animations_enabled': uiChartAnimationsEnabled ? 1 : 0,
      'updated_at': updatedAt,
    };
  }

  factory AppSettingsRecord.fromMap(Map<String, Object?> map) {
    return AppSettingsRecord(
      id: ((map['id'] as num?) ?? 1).toInt(),
      currencyCode: (map['currency_code'] as String?) ?? 'EUR',
      locale: (map['locale'] as String?) ?? 'de_DE',
      defaultHorizonYears:
          ((map['default_horizon_years'] as num?) ?? 10).toInt(),
      defaultVacancyPercent:
          ((map['default_vacancy_percent'] as num?) ?? 0.05).toDouble(),
      defaultManagementPercent:
          ((map['default_management_percent'] as num?) ?? 0.08).toDouble(),
      defaultMaintenancePercent:
          ((map['default_maintenance_percent'] as num?) ?? 0.05).toDouble(),
      defaultCapexPercent:
          ((map['default_capex_percent'] as num?) ?? 0.05).toDouble(),
      defaultAppreciationPercent:
          ((map['default_appreciation_percent'] as num?) ?? 0.02).toDouble(),
      defaultRentGrowthPercent:
          ((map['default_rent_growth_percent'] as num?) ?? 0.02).toDouble(),
      defaultExpenseGrowthPercent:
          ((map['default_expense_growth_percent'] as num?) ?? 0.02).toDouble(),
      defaultSaleCostPercent:
          ((map['default_sale_cost_percent'] as num?) ?? 0.06).toDouble(),
      defaultClosingCostBuyPercent:
          ((map['default_closing_cost_buy_percent'] as num?) ?? 0.03)
              .toDouble(),
      defaultClosingCostSellPercent:
          ((map['default_closing_cost_sell_percent'] as num?) ?? 0.02)
              .toDouble(),
      defaultDownPaymentPercent:
          ((map['default_down_payment_percent'] as num?) ?? 0.25).toDouble(),
      defaultInterestRatePercent:
          ((map['default_interest_rate_percent'] as num?) ?? 0.06).toDouble(),
      defaultTermYears: ((map['default_term_years'] as num?) ?? 30).toInt(),
      defaultReportTemplateId: map['default_report_template_id'] as String?,
      compareVisibleMetrics: _parseCompareMetrics(
        map['compare_visible_metrics'],
      ),
      enableDemoSeed: ((map['enable_demo_seed'] as num?) ?? 0) == 1,
      notificationVacancyThreshold:
          (map['notification_vacancy_threshold'] as num?)?.toDouble(),
      notificationNoiDropThreshold:
          (map['notification_noi_drop_threshold'] as num?)?.toDouble(),
      workspaceRootPath: map['workspace_root_path'] as String?,
      lastBackupAt: (map['last_backup_at'] as num?)?.toInt(),
      lastBackupPath: map['last_backup_path'] as String?,
      lastTaskGenerationAt: (map['last_task_generation_at'] as num?)?.toInt(),
      taskDueSoonDays: ((map['task_due_soon_days'] as num?) ?? 3).toInt(),
      enableTaskNotifications:
          ((map['enable_task_notifications'] as num?) ?? 1) == 1,
      defaultMarketRentMode: map['default_market_rent_mode'] as String?,
      budgetDefaultYearStartMonth:
          (map['budget_default_year_start_month'] as num?)?.toInt(),
      maintenanceDueSoonDays:
          ((map['maintenance_due_soon_days'] as num?) ?? 3).toInt(),
      covenantDueSoonDays:
          ((map['covenant_due_soon_days'] as num?) ?? 7).toInt(),
      qualityEpcExpiryWarningDays:
          ((map['quality_epc_expiry_warning_days'] as num?) ?? 90).toInt(),
      qualityRentRollStaleMonths:
          ((map['quality_rent_roll_stale_months'] as num?) ?? 1).toInt(),
      qualityLedgerStaleDays:
          ((map['quality_ledger_stale_days'] as num?) ?? 30).toInt(),
      scenarioAutoDailyVersionsEnabled:
          ((map['scenario_auto_daily_versions_enabled'] as num?) ?? 0) == 1,
      scenarioAutoDailyVersionsUserId:
          map['scenario_auto_daily_versions_user_id'] as String?,
      activeWorkspaceId: map['active_workspace_id'] as String?,
      activeUserId: map['active_user_id'] as String?,
      securityAppLockEnabled:
          ((map['security_app_lock_enabled'] as num?) ?? 0) == 1,
      securityPasswordHash: map['security_password_hash'] as String?,
      securityPasswordSalt: map['security_password_salt'] as String?,
      securityPasswordUpdatedAt:
          (map['security_password_updated_at'] as num?)?.toInt(),
      uiThemeMode: (map['ui_theme_mode'] as String?) ?? 'system',
      uiDensityMode: (map['ui_density_mode'] as String?) ?? 'comfort',
      uiChartAnimationsEnabled:
          ((map['ui_chart_animations_enabled'] as num?) ?? 1) == 1,
      updatedAt:
          ((map['updated_at'] as num?) ?? DateTime.now().millisecondsSinceEpoch)
              .toInt(),
    );
  }

  static List<String> _parseCompareMetrics(Object? raw) {
    final value = raw as String?;
    if (value == null || value.trim().isEmpty) {
      return const <String>[
        'monthly_cashflow',
        'cap_rate',
        'cash_on_cash',
        'irr',
        'dscr',
      ];
    }
    return value
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  AppSettingsRecord copyWith({
    int? id,
    String? currencyCode,
    String? locale,
    int? defaultHorizonYears,
    double? defaultVacancyPercent,
    double? defaultManagementPercent,
    double? defaultMaintenancePercent,
    double? defaultCapexPercent,
    double? defaultAppreciationPercent,
    double? defaultRentGrowthPercent,
    double? defaultExpenseGrowthPercent,
    double? defaultSaleCostPercent,
    double? defaultClosingCostBuyPercent,
    double? defaultClosingCostSellPercent,
    double? defaultDownPaymentPercent,
    double? defaultInterestRatePercent,
    int? defaultTermYears,
    Object? defaultReportTemplateId = _unset,
    List<String>? compareVisibleMetrics,
    bool? enableDemoSeed,
    Object? notificationVacancyThreshold = _unset,
    Object? notificationNoiDropThreshold = _unset,
    Object? workspaceRootPath = _unset,
    Object? lastBackupAt = _unset,
    Object? lastBackupPath = _unset,
    Object? lastTaskGenerationAt = _unset,
    int? taskDueSoonDays,
    bool? enableTaskNotifications,
    Object? defaultMarketRentMode = _unset,
    Object? budgetDefaultYearStartMonth = _unset,
    int? maintenanceDueSoonDays,
    int? covenantDueSoonDays,
    int? qualityEpcExpiryWarningDays,
    int? qualityRentRollStaleMonths,
    int? qualityLedgerStaleDays,
    bool? scenarioAutoDailyVersionsEnabled,
    Object? scenarioAutoDailyVersionsUserId = _unset,
    Object? activeWorkspaceId = _unset,
    Object? activeUserId = _unset,
    bool? securityAppLockEnabled,
    Object? securityPasswordHash = _unset,
    Object? securityPasswordSalt = _unset,
    Object? securityPasswordUpdatedAt = _unset,
    String? uiThemeMode,
    String? uiDensityMode,
    bool? uiChartAnimationsEnabled,
    int? updatedAt,
  }) {
    return AppSettingsRecord(
      id: id ?? this.id,
      currencyCode: currencyCode ?? this.currencyCode,
      locale: locale ?? this.locale,
      defaultHorizonYears: defaultHorizonYears ?? this.defaultHorizonYears,
      defaultVacancyPercent:
          defaultVacancyPercent ?? this.defaultVacancyPercent,
      defaultManagementPercent:
          defaultManagementPercent ?? this.defaultManagementPercent,
      defaultMaintenancePercent:
          defaultMaintenancePercent ?? this.defaultMaintenancePercent,
      defaultCapexPercent: defaultCapexPercent ?? this.defaultCapexPercent,
      defaultAppreciationPercent:
          defaultAppreciationPercent ?? this.defaultAppreciationPercent,
      defaultRentGrowthPercent:
          defaultRentGrowthPercent ?? this.defaultRentGrowthPercent,
      defaultExpenseGrowthPercent:
          defaultExpenseGrowthPercent ?? this.defaultExpenseGrowthPercent,
      defaultSaleCostPercent:
          defaultSaleCostPercent ?? this.defaultSaleCostPercent,
      defaultClosingCostBuyPercent:
          defaultClosingCostBuyPercent ?? this.defaultClosingCostBuyPercent,
      defaultClosingCostSellPercent:
          defaultClosingCostSellPercent ?? this.defaultClosingCostSellPercent,
      defaultDownPaymentPercent:
          defaultDownPaymentPercent ?? this.defaultDownPaymentPercent,
      defaultInterestRatePercent:
          defaultInterestRatePercent ?? this.defaultInterestRatePercent,
      defaultTermYears: defaultTermYears ?? this.defaultTermYears,
      defaultReportTemplateId:
          identical(defaultReportTemplateId, _unset)
              ? this.defaultReportTemplateId
              : defaultReportTemplateId as String?,
      compareVisibleMetrics:
          compareVisibleMetrics ?? this.compareVisibleMetrics,
      enableDemoSeed: enableDemoSeed ?? this.enableDemoSeed,
      notificationVacancyThreshold:
          identical(notificationVacancyThreshold, _unset)
              ? this.notificationVacancyThreshold
              : notificationVacancyThreshold as double?,
      notificationNoiDropThreshold:
          identical(notificationNoiDropThreshold, _unset)
              ? this.notificationNoiDropThreshold
              : notificationNoiDropThreshold as double?,
      workspaceRootPath:
          identical(workspaceRootPath, _unset)
              ? this.workspaceRootPath
              : workspaceRootPath as String?,
      lastBackupAt:
          identical(lastBackupAt, _unset)
              ? this.lastBackupAt
              : lastBackupAt as int?,
      lastBackupPath:
          identical(lastBackupPath, _unset)
              ? this.lastBackupPath
              : lastBackupPath as String?,
      lastTaskGenerationAt:
          identical(lastTaskGenerationAt, _unset)
              ? this.lastTaskGenerationAt
              : lastTaskGenerationAt as int?,
      taskDueSoonDays: taskDueSoonDays ?? this.taskDueSoonDays,
      enableTaskNotifications:
          enableTaskNotifications ?? this.enableTaskNotifications,
      defaultMarketRentMode:
          identical(defaultMarketRentMode, _unset)
              ? this.defaultMarketRentMode
              : defaultMarketRentMode as String?,
      budgetDefaultYearStartMonth:
          identical(budgetDefaultYearStartMonth, _unset)
              ? this.budgetDefaultYearStartMonth
              : budgetDefaultYearStartMonth as int?,
      maintenanceDueSoonDays:
          maintenanceDueSoonDays ?? this.maintenanceDueSoonDays,
      covenantDueSoonDays: covenantDueSoonDays ?? this.covenantDueSoonDays,
      qualityEpcExpiryWarningDays:
          qualityEpcExpiryWarningDays ?? this.qualityEpcExpiryWarningDays,
      qualityRentRollStaleMonths:
          qualityRentRollStaleMonths ?? this.qualityRentRollStaleMonths,
      qualityLedgerStaleDays:
          qualityLedgerStaleDays ?? this.qualityLedgerStaleDays,
      scenarioAutoDailyVersionsEnabled:
          scenarioAutoDailyVersionsEnabled ??
          this.scenarioAutoDailyVersionsEnabled,
      scenarioAutoDailyVersionsUserId:
          identical(scenarioAutoDailyVersionsUserId, _unset)
              ? this.scenarioAutoDailyVersionsUserId
              : scenarioAutoDailyVersionsUserId as String?,
      activeWorkspaceId:
          identical(activeWorkspaceId, _unset)
              ? this.activeWorkspaceId
              : activeWorkspaceId as String?,
      activeUserId:
          identical(activeUserId, _unset)
              ? this.activeUserId
              : activeUserId as String?,
      securityAppLockEnabled:
          securityAppLockEnabled ?? this.securityAppLockEnabled,
      securityPasswordHash:
          identical(securityPasswordHash, _unset)
              ? this.securityPasswordHash
              : securityPasswordHash as String?,
      securityPasswordSalt:
          identical(securityPasswordSalt, _unset)
              ? this.securityPasswordSalt
              : securityPasswordSalt as String?,
      securityPasswordUpdatedAt:
          identical(securityPasswordUpdatedAt, _unset)
              ? this.securityPasswordUpdatedAt
              : securityPasswordUpdatedAt as int?,
      uiThemeMode: uiThemeMode ?? this.uiThemeMode,
      uiDensityMode: uiDensityMode ?? this.uiDensityMode,
      uiChartAnimationsEnabled:
          uiChartAnimationsEnabled ?? this.uiChartAnimationsEnabled,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
