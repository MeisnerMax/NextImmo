part of '../../settings_screen.dart';

/// Security section (app lock and restricted local access). Split out of the
/// screen body for BIG-009. `_applySecurity` stays on the state class.
extension _SecuritySection on _SettingsScreenState {
  Widget buildSecuritySection(
    BuildContext context, {
    required bool canSettingsEdit,
  }) {
    final s = _strings;
    return Column(
      children: [
        _introCard(
          title: s.text('Security'),
          description: s.text(
            'Protect local access without burying the controls in a generic form.',
          ),
          warning: s.text(
            'App lock changes affect local access immediately after applying them.',
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _section(
          context,
          title: s.text('Access Controls'),
          children: [
            SizedBox(
              width: ResponsiveConstraints.itemWidth(context, idealWidth: 360),
              child: SwitchListTile(
                value: _enableAppLock,
                onChanged:
                    canSettingsEdit
                        ? (value) {
                          _editDraft(() {
                            _enableAppLock = value;
                          });
                        }
                        : null,
                contentPadding: EdgeInsets.zero,
                title: Text(s.text('Enable App Lock')),
              ),
            ),
            _field(
              _appLockPasswordController,
              s.text('New App Lock Password'),
              enabled: canSettingsEdit,
              helperText: s.text('Leave empty to keep the current password.'),
              obscureText: true,
            ),
            ElevatedButton(
              onPressed: canSettingsEdit ? _applySecurity : null,
              child: Text(s.text('Apply Security')),
            ),
          ],
        ),
      ],
    );
  }
}
