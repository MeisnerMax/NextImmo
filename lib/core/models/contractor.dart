import 'dart:convert';

/// Handwerker-Stammdaten (Contractor record)
class ContractorRecord {
  const ContractorRecord({
    required this.id,
    required this.companyName,
    required this.tradeCategory,
    required this.contactName,
    required this.phone,
    required this.email,
    required this.address,
    required this.hourlyRate,
    required this.serviceAreas,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.ratingPrice,
    this.ratingQuality,
    this.ratingSpeed,
    this.ratingCommunication,
    this.ratingPunctuality,
    this.insuranceCertExpiry,
    this.isActive = true,
  });

  final String id;
  final String companyName;
  final String tradeCategory;
  final String contactName;
  final String phone;
  final String email;
  final String address;
  final double? hourlyRate;
  final List<String> serviceAreas;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  // Ratings 1–5
  final double? ratingPrice;
  final double? ratingQuality;
  final double? ratingSpeed;
  final double? ratingCommunication;
  final double? ratingPunctuality;

  final int? insuranceCertExpiry;
  final bool isActive;

  /// Average rating across all criteria
  double? get overallRating {
    final vals = <double>[
      if (ratingPrice != null) ratingPrice!,
      if (ratingQuality != null) ratingQuality!,
      if (ratingSpeed != null) ratingSpeed!,
      if (ratingCommunication != null) ratingCommunication!,
      if (ratingPunctuality != null) ratingPunctuality!,
    ];
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'company_name': companyName,
      'trade_category': tradeCategory,
      'contact_name': contactName,
      'phone': phone,
      'email': email,
      'address': address,
      'hourly_rate': hourlyRate,
      'service_areas_json': jsonEncode(serviceAreas),
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'rating_price': ratingPrice,
      'rating_quality': ratingQuality,
      'rating_speed': ratingSpeed,
      'rating_communication': ratingCommunication,
      'rating_punctuality': ratingPunctuality,
      'insurance_cert_expiry': insuranceCertExpiry,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory ContractorRecord.fromMap(Map<String, Object?> map) {
    List<String> areas = [];
    final jsonStr = map['service_areas_json'] as String?;
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        areas = List<String>.from(jsonDecode(jsonStr) as List);
      } catch (_) {}
    }
    return ContractorRecord(
      id: map['id']! as String,
      companyName: map['company_name']! as String,
      tradeCategory: map['trade_category']! as String,
      contactName: map['contact_name']! as String,
      phone: map['phone']! as String,
      email: map['email']! as String,
      address: map['address']! as String,
      hourlyRate: map['hourly_rate'] as double?,
      serviceAreas: areas,
      notes: map['notes'] as String?,
      createdAt: ((map['created_at'] as num?) ?? 0).toInt(),
      updatedAt: ((map['updated_at'] as num?) ?? 0).toInt(),
      ratingPrice: map['rating_price'] as double?,
      ratingQuality: map['rating_quality'] as double?,
      ratingSpeed: map['rating_speed'] as double?,
      ratingCommunication: map['rating_communication'] as double?,
      ratingPunctuality: map['rating_punctuality'] as double?,
      insuranceCertExpiry: map['insurance_cert_expiry'] as int?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }
}

/// Common trade categories (Gewerke)
const List<String> kTradeCategories = [
  'Elektrik',
  'Sanitär / Heizung',
  'Dach',
  'Fassade',
  'Maler / Lackierer',
  'Trockenbau',
  'Böden',
  'Fenster / Türen',
  'Schlüsseldienst',
  'Schädlingsbekämpfung',
  'Garten / Landschaftsbau',
  'Reinigung',
  'Aufzug / Wartung',
  'Brandschutz',
  'Kälte / Klima',
  'Sonstiges',
];
