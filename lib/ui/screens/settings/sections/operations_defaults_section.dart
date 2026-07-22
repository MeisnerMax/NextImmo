part of '../../settings_screen.dart';

/// Operations defaults section (task/maintenance/covenant/automation defaults).
/// Split out of the screen body for BIG-009.
extension _OperationsDefaultsSection on _SettingsScreenState {
  Widget buildOperationsDefaultsSection(
    BuildContext context, {
    required bool canSettingsEdit,
  }) {
    final s = _strings;
    return Column(
      children: [
        _introCard(
          title: s.text('Operations Defaults'),
          description: s.text(
            'Use one operational baseline for generated work, budgets, and recurring checks.',
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _section(
          context,
          title: s.text('Workflow Defaults'),
          children: [
            _intField(
              _taskDueSoonDaysController,
              s.text('Task Due Soon Days'),
              enabled: canSettingsEdit,
            ),
            _intField(
              _budgetYearStartMonthController,
              s.text('Budget Year Start Month (1-12)'),
              enabled: canSettingsEdit,
            ),
            _intField(
              _maintenanceDueSoonDaysController,
              s.text('Maintenance Due Soon Days'),
              enabled: canSettingsEdit,
            ),
            _intField(
              _covenantDueSoonDaysController,
              s.text('Covenant Due Soon Days'),
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
                          _editDraft(() {
                            _scenarioAutoDailyVersionsEnabled = value;
                          });
                        }
                        : null,
                contentPadding: EdgeInsets.zero,
                title: Text(s.text('Scenario Auto Daily Versions')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
