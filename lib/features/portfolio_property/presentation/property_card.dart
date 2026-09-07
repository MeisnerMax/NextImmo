/// One property, as a card.
///
/// Built on [NxCard] rather than a new decoration: depth in this system is a
/// translucent fill, a hairline stroke and a top-edge inner highlight, and
/// `03_design_system.md` forbids reintroducing a shadow in so many words. A
/// card that invented its own surface would be the second visual style the
/// brief rules out.
///
/// **Where the numbers come from.** `PropertySummaryDto` carries none of them
/// — the list is a plain table read — so they arrive separately from
/// `PROPERTY-CARD-METRICS-01`, one batch for the whole page. Calling
/// `property_overview` per tile would be the N+1 the performance rules forbid
/// and would make a scroll of forty cards forty round trips.
///
/// **[metrics] null is a real state and renders as nothing.** Not yet loaded,
/// withheld by the server, or a failed read all leave the card without
/// figures. That is deliberate: a zero here would be indistinguishable from a
/// property with genuinely nothing open, and a card is exactly where a wrong
/// number gets believed. The grid says once, above itself, when a read failed.
///
/// **No occupancy percentage.** Occupied and total are shown as they are —
/// `3/4` — because whether a rate counts units or area is an owner decision
/// nobody has taken, and the two answers differ for every mixed-use asset.
/// Still no rent and no NOI: those need the finance contract.
///
/// The recorded unit count and the occupancy pair can disagree, and both are
/// shown when they do. `property.units` is the figure typed on the property;
/// the pair counts rows in `public.units`. A building half entered shows the
/// difference, which is more useful than picking one and hiding the other.
library;

import 'package:flutter/material.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_cover_image.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/theme/app_theme.dart';
import '../domain/property_card_metrics_dto.dart';
import '../domain/property_dto.dart';
import 'property_presentation.dart';

/// German label for a property type.
///
/// `property_type` is `text not null` in the schema, not an enum, and the
/// create dialog asks for a bare code. An unknown value is therefore normal,
/// not a defect — it is shown as it came rather than dropped or bent into
/// "Sonstige", so a workspace using its own vocabulary sees its own words.
String propertyTypeLabel(String propertyType) {
  return switch (propertyType) {
    'residential' => 'Wohnen',
    'commercial' => 'Gewerbe',
    'mixed_use' => 'Gemischt',
    'industrial' => 'Industrie',
    'land' => 'Grundstück',
    'parking' => 'Parken',
    'special' => 'Sonderimmobilie',
    _ => propertyType,
  };
}

class PropertyCard extends StatelessWidget {
  const PropertyCard({
    super.key,
    required this.property,
    this.metrics,
    this.coverUrl,
    this.onOpen,
    this.autofocus = false,
    this.opening = false,
  });

  final PropertySummaryDto property;

  /// The operational numbers for this property, or null when there are none to
  /// show yet. See the class doc: null renders as absence, never as zero.
  final PropertyCardMetricsDto? metrics;

  /// Null for the great majority of properties: images are optional and the
  /// demo fixture creates none. [NxCoverImage] treats that as the normal case.
  final String? coverUrl;

  final VoidCallback? onOpen;

  /// Restores the keyboard position after returning from this property, the
  /// same job the table row's open button does. Without it the card view
  /// would lose focus on the way back where the table keeps it.
  final bool autofocus;

  /// This property is being opened right now.
  ///
  /// The table replaces its open button with a spinner while the canonical
  /// read is in flight; without an equivalent the card would simply stop
  /// responding, which reads as a broken click rather than as work in
  /// progress.
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = propertyLocationLine(property);

    return NxCard(
      variant: NxCardVariant.interactive,
      onTap: onOpen,
      autofocus: autofocus,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Stack(
            children: <Widget>[
              NxCoverImage(
                url: coverUrl,
                semanticLabel: 'Titelbild von ${property.name}',
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadiusTokens.lg),
                ),
              ),
              if (opening)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(minHeight: 3),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        property.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    NxStatusBadge(
                      label: propertyStatusLabel(property.status),
                      kind: propertyStatusBadgeKind(property.status),
                    ),
                  ],
                ),
                if (location.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    location,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                // Wrap, not Row: at one column on a phone these two can need
                // two lines, and clipping the unit count to fit would lose the
                // more useful of the pair.
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xxs,
                  children: <Widget>[
                    _Fact(
                      icon: Icons.category_outlined,
                      label: propertyTypeLabel(property.propertyType),
                    ),
                    _Fact(
                      icon: Icons.meeting_room_outlined,
                      // The figure recorded on the property. It is not a count
                      // of `public.units`, and the two can differ while a
                      // building is still being entered -- which is why the
                      // occupancy pair below is shown next to it rather than
                      // instead of it.
                      label: property.units == 1
                          ? '1 Einheit'
                          : '${property.units} Einheiten',
                    ),
                  ],
                ),
                _MetricFacts(metrics: metrics),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// The batch numbers, or nothing at all.
///
/// Every entry is conditional on being greater than zero, with one exception:
/// occupancy is shown whenever units exist, because `0/12 vermietet` is the
/// single most important thing a card can say. The signals are the opposite —
/// "no overdue tickets" is not news, and a card that listed every zero would
/// bury the one property that has a problem.
class _MetricFacts extends StatelessWidget {
  const _MetricFacts({required this.metrics});

  final PropertyCardMetricsDto? metrics;

  @override
  Widget build(BuildContext context) {
    final PropertyCardMetricsDto? data = metrics;
    if (data == null) {
      return const SizedBox.shrink();
    }
    final semantic = context.semanticColors;
    final facts = <Widget>[];

    // `[]` returns null for a section the caller may not read, so an
    // unavailable section produces no entry rather than a zero.
    final unitsTotal = data.leasing['units_total'];
    final unitsOccupied = data.leasing['units_occupied'];
    if (unitsTotal != null && unitsOccupied != null && unitsTotal > 0) {
      facts.add(
        _Fact(
          icon: Icons.how_to_reg_outlined,
          label: '$unitsOccupied/$unitsTotal vermietet',
          // Not a warning: a vacant flat is a normal state of a portfolio,
          // and colouring it red would make every card shout.
          color: unitsOccupied == 0 ? semantic.warning : null,
        ),
      );
    }

    final expired = data.leasing['leases_expired_open'] ?? 0;
    if (expired > 0) {
      facts.add(
        _Fact(
          icon: Icons.error_outline,
          label: expired == 1
              ? '1 Vertrag überfällig'
              : '$expired Verträge überfällig',
          color: semantic.error,
        ),
      );
    }

    final ending = data.leasing['leases_ending_90d'] ?? 0;
    if (ending > 0) {
      facts.add(
        _Fact(
          icon: Icons.event_outlined,
          label: ending == 1 ? '1 läuft aus' : '$ending laufen aus',
          color: semantic.warning,
        ),
      );
    }

    final ticketsOpen = data.maintenance['tickets_open'] ?? 0;
    if (ticketsOpen > 0) {
      final overdue = data.maintenance['tickets_overdue'] ?? 0;
      final urgent = data.maintenance['tickets_urgent_open'] ?? 0;
      facts.add(
        _Fact(
          icon: Icons.build_outlined,
          label: ticketsOpen == 1 ? '1 Ticket offen' : '$ticketsOpen Tickets offen',
          color: overdue > 0
              ? semantic.error
              : (urgent > 0 ? semantic.warning : null),
        ),
      );
    }

    if (facts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: facts,
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;

  /// Null for a plain fact. A colour marks a signal that wants attention; the
  /// icon changes with it, so the meaning does not rest on colour alone.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = this.color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}
