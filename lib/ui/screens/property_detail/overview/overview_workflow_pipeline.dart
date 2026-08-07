import 'package:flutter/material.dart';

import '../../../../core/models/analysis_result.dart';
import '../../../../core/models/property.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_section_header.dart';
import '../../../i18n/app_strings.dart';
import '../../../state/app_state.dart';
import '../../../theme/app_theme.dart';
import 'overview_view_model.dart';

/// Workflow pipeline of the overview screen (SCR-011 section 2): every stage
/// navigates directly to its source module. Data derivation and navigation
/// targets are unchanged from the legacy screen — only the presentation moved
/// to tokens and `NxCard`/`NxSectionHeader`.
class OverviewWorkflowPipeline extends StatelessWidget {
  const OverviewWorkflowPipeline({
    super.key,
    required this.property,
    required this.summary,
    required this.metrics,
    required this.activePage,
    required this.onSelect,
  });

  final PropertyRecord? property;
  final OverviewDealSummary summary;
  final AnalysisMetrics metrics;
  final PropertyDetailPage activePage;
  final ValueChanged<PropertyDetailPage> onSelect;

  static int activeStepIndex(PropertyDetailPage page) {
    switch (page) {
      case PropertyDetailPage.overview:
      case PropertyDetailPage.audit:
        return 0;
      case PropertyDetailPage.units:
      case PropertyDetailPage.tenants:
      case PropertyDetailPage.leases:
      case PropertyDetailPage.rentRoll:
      case PropertyDetailPage.saleData:
      case PropertyDetailPage.buyerInterests:
      case PropertyDetailPage.viewings:
      case PropertyDetailPage.saleOffers:
      case PropertyDetailPage.reservations:
      case PropertyDetailPage.guests:
      case PropertyDetailPage.housekeeping:
      case PropertyDetailPage.hotelRevenue:
      case PropertyDetailPage.parkingStorage:
      case PropertyDetailPage.unitSaleStatus:
        return 1;
      case PropertyDetailPage.inputs:
      case PropertyDetailPage.scenarios:
      case PropertyDetailPage.versions:
      case PropertyDetailPage.assetWorkbook:
      case PropertyDetailPage.offer:
        return 2;
      case PropertyDetailPage.operationsOverview:
      case PropertyDetailPage.tasks:
      case PropertyDetailPage.maintenance:
      case PropertyDetailPage.alerts:
      case PropertyDetailPage.budgetVsActual:
      case PropertyDetailPage.covenants:
        return 3;
      case PropertyDetailPage.analysis:
      case PropertyDetailPage.comps:
      case PropertyDetailPage.criteria:
        return 4;
      case PropertyDetailPage.reports:
      case PropertyDetailPage.documents:
        return 5;
    }
  }

  List<OverviewWorkflowStep> _buildSteps() {
    final hasMasterData = property != null &&
        property!.addressLine1.isNotEmpty &&
        property!.city.isNotEmpty;
    final hasRentRoll = property != null && property!.units > 0;
    final hasPlanung = summary.purchasePrice > 0;
    final hasBetrieb = summary.rehabBudget > 0 || hasPlanung;
    final hasAnalyse = metrics.irr != null || metrics.capRate > 0;
    final hasReporting = hasAnalyse;

    return [
      OverviewWorkflowStep(
        title: 'Stammdaten',
        subtitle: hasMasterData ? 'Erfasst' : 'Ausstehend',
        icon: Icons.edit_note_outlined,
        page: PropertyDetailPage.overview,
        isCompleted: hasMasterData,
      ),
      OverviewWorkflowStep(
        title: 'Vermietung',
        subtitle: hasRentRoll ? 'Mieter gepflegt' : 'Einheiten anlegen',
        icon: Icons.apartment_outlined,
        page: PropertyDetailPage.rentRoll,
        isCompleted: hasRentRoll,
      ),
      OverviewWorkflowStep(
        title: 'Planung',
        subtitle: hasPlanung ? 'Kalkuliert' : 'Kaufpreis eintragen',
        icon: Icons.tune_outlined,
        page: PropertyDetailPage.inputs,
        isCompleted: hasPlanung,
      ),
      OverviewWorkflowStep(
        title: 'Betrieb',
        subtitle: hasBetrieb ? 'Laufend' : 'Kosten erfassen',
        icon: Icons.checklist_outlined,
        page: PropertyDetailPage.operationsOverview,
        isCompleted: hasBetrieb,
      ),
      OverviewWorkflowStep(
        title: 'Analyse',
        subtitle: hasAnalyse ? 'Rendite berechnet' : 'Berechnung läuft',
        icon: Icons.analytics_outlined,
        page: PropertyDetailPage.analysis,
        isCompleted: hasAnalyse,
      ),
      OverviewWorkflowStep(
        title: 'Reporting',
        subtitle: hasReporting ? 'Bereit' : 'Wartet auf Analyse',
        icon: Icons.summarize_outlined,
        page: PropertyDetailPage.reports,
        isCompleted: hasReporting,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    final activeIndex = activeStepIndex(activePage);
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NxSectionHeader(title: context.strings.text('Property Workflow')),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 760) {
                return _HorizontalPipeline(
                  steps: steps,
                  activeIndex: activeIndex,
                  onSelect: onSelect,
                );
              }
              return _VerticalPipeline(
                steps: steps,
                activeIndex: activeIndex,
                onSelect: onSelect,
              );
            },
          ),
        ],
      ),
    );
  }
}

class OverviewWorkflowStep {
  const OverviewWorkflowStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.page,
    required this.isCompleted,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final PropertyDetailPage page;
  final bool isCompleted;
}

class _StepColors {
  const _StepColors({
    required this.status,
    required this.circleBackground,
    required this.icon,
  });

  final Color status;
  final Color circleBackground;
  final Color icon;

  factory _StepColors.resolve(
    BuildContext context, {
    required bool isCompleted,
    required bool isActive,
  }) {
    final semantic = context.semanticColors;
    final primary = Theme.of(context).colorScheme.primary;
    if (isCompleted) {
      return _StepColors(
        status: semantic.success,
        circleBackground: semantic.success.withValues(alpha: 0.12),
        icon: semantic.success,
      );
    }
    if (isActive) {
      return _StepColors(
        status: primary,
        circleBackground: primary.withValues(alpha: 0.12),
        icon: primary,
      );
    }
    return _StepColors(
      status: semantic.textSecondary,
      circleBackground: semantic.surfaceAlt,
      icon: semantic.textSecondary,
    );
  }
}

class _HorizontalPipeline extends StatelessWidget {
  const _HorizontalPipeline({
    required this.steps,
    required this.activeIndex,
    required this.onSelect,
  });

  final List<OverviewWorkflowStep> steps;
  final int activeIndex;
  final ValueChanged<PropertyDetailPage> onSelect;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: _PipelineNode(
              step: steps[i],
              isActive: i == activeIndex,
              onTap: () => onSelect(steps[i].page),
            ),
          ),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.only(top: 22.0),
              child: Container(
                width: 24,
                height: 2,
                color: i < activeIndex
                    ? semantic.success
                    : (i == activeIndex ? primary : semantic.border),
              ),
            ),
        ],
      ],
    );
  }
}

class _VerticalPipeline extends StatelessWidget {
  const _VerticalPipeline({
    required this.steps,
    required this.activeIndex,
    required this.onSelect,
  });

  final List<OverviewWorkflowStep> steps;
  final int activeIndex;
  final ValueChanged<PropertyDetailPage> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _VerticalPipelineRow(
            step: steps[i],
            isActive: i == activeIndex,
            isLast: i == steps.length - 1,
            onTap: () => onSelect(steps[i].page),
          ),
      ],
    );
  }
}

class _VerticalPipelineRow extends StatelessWidget {
  const _VerticalPipelineRow({
    required this.step,
    required this.isActive,
    required this.isLast,
    required this.onTap,
  });

  final OverviewWorkflowStep step;
  final bool isActive;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _StepColors.resolve(
      context,
      isCompleted: step.isCompleted,
      isActive: isActive,
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.circleBackground,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.status,
                      width: isActive ? 2.5 : 1.5,
                    ),
                  ),
                  child: Icon(
                    step.isCompleted ? Icons.check : step.icon,
                    color: colors.icon,
                    size: 18,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: colors.status.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
              child: Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.semanticColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineNode extends StatelessWidget {
  const _PipelineNode({
    required this.step,
    required this.isActive,
    required this.onTap,
  });

  final OverviewWorkflowStep step;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _StepColors.resolve(
      context,
      isCompleted: step.isCompleted,
      isActive: isActive,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadiusTokens.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.circleBackground,
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.status,
                  width: isActive ? 2.5 : 1.5,
                ),
              ),
              child: Icon(
                step.isCompleted ? Icons.check_circle_outline : step.icon,
                color: colors.icon,
                size: 22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              step.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              step.subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.semanticColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
