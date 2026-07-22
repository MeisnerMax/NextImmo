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

class AppRadiusTokens {
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;

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
  });

  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color border;
  final Color surfaceAlt;
  final Color textSecondary;

  @override
  ThemeExtension<AppSemanticColors> copyWith({
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? border,
    Color? surfaceAlt,
    Color? textSecondary,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      border: border ?? this.border,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      textSecondary: textSecondary ?? this.textSecondary,
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
  // Light (warm-neutral, Phase 2 design system)
  static const Color lightBackground = Color(0xFFF9F8F5); // warm off-white canvas
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF3F1EC);
  static const Color lightBorder = Color(0xFFE6E2DB);
  static const Color lightTextPrimary = Color(0xFF1C1A17);
  static const Color lightTextSecondary = Color(0xFF6A645B);
  static const Color lightPrimary = Color(0xFF2563EB);
  static const Color lightSecondary = lightTextPrimary;
  static const Color lightAccent = Color(0xFF0D9488); // slate teal
  static const Color lightSuccess = Color(0xFF16A34A);
  static const Color lightWarning = Color(0xFFD97706);
  static const Color lightError = Color(0xFFDC2626);
  static const Color lightInfo = lightPrimary;

  // Dark (warm charcoal, Phase 2 design system)
  static const Color darkBackground = Color(0xFF13110D);
  static const Color darkSurface = Color(0xFF1C1915);
  static const Color darkSurfaceAlt = Color(0xFF272119);
  static const Color darkBorder = Color(0xFF37322B);
  static const Color darkTextPrimary = Color(0xFFF4F1EB);
  static const Color darkTextSecondary = Color(0xFF9E968A);
  static const Color darkPrimary = Color(0xFF60A5FA); // high-contrast primary blue
  static const Color darkSecondary = Color(0xFFD2CCC0);
  static const Color darkAccent = Color(0xFF2DD4BF);
  static const Color darkSuccess = Color(0xFF34D399);
  static const Color darkWarning = Color(0xFFFBBF24);
  static const Color darkError = Color(0xFFF87171);
  static const Color darkInfo = darkPrimary;

  // Micro-tokens used directly by AppTheme._buildTheme.
  static const Color darkOnPrimary = Color(0xFF06224A);
  static const Color tooltipSurfaceLight = Color(0xFF1C2733);
  static const Color tooltipSurfaceDark = Color(0xFF1E2731);

  // Shell sidebar (deliberately dark navy in both brightnesses).
  static const Color sidebarBackground = Color(0xFF030C28);
  static const Color sidebarSelected = Color(0xFF17417D);
  static const Color sidebarText = Color(0xFFEAF2FF);
  static const Color sidebarTextActive = Color(0xFFFFFFFF);
  static const Color sidebarMuted = Color(0xFFBFD0EA);

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
      fontFamily: 'Geist',
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: typography.h1Size,
          height: 1.12,
          fontWeight: FontWeight.w300,
          color: tokens.textPrimary,
          letterSpacing: 0,
        ),
        headlineSmall: TextStyle(
          fontSize: typography.h2Size,
          height: 1.3,
          fontWeight: FontWeight.w500,
          color: tokens.textPrimary,
          letterSpacing: 0,
        ),
        titleLarge: TextStyle(
          fontSize: typography.h3Size,
          height: 1.3,
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
        labelMedium: TextStyle(
          fontSize: compact ? 11 : 12,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: tokens.textSecondary,
          letterSpacing: 0,
        ),
        labelLarge: TextStyle(
          fontSize: typography.buttonSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          side: BorderSide(color: tokens.border),
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
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          borderSide: BorderSide(color: tokens.primary, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          borderSide: BorderSide(color: tokens.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          borderSide: BorderSide(color: tokens.error, width: 1),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: tokens.textSecondary,
        ),
        dataTextStyle: TextStyle(
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w500,
          color: tokens.textPrimary,
        ),
        dividerThickness: 0.8,
        headingRowHeight: compact ? 38 : 42,
        dataRowMinHeight: compact ? 36 : 40,
        dataRowMaxHeight: compact ? 40 : 44,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surfaceAlt.withValues(alpha: 0.72),
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        ),
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
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 10 : 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
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
            borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
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
    return AppSemanticColors(
      success: Colors.green,
      warning: Colors.orange,
      error: scheme.error,
      info: scheme.primary,
      border: scheme.outlineVariant,
      surfaceAlt: scheme.surfaceContainerHighest,
      textSecondary: scheme.onSurfaceVariant,
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
    return TextStyle(
      fontFamily: 'Geist',
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
