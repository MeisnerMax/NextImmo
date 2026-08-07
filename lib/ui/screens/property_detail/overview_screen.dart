import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/property.dart';
import '../../state/analysis_state.dart';
import '../../state/app_state.dart';
import '../../state/property_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/warnings_panel.dart';
import 'overview/overview_charts.dart';
import 'overview/overview_edit_property_dialog.dart';
import 'overview/overview_metric_grid.dart';
import 'overview/overview_onboarding_card.dart';
import 'overview/overview_section_states.dart';
import 'overview/overview_snapshot_section.dart';
import 'overview/overview_view_model.dart';
import 'overview/overview_workflow_pipeline.dart';

/// Overview screen of the property detail workspace (SCR-011, BIG-010 split):
/// slim orchestration over the section widgets in `overview/`. Sections
/// resolve independently (skeleton per section while loading, scoped error
/// with retry per section) — never a full-page spinner. Desktop renders two
/// columns (metrics + snapshots left, charts right); tablet/phone stack.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({
    super.key,
    required this.propertyId,
    required this.scenarioId,
    this.scrollable = true,
  });

  final String propertyId;
  final String scenarioId;
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisAsync = ref.watch(
      scenarioAnalysisControllerProvider(scenarioId),
    );
    final properties = ref.watch(propertiesControllerProvider).valueOrNull;
    final property = _findProperty(properties, propertyId);
    final activePage = ref.watch(propertyDetailPageProvider);

    void navigateTo(PropertyDetailPage page) {
      ref.read(propertyDetailPageProvider.notifier).state = page;
    }

    void retryAnalysis() {
      ref.invalidate(scenarioAnalysisControllerProvider(scenarioId));
    }

    Widget analysisSection({
      required String errorTitle,
      required Widget skeleton,
      required Widget Function(ScenarioAnalysisState state) builder,
    }) {
      return analysisAsync.when(
        data: builder,
        loading: () => skeleton,
        error: (_, __) => OverviewSectionError(
          title: errorTitle,
          onRetry: retryAnalysis,
        ),
      );
    }

    final analysisState = analysisAsync.valueOrNull;
    final summary = analysisState == null
        ? null
        : OverviewDealSummary.fromState(
            state: analysisState,
            property: property,
          );
    final showOnboarding =
        summary != null && overviewShouldShowOnboarding(summary, property);

    final pipelineSection = analysisSection(
      errorTitle: 'Workflow konnte nicht geladen werden',
      skeleton: const OverviewSectionSkeleton(
        key: ValueKey<String>('overview_pipeline_skeleton'),
        height: 96,
      ),
      builder: (state) => OverviewWorkflowPipeline(
        property: property,
        summary: summary!,
        metrics: state.analysis.metrics,
        activePage: activePage,
        onSelect: navigateTo,
      ),
    );

    final metricSection = analysisSection(
      errorTitle: 'Kennzahlen konnten nicht geladen werden',
      skeleton: const OverviewMetricGridSkeleton(
        key: ValueKey<String>('overview_metric_skeleton'),
      ),
      builder: (state) => OverviewMetricGrid(
        metrics: state.analysis.metrics,
        onOpenAnalysis: () => navigateTo(PropertyDetailPage.analysis),
      ),
    );

    final snapshotSection = analysisSection(
      errorTitle: 'Stammdaten konnten nicht geladen werden',
      skeleton: const OverviewSectionSkeleton(
        key: ValueKey<String>('overview_snapshot_skeleton'),
        height: 220,
      ),
      builder: (state) => OverviewSnapshotSection(
        property: property,
        summary: summary!,
        onEdit: () {
          final current = property;
          if (current == null) {
            return;
          }
          showOverviewEditPropertyDialog(
            context: context,
            ref: ref,
            property: current,
          );
        },
      ),
    );

    final cashflowChartSection = analysisSection(
      errorTitle: 'Cashflow-Projektion konnte nicht geladen werden',
      skeleton: const OverviewSectionSkeleton(
        key: ValueKey<String>('overview_cashflow_chart_skeleton'),
        height: 260,
      ),
      builder: (state) => OverviewCashflowChart(state: state),
    );

    final rentChartSection = analysisSection(
      errorTitle: 'Mietprojektion konnte nicht geladen werden',
      skeleton: const OverviewSectionSkeleton(
        key: ValueKey<String>('overview_rent_chart_skeleton'),
        height: 260,
      ),
      builder: (state) => OverviewRentProjectionChart(
        state: state,
        monthlyRentStart: summary!.monthlyRent,
      ),
    );

    final coverImage = _buildCoverImage(ref);

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1080;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            coverImage,
            if (showOnboarding) ...[
              OverviewOnboardingCard(onNavigate: navigateTo),
              const SizedBox(height: AppSpacing.component),
            ],
            pipelineSection,
            const SizedBox(height: AppSpacing.component),
            if (wide)
              Row(
                key: const ValueKey<String>('overview_wide_layout'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        metricSection,
                        const SizedBox(height: AppSpacing.component),
                        snapshotSection,
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.component),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        cashflowChartSection,
                        const SizedBox(height: AppSpacing.component),
                        rentChartSection,
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                key: const ValueKey<String>('overview_stacked_layout'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  metricSection,
                  const SizedBox(height: AppSpacing.component),
                  snapshotSection,
                  const SizedBox(height: AppSpacing.component),
                  cashflowChartSection,
                  const SizedBox(height: AppSpacing.component),
                  rentChartSection,
                ],
              ),
            if (analysisState != null) ...[
              const SizedBox(height: AppSpacing.component),
              WarningsPanel(warnings: analysisState.analysis.warnings),
            ],
          ],
        );
      },
    );

    if (!scrollable) {
      return content;
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: SingleChildScrollView(child: content),
    );
  }

  Widget _buildCoverImage(WidgetRef ref) {
    final titleImageAsync = ref.watch(propertyTitleImageProvider(propertyId));
    return titleImageAsync.when(
      data: (path) {
        if (path == null) {
          return const SizedBox.shrink();
        }
        final file = File(path);
        if (!file.existsSync()) {
          return const SizedBox.shrink();
        }
        return Container(
          height: 220,
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: AppSpacing.component),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadiusTokens.md),
            image: DecorationImage(
              image: FileImage(file),
              fit: BoxFit.cover,
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  static PropertyRecord? _findProperty(
    List<PropertyRecord>? properties,
    String propertyId,
  ) {
    if (properties == null) {
      return null;
    }
    for (final property in properties) {
      if (property.id == propertyId) {
        return property;
      }
    }
    return null;
  }
}
