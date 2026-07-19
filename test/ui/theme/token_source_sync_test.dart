import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Drift guard for DEBT-TOKEN-001.
///
/// [AppColors] (legacy static access) and the light token table inside
/// [AppTheme] both reference the same private palette. This test pins the
/// overlap through the public theme API so a reintroduced color literal in
/// either source fails loudly instead of drifting silently.
///
/// Deliberately NOT asserted: `AppColors.background` vs
/// `scaffoldBackgroundColor` — legacy screens treat "background" as the white
/// surface while the real canvas token is warmer. That mismatch is known and
/// resolved per screen in its redesign wave (see
/// `docs/architecture/phase_2/02_architecture_modernization_backlog.md`).
void main() {
  test('AppColors stays in sync with the light token source', () {
    final theme = AppTheme.light();
    final semantic = theme.extension<AppSemanticColors>()!;

    expect(theme.cardTheme.color, AppColors.surface);
    expect(semantic.border, AppColors.border);
    expect(theme.colorScheme.onSurface, AppColors.textPrimary);
    expect(semantic.textSecondary, AppColors.textSecondary);
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(semantic.success, AppColors.positive);
    expect(semantic.error, AppColors.negative);
    expect(semantic.warning, AppColors.warning);
  });

  test('light and dark themes expose distinct token tables', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    final lightSemantic = light.extension<AppSemanticColors>()!;
    final darkSemantic = dark.extension<AppSemanticColors>()!;

    // Guards against one table accidentally aliasing the other.
    expect(light.scaffoldBackgroundColor,
        isNot(equals(dark.scaffoldBackgroundColor)));
    expect(lightSemantic.border, isNot(equals(darkSemantic.border)));
    expect(lightSemantic.textSecondary,
        isNot(equals(darkSemantic.textSecondary)));
    expect(light.colorScheme.primary, isNot(equals(dark.colorScheme.primary)));
  });
}
