import '../valuation_factor.dart';
import '../valuation_factor_ids.dart';

/// Outcome of resolving the Bodenwert, shared by the Ertrags- and the
/// Sachwertverfahren: either a value plus the factors it was built from, or the
/// structured gap that makes the calling method report "nicht ermittelbar".
class LandValueResolution {
  const LandValueResolution({
    this.value,
    this.used = const [],
    this.missing = const [],
    this.derived = false,
  });

  final double? value;
  final List<ValuationFactor> used;
  final List<MissingFactor> missing;

  /// Whether the value came from `Fläche × Bodenrichtwert` rather than a
  /// directly supplied Bodenwert.
  final bool derived;
}

/// Resolves the Bodenwert: an explicitly supplied [ValuationFactorIds.landValue]
/// wins, otherwise it is derived from Grundstücksfläche × Bodenrichtwert. When
/// neither path is usable the gap is reported on the Bodenwert itself, so the UI
/// points at one missing concept instead of two unrelated inputs.
LandValueResolution resolveLandValue(FactorSet factors) {
  if (factors.has(ValuationFactorIds.landValue)) {
    return LandValueResolution(
      value: factors.value(ValuationFactorIds.landValue),
      used: [factors[ValuationFactorIds.landValue]!],
    );
  }

  const componentIds = [
    ValuationFactorIds.landAreaSqm,
    ValuationFactorIds.landValuePerSqm,
  ];
  final missing = factors.missingAmong(componentIds);
  if (missing.isNotEmpty) {
    return const LandValueResolution(
      missing: [
        MissingFactor(
          factorId: ValuationFactorIds.landValue,
          label: 'Bodenwert',
          reason: MissingFactorReason.notEntered,
          message:
              'Bodenwert fehlt (direkt oder aus Grundstücksfläche und '
              'Bodenrichtwert).',
        ),
      ],
    );
  }

  final area = factors.value(ValuationFactorIds.landAreaSqm)!;
  final perSqm = factors.value(ValuationFactorIds.landValuePerSqm)!;
  return LandValueResolution(
    value: area * perSqm,
    used: componentIds.map((id) => factors[id]!).toList(growable: false),
    derived: true,
  );
}
