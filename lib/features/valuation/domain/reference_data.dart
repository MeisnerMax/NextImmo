import 'valuation_factor.dart' show ConfidenceBand;

/// Building types for cost/useful-life reference lookups. Extensible — start
/// with the common German residential/commercial set.
enum ReferenceBuildingType {
  einfamilienhaus,
  doppelhaushaelfte,
  reihenhaus,
  mehrfamilienhaus,
  wohnUndGeschaeftshaus,
  buerogebaeude,
}

/// NHK Standardstufen 1–5 (Sachwertverfahren quality grade).
enum BuildingQualityStandard { einfach, basis, mittel, gehoben, starkGehoben }

/// Asset class for yield / market-adjustment-factor ranges. Extensible.
enum AssetClass {
  wohnenEinfamilien,
  wohnenMehrfamilien,
  gemischtGenutzt,
  buero,
  einzelhandel,
}

/// Normalherstellungskosten (NHK 2010 base, € per m² Bruttogrundfläche) plus the
/// Gesamtnutzungsdauer for a building type/standard. Indicative reference — the
/// [source]/[confidence] make clear it must be confirmed before use.
class BuildingCostReference {
  const BuildingCostReference({
    required this.normalHerstellungskostenPerSqm,
    required this.gesamtnutzungsdauerYears,
    this.confidence = ConfidenceBand.low,
    this.source = 'Indikativer NHK-2010-Richtwert – vor Verwendung bestätigen',
  });

  final double normalHerstellungskostenPerSqm;
  final int gesamtnutzungsdauerYears;
  final ConfidenceBand confidence;
  final String source;
}

/// Typical Bewirtschaftungskosten split, each as a share of the Rohertrag.
class OperatingCostBenchmark {
  const OperatingCostBenchmark({
    required this.verwaltungPercentOfRohertrag,
    required this.instandhaltungPercentOfRohertrag,
    required this.mietausfallwagnisPercentOfRohertrag,
    this.confidence = ConfidenceBand.low,
    this.source =
        'Typischer Bewirtschaftungskosten-Ansatz – vor Verwendung bestätigen',
  });

  final double verwaltungPercentOfRohertrag;
  final double instandhaltungPercentOfRohertrag;
  final double mietausfallwagnisPercentOfRohertrag;
  final ConfidenceBand confidence;
  final String source;

  double get totalPercentOfRohertrag =>
      verwaltungPercentOfRohertrag +
      instandhaltungPercentOfRohertrag +
      mietausfallwagnisPercentOfRohertrag;
}

/// A typical value with a plausible range — offered as a menu default that must
/// be confirmed. Used for the region-dependent inputs (Liegenschaftszinssatz,
/// Sachwertfaktor) that have no authoritative offline source.
class TypicalRange {
  const TypicalRange({
    required this.min,
    required this.typical,
    required this.max,
    this.unit,
    this.confidence = ConfidenceBand.low,
    this.source =
        'Typische Spanne – regionsabhängig, vor Verwendung bestätigen',
  });

  final double min;
  final double typical;
  final double max;
  final String? unit;
  final ConfidenceBand confidence;
  final String source;
}

/// Supplies reference values that seed *suggested* factors and menus. The local
/// [SeedReferenceDataProvider] ships indicative tables; an external provider
/// (BORIS-Bodenrichtwerte, Gutachterausschuss) can implement this interface as
/// a later stage without touching the methods.
abstract interface class ReferenceDataProvider {
  BuildingCostReference? buildingCost(
    ReferenceBuildingType type,
    BuildingQualityStandard standard,
  );

  int? gesamtnutzungsdauer(ReferenceBuildingType type);

  OperatingCostBenchmark? operatingCostBenchmark(ReferenceBuildingType type);

  /// Liegenschaftszinssatz range (as a fraction) for an asset class.
  TypicalRange? liegenschaftszinssatz(AssetClass assetClass);

  /// Sachwertfaktor (Marktanpassungsfaktor) range for an asset class.
  TypicalRange? sachwertfaktor(AssetClass assetClass);
}

/// Offline seed reference data. All figures are **indicative, low-confidence
/// placeholders meant to be confirmed/overridden** — they exist to power menus
/// and system suggestions, not to assert authoritative regional values. Refine
/// these tables (or plug in an external provider) as the data source matures.
class SeedReferenceDataProvider implements ReferenceDataProvider {
  const SeedReferenceDataProvider();

  // NHK 2010 base cost (€/m² BGF) by standard grade, per building type.
  static const Map<ReferenceBuildingType, Map<BuildingQualityStandard, double>>
  _nhkPerSqm = {
    ReferenceBuildingType.einfamilienhaus: {
      BuildingQualityStandard.einfach: 960,
      BuildingQualityStandard.basis: 1180,
      BuildingQualityStandard.mittel: 1430,
      BuildingQualityStandard.gehoben: 1810,
      BuildingQualityStandard.starkGehoben: 2270,
    },
    ReferenceBuildingType.doppelhaushaelfte: {
      BuildingQualityStandard.einfach: 900,
      BuildingQualityStandard.basis: 1110,
      BuildingQualityStandard.mittel: 1350,
      BuildingQualityStandard.gehoben: 1700,
      BuildingQualityStandard.starkGehoben: 2130,
    },
    ReferenceBuildingType.reihenhaus: {
      BuildingQualityStandard.einfach: 850,
      BuildingQualityStandard.basis: 1050,
      BuildingQualityStandard.mittel: 1280,
      BuildingQualityStandard.gehoben: 1610,
      BuildingQualityStandard.starkGehoben: 2020,
    },
    ReferenceBuildingType.mehrfamilienhaus: {
      BuildingQualityStandard.einfach: 830,
      BuildingQualityStandard.basis: 1010,
      BuildingQualityStandard.mittel: 1230,
      BuildingQualityStandard.gehoben: 1560,
      BuildingQualityStandard.starkGehoben: 1960,
    },
    ReferenceBuildingType.wohnUndGeschaeftshaus: {
      BuildingQualityStandard.einfach: 900,
      BuildingQualityStandard.basis: 1100,
      BuildingQualityStandard.mittel: 1340,
      BuildingQualityStandard.gehoben: 1690,
      BuildingQualityStandard.starkGehoben: 2120,
    },
    ReferenceBuildingType.buerogebaeude: {
      BuildingQualityStandard.einfach: 1050,
      BuildingQualityStandard.basis: 1300,
      BuildingQualityStandard.mittel: 1600,
      BuildingQualityStandard.gehoben: 2000,
      BuildingQualityStandard.starkGehoben: 2500,
    },
  };

  // Gesamtnutzungsdauer (years) by building type (ImmoWertV Anlage, indicative).
  static const Map<ReferenceBuildingType, int> _gnd = {
    ReferenceBuildingType.einfamilienhaus: 80,
    ReferenceBuildingType.doppelhaushaelfte: 80,
    ReferenceBuildingType.reihenhaus: 80,
    ReferenceBuildingType.mehrfamilienhaus: 80,
    ReferenceBuildingType.wohnUndGeschaeftshaus: 70,
    ReferenceBuildingType.buerogebaeude: 60,
  };

  // Typical Bewirtschaftungskosten split (share of Rohertrag).
  static const Map<ReferenceBuildingType, OperatingCostBenchmark> _opex = {
    ReferenceBuildingType.einfamilienhaus: OperatingCostBenchmark(
      verwaltungPercentOfRohertrag: 0.03,
      instandhaltungPercentOfRohertrag: 0.11,
      mietausfallwagnisPercentOfRohertrag: 0.02,
    ),
    ReferenceBuildingType.doppelhaushaelfte: OperatingCostBenchmark(
      verwaltungPercentOfRohertrag: 0.03,
      instandhaltungPercentOfRohertrag: 0.11,
      mietausfallwagnisPercentOfRohertrag: 0.02,
    ),
    ReferenceBuildingType.reihenhaus: OperatingCostBenchmark(
      verwaltungPercentOfRohertrag: 0.03,
      instandhaltungPercentOfRohertrag: 0.11,
      mietausfallwagnisPercentOfRohertrag: 0.02,
    ),
    ReferenceBuildingType.mehrfamilienhaus: OperatingCostBenchmark(
      verwaltungPercentOfRohertrag: 0.04,
      instandhaltungPercentOfRohertrag: 0.10,
      mietausfallwagnisPercentOfRohertrag: 0.03,
    ),
    ReferenceBuildingType.wohnUndGeschaeftshaus: OperatingCostBenchmark(
      verwaltungPercentOfRohertrag: 0.04,
      instandhaltungPercentOfRohertrag: 0.09,
      mietausfallwagnisPercentOfRohertrag: 0.04,
    ),
    ReferenceBuildingType.buerogebaeude: OperatingCostBenchmark(
      verwaltungPercentOfRohertrag: 0.04,
      instandhaltungPercentOfRohertrag: 0.08,
      mietausfallwagnisPercentOfRohertrag: 0.04,
    ),
  };

  // Liegenschaftszinssatz typical ranges (fraction) by asset class.
  static const Map<AssetClass, TypicalRange> _liegenschaftszins = {
    AssetClass.wohnenEinfamilien: TypicalRange(
      min: 0.020,
      typical: 0.025,
      max: 0.035,
    ),
    AssetClass.wohnenMehrfamilien: TypicalRange(
      min: 0.030,
      typical: 0.035,
      max: 0.045,
    ),
    AssetClass.gemischtGenutzt: TypicalRange(
      min: 0.040,
      typical: 0.050,
      max: 0.060,
    ),
    AssetClass.buero: TypicalRange(min: 0.045, typical: 0.055, max: 0.070),
    AssetClass.einzelhandel: TypicalRange(
      min: 0.050,
      typical: 0.060,
      max: 0.080,
    ),
  };

  // Sachwertfaktor (Marktanpassungsfaktor) typical ranges by asset class.
  static const Map<AssetClass, TypicalRange> _sachwertfaktor = {
    AssetClass.wohnenEinfamilien: TypicalRange(min: 0.8, typical: 1.1, max: 1.5),
    AssetClass.wohnenMehrfamilien: TypicalRange(
      min: 0.8,
      typical: 1.0,
      max: 1.4,
    ),
    AssetClass.gemischtGenutzt: TypicalRange(min: 0.7, typical: 0.95, max: 1.3),
    AssetClass.buero: TypicalRange(min: 0.7, typical: 0.9, max: 1.2),
    AssetClass.einzelhandel: TypicalRange(min: 0.6, typical: 0.85, max: 1.2),
  };

  @override
  BuildingCostReference? buildingCost(
    ReferenceBuildingType type,
    BuildingQualityStandard standard,
  ) {
    final perSqm = _nhkPerSqm[type]?[standard];
    final gnd = _gnd[type];
    if (perSqm == null || gnd == null) return null;
    return BuildingCostReference(
      normalHerstellungskostenPerSqm: perSqm,
      gesamtnutzungsdauerYears: gnd,
    );
  }

  @override
  int? gesamtnutzungsdauer(ReferenceBuildingType type) => _gnd[type];

  @override
  OperatingCostBenchmark? operatingCostBenchmark(ReferenceBuildingType type) =>
      _opex[type];

  @override
  TypicalRange? liegenschaftszinssatz(AssetClass assetClass) =>
      _liegenschaftszins[assetClass];

  @override
  TypicalRange? sachwertfaktor(AssetClass assetClass) =>
      _sachwertfaktor[assetClass];
}
