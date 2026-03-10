class MaintenanceTicketRecord {
  const MaintenanceTicketRecord({
    required this.id,
    required this.assetPropertyId,
    required this.unitId,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.reportedAt,
    required this.dueAt,
    required this.resolvedAt,
    required this.costEstimate,
    required this.costActual,
    required this.vendorName,
    required this.documentId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String assetPropertyId;
  final String? unitId;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final int reportedAt;
  final int? dueAt;
  final int? resolvedAt;
  final double? costEstimate;
  final double? costActual;
  final String? vendorName;
  final String? documentId;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'asset_property_id': assetPropertyId,
      'unit_id': unitId,
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
      'reported_at': reportedAt,
      'due_at': dueAt,
      'resolved_at': resolvedAt,
      'cost_estimate': costEstimate,
      'cost_actual': costActual,
      'vendor_name': vendorName,
      'document_id': documentId,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory MaintenanceTicketRecord.fromMap(Map<String, Object?> map) {
    return MaintenanceTicketRecord(
      id: map['id']! as String,
      assetPropertyId: map['asset_property_id']! as String,
      unitId: map['unit_id'] as String?,
      title: map['title']! as String,
      description: map['description'] as String?,
      status: map['status']! as String,
      priority: map['priority']! as String,
      reportedAt: (map['reported_at']! as num).toInt(),
      dueAt: (map['due_at'] as num?)?.toInt(),
      resolvedAt: (map['resolved_at'] as num?)?.toInt(),
      costEstimate: (map['cost_estimate'] as num?)?.toDouble(),
      costActual: (map['cost_actual'] as num?)?.toDouble(),
      vendorName: map['vendor_name'] as String?,
      documentId: map['document_id'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
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
