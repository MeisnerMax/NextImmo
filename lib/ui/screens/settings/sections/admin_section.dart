part of '../../settings_screen.dart';

/// Admin section (demo data and administrative helper settings). Split out of
/// the screen body for BIG-009.
extension _AdminSection on _SettingsScreenState {
  Widget buildAdminSection(
    BuildContext context, {
    required bool canSettingsEdit,
  }) {
    final s = _strings;
    return Column(
      children: [
        _introCard(
          title: s.text('Admin'),
          description: s.text(
            'Low-frequency administrative switches stay visible, but clearly separated from daily settings.',
          ),
          warning: s.text(
            'Administrative helper settings should stay restricted to setup and test workflows.',
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _section(
          context,
          title: s.text('Administrative Controls'),
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
                          _editDraft(() {
                            _enableDemoSeed = value;
                          });
                        }
                        : null,
                contentPadding: EdgeInsets.zero,
                title: Text(s.text('Enable Demo Seed Button')),
              ),
            ),
            _field(
              _scenarioAutoDailyVersionsUserController,
              s.text('Auto Version User Id'),
              enabled: canSettingsEdit,
              helperText: s.text(
                'User id used for automated scenario versions.',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
