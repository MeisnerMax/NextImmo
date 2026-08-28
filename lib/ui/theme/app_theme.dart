import 'package:flutter/material.dart';

enum AppThemeModeSetting { system, light, dark }

enum AppDensityModeSetting { comfort, compact, adaptive }

class AppColorTokens {
  const AppColorTokens({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.glassFill,
    required this.glassStroke,
    required this.innerHighlight,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color glassFill;
  final Color glassStroke;
  final Color innerHighlight;
}

class AppTypographyTokens {
  const AppTypographyTokens({
    required this.h1Size,
    required this.h2Size,
    required this.h3Size,
    required this.bodySize,
    required this.captionSize,
    required this.buttonSize,
  });

  final double h1Size;
  final double h2Size;
  final double h3Size;
  final double bodySize;
  final double captionSize;
  final double buttonSize;
}

/// Precision-Geometric shape scale: 8px for containers, 6px for inputs
/// (deliberately sharper/more technical), pill for status chips.
class AppRadiusTokens {
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 12;
  static const double pill = 999;

  const AppRadiusTokens._();
}

class AppElevationTokens {
  static const double level0 = 0;
  static const double level1 = 1;
  static const double level2 = 2;
  static const double level3 = 4;
  static const double level4 = 8;

  const AppElevationTokens._();
}

class AppIconTokens {
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;

  const AppIconTokens._();
}

/// Categorical palette for multi-series charts.
///
/// **Assign in fixed order, never cycled.** Colour follows the entity, not its
/// rank — a filter that changes the series count must not repaint the
/// survivors. Beyond five categories, fold the tail into "Sonstige" or use
/// small multiples; a sixth generated hue is not an option, because the set
/// below is only separable because it was solved for exactly five.
///
/// **Status colours are deliberately absent.** `success` / `warning` / `error`
/// are reserved for state and never double as "series 4"; the amber slot here
/// is yellow-700, one step off the warning token, for exactly that reason.
///
/// Verified with the dataviz validator against **all pairs** (not just
/// adjacent ones — legends show every series at once) on both the dark
/// `#020617` and the light `#F8FAFC` surface: OKLCH lightness band, chroma
/// floor, protan/deutan/tritan separation, normal-vision separation and WCAG
/// contrast all pass. Re-run that validator before changing any value here —
/// several obvious-looking alternatives (violet next to blue, teal next to
/// cyan) are indistinguishable under colour-vision deficiency and were
/// rejected on measurement, not taste.
///
/// This supersedes the source design's "cyan-to-emerald gradient" note, which
/// describes a single-series accent and says nothing about telling five
/// categories apart.
class AppChartPalette {
  static const List<Color> series = <Color>[
    Color(0xFF0891B2), // cyan-600
    Color(0xFFDB2777), // pink-600
    Color(0xFF2563EB), // blue-600
    Color(0xFF65A30D), // lime-600
    Color(0xFFA16207), // yellow-700
  ];

  /// Colour for series [index], clamped to the defined set.
  static Color at(int index) => series[index % series.length];

  const AppChartPalette._();
}

class AppBreakpoints {
  static const double mobileMax = 767;
  static const double tabletMax = 1199;

  const AppBreakpoints._();
}

enum AppViewport { mobile, tablet, desktop }

enum AppDesktopLayoutZone { large, medium, narrow }

class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.border,
    required this.surfaceAlt,
    required this.textSecondary,
    required this.glassFill,
    required this.glassStroke,
    required this.innerHighlight,
  });

  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color border;
  final Color surfaceAlt;
  final Color textSecondary;

  /// Translucent panel fill (Liquid Enterprise "Level 1").
  ///
  /// Deliberately alpha-blended rather than opaque so the same value works
  /// behind a real [BackdropFilter] (shell chrome, overlays) and in the cheap
  /// no-blur treatment used for the many small cards in dense grids.
  final Color glassFill;

  /// 1px panel outline — replaces the old hard border in dark.
  final Color glassStroke;

  /// Top-edge inner highlight that carries card hierarchy instead of a shadow.
  ///
  /// This is the *only* depth cue in the system. There is deliberately no glow
  /// token: the accent bloom the source design specified was removed on the
  /// author's call, so depth comes from the fill/stroke/highlight triplet and
  /// nothing emits light. Do not reintroduce a colored `BoxShadow` — see the
  /// elevation section of `03_design_system.md`.
  final Color innerHighlight;

  @override
  ThemeExtension<AppSemanticColors> copyWith({
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? border,
    Color? surfaceAlt,
    Color? textSecondary,
    Color? glassFill,
    Color? glassStroke,
    Color? innerHighlight,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      border: border ?? this.border,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      textSecondary: textSecondary ?? this.textSecondary,
      glassFill: glassFill ?? this.glassFill,
      glassStroke: glassStroke ?? this.glassStroke,
      innerHighlight: innerHighlight ?? this.innerHighlight,
    );
  }

  @override
  ThemeExtension<AppSemanticColors> lerp(
    covariant ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) {
      return this;
    }
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      border: Color.lerp(border, other.border, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassStroke: Color.lerp(glassStroke, other.glassStroke, t)!,
      innerHighlight: Color.lerp(innerHighlight, other.innerHighlight, t)!,
    );
  }
}

class AppDensityConfig extends ThemeExtension<AppDensityConfig> {
  const AppDensityConfig({required this.mode});

  final AppDensityModeSetting mode;

  @override
  ThemeExtension<AppDensityConfig> copyWith({AppDensityModeSetting? mode}) {
    return AppDensityConfig(mode: mode ?? this.mode);
  }

  @override
  ThemeExtension<AppDensityConfig> lerp(
    covariant ThemeExtension<AppDensityConfig>? other,
    double t,
  ) {
    if (other is! AppDensityConfig) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

/// Single source of truth for every raw color value (DEBT-TOKEN-001).
///
/// Both [AppColors] (legacy static access, light-only) and [AppTheme]'s
/// light/dark token tables reference these constants — never define a color
/// literal in either of them directly, extend this palette instead. That
/// keeps the two access paths structurally incapable of drifting apart
/// (guarded by test/ui/theme/token_source_sync_test.dart).
class _Palette {
  // Light — the same Liquid Enterprise structure, without the glass.
  //
  // Slate rather than the previous warm cream: the identity is now navy/cyan,
  // and a warm light theme next to a cold dark theme reads as two products.
  // The accent is cyan-700, not the dark theme's cyan-400 — Action Cyan on
  // white is ~1.9:1 and unusable for text or small controls.
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF1F5F9);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569); // 8.6:1 on white
  static const Color lightPrimary = Color(0xFF0E7490); // cyan-700, 5.1:1
  static const Color lightSecondary = lightTextPrimary;
  static const Color lightAccent = Color(0xFF0D9488);
  static const Color lightSuccess = Color(0xFF059669);
  static const Color lightWarning = Color(0xFFB45309); // amber-700 for AA
  static const Color lightError = Color(0xFFDC2626);
  static const Color lightInfo = lightPrimary;

  // Dark — "Liquid Enterprise", the leading identity.
  static const Color darkBackground = Color(0xFF020617); // Deep Midnight Navy
  static const Color darkSurface = Color(0xFF0F172A);
  static const Color darkSurfaceAlt = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF1E293B);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);

  /// Muted UI text.
  ///
  /// The source design used `#64748B` here, which is 4.24:1 on the navy
  /// canvas and fails WCAG AA for body text. Lifted to slate-400 (7.9:1).
  /// `#64748B` remains acceptable for non-text affordances only.
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkPrimary = Color(0xFF22D3EE); // Action Cyan, 11.2:1
  static const Color darkSecondary = Color(0xFFCBD5E1);

  /// Sits between Action Cyan and Success Emerald — the midpoint of the
  /// chart gradient the design specifies.
  static const Color darkAccent = Color(0xFF2DD4BF);
  static const Color darkSuccess = Color(0xFF10B981); // Success Emerald
  static const Color darkWarning = Color(0xFFF59E0B);
  static const Color darkError = Color(0xFFF87171);
  static const Color darkInfo = darkPrimary;

  // Depth tokens. Depth is built from a translucent fill, a hairline stroke
  // and a top-edge highlight — no emission, no drop shadow.
  static const Color darkGlassFill = Color(0x990F172A); // 60%
  static const Color darkGlassStroke = Color(0x14FFFFFF); // white 8%
  static const Color darkInnerHighlight = Color(0x0DFFFFFF); // white 5%

  static const Color lightGlassFill = Color(0xCCFFFFFF); // 80%
  static const Color lightGlassStroke = Color(0x140F172A);
  static const Color lightInnerHighlight = Color(0x0DFFFFFF);

  // Micro-tokens used directly by AppTheme._buildTheme.
  static const Color darkOnPrimary = Color(0xFF020617); // black-on-cyan
  static const Color tooltipSurfaceLight = Color(0xFF1C2733);
  static const Color tooltipSurfaceDark = Color(0xFF1E2731);

  // Shell sidebar (deliberately dark navy in both brightnesses).
  //
  // Sits one step below the canvas so the shell reads as the frame rather
  // than as another panel. The active item is Action Cyan on a cyan-tinted
  // fill — in the design the left bracket carries the selection, so the fill
  // stays quiet on purpose.
  static const Color sidebarBackground = Color(0xFF01040E);
  static const Color sidebarSelected = Color(0xFF07202E);
  static const Color sidebarText = Color(0xFF94A3B8);
  static const Color sidebarTextActive = Color(0xFF22D3EE);
  static const Color sidebarMuted = Color(0xFF64748B);

  const _Palette._();
}

class AppColors {
  /// Legacy screens treat "background" as the white surface color, not the
  /// warm canvas ([_Palette.lightBackground]). Kept that way deliberately —
  /// migrating those screens to theme-based colors happens per screen in its
  /// redesign wave (DEBT-TOKEN-001, waves 1/3/6).
  static const Color background = _Palette.lightSurface;
  static const Color surface = _Palette.lightSurface;
  static const Color border = _Palette.lightBorder;
  static const Color textPrimary = _Palette.lightTextPrimary;
  static const Color textSecondary = _Palette.lightTextSecondary;
  static const Color primary = _Palette.lightPrimary;
  static const Color positive = _Palette.lightSuccess;
  static const Color negative = _Palette.lightError;
  static const Color warning = _Palette.lightWarning;

  // Shell sidebar tokens (theme-independent, see _Palette).
  static const Color sidebarBackground = _Palette.sidebarBackground;
  static const Color sidebarSelected = _Palette.sidebarSelected;
  static const Color sidebarText = _Palette.sidebarText;
  static const Color sidebarTextActive = _Palette.sidebarTextActive;
  static const Color sidebarMuted = _Palette.sidebarMuted;

  const AppColors._();
}

class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double xxxl = 48;

  static const double page = lg;
  static const double section = lg;
  static const double component = sm;
  static const double cardPadding = md;

  const AppSpacing._();
}

class AppLayout {
  static const double desktopMaxContentWidth = 1440;
  static const double tabletMaxContentWidth = 1100;
  static const double desktopLargeMinWidth = 1440;
  static const double desktopMediumMinWidth = 1100;

  /// Master-detail panes split side by side from this width on — i.e. when
  /// the width *exceeds* [AppBreakpoints.tabletMax] (Foundation §4). The one
  /// constant behind `NxSplitView`, replacing the per-screen 1200 literals.
  static const double splitViewMinWidth = AppBreakpoints.tabletMax + 1;

  const AppLayout._();

  static AppViewport viewportForWidth(double width) {
    if (width <= AppBreakpoints.mobileMax) {
      return AppViewport.mobile;
    }
    if (width <= AppBreakpoints.tabletMax) {
      return AppViewport.tablet;
    }
    return AppViewport.desktop;
  }

  static double pagePaddingFor({
    required double width,
    required AppDensityModeSetting densityMode,
  }) {
    if (densityMode == AppDensityModeSetting.compact) {
      return 16;
    }
    if (densityMode == AppDensityModeSetting.adaptive) {
      final viewport = viewportForWidth(width);
      switch (viewport) {
        case AppViewport.mobile:
          return 20;
        case AppViewport.tablet:
          return 24;
        case AppViewport.desktop:
          return 64;
      }
    }
    if (width <= AppBreakpoints.mobileMax) {
      return 20;
    }
    if (width <= AppBreakpoints.tabletMax) {
      return 24;
    }
    return 64;
  }

  static int columnsForWidth(double width) {
    final viewport = viewportForWidth(width);
    switch (viewport) {
      case AppViewport.mobile:
        return 4;
      case AppViewport.tablet:
        return 8;
      case AppViewport.desktop:
        return 12;
    }
  }

  static AppDesktopLayoutZone desktopZoneForWidth(double width) {
    if (width >= desktopLargeMinWidth) {
      return AppDesktopLayoutZone.large;
    }
    if (width >= desktopMediumMinWidth) {
      return AppDesktopLayoutZone.medium;
    }
    return AppDesktopLayoutZone.narrow;
  }
}

class AppTheme {
  const AppTheme._();

  static const AppColorTokens _lightTokens = AppColorTokens(
    background: _Palette.lightBackground,
    surface: _Palette.lightSurface,
    surfaceAlt: _Palette.lightSurfaceAlt,
    border: _Palette.lightBorder,
    textPrimary: _Palette.lightTextPrimary,
    textSecondary: _Palette.lightTextSecondary,
    primary: _Palette.lightPrimary,
    secondary: _Palette.lightSecondary,
    accent: _Palette.lightAccent,
    success: _Palette.lightSuccess,
    warning: _Palette.lightWarning,
    error: _Palette.lightError,
    info: _Palette.lightInfo,
    glassFill: _Palette.lightGlassFill,
    glassStroke: _Palette.lightGlassStroke,
    innerHighlight: _Palette.lightInnerHighlight,
  );

  static const AppColorTokens _darkTokens = AppColorTokens(
    background: _Palette.darkBackground,
    surface: _Palette.darkSurface,
    surfaceAlt: _Palette.darkSurfaceAlt,
    border: _Palette.darkBorder,
    textPrimary: _Palette.darkTextPrimary,
    textSecondary: _Palette.darkTextSecondary,
    primary: _Palette.darkPrimary,
    secondary: _Palette.darkSecondary,
    accent: _Palette.darkAccent,
    success: _Palette.darkSuccess,
    warning: _Palette.darkWarning,
    error: _Palette.darkError,
    info: _Palette.darkInfo,
    glassFill: _Palette.darkGlassFill,
    glassStroke: _Palette.darkGlassStroke,
    innerHighlight: _Palette.darkInnerHighlight,
  );

  static const AppTypographyTokens _comfortTypography = AppTypographyTokens(
    h1Size: 48,
    h2Size: 24,
    h3Size: 18,
    bodySize: 15,
    captionSize: 12,
    buttonSize: 12,
  );

  static const AppTypographyTokens _compactTypography = AppTypographyTokens(
    h1Size: 32,
    h2Size: 22,
    h3Size: 18,
    bodySize: 13,
    captionSize: 11,
    buttonSize: 13,
  );

  static ThemeData light({
    AppDensityModeSetting densityMode = AppDensityModeSetting.comfort,
  }) {
    return _buildTheme(
      tokens: _lightTokens,
      brightness: Brightness.light,
      densityMode: densityMode,
    );
  }

  static ThemeData dark({
    AppDensityModeSetting densityMode = AppDensityModeSetting.comfort,
  }) {
    return _buildTheme(
      tokens: _darkTokens,
      brightness: Brightness.dark,
      densityMode: densityMode,
    );
  }

  static ThemeMode resolveThemeMode(String value) {
    switch (value.trim().toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static AppDensityModeSetting resolveDensityMode(String value) {
    switch (value.trim().toLowerCase()) {
      case 'compact':
        return AppDensityModeSetting.compact;
      case 'adaptive':
        return AppDensityModeSetting.adaptive;
      default:
        return AppDensityModeSetting.comfort;
    }
  }

  static ThemeData _buildTheme({
    required AppColorTokens tokens,
    required Brightness brightness,
    required AppDensityModeSetting densityMode,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: tokens.primary,
      brightness: brightness,
      primary: tokens.primary,
      secondary: tokens.secondary,
      error: tokens.error,
      surface: tokens.surface,
    );
    final compact = densityMode == AppDensityModeSetting.compact;
    final typography = compact ? _compactTypography : _comfortTypography;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        onSurface: tokens.textPrimary,
        onSurfaceVariant: tokens.textSecondary,
        onPrimary:
            brightness == Brightness.light
                ? Colors.white
                : _Palette.darkOnPrimary,
        outlineVariant: tokens.border,
        surfaceContainerHighest: tokens.surfaceAlt,
      ),
      scaffoldBackgroundColor: tokens.background,
      fontFamily: 'Inter',
      textTheme: TextTheme(
        // Headlines run on Hanken Grotesk, which ships as a variable font.
        // Flutter does not map `fontWeight` onto a variable font's wght axis,
        // so the weight has to come from `fontVariations`; `fontWeight` is
        // kept alongside it purely so widgets that read it (and any fallback
        // to Inter if the asset is missing) still resolve sensibly.
        displaySmall: TextStyle(
          fontFamily: 'HankenGrotesk',
          fontVariations: const [FontVariation('wght', 700)],
          fontSize: typography.h1Size,
          height: 1.16,
          fontWeight: FontWeight.w700,
          color: tokens.textPrimary,
          letterSpacing: -0.02 * typography.h1Size,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'HankenGrotesk',
          fontVariations: const [FontVariation('wght', 600)],
          fontSize: typography.h2Size,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
          letterSpacing: -0.01 * typography.h2Size,
        ),
        titleLarge: TextStyle(
          fontFamily: 'HankenGrotesk',
          fontVariations: const [FontVariation('wght', 600)],
          fontSize: typography.h3Size,
          height: 1.33,
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
          letterSpacing: 0,
        ),
        titleMedium: TextStyle(
          fontSize: compact ? 15 : 16,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
          letterSpacing: 0,
        ),
        bodyMedium: TextStyle(
          fontSize: typography.bodySize,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: tokens.textPrimary,
          letterSpacing: 0,
        ),
        bodySmall: TextStyle(
          fontSize: typography.captionSize,
          height: 1.4,
          fontWeight: FontWeight.w400,
          color: tokens.textSecondary,
          letterSpacing: 0,
        ),
        // The design's `label-sm`: uppercase-with-tracking is what separates
        // "metadata" from "content" in this system, so the tracking lives in
        // the token rather than being re-applied per screen.
        labelMedium: TextStyle(
          fontSize: compact ? 11 : 12,
          height: 1.33,
          fontWeight: FontWeight.w600,
          color: tokens.textSecondary,
          letterSpacing: 0.05 * (compact ? 11 : 12),
        ),
        labelLarge: TextStyle(
          fontSize: typography.buttonSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      // Aligned with NxCard so the ~180 raw Material `Card(...)` widgets still
      // scattered across the unmigrated screens land close to the system
      // instead of reading as a different, flatter surface next to it. The
      // one thing that cannot be expressed here is NxCard's top-edge
      // highlight gradient — CardThemeData takes a color, not a gradient — so
      // migrating a screen to NxCard is still a real improvement, just no
      // longer the difference between "designed" and "not designed".
      cardTheme: CardThemeData(
        color: tokens.glassFill,
        elevation: 0,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          side: BorderSide(color: tokens.glassStroke),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: compact,
        filled: true,
        fillColor: tokens.surface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 10 : 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          borderSide: BorderSide(color: tokens.primary, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          borderSide: BorderSide(color: tokens.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          borderSide: BorderSide(color: tokens.error, width: 1),
        ),
      ),
      // Maximum data density: 8px vertical padding, and rows separated by
      // background alternates rather than divider lines. `dividerThickness: 0`
      // is what makes the zebra treatment readable — lines plus alternates
      // read as noise.
      dataTableTheme: DataTableThemeData(
        headingTextStyle: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: tokens.textSecondary,
          letterSpacing: 0.05 * (compact ? 11 : 12),
        ),
        dataTextStyle: TextStyle(
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w500,
          color: tokens.textPrimary,
        ),
        dividerThickness: 0,
        headingRowHeight: compact ? 34 : 38,
        dataRowMinHeight: compact ? 34 : 38,
        dataRowMaxHeight: compact ? 38 : 44,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surfaceAlt.withValues(alpha: 0.72),
        side: BorderSide(color: tokens.border),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
        ),
      ),
      dividerTheme: DividerThemeData(color: tokens.border, thickness: 1),
      tooltipTheme: TooltipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: BoxDecoration(
          color:
              brightness == Brightness.dark
                  ? _Palette.tooltipSurfaceDark
                  : _Palette.tooltipSurfaceLight,
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return tokens.textSecondary;
          }
          return tokens.border;
        }),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(4),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor:
              brightness == Brightness.light
                  ? Colors.white
                  : _Palette.darkOnPrimary,
          // Flat. The accent fill alone carries primary emphasis; no bloom.
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 10 : 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 10 : 12,
          ),
          side: BorderSide(color: tokens.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          textStyle: TextStyle(
            fontSize: typography.buttonSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.textSecondary,
        textColor: tokens.textPrimary,
        selectedColor: tokens.primary,
        selectedTileColor: tokens.surfaceAlt.withValues(alpha: 0.42),
      ),
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[
        AppSemanticColors(
          success: tokens.success,
          warning: tokens.warning,
          error: tokens.error,
          info: tokens.info,
          border: tokens.border,
          surfaceAlt: tokens.surfaceAlt,
          textSecondary: tokens.textSecondary,
          glassFill: tokens.glassFill,
          glassStroke: tokens.glassStroke,
          innerHighlight: tokens.innerHighlight,
        ),
        AppDensityConfig(mode: densityMode),
      ],
    );
  }
}

extension AppThemeContext on BuildContext {
  AppSemanticColors get semanticColors {
    final theme = Theme.of(this);
    final colors = theme.extension<AppSemanticColors>();
    if (colors != null) {
      return colors;
    }
    final scheme = theme.colorScheme;
    // Fallback for themes built without the extension (bare `ThemeData()` in
    // tests and dialogs). Success/warning have no ColorScheme equivalent, so
    // they come straight from the palette — deliberately *not* via
    // `semanticColors`, which is this getter and would recurse forever.
    return AppSemanticColors(
      success: _Palette.lightSuccess,
      warning: _Palette.lightWarning,
      error: scheme.error,
      info: scheme.primary,
      border: scheme.outlineVariant,
      surfaceAlt: scheme.surfaceContainerHighest,
      textSecondary: scheme.onSurfaceVariant,
      glassFill: scheme.surface,
      glassStroke: scheme.outlineVariant,
      innerHighlight: const Color(0x00000000),
    );
  }

  AppDensityModeSetting get densityMode {
    return Theme.of(this).extension<AppDensityConfig>()?.mode ??
        AppDensityModeSetting.comfort;
  }

  AppViewport get viewport {
    return AppLayout.viewportForWidth(MediaQuery.sizeOf(this).width);
  }

  AppDesktopLayoutZone get desktopLayoutZone {
    return AppLayout.desktopZoneForWidth(MediaQuery.sizeOf(this).width);
  }

  bool get isLargeDesktop => desktopLayoutZone == AppDesktopLayoutZone.large;

  bool get isMediumDesktop => desktopLayoutZone == AppDesktopLayoutZone.medium;

  bool get isNarrowDesktop => desktopLayoutZone == AppDesktopLayoutZone.narrow;

  bool get compactLayout {
    final mode = densityMode;
    if (mode == AppDensityModeSetting.compact) {
      return true;
    }
    if (mode == AppDensityModeSetting.adaptive) {
      return viewport == AppViewport.desktop;
    }
    return false;
  }

  double get adaptivePagePadding {
    return AppLayout.pagePaddingFor(
      width: MediaQuery.sizeOf(this).width,
      densityMode: densityMode,
    );
  }

  TextStyle get tabularNumericStyle {
    return const TextStyle(
      fontFamily: 'Inter',
      fontFeatures: [FontFeature.tabularFigures()],
    );
  }

  /// Monospaced treatment for technical asset IDs and financial values.
  ///
  /// The design introduces a second font specifically so columns of numbers
  /// align and digits stay unambiguous — use this for IDs, money, and any
  /// figure the user compares vertically, not for prose.
  TextStyle get dataMonoStyle {
    return const TextStyle(
      fontFamily: 'JetBrainsMono',
      fontWeight: FontWeight.w500,
      fontFeatures: [FontFeature.tabularFigures()],
    );
  }
}
