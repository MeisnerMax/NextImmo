class PropertyRecord {
  const PropertyRecord({
    required this.id,
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
    required this.createdAt,
    required this.updatedAt,
    this.archived = false,
  });

  final String id;
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
  final int createdAt;
  final int updatedAt;
  final bool archived;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'address_line1': addressLine1,
      'address_line2': addressLine2,
      'zip': zip,
      'city': city,
      'country': country,
      'property_type': propertyType,
      'units': units,
      'sqft': sqft,
      'year_built': yearBuilt,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'archived': archived ? 1 : 0,
    };
  }

  factory PropertyRecord.fromMap(Map<String, Object?> map) {
    return PropertyRecord(
      id: map['id']! as String,
      name: map['name']! as String,
      addressLine1: map['address_line1']! as String,
      addressLine2: map['address_line2'] as String?,
      zip: map['zip']! as String,
      city: map['city']! as String,
      country: map['country']! as String,
      propertyType: map['property_type']! as String,
      units: (map['units']! as num).toInt(),
      sqft: (map['sqft'] as num?)?.toDouble(),
      yearBuilt: (map['year_built'] as num?)?.toInt(),
      notes: map['notes'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
      archived: ((map['archived'] as num?) ?? 0) == 1,
    );
  }
}
