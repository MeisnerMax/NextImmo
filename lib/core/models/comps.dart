class CompSale {
  const CompSale({
    required this.id,
    required this.propertyId,
    required this.address,
    required this.price,
    this.sqft,
    this.beds,
    this.baths,
    this.distanceKm,
    this.soldDate,
    required this.selected,
    required this.weight,
    this.source,
    required this.createdAt,
  });

  final String id;
  final String propertyId;
  final String address;
  final double price;
  final double? sqft;
  final double? beds;
  final double? baths;
  final double? distanceKm;
  final int? soldDate;
  final bool selected;
  final double weight;
  final String? source;
  final int createdAt;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'property_id': propertyId,
    'address': address,
    'price': price,
    'sqft': sqft,
    'beds': beds,
    'baths': baths,
    'distance_km': distanceKm,
    'sold_date': soldDate,
    'selected': selected ? 1 : 0,
    'weight': weight,
    'source': source,
    'created_at': createdAt,
  };

  factory CompSale.fromMap(Map<String, Object?> map) {
    return CompSale(
      id: map['id']! as String,
      propertyId: map['property_id']! as String,
      address: map['address']! as String,
      price: ((map['price'] as num?) ?? 0).toDouble(),
      sqft: (map['sqft'] as num?)?.toDouble(),
      beds: (map['beds'] as num?)?.toDouble(),
      baths: (map['baths'] as num?)?.toDouble(),
      distanceKm: (map['distance_km'] as num?)?.toDouble(),
      soldDate: (map['sold_date'] as num?)?.toInt(),
      selected: ((map['selected'] as num?) ?? 1) == 1,
      weight: ((map['weight'] as num?) ?? 1).toDouble(),
      source: map['source'] as String?,
      createdAt: ((map['created_at'] as num?) ?? 0).toInt(),
    );
  }
}

class CompRental {
  const CompRental({
    required this.id,
    required this.propertyId,
    required this.address,
    required this.rentMonthly,
    this.sqft,
    this.beds,
    this.baths,
    this.distanceKm,
    this.listedDate,
    required this.selected,
    required this.weight,
    this.source,
    required this.createdAt,
  });

  final String id;
  final String propertyId;
  final String address;
  final double rentMonthly;
  final double? sqft;
  final double? beds;
  final double? baths;
  final double? distanceKm;
  final int? listedDate;
  final bool selected;
  final double weight;
  final String? source;
  final int createdAt;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'property_id': propertyId,
    'address': address,
    'rent_monthly': rentMonthly,
    'sqft': sqft,
    'beds': beds,
    'baths': baths,
    'distance_km': distanceKm,
    'listed_date': listedDate,
    'selected': selected ? 1 : 0,
    'weight': weight,
    'source': source,
    'created_at': createdAt,
  };

  factory CompRental.fromMap(Map<String, Object?> map) {
    return CompRental(
      id: map['id']! as String,
      propertyId: map['property_id']! as String,
      address: map['address']! as String,
      rentMonthly: ((map['rent_monthly'] as num?) ?? 0).toDouble(),
      sqft: (map['sqft'] as num?)?.toDouble(),
      beds: (map['beds'] as num?)?.toDouble(),
      baths: (map['baths'] as num?)?.toDouble(),
      distanceKm: (map['distance_km'] as num?)?.toDouble(),
      listedDate: (map['listed_date'] as num?)?.toInt(),
      selected: ((map['selected'] as num?) ?? 1) == 1,
      weight: ((map['weight'] as num?) ?? 1).toDouble(),
      source: map['source'] as String?,
      createdAt: ((map['created_at'] as num?) ?? 0).toInt(),
    );
  }
}
