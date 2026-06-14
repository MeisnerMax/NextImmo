class ContactRecord {
  const ContactRecord({
    required this.id,
    required this.displayName,
    this.legalName,
    required this.role,
    this.email,
    this.phone,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String displayName;
  final String? legalName;
  final String role;
  final String? email;
  final String? phone;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  factory ContactRecord.fromMap(Map<String, Object?> map) {
    return ContactRecord(
      id: map['id']! as String,
      displayName: map['display_name']! as String,
      legalName: map['legal_name'] as String?,
      role: (map['role'] as String?) ?? 'other',
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      notes: map['notes'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class PropertySaleDetailsRecord {
  const PropertySaleDetailsRecord({
    required this.propertyId,
    this.askingPrice,
    this.minimumPrice,
    required this.saleStatus,
    this.listedAt,
    this.reservedAt,
    this.soldAt,
    this.notaryDate,
    this.notes,
    required this.updatedAt,
  });

  final String propertyId;
  final double? askingPrice;
  final double? minimumPrice;
  final String saleStatus;
  final int? listedAt;
  final int? reservedAt;
  final int? soldAt;
  final int? notaryDate;
  final String? notes;
  final int updatedAt;

  factory PropertySaleDetailsRecord.fromMap(Map<String, Object?> map) {
    return PropertySaleDetailsRecord(
      propertyId: map['property_id']! as String,
      askingPrice: (map['asking_price'] as num?)?.toDouble(),
      minimumPrice: (map['minimum_price'] as num?)?.toDouble(),
      saleStatus: (map['sale_status'] as String?) ?? 'draft',
      listedAt: (map['listed_at'] as num?)?.toInt(),
      reservedAt: (map['reserved_at'] as num?)?.toInt(),
      soldAt: (map['sold_at'] as num?)?.toInt(),
      notaryDate: (map['notary_date'] as num?)?.toInt(),
      notes: map['notes'] as String?,
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class BuyerInterestRecord {
  const BuyerInterestRecord({
    required this.id,
    required this.propertyId,
    this.unitId,
    this.contactId,
    required this.interestStatus,
    this.budgetAmount,
    this.offerAmount,
    this.viewingAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String propertyId;
  final String? unitId;
  final String? contactId;
  final String interestStatus;
  final double? budgetAmount;
  final double? offerAmount;
  final int? viewingAt;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  factory BuyerInterestRecord.fromMap(Map<String, Object?> map) {
    return BuyerInterestRecord(
      id: map['id']! as String,
      propertyId: map['property_id']! as String,
      unitId: map['unit_id'] as String?,
      contactId: map['contact_id'] as String?,
      interestStatus: (map['interest_status'] as String?) ?? 'active',
      budgetAmount: (map['budget_amount'] as num?)?.toDouble(),
      offerAmount: (map['offer_amount'] as num?)?.toDouble(),
      viewingAt: (map['viewing_at'] as num?)?.toInt(),
      notes: map['notes'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class ReservationRecord {
  const ReservationRecord({
    required this.id,
    required this.propertyId,
    this.unitId,
    this.guestContactId,
    required this.checkIn,
    required this.checkOut,
    required this.reservationStatus,
    this.totalAmount,
    this.source,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String propertyId;
  final String? unitId;
  final String? guestContactId;
  final int checkIn;
  final int checkOut;
  final String reservationStatus;
  final double? totalAmount;
  final String? source;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  factory ReservationRecord.fromMap(Map<String, Object?> map) {
    return ReservationRecord(
      id: map['id']! as String,
      propertyId: map['property_id']! as String,
      unitId: map['unit_id'] as String?,
      guestContactId: map['guest_contact_id'] as String?,
      checkIn: (map['check_in']! as num).toInt(),
      checkOut: (map['check_out']! as num).toInt(),
      reservationStatus: (map['reservation_status'] as String?) ?? 'reserved',
      totalAmount: (map['total_amount'] as num?)?.toDouble(),
      source: map['source'] as String?,
      notes: map['notes'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class UnitSaleDetailsRecord {
  const UnitSaleDetailsRecord({
    required this.unitId,
    required this.propertyId,
    required this.saleStatus,
    this.askingPrice,
    this.minimumPrice,
    this.reservedAt,
    this.soldAt,
    this.buyerContactId,
    this.notes,
    required this.updatedAt,
  });

  final String unitId;
  final String propertyId;
  final String saleStatus;
  final double? askingPrice;
  final double? minimumPrice;
  final int? reservedAt;
  final int? soldAt;
  final String? buyerContactId;
  final String? notes;
  final int updatedAt;

  factory UnitSaleDetailsRecord.fromMap(Map<String, Object?> map) {
    return UnitSaleDetailsRecord(
      unitId: map['unit_id']! as String,
      propertyId: map['property_id']! as String,
      saleStatus: (map['sale_status'] as String?) ?? 'available',
      askingPrice: (map['asking_price'] as num?)?.toDouble(),
      minimumPrice: (map['minimum_price'] as num?)?.toDouble(),
      reservedAt: (map['reserved_at'] as num?)?.toInt(),
      soldAt: (map['sold_at'] as num?)?.toInt(),
      buyerContactId: map['buyer_contact_id'] as String?,
      notes: map['notes'] as String?,
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

