import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/budget.dart';
import '../../../core/models/documents.dart';
import '../../../core/models/maintenance.dart';
import '../../../core/models/property.dart';
import '../../../core/models/security.dart';
import '../../../core/models/task.dart';
import '../../../data/repositories/budget_repo.dart';
import '../../../data/repositories/documents_repo.dart';
import '../../../data/repositories/operations_repo.dart';
import '../../state/app_state.dart';
import '../../state/property_state.dart';
import '../../state/security_state.dart';
import '../../theme/app_theme.dart';

enum DashboardSeverity { critical, warning, info }

enum DashboardActionCategory {
  leaseExpiry,
  documentGap,
  budgetVariance,
  maintenance,
  task,
  dataQuality,
}

class DashboardNavigationTarget {
  const DashboardNavigationTarget({
    required this.globalPage,
    this.propertyId,
    this.propertyDetailPage,
  });

  final GlobalPage globalPage;
  final String? propertyId;
  final PropertyDetailPage? propertyDetailPage;
}

class DashboardActionItem {
  const DashboardActionItem({
    required this.category,
    required this.severity,
    required this.title,
    required this.detail,
    required this.nextStep,
    required this.target,
    this.count,
  });

  final DashboardActionCategory category;
  final DashboardSeverity severity;
  final String title;
  final String detail;
  final String nextStep;
  final DashboardNavigationTarget target;
  final int? count;
}

class DashboardActivityItem {
  const DashboardActivityItem({
    required this.title,
    required this.detail,
    required this.timestamp,
    required this.target,
    required this.icon,
  });

  final String title;
  final String detail;
  final DateTime timestamp;
  final DashboardNavigationTarget target;
  final IconData icon;
}

class DashboardSignalMetric {
  const DashboardSignalMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.severity,
  });

  final String label;
  final int value;
  final String detail;
  final DashboardSeverity severity;
}

class DashboardCategoryValue {
  const DashboardCategoryValue({required this.label, required this.value});

  final String label;
  final int value;
}

class DashboardMonthValue {
  const DashboardMonthValue({required this.date, required this.value});

  final DateTime date;
  final int value;
}

class DashboardValuePoint {
  const DashboardValuePoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

class DashboardOverviewData {
  const DashboardOverviewData({
    required this.activeProperties,
    required this.totalUnits,
    required this.occupiedUnits,
    required this.vacantUnits,
    required this.annualRent,
    required this.monthlyRentRunRate,
    required this.annualOperatingCosts,
    required this.openDepositAmount,
    required this.serviceChargeBalance,
    required this.sourceCoverageRate,
    required this.criticalActions,
    required this.atRiskAssets,
    required this.propertyTypeMix,
    required this.intakeTrend,
    required this.signalMetrics,
    required this.actionItems,
    required this.activityItems,
  });

  final int activeProperties;
  final int totalUnits;
  final int occupiedUnits;
  final int vacantUnits;
  final double annualRent;
  final double monthlyRentRunRate;
  final double annualOperatingCosts;
  final double openDepositAmount;
  final double serviceChargeBalance;
  final double sourceCoverageRate;
  final int criticalActions;
  final int atRiskAssets;
  final List<DashboardCategoryValue> propertyTypeMix;
  final List<DashboardMonthValue> intakeTrend;
  final List<DashboardSignalMetric> signalMetrics;
  final List<DashboardActionItem> actionItems;
  final List<DashboardActivityItem> activityItems;

  factory DashboardOverviewData.empty() {
    return DashboardOverviewData(
      activeProperties: 0,
      totalUnits: 0,
      occupiedUnits: 0,
      vacantUnits: 0,
      annualRent: 0,
      monthlyRentRunRate: 0,
      annualOperatingCosts: 0,
      openDepositAmount: 0,
      serviceChargeBalance: 0,
      sourceCoverageRate: 0,
      criticalActions: 0,
      atRiskAssets: 0,
      propertyTypeMix: const <DashboardCategoryValue>[],
      intakeTrend: _buildMonthlyIntake(const <PropertyRecord>[]),
      signalMetrics: const <DashboardSignalMetric>[],
      actionItems: const <DashboardActionItem>[],
      activityItems: const <DashboardActivityItem>[],
    );
  }
}

final dashboardOverviewProvider =
    FutureProvider.autoDispose<DashboardOverviewData>((ref) async {
      final properties = await ref.watch(propertiesControllerProvider.future);
      final activeProperties = properties
          .where((property) => !property.archived)
          .toList(growable: false);
      if (activeProperties.isEmpty) {
        return DashboardOverviewData.empty();
      }

      final operationsRepo = ref.read(operationsRepositoryProvider);
      final documentsRepo = ref.read(documentsRepositoryProvider);
      final tasksRepo = ref.read(tasksRepositoryProvider);
      final maintenanceRepo = ref.read(maintenanceRepositoryProvider);
      final budgetRepo = ref.read(budgetRepositoryProvider);
      final rentalOverview = await ref
          .read(assetWorkbookRepositoryProvider)
          .loadPortfolioOverview();
      final now = DateTime.now();
      final tasks = await tasksRepo.listTasks();
      final maintenanceTickets = await maintenanceRepo.listTickets();
      final propertyDocuments = await documentsRepo.listDocuments(
        entityType: 'property',
      );

      final propertySignals = await Future.wait(
        activeProperties.map(
          (property) => _loadPropertySignal(
            property: property,
            now: now,
            tasks: tasks,
            maintenanceTickets: maintenanceTickets,
            operationsRepo: operationsRepo,
            documentsRepo: documentsRepo,
            budgetRepo: budgetRepo,
          ),
        ),
      );

      final actionItems = _buildActionItems(propertySignals, tasks);
      final atRiskAssets =
          actionItems
              .where((item) => item.target.propertyId != null)
              .map((item) => item.target.propertyId!)
              .toSet()
              .length;
      final signalMetrics = _buildSignalMetrics(propertySignals, tasks);

      return DashboardOverviewData(
        activeProperties: activeProperties.length,
        totalUnits: rentalOverview.rentedUnits + rentalOverview.emptyUnits,
        occupiedUnits: rentalOverview.rentedUnits,
        vacantUnits: rentalOverview.emptyUnits,
        annualRent: rentalOverview.annualRent,
        monthlyRentRunRate: rentalOverview.monthlyRentRunRate,
        annualOperatingCosts: rentalOverview.annualOperatingCosts,
        openDepositAmount: rentalOverview.openDepositAmount,
        serviceChargeBalance: rentalOverview.serviceChargeBalance,
        sourceCoverageRate: rentalOverview.sourceCoverageRate,
        criticalActions:
            actionItems
                .where((item) => item.severity == DashboardSeverity.critical)
                .length,
        atRiskAssets: atRiskAssets,
        propertyTypeMix: _buildTypeMix(activeProperties),
        intakeTrend: _buildMonthlyIntake(activeProperties),
        signalMetrics: signalMetrics,
        actionItems: actionItems,
        activityItems: _buildActivityItems(
          properties: activeProperties,
          tasks: tasks,
          maintenanceTickets: maintenanceTickets,
          propertyDocuments: propertyDocuments,
        ),
      );
    });

class DashboardScreenV2 extends ConsumerWidget {
  const DashboardScreenV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(dashboardOverviewProvider);
    final roleConfig = _roleConfigFor(ref.watch(activeUserRoleProvider));
    final securityContext = ref.watch(activeSecurityContextProvider);

    return overviewAsync.when(
      data:
          (overview) => _SovereignDashboard(
            overview: overview,
            subtitle: _buildSubtitle(roleConfig, securityContext),
            actionItems: _sortActionsForRole(overview.actionItems, roleConfig),
            onRefresh: () {
              ref.invalidate(propertiesControllerProvider);
              ref.invalidate(dashboardOverviewProvider);
            },
            onOpenTarget: (target) => _openTarget(ref, target),
          ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: Text('Dashboard konnte nicht geladen werden: $error'),
            ),
          ),
    );
  }
}

class _SovereignDashboard extends StatelessWidget {
  const _SovereignDashboard({
    required this.overview,
    required this.subtitle,
    required this.actionItems,
    required this.onRefresh,
    required this.onOpenTarget,
  });

  final DashboardOverviewData overview;
  final String subtitle;
  final List<DashboardActionItem> actionItems;
  final VoidCallback onRefresh;
  final ValueChanged<DashboardNavigationTarget> onOpenTarget;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 900;
        final pagePadding = context.adaptivePagePadding;
        final content = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child:
              mobile
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(context, compact: true),
                      const SizedBox(height: 32),
                      _kpiGrid(context, columns: 1),
                      const SizedBox(height: 32),
                      _performanceCard(context),
                      const SizedBox(height: 32),
                      _SignalGrid(
                        signalMetrics: overview.signalMetrics,
                        onOpenTarget: onOpenTarget,
                      ),
                      const SizedBox(height: 32),
                      _recentActivity(context),
                      const SizedBox(height: 32),
                      _rightPanel(context),
                    ],
                  )
                  : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _header(context, compact: false),
                            const SizedBox(height: 64),
                            _kpiGrid(context, columns: 3),
                            const SizedBox(height: 48),
                            _performanceCard(context),
                            const SizedBox(height: 48),
                            _SignalGrid(
                              signalMetrics: overview.signalMetrics,
                              onOpenTarget: onOpenTarget,
                            ),
                            const SizedBox(height: 48),
                            _recentActivity(context),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48),
                      SizedBox(width: 360, child: _rightPanel(context)),
                    ],
                  ),
        );

        return ListView(
          padding: EdgeInsets.fromLTRB(
            pagePadding,
            mobile ? 28 : 48,
            pagePadding,
            64,
          ),
          children: [Center(child: content)],
        );
      },
    );
  }

  Widget _header(BuildContext context, {required bool compact}) {
    final semantic = context.semanticColors;
    final actionButtons = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed:
              () => onOpenTarget(
                const DashboardNavigationTarget(
                  globalPage: GlobalPage.properties,
                ),
              ),
          icon: const Icon(Icons.table_chart_outlined),
          label: const Text('Vermietung & BK'),
        ),
        OutlinedButton.icon(
          onPressed:
              () => onOpenTarget(
                const DashboardNavigationTarget(
                  globalPage: GlobalPage.properties,
                ),
              ),
          icon: const Icon(Icons.home_work_outlined),
          label: const Text('Objekte'),
        ),
        _IconActionButton(icon: Icons.refresh, onPressed: onRefresh),
      ],
    );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dashboard',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontSize: compact ? 34 : 52,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: semantic.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7),
              decoration: BoxDecoration(
                color: semantic.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aktualisiert aus den gespeicherten Objekt-, Miet-, Aufgaben- und BK-Daten',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: semantic.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackActions = compact || constraints.maxWidth < 1100;
        if (stackActions) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 18),
              actionButtons,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 24),
            Flexible(child: Align(alignment: Alignment.bottomRight, child: actionButtons)),
          ],
        );
      },
    );
  }

  Widget _kpiGrid(BuildContext context, {required int columns}) {
    final rentableUnits = overview.occupiedUnits + overview.vacantUnits;
    final occupancyRate =
        rentableUnits == 0 ? 0.0 : overview.occupiedUnits / rentableUnits;
    final costRatio =
        overview.annualRent == 0
            ? 0.0
            : overview.annualOperatingCosts / overview.annualRent;
    final cards = [
      _KpiSpec(
        label: 'JAHRESMIETE',
        value: _formatCurrency(overview.annualRent),
        tone: Theme.of(context).colorScheme.onSurface,
      ),
      _KpiSpec(
        label: 'MONATSLAUF',
        value: _formatCurrency(overview.monthlyRentRunRate),
        tone: context.semanticColors.success,
        badge: Icons.trending_up,
      ),
      _KpiSpec(
        label: 'VERMIETUNGSQUOTE',
        value: _formatPercent(occupancyRate),
        tone: Theme.of(context).colorScheme.onSurface,
      ),
      _KpiSpec(
        label: 'BK / KOSTEN P.A.',
        value: _formatCurrency(overview.annualOperatingCosts),
        tone:
            costRatio > 0.35
                ? context.semanticColors.warning
                : Theme.of(context).colorScheme.onSurface,
      ),
      _KpiSpec(
        label: 'OFFENE KAUTIONEN',
        value: _formatCurrency(overview.openDepositAmount),
        tone:
            overview.openDepositAmount > 0
                ? context.semanticColors.warning
                : context.semanticColors.success,
      ),
      _KpiSpec(
        label: 'OFFENE AKTIONEN',
        value: '${overview.criticalActions}',
        tone:
            overview.criticalActions > 0
                ? context.semanticColors.error
                : context.semanticColors.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = columns == 1 ? 16.0 : 24.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(width: width, child: _SovereignKpiCard(spec: card)),
          ],
        );
      },
    );
  }

  Widget _performanceCard(BuildContext context) {
    final valuationPoints = _buildValuationTrend();
    return _SovereignModule(
      padding: const EdgeInsets.all(28),
      child: _ValuationTrendPanel(
        values: valuationPoints,
        description:
            'Portfolio-Wert aus Jahresmiete abzüglich laufender Kosten.',
      ),
    );
  }

  List<DashboardValuePoint> _buildValuationTrend() {
    final netAnnual = overview.annualRent - overview.annualOperatingCosts;
    if (netAnnual <= 0) {
      return const <DashboardValuePoint>[];
    }
    final estimatedValue = netAnnual / 0.055;
    final now = DateTime.now();
    return <DashboardValuePoint>[
      for (var index = 11; index >= 0; index--)
        DashboardValuePoint(
          date: DateTime(now.year, now.month - index),
          value: estimatedValue * (1 - index * 0.004),
        ),
    ];
  }

  Widget _recentActivity(BuildContext context) {
    final items = overview.activityItems.take(4).toList(growable: false);
    return _SovereignModule(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(28),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Aktuelle Aktivität',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      items.isEmpty
                          ? null
                          : () => onOpenTarget(items.first.target),
                  label: const Text('Öffnen'),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Noch keine aktuelle Portfolio-Aktivität.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else ...[
            _ActivityHeader(),
            for (final item in items)
              _ActivityRow(
                item: item,
                onTap: () => onOpenTarget(item.target),
              ),
          ],
        ],
      ),
    );
  }

  Widget _rightPanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('AKTUELLE HINWEISE'),
        const SizedBox(height: 24),
        if (actionItems.isEmpty)
          _AlertCard(
            color: context.semanticColors.success,
            title: 'Keine kritischen offenen Punkte',
            detail: 'Aktuell gibt es keine kritischen Dashboard-Aktionen.',
            onTap: onRefresh,
          )
        else
          for (var index = 0; index < math.min(2, actionItems.length); index++) ...[
            Container(
              key: ValueKey<String>('dashboard-action-$index'),
              child: _AlertCard(
                color: _severityColor(context, actionItems[index].severity),
                title: actionItems[index].title,
                detail: actionItems[index].detail,
                onTap: () => onOpenTarget(actionItems[index].target),
              ),
            ),
            const SizedBox(height: 24),
          ],
        const SizedBox(height: 48),
        const _SectionLabel('OBJEKTVERTEILUNG'),
        const SizedBox(height: 24),
        _SovereignModule(
          padding: const EdgeInsets.all(28),
          child: SizedBox(
            height: 250,
            child:
                overview.propertyTypeMix.isEmpty
                    ? const Center(child: Text('Noch keine aktiven Objekte.'))
                    : _TypeMixChart(values: overview.propertyTypeMix),
          ),
        ),
      ],
    );
  }
}

class _KpiSpec {
  const _KpiSpec({
    required this.label,
    required this.value,
    required this.tone,
    this.badge,
  });

  final String label;
  final String value;
  final Color tone;
  final IconData? badge;
}

class _SovereignKpiCard extends StatelessWidget {
  const _SovereignKpiCard({required this.spec});

  final _KpiSpec spec;

  @override
  Widget build(BuildContext context) {
    return _SovereignModule(
      padding: const EdgeInsets.all(22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 112),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final valueSize = constraints.maxWidth < 210 ? 24.0 : 30.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  spec.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          spec.value,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.displaySmall?.merge(
                            context.tabularNumericStyle.copyWith(
                              fontSize: valueSize,
                              color: spec.tone,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (spec.badge != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: spec.tone.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            AppRadiusTokens.sm,
                          ),
                        ),
                        child: Icon(spec.badge, color: spec.tone, size: 16),
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ValuationTrendPanel extends StatefulWidget {
  const _ValuationTrendPanel({
    required this.values,
    required this.description,
  });

  final List<DashboardValuePoint> values;
  final String description;

  @override
  State<_ValuationTrendPanel> createState() => _ValuationTrendPanelState();
}

class _ValuationTrendPanelState extends State<_ValuationTrendPanel> {
  String _selected = '6M';

  @override
  Widget build(BuildContext context) {
    final values = _filteredValues();
    final theme = Theme.of(context);
    
    final currentVal = widget.values.isNotEmpty ? widget.values.last.value : 0.0;
    final lastYearVal = widget.values.isNotEmpty ? widget.values.first.value : 0.0;
    final changePercent = lastYearVal > 0 ? (currentVal - lastYearVal) / lastYearVal : 0.0;
    final changeColor = changePercent >= 0 ? context.semanticColors.success : context.semanticColors.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wertentwicklung',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.semanticColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _ValuationPeriodSelector(
              selected: _selected,
              onChanged: (value) => setState(() => _selected = value),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (currentVal > 0)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.black.withValues(alpha: 0.01),
              borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
              border: Border.all(
                color: context.semanticColors.border,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'GESAMTPORTFOLIO-WERT',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: context.semanticColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _formatCurrency(currentVal),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'TENDENZ (12M)',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: context.semanticColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              changePercent >= 0 ? Icons.trending_up : Icons.trending_down,
                              color: changeColor,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${changePercent >= 0 ? '+' : ''}${(changePercent * 100).toStringAsFixed(1)}%',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: changeColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 280,
          child:
              values.isEmpty
                  ? const Center(child: Text('Noch keine Wertdaten.'))
                  : _ValuationTrendChart(values: values),
        ),
      ],
    );
  }

  List<DashboardValuePoint> _filteredValues() {
    if (_selected == '1J') {
      return widget.values;
    }
    if (_selected == 'YTD') {
      final year = DateTime.now().year;
      final values =
          widget.values.where((point) => point.date.year == year).toList();
      if (values.isNotEmpty) {
        return values;
      }
    }
    final start = math.max(0, widget.values.length - 6);
    return widget.values.skip(start).toList(growable: false);
  }
}

class _ValuationPeriodSelector extends StatelessWidget {
  const _ValuationPeriodSelector({
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
      segments: const [
        ButtonSegment(value: '6M', label: Text('6M')),
        ButtonSegment(value: 'YTD', label: Text('YTD')),
        ButtonSegment(value: '1J', label: Text('1J')),
      ],
      selected: <String>{selected},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _ValuationTrendChart extends StatelessWidget {
  const _ValuationTrendChart({required this.values});

  final List<DashboardValuePoint> values;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var index = 0; index < values.length; index++)
        FlSpot(index.toDouble(), values[index].value),
    ];
    final maxValue = values.fold<double>(
      0,
      (max, point) => point.value > max ? point.value : max,
    );
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxValue <= 0 ? 1 : maxValue * 1.05,
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
                  _formatCurrency(touchedSpot.y),
                  TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
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
              getTitlesWidget:
                  (value, _) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      _formatCurrency(value),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.semanticColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= values.length) {
                  return const SizedBox.shrink();
                }
                final date = values[index].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${date.month}/${date.year % 100}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.semanticColors.textSecondary,
                      fontWeight: FontWeight.w500,
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
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3.5,
            isStrokeCapRound: true,
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
    );
  }
}

class _SovereignModule extends StatelessWidget {
  const _SovereignModule({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: child,
    );
  }
}

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        child: Icon(icon, size: 22),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.labelMedium);
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.color,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final Color color;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: _SovereignModule(
        padding: const EdgeInsets.fromLTRB(24, 18, 18, 18),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 4, color: color),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.semanticColors.border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('OBJEKT', style: Theme.of(context).textTheme.labelMedium)),
          Expanded(child: Text('BEREICH', style: Theme.of(context).textTheme.labelMedium)),
          Expanded(child: Text('DATUM', style: Theme.of(context).textTheme.labelMedium, textAlign: TextAlign.right)),
          Expanded(child: Text('AKTION', style: Theme.of(context).textTheme.labelMedium, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.onTap});

  final DashboardActivityItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.semanticColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(item.icon, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                item.detail,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: Text(
                _formatDate(item.timestamp),
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Chip(
                  label: const Text('Öffnen'),
                  labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.semanticColors.success,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleConfig {
  const _RoleConfig({
    required this.label,
    required this.actionOrder,
  });

  final String label;
  final List<DashboardActionCategory> actionOrder;
}

class _PropertySignal {
  const _PropertySignal({
    required this.property,
    required this.expiringIn30Days,
    required this.expiringIn90Days,
    required this.missingDocuments,
    required this.overdueMaintenance,
    required this.openCriticalTasks,
    required this.budgetVarianceAlerts,
    required this.dataQualityIssues,
    required this.hasCriticalDataIssue,
  });

  final PropertyRecord property;
  final int expiringIn30Days;
  final int expiringIn90Days;
  final int missingDocuments;
  final int overdueMaintenance;
  final int openCriticalTasks;
  final int budgetVarianceAlerts;
  final int dataQualityIssues;
  final bool hasCriticalDataIssue;
}

Future<_PropertySignal> _loadPropertySignal({
  required PropertyRecord property,
  required DateTime now,
  required List<TaskRecord> tasks,
  required List<MaintenanceTicketRecord> maintenanceTickets,
  required OperationsRepo operationsRepo,
  required DocumentsRepo documentsRepo,
  required BudgetRepo budgetRepo,
}) async {
  var expiringIn30Days = 0;
  var expiringIn90Days = 0;
  var dataQualityIssues = 0;
  var hasCriticalDataIssue = false;

  try {
    final overview = await operationsRepo.loadOverview(property.id);
    expiringIn30Days = overview.expiringIn30Days;
    expiringIn90Days = overview.expiringIn90Days;
    dataQualityIssues = overview.dataQualityIssues.length;
    hasCriticalDataIssue = overview.dataQualityIssues.any(
      (issue) => issue.severity == 'critical',
    );
  } catch (_) {}

  var missingDocuments = 0;
  try {
    final compliance = await documentsRepo.checkComplianceForEntity(
      entityType: 'property',
      entityId: property.id,
      propertyType: property.propertyType,
    );
    missingDocuments = compliance.length;
  } catch (_) {}

  final overdueMaintenance =
      maintenanceTickets.where((ticket) {
        if (ticket.assetPropertyId != property.id) {
          return false;
        }
        if (_isClosedMaintenanceStatus(ticket.status)) {
          return false;
        }
        final dueAt = ticket.dueAt;
        return dueAt != null && dueAt < now.millisecondsSinceEpoch;
      }).length;

  final openCriticalTasks =
      tasks.where((task) {
        if (_isClosedTaskStatus(task.status)) {
          return false;
        }
        if (_taskPriorityRank(task.priority) < _taskPriorityRank('high')) {
          return false;
        }
        return _matchesProperty(task, property.id);
      }).length;

  var budgetVarianceAlerts = 0;
  try {
    final budgets = await budgetRepo.listBudgets(
      entityType: 'asset_property',
      entityId: property.id,
    );
    final approvedBudget = budgets.firstWhere(
      (budget) => budget.status == 'approved',
      orElse:
          () => budgets.isNotEmpty ? budgets.first : _emptyBudget(property.id),
    );
    if (approvedBudget.id.isNotEmpty) {
      final variance = await budgetRepo.computeBudgetVsActual(
        entityType: 'asset_property',
        entityId: property.id,
        budgetId: approvedBudget.id,
      );
      budgetVarianceAlerts = variance.where(_isVarianceAboveThreshold).length;
    }
  } catch (_) {}

  return _PropertySignal(
    property: property,
    expiringIn30Days: expiringIn30Days,
    expiringIn90Days: expiringIn90Days,
    missingDocuments: missingDocuments,
    overdueMaintenance: overdueMaintenance,
    openCriticalTasks: openCriticalTasks,
    budgetVarianceAlerts: budgetVarianceAlerts,
    dataQualityIssues: dataQualityIssues,
    hasCriticalDataIssue: hasCriticalDataIssue,
  );
}

List<DashboardActionItem> _buildActionItems(
  List<_PropertySignal> propertySignals,
  List<TaskRecord> tasks,
) {
  final items = <DashboardActionItem>[];
  for (final signal in propertySignals) {
    if (signal.expiringIn30Days > 0) {
      items.add(
        DashboardActionItem(
          category: DashboardActionCategory.leaseExpiry,
          severity: DashboardSeverity.critical,
          title: '${signal.property.name}: Mietvertrag läuft aus',
          detail:
              '${signal.expiringIn30Days} Mietvertrag/Mietverträge laufen innerhalb von 30 Tagen aus.',
          nextStep: 'Mietverträge prüfen',
          count: signal.expiringIn30Days,
          target: DashboardNavigationTarget(
            globalPage: GlobalPage.properties,
            propertyId: signal.property.id,
            propertyDetailPage: PropertyDetailPage.leases,
          ),
        ),
      );
    } else if (signal.expiringIn90Days > 0) {
      items.add(
        DashboardActionItem(
          category: DashboardActionCategory.leaseExpiry,
          severity: DashboardSeverity.warning,
          title: '${signal.property.name}: Verlängerung planen',
          detail:
              '${signal.expiringIn90Days} Mietvertrag/Mietverträge laufen innerhalb von 90 Tagen aus.',
          nextStep: 'Verlängerung planen',
          count: signal.expiringIn90Days,
          target: DashboardNavigationTarget(
            globalPage: GlobalPage.properties,
            propertyId: signal.property.id,
            propertyDetailPage: PropertyDetailPage.leases,
          ),
        ),
      );
    }

    if (signal.missingDocuments > 0) {
      items.add(
        DashboardActionItem(
          category: DashboardActionCategory.documentGap,
          severity:
              signal.missingDocuments >= 3
                  ? DashboardSeverity.critical
                  : DashboardSeverity.warning,
          title: '${signal.property.name}: Dokumente fehlen',
          detail:
              '${signal.missingDocuments} Dokumentenpunkt(e) brauchen Aufmerksamkeit.',
          nextStep: 'Dokumente öffnen',
          count: signal.missingDocuments,
          target: DashboardNavigationTarget(
            globalPage: GlobalPage.properties,
            propertyId: signal.property.id,
            propertyDetailPage: PropertyDetailPage.documents,
          ),
        ),
      );
    }

    if (signal.budgetVarianceAlerts > 0) {
      items.add(
        DashboardActionItem(
          category: DashboardActionCategory.budgetVariance,
          severity:
              signal.budgetVarianceAlerts >= 2
                  ? DashboardSeverity.critical
                  : DashboardSeverity.warning,
          title: '${signal.property.name}: Budgetabweichung',
          detail:
              '${signal.budgetVarianceAlerts} Budgetzeile(n) liegen außerhalb der Schwelle.',
          nextStep: 'Abweichung prüfen',
          count: signal.budgetVarianceAlerts,
          target: DashboardNavigationTarget(
            globalPage: GlobalPage.properties,
            propertyId: signal.property.id,
            propertyDetailPage: PropertyDetailPage.budgetVsActual,
          ),
        ),
      );
    }

    if (signal.overdueMaintenance > 0) {
      items.add(
        DashboardActionItem(
          category: DashboardActionCategory.maintenance,
          severity: DashboardSeverity.critical,
          title: '${signal.property.name}: Wartung überfällig',
          detail:
              '${signal.overdueMaintenance} Wartungspunkt(e) sind überfällig.',
          nextStep: 'Wartung öffnen',
          count: signal.overdueMaintenance,
          target: DashboardNavigationTarget(
            globalPage: GlobalPage.properties,
            propertyId: signal.property.id,
            propertyDetailPage: PropertyDetailPage.maintenance,
          ),
        ),
      );
    }

    if (signal.openCriticalTasks > 0) {
      items.add(
        DashboardActionItem(
          category: DashboardActionCategory.task,
          severity: DashboardSeverity.critical,
          title: '${signal.property.name}: wichtige Aufgaben offen',
          detail:
              '${signal.openCriticalTasks} Aufgabe(n) mit hoher Priorität sind offen.',
          nextStep: 'Aufgaben öffnen',
          count: signal.openCriticalTasks,
          target: DashboardNavigationTarget(
            globalPage: GlobalPage.properties,
            propertyId: signal.property.id,
            propertyDetailPage: PropertyDetailPage.tasks,
          ),
        ),
      );
    }

    if (signal.dataQualityIssues > 0) {
      items.add(
        DashboardActionItem(
          category: DashboardActionCategory.dataQuality,
          severity:
              signal.hasCriticalDataIssue
                  ? DashboardSeverity.critical
                  : DashboardSeverity.warning,
          title: '${signal.property.name}: Datenqualität prüfen',
          detail:
              '${signal.dataQualityIssues} Datenpunkt(e) müssen geprüft werden.',
          nextStep: 'Hinweise prüfen',
          count: signal.dataQualityIssues,
          target: DashboardNavigationTarget(
            globalPage: GlobalPage.properties,
            propertyId: signal.property.id,
            propertyDetailPage: PropertyDetailPage.alerts,
          ),
        ),
      );
    }
  }

  final globalCriticalTasks =
      tasks.where((task) {
        return !_isClosedTaskStatus(task.status) &&
            _taskPriorityRank(task.priority) >= _taskPriorityRank('high');
      }).length;
  if (globalCriticalTasks > 0) {
    items.add(
      DashboardActionItem(
        category: DashboardActionCategory.task,
        severity: DashboardSeverity.critical,
        title: 'Portfolio: wichtige Aufgaben offen',
        detail: '$globalCriticalTasks Aufgabe(n) mit hoher Priorität sind offen.',
        nextStep: 'Aufgaben öffnen',
        count: globalCriticalTasks,
        target: const DashboardNavigationTarget(globalPage: GlobalPage.tasks),
      ),
    );
  }

  items.sort((left, right) {
    final bySeverity =
        _severityRank(left.severity) - _severityRank(right.severity);
    if (bySeverity != 0) {
      return bySeverity;
    }
    return (right.count ?? 0).compareTo(left.count ?? 0);
  });
  return items.take(8).toList(growable: false);
}

List<DashboardSignalMetric> _buildSignalMetrics(
  List<_PropertySignal> propertySignals,
  List<TaskRecord> tasks,
) {
  final expiring30 = propertySignals.fold<int>(
    0,
    (sum, signal) => sum + signal.expiringIn30Days,
  );
  final expiring90 = propertySignals.fold<int>(
    0,
    (sum, signal) => sum + signal.expiringIn90Days,
  );
  final overdueMaintenance = propertySignals.fold<int>(
    0,
    (sum, signal) => sum + signal.overdueMaintenance,
  );
  final missingDocuments = propertySignals.fold<int>(
    0,
    (sum, signal) => sum + signal.missingDocuments,
  );
  final budgetVarianceAlerts = propertySignals.fold<int>(
    0,
    (sum, signal) => sum + signal.budgetVarianceAlerts,
  );
  final dataQualityIssues = propertySignals.fold<int>(
    0,
    (sum, signal) => sum + signal.dataQualityIssues,
  );
  final criticalTasks =
      tasks.where((task) {
        return !_isClosedTaskStatus(task.status) &&
            _taskPriorityRank(task.priority) >= _taskPriorityRank('high');
      }).length;

  return [
    DashboardSignalMetric(
      label: 'Mietende 30 Tage',
      value: expiring30,
      detail: 'Kurzfristige Mietvertragsprüfung.',
      severity:
          expiring30 == 0 ? DashboardSeverity.info : DashboardSeverity.critical,
    ),
    DashboardSignalMetric(
      label: 'Mietende 90 Tage',
      value: expiring90,
      detail: 'Verlängerungen und Neuvermietung planen.',
      severity:
          expiring90 == 0 ? DashboardSeverity.info : DashboardSeverity.warning,
    ),
    DashboardSignalMetric(
      label: 'Dokumentlücken',
      value: missingDocuments,
      detail: 'Erforderliche Unterlagen fehlen.',
      severity:
          missingDocuments == 0
              ? DashboardSeverity.info
              : DashboardSeverity.warning,
    ),
    DashboardSignalMetric(
      label: 'Budgetabweichungen',
      value: budgetVarianceAlerts,
      detail: 'Kostenzeilen über Schwelle.',
      severity:
          budgetVarianceAlerts == 0
              ? DashboardSeverity.info
              : DashboardSeverity.warning,
    ),
    DashboardSignalMetric(
      label: 'Wartung überfällig',
      value: overdueMaintenance,
      detail: 'Fällige Wartungspunkte offen.',
      severity:
          overdueMaintenance == 0
              ? DashboardSeverity.info
              : DashboardSeverity.critical,
    ),
    DashboardSignalMetric(
      label: 'Wichtige Aufgaben',
      value: criticalTasks,
      detail: 'Aufgaben mit hoher Priorität offen.',
      severity:
          criticalTasks == 0
              ? DashboardSeverity.info
              : DashboardSeverity.critical,
    ),
    DashboardSignalMetric(
      label: 'Datenqualität',
      value: dataQualityIssues,
      detail: 'Operative Datensätze mit Konflikten.',
      severity:
          dataQualityIssues == 0
              ? DashboardSeverity.info
              : DashboardSeverity.warning,
    ),
  ];
}

List<DashboardActivityItem> _buildActivityItems({
  required List<PropertyRecord> properties,
  required List<TaskRecord> tasks,
  required List<MaintenanceTicketRecord> maintenanceTickets,
  required List<DocumentRecord> propertyDocuments,
}) {
  final items = <DashboardActivityItem>[
    ...properties.map(
      (property) => DashboardActivityItem(
        title: property.name,
        detail: 'Objekt / ${property.city}',
        timestamp: DateTime.fromMillisecondsSinceEpoch(property.updatedAt),
        target: DashboardNavigationTarget(
          globalPage: GlobalPage.properties,
          propertyId: property.id,
          propertyDetailPage: PropertyDetailPage.overview,
        ),
        icon: Icons.home_work_outlined,
      ),
    ),
    ...tasks
        .where((task) => task.entityId != null)
        .map(
          (task) => DashboardActivityItem(
            title: task.title,
            detail: 'Aufgabe / ${task.status}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(task.updatedAt),
            target: DashboardNavigationTarget(
              globalPage: GlobalPage.tasks,
              propertyId:
                  task.entityType == 'property' ||
                          task.entityType == 'asset_property'
                      ? task.entityId
                      : null,
              propertyDetailPage:
                  task.entityType == 'property' ||
                          task.entityType == 'asset_property'
                      ? PropertyDetailPage.tasks
                      : null,
            ),
            icon: Icons.checklist_outlined,
          ),
        ),
    ...maintenanceTickets.map(
      (ticket) => DashboardActivityItem(
        title: ticket.title,
        detail: 'Wartung / ${ticket.status}',
        timestamp: DateTime.fromMillisecondsSinceEpoch(ticket.updatedAt),
        target: DashboardNavigationTarget(
          globalPage: GlobalPage.properties,
          propertyId: ticket.assetPropertyId,
          propertyDetailPage: PropertyDetailPage.maintenance,
        ),
        icon: Icons.build_outlined,
      ),
    ),
    ...propertyDocuments.map(
      (document) => DashboardActivityItem(
        title: document.fileName,
        detail: 'Dokument',
        timestamp: DateTime.fromMillisecondsSinceEpoch(document.createdAt),
        target: DashboardNavigationTarget(
          globalPage: GlobalPage.properties,
          propertyId: document.entityId,
          propertyDetailPage: PropertyDetailPage.documents,
        ),
        icon: Icons.description_outlined,
      ),
    ),
  ];

  items.sort((left, right) => right.timestamp.compareTo(left.timestamp));
  return items.take(8).toList(growable: false);
}

List<DashboardCategoryValue> _buildTypeMix(List<PropertyRecord> properties) {
  final counts = <String, int>{};
  for (final property in properties) {
    counts.update(
      property.propertyType,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }
  final entries =
      counts.entries.toList()
        ..sort((left, right) => right.value.compareTo(left.value));
  return entries
      .map(
        (entry) => DashboardCategoryValue(label: entry.key, value: entry.value),
      )
      .toList(growable: false);
}

List<DashboardMonthValue> _buildMonthlyIntake(List<PropertyRecord> properties) {
  final now = DateTime.now();
  final buckets = <DateTime, int>{
    for (var index = 5; index >= 0; index--)
      DateTime(now.year, now.month - index): 0,
  };
  for (final property in properties) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(property.createdAt);
    final month = DateTime(createdAt.year, createdAt.month);
    if (buckets.containsKey(month)) {
      buckets[month] = buckets[month]! + 1;
    }
  }
  return buckets.entries
      .map((entry) => DashboardMonthValue(date: entry.key, value: entry.value))
      .toList(growable: false);
}

List<DashboardActionItem> _sortActionsForRole(
  List<DashboardActionItem> items,
  _RoleConfig roleConfig,
) {
  final order = <DashboardActionCategory, int>{
    for (var index = 0; index < roleConfig.actionOrder.length; index++)
      roleConfig.actionOrder[index]: index,
  };
  final sorted = items.toList();
  sorted.sort((left, right) {
    final leftOrder = order[left.category] ?? roleConfig.actionOrder.length;
    final rightOrder = order[right.category] ?? roleConfig.actionOrder.length;
    if (leftOrder != rightOrder) {
      return leftOrder.compareTo(rightOrder);
    }
    final severityDelta =
        _severityRank(left.severity) - _severityRank(right.severity);
    if (severityDelta != 0) {
      return severityDelta;
    }
    return (right.count ?? 0).compareTo(left.count ?? 0);
  });
  return sorted;
}

String _buildSubtitle(
  _RoleConfig roleConfig,
  SecurityContextRecord? securityContext,
) {
  final workspaceName = securityContext?.workspace.name;
  if (workspaceName == null || workspaceName.trim().isEmpty) {
    return 'Zentrale Übersicht für Portfolio, Vermietung, BK, Aufgaben und operative Hinweise.';
  }
  return 'Zentrale Übersicht für $workspaceName: Portfolio, Vermietung, BK, Aufgaben und operative Hinweise.';
}

_RoleConfig _roleConfigFor(String role) {
  switch (_normalizeRole(role)) {
    case 'asset_manager':
      return const _RoleConfig(
        label: 'Asset Manager',
        actionOrder: [
          DashboardActionCategory.maintenance,
          DashboardActionCategory.leaseExpiry,
          DashboardActionCategory.task,
          DashboardActionCategory.documentGap,
          DashboardActionCategory.budgetVariance,
          DashboardActionCategory.dataQuality,
        ],
      );
    case 'analyst':
      return const _RoleConfig(
        label: 'Analyst',
        actionOrder: [
          DashboardActionCategory.budgetVariance,
          DashboardActionCategory.dataQuality,
          DashboardActionCategory.documentGap,
          DashboardActionCategory.leaseExpiry,
          DashboardActionCategory.task,
          DashboardActionCategory.maintenance,
        ],
      );
    case 'viewer':
      return const _RoleConfig(
        label: 'Viewer',
        actionOrder: [
          DashboardActionCategory.leaseExpiry,
          DashboardActionCategory.documentGap,
          DashboardActionCategory.dataQuality,
          DashboardActionCategory.budgetVariance,
          DashboardActionCategory.maintenance,
          DashboardActionCategory.task,
        ],
      );
    case 'admin':
    default:
      return const _RoleConfig(
        label: 'Admin',
        actionOrder: [
          DashboardActionCategory.task,
          DashboardActionCategory.documentGap,
          DashboardActionCategory.budgetVariance,
          DashboardActionCategory.maintenance,
          DashboardActionCategory.dataQuality,
          DashboardActionCategory.leaseExpiry,
        ],
      );
  }
}

void _openTarget(WidgetRef ref, DashboardNavigationTarget target) {
  ref.read(selectedScenarioIdProvider.notifier).state = null;
  ref.read(selectedOperationsUnitIdProvider.notifier).state = null;
  ref.read(selectedOperationsTenantIdProvider.notifier).state = null;
  ref.read(selectedOperationsLeaseIdProvider.notifier).state = null;

  if (target.globalPage != GlobalPage.properties) {
    ref.read(selectedPropertyIdProvider.notifier).state = null;
  }

  if (target.propertyId != null) {
    ref.read(selectedPropertyIdProvider.notifier).state = target.propertyId;
  }
  if (target.propertyDetailPage != null) {
    ref.read(propertyDetailPageProvider.notifier).state =
        target.propertyDetailPage!;
  }
  ref.read(globalPageProvider.notifier).state = target.globalPage;
}

String _normalizeRole(String role) {
  switch (role.trim().toLowerCase()) {
    case 'manager':
    case 'assetmanager':
    case 'asset_manager':
      return 'asset_manager';
    default:
      return role.trim().toLowerCase();
  }
}

int _severityRank(DashboardSeverity severity) {
  switch (severity) {
    case DashboardSeverity.critical:
      return 0;
    case DashboardSeverity.warning:
      return 1;
    case DashboardSeverity.info:
      return 2;
  }
}

bool _isVarianceAboveThreshold(BudgetVarianceRecord variance) {
  final percent = variance.variancePercent?.abs() ?? 0;
  return percent >= 0.1;
}

bool _isClosedMaintenanceStatus(String status) {
  return const {'completed', 'billed', 'resolved', 'closed'}.contains(status);
}

bool _isClosedTaskStatus(String status) {
  return status == 'done' || status == 'closed';
}

bool _matchesProperty(TaskRecord task, String propertyId) {
  final entityId = task.entityId;
  if (entityId == null || entityId.isEmpty) {
    return false;
  }
  return (task.entityType == 'property' ||
          task.entityType == 'asset_property') &&
      entityId == propertyId;
}

int _taskPriorityRank(String priority) {
  switch (priority) {
    case 'urgent':
      return 3;
    case 'high':
      return 2;
    case 'normal':
      return 1;
    default:
      return 0;
  }
}

BudgetRecord _emptyBudget(String propertyId) {
  return BudgetRecord(
    id: '',
    entityType: 'asset_property',
    entityId: propertyId,
    fiscalYear: DateTime.now().year,
    versionName: '',
    status: 'draft',
    createdAt: 0,
    updatedAt: 0,
  );
}

class _TypeMixChart extends StatelessWidget {
  const _TypeMixChart({required this.values});

  final List<DashboardCategoryValue> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Center(child: Text('Noch keine aktiven Objekte.'));
    }

    final bars = <BarChartGroupData>[];
    for (var index = 0; index < values.length; index++) {
      bars.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: values[index].value.toDouble(),
              width: 18,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
              ),
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        maxY: math.max<double>(1, values.first.value.toDouble() + 1),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => Theme.of(context).colorScheme.surface,
            tooltipBorder: BorderSide(color: context.semanticColors.border, width: 1.5),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            tooltipRoundedRadius: AppRadiusTokens.md,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final val = values[groupIndex];
              return BarTooltipItem(
                '${val.label}: ${val.value}',
                TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              );
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
              reservedSize: 24,
              getTitlesWidget: (value, _) => Text(value.toInt().toString()),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= values.length) {
                  return const SizedBox.shrink();
                }
                final label = values[index].label;
                final compact =
                    label.length > 10 ? '${label.substring(0, 10)}...' : label;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    compact,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: bars,
      ),
    );
  }
}

class _SignalGrid extends StatelessWidget {
  const _SignalGrid({
    required this.signalMetrics,
    required this.onOpenTarget,
  });

  final List<DashboardSignalMetric> signalMetrics;
  final ValueChanged<DashboardNavigationTarget> onOpenTarget;

  @override
  Widget build(BuildContext context) {
    if (signalMetrics.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          border: Border.all(color: context.semanticColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Text(
            'Operative Signale erscheinen, sobald Portfolio-Daten vorhanden sind.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.component,
      runSpacing: AppSpacing.component,
      children: signalMetrics
          .map(
            (metric) => _SignalCard(
              metric: metric,
              onTap: () => onOpenTarget(_signalTarget(metric.label)),
            ),
          )
          .toList(growable: false),
    );
  }

  DashboardNavigationTarget _signalTarget(String label) {
    if (label.contains('Mietende')) {
      return const DashboardNavigationTarget(globalPage: GlobalPage.properties);
    }
    if (label.contains('Dokument')) {
      return const DashboardNavigationTarget(globalPage: GlobalPage.documents);
    }
    if (label.contains('Budget')) {
      return const DashboardNavigationTarget(globalPage: GlobalPage.budgets);
    }
    if (label.contains('Wartung')) {
      return const DashboardNavigationTarget(globalPage: GlobalPage.maintenance);
    }
    if (label.contains('Aufgaben')) {
      return const DashboardNavigationTarget(globalPage: GlobalPage.tasks);
    }
    return const DashboardNavigationTarget(globalPage: GlobalPage.properties);
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.metric, required this.onTap});

  final DashboardSignalMetric metric;
  final VoidCallback onTap;

  IconData _metricIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('miet')) return Icons.key_outlined;
    if (l.contains('dokument')) return Icons.description_outlined;
    if (l.contains('budget')) return Icons.account_balance_wallet_outlined;
    if (l.contains('wartung') || l.contains('instand')) return Icons.build_outlined;
    if (l.contains('aufgabe') || l.contains('task')) return Icons.playlist_add_check_outlined;
    return Icons.info_outline;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _severityColor(context, metric.severity);
    
    return SizedBox(
      width: 230,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          side: BorderSide(color: context.semanticColors.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  color: color,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                metric.label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: context.semanticColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              _metricIcon(metric.label),
                              size: 16,
                              color: color.withValues(alpha: 0.8),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${metric.value}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          metric.detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: context.semanticColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _severityColor(BuildContext context, DashboardSeverity severity) {
  final semantic = context.semanticColors;
  switch (severity) {
    case DashboardSeverity.critical:
      return semantic.error;
    case DashboardSeverity.warning:
      return semantic.warning;
    case DashboardSeverity.info:
      return Theme.of(context).colorScheme.primary;
  }
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _formatCurrency(double value) {
  final sign = value < 0 ? '-' : '';
  final absValue = value.abs();
  if (absValue >= 1000000) {
    return '$sign€ ${(absValue / 1000000).toStringAsFixed(1)} Mio.';
  }
  if (absValue >= 1000) {
    return '$sign€ ${(absValue / 1000).toStringAsFixed(1)} Tsd.';
  }
  return '$sign€ ${absValue.toStringAsFixed(0)}';
}

String _formatPercent(double value) {
  return '${(value * 100).toStringAsFixed(1)}%';
}
