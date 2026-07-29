import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/reference_data.dart';

void main() {
  const provider = SeedReferenceDataProvider();

  group('SeedReferenceDataProvider', () {
    test('returns building cost + GND for a known type/standard', () {
      final ref = provider.buildingCost(
        ReferenceBuildingType.mehrfamilienhaus,
        BuildingQualityStandard.mittel,
      );
      expect(ref, isNotNull);
      expect(ref!.normalHerstellungskostenPerSqm, 1230);
      expect(ref.gesamtnutzungsdauerYears, 80);
    });

    test('exposes a Gesamtnutzungsdauer per type', () {
      expect(provider.gesamtnutzungsdauer(ReferenceBuildingType.buerogebaeude), 60);
    });

    test('operating-cost benchmark is present for every building type', () {
      for (final type in ReferenceBuildingType.values) {
        expect(
          provider.operatingCostBenchmark(type),
          isNotNull,
          reason: 'missing OpEx benchmark for $type',
        );
      }
    });

    test('MFH Bewirtschaftungskosten sum to the expected share of Rohertrag', () {
      final opex = provider.operatingCostBenchmark(
        ReferenceBuildingType.mehrfamilienhaus,
      )!;
      expect(opex.totalPercentOfRohertrag, closeTo(0.17, 1e-9));
    });

    test('provides Liegenschaftszins and Sachwertfaktor ranges', () {
      final lz = provider.liegenschaftszinssatz(AssetClass.wohnenMehrfamilien);
      expect(lz, isNotNull);
      expect(lz!.typical, 0.035);
      expect(lz.min <= lz.typical && lz.typical <= lz.max, isTrue);

      final swf = provider.sachwertfaktor(AssetClass.wohnenMehrfamilien);
      expect(swf, isNotNull);
      expect(swf!.min <= swf.typical && swf.typical <= swf.max, isTrue);
    });
  });
}
