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
    this.landArea,
    this.residentialArea,
    this.commercialArea,
    this.parkingSpots,
    this.ownerCompany,
    this.purchaseDate,
    this.purchasePrice,
    this.notary,
    this.seller,
    this.landRegistryDetails,
    this.parcel,
    this.energyCertificate,
    this.insuranceDetails,
    this.taxAssignment,
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
  final double? landArea;
  final double? residentialArea;
  final double? commercialArea;
  final int? parkingSpots;
  final String? ownerCompany;
  final int? purchaseDate;
  final double? purchasePrice;
  final String? notary;
  final String? seller;
  final String? landRegistryDetails;
  final String? parcel;
  final String? energyCertificate;
  final String? insuranceDetails;
  final String? taxAssignment;

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
      'land_area': landArea,
      'residential_area': residentialArea,
      'commercial_area': commercialArea,
      'parking_spots': parkingSpots,
      'owner_company': ownerCompany,
      'purchase_date': purchaseDate,
      'purchase_price': purchasePrice,
      'notary': notary,
      'seller': seller,
      'land_registry_details': landRegistryDetails,
      'parcel': parcel,
      'energy_certificate': energyCertificate,
      'insurance_details': insuranceDetails,
      'tax_assignment': taxAssignment,
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
      landArea: (map['land_area'] as num?)?.toDouble(),
      residentialArea: (map['residential_area'] as num?)?.toDouble(),
      commercialArea: (map['commercial_area'] as num?)?.toDouble(),
      parkingSpots: (map['parking_spots'] as num?)?.toInt(),
      ownerCompany: map['owner_company'] as String?,
      purchaseDate: (map['purchase_date'] as num?)?.toInt(),
      purchasePrice: (map['purchase_price'] as num?)?.toDouble(),
      notary: map['notary'] as String?,
      seller: map['seller'] as String?,
      landRegistryDetails: map['land_registry_details'] as String?,
      parcel: map['parcel'] as String?,
      energyCertificate: map['energy_certificate'] as String?,
      insuranceDetails: map['insurance_details'] as String?,
      taxAssignment: map['tax_assignment'] as String?,
    );
  }
}
