/// Proposed rules, drawn from the documented research
/// (`docs/product/ENTERPRISE_OPERATIONS_PROGRAM.md` §2, researched 2026-09-06).
///
/// **These are proposals, not law the product asserts.** Nothing here is
/// written by a migration and nothing is adopted in bulk: choosing one
/// pre-fills the form, an administrator reads it, and saving it records the
/// rule as `unverified` until somebody confirms it against the source. That is
/// the shape `DEC-014` authorised — the product proposes, a named person
/// confirms — made literal.
///
/// **Only figures the research states.** Every value below is traceable to the
/// §2 table or to the binding model consequences under it. Where the research
/// gives a range rather than a figure (the 2027 CO2 corridor), or names a
/// change without a number (§ 556 BGB), the proposal carries the fact and not
/// an invented amount. A plausible-looking number nobody wrote down is exactly
/// what this whole layer exists to keep out.
///
/// **Three of these are `decisionSupport`,** because the law wants a judgement
/// and the programme says so: § 5d CO2KostAufG is a five-part cumulative test
/// with open legal concepts, and the § 12 HeizkostenV cumulability and the
/// opted-commercial VAT treatment are both on the list of points the research
/// itself calls contradictory. A rule in that state can be shown and proposed
/// and can never be applied on its own.
library;

/// One proposal. The fields map one-to-one onto the create form.
class ComplianceRuleProposal {
  const ComplianceRuleProposal({
    required this.ruleKey,
    required this.label,
    required this.validFrom,
    required this.value,
    required this.sourceReference,
    this.validTo,
    this.unit,
    this.note,
    this.decisionSupport = false,
  });

  final String ruleKey;

  /// What to call it in a list a human reads. The `ruleKey` is what code uses.
  final String label;

  final DateTime validFrom;
  final DateTime? validTo;

  /// Pre-filled into the form as JSON. A number for a price, an object where
  /// the rule has parts.
  final Object value;

  final String? unit;
  final String sourceReference;
  final String? note;
  final bool decisionSupport;
}

/// The catalogue, oldest period first within a key.
final List<ComplianceRuleProposal> complianceRuleProposals =
    List<ComplianceRuleProposal>.unmodifiable(<ComplianceRuleProposal>[
      ComplianceRuleProposal(
        ruleKey: 'co2_price_eur_per_tonne',
        label: 'CO₂-Preis 2025',
        validFrom: DateTime(2025, 1, 1),
        validTo: DateTime(2025, 12, 31),
        value: 55,
        unit: 'EUR/t',
        sourceReference: 'BEHG; Rechtsstand-Recherche 2026-09-06, §2',
      ),
      ComplianceRuleProposal(
        ruleKey: 'co2_price_eur_per_tonne',
        label: 'CO₂-Preis 2026',
        validFrom: DateTime(2026, 1, 1),
        validTo: DateTime(2026, 12, 31),
        value: 60,
        unit: 'EUR/t',
        sourceReference: 'BEHG; Rechtsstand-Recherche 2026-09-06, §2',
      ),
      ComplianceRuleProposal(
        ruleKey: 'co2_price_corridor_eur_per_tonne',
        label: 'CO₂-Preiskorridor 2027',
        validFrom: DateTime(2027, 1, 1),
        validTo: DateTime(2027, 12, 31),
        // A corridor, not a price. The research gives 55–65 € and says ETS2
        // moved to 2028; picking a single number inside that range would be an
        // invention dressed as a citation.
        value: <String, Object>{'min': 55, 'max': 65},
        unit: 'EUR/t',
        sourceReference:
            'Korridor 55–65 EUR; ETS2 auf 2028 verschoben. '
            'Rechtsstand-Recherche 2026-09-06, §2',
        note:
            'Ein Korridor, kein Preis. Der konkrete Wert steht erst mit der '
            'Festlegung fest.',
      ),
      ComplianceRuleProposal(
        ruleKey: 'co2kostaufg_nonresidential_split',
        label: 'CO₂-Kostenteilung Nichtwohngebäude',
        validFrom: DateTime(2023, 1, 1),
        value: <String, Object>{'landlord_percent': 50, 'tenant_percent': 50},
        sourceReference: 'CO2KostAufG § 8; Rechtsstand-Recherche 2026-09-06, §2',
        note:
            '§ 8 Abs. 4 CO2KostAufG kündigt ein Stufenmodell „im Jahr 2025" an '
            '— es ist nicht gekommen. Nichtwohngebäude bleiben bei starr '
            '50/50; das ist der klassische Fallstrick.',
      ),
      ComplianceRuleProposal(
        ruleKey: 'umlageausfallwagnis_percent_max',
        label: 'Umlageausfallwagnis (Höchstsatz)',
        validFrom: DateTime(1970, 1, 1),
        value: <String, Object>{
          'max_percent': 2,
          'only_price_bound_housing': true,
        },
        unit: '%',
        sourceReference: '§ 25a NMV 1970 (nicht II. BV)',
        note:
            'Nur bei preisgebundenem Wohnraum. Ausserhalb davon darf das Feld '
            'gar nicht aktivierbar sein.',
      ),
      ComplianceRuleProposal(
        ruleKey: 'heizkostenv_70_percent_conditions',
        label: 'HeizkostenV: 70-%-Zwang',
        validFrom: DateTime(2009, 1, 1),
        value: <String, Object>{
          'no_wschv_1994_standard': true,
          'oil_or_gas_heating': true,
          'mostly_insulated_exposed_pipes': true,
          'conjunction': 'AND',
        },
        sourceReference: 'HeizkostenV § 7 Abs. 1',
        note:
            'Eine UND-Verknüpfung dreier Gebäudemerkmale, also drei '
            'Stammdatenattribute — kein Schalter.',
      ),
      ComplianceRuleProposal(
        ruleKey: 'tv_nebenkostenprivileg',
        label: 'TV-Nebenkostenprivileg (ausgelaufen)',
        validFrom: DateTime(2021, 12, 1),
        validTo: DateTime(2024, 6, 30),
        value: <String, Object>{'applies': true},
        sourceReference: 'TKG; ausgelaufen zum 30.06.2024',
        note:
            'Abrechnungen für 2024 müssen zeitanteilig trennen. Die Regel '
            'endet mitten im Abrechnungsjahr — genau der Fall, für den die '
            'Gültigkeitszeiträume da sind.',
      ),
      ComplianceRuleProposal(
        ruleKey: 'fernablesbarkeit_deadline',
        label: 'Fernablesbarkeit: Frist Altbestand',
        validFrom: DateTime(2021, 12, 1),
        value: <String, Object>{'deadline': '2026-12-31', 'scope': 'Altbestand'},
        sourceReference: 'HeizkostenV § 5; Rechtsstand-Recherche 2026-09-06, §2',
        note: 'Betrifft die Zählerstammdaten unmittelbar.',
      ),
      ComplianceRuleProposal(
        ruleKey: 'bgb_556_belegeinsicht_elektronisch',
        label: '§ 556 BGB: elektronische Belegeinsicht',
        validFrom: DateTime(2025, 1, 1),
        value: <String, Object>{
          'electronic_inspection_allowed': true,
          'invalidity_clause_moved_to': 'Abs. 5',
        },
        sourceReference: '§ 556 BGB i.d.F. BEG IV, wirksam 01.01.2025',
        note:
            'Der alte Abs. 4 ist Abs. 5 geworden. Wer auf „§ 556 Abs. 4 = '
            'Unwirksamkeitsklausel" verweist, verweist seit 2025 falsch.',
      ),
      ComplianceRuleProposal(
        ruleKey: 'abrechnung_mindestangaben',
        label: 'Formelle Mindestangaben der Abrechnung',
        validFrom: DateTime(2001, 9, 1),
        value: <String, Object>{
          'required': <String>[
            'Gesamtkosten',
            'Verteilerschlüssel mit Erläuterung',
            'Anteilsberechnung',
            'Vorauszahlungsabzug',
          ],
        },
        sourceReference: 'Ständige BGH-Rechtsprechung zu § 556 Abs. 3 BGB',
        note:
            'Formelle Unwirksamkeit macht die Nachforderung nicht fällig und '
            'setzt die Einwendungsfrist nicht in Gang — nach Fristablauf ist '
            'die gesamte Nachforderung verloren. Der teuerste Fehlerfall.',
      ),
      ComplianceRuleProposal(
        ruleKey: 'co2kostaufg_5d_haertefall',
        label: '§ 5d CO2KostAufG: Härtefall',
        validFrom: DateTime(2026, 7, 29),
        value: <String, Object>{
          'test': 'fünfgliedrig kumulativ',
          'indeterminate_legal_concepts': true,
        },
        sourceReference:
            'CO2KostAufG § 5d i.d.F. GModG (BGBl. 2026 I Nr. 226); '
            'ohne Kommentarliteratur',
        note:
            'Als Assistenz mit ausdrücklicher Bestätigung zu bauen, nicht als '
            'automatische Entscheidung.',
        decisionSupport: true,
      ),
      ComplianceRuleProposal(
        ruleKey: 'heizkostenv_12_kuerzung_kumulierbar',
        label: '§ 12 HeizkostenV: Kumulierbarkeit der Kürzungsrechte',
        validFrom: DateTime(2009, 1, 1),
        value: <String, Object>{'cumulative': 'ungeklärt'},
        sourceReference: 'HeizkostenV § 12; Quellenlage widersprüchlich',
        note:
            'Die Recherche führt diesen Punkt ausdrücklich als klärungs- '
            'bedürftig. Bis dahin: vorschlagen, nicht anwenden.',
        decisionSupport: true,
      ),
      ComplianceRuleProposal(
        ruleKey: 'ust_optierte_gewerbevermietung',
        label: 'USt bei optierter Gewerbevermietung',
        validFrom: DateTime(2001, 1, 1),
        value: <String, Object>{
          'commercial_opted': 'netto mit getrennter USt',
          'residential': 'brutto',
          'same_settlement_run': true,
        },
        sourceReference: '§ 9 UStG; Quellenlage für die Umlage widersprüchlich',
        note:
            'Der grösste Architekturtreiber bei gemischt genutzten Objekten: '
            'beide Modi im selben Abrechnungslauf.',
        decisionSupport: true,
      ),
    ]);
