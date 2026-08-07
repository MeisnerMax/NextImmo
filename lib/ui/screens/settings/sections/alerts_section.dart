part of '../../settings_screen.dart';

/// Alerts section (notification thresholds and quality warning behavior). Split
/// out of the screen body for BIG-009.
extension _AlertsSection on _SettingsScreenState {
  Widget buildAlertsSection(
    BuildContext context, {
    required bool canSettingsEdit,
  }) {
    final s = _strings;
    return Column(
      children: [
        _introCard(
          title: s.text('Alerts'),
          description: s.text(
            'Set thresholds that surface issues early without flooding daily work.',
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _section(
          context,
          title: s.text('Alert Thresholds'),
          children: [
            _decimalField(
              _vacancyAlertController,
              s.text('Vacancy Alert Threshold (0-1)'),
            ),
            _decimalField(
              _noiDropAlertController,
              s.text('NOI Drop Alert Threshold (0-1)'),
            ),
            _intField(
              _qualityEpcExpiryWarningDaysController,
              s.text('Quality EPC Expiry Warning Days'),
            ),
            _intField(
              _qualityRentRollStaleMonthsController,
              s.text('Quality Rent Roll Stale Months'),
            ),
            _intField(
              _qualityLedgerStaleDaysController,
              s.text('Quality Ledger Stale Days'),
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
                          _editDraft(() {
                            _enableTaskNotifications = value;
                          });
                        }
                        : null,
                contentPadding: EdgeInsets.zero,
                title: Text(s.text('Enable Task Notifications')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
