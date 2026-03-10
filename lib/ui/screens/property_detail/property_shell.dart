import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/scenario.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          page: selectedPage,
          propertyId: propertyId,
          scenarioId: activeScenarioId,
          scenarios: scenarios,
        );

        return DetailTemplate(
          title: propertyName,
          breadcrumbs: propertyBreadcrumbs(
            propertyName: propertyName,
            page: selectedPage,
          ),
          subtitle: '${section.title} / ${destination.label}',
          contextBar: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _scenarioSelector(
              context: context,
              ref: ref,
              scenarios: scenarios,
              selectedScenarioId: activeScenarioId,
            ),
          ),
          navigation: _propertyNavigation(
            context: context,
            ref: ref,
            selectedPage: selectedPage,
          ),
          content: detailContent,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
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
    if (zone == AppDesktopLayoutZone.narrow) {
      return _buildNarrowNavigation(
        context: context,
        ref: ref,
        selectedPage: selectedPage,
      );
    }
    final compact = zone == AppDesktopLayoutZone.medium;
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.component),
        children:
            compact
                ? propertyNavigationSections
                    .map(
                      (section) => _buildCompactSection(
                        context: context,
                        ref: ref,
                        section: section,
                        selectedPage: selectedPage,
                      ),
                    )
                    .toList(growable: false)
                : propertyNavigationSections
                    .expand(
                      (section) => <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                          child: Text(
                            section.title,
                            style: Theme.of(context).textTheme.labelMedium,
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
  }) {
    final selectedSection = propertySectionForPage(selectedPage);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.component),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Property Navigation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${selectedSection.title} / ${propertyDestinationForPage(selectedPage).label}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.component),
            DropdownButtonFormField<PropertyDetailPage>(
              value: selectedPage,
              isExpanded: true,
              items: propertyNavigationSections
                  .expand(
                    (section) => section.items.map(
                      (item) => DropdownMenuItem<PropertyDetailPage>(
                        value: item.page,
                        child: Text('${section.title} / ${item.label}'),
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  ref.read(propertyDetailPageProvider.notifier).state = value;
                }
              },
              decoration: const InputDecoration(labelText: 'Section'),
            ),
          ],
        ),
      ),
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
        section.title,
        style: Theme.of(context).textTheme.titleMedium,
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
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        ),
        selected: selected,
        selectedTileColor: const Color(0xFFEAF1F8),
        title: Text(item.label),
        onTap:
            () =>
                ref.read(propertyDetailPageProvider.notifier).state = item.page,
      ),
    );
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
      return const Text('Create or select a scenario');
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
      decoration: const InputDecoration(labelText: 'Scenario'),
    );
  }

  Widget _buildDetailContent({
    required PropertyDetailPage page,
    required String propertyId,
    required String? scenarioId,
    required List<ScenarioRecord> scenarios,
  }) {
    if (propertyPageRequiresScenario(page) && scenarioId == null) {
      return const Center(
        child: Text('Create or select a scenario to open this section.'),
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
        return OverviewScreen(propertyId: propertyId, scenarioId: scenarioId!);
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
