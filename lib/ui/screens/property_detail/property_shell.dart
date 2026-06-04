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
import 'property_audit_screen.dart';
import 'property_documents_screen.dart';
import 'property_tasks_screen.dart';
import 'rent_roll_screen.dart';
import 'reports_screen.dart';
import 'scenario_versions_screen.dart';
import 'scenarios_screen.dart';
import 'tenants_screen.dart';
import 'units_screen.dart';

class PropertyShell extends ConsumerWidget {
  const PropertyShell({super.key});

  static const Color _assetCanvas = Color(0xFF0F172A);
  static const Color _assetSidebar = Color(0xFF101415);
  static const Color _assetPanel = Color(0xFF1E293B);
  static const Color _assetPanelHigh = Color(0xFF263244);
  static const Color _assetBorder = Color(0x33475569);
  static const Color _assetText = Color(0xFFE0E3E5);
  static const Color _assetMuted = Color(0xFFC6C6CD);
  static const Color _assetAccent = Color(0xFF2DD4BF);

  static const Set<PropertyDetailPage> _workflowMenuPages =
      <PropertyDetailPage>{
        PropertyDetailPage.overview,
        PropertyDetailPage.operationsOverview,
        PropertyDetailPage.rentRoll,
        PropertyDetailPage.inputs,
        PropertyDetailPage.analysis,
        PropertyDetailPage.documents,
        PropertyDetailPage.reports,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return scenariosAsync.when(
      data: (scenarios) {
        final activeScenarioId = _resolveScenarioSelection(
          ref: ref,
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
            color: _assetCanvas,
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
                  ref: ref,
                  scenarios: scenarios,
                  selectedScenarioId: activeScenarioId,
                ),
              ),
              plainHeader: true,
              fullPageScroll: selectedPage == PropertyDetailPage.overview,
              pagePadding: AppSpacing.xl,
              headerActions: _propertyHeaderActions(context: context, ref: ref),
              navigation: _propertyNavigation(
                context: context,
                ref: ref,
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
      brightness: Brightness.dark,
      primary: _assetAccent,
      secondary: const Color(0xFFBCC7DE),
      surface: _assetPanel,
      surfaceContainerHighest: _assetPanelHigh,
      onSurface: _assetText,
      onPrimary: const Color(0xFF003731),
      outline: _assetBorder,
      error: const Color(0xFFFB7185),
    );
    final densityConfig = base.extension<AppDensityConfig>();
    final extensions = <ThemeExtension<dynamic>>[
      if (densityConfig != null) densityConfig,
      const AppSemanticColors(
        success: _assetAccent,
        warning: Color(0xFFFACC15),
        error: Color(0xFFFB7185),
        info: Color(0xFF93C5FD),
        border: _assetBorder,
        surfaceAlt: _assetPanelHigh,
        textSecondary: _assetMuted,
      ),
    ];
    return base.copyWith(
      colorScheme: colors,
      scaffoldBackgroundColor: _assetCanvas,
      dividerColor: _assetBorder,
      textTheme: base.textTheme.apply(
        bodyColor: _assetText,
        displayColor: _assetText,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: _assetPanel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          side: const BorderSide(color: _assetBorder),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _assetText,
          side: const BorderSide(color: Color(0xFF475569)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          ),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: _assetPanel,
        textStyle: TextStyle(color: _assetText),
      ),
      extensions: extensions,
    );
  }

  Widget _propertyHeaderActions({
    required BuildContext context,
    required WidgetRef ref,
  }) {
    final actions = <({IconData icon, String label, PropertyDetailPage page})>[
      (
        icon: Icons.edit_outlined,
        label: 'Edit Master Data',
        page: PropertyDetailPage.overview,
      ),
      (
        icon: Icons.tune_outlined,
        label: 'Edit Valuation',
        page: PropertyDetailPage.inputs,
      ),
      (
        icon: Icons.analytics_outlined,
        label: 'Analysis',
        page: PropertyDetailPage.analysis,
      ),
      (
        icon: Icons.apartment_outlined,
        label: 'Rent Management',
        page: PropertyDetailPage.rentRoll,
      ),
      (
        icon: Icons.add_task_outlined,
        label: 'Task',
        page: PropertyDetailPage.tasks,
      ),
      (
        icon: Icons.note_add_outlined,
        label: 'Document',
        page: PropertyDetailPage.documents,
      ),
      (
        icon: Icons.request_quote_outlined,
        label: 'Check Budget',
        page: PropertyDetailPage.budgetVsActual,
      ),
      (
        icon: Icons.summarize_outlined,
        label: 'Report',
        page: PropertyDetailPage.reports,
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final action in actions)
          OutlinedButton.icon(
            onPressed:
                () =>
                    ref.read(propertyDetailPageProvider.notifier).state =
                        action.page,
            icon: Icon(action.icon, size: 16),
            label: Text(context.strings.text(action.label)),
          ),
        PopupMenuButton<PropertyDetailPage>(
          onSelected:
              (page) =>
                  ref.read(propertyDetailPageProvider.notifier).state = page,
          itemBuilder:
              (context) => [
                _propertyActionMenuItem(context, PropertyDetailPage.scenarios),
                _propertyActionMenuItem(context, PropertyDetailPage.comps),
                _propertyActionMenuItem(context, PropertyDetailPage.offer),
                _propertyActionMenuItem(context, PropertyDetailPage.criteria),
                _propertyActionMenuItem(context, PropertyDetailPage.versions),
                _propertyActionMenuItem(context, PropertyDetailPage.covenants),
                _propertyActionMenuItem(context, PropertyDetailPage.audit),
                _propertyActionMenuItem(context, PropertyDetailPage.alerts),
              ],
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: context.semanticColors.border),
              borderRadius: BorderRadius.circular(AppRadiusTokens.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.more_horiz, size: 16),
                const SizedBox(width: 8),
                Text(context.strings.text('More')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  PopupMenuItem<PropertyDetailPage> _propertyActionMenuItem(
    BuildContext context,
    PropertyDetailPage page,
  ) {
    return PopupMenuItem<PropertyDetailPage>(
      value: page,
      child: Text(context.strings.text(propertyDestinationForPage(page).label)),
    );
  }

  String? _resolveScenarioSelection({
    required WidgetRef ref,
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

  Widget _propertyNavigation({
    required BuildContext context,
    required WidgetRef ref,
    required PropertyDetailPage selectedPage,
  }) {
    final zone = context.desktopLayoutZone;
    final sections = _visibleNavigationSections(selectedPage);
    if (zone == AppDesktopLayoutZone.narrow) {
      return _buildNarrowNavigation(
        context: context,
        ref: ref,
        selectedPage: selectedPage,
        sections: sections,
      );
    }
    final compact = zone == AppDesktopLayoutZone.medium;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _assetSidebar,
        border: Border.all(color: _assetBorder),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.component),
        children:
            compact
                ? sections
                    .map(
                      (section) => _buildCompactSection(
                        context: context,
                        ref: ref,
                        section: section,
                        selectedPage: selectedPage,
                      ),
                    )
                    .toList(growable: false)
                : sections
                    .expand(
                      (section) => <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                          child: Text(
                            context.strings.text(section.title),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: _assetMuted),
                          ),
                        ),
                        ...section.items.map(
                          (item) => _buildNavTile(
                            context: context,
                            ref: ref,
                            item: item,
                            selectedPage: selectedPage,
                          ),
                        ),
                      ],
                    )
                    .toList(growable: false),
      ),
    );
  }

  Widget _buildNarrowNavigation({
    required BuildContext context,
    required WidgetRef ref,
    required PropertyDetailPage selectedPage,
    required List<PropertyNavigationSection> sections,
  }) {
    final selectedSection = propertySectionForPage(selectedPage);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _assetSidebar,
        border: Border.all(color: _assetBorder),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.component),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.strings.text('Property Navigation'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${context.strings.text(selectedSection.title)} / ${context.strings.text(propertyDestinationForPage(selectedPage).label)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.semanticColors.textSecondary,
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
    return propertyNavigationSections
        .map((section) {
          final visibleItems =
              section.items
                  .where((item) => _workflowMenuPages.contains(item.page))
                  .toList(growable: false);
          return PropertyNavigationSection(
            title: section.title,
            routeKey: section.routeKey,
            items: visibleItems,
          );
        })
        .where((section) => section.items.isNotEmpty)
        .toList(growable: false);
  }

  bool _menuContainsPage(
    List<PropertyNavigationSection> sections,
    PropertyDetailPage page,
  ) {
    return sections.any(
      (section) => section.items.any((item) => item.page == page),
    );
  }

  Widget _buildCompactSection({
    required BuildContext context,
    required WidgetRef ref,
    required PropertyNavigationSection section,
    required PropertyDetailPage selectedPage,
  }) {
    final expanded = section.items.any((item) => item.page == selectedPage);
    return ExpansionTile(
      initiallyExpanded: expanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(
        context.strings.text(section.title),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: _assetText,
        ),
      ),
      children: section.items
          .map(
            (item) => _buildNavTile(
              context: context,
              ref: ref,
              item: item,
              selectedPage: selectedPage,
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildNavTile({
    required BuildContext context,
    required WidgetRef ref,
    required PropertyNavigationDestination item,
    required PropertyDetailPage selectedPage,
  }) {
    final selected = item.page == selectedPage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? _assetPanelHigh : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? _assetAccent : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            _iconForPropertyPage(item.page),
            size: 20,
            color: selected ? _assetAccent : _assetMuted,
          ),
          title: Text(
            context.strings.text(item.label),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? _assetText : _assetMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap:
              () =>
                  ref.read(propertyDetailPageProvider.notifier).state =
                      item.page,
        ),
      ),
    );
  }

  IconData _iconForPropertyPage(PropertyDetailPage page) {
    switch (page) {
      case PropertyDetailPage.overview:
        return Icons.dashboard_outlined;
      case PropertyDetailPage.operationsOverview:
        return Icons.business_center_outlined;
      case PropertyDetailPage.rentRoll:
        return Icons.apartment_outlined;
      case PropertyDetailPage.inputs:
        return Icons.account_balance_wallet_outlined;
      case PropertyDetailPage.analysis:
        return Icons.analytics_outlined;
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
    required WidgetRef ref,
    required List<ScenarioRecord> scenarios,
    required String? selectedScenarioId,
  }) {
    final zone = context.desktopLayoutZone;
    final selected =
        scenarios.any((scenario) => scenario.id == selectedScenarioId)
            ? selectedScenarioId
            : (scenarios.isNotEmpty ? scenarios.first.id : null);
    if (selected == null) {
      return Text(context.strings.text('Create or select a scenario'));
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
          context.strings.text(
            'Create or select a scenario to open this section.',
          ),
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
        return PropertyAuditScreen(propertyId: propertyId);
      case PropertyDetailPage.documents:
        return PropertyDocumentsScreen(propertyId: propertyId);
      case PropertyDetailPage.reports:
        return ReportsScreen(propertyId: propertyId, scenarioId: scenarioId!);
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
