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
import '../../components/nx_status_badge.dart';
import '../../state/app_state.dart';
import '../../state/property_state.dart';
import '../../theme/app_theme.dart';

/// Data model, local aggregation and shared helpers for the dashboard
/// (SCR-004, BIG-007 split). The presentation lives in the sibling
/// `dashboard_*` widgets; `dashboard_screen.dart` re-exports this library so
/// existing imports keep resolving. The aggregation contract is unchanged —
/// a single [dashboardOverviewProvider] `AsyncValue`, no per-tile providers.

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

/// Estimated 12-month portfolio value trend derived from the overview's net
/// operating result — pure presentation logic shared by the trend chart.
List<DashboardValuePoint> buildDashboardValuationTrend(
  DashboardOverviewData overview,
) {
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

class DashboardRoleConfig {
  const DashboardRoleConfig({required this.label, required this.actionOrder});

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

/// Reorders the attention items by the active role's priority, keeping the
/// severity/count tiebreak — role-based content filtering is unchanged.
List<DashboardActionItem> sortActionsForRole(
  List<DashboardActionItem> items,
  DashboardRoleConfig roleConfig,
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

String buildDashboardSubtitle(
  DashboardRoleConfig roleConfig,
  SecurityContextRecord? securityContext,
) {
  final workspaceName = securityContext?.workspace.name;
  if (workspaceName == null || workspaceName.trim().isEmpty) {
    return 'Zentrale Übersicht für Portfolio, Vermietung, BK, Aufgaben und operative Hinweise.';
  }
  return 'Zentrale Übersicht für $workspaceName: Portfolio, Vermietung, BK, Aufgaben und operative Hinweise.';
}

DashboardRoleConfig roleConfigFor(String role) {
  switch (_normalizeRole(role)) {
    case 'asset_manager':
      return const DashboardRoleConfig(
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
      return const DashboardRoleConfig(
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
      return const DashboardRoleConfig(
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
      return const DashboardRoleConfig(
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

void openDashboardTarget(WidgetRef ref, DashboardNavigationTarget target) {
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

/// Severity accent color for attention/alert affordances (border/tint use,
/// never a drop shadow).
Color dashboardSeverityColor(BuildContext context, DashboardSeverity severity) {
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

/// Badge kind + label pair the attention list uses so severity is never
/// signaled by color alone (accessibility rule from the design system).
NxBadgeKind dashboardSeverityBadgeKind(DashboardSeverity severity) {
  switch (severity) {
    case DashboardSeverity.critical:
      return NxBadgeKind.error;
    case DashboardSeverity.warning:
      return NxBadgeKind.warning;
    case DashboardSeverity.info:
      return NxBadgeKind.info;
  }
}

String dashboardSeverityLabel(DashboardSeverity severity) {
  switch (severity) {
    case DashboardSeverity.critical:
      return 'Kritisch';
    case DashboardSeverity.warning:
      return 'Warnung';
    case DashboardSeverity.info:
      return 'Hinweis';
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

String formatDashboardDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String formatDashboardCurrency(double value) {
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

String formatDashboardPercent(double value) {
  return '${(value * 100).toStringAsFixed(1)}%';
}
