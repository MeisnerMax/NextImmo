part of '../../settings_screen.dart';

/// Analysis defaults section (operating, growth/exit, financing underwriting
/// defaults). Split out of the screen body for BIG-009.
extension _AnalysisDefaultsSection on _SettingsScreenState {
  Widget buildAnalysisDefaultsSection(
    BuildContext context, {
    required bool canSettingsEdit,
  }) {
    final s = _strings;
    return Column(
      children: [
        _introCard(
          title: s.text('Analysis Defaults'),
          description: s.text(
            'Keep underwriting assumptions consistent so new scenarios start from the same baseline.',
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _section(
          context,
          title: s.text('Operating Defaults'),
          children: [
            _decimalField(
              _vacancyController,
              s.text('Vacancy Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.05 = 5.0%'),
            ),
            _decimalField(
              _managementController,
              s.text('Management Fee Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.05 = 5.0%'),
            ),
            _decimalField(
              _maintenanceController,
              s.text('Maintenance Reserve Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.05 = 5.0%'),
            ),
            _decimalField(
              _capexController,
              s.text('CapEx Reserve Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.05 = 5.0%'),
            ),
          ],
        ),
        _section(
          context,
          title: s.text('Growth and Exit'),
          children: [
            _decimalField(
              _appreciationController,
              s.text('Appreciation Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.02 = 2.0%'),
            ),
            _decimalField(
              _rentGrowthController,
              s.text('Rent Growth Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.02 = 2.0%'),
            ),
            _decimalField(
              _expenseGrowthController,
              s.text('Expense Growth Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.02 = 2.0%'),
            ),
            _decimalField(
              _saleCostController,
              s.text('Sale Cost Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.06 = 6.0%'),
            ),
            _decimalField(
              _closingBuyController,
              s.text('Acquisition Cost Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.03 = 3.0%'),
            ),
            _decimalField(
              _closingSellController,
              s.text('Disposition Closing Cost Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.02 = 2.0%'),
            ),
          ],
        ),
        _section(
          context,
          title: s.text('Financing'),
          children: [
            _decimalField(
              _downPaymentController,
              s.text('Down Payment Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.25 = 25.0%'),
            ),
            _decimalField(
              _interestController,
              s.text('Interest Rate'),
              enabled: canSettingsEdit,
              helperText: s.text('Decimal value, for example 0.06 = 6.0%'),
            ),
            _intField(
              _termYearsController,
              s.text('Loan Term Years'),
              enabled: canSettingsEdit,
              helperText: s.text('Used for new financing assumptions.'),
            ),
            _field(
              _defaultMarketRentModeController,
              s.text('Default Market Rent Mode'),
              enabled: canSettingsEdit,
              helperText: s.text('Optional market rent default.'),
            ),
          ],
        ),
      ],
    );
  }
}
