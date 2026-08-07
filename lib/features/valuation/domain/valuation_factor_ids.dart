/// Stable factor identifiers shared by methods and the (later) factor-assembly
/// layer, so the two never drift on stringly-typed keys.
abstract final class ValuationFactorIds {
  // Income / operating.
  static const grossRentAnnual = 'grossRentAnnual'; // Rohertrag p.a.
  static const operatingExpensesAnnual =
      'operatingExpensesAnnual'; // Bewirtschaftungskosten p.a.
  static const vacancyRate = 'vacancyRate'; // Mietausfall-/Leerstandsquote
  static const stabilizedNoiAnnual = 'stabilizedNoiAnnual'; // Reinertrag p.a.

  // Growth / horizon.
  static const rentGrowthRate = 'rentGrowthRate';
  static const expenseGrowthRate = 'expenseGrowthRate';
  static const holdYears = 'holdYears'; // Betrachtungszeitraum

  // Investment / DCF.
  static const discountRate = 'discountRate'; // Kalkulationszins
  static const capRate = 'capRate'; // Kapitalisierungszins (Direktkap.)
  static const exitCapRate = 'exitCapRate';
  static const terminalGrowthRate = 'terminalGrowthRate';
  static const saleCostRate = 'saleCostRate'; // Verkaufskostenquote

  // Grundstück / Bodenwert (Ertrags- und Sachwertverfahren).
  static const landAreaSqm = 'landAreaSqm'; // Grundstücksfläche in m²
  static const landValuePerSqm = 'landValuePerSqm'; // Bodenrichtwert €/m²
  static const landValue = 'landValue'; // Bodenwert (direkt vorgegeben)
  static const liegenschaftszinssatz = 'liegenschaftszinssatz';

  // Nutzungsdauer / Alter.
  static const buildingAgeYears = 'buildingAgeYears'; // Alter des Gebäudes
  static const totalUsefulLifeYears =
      'totalUsefulLifeYears'; // Gesamtnutzungsdauer
  static const remainingUsefulLifeYears =
      'remainingUsefulLifeYears'; // Restnutzungsdauer

  // Sachwertverfahren.
  static const grossFloorAreaSqm = 'grossFloorAreaSqm'; // Bruttogrundfläche BGF
  static const normalHerstellungskostenPerSqm =
      'normalHerstellungskostenPerSqm'; // NHK €/m² BGF
  static const constructionPriceIndex = 'constructionPriceIndex'; // Baupreisindex
  static const regionalFactor = 'regionalFactor'; // Regionalfaktor
  static const outdoorFacilitiesValue =
      'outdoorFacilitiesValue'; // Außenanlagen
  static const sachwertfaktor = 'sachwertfaktor'; // Marktanpassungsfaktor

  // Vergleichswertverfahren.
  static const subjectLivingAreaSqm =
      'subjectLivingAreaSqm'; // Wohn-/Nutzfläche des Bewertungsobjekts

  // Besondere objektspezifische Grundstücksmerkmale (boM), ± auf das Ergebnis.
  static const otherValueAdjustment = 'otherValueAdjustment';

  // Reference / context.
  static const purchasePrice = 'purchasePrice'; // Kaufpreis (für Kennzahlen)
}
