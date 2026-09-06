/// A property's booked actuals, per account and per currency (FINANCE-01a).
///
/// This is what the ledger foundation publishes and nothing more. There is no
/// NOI here, no cashflow, no margin and no net result, and there is no field to
/// put one in. Each of those is a formula, and `PROPERTY_PERFORMANCE_V2.md` §7
/// requires a definition *version* to travel with any computed figure so a
/// number can be reproduced and audited later. That versioning is `FINANCE-01b`.
/// A screen that summed these rows into a "result" would publish exactly the
/// unreproducible figure the overview spec rules out.
///
/// Two properties of the shape are load-bearing:
///
///   * **A row is per account *and* per currency.** Two currencies on one
///     account are two rows. There is no total across them, because adding EUR
///     to CHF produces a number that is wrong in both.
///   * **Provisionality travels with the numbers.** The periods covered by the
///     figures are published with their open/closed status, so a total that
///     includes a half-booked month can be labelled as provisional rather than
///     read as final.
library;

/// The account classes the ledger recognises. The server sends the key; an
/// unknown one is kept as [FinanceAccountType.unknown] with its raw key rather
/// than dropped, so a newer server's account class is visible instead of
/// silently missing from a statement.
enum FinanceAccountType { income, expense, asset, liability, equity, unknown }

FinanceAccountType financeAccountTypeFromWire(String value) {
  return switch (value) {
    'income' => FinanceAccountType.income,
    'expense' => FinanceAccountType.expense,
    'asset' => FinanceAccountType.asset,
    'liability' => FinanceAccountType.liability,
    'equity' => FinanceAccountType.equity,
    _ => FinanceAccountType.unknown,
  };
}

enum FinancePeriodStatus { open, closed }

/// One account's booked total in one currency.
class FinanceActualLine {
  const FinanceActualLine({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.accountTypeKey,
    required this.currencyCode,
    required this.amount,
    required this.entries,
  });

  final String accountId;
  final String accountCode;
  final String accountName;

  final FinanceAccountType accountType;

  /// The server's raw key, always present. Rendered when [accountType] is
  /// unknown so the row still says what it is.
  final String accountTypeKey;

  final String currencyCode;

  /// Signed in the natural direction of the account type: income positive when
  /// earned, expense positive when incurred. Never negated for display, since
  /// a credit note is legitimately negative and flipping signs would hide it.
  final num amount;

  /// How many bookings stand behind the total. A reader who wants to know
  /// whether a figure rests on one entry or two hundred can see it.
  final int entries;
}

/// One accounting period the figures drew on, and whether it is final.
class FinancePeriodCoverage {
  const FinancePeriodCoverage({
    required this.periodId,
    required this.fiscalYear,
    required this.periodMonth,
    required this.status,
    required this.entries,
  });

  final String periodId;
  final int fiscalYear;
  final int periodMonth;
  final FinancePeriodStatus status;
  final int entries;

  bool get isClosed => status == FinancePeriodStatus.closed;
}

class PropertyFinanceActualsDto {
  const PropertyFinanceActualsDto({
    required this.asOf,
    required this.lines,
    required this.periods,
    required this.isProvisional,
    required this.openPeriods,
    required this.coveredPeriods,
  });

  /// When the server produced the snapshot.
  final DateTime asOf;

  /// Server-ordered: account type, then code, then currency. Rendered in that
  /// order rather than re-sorted, so the statement reads the same everywhere.
  final List<FinanceActualLine> lines;

  final List<FinancePeriodCoverage> periods;

  /// True while any covered period is still open. Every figure is then
  /// provisional — not wrong, but not final either.
  final bool isProvisional;

  final int openPeriods;
  final int coveredPeriods;

  bool get isEmpty => lines.isEmpty;

  /// The currencies present, in the order the server's rows introduced them.
  List<String> get currencies {
    final seen = <String>[];
    for (final line in lines) {
      if (!seen.contains(line.currencyCode)) {
        seen.add(line.currencyCode);
      }
    }
    return seen;
  }

  /// The lines of one account class in one currency. Grouping only — no
  /// arithmetic across classes, which is where a net result would sneak in.
  List<FinanceActualLine> linesOf(
    FinanceAccountType type,
    String currencyCode,
  ) {
    return lines
        .where(
          (line) =>
              line.accountType == type && line.currencyCode == currencyCode,
        )
        .toList(growable: false);
  }

  /// The sum of one account class in one currency.
  ///
  /// Deliberately narrow: same class, same currency. That is a subtotal of
  /// like things, which the ledger already implies and which needs no
  /// definition version. Combining two classes would be a formula and is
  /// therefore not offered here at all.
  num subtotalOf(FinanceAccountType type, String currencyCode) {
    var total = 0 as num;
    for (final line in linesOf(type, currencyCode)) {
      total += line.amount;
    }
    return total;
  }
}
