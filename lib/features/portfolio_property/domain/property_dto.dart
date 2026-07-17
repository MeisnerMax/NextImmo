enum PropertyStatus { draft, active, archived }

class PropertyDto {
  const PropertyDto({
    required this.id,
    required this.workspaceId,
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
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required this.version,
    this.deletedAt,
  });

  final String id;
  final String workspaceId;
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
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;
  final int version;
  final DateTime? deletedAt;
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
