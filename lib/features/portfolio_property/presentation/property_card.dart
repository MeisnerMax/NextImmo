/// One property, as a card.
///
/// Built on [NxCard] rather than a new decoration: depth in this system is a
/// translucent fill, a hairline stroke and a top-edge inner highlight, and
/// `03_design_system.md` forbids reintroducing a shadow in so many words. A
/// card that invented its own surface would be the second visual style the
/// brief rules out.
///
/// **What it deliberately does not show.** No occupancy, no rent, no NOI, no
/// alert count. `PropertySummaryDto` carries none of them, and the list is a
/// plain table read rather than an aggregate — so a card wanting them would
/// have to call `property_overview` once per tile. That is the N+1 the
/// performance rules forbid, and it would also make a scroll of forty cards
/// forty round trips. Those figures belong to a batch read that does not exist
/// yet; until it does, the card shows what the row actually holds and does not
/// imply more.
///
/// The three fields that *are* new here — type, unit count, country — were
/// always on the row and simply never selected.
library;

import 'package:flutter/material.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_cover_image.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/theme/app_theme.dart';
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
    this.coverUrl,
    this.onOpen,
    this.autofocus = false,
    this.opening = false,
  });

  final PropertySummaryDto property;

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
                      // The figure recorded on the property, which is what a
                      // list read can honestly show. It is not a count of
                      // `public.units`, and the two can differ while a
                      // building is still being entered.
                      label: property.units == 1
                          ? '1 Einheit'
                          : '${property.units} Einheiten',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
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
