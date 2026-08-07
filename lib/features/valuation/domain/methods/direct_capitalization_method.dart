import '../valuation_factor.dart';
import '../valuation_factor_ids.dart';
import '../valuation_method.dart';

/// Direktkapitalisierung: value = stabilized NOI / cap rate. The stabilized NOI
/// is taken directly when provided, otherwise derived from Rohertrag, vacancy
/// and Bewirtschaftungskosten. Also surfaces the common quick ratios
/// (Brutto-/Nettoanfangsrendite, Faktor) when a purchase price is available.
class DirectCapitalizationMethod implements ValuationMethod {
  const DirectCapitalizationMethod();

  @override
  ValuationMethodKind get kind => ValuationMethodKind.directCapitalization;

  @override
  String get name => 'Direktkapitalisierung';

  @override
  MethodResult evaluate(FactorSet factors) {
    final capMissing = factors.missingAmong([ValuationFactorIds.capRate]);

    // Resolve NOI: prefer an explicit stabilized NOI, else derive from parts.
    final used = <ValuationFactor>[];
    double? noi;
    final noiComponentMissing = <MissingFactor>[];

    if (factors.has(ValuationFactorIds.stabilizedNoiAnnual)) {
      noi = factors.value(ValuationFactorIds.stabilizedNoiAnnual);
      used.add(factors[ValuationFactorIds.stabilizedNoiAnnual]!);
    } else {
      final componentIds = [
        ValuationFactorIds.grossRentAnnual,
        ValuationFactorIds.vacancyRate,
        ValuationFactorIds.operatingExpensesAnnual,
      ];
      final missing = factors.missingAmong(componentIds);
      if (missing.isEmpty) {
        final grossRent = factors.value(ValuationFactorIds.grossRentAnnual)!;
        final vacancy = factors.value(ValuationFactorIds.vacancyRate)!;
        final opex = factors.value(ValuationFactorIds.operatingExpensesAnnual)!;
        noi = grossRent * (1 - vacancy) - opex;
        used.addAll(componentIds.map((id) => factors[id]!));
      } else {
        // Report the stabilized-NOI gap rather than every component.
        noiComponentMissing.add(
          MissingFactor(
            factorId: ValuationFactorIds.stabilizedNoiAnnual,
            label: 'Reinertrag p.a.',
            reason: MissingFactorReason.notEntered,
            message:
                'Reinertrag p.a. fehlt (direkt oder aus Rohertrag, '
                'Leerstand und Bewirtschaftungskosten).',
          ),
        );
      }
    }

    final missing = [...capMissing, ...noiComponentMissing];
    if (missing.isNotEmpty) {
      return MethodUnavailable(missingFactors: missing);
    }

    final capRate = factors.value(ValuationFactorIds.capRate)!;
    used.add(factors[ValuationFactorIds.capRate]!);
    final value = noi! / capRate;

    final breakdown = <MethodBreakdownLine>[
      MethodBreakdownLine(label: 'Reinertrag p.a.', amount: noi, unit: '€'),
      MethodBreakdownLine(
        label: 'Ertragswert (direkt kapitalisiert)',
        amount: value,
        unit: '€',
        formula: 'Reinertrag / Kapitalisierungszins',
      ),
    ];

    // Optional quick ratios when a purchase price is present.
    final price = factors.value(ValuationFactorIds.purchasePrice);
    final grossRent = factors.value(ValuationFactorIds.grossRentAnnual);
    if (price != null && price > 0) {
      breakdown.add(
        MethodBreakdownLine(
          label: 'Nettoanfangsrendite',
          amount: noi / price,
          formula: 'Reinertrag / Kaufpreis',
        ),
      );
      if (grossRent != null && grossRent > 0) {
        breakdown.add(
          MethodBreakdownLine(
            label: 'Bruttoanfangsrendite',
            amount: grossRent / price,
            formula: 'Rohertrag / Kaufpreis',
          ),
        );
        breakdown.add(
          MethodBreakdownLine(
            label: 'Faktor (Kaufpreis / Rohertrag)',
            amount: price / grossRent,
          ),
        );
      }
    }

    return MethodValue(
      amount: value,
      confidence: combineConfidence(used),
      breakdown: breakdown,
      assumptions:
          used.map(ValuationAssumption.fromFactor).toList(growable: false),
    );
  }
}
