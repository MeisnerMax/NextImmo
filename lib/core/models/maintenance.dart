class MaintenanceTicketRecord {
  const MaintenanceTicketRecord({
    required this.id,
    required this.assetPropertyId,
    required this.unitId,
    required this.title,
    required this.description,
    required this.category,
    required this.status,
    required this.priority,
    required this.reportedAt,
    required this.dueAt,
    required this.resolvedAt,
    required this.costEstimate,
    required this.costActual,
    required this.vendorName,
    required this.documentId,
    required this.damageLocation,
    required this.insuranceCase,
    required this.insuranceStatus,
    required this.insuranceClaimNumber,
    required this.createdAt,
    required this.updatedAt,
    this.startDate,
    this.endDate,
    this.assigneeType,
    this.assigneeName,
    this.building,
    this.area,
    this.technical,
    this.outdoor,
  });

  final String id;
  final String assetPropertyId;
  final String? unitId;
  final String title;
  final String? description;
  final String category;
  final String status;
  final String priority;
  final int reportedAt;
  final int? dueAt;
  final int? resolvedAt;
  final double? costEstimate;
  final double? costActual;
  final String? vendorName;
  final String? documentId;
  final String? damageLocation;
  final bool insuranceCase;
  final String? insuranceStatus;
  final String? insuranceClaimNumber;
  final int createdAt;
  final int updatedAt;
  final int? startDate;
  final int? endDate;
  final String? assigneeType;
  final String? assigneeName;
  final String? building;
  final String? area;
  final String? technical;
  final String? outdoor;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'asset_property_id': assetPropertyId,
      'unit_id': unitId,
      'title': title,
      'description': description,
      'category': category,
      'status': status,
      'priority': priority,
      'reported_at': reportedAt,
      'due_at': dueAt,
      'resolved_at': resolvedAt,
      'cost_estimate': costEstimate,
      'cost_actual': costActual,
      'vendor_name': vendorName,
      'document_id': documentId,
      'damage_location': damageLocation,
      'insurance_case': insuranceCase ? 1 : 0,
      'insurance_status': insuranceStatus,
      'insurance_claim_number': insuranceClaimNumber,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'start_date': startDate,
      'end_date': endDate,
      'assignee_type': assigneeType,
      'assignee_name': assigneeName,
      'building': building,
      'area': area,
      'technical': technical,
      'outdoor': outdoor,
    };
  }

  factory MaintenanceTicketRecord.fromMap(Map<String, Object?> map) {
    return MaintenanceTicketRecord(
      id: map['id']! as String,
      assetPropertyId: map['asset_property_id']! as String,
      unitId: map['unit_id'] as String?,
      title: map['title']! as String,
      description: map['description'] as String?,
      category: (map['category'] as String?) ?? 'general',
      status: map['status']! as String,
      priority: map['priority']! as String,
      reportedAt: (map['reported_at']! as num).toInt(),
      dueAt: (map['due_at'] as num?)?.toInt(),
      resolvedAt: (map['resolved_at'] as num?)?.toInt(),
      costEstimate: (map['cost_estimate'] as num?)?.toDouble(),
      costActual: (map['cost_actual'] as num?)?.toDouble(),
      vendorName: map['vendor_name'] as String?,
      documentId: map['document_id'] as String?,
      damageLocation: map['damage_location'] as String?,
      insuranceCase: ((map['insurance_case'] as num?)?.toInt() ?? 0) == 1,
      insuranceStatus: map['insurance_status'] as String?,
      insuranceClaimNumber: map['insurance_claim_number'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
      startDate: (map['start_date'] as num?)?.toInt(),
      endDate: (map['end_date'] as num?)?.toInt(),
      assigneeType: map['assignee_type'] as String?,
      assigneeName: map['assignee_name'] as String?,
      building: map['building'] as String?,
      area: map['area'] as String?,
      technical: map['technical'] as String?,
      outdoor: map['outdoor'] as String?,
    );
  }
}

class MaintenanceTicketHistoryRecord {
  const MaintenanceTicketHistoryRecord({
    required this.id,
    required this.ticketId,
    required this.action,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String ticketId;
  final String action;
  final String? note;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'ticket_id': ticketId,
      'action': action,
      'note': note,
      'created_at': createdAt,
    };
  }

  factory MaintenanceTicketHistoryRecord.fromMap(Map<String, Object?> map) {
    return MaintenanceTicketHistoryRecord(
      id: map['id']! as String,
      ticketId: map['ticket_id']! as String,
      action: map['action']! as String,
      note: map['note'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class MaintenanceWorkflowRecord {
  const MaintenanceWorkflowRecord({
    required this.ticket,
    required this.propertyName,
    required this.documentName,
    required this.linkedTaskCount,
  });

  final MaintenanceTicketRecord ticket;
  final String? propertyName;
  final String? documentName;
  final int linkedTaskCount;
}
