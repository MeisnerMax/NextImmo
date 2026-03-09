import '../models/operations.dart';

class OperationsDataQualityEngine {
  const OperationsDataQualityEngine({
    this.vacancyAlertThreshold = const Duration(days: 45),
    this.rentRollStaleThreshold = const Duration(days: 92),
  });

  final Duration vacancyAlertThreshold;
  final Duration rentRollStaleThreshold;

  List<OperationsDataQualityIssue> evaluate({
    required String propertyId,
    required List<UnitRecord> units,
    required List<LeaseRecord> leases,
    required Map<String, TenantRecord> tenantsById,
    required List<RentRollSnapshotRecord> snapshots,
    DateTime? now,
  }) {
    final issues = <OperationsDataQualityIssue>[];
    final clock = now ?? DateTime.now();
    final activeLeasesByUnit = _activeLeasesByUnit(leases, clock);
    final unitsById = <String, UnitRecord>{
      for (final unit in units) unit.id: unit,
    };

    for (final unit in units) {
      if (unit.unitCode.trim().isEmpty) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'missing_unit_code',
            severity: 'warning',
            message: 'A unit is missing its unit number or name.',
            recommendedAction: 'Enter a unit number to keep lists and rent roll readable.',
            propertyId: propertyId,
            unitId: unit.id,
          ),
        );
      }
      if (unit.status == 'offline' &&
          (unit.offlineReason == null || unit.offlineReason!.trim().isEmpty)) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'offline_missing_reason',
            severity: 'critical',
            message: 'Unit ${unit.unitCode} is offline without a reason.',
            recommendedAction: 'Add the offline reason before the unit disappears from normal operations.',
            propertyId: propertyId,
            unitId: unit.id,
          ),
        );
      }
      if (unit.status == 'vacant' && unit.vacancySince == null) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'vacancy_missing_since',
            severity: 'warning',
            message: 'Unit ${unit.unitCode} is vacant without vacancy date.',
            recommendedAction: 'Set the vacancy start date so vacancy aging can be tracked.',
            propertyId: propertyId,
            unitId: unit.id,
          ),
        );
      }
      if (unit.status == 'vacant' && unit.vacancySince != null) {
        final vacancyDate = DateTime.fromMillisecondsSinceEpoch(unit.vacancySince!);
        if (clock.difference(DateTime(vacancyDate.year, vacancyDate.month, vacancyDate.day)) >=
            vacancyAlertThreshold) {
          issues.add(
            OperationsDataQualityIssue(
              type: 'vacancy_aged',
              severity: 'warning',
              message:
                  'Unit ${unit.unitCode} has been vacant for ${clock.difference(vacancyDate).inDays} days.',
              recommendedAction: 'Review marketing status, target rent and next action for this vacancy.',
              propertyId: propertyId,
              unitId: unit.id,
            ),
          );
        }
      }

      final activeLeases = activeLeasesByUnit[unit.id] ?? const <LeaseRecord>[];
      if (unit.status == 'occupied' && activeLeases.isEmpty) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'occupied_without_active_lease',
            severity: 'critical',
            message: 'Unit ${unit.unitCode} is occupied without an active lease.',
            recommendedAction: 'Create or reactivate the lease before rent roll or reports diverge.',
            propertyId: propertyId,
            unitId: unit.id,
          ),
        );
      }
      if (unit.status == 'vacant' && activeLeases.isNotEmpty) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'vacant_with_active_lease',
            severity: 'critical',
            message: 'Unit ${unit.unitCode} is vacant but still has an active lease.',
            recommendedAction: 'End the lease or correct the unit status.',
            propertyId: propertyId,
            unitId: unit.id,
            leaseId: activeLeases.first.id,
            tenantId: activeLeases.first.tenantId,
          ),
        );
      }
    }

    for (final lease in leases) {
      if (lease.leaseName.trim().isEmpty) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'missing_lease_name',
            severity: 'warning',
            message: 'A lease is missing its lease name.',
            recommendedAction: 'Add a recognizable lease name for search and reporting.',
            propertyId: propertyId,
            leaseId: lease.id,
            unitId: lease.unitId,
            tenantId: lease.tenantId,
          ),
        );
      }
      if (!unitsById.containsKey(lease.unitId)) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'orphan_lease_unit',
            severity: 'critical',
            message: 'Lease ${lease.leaseName} points to a missing unit.',
            recommendedAction: 'Reconnect the lease to a valid unit or archive the broken record.',
            propertyId: propertyId,
            leaseId: lease.id,
            unitId: lease.unitId,
            tenantId: lease.tenantId,
          ),
        );
      }
      if (lease.tenantId != null && !tenantsById.containsKey(lease.tenantId)) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'orphan_lease_tenant',
            severity: 'critical',
            message: 'Lease ${lease.leaseName} points to a missing tenant.',
            recommendedAction: 'Reconnect the lease to a tenant or clean up the broken reference.',
            propertyId: propertyId,
            leaseId: lease.id,
            unitId: lease.unitId,
            tenantId: lease.tenantId,
          ),
        );
      }
      if (lease.endDate != null && lease.endDate! < lease.startDate) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'lease_end_before_start',
            severity: 'critical',
            message: 'Lease ${lease.leaseName} ends before it starts.',
            recommendedAction: 'Correct the lease dates before saving reports or rent roll snapshots.',
            propertyId: propertyId,
            leaseId: lease.id,
            unitId: lease.unitId,
            tenantId: lease.tenantId,
          ),
        );
      }
      if (lease.securityDeposit != null && lease.securityDeposit! < 0) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'deposit_below_zero',
            severity: 'critical',
            message: 'Lease ${lease.leaseName} has a negative deposit.',
            recommendedAction: 'Enter a non-negative deposit amount.',
            propertyId: propertyId,
            leaseId: lease.id,
            unitId: lease.unitId,
            tenantId: lease.tenantId,
          ),
        );
      }
      if (lease.status == 'active' &&
          (lease.securityDeposit == null || lease.securityDeposit == 0)) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'missing_deposit',
            severity: 'warning',
            message: 'Lease ${lease.leaseName} is active without a deposit amount.',
            recommendedAction: 'Verify the deposit and document its status.',
            propertyId: propertyId,
            leaseId: lease.id,
            unitId: lease.unitId,
            tenantId: lease.tenantId,
          ),
        );
      }
      if (lease.paymentDayOfMonth != null &&
          (lease.paymentDayOfMonth! < 1 || lease.paymentDayOfMonth! > 31)) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'invalid_payment_day',
            severity: 'critical',
            message: 'Lease ${lease.leaseName} has an invalid payment day.',
            recommendedAction: 'Set the payment day between 1 and 31.',
            propertyId: propertyId,
            leaseId: lease.id,
            unitId: lease.unitId,
            tenantId: lease.tenantId,
          ),
        );
      }
      if (_isActiveLease(lease, clock)) {
        final tenant = lease.tenantId == null ? null : tenantsById[lease.tenantId];
        if (tenant == null ||
            (tenant.email == null || tenant.email!.trim().isEmpty) ||
            (tenant.phone == null || tenant.phone!.trim().isEmpty)) {
          issues.add(
            OperationsDataQualityIssue(
              type: 'missing_tenant_contact',
              severity: 'warning',
              message: 'Lease ${lease.leaseName} is missing tenant email or phone.',
              recommendedAction: 'Complete tenant contact details before the next operational handoff.',
              propertyId: propertyId,
              leaseId: lease.id,
              unitId: lease.unitId,
              tenantId: lease.tenantId,
            ),
          );
        }
      }
    }

    for (final tenant in tenantsById.values) {
      if (tenant.displayName.trim().isEmpty) {
        issues.add(
          OperationsDataQualityIssue(
            type: 'missing_tenant_display_name',
            severity: 'warning',
            message: 'A tenant is missing the display name.',
            recommendedAction: 'Add a tenant display name for search and contact flows.',
            propertyId: propertyId,
            tenantId: tenant.id,
          ),
        );
      }
    }

    issues.addAll(_buildOverlapIssues(propertyId, leases));

    final latestSnapshot = snapshots.isEmpty ? null : snapshots.first;
    if (_isRentRollStale(latestSnapshot, clock)) {
      issues.add(
        OperationsDataQualityIssue(
          type: 'stale_rent_roll',
          severity: 'warning',
          message: 'Rent roll is missing or older than the accepted freshness window.',
          recommendedAction: 'Generate a new rent roll snapshot for the current period.',
          propertyId: propertyId,
        ),
      );
    }

    return issues;
  }

  Map<String, List<LeaseRecord>> _activeLeasesByUnit(
    List<LeaseRecord> leases,
    DateTime now,
  ) {
    final grouped = <String, List<LeaseRecord>>{};
    for (final lease in leases) {
      if (!_isActiveLease(lease, now)) {
        continue;
      }
      grouped.putIfAbsent(lease.unitId, () => <LeaseRecord>[]).add(lease);
    }
    return grouped;
  }

  bool _isActiveLease(LeaseRecord lease, DateTime now) {
    if (lease.status != 'active') {
      return false;
    }
    final today = now.millisecondsSinceEpoch;
    if (lease.startDate > today) {
      return false;
    }
    return lease.endDate == null || lease.endDate! >= today;
  }

  List<OperationsDataQualityIssue> _buildOverlapIssues(
    String propertyId,
    List<LeaseRecord> leases,
  ) {
    final issues = <OperationsDataQualityIssue>[];
    final byUnit = <String, List<LeaseRecord>>{};
    for (final lease in leases) {
      if (lease.status != 'active' && lease.status != 'future') {
        continue;
      }
      byUnit.putIfAbsent(lease.unitId, () => <LeaseRecord>[]).add(lease);
    }
    for (final entry in byUnit.entries) {
      final unitLeases = entry.value..sort((a, b) => a.startDate.compareTo(b.startDate));
      for (var index = 0; index < unitLeases.length - 1; index += 1) {
        final current = unitLeases[index];
        final next = unitLeases[index + 1];
        final currentEnd = current.endDate ?? 8640000000000000;
        if (next.startDate <= currentEnd) {
          issues.add(
            OperationsDataQualityIssue(
              type: 'overlapping_leases',
              severity: 'critical',
              message:
                  'Unit ${entry.key} has overlapping leases ${current.leaseName} and ${next.leaseName}.',
              recommendedAction: 'Resolve the date overlap before rent roll and alerts become unreliable.',
              propertyId: propertyId,
              unitId: entry.key,
              leaseId: current.id,
              tenantId: current.tenantId,
            ),
          );
        }
      }
    }
    return issues;
  }

  bool _isRentRollStale(RentRollSnapshotRecord? snapshot, DateTime now) {
    if (snapshot == null) {
      return true;
    }
    final snapshotMonth = _parsePeriod(snapshot.periodKey);
    if (snapshotMonth == null) {
      return true;
    }
    final currentMonth = DateTime(now.year, now.month);
    return currentMonth.difference(snapshotMonth) > rentRollStaleThreshold;
  }

  DateTime? _parsePeriod(String periodKey) {
    final parts = periodKey.split('-');
    if (parts.length != 2) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return null;
    }
    return DateTime(year, month);
  }
}
