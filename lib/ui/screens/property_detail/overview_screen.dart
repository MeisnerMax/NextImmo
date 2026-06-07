import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/financing.dart';
import '../../../core/engine/normalize.dart';
import '../../../core/models/analysis_result.dart';
import '../../../core/models/property.dart';
import '../../i18n/app_strings.dart';
import '../../state/app_state.dart';
import '../../state/analysis_state.dart';
import '../../state/property_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/warnings_panel.dart';

class OverviewScreen extends ConsumerStatefulWidget {
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
  ConsumerState<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends ConsumerState<OverviewScreen> {
  static const Color _panel = Color(0xFFFFFFFF);
  static const Color _panelHigh = Color(0xFFF1F5F9);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _text = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _teal = Color(0xFF10B981);
  static const Color _rose = Color(0xFFDC2626);

  _CashflowMode _cashflowMode = _CashflowMode.annual;

  @override
  Widget build(BuildContext context) {
    final analysisAsync = ref.watch(
      scenarioAnalysisControllerProvider(widget.scenarioId),
    );
    final properties = ref.watch(propertiesControllerProvider).valueOrNull;
    final property = _findProperty(properties, widget.propertyId);

    return analysisAsync.when(
      data: (state) {
        final metrics = state.analysis.metrics;
        final summary = _DealSummaryViewModel.fromState(
          state: state,
          property: property,
        );

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_shouldShowOnboarding(summary, property)) ...[
              _buildOnboardingCard(context),
              const SizedBox(height: AppSpacing.component),
            ],
            _buildWorkflowHub(context, property, summary, metrics),
            const SizedBox(height: AppSpacing.component),
            _buildMetricGrid(context, metrics),
            const SizedBox(height: AppSpacing.component),
            _buildSnapshotSections(context, summary, property),
            const SizedBox(height: AppSpacing.component),
            _buildCharts(context, state, summary),
            const SizedBox(height: AppSpacing.component),
            WarningsPanel(warnings: state.analysis.warnings),
          ],
        );
        if (!widget.scrollable) {
          return content;
        }
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: SingleChildScrollView(child: content),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildWorkflowHub(
    BuildContext context,
    PropertyRecord? property,
    _DealSummaryViewModel summary,
    AnalysisMetrics metrics,
  ) {
    final activePage = ref.watch(propertyDetailPageProvider);
    return _assetPanel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.strings.text('Property Workflow'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 760) {
                return _buildHorizontalPipeline(
                  context,
                  property,
                  summary,
                  metrics,
                  activePage,
                );
              } else {
                return _buildVerticalPipeline(
                  context,
                  property,
                  summary,
                  metrics,
                  activePage,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  int _activeStepIndex(PropertyDetailPage page) {
    switch (page) {
      case PropertyDetailPage.overview:
      case PropertyDetailPage.audit:
        return 0;
      case PropertyDetailPage.units:
      case PropertyDetailPage.tenants:
      case PropertyDetailPage.leases:
      case PropertyDetailPage.rentRoll:
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

  List<_WorkflowStepData> _getWorkflowSteps(
    BuildContext context,
    PropertyRecord? property,
    _DealSummaryViewModel summary,
    AnalysisMetrics metrics,
  ) {
    final hasMasterData = property != null &&
        property.addressLine1.isNotEmpty &&
        property.city.isNotEmpty;
    final hasRentRoll = property != null && property.units > 0;
    final hasPlanung = summary.purchasePrice > 0;
    final hasBetrieb = summary.rehabBudget > 0 || hasPlanung;
    final hasAnalyse = metrics.irr != null || metrics.capRate > 0;
    final hasReporting = hasAnalyse;

    return [
      _WorkflowStepData(
        title: 'Stammdaten',
        subtitle: hasMasterData ? 'Erfasst' : 'Ausstehend',
        icon: Icons.edit_note_outlined,
        page: PropertyDetailPage.overview,
        isCompleted: hasMasterData,
      ),
      _WorkflowStepData(
        title: 'Vermietung',
        subtitle: hasRentRoll ? 'Mieter gepflegt' : 'Einheiten anlegen',
        icon: Icons.apartment_outlined,
        page: PropertyDetailPage.rentRoll,
        isCompleted: hasRentRoll,
      ),
      _WorkflowStepData(
        title: 'Planung',
        subtitle: hasPlanung ? 'Kalkuliert' : 'Kaufpreis eintragen',
        icon: Icons.tune_outlined,
        page: PropertyDetailPage.inputs,
        isCompleted: hasPlanung,
      ),
      _WorkflowStepData(
        title: 'Betrieb',
        subtitle: hasBetrieb ? 'Laufend' : 'Kosten erfassen',
        icon: Icons.checklist_outlined,
        page: PropertyDetailPage.operationsOverview,
        isCompleted: hasBetrieb,
      ),
      _WorkflowStepData(
        title: 'Analyse',
        subtitle: hasAnalyse ? 'Rendite berechnet' : 'Berechnung läuft',
        icon: Icons.analytics_outlined,
        page: PropertyDetailPage.analysis,
        isCompleted: hasAnalyse,
      ),
      _WorkflowStepData(
        title: 'Reporting',
        subtitle: hasReporting ? 'Bereit' : 'Wartet auf Analyse',
        icon: Icons.summarize_outlined,
        page: PropertyDetailPage.reports,
        isCompleted: hasReporting,
      ),
    ];
  }

  Widget _buildHorizontalPipeline(
    BuildContext context,
    PropertyRecord? property,
    _DealSummaryViewModel summary,
    AnalysisMetrics metrics,
    PropertyDetailPage activePage,
  ) {
    final activeIndex = _activeStepIndex(activePage);
    final steps = _getWorkflowSteps(context, property, summary, metrics);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: _PipelineNode(
              step: steps[i],
              index: i,
              isActive: i == activeIndex,
              onTap: () => ref.read(propertyDetailPageProvider.notifier).state = steps[i].page,
            ),
          ),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.only(top: 22.0),
              child: Container(
                width: 24,
                height: 2,
                color: i < activeIndex
                    ? const Color(0xFF10B981)
                    : (i == activeIndex ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0)),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildVerticalPipeline(
    BuildContext context,
    PropertyRecord? property,
    _DealSummaryViewModel summary,
    AnalysisMetrics metrics,
    PropertyDetailPage activePage,
  ) {
    final activeIndex = _activeStepIndex(activePage);
    final steps = _getWorkflowSteps(context, property, summary, metrics);

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          _buildVerticalPipelineRow(
            context: context,
            step: steps[i],
            index: i,
            isActive: i == activeIndex,
            isLast: i == steps.length - 1,
            onTap: () => ref.read(propertyDetailPageProvider.notifier).state = steps[i].page,
          ),
        ],
      ],
    );
  }

  Widget _buildVerticalPipelineRow({
    required BuildContext context,
    required _WorkflowStepData step,
    required int index,
    required bool isActive,
    required bool isLast,
    required VoidCallback onTap,
  }) {
    final statusColor = step.isCompleted
        ? const Color(0xFF10B981)
        : (isActive ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8));

    final bgCircleColor = step.isCompleted
        ? const Color(0xFFDCFCE7)
        : (isActive ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9));

    final iconColor = step.isCompleted
        ? const Color(0xFF15803D)
        : (isActive ? const Color(0xFF1D4ED8) : const Color(0xFF64748B));

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
                    color: bgCircleColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: statusColor,
                      width: isActive ? 2.5 : 1.5,
                    ),
                  ),
                  child: Icon(
                    step.isCompleted ? Icons.check : step.icon,
                    color: iconColor,
                    size: 18,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: statusColor.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
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
                            color: const Color(0xFF0F172A),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
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

  Widget _buildMetricGrid(BuildContext context, AnalysisMetrics metrics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final twoColumn =
            constraints.maxWidth >= 520 && constraints.maxWidth < 980;
        final metricWidth =
            compact
                ? constraints.maxWidth
                : twoColumn
                ? (constraints.maxWidth - AppSpacing.component) / 2
                : 220.0;
        final wideWidth =
            compact || twoColumn
                ? metricWidth
                : (metricWidth * 2) + AppSpacing.component;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.payments_outlined,
              label: 'Monthly Cashflow',
              value: metrics.monthlyCashflowYear1.toStringAsFixed(2),
              tone: _toneFor(metrics.monthlyCashflowYear1),
            ),
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.bar_chart_outlined,
              label: 'NOI Y1',
              value: metrics.noiYear1.toStringAsFixed(2),
              tone: _toneFor(metrics.noiYear1),
            ),
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.percent_outlined,
              label: 'Cap Rate',
              value: '${(metrics.capRate * 100).toStringAsFixed(2)}%',
              tone: _text,
            ),
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.currency_exchange_outlined,
              label: 'Cash on Cash',
              value: '${(metrics.cashOnCash * 100).toStringAsFixed(2)}%',
              tone: _toneFor(metrics.cashOnCash),
            ),
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.show_chart_outlined,
              label: 'IRR',
              value:
                  metrics.irr == null
                      ? 'N/A'
                      : '${(metrics.irr! * 100).toStringAsFixed(2)}%',
              tone: metrics.irr == null ? _text : _toneFor(metrics.irr!),
            ),
            _metricCard(
              context,
              width: metricWidth,
              icon: Icons.trending_up_outlined,
              label: 'ROI',
              value: '${(metrics.roi * 100).toStringAsFixed(2)}%',
              tone: _toneFor(metrics.roi),
            ),
            _metricCard(
              context,
              width: wideWidth,
              icon: Icons.balance_outlined,
              label: 'DSCR',
              value: metrics.dscr?.toStringAsFixed(2) ?? 'N/A',
              subtitle: metrics.dscr == null ? null : 'Ratio',
              tone: _text,
            ),
          ],
        );
      },
    );
  }



  Widget _metricCard(
    BuildContext context, {
    required double width,
    required IconData icon,
    required String label,
    required String value,
    required Color tone,
    String? subtitle,
  }) {
    return SizedBox(
      width: width,
      height: 132,
      child: Container(
        decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: Container(color: tone),
              ),
              Positioned.fill(
                left: 4,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Icon(icon, size: 52, color: _muted.withValues(alpha: 0.14)),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            context.strings.text(label).toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: _muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Text(
                                  value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.headlineMedium?.merge(
                                    context.tabularNumericStyle.copyWith(
                                      color: tone,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(width: 6),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    subtitle,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: _muted),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnboardingCard(BuildContext context) {
    final s = context.strings;
    final actions = <
      ({IconData icon, String title, String description, VoidCallback onTap})
    >[
      (
        icon: Icons.tune_outlined,
        title: s.text('Add financial assumptions'),
        description: s.text('Purchase price, financing and capex assumptions'),
        onTap:
            () =>
                ref.read(propertyDetailPageProvider.notifier).state =
                    PropertyDetailPage.inputs,
      ),
      (
        icon: Icons.flag_outlined,
        title: s.text('Set strategy'),
        description: s.text('Choose the base scenario and investment approach'),
        onTap:
            () =>
                ref.read(propertyDetailPageProvider.notifier).state =
                    PropertyDetailPage.scenarios,
      ),
      (
        icon: Icons.bar_chart_outlined,
        title: s.text('Add rent data'),
        description: s.text('Enter rent, vacancy and operating income data'),
        onTap:
            () =>
                ref.read(propertyDetailPageProvider.notifier).state =
                    PropertyDetailPage.inputs,
      ),
      (
        icon: Icons.folder_open_outlined,
        title: s.text('Add documents'),
        description: s.text(
          'Upload leases, diligence files and supporting material',
        ),
        onTap:
            () =>
                ref.read(propertyDetailPageProvider.notifier).state =
                    PropertyDetailPage.documents,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.text('Next Steps'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              s.text(
                'This property was created with the basics only. Add the next inputs to unlock a reliable analysis.',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.component),
            Wrap(
              spacing: AppSpacing.component,
              runSpacing: AppSpacing.component,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: 260,
                    child: OutlinedButton(
                      onPressed: action.onTap,
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadiusTokens.md,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(action.icon),
                          const SizedBox(height: 12),
                          Text(
                            action.title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            action.description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotSections(
    BuildContext context,
    _DealSummaryViewModel summary,
    PropertyRecord? property,
  ) {
    return _assetPanel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.strings.text('Property Snapshot'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080 ? 2 : 1;
              final width =
                  columns == 2
                      ? (constraints.maxWidth - AppSpacing.component) / 2
                      : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.component,
                runSpacing: AppSpacing.component,
                children: [
                  SizedBox(
                    width: width,
                    child: _snapshotGroup(
                      context,
                      title: 'Object Profile',
                      rows: [
                        _SnapshotRow(
                          label: 'Address',
                          value: _propertyAddress(property),
                        ),
                        _SnapshotRow(
                          label: 'Property Type',
                          value: property?.propertyType ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Units',
                          value: property?.units.toString() ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Size m2',
                          value: _formatOptional(summary.sizeM2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _snapshotGroup(
                      context,
                      title: 'Valuation Snapshot',
                      rows: [
                        _SnapshotRow(
                          label: 'Purchase Price',
                          value: _formatNumber(summary.purchasePrice),
                        ),
                        _SnapshotRow(
                          label: 'Price per m2',
                          value: _formatOptional(summary.pricePerM2),
                        ),
                        _SnapshotRow(
                          label: 'Hold Period',
                          value: summary.holdPeriodLabel,
                        ),
                        _SnapshotRow(
                          label: 'Exit Assumption',
                          value: summary.exitAssumptionMode,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _snapshotGroup(
                      context,
                      title: 'Rent Snapshot',
                      rows: [
                        _SnapshotRow(
                          label: 'Monthly Rent',
                          value: _formatNumber(summary.monthlyRent),
                        ),
                        _SnapshotRow(
                          label: 'Rent per m2',
                          value: _formatOptional(summary.rentPerM2),
                        ),
                        _SnapshotRow(
                          label: 'Units',
                          value: property?.units.toString() ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Year Built',
                          value: property?.yearBuilt?.toString() ?? 'N/A',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _snapshotGroup(
                      context,
                      title: 'Financing Snapshot',
                      rows: [
                        _SnapshotRow(
                          label: 'Rehab Budget',
                          value: _formatNumber(summary.rehabBudget),
                        ),
                        _SnapshotRow(
                          label: 'Total Acquisition Cost',
                          value: _formatNumber(summary.totalAcquisitionCost),
                        ),
                        _SnapshotRow(
                          label: 'Total Equity Invested',
                          value: _formatNumber(summary.totalEquityInvested),
                        ),
                        _SnapshotRow(
                          label: 'LTV',
                          value:
                              summary.ltv == null
                                  ? 'N/A'
                                  : '${(summary.ltv! * 100).toStringAsFixed(2)}%',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _assetPanel(BuildContext context, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: child,
    );
  }

  Widget _snapshotGroup(
    BuildContext context, {
    required String title,
    required List<_SnapshotRow> rows,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.component),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.strings.text(title),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: _text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final row in rows) _snapshotRow(context, row),
          ],
        ),
      ),
    );
  }

  Widget _snapshotRow(BuildContext context, _SnapshotRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              context.strings.text(row.label),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _muted,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.component),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(
                color: _text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharts(
    BuildContext context,
    ScenarioAnalysisState state,
    _DealSummaryViewModel summary,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 1080;
        if (stacked) {
          return Column(
            children: [
              SizedBox(height: 300, child: _buildCashflowChartCard(state)),
              const SizedBox(height: AppSpacing.component),
              SizedBox(
                height: 300,
                child: _buildRentProjectionChartCard(
                  state,
                  summary.monthlyRent,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 300,
                child: _buildCashflowChartCard(state),
              ),
            ),
            const SizedBox(width: AppSpacing.component),
            Expanded(
              child: SizedBox(
                height: 300,
                child: _buildRentProjectionChartCard(
                  state,
                  summary.monthlyRent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCashflowChartCard(ScenarioAnalysisState state) {
    final useMonthly = _cashflowMode == _CashflowMode.monthlyAverage;
    final annualPeriods = state.analysis.proformaYears;
    final monthlyPeriods = state.analysis.proformaMonths;
    if (annualPeriods.isEmpty || monthlyPeriods.isEmpty) {
      return const Card(
        child: Center(
          child: Text('Cashflow chart unavailable: no proforma data.'),
        ),
      );
    }
    final values =
        useMonthly
            ? monthlyPeriods
                .map((entry) => entry.cashflowBeforeTax)
                .toList(growable: false)
            : annualPeriods
                .map((entry) => entry.cashflowBeforeTax)
                .toList(growable: false);
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++)
        FlSpot((i + 1).toDouble(), values[i]),
    ];

    final minY = _minAxisValue(values);
    final maxY = _maxAxisValue(values);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Cashflow Projection',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                ToggleButtons(
                  isSelected: [
                    _cashflowMode == _CashflowMode.annual,
                    _cashflowMode == _CashflowMode.monthlyAverage,
                  ],
                  onPressed: (index) {
                    setState(() {
                      _cashflowMode =
                          index == 0
                              ? _CashflowMode.annual
                              : _CashflowMode.monthlyAverage;
                    });
                  },
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Annual'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Monthly'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: 1,
                  maxX: values.length.toDouble(),
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: context.semanticColors.border.withValues(alpha: 0.4),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (spot) => Theme.of(context).colorScheme.surface,
                      tooltipBorder: BorderSide(color: context.semanticColors.border, width: 1.5),
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      tooltipRoundedRadius: AppRadiusTokens.md,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((touchedSpot) {
                          return LineTooltipItem(
                            '€ ${_formatNumber(touchedSpot.y)}',
                            TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ).merge(context.tabularNumericStyle),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 64,
                        getTitlesWidget: (value, _) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '€ ${value.toStringAsFixed(0)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.semanticColors.textSecondary,
                            ).merge(context.tabularNumericStyle),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          final period = value.toInt();
                          if (period <= 0 || period > values.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              useMonthly ? 'M$period' : 'Y$period',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.semanticColors.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      barWidth: 3,
                      color: Theme.of(context).colorScheme.primary,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 4.5,
                          color: Theme.of(context).colorScheme.primary,
                          strokeWidth: 2,
                          strokeColor: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.24),
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      spots: spots,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRentProjectionChartCard(
    ScenarioAnalysisState state,
    double monthlyRentStart,
  ) {
    final normalized = normalizeInputs(
      inputs: state.inputs,
      settings: state.settings,
      incomeLines: state.incomeLines,
      expenseLines: state.expenseLines,
    );
    final monthsCount = state.analysis.proformaMonths.length;
    if (monthsCount <= 0) {
      return const Card(
        child: Center(
          child: Text('Rent chart unavailable: no projection months.'),
        ),
      );
    }
    final growth = normalized.inputs.rentGrowthPercent;
    final values = <double>[
      for (var month = 1; month <= monthsCount; month++)
        monthlyRentStart * math.pow(1 + growth, (month - 1) / 12).toDouble(),
    ];
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++)
        FlSpot((i + 1).toDouble(), values[i]),
    ];
    final maxY = _maxAxisValue(values);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rent Projection',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.component),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: 1,
                  maxX: monthsCount.toDouble(),
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: context.semanticColors.border.withValues(alpha: 0.4),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (spot) => Theme.of(context).colorScheme.surface,
                      tooltipBorder: BorderSide(color: context.semanticColors.border, width: 1.5),
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      tooltipRoundedRadius: AppRadiusTokens.md,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((touchedSpot) {
                          return LineTooltipItem(
                            '€ ${_formatNumber(touchedSpot.y)}',
                            TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ).merge(context.tabularNumericStyle),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 64,
                        getTitlesWidget: (value, _) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '€ ${value.toStringAsFixed(0)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.semanticColors.textSecondary,
                            ).merge(context.tabularNumericStyle),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          final month = value.toInt();
                          if (month <= 0 || month > monthsCount) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'M$month',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.semanticColors.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      barWidth: 3,
                      color: Theme.of(context).colorScheme.secondary,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 4.5,
                          color: Theme.of(context).colorScheme.secondary,
                          strokeWidth: 2,
                          strokeColor: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.24),
                            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      spots: spots,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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

  static String _propertyAddress(PropertyRecord? property) {
    if (property == null) {
      return 'N/A';
    }
    final parts = <String>[
      property.addressLine1,
      if (property.addressLine2 != null &&
          property.addressLine2!.trim().isNotEmpty)
        property.addressLine2!,
      property.city,
      property.country,
    ].where((part) => part.trim().isNotEmpty).toList(growable: false);
    return parts.isEmpty ? 'N/A' : parts.join(', ');
  }

  static String _formatNumber(double value) => value.toStringAsFixed(2);

  static Color _toneFor(double value) {
    if (value < 0) {
      return _rose;
    }
    if (value > 0) {
      return _teal;
    }
    return _text;
  }

  static String _formatOptional(double? value) {
    if (value == null) {
      return 'N/A';
    }
    return value.toStringAsFixed(2);
  }

  static double _maxAxisValue(List<double> values) {
    final maxValue = values.fold<double>(
      double.negativeInfinity,
      (current, value) => math.max(current, value),
    );
    if (!maxValue.isFinite) {
      return 1;
    }
    return maxValue <= 0 ? 1 : maxValue * 1.1;
  }

  static double _minAxisValue(List<double> values) {
    final minValue = values.fold<double>(
      double.infinity,
      (current, value) => math.min(current, value),
    );
    if (!minValue.isFinite) {
      return 0;
    }
    if (minValue >= 0) {
      return 0;
    }
    return minValue * 1.1;
  }

  static bool _shouldShowOnboarding(
    _DealSummaryViewModel summary,
    PropertyRecord? property,
  ) {
    final propertyHasOnlyBasics =
        property != null &&
        (property.sqft == null || property.sqft == 0) &&
        property.yearBuilt == null &&
        (property.notes == null || property.notes!.trim().isEmpty);
    final assumptionsMissing =
        summary.purchasePrice <= 0 &&
        summary.monthlyRent <= 0 &&
        summary.rehabBudget <= 0;
    return propertyHasOnlyBasics && assumptionsMissing;
  }
}

enum _CashflowMode { annual, monthlyAverage }

class _SnapshotRow {
  const _SnapshotRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _DealSummaryViewModel {
  const _DealSummaryViewModel({
    required this.purchasePrice,
    required this.sizeM2,
    required this.pricePerM2,
    required this.monthlyRent,
    required this.rentPerM2,
    required this.rehabBudget,
    required this.closingCostsBuy,
    required this.totalAcquisitionCost,
    required this.totalEquityInvested,
    required this.loanAmount,
    required this.ltv,
    required this.holdPeriodLabel,
    required this.exitAssumptionMode,
  });

  final double purchasePrice;
  final double? sizeM2;
  final double? pricePerM2;
  final double monthlyRent;
  final double? rentPerM2;
  final double rehabBudget;
  final double closingCostsBuy;
  final double totalAcquisitionCost;
  final double totalEquityInvested;
  final double loanAmount;
  final double? ltv;
  final String holdPeriodLabel;
  final String exitAssumptionMode;

  factory _DealSummaryViewModel.fromState({
    required ScenarioAnalysisState state,
    required PropertyRecord? property,
  }) {
    final normalized = normalizeInputs(
      inputs: state.inputs,
      settings: state.settings,
      incomeLines: state.incomeLines,
      expenseLines: state.expenseLines,
    );
    final inputs = normalized.inputs;
    final financing = resolveFinancing(inputs);
    final ltv =
        financing.totalAcquisitionCost <= 0
            ? null
            : financing.loanPrincipal / financing.totalAcquisitionCost;

    final sizeM2 = property?.sqft == null ? null : property!.sqft! * 0.092903;
    final monthlyRent = inputs.rentOverride ?? inputs.rentMonthlyTotal;
    final pricePerM2 =
        sizeM2 == null || sizeM2 <= 0 ? null : inputs.purchasePrice / sizeM2;
    final rentPerM2 =
        sizeM2 == null || sizeM2 <= 0 ? null : monthlyRent / sizeM2;

    return _DealSummaryViewModel(
      purchasePrice: inputs.purchasePrice,
      sizeM2: sizeM2,
      pricePerM2: pricePerM2,
      monthlyRent: monthlyRent,
      rentPerM2: rentPerM2,
      rehabBudget: inputs.rehabBudget,
      closingCostsBuy: financing.buyClosingCosts,
      totalAcquisitionCost: financing.totalAcquisitionCost,
      totalEquityInvested: financing.totalCashInvested,
      loanAmount: financing.loanPrincipal,
      ltv: ltv,
      holdPeriodLabel: '${normalized.horizonMonths}m',
      exitAssumptionMode:
          state.valuation.valuationMode == 'exit_cap'
              ? 'Exit Cap'
              : 'Appreciation',
    );
  }
}

class _WorkflowStepData {
  const _WorkflowStepData({
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

class _PipelineNode extends StatelessWidget {
  const _PipelineNode({
    required this.step,
    required this.index,
    required this.isActive,
    required this.onTap,
  });

  final _WorkflowStepData step;
  final int index;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = step.isCompleted
        ? const Color(0xFF10B981)
        : (isActive ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8));

    final bgCircleColor = step.isCompleted
        ? const Color(0xFFDCFCE7)
        : (isActive ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9));

    final iconColor = step.isCompleted
        ? const Color(0xFF15803D)
        : (isActive ? const Color(0xFF1D4ED8) : const Color(0xFF64748B));

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
                color: bgCircleColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: statusColor,
                  width: isActive ? 2.5 : 1.5,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                          blurRadius: 8,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
              child: Icon(
                step.isCompleted ? Icons.check_circle_outline : step.icon,
                color: iconColor,
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
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              step.subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
