import '../models/operations.dart';

class LeaseIndexationEngine {
  const LeaseIndexationEngine();

  List<LeaseRentScheduleRecord> buildRentSchedule({
    required LeaseRecord lease,
    required List<LeaseIndexationRuleRecord> indexationRules,
    required String fromPeriodKey,
    required String toPeriodKey,
    required Map<String, LeaseRentScheduleRecord> manualOverrides,
  }) {
    final months = _expandMonths(fromPeriodKey, toPeriodKey);
    final rules = List<LeaseIndexationRuleRecord>.from(indexationRules)..sort(
      (a, b) => a.effectiveFromPeriodKey.compareTo(b.effectiveFromPeriodKey),
    );

    var currentRent = lease.baseRentMonthly;
    final output = <LeaseRentScheduleRecord>[];
    final leaseStart = DateTime.fromMillisecondsSinceEpoch(lease.startDate);

    for (var i = 0; i < months.length; i++) {
      final period = months[i];
      if (i > 0) {
        final prev = months[i - 1];
        if (_isAnniversary(period, leaseStart) &&
            !_sameYearMonth(prev, leaseStart)) {
          currentRent = _applyAnnualRules(currentRent, period, rules);
        }
      }

      final manual = manualOverrides[period];
      if (manual != null) {
        output.add(manual);
      } else {
        output.add(
          LeaseRentScheduleRecord(
            id: '${lease.id}_$period',
            leaseId: lease.id,
            periodKey: period,
            rentMonthly: currentRent,
            source: _sourceForPeriod(period, rules),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    }

    return output;
  }

  double _applyAnnualRules(
    double currentRent,
    String period,
    List<LeaseIndexationRuleRecord> rules,
  ) {
    var nextRent = currentRent;
    for (final rule in rules) {
      if (period.compareTo(rule.effectiveFromPeriodKey) < 0) {
        continue;
      }
      if (rule.kind == 'cpi') {
        var percent = rule.annualPercent ?? 0.0;
        if (rule.capPercent != null && percent > rule.capPercent!) {
          percent = rule.capPercent!;
        }
        if (rule.floorPercent != null && percent < rule.floorPercent!) {
          percent = rule.floorPercent!;
        }
        nextRent = nextRent * (1 + percent);
      } else if (rule.kind == 'fixed_step') {
        nextRent = nextRent + (rule.fixedStepAmount ?? 0.0);
      }
    }
    return nextRent;
  }

  String _sourceForPeriod(
    String period,
    List<LeaseIndexationRuleRecord> rules,
  ) {
    for (final rule in rules) {
      if (period.compareTo(rule.effectiveFromPeriodKey) >= 0 &&
          (rule.kind == 'cpi' || rule.kind == 'fixed_step')) {
        return 'indexation';
      }
    }
    return 'base';
  }

  bool _isAnniversary(String periodKey, DateTime leaseStart) {
    final parts = periodKey.split('-');
    if (parts.length != 2) {
      return false;
    }
    final month = int.tryParse(parts[1]) ?? 1;
    return month == leaseStart.month;
  }

  bool _sameYearMonth(String periodKey, DateTime date) {
    final parts = periodKey.split('-');
    if (parts.length != 2) {
      return false;
    }
    final year = int.tryParse(parts[0]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 0;
    return year == date.year && month == date.month;
  }

  List<String> _expandMonths(String fromPeriodKey, String toPeriodKey) {
    final from = _toDate(fromPeriodKey);
    final to = _toDate(toPeriodKey);
    if (from == null || to == null || from.isAfter(to)) {
      return const [];
    }
    final out = <String>[];
    var cursor = DateTime(from.year, from.month);
    while (!cursor.isAfter(to)) {
      final month = cursor.month.toString().padLeft(2, '0');
      out.add('${cursor.year}-$month');
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return out;
  }

  DateTime? _toDate(String periodKey) {
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
