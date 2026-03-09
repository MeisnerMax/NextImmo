import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

void main() {
  test('resolve theme mode from setting', () {
    expect(AppTheme.resolveThemeMode('system'), ThemeMode.system);
    expect(AppTheme.resolveThemeMode('light'), ThemeMode.light);
    expect(AppTheme.resolveThemeMode('dark'), ThemeMode.dark);
    expect(AppTheme.resolveThemeMode('unknown'), ThemeMode.system);
  });

  test('resolve density mode from setting', () {
    expect(
      AppTheme.resolveDensityMode('comfort'),
      AppDensityModeSetting.comfort,
    );
    expect(
      AppTheme.resolveDensityMode('compact'),
      AppDensityModeSetting.compact,
    );
    expect(
      AppTheme.resolveDensityMode('adaptive'),
      AppDensityModeSetting.adaptive,
    );
    expect(
      AppTheme.resolveDensityMode('invalid'),
      AppDensityModeSetting.comfort,
    );
  });
}
