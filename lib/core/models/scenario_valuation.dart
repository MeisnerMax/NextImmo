class ScenarioValuationRecord {
  const ScenarioValuationRecord({
    required this.scenarioId,
    required this.valuationMode,
    required this.exitCapRatePercent,
    required this.stabilizedNoiMode,
    required this.stabilizedNoiManual,
    required this.stabilizedNoiAvgYears,
    required this.updatedAt,
  });

  final String scenarioId;
  final String valuationMode;
  final double? exitCapRatePercent;
  final String? stabilizedNoiMode;
  final double? stabilizedNoiManual;
  final int? stabilizedNoiAvgYears;
  final int updatedAt;

  static ScenarioValuationRecord defaults({required String scenarioId}) {
    return ScenarioValuationRecord(
      scenarioId: scenarioId,
      valuationMode: 'appreciation',
      exitCapRatePercent: null,
      stabilizedNoiMode: 'use_year1_noi',
      stabilizedNoiManual: null,
      stabilizedNoiAvgYears: 3,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  ScenarioValuationRecord copyWith({
    String? valuationMode,
    double? exitCapRatePercent,
    bool clearExitCapRatePercent = false,
    String? stabilizedNoiMode,
    double? stabilizedNoiManual,
    bool clearStabilizedNoiManual = false,
    int? stabilizedNoiAvgYears,
    bool clearStabilizedNoiAvgYears = false,
    int? updatedAt,
  }) {
    return ScenarioValuationRecord(
      scenarioId: scenarioId,
      valuationMode: valuationMode ?? this.valuationMode,
      exitCapRatePercent:
          clearExitCapRatePercent
              ? null
              : (exitCapRatePercent ?? this.exitCapRatePercent),
      stabilizedNoiMode: stabilizedNoiMode ?? this.stabilizedNoiMode,
      stabilizedNoiManual:
          clearStabilizedNoiManual
              ? null
              : (stabilizedNoiManual ?? this.stabilizedNoiManual),
      stabilizedNoiAvgYears:
          clearStabilizedNoiAvgYears
              ? null
              : (stabilizedNoiAvgYears ?? this.stabilizedNoiAvgYears),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'scenario_id': scenarioId,
      'valuation_mode': valuationMode,
      'exit_cap_rate_percent': exitCapRatePercent,
      'stabilized_noi_mode': stabilizedNoiMode,
      'stabilized_noi_manual': stabilizedNoiManual,
      'stabilized_noi_avg_years': stabilizedNoiAvgYears,
      'updated_at': updatedAt,
    };
  }

  factory ScenarioValuationRecord.fromMap(Map<String, Object?> map) {
    return ScenarioValuationRecord(
      scenarioId: map['scenario_id']! as String,
      valuationMode: (map['valuation_mode'] as String?) ?? 'appreciation',
      exitCapRatePercent: (map['exit_cap_rate_percent'] as num?)?.toDouble(),
      stabilizedNoiMode:
          (map['stabilized_noi_mode'] as String?) ?? 'use_year1_noi',
      stabilizedNoiManual: (map['stabilized_noi_manual'] as num?)?.toDouble(),
      stabilizedNoiAvgYears:
          (map['stabilized_noi_avg_years'] as num?)?.toInt() ?? 3,
      updatedAt:
          ((map['updated_at'] as num?) ?? DateTime.now().millisecondsSinceEpoch)
              .toInt(),
    );
  }
}
