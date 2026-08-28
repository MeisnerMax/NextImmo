import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_environment.dart';
import 'ui/i18n/app_strings.dart';
import 'ui/navigation/app_navigation.dart';
import 'ui/screens/security/supabase_security_gate.dart';
import 'ui/theme/app_theme.dart';
import 'ui/zoom/app_zoom.dart';

class NexImmoApp extends ConsumerWidget {
  const NexImmoApp({super.key, required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Theme, density and locale used to come from the locally persisted
    // settings row, which only ever existed in the SQLite runtime. The cloud
    // runtime already resolved to these defaults because it never read that
    // row, so removing the branch changes nothing a user sees. Making them
    // cloud-persisted is its own increment.
    final densityMode = AppTheme.resolveDensityMode('comfort');

    return MaterialApp(
      title: 'NexImmo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(densityMode: densityMode),
      darkTheme: AppTheme.dark(densityMode: densityMode),
      themeMode: AppTheme.resolveThemeMode('dark'),
      locale: AppStrings.localeFromLanguageCode(null),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: AppStrings.localizationsDelegates,
      builder:
          (context, child) =>
              AppZoomHost(child: child ?? const SizedBox.shrink()),
      onGenerateRoute: _generateCloudRoute,
      onGenerateInitialRoutes: _generateCloudInitialRoutes,
    );
  }

  List<Route<void>> _generateCloudInitialRoutes(String initialRoute) {
    final route = _generateCloudRoute(RouteSettings(name: initialRoute));
    if (route != null) {
      return <Route<void>>[route];
    }
    return <Route<void>>[
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/'),
        builder:
            (_) => const SupabaseSecurityGate(
              // Foundation §2: land on the working properties page until the
              // dashboard is cloud-ready (P2-D09).
              routeTarget: CloudRouteTarget.landing,
            ),
      ),
    ];
  }

  Route<void>? _generateCloudRoute(RouteSettings settings) {
    final target = cloudRouteTargetFromName(settings.name);
    return target == null
        ? null
        : MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => SupabaseSecurityGate(routeTarget: target),
        );
  }
}
