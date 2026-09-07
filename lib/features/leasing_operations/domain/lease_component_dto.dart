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
  double? get grossMonthly =>
      leaseComponentGross(vatMode, amount, vatRatePercent);
}

/// The gross rule, in one place.
///
/// Extracted when the history read (V-2b) needed the same answer for a period
/// row. A second copy of this would be a second chance to disagree about
/// whether a net amount without a rate can be grossed up -- it cannot, and
/// null is the answer both callers must give.
double? leaseComponentGross(
  LeaseComponentVatMode vatMode,
  double amount,
  double? vatRatePercent,
) {
  return switch (vatMode) {
    LeaseComponentVatMode.exempt => amount,
    LeaseComponentVatMode.gross => amount,
    LeaseComponentVatMode.net => vatRatePercent == null
        ? null
        : amount * (1 + vatRatePercent / 100),
    LeaseComponentVatMode.unknown => null,
  };
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

}


/// One recorded period of one component type (LEASING-COMPONENTS-02, V-2b).
///
/// Distinct from [LeaseComponentDto] because it answers a different question.
/// That one is "what is in force"; this one is "what was ever recorded", so it
/// carries [inForce] rather than being implicitly current, and it keeps the
/// note and the last edit, which are what a contract review reads.
class LeaseComponentPeriodDto {
  const LeaseComponentPeriodDto({
    required this.id,
    required this.validFrom,
    required this.amount,
    required this.currencyCode,
    required this.vatMode,
    required this.version,
    required this.inForce,
    this.validTo,
    this.vatRatePercent,
    this.note,
    this.updatedAt,
  });

  final String id;

  /// Inclusive on both ends, as the contract reads. Null [validTo] is
  /// open-ended, not missing.
  final DateTime validFrom;
  final DateTime? validTo;

  final double amount;
  final String currencyCode;
  final LeaseComponentVatMode vatMode;
  final double? vatRatePercent;
  final String? note;
  final int version;
  final DateTime? updatedAt;

  /// Whether this period covers the date the history was read for. The server
  /// decides it, and at most one period per type can carry it, because the
  /// table forbids two rows covering the same day.
  final bool inForce;

  bool get isOpenEnded => validTo == null;

  double? get grossMonthly =>
      leaseComponentGross(vatMode, amount, vatRatePercent);
}

/// A hole between two recorded periods.
///
/// Interior only. The time before the first period is not a gap -- nothing was
/// ever claimed about it -- and neither is the time after an open-ended last
/// one. The server makes that judgement; this type only names what it sent.
class LeaseComponentGap {
  const LeaseComponentGap({required this.from, required this.to});

  /// Both inclusive, like every other date in the payload.
  final DateTime from;
  final DateTime to;
}

/// Everything ever recorded for one component type on one lease.
class LeaseComponentTimelineDto {
  const LeaseComponentTimelineDto({
    required this.componentType,
    required this.periods,
    required this.gaps,
    this.rawTypeKey,
  });

  final LeaseComponentType componentType;

  /// Oldest first, as the server ordered them.
  final List<LeaseComponentPeriodDto> periods;

  final List<LeaseComponentGap> gaps;

  /// The server's key, kept only for [LeaseComponentType.unknown].
  final String? rawTypeKey;

  bool get hasGap => gaps.isNotEmpty;

  /// The period covering the date this history was read for, or null when the
  /// type has a hole there. Null is a real answer, not a lookup failure.
  LeaseComponentPeriodDto? get current {
    for (final LeaseComponentPeriodDto period in periods) {
      if (period.inForce) {
        return period;
      }
    }
    return null;
  }
}

/// The full component history of one lease.
class LeaseComponentHistoryDto {
  const LeaseComponentHistoryDto({
    required this.leaseId,
    required this.asOfDate,
    required this.timelines,
    this.propertyId,
    this.currencyCode,
  });

  final String leaseId;
  final String? propertyId;
  final String? currencyCode;

  /// The date [LeaseComponentPeriodDto.inForce] was decided against. The
  /// history itself is complete regardless.
  final DateTime asOfDate;

  /// One entry per type that has any history. A type never recorded on this
  /// lease is absent, not present and empty -- nothing was claimed about it.
  final List<LeaseComponentTimelineDto> timelines;
}
