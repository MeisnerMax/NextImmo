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
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;

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

class AppColors {
  static const Color background = Color(0xFFF6F8FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFD4DCE5);
  static const Color textPrimary = Color(0xFF1C2733);
  static const Color textSecondary = Color(0xFF5A6B7C);
  static const Color primary = Color(0xFF0F5C73);
  static const Color positive = Color(0xFF1C8C5E);
  static const Color negative = Color(0xFFC44949);
  static const Color warning = Color(0xFFC28A1A);

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
          return 12;
        case AppViewport.tablet:
          return 16;
        case AppViewport.desktop:
          return 24;
      }
    }
    return 24;
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
    background: Color(0xFFF6F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEF2F6),
    border: Color(0xFFD4DCE5),
    textPrimary: Color(0xFF1C2733),
    textSecondary: Color(0xFF5A6B7C),
    primary: Color(0xFF0F5C73),
    secondary: Color(0xFF3A7E91),
    accent: Color(0xFF16A3A6),
    success: Color(0xFF1C8C5E),
    warning: Color(0xFFC28A1A),
    error: Color(0xFFC44949),
    info: Color(0xFF2B78B8),
  );

  static const AppColorTokens _darkTokens = AppColorTokens(
    background: Color(0xFF0F141A),
    surface: Color(0xFF161D25),
    surfaceAlt: Color(0xFF1E2731),
    border: Color(0xFF2D3946),
    textPrimary: Color(0xFFE8EEF5),
    textSecondary: Color(0xFFB2C0CF),
    primary: Color(0xFF41A8C4),
    secondary: Color(0xFF5BB7C8),
    accent: Color(0xFF57D2CF),
    success: Color(0xFF41B883),
    warning: Color(0xFFE0A13D),
    error: Color(0xFFE47676),
    info: Color(0xFF6AB0E8),
  );

  static const AppTypographyTokens _comfortTypography = AppTypographyTokens(
    h1Size: 32,
    h2Size: 24,
    h3Size: 20,
    bodySize: 14,
    captionSize: 12,
    buttonSize: 14,
  );

  static const AppTypographyTokens _compactTypography = AppTypographyTokens(
    h1Size: 30,
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
        onPrimary: Colors.white,
      ),
      scaffoldBackgroundColor: tokens.background,
      fontFamily: 'Segoe UI',
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: typography.h1Size,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: tokens.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: typography.h2Size,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: tokens.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: typography.h3Size,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: tokens.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: compact ? 15 : 16,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: typography.bodySize,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: tokens.textPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: typography.captionSize,
          height: 1.4,
          fontWeight: FontWeight.w400,
          color: tokens.textSecondary,
        ),
        labelMedium: TextStyle(
          fontSize: compact ? 11 : 12,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: tokens.textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: typography.buttonSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation:
            brightness == Brightness.dark ? 0 : AppElevationTokens.level2,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          side: BorderSide(color: tokens.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: compact,
        filled: true,
        fillColor: tokens.surfaceAlt,
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
          borderSide: BorderSide(color: tokens.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          borderSide: BorderSide(color: tokens.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          borderSide: BorderSide(color: tokens.error, width: 1.4),
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
        backgroundColor: tokens.surfaceAlt,
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  ? const Color(0xFF1E2731)
                  : const Color(0xFF1C2733),
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
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 10 : 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 10 : 12,
          ),
          side: BorderSide(color: tokens.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          ),
        ),
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
}
