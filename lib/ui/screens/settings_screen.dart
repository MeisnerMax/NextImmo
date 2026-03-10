import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/security/rbac.dart';
import '../../core/models/settings.dart';
import '../../data/sqlite/migrations.dart';
import '../components/nx_card.dart';
import '../components/nx_form_section_card.dart';
import '../components/responsive_constraints.dart';
import '../components/save_status_indicator.dart';
import '../state/app_state.dart';
import '../state/security_state.dart';
import '../templates/settings_template.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AppSettingsRecord? _settings;
  String? _status;
  String? _statusDetail;
  SaveStatusTone? _statusTone;
  DateTime? _lastSavedAt;
  bool _isSaving = false;
  bool _isHydrating = false;

  final _currencyController = TextEditingController();
  final _localeController = TextEditingController();
  final _horizonController = TextEditingController();
  final _vacancyController = TextEditingController();
  final _managementController = TextEditingController();
  final _maintenanceController = TextEditingController();
  final _capexController = TextEditingController();
  final _appreciationController = TextEditingController();
  final _rentGrowthController = TextEditingController();
  final _expenseGrowthController = TextEditingController();
  final _saleCostController = TextEditingController();
  final _closingBuyController = TextEditingController();
  final _closingSellController = TextEditingController();
  final _downPaymentController = TextEditingController();
  final _interestController = TextEditingController();
  final _termYearsController = TextEditingController();
  final _vacancyAlertController = TextEditingController();
  final _noiDropAlertController = TextEditingController();
  final _workspaceRootController = TextEditingController();
  final _taskDueSoonDaysController = TextEditingController();
  final _defaultMarketRentModeController = TextEditingController();
  final _budgetYearStartMonthController = TextEditingController();
  final _maintenanceDueSoonDaysController = TextEditingController();
  final _covenantDueSoonDaysController = TextEditingController();
  final _qualityEpcExpiryWarningDaysController = TextEditingController();
  final _qualityRentRollStaleMonthsController = TextEditingController();
  final _qualityLedgerStaleDaysController = TextEditingController();
  final _scenarioAutoDailyVersionsUserController = TextEditingController();
  final _appLockPasswordController = TextEditingController();
  bool _enableDemoSeed = false;
  bool _enableTaskNotifications = true;
  bool _enableAppLock = false;
  bool _scenarioAutoDailyVersionsEnabled = false;
  String _uiThemeMode = 'system';
  String _uiDensityMode = 'comfort';
  bool _uiChartAnimationsEnabled = true;
  String _selectedSectionId = 'general';

  static const Map<String, String> _sectionTitles = <String, String>{
    'general': 'General',
    'analysis_defaults': 'Analysis Defaults',
    'operations_defaults': 'Operations Defaults',
    'alerts': 'Alerts',
    'appearance': 'Appearance',
    'security': 'Security',
    'backup_restore': 'Backup & Restore',
    'admin': 'Admin',
  };

  List<TextEditingController> get _allControllers => <TextEditingController>[
    _currencyController,
    _localeController,
    _horizonController,
    _vacancyController,
    _managementController,
    _maintenanceController,
    _capexController,
    _appreciationController,
    _rentGrowthController,
    _expenseGrowthController,
    _saleCostController,
    _closingBuyController,
    _closingSellController,
    _downPaymentController,
    _interestController,
    _termYearsController,
    _vacancyAlertController,
    _noiDropAlertController,
    _workspaceRootController,
    _taskDueSoonDaysController,
    _defaultMarketRentModeController,
    _budgetYearStartMonthController,
    _maintenanceDueSoonDaysController,
    _covenantDueSoonDaysController,
    _qualityEpcExpiryWarningDaysController,
    _qualityRentRollStaleMonthsController,
    _qualityLedgerStaleDaysController,
    _scenarioAutoDailyVersionsUserController,
    _appLockPasswordController,
  ];

  @override
  void initState() {
    super.initState();
    for (final controller in _allControllers) {
      controller.addListener(_handleDraftChanged);
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in _allControllers) {
      controller.removeListener(_handleDraftChanged);
    }
    _currencyController.dispose();
    _localeController.dispose();
    _horizonController.dispose();
    _vacancyController.dispose();
    _managementController.dispose();
    _maintenanceController.dispose();
    _capexController.dispose();
    _appreciationController.dispose();
    _rentGrowthController.dispose();
    _expenseGrowthController.dispose();
    _saleCostController.dispose();
    _closingBuyController.dispose();
    _closingSellController.dispose();
    _downPaymentController.dispose();
    _interestController.dispose();
    _termYearsController.dispose();
    _vacancyAlertController.dispose();
    _noiDropAlertController.dispose();
    _workspaceRootController.dispose();
    _taskDueSoonDaysController.dispose();
    _defaultMarketRentModeController.dispose();
    _budgetYearStartMonthController.dispose();
    _maintenanceDueSoonDaysController.dispose();
    _covenantDueSoonDaysController.dispose();
    _qualityEpcExpiryWarningDaysController.dispose();
    _qualityRentRollStaleMonthsController.dispose();
    _qualityLedgerStaleDaysController.dispose();
    _scenarioAutoDailyVersionsUserController.dispose();
    _appLockPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final role = ref.watch(activeUserRoleProvider);
    final rbac = ref.watch(rbacProvider);
    final canSettingsEdit = rbac.can(
      action: RbacAction.settingsEdit,
      role: role,
    );
    final canBackupRestore = rbac.can(
      action: RbacAction.backupRestore,
      role: role,
    );
    final canExport = rbac.can(action: RbacAction.export, role: role);
    final saveChanges = _collectSaveChanges(settings);
    final securityChanges = _collectSecurityChanges(settings);
    final hasDraftChanges =
        saveChanges.isNotEmpty || securityChanges.isNotEmpty;
    final headerStatus = _buildHeaderStatus(
      saveChanges: saveChanges,
      securityChanges: securityChanges,
      canSettingsEdit: canSettingsEdit,
    );

    return SettingsTemplate(
      title: 'Settings',
      breadcrumbs: const ['System', 'Settings'],
      subtitle:
          'Use clear defaults, isolate risky actions, and keep every change visible.',
      navigationItems: _navigationItems(
        saveChanges: saveChanges,
        securityChanges: securityChanges,
      ),
      selectedId: _selectedSectionId,
      onSelect: (value) => setState(() => _selectedSectionId = value),
      saveStatus: SaveStatusIndicator(
        label: headerStatus.label,
        detail: headerStatus.detail,
        tone: headerStatus.tone,
        compact: true,
      ),
      primaryAction: ElevatedButton(
        onPressed:
            canSettingsEdit && !_isSaving && saveChanges.isNotEmpty
                ? _save
                : null,
        child: Text(_isSaving ? 'Saving...' : 'Save Settings'),
      ),
      secondaryActions: [
        OutlinedButton(
          onPressed: () => _reloadOrDiscard(hasDraftChanges),
          child: Text(hasDraftChanges ? 'Discard Draft' : 'Reload'),
        ),
      ],
      content: SingleChildScrollView(
        child: _buildSettingsContent(
          context: context,
          settings: settings,
          canSettingsEdit: canSettingsEdit,
          canBackupRestore: canBackupRestore,
          canExport: canExport,
          saveChanges: saveChanges,
          securityChanges: securityChanges,
        ),
      ),
    );
  }

  List<SettingsNavigationItem> _navigationItems({
    required List<_SettingChange> saveChanges,
    required List<_SettingChange> securityChanges,
  }) {
    final counts = _countChangesBySection(<_SettingChange>[
      ...saveChanges,
      ...securityChanges,
    ]);
    SettingsNavigationItem item({
      required String id,
      required String label,
      required IconData icon,
      required String description,
      bool dangerous = false,
    }) {
      final changeCount = counts[id] ?? 0;
      return SettingsNavigationItem(
        id: id,
        label: label,
        icon: icon,
        description: description,
        badgeLabel:
            changeCount > 0
                ? '$changeCount'
                : dangerous
                ? 'Risk'
                : null,
        badgeKind:
            changeCount > 0
                ? SettingsNavigationBadgeKind.warning
                : dangerous
                ? SettingsNavigationBadgeKind.danger
                : SettingsNavigationBadgeKind.neutral,
      );
    }

    return <SettingsNavigationItem>[
      item(
        id: 'general',
        label: 'General',
        icon: Icons.tune_outlined,
        description: 'Locale, currency, and core scenario defaults.',
      ),
      item(
        id: 'analysis_defaults',
        label: 'Analysis Defaults',
        icon: Icons.analytics_outlined,
        description: 'Underwriting, growth, exit, and financing defaults.',
      ),
      item(
        id: 'operations_defaults',
        label: 'Operations Defaults',
        icon: Icons.build_circle_outlined,
        description: 'Task, maintenance, covenant, and automation defaults.',
      ),
      item(
        id: 'alerts',
        label: 'Alerts',
        icon: Icons.notifications_active_outlined,
        description: 'Thresholds and quality warning behavior.',
      ),
      item(
        id: 'appearance',
        label: 'Appearance',
        icon: Icons.palette_outlined,
        description: 'Theme, density, and interface motion.',
      ),
      item(
        id: 'security',
        label: 'Security',
        icon: Icons.lock_outline,
        description: 'App lock and restricted actions.',
        dangerous: true,
      ),
      item(
        id: 'backup_restore',
        label: 'Backup & Restore',
        icon: Icons.backup_outlined,
        description: 'Workspace path plus backup and restore actions.',
        dangerous: true,
      ),
      item(
        id: 'admin',
        label: 'Admin',
        icon: Icons.admin_panel_settings_outlined,
        description: 'Demo data and administrative helper settings.',
        dangerous: true,
      ),
    ];
  }

  _HeaderStatus _buildHeaderStatus({
    required List<_SettingChange> saveChanges,
    required List<_SettingChange> securityChanges,
    required bool canSettingsEdit,
  }) {
    if (_isSaving) {
      return _HeaderStatus(
        label: 'Saving settings...',
        detail:
            'Applying ${saveChanges.length} pending change${saveChanges.length == 1 ? '' : 's'}.',
        tone: SaveStatusTone.working,
      );
    }
    if (_statusTone == SaveStatusTone.error && _status != null) {
      return _HeaderStatus(
        label: _status!,
        detail: _statusDetail,
        tone: SaveStatusTone.error,
      );
    }
    if (saveChanges.isNotEmpty) {
      final sections = _countChangesBySection(
        saveChanges,
      ).keys.map((id) => _sectionTitles[id] ?? id).join(', ');
      return _HeaderStatus(
        label:
            '${saveChanges.length} unsaved change${saveChanges.length == 1 ? '' : 's'}',
        detail:
            sections.isEmpty
                ? 'Use Save Settings to commit the current draft.'
                : 'Changed sections: $sections',
        tone: canSettingsEdit ? SaveStatusTone.warning : SaveStatusTone.neutral,
      );
    }
    if (_selectedSectionId == 'security' && securityChanges.isNotEmpty) {
      return _HeaderStatus(
        label:
            '${securityChanges.length} security change${securityChanges.length == 1 ? '' : 's'} ready',
        detail: 'Use Apply Security in this section to commit them.',
        tone: SaveStatusTone.warning,
      );
    }
    if (_status != null && _statusTone != null) {
      return _HeaderStatus(
        label: _status!,
        detail: _statusDetail,
        tone: _statusTone!,
      );
    }
    return _HeaderStatus(
      label: 'All changes saved',
      detail:
          _lastSavedAt == null
              ? 'No local draft is pending.'
              : 'Last saved ${_formatTimestamp(_lastSavedAt)}',
      tone: SaveStatusTone.success,
    );
  }

  Widget _buildDraftOverview(
    BuildContext context, {
    required List<_SettingChange> saveChanges,
    required List<_SettingChange> securityChanges,
    required bool canSettingsEdit,
  }) {
    final allChanges = <_SettingChange>[...saveChanges, ...securityChanges];
    final currentSectionChanges =
        allChanges
            .where((change) => change.sectionId == _selectedSectionId)
            .toList();
    final counts = _countChangesBySection(allChanges);
    final status = _buildHeaderStatus(
      saveChanges: saveChanges,
      securityChanges: securityChanges,
      canSettingsEdit: canSettingsEdit,
    );
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Save Overview',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SaveStatusIndicator(
                label: status.label,
                detail: status.detail,
                tone: status.tone,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Text(
            canSettingsEdit
                ? 'General settings save through the header action. Security changes are applied separately inside the Security section.'
                : 'This role can review settings, but cannot save configuration changes.',
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _overviewChip(context, 'Pending fields', '${allChanges.length}'),
              _overviewChip(context, 'Changed sections', '${counts.length}'),
              _overviewChip(
                context,
                'Selected section',
                _sectionTitles[_selectedSectionId] ?? _selectedSectionId,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Text(
            currentSectionChanges.isEmpty
                ? 'No pending draft changes in this section.'
                : 'Pending changes in this section',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (currentSectionChanges.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final change in currentSectionChanges.take(6))
                  _changeChip(context, change),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _overviewChip(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _changeChip(BuildContext context, _SettingChange change) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Text(
        '${change.label}: ${change.previousValue} -> ${change.nextValue}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Map<String, int> _countChangesBySection(List<_SettingChange> changes) {
    final counts = <String, int>{};
    for (final change in changes) {
      counts.update(change.sectionId, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  List<_SettingChange> _collectSecurityChanges(AppSettingsRecord settings) {
    final changes = <_SettingChange>[];
    if (_enableAppLock != settings.securityAppLockEnabled) {
      changes.add(
        _SettingChange(
          sectionId: 'security',
          label: 'Enable App Lock',
          previousValue: settings.securityAppLockEnabled ? 'On' : 'Off',
          nextValue: _enableAppLock ? 'On' : 'Off',
        ),
      );
    }
    if (_appLockPasswordController.text.trim().isNotEmpty) {
      changes.add(
        const _SettingChange(
          sectionId: 'security',
          label: 'App Lock Password',
          previousValue: 'Keep current password',
          nextValue: 'Replace password',
        ),
      );
    }
    return changes;
  }

  List<_SettingChange> _collectSaveChanges(AppSettingsRecord settings) {
    final changes = <_SettingChange>[];

    void addText({
      required String sectionId,
      required String label,
      required String currentValue,
      required String savedValue,
    }) {
      final current = currentValue.trim();
      final saved = savedValue.trim();
      if (current == saved) {
        return;
      }
      changes.add(
        _SettingChange(
          sectionId: sectionId,
          label: label,
          previousValue: saved.isEmpty ? 'Not set' : saved,
          nextValue: current.isEmpty ? 'Not set' : current,
        ),
      );
    }

    void addBool({
      required String sectionId,
      required String label,
      required bool currentValue,
      required bool savedValue,
    }) {
      if (currentValue == savedValue) {
        return;
      }
      changes.add(
        _SettingChange(
          sectionId: sectionId,
          label: label,
          previousValue: savedValue ? 'On' : 'Off',
          nextValue: currentValue ? 'On' : 'Off',
        ),
      );
    }

    void addNumber({
      required String sectionId,
      required String label,
      required String currentValue,
      required String savedValue,
      bool isPercent = false,
    }) {
      final current = currentValue.trim();
      if (current == savedValue.trim()) {
        return;
      }
      changes.add(
        _SettingChange(
          sectionId: sectionId,
          label: label,
          previousValue:
              isPercent ? _formatPercentString(savedValue) : savedValue,
          nextValue:
              current.isEmpty
                  ? 'Not set'
                  : isPercent
                  ? _formatPercentString(current)
                  : current,
        ),
      );
    }

    addText(
      sectionId: 'general',
      label: 'Currency Code',
      currentValue: _currencyController.text,
      savedValue: settings.currencyCode,
    );
    addText(
      sectionId: 'general',
      label: 'Locale',
      currentValue: _localeController.text,
      savedValue: settings.locale,
    );
    addNumber(
      sectionId: 'general',
      label: 'Default Horizon Years',
      currentValue: _horizonController.text,
      savedValue: settings.defaultHorizonYears.toString(),
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Vacancy Rate',
      currentValue: _vacancyController.text,
      savedValue: settings.defaultVacancyPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Management Fee Rate',
      currentValue: _managementController.text,
      savedValue: settings.defaultManagementPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Maintenance Reserve Rate',
      currentValue: _maintenanceController.text,
      savedValue: settings.defaultMaintenancePercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'CapEx Reserve Rate',
      currentValue: _capexController.text,
      savedValue: settings.defaultCapexPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Appreciation Rate',
      currentValue: _appreciationController.text,
      savedValue: settings.defaultAppreciationPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Rent Growth Rate',
      currentValue: _rentGrowthController.text,
      savedValue: settings.defaultRentGrowthPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Expense Growth Rate',
      currentValue: _expenseGrowthController.text,
      savedValue: settings.defaultExpenseGrowthPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Sale Cost Rate',
      currentValue: _saleCostController.text,
      savedValue: settings.defaultSaleCostPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Acquisition Cost Rate',
      currentValue: _closingBuyController.text,
      savedValue: settings.defaultClosingCostBuyPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Disposition Closing Cost Rate',
      currentValue: _closingSellController.text,
      savedValue: settings.defaultClosingCostSellPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Down Payment Rate',
      currentValue: _downPaymentController.text,
      savedValue: settings.defaultDownPaymentPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Interest Rate',
      currentValue: _interestController.text,
      savedValue: settings.defaultInterestRatePercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: 'Loan Term Years',
      currentValue: _termYearsController.text,
      savedValue: settings.defaultTermYears.toString(),
    );
    addText(
      sectionId: 'analysis_defaults',
      label: 'Market Rent Mode',
      currentValue: _defaultMarketRentModeController.text,
      savedValue: settings.defaultMarketRentMode ?? '',
    );
    addNumber(
      sectionId: 'operations_defaults',
      label: 'Task Due Soon Days',
      currentValue: _taskDueSoonDaysController.text,
      savedValue: settings.taskDueSoonDays.toString(),
    );
    addNumber(
      sectionId: 'operations_defaults',
      label: 'Budget Year Start Month',
      currentValue: _budgetYearStartMonthController.text,
      savedValue: settings.budgetDefaultYearStartMonth?.toString() ?? '',
    );
    addNumber(
      sectionId: 'operations_defaults',
      label: 'Maintenance Due Soon Days',
      currentValue: _maintenanceDueSoonDaysController.text,
      savedValue: settings.maintenanceDueSoonDays.toString(),
    );
    addNumber(
      sectionId: 'operations_defaults',
      label: 'Covenant Due Soon Days',
      currentValue: _covenantDueSoonDaysController.text,
      savedValue: settings.covenantDueSoonDays.toString(),
    );
    addBool(
      sectionId: 'operations_defaults',
      label: 'Scenario Auto Daily Versions',
      currentValue: _scenarioAutoDailyVersionsEnabled,
      savedValue: settings.scenarioAutoDailyVersionsEnabled,
    );
    addText(
      sectionId: 'admin',
      label: 'Auto Version User Id',
      currentValue: _scenarioAutoDailyVersionsUserController.text,
      savedValue: settings.scenarioAutoDailyVersionsUserId ?? '',
    );
    addNumber(
      sectionId: 'alerts',
      label: 'Vacancy Alert Threshold',
      currentValue: _vacancyAlertController.text,
      savedValue: settings.notificationVacancyThreshold?.toString() ?? '',
      isPercent: true,
    );
    addNumber(
      sectionId: 'alerts',
      label: 'NOI Drop Alert Threshold',
      currentValue: _noiDropAlertController.text,
      savedValue: settings.notificationNoiDropThreshold?.toString() ?? '',
      isPercent: true,
    );
    addNumber(
      sectionId: 'alerts',
      label: 'EPC Expiry Warning Days',
      currentValue: _qualityEpcExpiryWarningDaysController.text,
      savedValue: settings.qualityEpcExpiryWarningDays.toString(),
    );
    addNumber(
      sectionId: 'alerts',
      label: 'Rent Roll Stale Months',
      currentValue: _qualityRentRollStaleMonthsController.text,
      savedValue: settings.qualityRentRollStaleMonths.toString(),
    );
    addNumber(
      sectionId: 'alerts',
      label: 'Ledger Stale Days',
      currentValue: _qualityLedgerStaleDaysController.text,
      savedValue: settings.qualityLedgerStaleDays.toString(),
    );
    addBool(
      sectionId: 'alerts',
      label: 'Task Notifications',
      currentValue: _enableTaskNotifications,
      savedValue: settings.enableTaskNotifications,
    );
    addText(
      sectionId: 'backup_restore',
      label: 'Workspace Root Path',
      currentValue: _workspaceRootController.text,
      savedValue: settings.workspaceRootPath ?? '',
    );
    addText(
      sectionId: 'appearance',
      label: 'Theme Mode',
      currentValue: _uiThemeMode,
      savedValue: settings.uiThemeMode,
    );
    addText(
      sectionId: 'appearance',
      label: 'Density Mode',
      currentValue: _uiDensityMode,
      savedValue: settings.uiDensityMode,
    );
    addBool(
      sectionId: 'appearance',
      label: 'Chart Animations',
      currentValue: _uiChartAnimationsEnabled,
      savedValue: settings.uiChartAnimationsEnabled,
    );
    addBool(
      sectionId: 'admin',
      label: 'Enable Demo Seed Button',
      currentValue: _enableDemoSeed,
      savedValue: settings.enableDemoSeed,
    );

    return changes;
  }

  Widget _buildSettingsContent({
    required BuildContext context,
    required AppSettingsRecord settings,
    required bool canSettingsEdit,
    required bool canBackupRestore,
    required bool canExport,
    required List<_SettingChange> saveChanges,
    required List<_SettingChange> securityChanges,
  }) {
    late final Widget content;
    switch (_selectedSectionId) {
      case 'general':
        content = Column(
          children: [
            _introCard(
              title: 'General',
              description:
                  'These defaults shape new scenarios before property-specific inputs take over.',
            ),
            const SizedBox(height: AppSpacing.component),
            _section(
              context,
              title: 'General Defaults',
              children: [
                _field(
                  _currencyController,
                  'Currency Code',
                  enabled: canSettingsEdit,
                  helperText: 'Used in new scenarios and reports.',
                ),
                _field(
                  _localeController,
                  'Locale',
                  enabled: canSettingsEdit,
                  helperText: 'Formatting profile such as de_DE or en_US.',
                ),
                _intField(
                  _horizonController,
                  'Default Hold Period',
                  enabled: canSettingsEdit,
                  helperText: 'Years used for new scenarios.',
                ),
              ],
            ),
          ],
        );
        break;
      case 'analysis_defaults':
        content = Column(
          children: [
            _introCard(
              title: 'Analysis Defaults',
              description:
                  'Keep underwriting assumptions consistent so new scenarios start from the same baseline.',
            ),
            const SizedBox(height: AppSpacing.component),
            _section(
              context,
              title: 'Operating Defaults',
              children: [
                _decimalField(
                  _vacancyController,
                  'Vacancy Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.05 = 5.0%',
                ),
                _decimalField(
                  _managementController,
                  'Management Fee Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.05 = 5.0%',
                ),
                _decimalField(
                  _maintenanceController,
                  'Maintenance Reserve Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.05 = 5.0%',
                ),
                _decimalField(
                  _capexController,
                  'CapEx Reserve Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.05 = 5.0%',
                ),
              ],
            ),
            _section(
              context,
              title: 'Growth and Exit',
              children: [
                _decimalField(
                  _appreciationController,
                  'Appreciation Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.02 = 2.0%',
                ),
                _decimalField(
                  _rentGrowthController,
                  'Rent Growth Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.02 = 2.0%',
                ),
                _decimalField(
                  _expenseGrowthController,
                  'Expense Growth Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.02 = 2.0%',
                ),
                _decimalField(
                  _saleCostController,
                  'Sale Cost Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.06 = 6.0%',
                ),
                _decimalField(
                  _closingBuyController,
                  'Acquisition Cost Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.03 = 3.0%',
                ),
                _decimalField(
                  _closingSellController,
                  'Disposition Closing Cost Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.02 = 2.0%',
                ),
              ],
            ),
            _section(
              context,
              title: 'Financing',
              children: [
                _decimalField(
                  _downPaymentController,
                  'Down Payment Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.25 = 25.0%',
                ),
                _decimalField(
                  _interestController,
                  'Interest Rate',
                  enabled: canSettingsEdit,
                  helperText: 'Decimal value, for example 0.06 = 6.0%',
                ),
                _intField(
                  _termYearsController,
                  'Loan Term Years',
                  enabled: canSettingsEdit,
                  helperText: 'Used for new financing assumptions.',
                ),
                _field(
                  _defaultMarketRentModeController,
                  'Default Market Rent Mode',
                  enabled: canSettingsEdit,
                  helperText: 'Optional market rent default.',
                ),
              ],
            ),
          ],
        );
        break;
      case 'operations_defaults':
        content = Column(
          children: [
            _introCard(
              title: 'Operations Defaults',
              description:
                  'Use one operational baseline for generated work, budgets, and recurring checks.',
            ),
            const SizedBox(height: AppSpacing.component),
            _section(
              context,
              title: 'Workflow Defaults',
              children: [
                _intField(
                  _taskDueSoonDaysController,
                  'Task Due Soon Days',
                  enabled: canSettingsEdit,
                ),
                _intField(
                  _budgetYearStartMonthController,
                  'Budget Year Start Month (1-12)',
                  enabled: canSettingsEdit,
                ),
                _intField(
                  _maintenanceDueSoonDaysController,
                  'Maintenance Due Soon Days',
                  enabled: canSettingsEdit,
                ),
                _intField(
                  _covenantDueSoonDaysController,
                  'Covenant Due Soon Days',
                  enabled: canSettingsEdit,
                ),
                SizedBox(
                  width: ResponsiveConstraints.itemWidth(
                    context,
                    idealWidth: 360,
                  ),
                  child: SwitchListTile(
                    value: _scenarioAutoDailyVersionsEnabled,
                    onChanged:
                        canSettingsEdit
                            ? (value) {
                              setState(() {
                                _scenarioAutoDailyVersionsEnabled = value;
                              });
                            }
                            : null,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Scenario Auto Daily Versions'),
                  ),
                ),
              ],
            ),
          ],
        );
        break;
      case 'alerts':
        content = Column(
          children: [
            _introCard(
              title: 'Alerts',
              description:
                  'Set thresholds that surface issues early without flooding daily work.',
            ),
            const SizedBox(height: AppSpacing.component),
            _section(
              context,
              title: 'Alert Thresholds',
              children: [
                _decimalField(
                  _vacancyAlertController,
                  'Vacancy Alert Threshold (0-1)',
                ),
                _decimalField(
                  _noiDropAlertController,
                  'NOI Drop Alert Threshold (0-1)',
                ),
                _intField(
                  _qualityEpcExpiryWarningDaysController,
                  'Quality EPC Expiry Warning Days',
                ),
                _intField(
                  _qualityRentRollStaleMonthsController,
                  'Quality Rent Roll Stale Months',
                ),
                _intField(
                  _qualityLedgerStaleDaysController,
                  'Quality Ledger Stale Days',
                ),
                SizedBox(
                  width: ResponsiveConstraints.itemWidth(
                    context,
                    idealWidth: 320,
                  ),
                  child: SwitchListTile(
                    value: _enableTaskNotifications,
                    onChanged:
                        canSettingsEdit
                            ? (value) {
                              setState(() {
                                _enableTaskNotifications = value;
                              });
                            }
                            : null,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Task Notifications'),
                  ),
                ),
              ],
            ),
          ],
        );
        break;
      case 'appearance':
        content = _buildAppearanceContent(context, canSettingsEdit);
        break;
      case 'security':
        content = _buildSecurityContent(context, canSettingsEdit);
        break;
      case 'backup_restore':
        content = _buildBackupContent(
          context,
          settings: settings,
          canBackupRestore: canBackupRestore,
          canExport: canExport,
        );
        break;
      case 'admin':
        content = Column(
          children: [
            _introCard(
              title: 'Admin',
              description:
                  'Low-frequency administrative switches stay visible, but clearly separated from daily settings.',
              warning:
                  'Administrative helper settings should stay restricted to setup and test workflows.',
            ),
            const SizedBox(height: AppSpacing.component),
            _section(
              context,
              title: 'Administrative Controls',
              children: [
                SizedBox(
                  width: ResponsiveConstraints.itemWidth(
                    context,
                    idealWidth: 320,
                  ),
                  child: SwitchListTile(
                    value: _enableDemoSeed,
                    onChanged:
                        canSettingsEdit
                            ? (value) {
                              setState(() {
                                _enableDemoSeed = value;
                              });
                            }
                            : null,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Demo Seed Button'),
                  ),
                ),
                _field(
                  _scenarioAutoDailyVersionsUserController,
                  'Auto Version User Id',
                  enabled: canSettingsEdit,
                  helperText: 'User id used for automated scenario versions.',
                ),
              ],
            ),
          ],
        );
        break;
      default:
        content = const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDraftOverview(
          context,
          saveChanges: saveChanges,
          securityChanges: securityChanges,
          canSettingsEdit: canSettingsEdit,
        ),
        const SizedBox(height: AppSpacing.component),
        content,
      ],
    );
  }

  Widget _buildAppearanceContent(BuildContext context, bool canSettingsEdit) {
    return Column(
      children: [
        _introCard(
          title: 'Appearance',
          description:
              'Control density and motion so the interface stays predictable across desktop setups.',
        ),
        const SizedBox(height: AppSpacing.component),
        _section(
          context,
          title: 'UI and Accessibility',
          children: [
            SizedBox(
              width: ResponsiveConstraints.itemWidth(context, idealWidth: 260),
              child: DropdownButtonFormField<String>(
                value: _uiThemeMode,
                decoration: const InputDecoration(labelText: 'Theme Mode'),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('System')),
                  DropdownMenuItem(value: 'light', child: Text('Light')),
                  DropdownMenuItem(value: 'dark', child: Text('Dark')),
                ],
                onChanged:
                    canSettingsEdit
                        ? (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _uiThemeMode = value;
                          });
                        }
                        : null,
              ),
            ),
            SizedBox(
              width: ResponsiveConstraints.itemWidth(context, idealWidth: 260),
              child: DropdownButtonFormField<String>(
                value: _uiDensityMode,
                decoration: const InputDecoration(labelText: 'Density Mode'),
                items: const [
                  DropdownMenuItem(value: 'comfort', child: Text('Comfort')),
                  DropdownMenuItem(value: 'compact', child: Text('Compact')),
                  DropdownMenuItem(value: 'adaptive', child: Text('Adaptive')),
                ],
                onChanged:
                    canSettingsEdit
                        ? (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _uiDensityMode = value;
                          });
                        }
                        : null,
              ),
            ),
            SizedBox(
              width: ResponsiveConstraints.itemWidth(context, idealWidth: 320),
              child: SwitchListTile(
                value: _uiChartAnimationsEnabled,
                onChanged:
                    canSettingsEdit
                        ? (value) {
                          setState(() {
                            _uiChartAnimationsEnabled = value;
                          });
                        }
                        : null,
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable Chart Animations'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSecurityContent(BuildContext context, bool canSettingsEdit) {
    return Column(
      children: [
        _introCard(
          title: 'Security',
          description:
              'Protect local access without burying the controls in a generic form.',
          warning:
              'App lock changes affect local access immediately after applying them.',
        ),
        const SizedBox(height: AppSpacing.component),
        _section(
          context,
          title: 'Access Controls',
          children: [
            SizedBox(
              width: ResponsiveConstraints.itemWidth(context, idealWidth: 360),
              child: SwitchListTile(
                value: _enableAppLock,
                onChanged:
                    canSettingsEdit
                        ? (value) {
                          setState(() {
                            _enableAppLock = value;
                          });
                        }
                        : null,
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable App Lock'),
              ),
            ),
            _field(
              _appLockPasswordController,
              'New App Lock Password',
              enabled: canSettingsEdit,
              helperText: 'Leave empty to keep the current password.',
              obscureText: true,
            ),
            ElevatedButton(
              onPressed: canSettingsEdit ? _applySecurity : null,
              child: const Text('Apply Security'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBackupContent(
    BuildContext context, {
    required AppSettingsRecord settings,
    required bool canBackupRestore,
    required bool canExport,
  }) {
    return Column(
      children: [
        _introCard(
          title: 'Backup & Restore',
          description:
              'Keep workspace paths visible and separate backup actions from general defaults.',
          warning:
              'Restore replaces the current database and docs after creating a pre-restore backup.',
        ),
        const SizedBox(height: AppSpacing.component),
        _section(
          context,
          title: 'Workspace and Backup',
          children: [
            SizedBox(
              width: ResponsiveConstraints.itemWidth(
                context,
                idealWidth: 540,
                maxWidth: 720,
              ),
              child: TextField(
                controller: _workspaceRootController,
                enabled: canExport || canBackupRestore,
                decoration: const InputDecoration(
                  labelText: 'Workspace Root Path (optional)',
                  helperText: 'Optional root folder for the workspace.',
                ),
              ),
            ),
            SizedBox(
              width: ResponsiveConstraints.itemWidth(
                context,
                idealWidth: 540,
                maxWidth: 720,
              ),
              child: Text(
                'Last Backup: ${settings.lastBackupAt == null ? 'never' : DateTime.fromMillisecondsSinceEpoch(settings.lastBackupAt!).toIso8601String()}'
                '${settings.lastBackupPath == null ? '' : ' | ${settings.lastBackupPath}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: canExport ? _createBackup : null,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Create Backup ZIP'),
                ),
                OutlinedButton.icon(
                  onPressed: canBackupRestore ? _restoreBackup : null,
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore from ZIP'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  void _handleDraftChanged() {
    if (_isHydrating || !mounted) {
      return;
    }
    setState(() {
      _status = null;
      _statusDetail = null;
      _statusTone = null;
    });
  }

  Future<void> _reloadOrDiscard(bool hasDraftChanges) async {
    if (!hasDraftChanges) {
      await _load();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Discard Draft Changes'),
            content: const Text(
              'This reloads the saved settings and removes your unsaved local draft changes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Discard Draft'),
              ),
            ],
          ),
    );
    if (discard == true) {
      await _load();
    }
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) {
      return 'never';
    }
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  String _formatPercentString(String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null) {
      return raw.trim().isEmpty ? 'Not set' : raw.trim();
    }
    return '${(value * 100).toStringAsFixed(1)}%';
  }

  Widget _introCard({
    required String title,
    required String description,
    String? warning,
  }) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(description),
          if (warning != null) ...[
            const SizedBox(height: AppSpacing.component),
            Container(
              padding: const EdgeInsets.all(AppSpacing.component),
              decoration: BoxDecoration(
                color: context.semanticColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadiusTokens.md),
                border: Border.all(
                  color: context.semanticColors.error.withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                warning,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return NxFormSectionCard(title: title, children: children);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool enabled = true,
    double idealWidth = 260,
    double maxWidth = 560,
    String? helperText,
    bool obscureText = false,
  }) {
    return SizedBox(
      width: ResponsiveConstraints.itemWidth(
        context,
        idealWidth: idealWidth,
        maxWidth: maxWidth,
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        decoration: InputDecoration(labelText: label, helperText: helperText),
      ),
    );
  }

  Widget _decimalField(
    TextEditingController controller,
    String label, {
    bool enabled = true,
    String? helperText,
  }) {
    return SizedBox(
      width: ResponsiveConstraints.itemWidth(context, idealWidth: 260),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, helperText: helperText),
      ),
    );
  }

  Widget _intField(
    TextEditingController controller,
    String label, {
    bool enabled = true,
    String? helperText,
  }) {
    return SizedBox(
      width: ResponsiveConstraints.itemWidth(context, idealWidth: 260),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, helperText: helperText),
      ),
    );
  }

  String? _validateBeforeSave() {
    bool invalidPercent(TextEditingController controller) {
      final value = double.tryParse(controller.text.trim());
      return value == null || value < 0 || value > 1;
    }

    bool invalidInt(TextEditingController controller, {int? min, int? max}) {
      final value = int.tryParse(controller.text.trim());
      if (value == null) {
        return true;
      }
      if (min != null && value < min) {
        return true;
      }
      if (max != null && value > max) {
        return true;
      }
      return false;
    }

    if (_currencyController.text.trim().isEmpty ||
        _localeController.text.trim().isEmpty ||
        invalidInt(_horizonController, min: 1)) {
      return 'general';
    }
    if (invalidPercent(_vacancyController) ||
        invalidPercent(_managementController) ||
        invalidPercent(_maintenanceController) ||
        invalidPercent(_capexController) ||
        invalidPercent(_appreciationController) ||
        invalidPercent(_rentGrowthController) ||
        invalidPercent(_expenseGrowthController) ||
        invalidPercent(_saleCostController) ||
        invalidPercent(_closingBuyController) ||
        invalidPercent(_closingSellController) ||
        invalidPercent(_downPaymentController) ||
        invalidPercent(_interestController) ||
        invalidInt(_termYearsController, min: 1)) {
      return 'analysis_defaults';
    }
    if (invalidInt(_taskDueSoonDaysController, min: 0) ||
        invalidInt(_maintenanceDueSoonDaysController, min: 0) ||
        invalidInt(_covenantDueSoonDaysController, min: 0) ||
        (_budgetYearStartMonthController.text.trim().isNotEmpty &&
            invalidInt(_budgetYearStartMonthController, min: 1, max: 12))) {
      return 'operations_defaults';
    }
    if (_scenarioAutoDailyVersionsEnabled &&
        _scenarioAutoDailyVersionsUserController.text.trim().isEmpty) {
      return 'admin';
    }
    if ((_vacancyAlertController.text.trim().isNotEmpty &&
            invalidPercent(_vacancyAlertController)) ||
        (_noiDropAlertController.text.trim().isNotEmpty &&
            invalidPercent(_noiDropAlertController)) ||
        invalidInt(_qualityEpcExpiryWarningDaysController, min: 0) ||
        invalidInt(_qualityRentRollStaleMonthsController, min: 0) ||
        invalidInt(_qualityLedgerStaleDaysController, min: 0)) {
      return 'alerts';
    }
    return null;
  }

  Future<void> _load() async {
    final settings = await ref.read(inputsRepositoryProvider).getSettings();
    final workspace = await ref
        .read(workspaceRepositoryProvider)
        .resolvePaths(settings);
    _isHydrating = true;
    _currencyController.text = settings.currencyCode;
    _localeController.text = settings.locale;
    _horizonController.text = settings.defaultHorizonYears.toString();
    _vacancyController.text = settings.defaultVacancyPercent.toString();
    _managementController.text = settings.defaultManagementPercent.toString();
    _maintenanceController.text = settings.defaultMaintenancePercent.toString();
    _capexController.text = settings.defaultCapexPercent.toString();
    _appreciationController.text =
        settings.defaultAppreciationPercent.toString();
    _rentGrowthController.text = settings.defaultRentGrowthPercent.toString();
    _expenseGrowthController.text =
        settings.defaultExpenseGrowthPercent.toString();
    _saleCostController.text = settings.defaultSaleCostPercent.toString();
    _closingBuyController.text =
        settings.defaultClosingCostBuyPercent.toString();
    _closingSellController.text =
        settings.defaultClosingCostSellPercent.toString();
    _downPaymentController.text = settings.defaultDownPaymentPercent.toString();
    _interestController.text = settings.defaultInterestRatePercent.toString();
    _termYearsController.text = settings.defaultTermYears.toString();
    _vacancyAlertController.text =
        settings.notificationVacancyThreshold?.toString() ?? '';
    _noiDropAlertController.text =
        settings.notificationNoiDropThreshold?.toString() ?? '';
    _workspaceRootController.text = workspace.rootPath;
    _taskDueSoonDaysController.text = settings.taskDueSoonDays.toString();
    _defaultMarketRentModeController.text =
        settings.defaultMarketRentMode ?? '';
    _budgetYearStartMonthController.text =
        settings.budgetDefaultYearStartMonth?.toString() ?? '';
    _maintenanceDueSoonDaysController.text =
        settings.maintenanceDueSoonDays.toString();
    _covenantDueSoonDaysController.text =
        settings.covenantDueSoonDays.toString();
    _qualityEpcExpiryWarningDaysController.text =
        settings.qualityEpcExpiryWarningDays.toString();
    _qualityRentRollStaleMonthsController.text =
        settings.qualityRentRollStaleMonths.toString();
    _qualityLedgerStaleDaysController.text =
        settings.qualityLedgerStaleDays.toString();
    _scenarioAutoDailyVersionsEnabled =
        settings.scenarioAutoDailyVersionsEnabled;
    _scenarioAutoDailyVersionsUserController.text =
        settings.scenarioAutoDailyVersionsUserId ?? '';
    _enableAppLock = settings.securityAppLockEnabled;
    _appLockPasswordController.clear();
    _uiThemeMode = settings.uiThemeMode;
    _uiDensityMode = settings.uiDensityMode;
    _uiChartAnimationsEnabled = settings.uiChartAnimationsEnabled;
    _isHydrating = false;
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _enableDemoSeed = settings.enableDemoSeed;
      _enableTaskNotifications = settings.enableTaskNotifications;
      _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(settings.updatedAt);
      _status = null;
      _statusDetail = null;
      _statusTone = null;
    });
  }

  Future<void> _save() async {
    final current = _settings;
    if (current == null) {
      return;
    }
    final role = ref.read(activeUserRoleProvider);
    final canEdit = ref
        .read(rbacProvider)
        .can(action: RbacAction.settingsEdit, role: role);
    if (!canEdit) {
      if (mounted) {
        setState(() {
          _status = 'Insufficient permission to edit settings.';
          _statusDetail =
              'This role can review settings, but cannot save them.';
          _statusTone = SaveStatusTone.error;
        });
      }
      return;
    }
    final invalidSection = _validateBeforeSave();
    if (invalidSection != null) {
      if (mounted) {
        setState(() {
          _selectedSectionId = invalidSection;
          _status = 'Review invalid values before saving.';
          _statusDetail =
              'Check ${_sectionTitles[invalidSection] ?? invalidSection} for empty or out-of-range fields.';
          _statusTone = SaveStatusTone.error;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isSaving = true;
        _status = 'Saving settings...';
        _statusDetail = null;
        _statusTone = SaveStatusTone.working;
      });
    }

    final updated = current.copyWith(
      currencyCode:
          _currencyController.text.trim().isEmpty
              ? current.currencyCode
              : _currencyController.text.trim(),
      locale:
          _localeController.text.trim().isEmpty
              ? current.locale
              : _localeController.text.trim(),
      defaultHorizonYears:
          int.tryParse(_horizonController.text) ?? current.defaultHorizonYears,
      defaultVacancyPercent:
          double.tryParse(_vacancyController.text) ??
          current.defaultVacancyPercent,
      defaultManagementPercent:
          double.tryParse(_managementController.text) ??
          current.defaultManagementPercent,
      defaultMaintenancePercent:
          double.tryParse(_maintenanceController.text) ??
          current.defaultMaintenancePercent,
      defaultCapexPercent:
          double.tryParse(_capexController.text) ?? current.defaultCapexPercent,
      defaultAppreciationPercent:
          double.tryParse(_appreciationController.text) ??
          current.defaultAppreciationPercent,
      defaultRentGrowthPercent:
          double.tryParse(_rentGrowthController.text) ??
          current.defaultRentGrowthPercent,
      defaultExpenseGrowthPercent:
          double.tryParse(_expenseGrowthController.text) ??
          current.defaultExpenseGrowthPercent,
      defaultSaleCostPercent:
          double.tryParse(_saleCostController.text) ??
          current.defaultSaleCostPercent,
      defaultClosingCostBuyPercent:
          double.tryParse(_closingBuyController.text) ??
          current.defaultClosingCostBuyPercent,
      defaultClosingCostSellPercent:
          double.tryParse(_closingSellController.text) ??
          current.defaultClosingCostSellPercent,
      defaultDownPaymentPercent:
          double.tryParse(_downPaymentController.text) ??
          current.defaultDownPaymentPercent,
      defaultInterestRatePercent:
          double.tryParse(_interestController.text) ??
          current.defaultInterestRatePercent,
      defaultTermYears:
          int.tryParse(_termYearsController.text) ?? current.defaultTermYears,
      enableDemoSeed: _enableDemoSeed,
      notificationVacancyThreshold:
          _vacancyAlertController.text.trim().isEmpty
              ? null
              : double.tryParse(_vacancyAlertController.text.trim()),
      notificationNoiDropThreshold:
          _noiDropAlertController.text.trim().isEmpty
              ? null
              : double.tryParse(_noiDropAlertController.text.trim()),
      workspaceRootPath:
          _workspaceRootController.text.trim().isEmpty
              ? null
              : _workspaceRootController.text.trim(),
      taskDueSoonDays:
          int.tryParse(_taskDueSoonDaysController.text.trim()) ??
          current.taskDueSoonDays,
      enableTaskNotifications: _enableTaskNotifications,
      defaultMarketRentMode:
          _defaultMarketRentModeController.text.trim().isEmpty
              ? null
              : _defaultMarketRentModeController.text.trim(),
      budgetDefaultYearStartMonth:
          _budgetYearStartMonthController.text.trim().isEmpty
              ? null
              : int.tryParse(_budgetYearStartMonthController.text.trim()),
      maintenanceDueSoonDays:
          int.tryParse(_maintenanceDueSoonDaysController.text.trim()) ??
          current.maintenanceDueSoonDays,
      covenantDueSoonDays:
          int.tryParse(_covenantDueSoonDaysController.text.trim()) ??
          current.covenantDueSoonDays,
      qualityEpcExpiryWarningDays:
          int.tryParse(_qualityEpcExpiryWarningDaysController.text.trim()) ??
          current.qualityEpcExpiryWarningDays,
      qualityRentRollStaleMonths:
          int.tryParse(_qualityRentRollStaleMonthsController.text.trim()) ??
          current.qualityRentRollStaleMonths,
      qualityLedgerStaleDays:
          int.tryParse(_qualityLedgerStaleDaysController.text.trim()) ??
          current.qualityLedgerStaleDays,
      scenarioAutoDailyVersionsEnabled: _scenarioAutoDailyVersionsEnabled,
      scenarioAutoDailyVersionsUserId:
          _scenarioAutoDailyVersionsUserController.text.trim().isEmpty
              ? null
              : _scenarioAutoDailyVersionsUserController.text.trim(),
      uiThemeMode: _uiThemeMode,
      uiDensityMode: _uiDensityMode,
      uiChartAnimationsEnabled: _uiChartAnimationsEnabled,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      await ref.read(inputsRepositoryProvider).updateSettings(updated);
      ref.read(settingsRevisionProvider.notifier).state++;
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = updated;
        _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(updated.updatedAt);
        _status = 'Settings saved.';
        _statusDetail = 'Saved ${_formatTimestamp(_lastSavedAt)}';
        _statusTone = SaveStatusTone.success;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Settings save failed.';
        _statusDetail = '$error';
        _statusTone = SaveStatusTone.error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _applySecurity() async {
    try {
      if (_enableAppLock &&
          !_settings!.securityAppLockEnabled &&
          _appLockPasswordController.text.trim().isEmpty) {
        setState(() {
          _selectedSectionId = 'security';
          _status = 'Security update blocked.';
          _statusDetail =
              'Provide a password before enabling app lock for the first time.';
          _statusTone = SaveStatusTone.error;
        });
        return;
      }
      if (mounted) {
        setState(() {
          _status = 'Applying security changes...';
          _statusDetail = null;
          _statusTone = SaveStatusTone.working;
        });
      }
      await ref
          .read(securityControllerProvider.notifier)
          .setAppLock(
            enabled: _enableAppLock,
            password: _appLockPasswordController.text.trim(),
          );
      _appLockPasswordController.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Security settings updated.';
        _statusDetail = 'Local access controls were updated successfully.';
        _statusTone = SaveStatusTone.success;
      });
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Security update failed.';
        _statusDetail = '$error';
        _statusTone = SaveStatusTone.error;
      });
    }
  }

  Future<void> _createBackup() async {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    final role = ref.read(activeUserRoleProvider);
    final canExport = ref
        .read(rbacProvider)
        .can(action: RbacAction.export, role: role);
    if (!canExport) {
      if (mounted) {
        setState(() {
          _status = 'Insufficient permission to export backups.';
          _statusDetail = null;
          _statusTone = SaveStatusTone.error;
        });
      }
      return;
    }
    final saveLocation = await getSaveLocation(
      suggestedName:
          'neximmo_backup_${DateTime.now().millisecondsSinceEpoch}.zip',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ZIP', extensions: ['zip']),
      ],
    );
    if (saveLocation == null) {
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _status = 'Creating backup...';
          _statusDetail = saveLocation.path;
          _statusTone = SaveStatusTone.working;
        });
      }
      final effectiveSettings = settings.copyWith(
        workspaceRootPath:
            _workspaceRootController.text.trim().isEmpty
                ? null
                : _workspaceRootController.text.trim(),
      );
      final workspace = await ref
          .read(workspaceRepositoryProvider)
          .resolvePaths(effectiveSettings);
      final manifest = await ref
          .read(backupServiceProvider)
          .createBackup(
            dbPath: workspace.dbPath,
            docsDirectoryPath: workspace.docsPath,
            destinationZipPath: saveLocation.path,
            dbSchemaVersion: DbMigrations.currentVersion,
            appVersion: '1.0.0+1',
          );
      final updated = settings.copyWith(
        workspaceRootPath: workspace.rootPath,
        lastBackupAt: manifest.createdAt,
        lastBackupPath: saveLocation.path,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await ref.read(inputsRepositoryProvider).updateSettings(updated);
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = updated;
        _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(updated.updatedAt);
        _workspaceRootController.text = updated.workspaceRootPath ?? '';
        _status = 'Backup created.';
        _statusDetail = saveLocation.path;
        _statusTone = SaveStatusTone.success;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Backup failed.';
        _statusDetail = '$error';
        _statusTone = SaveStatusTone.error;
      });
    }
  }

  Future<void> _restoreBackup() async {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    final role = ref.read(activeUserRoleProvider);
    final canRestore = ref
        .read(rbacProvider)
        .can(action: RbacAction.backupRestore, role: role);
    if (!canRestore) {
      if (mounted) {
        setState(() {
          _status = 'Insufficient permission to restore backups.';
          _statusDetail = null;
          _statusTone = SaveStatusTone.error;
        });
      }
      return;
    }
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ZIP', extensions: ['zip']),
      ],
    );
    if (file == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Restore Backup'),
            content: const Text(
              'Before restore, an automatic pre-restore backup will be created.\n'
              'The current DB data and docs folder will be replaced.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Restore'),
              ),
            ],
          ),
    );
    if (confirm != true) {
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _status = 'Restoring backup...';
          _statusDetail = file.path;
          _statusTone = SaveStatusTone.working;
        });
      }
      final effectiveSettings = settings.copyWith(
        workspaceRootPath:
            _workspaceRootController.text.trim().isEmpty
                ? null
                : _workspaceRootController.text.trim(),
      );
      final backupService = ref.read(backupServiceProvider);
      final workspace = await ref
          .read(workspaceRepositoryProvider)
          .resolvePaths(effectiveSettings);
      final manifest = await backupService.readManifest(file.path);
      if (manifest.dbSchemaVersion > DbMigrations.currentVersion) {
        throw StateError(
          'Backup schema (${manifest.dbSchemaVersion}) is newer than current app schema (${DbMigrations.currentVersion}).',
        );
      }

      final preRestorePath = p.join(
        workspace.backupsPath,
        'pre_restore_${DateTime.now().millisecondsSinceEpoch}.zip',
      );
      await backupService.createBackup(
        dbPath: workspace.dbPath,
        docsDirectoryPath: workspace.docsPath,
        destinationZipPath: preRestorePath,
        dbSchemaVersion: DbMigrations.currentVersion,
        appVersion: '1.0.0+1',
      );

      final currentDb = ref.read(databaseProvider);
      await backupService.restoreFromBackup(
        zipPath: file.path,
        docsDirectoryPath: workspace.docsPath,
        tempDirectoryPath: workspace.tempPath,
        restoreDbFromFile: (extractedDbFile) async {
          final backupDb = await databaseFactoryFfi.openDatabase(
            extractedDbFile.path,
            options: OpenDatabaseOptions(readOnly: true),
          );
          try {
            await _restoreDatabaseData(
              currentDb: currentDb,
              backupDb: backupDb,
            );
          } finally {
            await backupDb.close();
          }
        },
      );

      await ref.read(searchRepositoryProvider).rebuildIndex();
      ref.read(globalPageProvider.notifier).state = GlobalPage.dashboard;
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Restore completed.';
        _statusDetail = file.path;
        _statusTone = SaveStatusTone.success;
      });
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Restore failed.';
        _statusDetail = '$error';
        _statusTone = SaveStatusTone.error;
      });
    }
  }

  Future<void> _restoreDatabaseData({
    required Database currentDb,
    required Database backupDb,
  }) async {
    final currentTables = await currentDb.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final backupTables = await backupDb.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final backupTableNames =
        backupTables.map((row) => row['name'] as String).toSet();

    await currentDb.transaction((txn) async {
      await txn.execute('PRAGMA foreign_keys = OFF');
      for (final row in currentTables) {
        final table = row['name'] as String;
        if (table == 'android_metadata') {
          continue;
        }
        if (!backupTableNames.contains(table)) {
          await txn.delete(table);
          continue;
        }
        final currentCols =
            (await txn.rawQuery(
              'PRAGMA table_info($table)',
            )).map((c) => c['name'] as String).toSet();
        final backupCols =
            (await backupDb.rawQuery(
              'PRAGMA table_info($table)',
            )).map((c) => c['name'] as String).toSet();
        final commonCols = currentCols
            .where((c) => backupCols.contains(c))
            .toList(growable: false);
        await txn.delete(table);
        if (commonCols.isEmpty) {
          continue;
        }
        final backupRows = await backupDb.query(table, columns: commonCols);
        for (final backupRow in backupRows) {
          final map = <String, Object?>{
            for (final col in commonCols) col: backupRow[col],
          };
          await txn.insert(
            table,
            map,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await txn.execute('PRAGMA foreign_keys = ON');
    });
  }
}

class _HeaderStatus {
  const _HeaderStatus({
    required this.label,
    required this.detail,
    required this.tone,
  });

  final String label;
  final String? detail;
  final SaveStatusTone tone;
}

class _SettingChange {
  const _SettingChange({
    required this.sectionId,
    required this.label,
    required this.previousValue,
    required this.nextValue,
  });

  final String sectionId;
  final String label;
  final String previousValue;
  final String nextValue;
}
