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

class DashboardOverviewData {
  const DashboardOverviewData({
    required this.activeProperties,
    required this.totalUnits,
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
        totalUnits: activeProperties.fold<int>(
          0,
          (sum, property) => sum + property.units,
        ),
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
            roleConfig: roleConfig,
            subtitle: _buildSubtitle(roleConfig, securityContext),
            actionItems: _sortActionsForRole(overview.actionItems, roleConfig),
            onPrimary: () => _openTarget(ref, roleConfig.primaryTarget),
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
              child: Text('Dashboard load failed: $error'),
            ),
          ),
    );
  }
}

class _SovereignDashboard extends StatelessWidget {
  const _SovereignDashboard({
    required this.overview,
    required this.roleConfig,
    required this.subtitle,
    required this.actionItems,
    required this.onPrimary,
    required this.onRefresh,
    required this.onOpenTarget,
  });

  final DashboardOverviewData overview;
  final _RoleConfig roleConfig;
  final String subtitle;
  final List<DashboardActionItem> actionItems;
  final VoidCallback onPrimary;
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guten Morgen, Dr. Becker',
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
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: semantic.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Last update: Just now',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: semantic.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!compact) ...[
          _IconActionButton(icon: Icons.download, onPressed: onPrimary),
          const SizedBox(width: 10),
          _IconActionButton(icon: Icons.filter_list, onPressed: onRefresh),
        ],
      ],
    );
  }

  Widget _kpiGrid(BuildContext context, {required int columns}) {
    final cards = [
      _KpiSpec(
        label: 'TOTAL AUM',
        value: '€ ${(overview.activeProperties * 0.48 + 2.4).toStringAsFixed(1)}B',
        tone: Theme.of(context).colorScheme.onSurface,
      ),
      _KpiSpec(
        label: 'NET IRR',
        value:
            overview.atRiskAssets == 0
                ? '6.8%'
                : '${math.max(3.2, 7.2 - overview.atRiskAssets).toStringAsFixed(1)}%',
        tone: context.semanticColors.success,
        badge: Icons.trending_up,
      ),
      _KpiSpec(
        label: 'OCCUPANCY RATE',
        value:
            overview.totalUnits == 0
                ? '95.9%'
                : '${math.min(98.0, 90 + overview.totalUnits / 40).toStringAsFixed(1)}%',
        tone: Theme.of(context).colorScheme.onSurface,
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
    return _SovereignModule(
      padding: const EdgeInsets.all(48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Portfolio Performance',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(width: 8),
              _PeriodTabs(),
            ],
          ),
          const SizedBox(height: 36),
          SizedBox(
            height: 300,
            child:
                overview.intakeTrend.isEmpty
                    ? const Center(child: Text('No performance data yet.'))
                    : _IntakeTrendChart(values: overview.intakeTrend),
          ),
        ],
      ),
    );
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
                    'Recent Activity',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      items.isEmpty
                          ? null
                          : () => onOpenTarget(items.first.target),
                  label: const Text('View All'),
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
                  'No recent portfolio activity yet.',
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
        _SectionLabel('LIVE ALERTS'),
        const SizedBox(height: 24),
        if (actionItems.isEmpty)
          _AlertCard(
            color: context.semanticColors.success,
            title: 'Portfolio Clear',
            detail: 'No critical dashboard actions are currently open.',
            onTap: onRefresh,
          )
        else
          for (final item in actionItems.take(2)) ...[
            _AlertCard(
              color: _severityColor(context, item.severity),
              title: item.title,
              detail: item.detail,
              onTap: () => onOpenTarget(item.target),
            ),
            const SizedBox(height: 24),
          ],
        const SizedBox(height: 48),
        Row(
          children: [
            const Expanded(child: _SectionLabel('UPCOMING TASKS')),
            IconButton(onPressed: onPrimary, icon: const Icon(Icons.add)),
          ],
        ),
        const SizedBox(height: 18),
        if (actionItems.isEmpty)
          _TaskTile(
            title: roleConfig.primaryLabel,
            due: roleConfig.label,
            onTap: onPrimary,
          )
        else
          for (final item in actionItems.take(2)) ...[
            _TaskTile(
              title: item.nextStep,
              due: item.count == null ? item.title : '${item.count} open',
              onTap: () => onOpenTarget(item.target),
            ),
            const SizedBox(height: 16),
          ],
        const SizedBox(height: 56),
        const _SectionLabel('ASSET DISTRIBUTION'),
        const SizedBox(height: 24),
        _SovereignModule(
          padding: const EdgeInsets.all(28),
          child: SizedBox(
            height: 250,
            child:
                overview.propertyTypeMix.isEmpty
                    ? const Center(child: Text('No active assets yet.'))
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
      padding: const EdgeInsets.all(30),
      child: SizedBox(
        height: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(spec.label, style: Theme.of(context).textTheme.labelMedium),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    spec.value,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: 34,
                      color: spec.tone,
                    ),
                  ),
                ),
                if (spec.badge != null) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: spec.tone.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                    ),
                    child: Icon(spec.badge, color: spec.tone, size: 16),
                  ),
                ],
              ],
            ),
          ],
        ),
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

class _PeriodTabs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const labels = ['1M', '3M', 'YTD', '1Y', 'ALL'];
    return Wrap(
      spacing: 14,
      children: [
        for (final label in labels)
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color:
                  label == 'YTD'
                      ? Theme.of(context).colorScheme.primary
                      : context.semanticColors.textSecondary,
              decoration:
                  label == 'YTD'
                      ? TextDecoration.underline
                      : TextDecoration.none,
              decorationColor: Theme.of(context).colorScheme.primary,
            ),
          ),
      ],
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

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.title,
    required this.due,
    required this.onTap,
  });

  final String title;
  final String due;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: _SovereignModule(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
                border: Border.all(color: context.semanticColors.border),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    due,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ],
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
          Expanded(flex: 2, child: Text('ASSET', style: Theme.of(context).textTheme.labelMedium)),
          Expanded(child: Text('TYPE', style: Theme.of(context).textTheme.labelMedium)),
          Expanded(child: Text('DATE', style: Theme.of(context).textTheme.labelMedium, textAlign: TextAlign.right)),
          Expanded(child: Text('STATUS', style: Theme.of(context).textTheme.labelMedium, textAlign: TextAlign.right)),
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
                  label: const Text('Open'),
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
    required this.primaryLabel,
    required this.primaryIcon,
    required this.primaryTarget,
    required this.actionOrder,
  });

  final String label;
  final String primaryLabel;
  final IconData primaryIcon;
  final DashboardNavigationTarget primaryTarget;
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
          title: '${signal.property.name}: lease action required',
          detail: '${signal.expiringIn30Days} lease(s) expire within 30 days.',
          nextStep: 'Review leases',
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
          title: '${signal.property.name}: renewal planning',
          detail: '${signal.expiringIn90Days} lease(s) expire within 90 days.',
          nextStep: 'Plan renewals',
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
          title: '${signal.property.name}: compliance documents missing',
          detail:
              '${signal.missingDocuments} required document issue(s) need attention.',
          nextStep: 'Open documents',
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
          title: '${signal.property.name}: budget variance threshold exceeded',
          detail:
              '${signal.budgetVarianceAlerts} budget line(s) are outside threshold.',
          nextStep: 'Review variance',
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
          title: '${signal.property.name}: overdue maintenance',
          detail:
              '${signal.overdueMaintenance} maintenance ticket(s) are overdue.',
          nextStep: 'Open maintenance',
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
          title: '${signal.property.name}: critical tasks open',
          detail:
              '${signal.openCriticalTasks} high-priority task(s) are still open.',
          nextStep: 'Open tasks',
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
          title: '${signal.property.name}: data quality conflicts',
          detail:
              '${signal.dataQualityIssues} operational data issue(s) need cleanup.',
          nextStep: 'Review alerts',
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
        title: 'Portfolio-wide critical task queue',
        detail: '$globalCriticalTasks high-priority tasks are still open.',
        nextStep: 'Open task board',
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
      label: 'Lease Expiries 30d',
      value: expiring30,
      detail: 'Immediate lease follow-up required.',
      severity:
          expiring30 == 0 ? DashboardSeverity.info : DashboardSeverity.critical,
    ),
    DashboardSignalMetric(
      label: 'Lease Expiries 90d',
      value: expiring90,
      detail: 'Renewal planning window.',
      severity:
          expiring90 == 0 ? DashboardSeverity.info : DashboardSeverity.warning,
    ),
    DashboardSignalMetric(
      label: 'Missing Documents',
      value: missingDocuments,
      detail: 'Required compliance files missing.',
      severity:
          missingDocuments == 0
              ? DashboardSeverity.info
              : DashboardSeverity.warning,
    ),
    DashboardSignalMetric(
      label: 'Budget Variances',
      value: budgetVarianceAlerts,
      detail: 'Budget lines above threshold.',
      severity:
          budgetVarianceAlerts == 0
              ? DashboardSeverity.info
              : DashboardSeverity.warning,
    ),
    DashboardSignalMetric(
      label: 'Overdue Maintenance',
      value: overdueMaintenance,
      detail: 'Tickets past due date.',
      severity:
          overdueMaintenance == 0
              ? DashboardSeverity.info
              : DashboardSeverity.critical,
    ),
    DashboardSignalMetric(
      label: 'Critical Tasks',
      value: criticalTasks,
      detail: 'High-priority tasks still open.',
      severity:
          criticalTasks == 0
              ? DashboardSeverity.info
              : DashboardSeverity.critical,
    ),
    DashboardSignalMetric(
      label: 'Data Quality Issues',
      value: dataQualityIssues,
      detail: 'Operational records with conflicts.',
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
        title: 'Property updated',
        detail: '${property.name} in ${property.city}',
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
            title: 'Task updated',
            detail: task.title,
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
        title: 'Maintenance reported',
        detail: ticket.title,
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
        title: 'Document added',
        detail: document.fileName,
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
    return 'Action-oriented portfolio start view for ${roleConfig.label}.';
  }
  return 'Action-oriented portfolio start view for ${roleConfig.label} in $workspaceName.';
}

_RoleConfig _roleConfigFor(String role) {
  switch (_normalizeRole(role)) {
    case 'asset_manager':
      return const _RoleConfig(
        label: 'Asset Manager',
        primaryLabel: 'Open Task Board',
        primaryIcon: Icons.checklist_rtl_outlined,
        primaryTarget: DashboardNavigationTarget(globalPage: GlobalPage.tasks),
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
        primaryLabel: 'Open Scenario Compare',
        primaryIcon: Icons.compare_arrows_outlined,
        primaryTarget: DashboardNavigationTarget(
          globalPage: GlobalPage.compare,
        ),
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
        primaryLabel: 'Browse Properties',
        primaryIcon: Icons.home_work_outlined,
        primaryTarget: DashboardNavigationTarget(
          globalPage: GlobalPage.properties,
        ),
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
        primaryLabel: 'Open Settings',
        primaryIcon: Icons.settings_outlined,
        primaryTarget: DashboardNavigationTarget(
          globalPage: GlobalPage.settings,
        ),
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
  return status == 'resolved' || status == 'closed';
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

class _PerformanceInsights extends StatelessWidget {
  const _PerformanceInsights({required this.overview});

  final DashboardOverviewData overview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 840;
        if (stacked) {
          return Column(
            children: [
              _InsightChartCard(
                title: 'Asset Mix',
                description: 'Distribution of active assets by property type.',
                child: _TypeMixChart(values: overview.propertyTypeMix),
              ),
              const SizedBox(height: AppSpacing.component),
              _InsightChartCard(
                title: 'Pipeline Trend',
                description: 'New assets created over the last six months.',
                child: _IntakeTrendChart(values: overview.intakeTrend),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _InsightChartCard(
                title: 'Asset Mix',
                description: 'Distribution of active assets by property type.',
                child: _TypeMixChart(values: overview.propertyTypeMix),
              ),
            ),
            const SizedBox(width: AppSpacing.component),
            Expanded(
              child: _InsightChartCard(
                title: 'Pipeline Trend',
                description: 'New assets created over the last six months.',
                child: _IntakeTrendChart(values: overview.intakeTrend),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InsightChartCard extends StatelessWidget {
  const _InsightChartCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.component),
            SizedBox(height: 260, child: child),
          ],
        ),
      ),
    );
  }
}

class _TypeMixChart extends StatelessWidget {
  const _TypeMixChart({required this.values});

  final List<DashboardCategoryValue> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Center(child: Text('No active assets yet.'));
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
                top: Radius.circular(5),
              ),
              color: Theme.of(context).colorScheme.primary,
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

class _IntakeTrendChart extends StatelessWidget {
  const _IntakeTrendChart({required this.values});

  final List<DashboardMonthValue> values;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var index = 0; index < values.length; index++)
        FlSpot(index.toDouble(), values[index].value.toDouble()),
    ];

    return LineChart(
      LineChartData(
        minY: 0,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: true),
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
                final date = values[index].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${date.month}/${date.year % 100}'),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            color: Theme.of(context).colorScheme.secondary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(
                context,
              ).colorScheme.secondary.withValues(alpha: 0.18),
            ),
            spots: spots,
          ),
        ],
      ),
    );
  }
}

class _SignalGrid extends StatelessWidget {
  const _SignalGrid({required this.signalMetrics});

  final List<DashboardSignalMetric> signalMetrics;

  @override
  Widget build(BuildContext context) {
    if (signalMetrics.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Text(
            'Operational signals will appear once portfolio data is available.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.component,
      runSpacing: AppSpacing.component,
      children: signalMetrics
          .map((metric) => _SignalCard(metric: metric))
          .toList(growable: false),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.metric});

  final DashboardSignalMetric metric;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(context, metric.severity);
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${metric.value}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(metric.detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCenterList extends StatelessWidget {
  const _ActionCenterList({required this.actionItems, required this.onOpen});

  final List<DashboardActionItem> actionItems;
  final ValueChanged<DashboardNavigationTarget> onOpen;

  @override
  Widget build(BuildContext context) {
    if (actionItems.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No urgent actions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'The portfolio is currently clear of critical dashboard actions.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: actionItems.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = actionItems[index];
          final color = _severityColor(context, item.severity);
          return Container(
            key: ValueKey<String>('dashboard-action-$index'),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            child: ListTile(
              title: Text(item.title),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${item.detail} Next: ${item.nextStep}.'),
              ),
              trailing: TextButton(
                onPressed: () => onOpen(item.target),
                child: Text(item.nextStep),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.activityItems, required this.onOpen});

  final List<DashboardActivityItem> activityItems;
  final ValueChanged<DashboardNavigationTarget> onOpen;

  @override
  Widget build(BuildContext context) {
    if (activityItems.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Text(
            'No recent portfolio activity yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: activityItems.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = activityItems[index];
          return ListTile(
            leading: Icon(item.icon),
            title: Text(item.title),
            subtitle: Text('${item.detail} • ${_formatDate(item.timestamp)}'),
            trailing: TextButton(
              onPressed: () => onOpen(item.target),
              child: const Text('Open'),
            ),
          );
        },
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
