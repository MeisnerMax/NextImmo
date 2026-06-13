import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/scenario.dart';
import '../../i18n/app_strings.dart';
import '../../navigation/app_navigation.dart';
import '../../state/analysis_state.dart';
import '../../state/app_state.dart';
import '../../state/property_state.dart';
import '../../state/scenario_state.dart';
import '../../templates/detail_template.dart';
import '../../theme/app_theme.dart';
import 'analysis_screen.dart';
import 'asset_workbook_screen.dart';
import 'budget_vs_actual_screen.dart';
import 'comps_screen.dart';
import 'covenants_screen.dart';
import 'criteria_check_screen.dart';
import 'inputs_screen.dart';
import 'leases_screen.dart';
import 'maintenance_screen.dart';
import 'operations_alerts_screen.dart';
import 'operations_overview_screen.dart';
import 'offer_screen.dart';
import 'overview_screen.dart';
import 'property_documents_screen.dart';
import 'property_tasks_screen.dart';
import 'rent_roll_screen.dart';
import 'scenario_versions_screen.dart';
import 'scenarios_screen.dart';
import 'tenants_screen.dart';
import 'units_screen.dart';

final _autoScenarioCreationInFlightProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

class PropertyShell extends ConsumerStatefulWidget {
  const PropertyShell({super.key});

  static const Color _assetCanvas = Color(0xFFF8FAFC);
  static const Color _assetSidebar = Color(0xFF0F172A);
  static const Color _assetPanel = Color(0xFFFFFFFF);
  static const Color _assetPanelHigh = Color(0xFFF1F5F9);
  static const Color _assetBorder = Color(0xFFE2E8F0);
  static const Color _assetText = Color(0xFF0F172A);
  static const Color _assetMuted = Color(0xFF64748B);
  static const Color _assetAccent = Color(0xFF2563EB);
  static const Color _assetMenuText = Color(0xFFEAF2FF);
  static const Color _assetMenuMuted = Color(0xFFBFD0EA);
  static const Color _assetMenuSelected = Color(0xFF1E293B);

  @override
  ConsumerState<PropertyShell> createState() => _PropertyShellState();
}

class _PropertyShellState extends ConsumerState<PropertyShell> {
  final Map<String, bool> _expanded = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final propertyId = ref.watch(selectedPropertyIdProvider);
    if (propertyId == null) {
      return const SizedBox.shrink();
    }

    final selectedPage = ref.watch(propertyDetailPageProvider);
    final selectedScenarioId = ref.watch(selectedScenarioIdProvider);
    final scenariosAsync = ref.watch(scenariosByPropertyProvider(propertyId));
    final propertiesAsync = ref.watch(propertiesControllerProvider);
    final propertyName = propertiesAsync.maybeWhen(
      data: (items) {
        for (final property in items) {
          if (property.id == propertyId) {
            return property.name;
          }
        }
        return propertyId;
      },
      orElse: () => propertyId,
    );
    final section = propertySectionForPage(selectedPage);
    final destination = propertyDestinationForPage(selectedPage);

    // Auto-expand active section
    _expanded[section.title] = true;

    return scenariosAsync.when(
      data: (scenarios) {
        if (scenarios.isEmpty) {
          _ensureBaseScenario(propertyId: propertyId);
        }
        final activeScenarioId = _resolveScenarioSelection(
          scenarios: scenarios,
          selectedScenarioId: selectedScenarioId,
        );
        final detailContent = _buildDetailContent(
          context: context,
          page: selectedPage,
          propertyId: propertyId,
          scenarioId: activeScenarioId,
          scenarios: scenarios,
        );

        return Theme(
          data: _propertyWorkspaceTheme(context),
          child: Container(
            color: PropertyShell._assetCanvas,
            child: DetailTemplate(
              title: propertyName,
              breadcrumbs: propertyBreadcrumbs(
                propertyName: propertyName,
                page: selectedPage,
              ).map(s.text).toList(growable: false),
              subtitle: '${s.text(section.title)} / ${s.text(destination.label)}',
              contextBar: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: _scenarioSelector(
                  context: context,
                  scenarios: scenarios,
                  selectedScenarioId: activeScenarioId,
                ),
              ),
              plainHeader: true,
              fullPageScroll: _usesFullPageScroll(selectedPage),
              pagePadding: AppSpacing.xl,
              navigation: _propertyNavigation(
                context: context,
                selectedPage: selectedPage,
              ),
              content: detailContent,
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (error, _) =>
              Center(child: Text(s.errorWithPrefix(s.text('Error'), error))),
    );
  }

  ThemeData _propertyWorkspaceTheme(BuildContext context) {
    final base = Theme.of(context);
    final colors = base.colorScheme.copyWith(
      brightness: Brightness.light,
      primary: PropertyShell._assetAccent,
      secondary: const Color(0xFF0F172A),
      surface: PropertyShell._assetPanel,
      surfaceContainerHighest: PropertyShell._assetPanelHigh,
      onSurface: PropertyShell._assetText,
      onPrimary: Colors.white,
      outline: PropertyShell._assetBorder,
      error: const Color(0xFFDC2626),
    );
    final densityConfig = base.extension<AppDensityConfig>();
    final extensions = <ThemeExtension<dynamic>>[
      if (densityConfig != null) densityConfig,
      const AppSemanticColors(
        success: Color(0xFF16A34A),
        warning: Color(0xFFD97706),
        error: Color(0xFFDC2626),
        info: PropertyShell._assetAccent,
        border: PropertyShell._assetBorder,
        surfaceAlt: PropertyShell._assetPanelHigh,
        textSecondary: PropertyShell._assetMuted,
      ),
    ];
    return base.copyWith(
      colorScheme: colors,
      scaffoldBackgroundColor: PropertyShell._assetCanvas,
      dividerColor: PropertyShell._assetBorder,
      textTheme: base.textTheme.apply(
        bodyColor: PropertyShell._assetText,
        displayColor: PropertyShell._assetText,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: PropertyShell._assetPanel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          side: const BorderSide(color: PropertyShell._assetBorder),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: PropertyShell._assetMuted),
        helperStyle: const TextStyle(color: PropertyShell._assetMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          borderSide: const BorderSide(color: PropertyShell._assetBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          borderSide: const BorderSide(color: PropertyShell._assetBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          borderSide: const BorderSide(color: PropertyShell._assetAccent),
        ),
      ),
      dataTableTheme: base.dataTableTheme.copyWith(
        headingTextStyle: const TextStyle(
          color: PropertyShell._assetMuted,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: const TextStyle(
          color: PropertyShell._assetText,
          fontWeight: FontWeight.w500,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: PropertyShell._assetPanelHigh,
        side: const BorderSide(color: PropertyShell._assetBorder),
        labelStyle: const TextStyle(
          color: PropertyShell._assetText,
          fontWeight: FontWeight.w600,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: PropertyShell._assetText,
          side: const BorderSide(color: PropertyShell._assetBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          ),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: Colors.white,
        textStyle: TextStyle(color: PropertyShell._assetText),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: PropertyShell._assetMuted),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        textColor: PropertyShell._assetText,
        iconColor: PropertyShell._assetMuted,
        selectedColor: PropertyShell._assetAccent,
        selectedTileColor: PropertyShell._assetPanelHigh,
      ),
      extensions: extensions,
    );
  }

  bool _usesFullPageScroll(PropertyDetailPage page) {
    return true;
  }

  String? _resolveScenarioSelection({
    required List<ScenarioRecord> scenarios,
    required String? selectedScenarioId,
  }) {
    if (scenarios.isEmpty) {
      if (selectedScenarioId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(selectedScenarioIdProvider.notifier).state = null;
        });
      }
      return null;
    }
    for (final scenario in scenarios) {
      if (scenario.id == selectedScenarioId) {
        return selectedScenarioId;
      }
    }
    final nextScenarioId = scenarios.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedScenarioIdProvider.notifier).state = nextScenarioId;
    });
    return nextScenarioId;
  }

  void _ensureBaseScenario({
    required String propertyId,
  }) {
    final inFlight = ref.read(_autoScenarioCreationInFlightProvider);
    if (inFlight.contains(propertyId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final current = ref.read(_autoScenarioCreationInFlightProvider);
      if (current.contains(propertyId)) {
        return;
      }
      ref.read(_autoScenarioCreationInFlightProvider.notifier).state =
          <String>{...current, propertyId};
      final scenario = await ref
          .read(scenariosByPropertyProvider(propertyId).notifier)
          .create(name: 'Basis Vermietung', strategyType: 'rental');
      if (scenario != null) {
        ref.read(selectedScenarioIdProvider.notifier).state = scenario.id;
      }
      final after = ref.read(_autoScenarioCreationInFlightProvider);
      ref.read(_autoScenarioCreationInFlightProvider.notifier).state =
          after.where((id) => id != propertyId).toSet();
    });
  }

  Widget _propertyNavigation({
    required BuildContext context,
    required PropertyDetailPage selectedPage,
  }) {
    final zone = context.desktopLayoutZone;
    final sections = _visibleNavigationSections(selectedPage);
    if (zone == AppDesktopLayoutZone.narrow) {
      return _buildNarrowNavigation(
        context: context,
        selectedPage: selectedPage,
        sections: sections,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PropertyShell._assetSidebar,
        border: Border.all(color: PropertyShell._assetBorder),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.component,
        ),
        children: sections
            .map(
              (section) => _buildAccordionSection(
                context: context,
                section: section,
                selectedPage: selectedPage,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildNarrowNavigation({
    required BuildContext context,
    required PropertyDetailPage selectedPage,
    required List<PropertyNavigationSection> sections,
  }) {
    final selectedSection = propertySectionForPage(selectedPage);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PropertyShell._assetSidebar,
        border: Border.all(color: PropertyShell._assetBorder),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.component),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.strings.text('Property Navigation'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: PropertyShell._assetMenuText,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${context.strings.text(selectedSection.title)} / ${context.strings.text(propertyDestinationForPage(selectedPage).label)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PropertyShell._assetMenuMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.component),
            DropdownButtonFormField<PropertyDetailPage>(
              value:
                  _menuContainsPage(sections, selectedPage)
                      ? selectedPage
                      : null,
              isExpanded: true,
              items: sections
                  .expand(
                    (section) => section.items.map(
                      (item) => DropdownMenuItem<PropertyDetailPage>(
                        value: item.page,
                        child: Text(
                          '${context.strings.text(section.title)} / ${context.strings.text(item.label)}',
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  ref.read(propertyDetailPageProvider.notifier).state = value;
                }
              },
              decoration: InputDecoration(
                labelText: context.strings.text('Section'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PropertyNavigationSection> _visibleNavigationSections(
    PropertyDetailPage selectedPage,
  ) {
    return propertyNavigationSections;
  }

  bool _menuContainsPage(
    List<PropertyNavigationSection> sections,
    PropertyDetailPage page,
  ) {
    return sections.any(
      (section) => section.items.any((item) => item.page == page),
    );
  }

  Widget _buildAccordionSection({
    required BuildContext context,
    required PropertyNavigationSection section,
    required PropertyDetailPage selectedPage,
  }) {
    final title = section.title;
    final expanded = _expanded[title] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _expanded[title] = !expanded;
            });
          },
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.strings.text(title).toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: PropertyShell._assetMenuMuted,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: PropertyShell._assetMenuMuted,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: [
              const SizedBox(height: 4),
              for (final item in section.items)
                _buildNavTile(
                  context: context,
                  item: item,
                  selectedPage: selectedPage,
                ),
              const SizedBox(height: 8),
            ],
          ),
          crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 140),
        ),
      ],
    );
  }

  Widget _buildNavTile({
    required BuildContext context,
    required PropertyNavigationDestination item,
    required PropertyDetailPage selectedPage,
  }) {
    final selected = item.page == selectedPage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: selected ? PropertyShell._assetMenuSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                _iconForPropertyPage(item.page),
                size: 20,
                color: selected ? Colors.white : PropertyShell._assetMenuMuted,
              ),
              title: Text(
                context.strings.text(item.label),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : PropertyShell._assetMenuMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                ref.read(propertyDetailPageProvider.notifier).state = item.page;
              },
            ),
          ),
          if (selected)
            Positioned(
              left: 0,
              top: 8,
              bottom: 8,
              width: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconForPropertyPage(PropertyDetailPage page) {
    switch (page) {
      case PropertyDetailPage.overview:
        return Icons.dashboard_outlined;
      case PropertyDetailPage.audit:
        return Icons.history_outlined;
      case PropertyDetailPage.operationsOverview:
        return Icons.business_center_outlined;
      case PropertyDetailPage.units:
        return Icons.door_front_door_outlined;
      case PropertyDetailPage.tenants:
        return Icons.people_outline;
      case PropertyDetailPage.leases:
        return Icons.description_outlined;
      case PropertyDetailPage.rentRoll:
        return Icons.apartment_outlined;
      case PropertyDetailPage.assetWorkbook:
        return Icons.request_quote_outlined;
      case PropertyDetailPage.budgetVsActual:
        return Icons.account_balance_outlined;
      case PropertyDetailPage.tasks:
        return Icons.add_task_outlined;
      case PropertyDetailPage.maintenance:
        return Icons.build_outlined;
      case PropertyDetailPage.alerts:
        return Icons.notifications_active_outlined;
      case PropertyDetailPage.scenarios:
        return Icons.route_outlined;
      case PropertyDetailPage.inputs:
        return Icons.account_balance_wallet_outlined;
      case PropertyDetailPage.analysis:
        return Icons.analytics_outlined;
      case PropertyDetailPage.comps:
        return Icons.compare_arrows_outlined;
      case PropertyDetailPage.offer:
        return Icons.local_offer_outlined;
      case PropertyDetailPage.criteria:
        return Icons.rule_outlined;
      case PropertyDetailPage.versions:
        return Icons.timeline_outlined;
      case PropertyDetailPage.covenants:
        return Icons.verified_user_outlined;
      case PropertyDetailPage.documents:
        return Icons.folder_open_outlined;
      case PropertyDetailPage.reports:
        return Icons.summarize_outlined;
      default:
        return Icons.arrow_right_alt;
    }
  }

  Widget _scenarioSelector({
    required BuildContext context,
    required List<ScenarioRecord> scenarios,
    required String? selectedScenarioId,
  }) {
    final zone = context.desktopLayoutZone;
    final selected =
        scenarios.any((scenario) => scenario.id == selectedScenarioId)
            ? selectedScenarioId
            : (scenarios.isNotEmpty ? scenarios.first.id : null);
    if (selected == null) {
      return Text(context.strings.text('Basisszenario wird erstellt...'));
    }
    if (scenarios.length <= 3 && zone != AppDesktopLayoutZone.narrow) {
      return SegmentedButton<String>(
        segments: scenarios
            .map(
              (scenario) => ButtonSegment<String>(
                value: scenario.id,
                label: Text(scenario.name, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(growable: false),
        selected: <String>{selected},
        onSelectionChanged: (selection) {
          final next = selection.isEmpty ? null : selection.first;
          final previousScenarioId = selectedScenarioId;
          if (previousScenarioId != null) {
            ref
                .read(
                  scenarioAnalysisControllerProvider(
                    previousScenarioId,
                  ).notifier,
                )
                .flushPendingSave();
          }
          ref.read(selectedScenarioIdProvider.notifier).state = next;
        },
      );
    }
    return DropdownButtonFormField<String>(
      value: selected,
      items: scenarios
          .map(
            (scenario) => DropdownMenuItem<String>(
              value: scenario.id,
              child: Text(scenario.name),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        final previousScenarioId = selectedScenarioId;
        if (previousScenarioId != null) {
          ref
              .read(
                scenarioAnalysisControllerProvider(previousScenarioId).notifier,
              )
              .flushPendingSave();
        }
        ref.read(selectedScenarioIdProvider.notifier).state = value;
      },
      decoration: InputDecoration(labelText: context.strings.text('Scenario')),
    );
  }

  Widget _buildDetailContent({
    required BuildContext context,
    required PropertyDetailPage page,
    required String propertyId,
    required String? scenarioId,
    required List<ScenarioRecord> scenarios,
  }) {
    if (propertyPageRequiresScenario(page) && scenarioId == null) {
      return Center(
        child: Text(
          context.strings.text('Basisszenario wird erstellt...'),
        ),
      );
    }
    return _buildDetailPage(
      page: page,
      propertyId: propertyId,
      scenarioId: scenarioId,
      scenarios: scenarios,
    );
  }

  Widget _buildDetailPage({
    required PropertyDetailPage page,
    required String propertyId,
    required String? scenarioId,
    required List<ScenarioRecord> scenarios,
  }) {
    switch (page) {
      case PropertyDetailPage.overview:
        return OverviewScreen(
          propertyId: propertyId,
          scenarioId: scenarioId!,
          scrollable: false,
        );
      case PropertyDetailPage.inputs:
        return InputsScreen(scenarioId: scenarioId!);
      case PropertyDetailPage.analysis:
        return AnalysisScreen(scenarioId: scenarioId!);
      case PropertyDetailPage.comps:
        return CompsScreen(propertyId: propertyId, scenarioId: scenarioId!);
      case PropertyDetailPage.criteria:
        return CriteriaCheckScreen(scenarioId: scenarioId!);
      case PropertyDetailPage.offer:
        return OfferScreen(scenarioId: scenarioId!);
      case PropertyDetailPage.scenarios:
        return ScenariosScreen(propertyId: propertyId, scenarios: scenarios);
      case PropertyDetailPage.versions:
        return ScenarioVersionsScreen(scenarioId: scenarioId!);
      case PropertyDetailPage.audit:
        return PropertyDocumentsScreen(
          propertyId: propertyId,
          scenarioId: scenarioId,
          initialIndex: 1,
        );
      case PropertyDetailPage.documents:
        return PropertyDocumentsScreen(
          propertyId: propertyId,
          scenarioId: scenarioId,
          initialIndex: 0,
        );
      case PropertyDetailPage.reports:
        return PropertyDocumentsScreen(
          propertyId: propertyId,
          scenarioId: scenarioId,
          initialIndex: 2,
        );
      case PropertyDetailPage.operationsOverview:
        return OperationsOverviewScreen(propertyId: propertyId);
      case PropertyDetailPage.tasks:
        return PropertyTasksScreen(propertyId: propertyId);
      case PropertyDetailPage.units:
        return UnitsScreen(propertyId: propertyId);
      case PropertyDetailPage.tenants:
        return TenantsScreen(propertyId: propertyId);
      case PropertyDetailPage.leases:
        return LeasesScreen(propertyId: propertyId);
      case PropertyDetailPage.rentRoll:
        return RentRollScreen(propertyId: propertyId);
      case PropertyDetailPage.assetWorkbook:
        return AssetWorkbookScreen(propertyId: propertyId);
      case PropertyDetailPage.alerts:
        return OperationsAlertsScreen(propertyId: propertyId);
      case PropertyDetailPage.budgetVsActual:
        return BudgetVsActualScreen(propertyId: propertyId);
      case PropertyDetailPage.maintenance:
        return PropertyMaintenanceScreen(propertyId: propertyId);
      case PropertyDetailPage.covenants:
        return CovenantsScreen(propertyId: propertyId);
    }
  }
}

