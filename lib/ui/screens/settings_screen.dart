import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/security/rbac.dart';
import '../../core/models/settings.dart';
import '../../data/sqlite/migrations.dart';
import '../components/responsive_constraints.dart';
import '../state/app_state.dart';
import '../state/security_state.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AppSettingsRecord? _settings;
  String? _status;

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Global Defaults',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'These values are used for new scenarios and for "Apply Current Settings" in Inputs.',
            ),
            const SizedBox(height: AppSpacing.component),
            _section(
              context,
              title: 'General',
              children: [
                _field(_currencyController, 'Currency Code'),
                _field(_localeController, 'Locale'),
                _intField(_horizonController, 'Default Horizon Years'),
              ],
            ),
            _section(
              context,
              title: 'UI and Accessibility',
              children: [
                SizedBox(
                  width: ResponsiveConstraints.itemWidth(
                    context,
                    idealWidth: 260,
                  ),
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
                  width: ResponsiveConstraints.itemWidth(
                    context,
                    idealWidth: 260,
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _uiDensityMode,
                    decoration: const InputDecoration(
                      labelText: 'Density Mode',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'comfort',
                        child: Text('Comfort'),
                      ),
                      DropdownMenuItem(
                        value: 'compact',
                        child: Text('Compact'),
                      ),
                      DropdownMenuItem(
                        value: 'adaptive',
                        child: Text('Adaptive'),
                      ),
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
                  width: ResponsiveConstraints.itemWidth(
                    context,
                    idealWidth: 320,
                  ),
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
            _section(
              context,
              title: 'Operating Defaults',
              children: [
                _decimalField(_vacancyController, 'Vacancy % (0-1)'),
                _decimalField(_managementController, 'Management % (0-1)'),
                _decimalField(_maintenanceController, 'Maintenance % (0-1)'),
                _decimalField(_capexController, 'CapEx % (0-1)'),
              ],
            ),
            _section(
              context,
              title: 'Growth and Exit',
              children: [
                _decimalField(_appreciationController, 'Appreciation % (0-1)'),
                _decimalField(_rentGrowthController, 'Rent Growth % (0-1)'),
                _decimalField(
                  _expenseGrowthController,
                  'Expense Growth % (0-1)',
                ),
                _decimalField(_saleCostController, 'Sale Cost % (0-1)'),
                _decimalField(
                  _closingBuyController,
                  'Closing Cost Buy % (0-1)',
                ),
                _decimalField(
                  _closingSellController,
                  'Closing Cost Sell % (0-1)',
                ),
              ],
            ),
            _section(
              context,
              title: 'Financing',
              children: [
                _decimalField(_downPaymentController, 'Down Payment % (0-1)'),
                _decimalField(_interestController, 'Interest Rate % (0-1)'),
                _intField(_termYearsController, 'Term Years'),
              ],
            ),
            _section(
              context,
              title: 'Portfolio and Notifications',
              children: [
                SizedBox(
                  width: ResponsiveConstraints.itemWidth(
                    context,
                    idealWidth: 320,
                  ),
                  child: SwitchListTile(
                    value: _enableDemoSeed,
                    onChanged: (value) {
                      setState(() {
                        _enableDemoSeed = value;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Demo Seed Button'),
                  ),
                ),
                _decimalField(
                  _vacancyAlertController,
                  'Vacancy Alert Threshold (0-1)',
                ),
                _decimalField(
                  _noiDropAlertController,
                  'NOI Drop Alert Threshold (0-1)',
                ),
                _intField(_taskDueSoonDaysController, 'Task Due Soon Days'),
                _field(
                  _defaultMarketRentModeController,
                  'Default Market Rent Mode',
                ),
                _intField(
                  _budgetYearStartMonthController,
                  'Budget Year Start Month (1-12)',
                ),
                _intField(
                  _maintenanceDueSoonDaysController,
                  'Maintenance Due Soon Days',
                ),
                _intField(
                  _covenantDueSoonDaysController,
                  'Covenant Due Soon Days',
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
                _field(
                  _scenarioAutoDailyVersionsUserController,
                  'Auto Version User Id',
                ),
                SizedBox(
                  width: ResponsiveConstraints.itemWidth(
                    context,
                    idealWidth: 320,
                  ),
                  child: SwitchListTile(
                    value: _enableTaskNotifications,
                    onChanged: (value) {
                      setState(() {
                        _enableTaskNotifications = value;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Task Notifications'),
                  ),
                ),
              ],
            ),
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
                    decoration: const InputDecoration(
                      labelText: 'Workspace Root Path (optional)',
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
            _section(
              context,
              title: 'Security',
              children: [
                SizedBox(
                  width: ResponsiveConstraints.itemWidth(
                    context,
                    idealWidth: 360,
                  ),
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
                _field(_appLockPasswordController, 'New App Lock Password'),
                ElevatedButton(
                  onPressed: canSettingsEdit ? _applySecurity : null,
                  child: const Text('Apply Security'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: canSettingsEdit ? _save : null,
                  child: const Text('Save Settings'),
                ),
                OutlinedButton(onPressed: _load, child: const Text('Reload')),
              ],
            ),
            if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          ],
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 12, children: children),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return SizedBox(
      width: ResponsiveConstraints.itemWidth(context, idealWidth: 260),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _decimalField(TextEditingController controller, String label) {
    return SizedBox(
      width: ResponsiveConstraints.itemWidth(context, idealWidth: 260),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _intField(TextEditingController controller, String label) {
    return SizedBox(
      width: ResponsiveConstraints.itemWidth(context, idealWidth: 260),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Future<void> _load() async {
    final settings = await ref.read(inputsRepositoryProvider).getSettings();
    final workspace = await ref
        .read(workspaceRepositoryProvider)
        .resolvePaths(settings);
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
    _uiThemeMode = settings.uiThemeMode;
    _uiDensityMode = settings.uiDensityMode;
    _uiChartAnimationsEnabled = settings.uiChartAnimationsEnabled;
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _enableDemoSeed = settings.enableDemoSeed;
      _enableTaskNotifications = settings.enableTaskNotifications;
      _status = null;
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
        });
      }
      return;
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

    await ref.read(inputsRepositoryProvider).updateSettings(updated);
    ref.read(settingsRevisionProvider.notifier).state++;
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = updated;
      _status = 'Settings saved.';
    });
  }

  Future<void> _applySecurity() async {
    try {
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
      });
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Security update failed: $error';
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
        _workspaceRootController.text = updated.workspaceRootPath ?? '';
        _status = 'Backup created: ${saveLocation.path}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Backup failed: $error';
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
        _status = 'Restore completed from ${file.path}';
      });
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Restore failed: $error';
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
