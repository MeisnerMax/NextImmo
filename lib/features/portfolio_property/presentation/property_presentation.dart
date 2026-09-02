import '../../../ui/components/nx_status_badge.dart';
import '../domain/property_dto.dart';

/// Property-internal presentation helpers shared by the workspace host, the
/// list and the asset surface. Deliberately not shared UI: the mappings live
/// beside the domain enum they describe (Foundation §12).

/// German product label for a property status. The label — not the badge
/// colour — carries the meaning (Foundation §12/§16).
String propertyStatusLabel(PropertyStatus status) {
  return switch (status) {
    PropertyStatus.draft => 'Entwurf',
    PropertyStatus.active => 'Aktiv',
    PropertyStatus.archived => 'Archiviert',
  };
}

NxBadgeKind propertyStatusBadgeKind(PropertyStatus status) {
  return switch (status) {
    PropertyStatus.active => NxBadgeKind.success,
    PropertyStatus.draft => NxBadgeKind.warning,
    PropertyStatus.archived => NxBadgeKind.neutral,
  };
}

/// `Musterstraße 1, 12345 Berlin` — the secondary location line of a
/// property. Tolerates blank parts so a sparsely filled record never renders
/// dangling separators.
String propertyLocationLine(PropertySummaryDto property) {
  final street = property.addressLine1.trim();
  final place = '${property.zip.trim()} ${property.city.trim()}'.trim();
  if (street.isEmpty) {
    return place;
  }
  if (place.isEmpty) {
    return street;
  }
  return '$street, $place';
}

/// `dd.MM.yyyy HH:mm` in local time. No `intl` dependency exists in this
/// app and none is added for a single timestamp.
String formatPropertyTimestamp(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Renders the stored `sqft` value in its contract unit. The number is shown
/// with a German decimal comma and without a trailing `,0`; there is no
/// conversion to m² (spec `PROPERTY_ASSET_V2.md` §20).
String formatSquareFeet(double value) {
  final text =
      value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();
  return '${text.replaceAll('.', ',')} ft²';
}
