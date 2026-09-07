/// Domain DTOs for the LeaseComponent aggregate (LEASING-COMPONENTS-01, V-2).
///
/// A component is what a tenant pays for one thing over one period: base rent
/// from January to June, a heating advance from January onwards, a parking
/// charge that ended in April. The lease's three flat columns
/// (`baseRentMonthly` and friends) stay what they always were — the figures the
/// contract was signed at — and DEC-029 keeps them there. Components are
/// authoritative *per type* from the moment one exists for that type.
///
/// **A gap is a gap.** Where no component covers a date the server returns no
/// row, and this layer does not invent one. There is deliberately no
/// `amountOrZero`, no fallback to the lease column and no default: "not
/// recorded" and "nothing owed" are different answers, and a screen that cannot
/// tell them apart will eventually show the wrong one as a fact.
library;

/// The five component types the server knows, plus [unknown] for anything a
/// newer server sends.
///
/// [unknown] exists because the alternative is worse in both directions: a
/// throw would make one unfamiliar row break a whole contract view, and
/// silently dropping it would understate what a tenant pays. A row that arrives
/// as unknown is shown with its raw key, which is honest and visibly odd.
enum LeaseComponentType {
  baseRent,
  serviceChargeAdvance,
  heatingAdvance,
  parking,
  other,
  unknown,
}

/// How VAT relates to [LeaseComponentDto.amount].
enum LeaseComponentVatMode {
  /// No VAT — the residential default.
  exempt,

  /// [LeaseComponentDto.amount] is net; VAT comes on top at the stored rate.
  net,

  /// [LeaseComponentDto.amount] already includes VAT at the stored rate.
  gross,

  unknown,
}

LeaseComponentType leaseComponentTypeFromKey(String key) =>
    switch (key) {
      'base_rent' => LeaseComponentType.baseRent,
      'service_charge_advance' => LeaseComponentType.serviceChargeAdvance,
      'heating_advance' => LeaseComponentType.heatingAdvance,
      'parking' => LeaseComponentType.parking,
      'other' => LeaseComponentType.other,
      _ => LeaseComponentType.unknown,
    };

String leaseComponentTypeKey(LeaseComponentType type) =>
    switch (type) {
      LeaseComponentType.baseRent => 'base_rent',
      LeaseComponentType.serviceChargeAdvance => 'service_charge_advance',
      LeaseComponentType.heatingAdvance => 'heating_advance',
      LeaseComponentType.parking => 'parking',
      LeaseComponentType.other => 'other',
      // Never sent to the server: the command layer refuses it rather than
      // guessing which type an unfamiliar row meant.
      LeaseComponentType.unknown => 'unknown',
    };

LeaseComponentVatMode leaseComponentVatModeFromKey(String key) =>
    switch (key) {
      'exempt' => LeaseComponentVatMode.exempt,
      'net' => LeaseComponentVatMode.net,
      'gross' => LeaseComponentVatMode.gross,
      _ => LeaseComponentVatMode.unknown,
    };

String leaseComponentVatModeKey(LeaseComponentVatMode mode) =>
    switch (mode) {
      LeaseComponentVatMode.exempt => 'exempt',
      LeaseComponentVatMode.net => 'net',
      LeaseComponentVatMode.gross => 'gross',
      LeaseComponentVatMode.unknown => 'unknown',
    };

/// One component of one lease, valid over a closed or open-ended period.
class LeaseComponentDto {
  const LeaseComponentDto({
    required this.id,
    required this.leaseId,
    required this.propertyId,
    required this.componentType,
    required this.amount,
    required this.currencyCode,
    required this.vatMode,
    required this.validFrom,
    required this.version,
    this.validTo,
    this.vatRatePercent,
    this.rawTypeKey,
  });

  final String id;
  final String leaseId;
  final String propertyId;
  final LeaseComponentType componentType;
  final double amount;
  final String currencyCode;
  final LeaseComponentVatMode vatMode;

  /// Inclusive on both ends. A null [validTo] means open-ended, which is the
  /// normal state of a current component rather than missing data.
  final DateTime validFrom;
  final DateTime? validTo;

  final double? vatRatePercent;
  final int version;

  /// The server's key, kept only when [componentType] came back as
  /// [LeaseComponentType.unknown]. Shown verbatim so an unfamiliar row is
  /// visibly unfamiliar instead of quietly labelled "Sonstiges".
  final String? rawTypeKey;

  bool get isOpenEnded => validTo == null;

  /// Gross monthly amount where that can be stated, and null where it cannot.
  ///
  /// Null is a real answer here, not a failure: a [LeaseComponentVatMode.net]
  /// component without a rate cannot be grossed up, and an
  /// [LeaseComponentVatMode.unknown] mode from a newer server says nothing
  /// about how the amount relates to tax. Returning [amount] in either case
  /// would present a net figure as a gross one.
  double? get grossMonthly => switch (vatMode) {
    LeaseComponentVatMode.exempt => amount,
    LeaseComponentVatMode.gross => amount,
    LeaseComponentVatMode.net => vatRatePercent == null
        ? null
        : amount * (1 + vatRatePercent! / 100),
    LeaseComponentVatMode.unknown => null,
  };
}

/// Why a set of components has no total, decided in one place.
///
/// The widget used to re-derive this from the components, which meant the rule
/// lived twice and the sentence under the total could name the wrong reason.
enum LeaseComponentTotalBlocker {
  /// There is a total.
  none,

  /// The components disagree on currency. A total across currencies looks
  /// authoritative and means nothing.
  mixedCurrency,

  /// Some are `net` and some are not. A net amount is payable *plus* tax and an
  /// exempt or gross amount is payable as it stands, so adding them produces a
  /// figure that is neither.
  mixedVat,

  /// A VAT mode this build does not recognise, where it cannot say how the
  /// amount relates to tax at all.
  unknownVat,

  /// A component type that has history for this lease has no row covering the
  /// queried date. Summing what is left would be summing *around* a gap, which
  /// DEC-029 forbids in as many words.
  gapAtDate,
}

/// What one component type looks like across the whole term, as the server
/// sees it (LEASING-COMPONENTS-01c).
class LeaseComponentCoverageType {
  const LeaseComponentCoverageType({
    required this.componentType,
    required this.inForce,
    required this.gapCount,
    this.firstGapFrom,
    this.firstGapTo,
    this.openGapFrom,
    this.rawTypeKey,
  });

  final LeaseComponentType componentType;

  /// Whether a row covers the queried date. False here with [gapCount] above
  /// zero is the case that used to be invisible: recorded once, not now.
  final bool inForce;

  final int gapCount;
  final DateTime? firstGapFrom;
  final DateTime? firstGapTo;

  /// Start of the gap that reaches the queried date, when there is one — the
  /// actionable half: "unrecorded since X and still".
  final DateTime? openGapFrom;

  final String? rawTypeKey;

  bool get hasGap => gapCount > 0;
}

/// Coverage of one lease over the window the server examined.
class LeaseComponentCoverage {
  const LeaseComponentCoverage({
    required this.leaseId,
    required this.windowFrom,
    required this.windowTo,
    required this.complete,
    required this.types,
  });

  final String leaseId;

  /// The lease start, and the queried date — never later. A fixed-term lease is
  /// not incomplete for its own future; nobody has agreed that yet.
  final DateTime windowFrom;
  final DateTime windowTo;

  final bool complete;

  /// Only types with at least one row for this lease. A type nobody ever
  /// recorded is absent rather than reported as a gap: nothing was claimed
  /// about it, so there is nothing to be incomplete about.
  final List<LeaseComponentCoverageType> types;

  LeaseComponentCoverageType? ofType(LeaseComponentType type) {
    for (final entry in types) {
      if (entry.componentType == type) {
        return entry;
      }
    }
    return null;
  }
}

/// The components in force on one date, for one lease or one property.
///
/// Carries [asOfDate] because the answer is only meaningful with it, and a
/// screen that shows figures without the date they were true on invites
/// exactly the misreading LEASING-ASOF-01 was created to remove.
class LeaseComponentsAsOfDto {
  const LeaseComponentsAsOfDto({
    required this.asOfDate,
    required this.components,
    this.coverage = const <LeaseComponentCoverage>[],
  });

  final DateTime asOfDate;
  final List<LeaseComponentDto> components;

  /// Per lease, because the property-scoped read spans several and one flag
  /// would hide which is incomplete. Empty when no lease in scope has any
  /// component at all.
  final List<LeaseComponentCoverage> coverage;

  LeaseComponentCoverage? coverageOf(String leaseId) {
    for (final entry in coverage) {
      if (entry.leaseId == leaseId) {
        return entry;
      }
    }
    return null;
  }

  /// True when every lease in scope is fully covered — and true, deliberately,
  /// when there is nothing to cover.
  bool get complete => coverage.every((entry) => entry.complete);

  /// Types that have history for this lease but no row covering the queried
  /// date. The reason a total must not be shown.
  List<LeaseComponentCoverageType> get recordedButMissingToday => <
      LeaseComponentCoverageType>[
    for (final entry in coverage)
      for (final type in entry.types)
        if (!type.inForce) type,
  ];

  /// The component of a given type in force, or null when none covers the date.
  ///
  /// Null means "not recorded for this date". Callers must not read it as zero
  /// — see the library comment.
  LeaseComponentDto? ofType(LeaseComponentType type) {
    for (final component in components) {
      if (component.componentType == type) {
        return component;
      }
    }
    return null;
  }

  /// Why there is no total, or [LeaseComponentTotalBlocker.none].
  ///
  /// Decided here rather than in the widget, so the sentence under the total
  /// can name the actual reason instead of a catch-all. Four ways to have no
  /// total, and only the first is the obvious one.
  LeaseComponentTotalBlocker get totalBlocker {
    if (components.isEmpty) {
      return LeaseComponentTotalBlocker.none;
    }
    // DEC-029, checked first because it is the one that would otherwise
    // produce a plausible number: a type recorded for other periods and not
    // this one is missing from the sum, and the sum would not say so.
    if (recordedButMissingToday.isNotEmpty) {
      return LeaseComponentTotalBlocker.gapAtDate;
    }
    if (components.any((c) => c.vatMode == LeaseComponentVatMode.unknown)) {
      return LeaseComponentTotalBlocker.unknownVat;
    }
    final netCount = components
        .where((c) => c.vatMode == LeaseComponentVatMode.net)
        .length;
    if (netCount != 0 && netCount != components.length) {
      return LeaseComponentTotalBlocker.mixedVat;
    }
    final currency = components.first.currencyCode;
    if (components.any((c) => c.currencyCode != currency)) {
      return LeaseComponentTotalBlocker.mixedCurrency;
    }
    return LeaseComponentTotalBlocker.none;
  }

  /// Sum of the recorded components, the currency they share, and whether the
  /// figure is a net one.
  ///
  /// Null whenever [totalBlocker] says the sum would not correspond to
  /// anything. When every component is `net` the sum is still useful — it is
  /// simply a net total, and [isNet] says so, so the label can too.
  ({double amount, String currencyCode, bool isNet})? get recordedTotal {
    if (components.isEmpty ||
        totalBlocker != LeaseComponentTotalBlocker.none) {
      return null;
    }
    var total = 0.0;
    for (final component in components) {
      total += component.amount;
    }
    return (
      amount: total,
      currencyCode: components.first.currencyCode,
      isNet: components.every((c) => c.vatMode == LeaseComponentVatMode.net),
    );
  }
}
