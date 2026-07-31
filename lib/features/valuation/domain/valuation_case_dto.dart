/// Persistence-facing DTOs for the valuation aggregate (P2-D07).
///
/// These mirror the planned `valuation_cases`, `valuation_factors`,
/// `valuation_method_results` and `market_value_opinions` rows field for field,
/// so the SQLite and Supabase adapters agree on one wire shape. The engine's
/// domain types stay free of any storage concern.
///
/// The honesty rule survives serialization: a factor keeps its provenance, and a
/// method result that was "nicht ermittelbar" is stored *as* unavailable with
/// its reasons — never as a row with a substituted amount.
library;

import 'cash_flow_projection.dart';
import 'methods/comparison_approach_method.dart';
import 'valuation_case.dart';
import 'valuation_factor.dart';
import 'valuation_method.dart';
import 'valuation_report.dart';

/// One row of `valuation_cases`.
class ValuationCaseDto {
  const ValuationCaseDto({
    required this.id,
    required this.workspaceId,
    required this.propertyId,
    required this.title,
    required this.kind,
    required this.status,
    required this.dcfTerminal,
    required this.enabledMethods,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required this.version,
    this.scenarioId,
    this.weightOverrides = const {},
    this.minimumComparables = 3,
    this.variantGroupId,
    this.variantLabel,
  }) : assert(
         (variantGroupId == null) == (variantLabel == null),
         'Varianten-Gruppe und -Name gehören zusammen (DEC-023).',
       );

  final String id;
  final String workspaceId;
  final String propertyId;
  final String? scenarioId;
  final String title;
  final ValuationCaseKind kind;
  final ValuationCaseStatus status;
  final DcfTerminalMethod dcfTerminal;
  final Set<ValuationMethodKind> enabledMethods;
  final Map<ValuationMethodKind, double> weightOverrides;
  final int minimumComparables;

  /// Set together with [variantLabel] when this case is one named variant among
  /// siblings (`DEC-023`); both null for a standalone case.
  final String? variantGroupId;
  final String? variantLabel;

  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;
  final int version;

  static ValuationCaseDto? fromJson(Map<String, dynamic> json) {
    final kind = ValuationCaseKind.fromWire(json['kind'] as String?);
    final status = ValuationCaseStatus.fromWire(json['status'] as String?);
    final terminal = DcfTerminalMethod.fromWire(json['dcf_terminal'] as String?);
    final id = json['id'] as String?;
    final workspaceId = json['workspace_id'] as String?;
    final propertyId = json['property_id'] as String?;
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updated_at'] as String? ?? '');
    if (kind == null ||
        status == null ||
        terminal == null ||
        id == null ||
        workspaceId == null ||
        propertyId == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return ValuationCaseDto(
      id: id,
      workspaceId: workspaceId,
      propertyId: propertyId,
      scenarioId: json['scenario_id'] as String?,
      title: json['title'] as String? ?? '',
      kind: kind,
      status: status,
      dcfTerminal: terminal,
      enabledMethods: _methodSet(json['enabled_methods']),
      weightOverrides: _weightMap(json['weight_overrides']),
      minimumComparables: (json['minimum_comparables'] as num?)?.toInt() ?? 3,
      variantGroupId: _variantGroupId(json),
      variantLabel: _variantLabel(json),
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: json['created_by'] as String? ?? '',
      updatedBy: json['updated_by'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'property_id': propertyId,
    'scenario_id': scenarioId,
    'title': title,
    'kind': kind.wireName,
    'status': status.wireName,
    'dcf_terminal': dcfTerminal.wireName,
    'enabled_methods':
        enabledMethods.map((m) => m.wireName).toList(growable: false)..sort(),
    'weight_overrides': <String, dynamic>{
      for (final entry in weightOverrides.entries)
        entry.key.wireName: entry.value,
    },
    'minimum_comparables': minimumComparables,
    'variant_group_id': variantGroupId,
    'variant_label': variantLabel,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'created_by': createdBy,
    'updated_by': updatedBy,
    'version': version,
  };

  /// Rebuilds the engine's aggregate. [factors] and [comparables] are stored
  /// separately (own table / the `comps` aggregate), so they are supplied by the
  /// adapter rather than carried on this row.
  ValuationCase toDomain({
    required Iterable<ValuationFactor> factors,
    List<ComparableSale> comparables = const [],
  }) => ValuationCase(
    id: id,
    propertyId: propertyId,
    scenarioId: scenarioId,
    title: title,
    kind: kind,
    status: status,
    factors: FactorSet(factors),
    comparables: comparables,
    dcfTerminal: dcfTerminal,
    enabledMethods: enabledMethods,
    weightOverrides: weightOverrides,
    minimumComparables: minimumComparables,
  );

  /// Both variant fields are read as a pair: a row that carries only one of
  /// them cannot exist (check constraint), and treating a half-pair as a
  /// grouping would invent a variant the database does not have.
  static String? _variantGroupId(Map<String, dynamic> json) {
    final group = json['variant_group_id'];
    final label = json['variant_label'];
    return group is String && label is String ? group : null;
  }

  static String? _variantLabel(Map<String, dynamic> json) {
    final group = json['variant_group_id'];
    final label = json['variant_label'];
    return group is String && label is String ? label : null;
  }

  static Set<ValuationMethodKind> _methodSet(Object? raw) {
    if (raw is! List) return ValuationCase.allMethodKinds;
    final kinds = <ValuationMethodKind>{};
    for (final entry in raw) {
      final kind = ValuationMethodKind.fromWire(entry as String?);
      if (kind != null) kinds.add(kind);
    }
    return kinds.isEmpty ? ValuationCase.allMethodKinds : kinds;
  }

  static Map<ValuationMethodKind, double> _weightMap(Object? raw) {
    if (raw is! Map) return const {};
    final weights = <ValuationMethodKind, double>{};
    raw.forEach((key, value) {
      final kind = ValuationMethodKind.fromWire(key as String?);
      final weight = (value as num?)?.toDouble();
      if (kind != null && weight != null) weights[kind] = weight;
    });
    return weights;
  }
}

/// One row of `valuation_factors` — the provenance-tagged factor of a case.
class ValuationFactorDto {
  const ValuationFactorDto({
    required this.caseId,
    required this.factorId,
    required this.label,
    required this.provenance,
    required this.confidence,
    this.value,
    this.unit,
    this.source,
    this.note,
  });

  final String caseId;
  final String factorId;
  final String label;
  final FactorProvenance provenance;
  final ConfidenceBand confidence;
  final double? value;
  final String? unit;
  final String? source;
  final String? note;

  factory ValuationFactorDto.fromDomain({
    required String caseId,
    required ValuationFactor factor,
  }) => ValuationFactorDto(
    caseId: caseId,
    factorId: factor.id,
    label: factor.label,
    provenance: factor.provenance,
    confidence: factor.confidence,
    value: factor.value,
    unit: factor.unit,
    source: factor.source,
    note: factor.note,
  );

  static ValuationFactorDto? fromJson(Map<String, dynamic> json) {
    final provenance = FactorProvenance.fromWire(json['provenance'] as String?);
    final caseId = json['valuation_case_id'] as String?;
    final factorId = json['factor_id'] as String?;
    if (provenance == null || caseId == null || factorId == null) return null;
    return ValuationFactorDto(
      caseId: caseId,
      factorId: factorId,
      label: json['label'] as String? ?? factorId,
      provenance: provenance,
      confidence:
          ConfidenceBand.fromWire(json['confidence'] as String?) ??
          ConfidenceBand.unknown,
      value: (json['value'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
      source: json['source'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'valuation_case_id': caseId,
    'factor_id': factorId,
    'label': label,
    'provenance': provenance.wireName,
    'confidence': confidence.wireName,
    'value': value,
    'unit': unit,
    'source': source,
    'note': note,
  };

  ValuationFactor toDomain() => ValuationFactor(
    id: factorId,
    label: label,
    provenance: provenance,
    value: value,
    unit: unit,
    source: source,
    note: note,
    confidence: confidence,
  );
}

/// One row of `valuation_method_results`: what a single method concluded, value
/// *or* explicit unavailability with its reasons.
class ValuationMethodResultDto {
  const ValuationMethodResultDto({
    required this.caseId,
    required this.method,
    required this.isAvailable,
    this.amount,
    this.confidence,
    this.breakdown = const [],
    this.assumptions = const [],
    this.missingFactors = const [],
    this.reasons = const [],
  });

  final String caseId;
  final ValuationMethodKind method;

  /// False for a stored "nicht ermittelbar" — then [amount] is null and
  /// [missingFactors]/[reasons] carry the explanation.
  final bool isAvailable;
  final double? amount;
  final ConfidenceBand? confidence;
  final List<Map<String, dynamic>> breakdown;
  final List<Map<String, dynamic>> assumptions;
  final List<Map<String, dynamic>> missingFactors;
  final List<String> reasons;

  factory ValuationMethodResultDto.fromDomain({
    required String caseId,
    required ValuationMethodKind method,
    required MethodResult result,
  }) => switch (result) {
    MethodValue(:final amount, :final confidence, :final breakdown, :final assumptions) =>
      ValuationMethodResultDto(
        caseId: caseId,
        method: method,
        isAvailable: true,
        amount: amount,
        confidence: confidence,
        breakdown:
            breakdown
                .map(
                  (line) => <String, dynamic>{
                    'label': line.label,
                    'amount': line.amount,
                    'unit': line.unit,
                    'formula': line.formula,
                    'note': line.note,
                  },
                )
                .toList(growable: false),
        assumptions:
            assumptions
                .map(
                  (a) => <String, dynamic>{
                    'factor_id': a.factorId,
                    'label': a.label,
                    'provenance': a.provenance.wireName,
                    'value': a.value,
                    'unit': a.unit,
                    'source': a.source,
                  },
                )
                .toList(growable: false),
      ),
    MethodUnavailable(:final missingFactors, :final reasons) =>
      ValuationMethodResultDto(
        caseId: caseId,
        method: method,
        isAvailable: false,
        missingFactors:
            missingFactors
                .map(
                  (m) => <String, dynamic>{
                    'factor_id': m.factorId,
                    'label': m.label,
                    'reason': m.reason.name,
                    'message': m.message,
                  },
                )
                .toList(growable: false),
        reasons: List<String>.from(reasons),
      ),
  };

  static ValuationMethodResultDto? fromJson(Map<String, dynamic> json) {
    final method = ValuationMethodKind.fromWire(json['method'] as String?);
    final caseId = json['valuation_case_id'] as String?;
    if (method == null || caseId == null) return null;
    return ValuationMethodResultDto(
      caseId: caseId,
      method: method,
      isAvailable: json['is_available'] as bool? ?? false,
      amount: (json['amount'] as num?)?.toDouble(),
      confidence: ConfidenceBand.fromWire(json['confidence'] as String?),
      breakdown: _objectList(json['breakdown']),
      assumptions: _objectList(json['assumptions']),
      missingFactors: _objectList(json['missing_factors']),
      reasons: _stringList(json['reasons']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'valuation_case_id': caseId,
    'method': method.wireName,
    'is_available': isAvailable,
    'amount': amount,
    'confidence': confidence?.wireName,
    'breakdown': breakdown,
    'assumptions': assumptions,
    'missing_factors': missingFactors,
    'reasons': reasons,
  };
}

/// One row of `market_value_opinions`: the reconciled Verkehrswert of a case, or
/// the recorded statement that it was not determinable.
class MarketValueOpinionDto {
  const MarketValueOpinionDto({
    required this.caseId,
    required this.isAvailable,
    this.amount,
    this.confidence,
    this.weights = const {},
    this.rationale = '',
    this.unavailableMethods = const [],
  });

  final String caseId;
  final bool isAvailable;
  final double? amount;
  final ConfidenceBand? confidence;
  final Map<ValuationMethodKind, double> weights;

  /// The weighting justification, or the reason no value could be concluded.
  final String rationale;
  final List<ValuationMethodKind> unavailableMethods;

  factory MarketValueOpinionDto.fromDomain({
    required String caseId,
    required MarketValueOpinion opinion,
  }) => switch (opinion) {
    MarketValue(:final amount, :final confidence, :final weights, :final rationale) =>
      MarketValueOpinionDto(
        caseId: caseId,
        isAvailable: true,
        amount: amount,
        confidence: confidence,
        weights: weights,
        rationale: rationale,
      ),
    MarketValueUnavailable(:final reason, :final unavailableMethods) =>
      MarketValueOpinionDto(
        caseId: caseId,
        isAvailable: false,
        rationale: reason,
        unavailableMethods: unavailableMethods,
      ),
  };

  static MarketValueOpinionDto? fromJson(Map<String, dynamic> json) {
    final caseId = json['valuation_case_id'] as String?;
    if (caseId == null) return null;
    return MarketValueOpinionDto(
      caseId: caseId,
      isAvailable: json['is_available'] as bool? ?? false,
      amount: (json['amount'] as num?)?.toDouble(),
      confidence: ConfidenceBand.fromWire(json['confidence'] as String?),
      weights: ValuationCaseDto._weightMap(json['weights']),
      rationale: json['rationale'] as String? ?? '',
      unavailableMethods:
          _stringList(json['unavailable_methods'])
              .map(ValuationMethodKind.fromWire)
              .whereType<ValuationMethodKind>()
              .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'valuation_case_id': caseId,
    'is_available': isAvailable,
    'amount': amount,
    'confidence': confidence?.wireName,
    'weights': <String, dynamic>{
      for (final entry in weights.entries) entry.key.wireName: entry.value,
    },
    'rationale': rationale,
    'unavailable_methods':
        unavailableMethods.map((m) => m.wireName).toList(growable: false),
  };
}

List<Map<String, dynamic>> _objectList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().toList(growable: false);
}
