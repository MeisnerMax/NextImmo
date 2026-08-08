part of '../../settings_screen.dart';

/// Appearance section (theme, density, interface motion). Split out of the
/// screen body for BIG-009.
extension _AppearanceSection on _SettingsScreenState {
  Widget buildAppearanceSection(
    BuildContext context, {
    required bool canSettingsEdit,
  }) {
    final s = _strings;
    return Column(
      children: [
        _introCard(
          title: s.text('Appearance'),
          description: s.text(
            'Control density and motion so the interface stays predictable across desktop setups.',
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _section(
          context,
          title: s.text('UI and Accessibility'),
          children: [
            SizedBox(
              width: ResponsiveConstraints.itemWidth(context, idealWidth: 260),
              child: DropdownButtonFormField<String>(
                value: _uiThemeMode,
                decoration: InputDecoration(labelText: s.text('Theme Mode')),
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(s.text('System')),
                  ),
                  DropdownMenuItem(
                    value: 'light',
                    child: Text(s.text('Light')),
                  ),
                  DropdownMenuItem(value: 'dark', child: Text(s.text('Dark'))),
                ],
                onChanged:
                    canSettingsEdit
                        ? (value) {
                          if (value == null) {
                            return;
                          }
                          _editDraft(() {
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
                decoration: InputDecoration(labelText: s.text('Density Mode')),
                items: [
                  DropdownMenuItem(
                    value: 'comfort',
                    child: Text(s.text('Comfort')),
                  ),
                  DropdownMenuItem(
                    value: 'compact',
                    child: Text(s.text('Compact')),
                  ),
                  DropdownMenuItem(
                    value: 'adaptive',
                    child: Text(s.text('Adaptive')),
                  ),
                ],
                onChanged:
                    canSettingsEdit
                        ? (value) {
                          if (value == null) {
                            return;
                          }
                          _editDraft(() {
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
                          _editDraft(() {
                            _uiChartAnimationsEnabled = value;
                          });
                        }
                        : null,
                contentPadding: EdgeInsets.zero,
                title: Text(s.text('Enable Chart Animations')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
