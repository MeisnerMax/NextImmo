class ScenarioWorkflowStatus {
  const ScenarioWorkflowStatus._();

  static const String draft = 'draft';
  static const String inReview = 'in_review';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
  static const String archived = 'archived';

  static const Set<String> values = <String>{
    draft,
    inReview,
    approved,
    rejected,
    archived,
  };
}

class ScenarioRecord {
  const ScenarioRecord({
    required this.id,
    required this.propertyId,
    required this.name,
    required this.strategyType,
    required this.isBase,
    this.workflowStatus = ScenarioWorkflowStatus.draft,
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectedAt,
    this.reviewComment,
    this.changedSinceApproval = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String propertyId;
  final String name;
  final String strategyType;
  final bool isBase;
  final String workflowStatus;
  final String? approvedBy;
  final int? approvedAt;
  final String? rejectedBy;
  final int? rejectedAt;
  final String? reviewComment;
  final bool changedSinceApproval;
  final int createdAt;
  final int updatedAt;

  bool get isApproved => workflowStatus == ScenarioWorkflowStatus.approved;

  ScenarioRecord copyWith({
    String? name,
    String? strategyType,
    bool? isBase,
    String? workflowStatus,
    String? approvedBy,
    int? approvedAt,
    String? rejectedBy,
    int? rejectedAt,
    String? reviewComment,
    bool? changedSinceApproval,
    int? updatedAt,
  }) {
    return ScenarioRecord(
      id: id,
      propertyId: propertyId,
      name: name ?? this.name,
      strategyType: strategyType ?? this.strategyType,
      isBase: isBase ?? this.isBase,
      workflowStatus: workflowStatus ?? this.workflowStatus,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      reviewComment: reviewComment ?? this.reviewComment,
      changedSinceApproval: changedSinceApproval ?? this.changedSinceApproval,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'property_id': propertyId,
      'name': name,
      'strategy_type': strategyType,
      'is_base': isBase ? 1 : 0,
      'workflow_status': workflowStatus,
      'approved_by': approvedBy,
      'approved_at': approvedAt,
      'rejected_by': rejectedBy,
      'rejected_at': rejectedAt,
      'review_comment': reviewComment,
      'changed_since_approval': changedSinceApproval ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ScenarioRecord.fromMap(Map<String, Object?> map) {
    return ScenarioRecord(
      id: map['id']! as String,
      propertyId: map['property_id']! as String,
      name: map['name']! as String,
      strategyType: map['strategy_type']! as String,
      isBase: ((map['is_base'] as num?) ?? 0) == 1,
      workflowStatus:
          (map['workflow_status'] as String?) ?? ScenarioWorkflowStatus.draft,
      approvedBy: map['approved_by'] as String?,
      approvedAt: (map['approved_at'] as num?)?.toInt(),
      rejectedBy: map['rejected_by'] as String?,
      rejectedAt: (map['rejected_at'] as num?)?.toInt(),
      reviewComment: map['review_comment'] as String?,
      changedSinceApproval:
          ((map['changed_since_approval'] as num?) ?? 0) == 1,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}
