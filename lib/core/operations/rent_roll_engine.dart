import '../models/operations.dart';

class RentRollEngine {
  const RentRollEngine();

  RentRollComputationResult compute({
    required String periodKey,
    required List<UnitRecord> units,
    required List<LeaseRecord> leases,
    required List<LeaseRentScheduleRecord> schedule,
    required Map<String, TenantRecord> tenantsById,
  }) {
    final lines = <RentRollComputationLine>[];
    final start = _periodStart(periodKey);
    final end = _periodEnd(periodKey);
    final scheduleByLease = <String, Map<String, LeaseRentScheduleRecord>>{};
    for (final entry in schedule) {
      scheduleByLease.putIfAbsent(
            entry.leaseId,
            () => <String, LeaseRentScheduleRecord>{},
          )[entry.periodKey] =
          entry;
    }

    var occupiedCount = 0;
    var rentableCount = 0;
    var inPlace = 0.0;
    var gpr = 0.0;
    var marketRentTotal = 0.0;
    var marketRentSeen = false;

    for (final unit in units) {
      final activeLeases =
          leases.where((lease) {
              if (lease.unitId != unit.id) {
                return false;
              }
              if (lease.status != 'active') {
                return false;
              }
              if (lease.startDate > end.millisecondsSinceEpoch) {
                return false;
              }
              if (lease.endDate != null &&
                  lease.endDate! < start.millisecondsSinceEpoch) {
                return false;
              }
              return true;
            }).toList()
            ..sort((a, b) => b.startDate.compareTo(a.startDate));

      final lease = activeLeases.isEmpty ? null : activeLeases.first;
      final isOffline = unit.status == 'offline';
      final status =
          isOffline ? 'offline' : (lease == null ? 'vacant' : 'occupied');

      var inPlaceMonthly = 0.0;
      if (lease != null) {
        final byPeriod = scheduleByLease[lease.id];
        final overridden = byPeriod == null ? null : byPeriod[periodKey];
        inPlaceMonthly = overridden?.rentMonthly ?? lease.baseRentMonthly;
      }

      if (!isOffline) {
        rentableCount += 1;
        if (status == 'occupied') {
          occupiedCount += 1;
          inPlace += inPlaceMonthly;
        }

        if (unit.marketRentMonthly != null) {
          gpr += unit.marketRentMonthly!;
          marketRentTotal += unit.marketRentMonthly!;
          marketRentSeen = true;
        } else {
          gpr += inPlaceMonthly;
        }
      }

      final tenantName =
          lease?.tenantId == null
              ? null
              : tenantsById[lease!.tenantId!]?.displayName;

      lines.add(
        RentRollComputationLine(
          unit: unit,
          lease: lease,
          tenantName: tenantName,
          status: status,
          inPlaceRentMonthly: inPlaceMonthly,
          marketRentMonthly: unit.marketRentMonthly,
          leaseEndDate: lease?.endDate,
        ),
      );
    }

    final vacancyLoss = (gpr - inPlace) < 0 ? 0.0 : (gpr - inPlace);
    final occupancyRate =
        rentableCount == 0 ? 0.0 : occupiedCount / rentableCount;

    return RentRollComputationResult(
      occupancyRate: occupancyRate,
      gprMonthly: gpr,
      vacancyLossMonthly: vacancyLoss,
      egiMonthly: inPlace,
      inPlaceRentMonthly: inPlace,
      marketRentMonthly: marketRentSeen ? marketRentTotal : null,
      lines: lines,
    );
  }

  DateTime _periodStart(String periodKey) {
    final parts = periodKey.split('-');
    final year = int.tryParse(parts[0]) ?? 1970;
    final month = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
    return DateTime(year, month);
  }

  DateTime _periodEnd(String periodKey) {
    final start = _periodStart(periodKey);
    return DateTime(start.year, start.month + 1, 0, 23, 59, 59, 999);
  }
}
