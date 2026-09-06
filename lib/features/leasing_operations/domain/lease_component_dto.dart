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

/// The components in force on one date, for one lease or one property.
///
/// Carries [asOfDate] because the answer is only meaningful with it, and a
/// screen that shows figures without the date they were true on invites
/// exactly the misreading LEASING-ASOF-01 was created to remove.
class LeaseComponentsAsOfDto {
  const LeaseComponentsAsOfDto({
    required this.asOfDate,
    required this.components,
  });

  final DateTime asOfDate;
  final List<LeaseComponentDto> components;

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

  /// Sum of the recorded components, and the currency they share.
  ///
  /// Null when the components disagree on currency. Summing across currencies
  /// produces a number that looks authoritative and means nothing, which is the
  /// mistake the rest of this codebase already declines to make.
  ({double amount, String currencyCode})? get recordedTotal {
    if (components.isEmpty) {
      return null;
    }
    final currency = components.first.currencyCode;
    var total = 0.0;
    for (final component in components) {
      if (component.currencyCode != currency) {
        return null;
      }
      total += component.amount;
    }
    return (amount: total, currencyCode: currency);
  }
}
