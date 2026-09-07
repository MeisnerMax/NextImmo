/// Warm rent per lease, as the server computes it (WARM-RENT-01, P-7).
///
/// The point of this type is that it can be *incomplete in two different ways*
/// and says which. A single nullable number would collapse both into "no
/// figure" and leave the screen guessing.
///
///   * [gapTypes] — a constituent was recorded for other periods and not this
///     date. The figures are withheld entirely: summing what remains would be
///     summing around a gap, which DEC-029 forbids in as many words.
///   * [absentTypes] — a constituent was never recorded. Not a gap, because
///     nothing was ever claimed about it, but the sum is then narrower than the
///     word. [isWarm] is what says so.
///
/// There is deliberately no `total` getter that falls back to something. A
/// warm rent that cannot be stated is not a zero and not a base rent.
library;

import 'lease_component_dto.dart';

class WarmRentDto {
  const WarmRentDto({
    required this.leaseId,
    required this.propertyId,
    required this.currencyCode,
    required this.isWarm,
    this.includedTypes = const <LeaseComponentType>[],
    this.gapTypes = const <LeaseComponentType>[],
    this.absentTypes = const <LeaseComponentType>[],
    this.netMonthly,
    this.grossMonthly,
  });

  final String leaseId;
  final String propertyId;
  final String currencyCode;

  /// True only when a heating advance is one of the [includedTypes].
  ///
  /// A total without heating is a cold rent plus service charges. Both totals
  /// that predate this contract get that wrong — the legacy `warmRentMonthly`
  /// adds parking and omits heating — so the flag exists to stop a third one
  /// from doing the same.
  final bool isWarm;

  /// The constituents that actually went into the figures, in the order a rent
  /// statement reads.
  final List<LeaseComponentType> includedTypes;

  /// Recorded for other periods, missing on this date.
  final List<LeaseComponentType> gapTypes;

  /// Never recorded for this lease at all.
  final List<LeaseComponentType> absentTypes;

  /// Null whenever the parts cannot be added into one honest figure — a gap, a
  /// currency conflict, or net beside exempt, where one of the two is already a
  /// payable amount.
  final double? netMonthly;

  /// Null when a net amount cannot be grossed up. Note this can be present
  /// while [netMonthly] is null: net beside exempt has a meaningful gross total
  /// and no meaningful net one, and withholding both would be a lazy symmetry.
  final double? grossMonthly;

  bool get hasGap => gapTypes.isNotEmpty;

  /// True when there is a figure to show at all.
  bool get hasFigure => netMonthly != null || grossMonthly != null;
}
