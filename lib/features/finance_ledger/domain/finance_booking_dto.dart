/// Accounting periods and what was booked into them (`FINANCE-BOOKINGS-01`).
///
/// **A booking cannot be edited or deleted, and this model says so.** There is
/// no update, no delete and no reversal command on the server, no write policy
/// on the table, and no column linking a correction to what it corrects. The
/// only remedy for a mis-booking is a compensating counter-booking with a
/// negated amount — which is why [FinanceLedgerEntryDto.amount] is signed and
/// why the surface shows both rows rather than netting them away. A list that
/// hid the pair would hide the mistake and the correction together.
///
/// **The period is workspace-wide and monthly; the booking is per property.**
/// One period holds every property's costs for that month, and closing it
/// stops further entries for all of them. Closing needs `finance.close`, a
/// permission separate from `finance.manage`, precisely so that whoever books
/// is not automatically whoever seals the month.
library;

/// Whether a period still accepts entries.
enum FinancePeriodState {
  open,
  closed,

  /// From a newer server.
  unknown,
}

FinancePeriodState financePeriodStateFromKey(String key) => switch (key) {
  'open' => FinancePeriodState.open,
  'closed' => FinancePeriodState.closed,
  _ => FinancePeriodState.unknown,
};

String financePeriodStateKey(FinancePeriodState value) => switch (value) {
  FinancePeriodState.open => 'open',
  FinancePeriodState.closed => 'closed',
  // Never sent: the command layer refuses it rather than guessing what an
  // unfamiliar state meant.
  FinancePeriodState.unknown => 'unknown',
};

class FinancePeriodDto {
  const FinancePeriodDto({
    required this.id,
    required this.workspaceId,
    required this.fiscalYear,
    required this.periodMonth,
    required this.state,
    required this.version,
    required this.entryCount,
    this.closedAt,
    this.closedBy,
    this.rawStateKey,
  });

  final String id;
  final String workspaceId;
  final int fiscalYear;

  /// 1–12. A period is a calendar month of a fiscal year, and a booking must
  /// fall inside it — the server refuses a date that does not.
  final int periodMonth;

  final FinancePeriodState state;
  final int version;

  /// How many ledger entries the period holds, across every property. Read
  /// rather than counted here: closing an empty period is usually a mistake
  /// and closing a full one is the normal act, and the difference should be
  /// visible before the decision.
  final int entryCount;

  final DateTime? closedAt;
  final String? closedBy;

  /// The server's key, kept only when the state came back unrecognised.
  final String? rawStateKey;

  bool get isOpen => state == FinancePeriodState.open;

  /// Whether this build may act on the period at all. False for a state it
  /// does not recognise: a newer server could introduce one with rules this
  /// build does not know, and acting on it would be acting blind.
  bool get isActionable => state != FinancePeriodState.unknown;

  String get label =>
      '${periodMonth.toString().padLeft(2, '0')}/$fiscalYear';
}

class FinancePeriodOverviewDto {
  const FinancePeriodOverviewDto({
    required this.periods,
    required this.openCount,
    required this.totalCount,
  });

  /// Newest first, as the server orders them.
  final List<FinancePeriodDto> periods;

  /// Counted by the server over every period in the workspace.
  final int openCount;
  final int totalCount;

  List<FinancePeriodDto> get open =>
      periods.where((FinancePeriodDto period) => period.isOpen).toList(
        growable: false,
      );
}

/// One booked cost.
class FinanceLedgerEntryDto {
  const FinanceLedgerEntryDto({
    required this.id,
    required this.workspaceId,
    required this.propertyId,
    required this.accountId,
    required this.periodId,
    required this.bookedOn,
    required this.amount,
    required this.currencyCode,
    required this.version,
    this.description,
    this.source,
    this.unitId,
    this.unitCode,
    this.accountCode,
    this.accountName,
    this.accountType,
    this.periodFiscalYear,
    this.periodMonth,
    this.periodStatus,
    this.allocatable,
    this.settlementPrinciple,
  });

  final String id;
  final String workspaceId;
  final String propertyId;
  final String accountId;
  final String periodId;

  /// Inside its period — the server refuses a date that is not, since every
  /// figure downstream groups by period.
  final DateTime bookedOn;

  /// Signed. A negative amount is a counter-booking, the only correction this
  /// schema offers, and it is a legitimate entry rather than an error.
  final num amount;

  final String currencyCode;
  final String? description;

  /// `manual` for anything a person books. The command hard-codes it; a
  /// client cannot claim an entry came from an import.
  final String? source;

  final String? unitId;
  final String? unitCode;

  final String? accountCode;
  final String? accountName;
  final String? accountType;

  final int? periodFiscalYear;
  final int? periodMonth;
  final String? periodStatus;

  /// Whether this cost may be passed on to tenants. **Null means nobody has
  /// classified the cost type**, which is not the same as false — and the two
  /// must not be rendered alike, because only one of them is a decision.
  final bool? allocatable;

  final String? settlementPrinciple;
  final int version;

  bool get isCounterBooking => amount < 0;

  /// Whether a service-charge settlement could use this cost at all. Null
  /// classification is deliberately not usable: an undecided cost is not an
  /// apportionable one.
  bool get isApportionable => allocatable == true;
}

class FinanceLedgerOverviewDto {
  const FinanceLedgerOverviewDto({
    required this.entries,
    required this.returnedCount,
    required this.totalCount,
    required this.limit,
  });

  final List<FinanceLedgerEntryDto> entries;

  /// How many rows came back, and how many the filter matched in total. They
  /// differ when the page is capped, and the surface says so rather than
  /// letting a truncated list read as the whole answer.
  final int returnedCount;
  final int totalCount;
  final int limit;

  bool get isTruncated => totalCount > returnedCount;

  /// The signed sum of what came back, per currency. Computed here only for
  /// display of the page in hand — `property_finance_actuals` is the
  /// authoritative total, and this never stands in for it.
  Map<String, num> get pageTotalsByCurrency {
    final Map<String, num> totals = <String, num>{};
    for (final FinanceLedgerEntryDto entry in entries) {
      totals[entry.currencyCode] =
          (totals[entry.currencyCode] ?? 0) + entry.amount;
    }
    return totals;
  }
}
