class CriteriaSet {
  const CriteriaSet({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final bool isDefault;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'is_default': isDefault ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory CriteriaSet.fromMap(Map<String, Object?> map) {
    return CriteriaSet(
      id: map['id']! as String,
      name: map['name']! as String,
      isDefault: ((map['is_default'] as num?) ?? 0) == 1,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class CriteriaRule {
  const CriteriaRule({
    required this.id,
    required this.criteriaSetId,
    required this.fieldKey,
    required this.operator,
    required this.targetValue,
    required this.unit,
    required this.severity,
    required this.enabled,
  });

  final String id;
  final String criteriaSetId;
  final String fieldKey;
  final String operator;
  final double targetValue;
  final String unit;
  final String severity;
  final bool enabled;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'criteria_set_id': criteriaSetId,
      'field_key': fieldKey,
      'operator': operator,
      'target_value': targetValue,
      'unit': unit,
      'severity': severity,
      'enabled': enabled ? 1 : 0,
    };
  }

  factory CriteriaRule.fromMap(Map<String, Object?> map) {
    return CriteriaRule(
      id: map['id']! as String,
      criteriaSetId: map['criteria_set_id']! as String,
      fieldKey: map['field_key']! as String,
      operator: map['operator']! as String,
      targetValue: ((map['target_value'] as num?) ?? 0).toDouble(),
      unit: map['unit']! as String,
      severity: map['severity']! as String,
      enabled: ((map['enabled'] as num?) ?? 1) == 1,
    );
  }
}

class RuleEvaluation {
  const RuleEvaluation({
    required this.rule,
    required this.actualValue,
    required this.pass,
    required this.unknown,
  });

  final CriteriaRule rule;
  final double? actualValue;
  final bool pass;
  final bool unknown;
}

class CriteriaEvaluationResult {
  const CriteriaEvaluationResult({
    required this.passed,
    required this.evaluations,
    required this.failed,
    required this.warnings,
    required this.unknown,
  });

  final bool passed;
  final List<RuleEvaluation> evaluations;
  final List<RuleEvaluation> failed;
  final List<RuleEvaluation> warnings;
  final List<RuleEvaluation> unknown;
}
