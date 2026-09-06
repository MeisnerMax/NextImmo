enum PropertyStatus { draft, active, archived }

class PropertySummaryDto {
  const PropertySummaryDto({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.addressLine1,
    required this.zip,
    required this.city,
    required this.status,
    required this.version,
    required this.propertyType,
    required this.country,
    required this.units,
  });

  final String id;
  final String workspaceId;
  final String name;
  final String addressLine1;
  final String zip;
  final String city;
  final PropertyStatus status;
  final int version;

  /// Free text at the database level, not an enum: `property_type` is
  /// `text not null` and the create dialog asks for a code. A build that does
  /// not know a value shows it rather than dropping it.
  final String propertyType;

  final String country;

  /// The unit count carried on the property row itself — the figure the
  /// creator stated, not a count of `public.units`. Those can differ while a
  /// building is being recorded, and the card says which one it shows.
  final int units;

  factory PropertySummaryDto.fromProperty(PropertyDto property) {
    return PropertySummaryDto(
      id: property.id,
      workspaceId: property.workspaceId,
      name: property.name,
      addressLine1: property.addressLine1,
      zip: property.zip,
      city: property.city,
      status: property.status,
      version: property.version,
      propertyType: property.propertyType,
      country: property.country,
      units: property.units,
    );
  }
}

class PropertyDto extends PropertySummaryDto {
  const PropertyDto({
    required super.id,
    required super.workspaceId,
    required super.name,
    required super.addressLine1,
    this.addressLine2,
    required super.zip,
    required super.city,
    required super.country,
    required super.propertyType,
    required super.units,
    this.sqft,
    this.yearBuilt,
    this.notes,
    required super.status,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required super.version,
    this.deletedAt,
    this.deletedBy,
  });

  final String? addressLine2;
  final double? sqft;
  final int? yearBuilt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;
  final DateTime? deletedAt;

  /// User that tombstoned (archived) the property, mirroring the SQLite
  /// `deleted_by` marker. Populated only on reads that select the row
  /// (`getById`/`list`); the `update` RPC result does not carry it.
  final String? deletedBy;
}

class PropertyUpdateDto {
  const PropertyUpdateDto({
    required this.name,
    required this.addressLine1,
    this.addressLine2,
    required this.zip,
    required this.city,
    required this.country,
    required this.propertyType,
    required this.units,
    this.sqft,
    this.yearBuilt,
    this.notes,
    required this.status,
  });

  final String name;
  final String addressLine1;
  final String? addressLine2;
  final String zip;
  final String city;
  final String country;
  final String propertyType;
  final int units;
  final double? sqft;
  final int? yearBuilt;
  final String? notes;
  final PropertyStatus status;
}

/// The fields a new property carries (PROPERTY-DATA-02).
///
/// Deliberately smaller than [PropertyUpdateDto]: `status` is not settable —
/// a created property always starts as [PropertyStatus.draft], and promoting
/// it is an explicit, audited update. `version`, ids and actor metadata are
/// server-owned.
class PropertyCreateDto {
  const PropertyCreateDto({
    required this.name,
    required this.addressLine1,
    this.addressLine2,
    required this.zip,
    required this.city,
    required this.country,
    required this.propertyType,
    this.units = 0,
    this.sqft,
    this.yearBuilt,
    this.notes,
  });

  final String name;
  final String addressLine1;
  final String? addressLine2;
  final String zip;
  final String city;
  final String country;
  final String propertyType;
  final int units;
  final double? sqft;
  final int? yearBuilt;
  final String? notes;
}
