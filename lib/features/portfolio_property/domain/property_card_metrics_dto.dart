/// Card metrics for a page of properties (PROPERTY-CARD-METRICS-01).
///
/// The batch answer to the question the card doc comment used to end on: the
/// list read is a plain table read, so a card wanting operational numbers had
/// to call `property_overview` once per tile. Forty cards, forty round trips.
/// This is that read, batched.
///
/// It reuses [PropertySummarySection] — the overview's section type — on
/// purpose. The available/unavailable distinction is the same distinction, and
/// a second type would be a second place for someone to write `?? 0`.
library;

import 'property_overview_dto.dart';

/// The overview's section type, under the name this file uses for it. Both
/// reads answer with the same shape because both are permission-scoped the
/// same way.
typedef PropertySummarySection = PropertyOverviewSection;

/// The card numbers for one property.
class PropertyCardMetricsDto {
  const PropertyCardMetricsDto({
    required this.propertyId,
    required this.leasing,
    required this.maintenance,
  });

  final String propertyId;

  /// Units and leases. Occupied and total are both here; the ratio is not,
  /// and the server does not send one — by unit or by area is an owner
  /// decision nobody has taken, and the two answers differ for every
  /// mixed-use asset.
  final PropertySummarySection leasing;

  final PropertySummarySection maintenance;
}

/// One batch answer.
class PropertyCardMetricsBatch {
  const PropertyCardMetricsBatch({
    required this.asOf,
    required this.byPropertyId,
    required this.withheld,
  });

  const PropertyCardMetricsBatch.empty()
    : asOf = null,
      byPropertyId = const <String, PropertyCardMetricsDto>{},
      withheld = const <String>[];

  /// When the server counted. Null only for [PropertyCardMetricsBatch.empty],
  /// which stands for "not asked yet" rather than for an answer.
  final DateTime? asOf;

  final Map<String, PropertyCardMetricsDto> byPropertyId;

  /// Ids the server would not answer for — either because they name no
  /// property or because the caller may not see them. The server does not say
  /// which, deliberately: distinguishing them would answer the existence
  /// question for someone the entity scope says may not ask it.
  ///
  /// A card for a withheld id shows no numbers. It must not show zeroes.
  final List<String> withheld;

  /// The metrics for [propertyId], or null when the server withheld it or was
  /// never asked. Nullable on purpose — there is no empty-but-present value
  /// to fall back to, because that value would be a lie.
  PropertyCardMetricsDto? operator [](String propertyId) =>
      byPropertyId[propertyId];
}
