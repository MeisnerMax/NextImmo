import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/rbac.dart';
import '../../core/models/settings.dart';
import '../../data/repositories/workspace_repo.dart';
import '../i18n/app_strings.dart';
import '../components/nx_card.dart';
import '../components/nx_form_section_card.dart';
import '../components/responsive_constraints.dart';
import '../components/save_status_indicator.dart';
import '../state/app_state.dart';
import '../state/security_state.dart';
import '../templates/settings_template.dart';
import '../theme/app_theme.dart';
import 'settings/settings_section_states.dart';

// BIG-009: one file per settings section. Each part declares a private
// extension on `_SettingsScreenState` and reaches the shared controllers, draft
// helpers and RBAC flags through the implicit receiver — no state re-threading.
part 'settings/sections/general_section.dart';
part 'settings/sections/analysis_defaults_section.dart';
part 'settings/sections/operations_defaults_section.dart';
part 'settings/sections/alerts_section.dart';
part 'settings/sections/appearance_section.dart';
part 'settings/sections/security_section.dart';
part 'settings/sections/backup_restore_section.dart';
part 'settings/sections/admin_section.dart';

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
  Object? _loadError;

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
  String _uiLanguageCode = 'en';
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

  AppStrings get _strings => context.strings;

  String _sectionTitle(String id) => _strings.text(_sectionTitles[id] ?? id);

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
    final s = _strings;
    final settings = _settings;
    if (settings == null) {
      return _loadError != null
          ? SettingsLoadError(onRetry: _load)
          : const SettingsSkeleton();
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
      title: s.text('Settings'),
      breadcrumbs: <String>[s.text('System'), s.text('Settings')],
      subtitle: s.text(
        'Use clear defaults, isolate risky actions, and keep every change visible.',
      ),
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
        child: Text(s.text(_isSaving ? 'Saving...' : 'Save Settings')),
      ),
      secondaryActions: [
        OutlinedButton(
          onPressed: () => _reloadOrDiscard(hasDraftChanges),
          child: Text(s.text(hasDraftChanges ? 'Discard Draft' : 'Reload')),
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
    final s = _strings;
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
                ? s.text('Risk')
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
        label: s.text('General'),
        icon: Icons.tune_outlined,
        description: s.text('Locale, currency, and core scenario defaults.'),
      ),
      item(
        id: 'analysis_defaults',
        label: s.text('Analysis Defaults'),
        icon: Icons.analytics_outlined,
        description: s.text(
          'Underwriting, growth, exit, and financing defaults.',
        ),
      ),
      item(
        id: 'operations_defaults',
        label: s.text('Operations Defaults'),
        icon: Icons.build_circle_outlined,
        description: s.text(
          'Task, maintenance, covenant, and automation defaults.',
        ),
      ),
      item(
        id: 'alerts',
        label: s.text('Alerts'),
        icon: Icons.notifications_active_outlined,
        description: s.text('Thresholds and quality warning behavior.'),
      ),
      item(
        id: 'appearance',
        label: s.text('Appearance'),
        icon: Icons.palette_outlined,
        description: s.text('Theme, density, and interface motion.'),
      ),
      item(
        id: 'security',
        label: s.text('Security'),
        icon: Icons.lock_outline,
        description: s.text('App lock and restricted actions.'),
        dangerous: true,
      ),
      item(
        id: 'backup_restore',
        label: s.text('Backup & Restore'),
        icon: Icons.backup_outlined,
        description: s.text('Workspace path plus backup and restore actions.'),
        dangerous: true,
      ),
      item(
        id: 'admin',
        label: s.text('Admin'),
        icon: Icons.admin_panel_settings_outlined,
        description: s.text('Demo data and administrative helper settings.'),
        dangerous: true,
      ),
    ];
  }

  _HeaderStatus _buildHeaderStatus({
    required List<_SettingChange> saveChanges,
    required List<_SettingChange> securityChanges,
    required bool canSettingsEdit,
  }) {
    final s = _strings;
    if (_isSaving) {
      return _HeaderStatus(
        label: s.text('Saving settings...'),
        detail: s.applyingPendingChangesDetail(saveChanges.length),
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
      ).keys.map(_sectionTitle).join(', ');
      return _HeaderStatus(
        label: s.unsavedChangesLabel(saveChanges.length),
        detail: s.changedSectionsDetail(sections),
        tone: canSettingsEdit ? SaveStatusTone.warning : SaveStatusTone.neutral,
      );
    }
    if (_selectedSectionId == 'security' && securityChanges.isNotEmpty) {
      return _HeaderStatus(
        label: s.pendingSecurityChangesLabel(securityChanges.length),
        detail: s.text('Use Apply Security in this section to commit them.'),
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
      label: s.text('All changes saved'),
      detail:
          _lastSavedAt == null
              ? s.text('No local draft is pending.')
              : s.lastSavedLabel(_formatTimestamp(_lastSavedAt)),
      tone: SaveStatusTone.success,
    );
  }

  Widget _buildDraftOverview(
    BuildContext context, {
    required List<_SettingChange> saveChanges,
    required List<_SettingChange> securityChanges,
    required bool canSettingsEdit,
  }) {
    final s = _strings;
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
                s.text('Save Overview'),
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
                ? s.text(
                  'General settings save through the header action. Security changes are applied separately inside the Security section.',
                )
                : s.text(
                  'This role can review settings, but cannot save configuration changes.',
                ),
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _overviewChip(
                context,
                s.text('Pending fields'),
                '${allChanges.length}',
              ),
              _overviewChip(
                context,
                s.text('Changed sections'),
                '${counts.length}',
              ),
              _overviewChip(
                context,
                s.text('Selected section'),
                _sectionTitle(_selectedSectionId),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Text(
            currentSectionChanges.isEmpty
                ? s.text('No pending draft changes in this section.')
                : s.text('Pending changes in this section'),
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
    final s = _strings;
    final changes = <_SettingChange>[];
    if (_enableAppLock != settings.securityAppLockEnabled) {
      changes.add(
        _SettingChange(
          sectionId: 'security',
          label: s.text('Enable App Lock'),
          previousValue: s.onOff(settings.securityAppLockEnabled),
          nextValue: s.onOff(_enableAppLock),
        ),
      );
    }
    if (_appLockPasswordController.text.trim().isNotEmpty) {
      changes.add(
        _SettingChange(
          sectionId: 'security',
          label: s.text('App Lock Password'),
          previousValue: s.text('Keep current password'),
          nextValue: s.text('Replace password'),
        ),
      );
    }
    return changes;
  }

  List<_SettingChange> _collectSaveChanges(AppSettingsRecord settings) {
    final s = _strings;
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
          previousValue: saved.isEmpty ? s.notSet : saved,
          nextValue: current.isEmpty ? s.notSet : current,
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
          previousValue: s.onOff(savedValue),
          nextValue: s.onOff(currentValue),
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
                  ? s.notSet
                  : isPercent
                  ? _formatPercentString(current)
                  : current,
        ),
      );
    }

    addText(
      sectionId: 'general',
      label: s.text('Currency Code'),
      currentValue: _currencyController.text,
      savedValue: settings.currencyCode,
    );
    addText(
      sectionId: 'general',
      label: s.text('Language'),
      currentValue: s.languageName(_uiLanguageCode),
      savedValue: s.languageName(settings.uiLanguageCode),
    );
    addText(
      sectionId: 'general',
      label: s.text('Locale'),
      currentValue: _localeController.text,
      savedValue: settings.locale,
    );
    addNumber(
      sectionId: 'general',
      label: s.text('Default Horizon Years'),
      currentValue: _horizonController.text,
      savedValue: settings.defaultHorizonYears.toString(),
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Vacancy Rate'),
      currentValue: _vacancyController.text,
      savedValue: settings.defaultVacancyPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Management Fee Rate'),
      currentValue: _managementController.text,
      savedValue: settings.defaultManagementPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Maintenance Reserve Rate'),
      currentValue: _maintenanceController.text,
      savedValue: settings.defaultMaintenancePercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('CapEx Reserve Rate'),
      currentValue: _capexController.text,
      savedValue: settings.defaultCapexPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Appreciation Rate'),
      currentValue: _appreciationController.text,
      savedValue: settings.defaultAppreciationPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Rent Growth Rate'),
      currentValue: _rentGrowthController.text,
      savedValue: settings.defaultRentGrowthPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Expense Growth Rate'),
      currentValue: _expenseGrowthController.text,
      savedValue: settings.defaultExpenseGrowthPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Sale Cost Rate'),
      currentValue: _saleCostController.text,
      savedValue: settings.defaultSaleCostPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Acquisition Cost Rate'),
      currentValue: _closingBuyController.text,
      savedValue: settings.defaultClosingCostBuyPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Disposition Closing Cost Rate'),
      currentValue: _closingSellController.text,
      savedValue: settings.defaultClosingCostSellPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Down Payment Rate'),
      currentValue: _downPaymentController.text,
      savedValue: settings.defaultDownPaymentPercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Interest Rate'),
      currentValue: _interestController.text,
      savedValue: settings.defaultInterestRatePercent.toString(),
      isPercent: true,
    );
    addNumber(
      sectionId: 'analysis_defaults',
      label: s.text('Loan Term Years'),
      currentValue: _termYearsController.text,
      savedValue: settings.defaultTermYears.toString(),
    );
    addText(
      sectionId: 'analysis_defaults',
      label: s.text('Market Rent Mode'),
      currentValue: _defaultMarketRentModeController.text,
      savedValue: settings.defaultMarketRentMode ?? '',
    );
    addNumber(
      sectionId: 'operations_defaults',
      label: s.text('Task Due Soon Days'),
      currentValue: _taskDueSoonDaysController.text,
      savedValue: settings.taskDueSoonDays.toString(),
    );
    addNumber(
      sectionId: 'operations_defaults',
      label: s.text('Budget Year Start Month'),
      currentValue: _budgetYearStartMonthController.text,
      savedValue: settings.budgetDefaultYearStartMonth?.toString() ?? '',
    );
    addNumber(
      sectionId: 'operations_defaults',
      label: s.text('Maintenance Due Soon Days'),
      currentValue: _maintenanceDueSoonDaysController.text,
      savedValue: settings.maintenanceDueSoonDays.toString(),
    );
    addNumber(
      sectionId: 'operations_defaults',
      label: s.text('Covenant Due Soon Days'),
      currentValue: _covenantDueSoonDaysController.text,
      savedValue: settings.covenantDueSoonDays.toString(),
    );
    addBool(
      sectionId: 'operations_defaults',
      label: s.text('Scenario Auto Daily Versions'),
      currentValue: _scenarioAutoDailyVersionsEnabled,
      savedValue: settings.scenarioAutoDailyVersionsEnabled,
    );
    addText(
      sectionId: 'admin',
      label: s.text('Auto Version User Id'),
      currentValue: _scenarioAutoDailyVersionsUserController.text,
      savedValue: settings.scenarioAutoDailyVersionsUserId ?? '',
    );
    addNumber(
      sectionId: 'alerts',
      label: s.text('Vacancy Alert Threshold'),
      currentValue: _vacancyAlertController.text,
      savedValue: settings.notificationVacancyThreshold?.toString() ?? '',
      isPercent: true,
    );
    addNumber(
      sectionId: 'alerts',
      label: s.text('NOI Drop Alert Threshold'),
      currentValue: _noiDropAlertController.text,
      savedValue: settings.notificationNoiDropThreshold?.toString() ?? '',
      isPercent: true,
    );
    addNumber(
      sectionId: 'alerts',
      label: s.text('EPC Expiry Warning Days'),
      currentValue: _qualityEpcExpiryWarningDaysController.text,
      savedValue: settings.qualityEpcExpiryWarningDays.toString(),
    );
    addNumber(
      sectionId: 'alerts',
      label: s.text('Rent Roll Stale Months'),
      currentValue: _qualityRentRollStaleMonthsController.text,
      savedValue: settings.qualityRentRollStaleMonths.toString(),
    );
    addNumber(
      sectionId: 'alerts',
      label: s.text('Ledger Stale Days'),
      currentValue: _qualityLedgerStaleDaysController.text,
      savedValue: settings.qualityLedgerStaleDays.toString(),
    );
    addBool(
      sectionId: 'alerts',
      label: s.text('Task Notifications'),
      currentValue: _enableTaskNotifications,
      savedValue: settings.enableTaskNotifications,
    );
    addText(
      sectionId: 'backup_restore',
      label: s.text('Workspace Root Path'),
      currentValue: _workspaceRootController.text,
      savedValue: settings.workspaceRootPath ?? '',
    );
    addText(
      sectionId: 'appearance',
      label: s.text('Theme Mode'),
      currentValue: _uiThemeMode,
      savedValue: settings.uiThemeMode,
    );
    addText(
      sectionId: 'appearance',
      label: s.text('Density Mode'),
      currentValue: _uiDensityMode,
      savedValue: settings.uiDensityMode,
    );
    addBool(
      sectionId: 'appearance',
      label: s.text('Chart Animations'),
      currentValue: _uiChartAnimationsEnabled,
      savedValue: settings.uiChartAnimationsEnabled,
    );
    addBool(
      sectionId: 'admin',
      label: s.text('Enable Demo Seed Button'),
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
        content = buildGeneralSection(context, canSettingsEdit: canSettingsEdit);
        break;
      case 'analysis_defaults':
        content = buildAnalysisDefaultsSection(
          context,
          canSettingsEdit: canSettingsEdit,
        );
        break;
      case 'operations_defaults':
        content = buildOperationsDefaultsSection(
          context,
          canSettingsEdit: canSettingsEdit,
        );
        break;
      case 'alerts':
        content = buildAlertsSection(context, canSettingsEdit: canSettingsEdit);
        break;
      case 'appearance':
        content = buildAppearanceSection(
          context,
          canSettingsEdit: canSettingsEdit,
        );
        break;
      case 'security':
        content = buildSecuritySection(
          context,
          canSettingsEdit: canSettingsEdit,
        );
        break;
      case 'backup_restore':
        content = buildBackupRestoreSection(
          context,
          settings: settings,
          canBackupRestore: canBackupRestore,
          canExport: canExport,
        );
        break;
      case 'admin':
        content = buildAdminSection(context, canSettingsEdit: canSettingsEdit);
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

  /// Applies an in-place draft edit from a section part and rebuilds. Section
  /// builders are extensions on this state and must not call the protected
  /// `setState` directly, so they route toggle changes through here.
  void _editDraft(VoidCallback change) => setState(change);

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
    final s = _strings;
    if (!hasDraftChanges) {
      await _load();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(s.text('Discard Draft Changes')),
            content: Text(
              s.text(
                'This reloads the saved settings and removes your unsaved local draft changes.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(s.text('Cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(s.text('Discard Draft')),
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
      return _strings.never;
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
      return raw.trim().isEmpty ? _strings.notSet : raw.trim();
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
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
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
        decoration: _settingInputDecoration(label, helperText: helperText),
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
        decoration: _settingInputDecoration(label, helperText: helperText),
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
        decoration: _settingInputDecoration(label, helperText: helperText),
      ),
    );
  }

  InputDecoration _settingInputDecoration(
    String label, {
    String? helperText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: context.semanticColors.surfaceAlt,
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
    final AppSettingsRecord settings;
    final WorkspacePaths workspace;
    try {
      settings = await ref.read(inputsRepositoryProvider).getSettings();
      workspace =
          await ref.read(workspaceRepositoryProvider).resolvePaths(settings);
    } catch (error) {
      _isHydrating = false;
      // A refresh after a mutation keeps its caller's existing error handling;
      // only the initial load falls back to the on-screen retry state.
      if (_settings != null) {
        rethrow;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
      });
      return;
    }
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
    _uiLanguageCode = settings.uiLanguageCode;
    _uiThemeMode = settings.uiThemeMode;
    _uiDensityMode = settings.uiDensityMode;
    _uiChartAnimationsEnabled = settings.uiChartAnimationsEnabled;
    _isHydrating = false;
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _loadError = null;
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
          _status = _strings.text('Insufficient permission to edit settings.');
          _statusDetail = _strings.text(
            'This role can review settings, but cannot save them.',
          );
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
          _status = _strings.text('Review invalid values before saving.');
          _statusDetail = _strings.invalidSectionDetail(
            _sectionTitle(invalidSection),
          );
          _statusTone = SaveStatusTone.error;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isSaving = true;
        _status = _strings.text('Saving settings...');
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
      uiLanguageCode: _uiLanguageCode,
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
        _status = _strings.text('Settings saved.');
        _statusDetail = _strings.lastSavedLabel(_formatTimestamp(_lastSavedAt));
        _statusTone = SaveStatusTone.success;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _strings.text('Settings save failed.');
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
          _status = _strings.text('Security update blocked.');
          _statusDetail = _strings.text(
            'Provide a password before enabling app lock for the first time.',
          );
          _statusTone = SaveStatusTone.error;
        });
        return;
      }
      if (mounted) {
        setState(() {
          _status = _strings.text('Applying security changes...');
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
        _status = _strings.text('Security settings updated.');
        _statusDetail = _strings.text(
          'Local access controls were updated successfully.',
        );
        _statusTone = SaveStatusTone.success;
      });
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _strings.text('Security update failed.');
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
          _status = _strings.text('Insufficient permission to export backups.');
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
          _status = _strings.text('Creating backup...');
          _statusDetail = saveLocation.path;
          _statusTone = SaveStatusTone.working;
        });
      }
      final result = await ref
          .read(backupRestoreServiceProvider)
          .createBackup(
            settings: settings,
            workspaceRootPath: _workspaceRootController.text,
            destinationZipPath: saveLocation.path,
          );
      final updated = result.updatedSettings;
      ref.read(settingsRevisionProvider.notifier).state++;
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = updated;
        _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(updated.updatedAt);
        _workspaceRootController.text = updated.workspaceRootPath ?? '';
        _status = _strings.text('Backup created.');
        _statusDetail = saveLocation.path;
        _statusTone = SaveStatusTone.success;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _strings.text('Backup failed.');
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
          _status = _strings.text(
            'Insufficient permission to restore backups.',
          );
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
            title: Text(_strings.text('Restore Backup')),
            content: Text(
              _strings.text(
                'Before restore, an automatic pre-restore backup will be created.\nThe current DB data and docs folder will be replaced.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_strings.text('Cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(_strings.text('Restore')),
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
          _status = _strings.text('Restoring backup...');
          _statusDetail = file.path;
          _statusTone = SaveStatusTone.working;
        });
      }
      await ref
          .read(backupRestoreServiceProvider)
          .restoreBackup(
            settings: settings,
            workspaceRootPath: _workspaceRootController.text,
            sourceZipPath: file.path,
            newerSchemaMessage:
                (backupSchemaVersion, currentSchemaVersion) => _strings.text(
                  'Backup schema ({schema}) is newer than current app schema ({current}).',
                  <String, Object?>{
                  'schema': backupSchemaVersion,
                  'current': currentSchemaVersion,
                  },
                ),
          );
      ref.read(globalPageProvider.notifier).state = GlobalPage.dashboard;
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _strings.text('Restore completed.');
        _statusDetail = file.path;
        _statusTone = SaveStatusTone.success;
      });
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _strings.text('Restore failed.');
        _statusDetail = '$error';
        _statusTone = SaveStatusTone.error;
      });
    }
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
