import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_environment.dart';
import 'features/reference_slice/presentation/reference_slice_screen.dart';
import 'ui/i18n/app_strings.dart';
import 'ui/navigation/app_navigation.dart';
import 'ui/screens/security/security_gate.dart';
import 'ui/state/app_state.dart';
import 'ui/theme/app_theme.dart';
import 'ui/zoom/app_zoom.dart';

class NexImmoApp extends ConsumerWidget {
  const NexImmoApp({super.key, required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        environment.dataBackend == DataBackend.sqlite
            ? ref.watch(appSettingsProvider).valueOrNull
            : null;
    final densityMode = AppTheme.resolveDensityMode(
      settings?.uiDensityMode ?? 'comfort',
    );

    return MaterialApp(
      title: 'NexImmo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(densityMode: densityMode),
      darkTheme: AppTheme.dark(densityMode: densityMode),
      themeMode: AppTheme.resolveThemeMode(settings?.uiThemeMode ?? 'system'),
      locale: AppStrings.localeFromLanguageCode(settings?.uiLanguageCode),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: AppStrings.localizationsDelegates,
      builder: (context, child) => AppZoomHost(
        child: child ?? const SizedBox.shrink(),
      ),
      home:
          environment.dataBackend == DataBackend.sqlite
              ? const SecurityGate()
              : const ReferenceSliceScreen(),
      onGenerateRoute:
          environment.dataBackend == DataBackend.supabase
              ? _generateReferenceRoute
              : null,
    );
  }

  Route<void>? _generateReferenceRoute(RouteSettings settings) {
    final propertyId = referencePropertyIdFromRoute(settings.name);
    if (settings.name == referencePropertiesRoute || propertyId != null) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => ReferenceSliceScreen(initialPropertyId: propertyId),
      );
    }
    return null;
  }
}
