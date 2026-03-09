import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/scenario.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_empty_state.dart';
import '../../../state/analysis_state.dart';
import '../../../state/app_state.dart';
import '../../../state/property_state.dart';
import '../../../state/scenario_state.dart';
import '../../../theme/app_theme.dart';
import '../../property_detail/analysis_screen.dart';
import '../../property_detail/budget_vs_actual_screen.dart';
import '../../property_detail/comps_screen.dart';
import '../../property_detail/covenants_screen.dart';
import '../../property_detail/criteria_check_screen.dart';
import '../../property_detail/inputs_screen.dart';
import '../../property_detail/leases_screen.dart';
import '../../property_detail/maintenance_screen.dart';
import '../../property_detail/operations_alerts_screen.dart';
import '../../property_detail/operations_overview_screen.dart';
import '../../property_detail/offer_screen.dart';
import '../../property_detail/overview_screen.dart';
import '../../property_detail/property_audit_screen.dart';
import '../../property_detail/rent_roll_screen.dart';
import '../../property_detail/reports_screen.dart';
import '../../property_detail/scenario_versions_screen.dart';
import '../../property_detail/scenarios_screen.dart';
import '../../property_detail/tenants_screen.dart';
import '../../property_detail/units_screen.dart';

class PropertyShellV2 extends ConsumerWidget {
  const PropertyShellV2({super.key});

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
        return 'Property Detail';
      },
      orElse: () => 'Property Detail',
    );

    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: scenariosAsync.when(
        data: (scenarios) {
          if (scenarios.isNotEmpty && selectedScenarioId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(selectedScenarioIdProvider.notifier).state =
                  scenarios.first.id;
            });
          }
          final detailContent =
              selectedScenarioId == null
                  ? const NxEmptyState(
                    title: 'No scenario selected',
                    description: 'Create or select a scenario to continue.',
                    icon: Icons.timeline,
                  )
                  : _buildDetailPage(
                    page: selectedPage,
                    propertyId: propertyId,
                    scenarioId: selectedScenarioId,
                    scenarios: scenarios,
                  );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NxCard(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 980;
                    final breadcrumb = Text(
                      'Properties / $propertyName',
                      style: Theme.of(context).textTheme.titleMedium,
                    );
                    final selector = ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: _scenarioSelector(
                        ref: ref,
                        scenarios: scenarios,
                        selectedScenarioId: selectedScenarioId,
                      ),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          breadcrumb,
                          const SizedBox(height: AppSpacing.component),
                          selector,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: breadcrumb),
                        const SizedBox(width: AppSpacing.component),
                        selector,
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 980;
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 220,
                            child: _propertySidebar(
                              context: context,
                              ref: ref,
                              selectedPage: selectedPage,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.component),
                          Expanded(child: detailContent),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 260,
                          child: _propertySidebar(
                            context: context,
                            ref: ref,
                            selectedPage: selectedPage,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.component),
                        Expanded(child: detailContent),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _propertySidebar({
    required BuildContext context,
    required WidgetRef ref,
    required PropertyDetailPage selectedPage,
  }) {
    return NxCard(
      child: ListView(
        children: PropertyDetailPage.values
            .map(
              (page) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  selected: page == selectedPage,
                  selectedTileColor: const Color(0xFFEAF1F8),
                  title: Text(_label(page)),
                  onTap:
                      () =>
                          ref.read(propertyDetailPageProvider.notifier).state =
                              page,
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _scenarioSelector({
    required WidgetRef ref,
    required List<ScenarioRecord> scenarios,
    required String? selectedScenarioId,
  }) {
    final selected =
        scenarios.any((s) => s.id == selectedScenarioId)
            ? selectedScenarioId
            : (scenarios.isNotEmpty ? scenarios.first.id : null);
    if (selected == null) {
      return const Text('Create scenario');
    }
    if (scenarios.length <= 3) {
      return SegmentedButton<String>(
        segments: scenarios
            .map(
              (s) => ButtonSegment<String>(
                value: s.id,
                label: Text(s.name, overflow: TextOverflow.ellipsis),
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
          .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
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

  Widget _buildDetailPage({
    required PropertyDetailPage page,
    required String propertyId,
    required String scenarioId,
    required List<ScenarioRecord> scenarios,
  }) {
    switch (page) {
      case PropertyDetailPage.overview:
        return OverviewScreen(propertyId: propertyId, scenarioId: scenarioId);
      case PropertyDetailPage.inputs:
        return InputsScreen(scenarioId: scenarioId);
      case PropertyDetailPage.analysis:
        return AnalysisScreen(scenarioId: scenarioId);
      case PropertyDetailPage.comps:
        return CompsScreen(propertyId: propertyId, scenarioId: scenarioId);
      case PropertyDetailPage.criteria:
        return CriteriaCheckScreen(scenarioId: scenarioId);
      case PropertyDetailPage.offer:
        return OfferScreen(scenarioId: scenarioId);
      case PropertyDetailPage.scenarios:
        return ScenariosScreen(propertyId: propertyId, scenarios: scenarios);
      case PropertyDetailPage.versions:
        return ScenarioVersionsScreen(scenarioId: scenarioId);
      case PropertyDetailPage.audit:
        return PropertyAuditScreen(propertyId: propertyId);
      case PropertyDetailPage.reports:
        return ReportsScreen(propertyId: propertyId, scenarioId: scenarioId);
      case PropertyDetailPage.operationsOverview:
        return OperationsOverviewScreen(propertyId: propertyId);
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

  String _label(PropertyDetailPage page) {
    switch (page) {
      case PropertyDetailPage.overview:
        return 'Overview';
      case PropertyDetailPage.inputs:
        return 'Inputs';
      case PropertyDetailPage.analysis:
        return 'Analysis';
      case PropertyDetailPage.comps:
        return 'Comps';
      case PropertyDetailPage.criteria:
        return 'Criteria';
      case PropertyDetailPage.offer:
        return 'Offer';
      case PropertyDetailPage.scenarios:
        return 'Scenarios';
      case PropertyDetailPage.versions:
        return 'Versions';
      case PropertyDetailPage.audit:
        return 'Audit';
      case PropertyDetailPage.reports:
        return 'Reports';
      case PropertyDetailPage.operationsOverview:
        return 'Operations Overview';
      case PropertyDetailPage.units:
        return 'Units';
      case PropertyDetailPage.tenants:
        return 'Tenants';
      case PropertyDetailPage.leases:
        return 'Leases';
      case PropertyDetailPage.rentRoll:
        return 'Rent Roll';
      case PropertyDetailPage.alerts:
        return 'Operations Alerts';
      case PropertyDetailPage.budgetVsActual:
        return 'Budget vs Actual';
      case PropertyDetailPage.maintenance:
        return 'Maintenance';
      case PropertyDetailPage.covenants:
        return 'Covenants';
    }
  }
}
