/// A starting point for the cost type tree, from § 2 BetrKV
/// (`FINANCE-COST-TYPES-01`).
///
/// **This is a suggestion, not a rule, and the difference is deliberate.**
/// `DEC-014` records the BetrKV § 2 catalogue as one of the seven points where
/// the sources contradict each other, which is why P-2a made `betrkv_position`
/// free text rather than a seventeen-value enum: a fixed list in a migration
/// would encode a legal position nobody has signed off, and correcting it
/// would cost another migration.
///
/// So nothing here is enforced anywhere. Adopting an entry creates an ordinary
/// cost type the workspace can rename, re-code, deactivate or delete; a cost
/// type that appears on no list is accepted exactly as readily; and no
/// validation anywhere consults this file. What it does is spare somebody
/// typing seventeen rows from memory, with the source named so they can check
/// each one against it.
///
/// The heating positions carry [underHeatingCostRegulation] because P-2a
/// already enforces the consequence — a HeizkostenV position settles on the
/// performance principle (BGH VIII ZR 156/11), as a CHECK constraint. The flag
/// pre-fills the classification form that opens after an adoption; the person
/// classifying the cost type confirms it, and can clear it.
///
/// **Adopting an entry is two steps, and the second is where the position is
/// recorded.** Creating the cost type writes a `finance_accounts` row and
/// nothing else — no allocation rule, because whether a cost may be passed on
/// is a decision this catalogue does not make. The classification form that
/// follows carries [positionText] into `betrkv_position`, and that is the only
/// thing that retires a suggestion from the panel. Cancelling it leaves the
/// cost type created and the suggestion still on offer, which is the honest
/// state: nothing recorded which position it is.
library;

class BetrkvSuggestion {
  const BetrkvSuggestion({
    required this.position,
    required this.name,
    required this.suggestedCode,
    required this.positionText,
    this.underHeatingCostRegulation = false,
    this.note,
  });

  /// The number in § 2 BetrKV. Shown so the reader can look it up.
  final String position;

  /// A short name for the cost type, the way a booking would read.
  final String name;

  /// A machine-safe code the form pre-fills. Workspaces with their own chart
  /// of accounts will replace it, which is why it is suggested rather than
  /// assigned.
  final String suggestedCode;

  /// Pre-fills `betrkv_position` on the classification form, and is what the
  /// panel matches against to retire a suggestion. The item as the regulation
  /// words it, shortened. Free text on the server, and editable there: a
  /// workspace that rewords it is simply offered the position again, because
  /// nothing then records that this is that position.
  final String positionText;

  /// Pre-fills P-2a's HeizkostenV flag on the classification form, which
  /// forces the performance principle. Confirmed by the person classifying the
  /// cost type, never applied on their behalf.
  ///
  /// Set for the three positions whose subject is a *central* installation —
  /// § 1 Abs. 1 HeizkostenV applies where a building is supplied centrally.
  /// A decentralised supply (a Durchlauferhitzer in the dwelling) is outside
  /// both, which is why the position texts keep the word "zentralen".
  final bool underHeatingCostRegulation;

  /// Said where an item is commonly misread.
  final String? note;
}

/// The seventeen items of § 2 BetrKV, in their own order.
///
/// Positions 4, 5 and 6 have sub-items in the regulation (central plant,
/// central fuel supply, commercial heat supply, maintenance of individual
/// units). They are offered as one cost type each: which sub-item applies is a
/// property of the building, not of the chart of accounts, and splitting them
/// here would put a decision in the catalogue that belongs in the booking.
const List<BetrkvSuggestion> betrkvSuggestions = <BetrkvSuggestion>[
  BetrkvSuggestion(
    position: '1',
    name: 'Grundsteuer',
    suggestedCode: 'betrkv.01',
    positionText: 'Laufende öffentliche Lasten des Grundstücks',
    note:
        'Die Grundsteuer ist der Regelfall, aber nicht der ganze Wortlaut: '
        'die Position umfasst die laufenden öffentlichen Lasten insgesamt.',
  ),
  BetrkvSuggestion(
    position: '2',
    name: 'Wasserversorgung',
    suggestedCode: 'betrkv.02',
    positionText: 'Kosten der Wasserversorgung',
  ),
  BetrkvSuggestion(
    position: '3',
    name: 'Entwässerung',
    suggestedCode: 'betrkv.03',
    positionText: 'Kosten der Entwässerung',
  ),
  BetrkvSuggestion(
    position: '4',
    name: 'Heizung',
    suggestedCode: 'betrkv.04',
    positionText: 'Kosten des Betriebs der zentralen Heizungsanlage',
    underHeatingCostRegulation: true,
    note:
        'Umfasst in der Verordnung auch die zentrale Brennstoffversorgung, '
        'die gewerbliche Wärmelieferung und die Wartung von Etagenheizungen.',
  ),
  BetrkvSuggestion(
    position: '5',
    name: 'Warmwasser',
    suggestedCode: 'betrkv.05',
    positionText:
        'Kosten des Betriebs der zentralen Warmwasserversorgungsanlage',
    underHeatingCostRegulation: true,
    note:
        'Das Wort „zentralen" trägt die Abgrenzung: eine dezentrale '
        'Warmwasserbereitung in der Wohnung fällt weder unter diese Position '
        'noch unter die HeizkostenV.',
  ),
  BetrkvSuggestion(
    position: '6',
    name: 'Heizung und Warmwasser verbunden',
    suggestedCode: 'betrkv.06',
    positionText:
        'Kosten verbundener Heizungs- und Warmwasserversorgungsanlagen',
    underHeatingCostRegulation: true,
    note:
        'Nur anlegen, wenn die Anlagen tatsächlich verbunden sind — sonst '
        'genügen die Positionen 4 und 5.',
  ),
  BetrkvSuggestion(
    position: '7',
    name: 'Aufzug',
    suggestedCode: 'betrkv.07',
    positionText: 'Kosten des Betriebs des Personen- oder Lastenaufzugs',
  ),
  BetrkvSuggestion(
    position: '8',
    name: 'Straßenreinigung und Müllbeseitigung',
    suggestedCode: 'betrkv.08',
    positionText: 'Kosten der Straßenreinigung und Müllbeseitigung',
  ),
  BetrkvSuggestion(
    position: '9',
    name: 'Gebäudereinigung',
    suggestedCode: 'betrkv.09',
    positionText: 'Kosten der Gebäudereinigung und Ungezieferbekämpfung',
  ),
  BetrkvSuggestion(
    position: '10',
    name: 'Gartenpflege',
    suggestedCode: 'betrkv.10',
    positionText: 'Kosten der Gartenpflege',
  ),
  BetrkvSuggestion(
    position: '11',
    name: 'Beleuchtung',
    suggestedCode: 'betrkv.11',
    positionText: 'Kosten der Beleuchtung',
    note:
        'Nur Beleuchtungsstrom: Außenbeleuchtung und die gemeinsam genutzten '
        'Gebäudeteile. Nicht der gesamte Allgemeinstrom — der Betriebsstrom '
        'von Aufzug, Antenne, Waschküche und Heizung steht jeweils in der '
        'eigenen Position (7, 15, 16, 4).',
  ),
  BetrkvSuggestion(
    position: '12',
    name: 'Schornsteinreinigung',
    suggestedCode: 'betrkv.12',
    positionText: 'Kosten der Schornsteinreinigung',
  ),
  BetrkvSuggestion(
    position: '13',
    name: 'Versicherung',
    suggestedCode: 'betrkv.13',
    positionText: 'Kosten der Sach- und Haftpflichtversicherung',
  ),
  BetrkvSuggestion(
    position: '14',
    name: 'Hauswart',
    suggestedCode: 'betrkv.14',
    positionText: 'Kosten für den Hauswart',
  ),
  BetrkvSuggestion(
    position: '15',
    name: 'Antenne und Breitband',
    suggestedCode: 'betrkv.15',
    positionText:
        'Kosten des Betriebs der Gemeinschafts-Antennenanlage oder '
        'Verteilanlage',
    note:
        'Seit dem TKModG (1.12.2021) hat die Position drei Buchstaben: '
        'Gemeinschaftsantenne, mit einem Breitbandnetz verbundene private '
        'Verteilanlage, und der Betrieb einer gebäudeinternen Verteilanlage '
        '(Glasfaserbereitstellungsentgelt, § 72 Abs. 1 TKG). Für die '
        'getrennte Abrechnung ggf. mehrere Kostenarten anlegen.',
  ),
  BetrkvSuggestion(
    position: '16',
    name: 'Wäschepflege',
    suggestedCode: 'betrkv.16',
    positionText:
        'Kosten des Betriebs der Einrichtungen für die Wäschepflege',
  ),
  BetrkvSuggestion(
    position: '17',
    name: 'Sonstige Betriebskosten',
    suggestedCode: 'betrkv.17',
    positionText: 'Sonstige Betriebskosten',
    note:
        'Sammelposition. Sie trägt sich nicht selbst: eine sonstige '
        'Betriebskostenart ist nur umlagefähig, wenn sie im Mietvertrag '
        'einzeln benannt ist. Deshalb eher je Kostenart eine eigene Position '
        'anlegen als alles hier zu sammeln.',
  ),
];

/// Which suggestions the workspace has not taken up yet.
///
/// Matched on the position text rather than the code or the name, because both
/// of those are the workspace's to change and the position is what identifies
/// the item. A workspace that renamed "Hauswart" to "Hausmeisterdienst" and
/// kept the position should not be offered it again.
List<BetrkvSuggestion> outstandingBetrkvSuggestions(
  Iterable<String?> takenPositionTexts,
) {
  final Set<String> taken = takenPositionTexts
      .whereType<String>()
      .map((String text) => text.trim().toLowerCase())
      .toSet();
  return betrkvSuggestions
      .where(
        (BetrkvSuggestion suggestion) =>
            !taken.contains(suggestion.positionText.trim().toLowerCase()),
      )
      .toList(growable: false);
}
