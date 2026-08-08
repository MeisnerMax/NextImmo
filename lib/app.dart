import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_environment.dart';
import 'features/reference_slice/presentation/reference_members_screen.dart';
import 'features/reference_slice/presentation/reference_slice_screen.dart';
import 'ui/i18n/app_strings.dart';
import 'ui/navigation/app_navigation.dart';
import 'ui/screens/docs/compliance_dashboard_screen.dart';
import 'ui/screens/docs/documents_workspace_panel.dart';
import 'ui/screens/parties/parties_screen.dart';
import 'ui/screens/property_detail/property_documents_panel.dart';
import 'ui/screens/security/security_gate.dart';
import 'ui/shell/cloud_app_scaffold.dart';
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
      themeMode: AppTheme.resolveThemeMode(settings?.uiThemeMode ?? 'dark'),
      locale: AppStrings.localeFromLanguageCode(settings?.uiLanguageCode),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: AppStrings.localizationsDelegates,
      builder:
          (context, child) =>
              AppZoomHost(child: child ?? const SizedBox.shrink()),
      home:
          environment.dataBackend == DataBackend.sqlite
              ? const SecurityGate()
              : null,
      onGenerateRoute:
          environment.dataBackend == DataBackend.supabase
              ? _generateReferenceRoute
              : null,
      onGenerateInitialRoutes:
          environment.dataBackend == DataBackend.supabase
              ? _generateReferenceInitialRoutes
              : null,
    );
  }

  List<Route<void>> _generateReferenceInitialRoutes(String initialRoute) {
    final route = _generateReferenceRoute(RouteSettings(name: initialRoute));
    if (route != null) {
      return <Route<void>>[route];
    }
    return <Route<void>>[
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: referencePropertiesRoute),
        builder:
            (_) => const CloudAppScaffold(
              activeRoute: referencePropertiesRoute,
              child: ReferenceSliceScreen(),
            ),
      ),
    ];
  }

  Route<void>? _generateReferenceRoute(RouteSettings settings) {
    if (settings.name == partiesRoute) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder:
            (_) => CloudAppScaffold(
              activeRoute: settings.name,
              child: const Scaffold(body: SafeArea(child: PartiesScreen())),
            ),
      );
    }
    if (settings.name == complianceRoute) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder:
            (context) => CloudAppScaffold(
              activeRoute: settings.name,
              child: Scaffold(
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: ComplianceDashboardScreen(
                      // A finding leads to the object's documents, which in cloud
                      // mode is its own additive route.
                      onOpenRequirement:
                          (requirement) => Navigator.of(context).pushNamed(
                            propertyDocumentsRouteFor(requirement.entityId),
                          ),
                    ),
                  ),
                ),
              ),
            ),
      );
    }
    if (settings.name == documentsWorkspaceRoute) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder:
            (_) => CloudAppScaffold(
              activeRoute: settings.name,
              child: const Scaffold(
                body: SafeArea(child: DocumentsWorkspacePanel()),
              ),
            ),
      );
    }
    final documentsPropertyId = propertyDocumentsPropertyIdFromRoute(
      settings.name,
    );
    if (documentsPropertyId != null) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder:
            (_) => CloudAppScaffold(
              activeRoute: settings.name,
              child: Scaffold(
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: PropertyDocumentsPanel(
                      propertyId: documentsPropertyId,
                    ),
                  ),
                ),
              ),
            ),
      );
    }
    if (settings.name == referenceMembersRoute) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder:
            (_) => CloudAppScaffold(
              activeRoute: settings.name,
              child: const ReferenceMembersScreen(),
            ),
      );
    }
    final propertyId = referencePropertyIdFromRoute(settings.name);
    if (settings.name == referencePropertiesRoute || propertyId != null) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder:
            (_) => CloudAppScaffold(
              activeRoute: settings.name,
              child: ReferenceSliceScreen(initialPropertyId: propertyId),
            ),
      );
    }
    return null;
  }
}
