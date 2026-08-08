part of '../../settings_screen.dart';

/// General section (locale, currency, core scenario defaults). Split out of the
/// screen body for BIG-009; state stays owned by [_SettingsScreenState] and is
/// reached via the implicit receiver of this extension.
extension _GeneralSection on _SettingsScreenState {
  Widget buildGeneralSection(
    BuildContext context, {
    required bool canSettingsEdit,
  }) {
    final s = _strings;
    return Column(
      children: [
        _introCard(
          title: s.text('General'),
          description: s.text(
            'These defaults shape new scenarios before property-specific inputs take over.',
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _section(
          context,
          title: s.text('General Defaults'),
          children: [
            SizedBox(
              width: ResponsiveConstraints.itemWidth(
                context,
                idealWidth: 260,
              ),
              child: DropdownButtonFormField<String>(
                value: _uiLanguageCode,
                decoration: InputDecoration(
                  labelText: s.text('Language'),
                  helperText: s.text(
                    'Choose the language for all texts, tooltips and labels.',
                  ),
                ),
                items: <String>['de', 'en']
                    .map(
                      (code) => DropdownMenuItem<String>(
                        value: code,
                        child: Text(s.languageName(code)),
                      ),
                    )
                    .toList(growable: false),
                onChanged:
                    canSettingsEdit
                        ? (value) {
                          if (value == null) {
                            return;
                          }
                          _editDraft(() {
                            _uiLanguageCode = value;
                          });
                        }
                        : null,
              ),
            ),
            _field(
              _currencyController,
              s.text('Currency Code'),
              enabled: canSettingsEdit,
              helperText: s.text('Used in new scenarios and reports.'),
            ),
            _field(
              _localeController,
              s.text('Locale'),
              enabled: canSettingsEdit,
              helperText: s.text(
                'Formatting profile such as de_DE or en_US.',
              ),
            ),
            _intField(
              _horizonController,
              s.text('Default Hold Period'),
              enabled: canSettingsEdit,
              helperText: s.text('Years used for new scenarios.'),
            ),
          ],
        ),
      ],
    );
  }
}
