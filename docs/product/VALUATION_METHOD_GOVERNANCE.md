# Valuation Method Governance

## Metadaten

- Decision ID: `METHOD-GOV-01`
- Status: **APPROVED**
- Entscheidungstyp: verbindliche Fach- und Produktarchitektur
- Geltungsbereich: NexImmo Valuation V2
- Stand: 2026-09-01
- Repository-Basis: `origin/main` = `bf0693cbde0a1efe10a78e9fe3ca1f0a08af3a1c`
- Implementierung: ausdrücklich nicht Bestandteil dieser Entscheidung
- Verbindliche Folgespecs:
  - [Valuation V2 Workflow](screens/valuation_v2_workflow.md)
  - [Valuation Queue V2](screens/valuation_queue_v2.md)
  - [Create Valuation V2](screens/valuation_create_v2.md)
  - [Valuation Case Workspace V2](screens/valuation_case_workspace_v2.md)

## 1. Entscheidung

NexImmo unterscheidet zwei fachliche Methodenkategorien. Eine Methode gehört genau einer Kategorie an.

| Kategorie | Wertbasis und Zweck | Zulässige Methoden in V2 | Zulässige Hauptergebnisse |
|---|---|---|---|
| **A. Market Valuation** | objektive, stichtagsbezogene Ableitung aus Sicht des gewöhnlichen Grundstücksmarkts | Vergleichswertverfahren, Ertragswertverfahren, Sachwertverfahren | Verfahrenswert; unter dem Professional Gate zunächst nur indikative Marktwertableitung |
| **B. Investment Analysis** | eigentümer-, ankäufer- oder strategiespezifische Analyse von Cashflow, Rendite und Preis | Aggregate DCF, Direct Capitalization; später Lease-by-Lease/levered DCF | DCF Value, Capitalized Value, Investment Value nur bei expliziter Investor-Perspektive, NOI, NPV, IRR, Equity Multiple |

Daneben existiert eine **Transaktions- und Entscheidungsebene**, aber keine dritte Bewertungsmethode: Purchase Price, Offer, Target Price und Investment-Committee-Entscheidungen sind Eingaben oder Handlungsentscheidungen. Sie dürfen mit Ergebnissen verglichen, aber nie als Bewertungsverfahren ausgegeben werden.

Diese Trennung ist verbindlich für Domain Contracts, Engine-Ergebnisse, UI, Audit, Freigabe und Export. Die Bezeichnung einer Engine im Code entscheidet nicht über die fachlich zulässige Produktbezeichnung.

### 1.1 Harte Invarianten

1. Market-Valuation- und Investment-Analysis-Ergebnisse werden nie in einer gemeinsamen Reconciliation gewichtet.
2. DCF ist eine Berechnungsmethode, keine Wertbasis. Das Ergebnis ist nicht automatisch Marktwert und nicht automatisch Investment Value.
3. Direct Capitalization ist in NexImmo V2 eine Investment-/Yield-Analyse und kein deutsches Ertragswertverfahren.
4. Purchase Price und Offer sind keine Werturteile.
5. Ein generisches Feld oder Label `Value`, `Market Value Opinion` oder `Verkehrswert` ist ohne ausgewiesene Wertbasis unzulässig.
6. Technische Workflow-Freigabe ist nicht gleich professionelle Marktwertfreigabe.
7. ARGUS dient als Referenz für professionelle Cashflow- und Investmentfunktionalität, nicht als Begriffsgrundlage für einen deutschen Verkehrswert.

## 2. Fachliche Grundlage

### 2.1 Deutsche Market Valuation

§ 194 BauGB definiert Verkehrswert und Marktwert synonym und bindet den Wert an Wertermittlungsstichtag, gewöhnlichen Geschäftsverkehr, rechtliche und tatsächliche Objektmerkmale sowie den Ausschluss ungewöhnlicher oder persönlicher Verhältnisse.

§ 6 ImmoWertV nennt Vergleichswert-, Ertragswert- und Sachwertverfahren. Die Verfahrenswahl muss zum Objekt, den Marktgepflogenheiten und der Eignung der Daten passen und begründet werden. Der Verkehrswert ist aus den angewandten Verfahrenswerten unter Würdigung ihrer Aussagefähigkeit abzuleiten. §§ 7 bis 10 verlangen insbesondere Marktanpassung, Berücksichtigung besonderer objektspezifischer Grundstücksmerkmale, geeignete Daten und Modellkonformität.

Daraus folgt für NexImmo:

- Die drei deutschen Verfahren sind keine frei austauschbaren Formeln.
- Ein vorhandener Rechenweg allein genügt nicht für die Bezeichnung „Marktwert/Verkehrswert“.
- Default-Gewichte können fachliche Eignung und begründete Würdigung nicht ersetzen.
- Investor-spezifische Renditeannahmen dürfen nicht unbemerkt in eine objektive Marktwertbasis eingehen.

### 2.2 Investment Value und Market Value

IVS unterscheidet Market Value als marktbezogene Wertbasis von Investment Value/Worth als Wert für einen bestimmten Eigentümer oder potenziellen Eigentümer mit individuellen Anlage- oder Betriebszielen. IVS unterscheidet außerdem `Weighting` von bloßem Averaging; das Mitteln von Bewertungen ist keine zulässige Reconciliation.

NexImmo übernimmt deshalb nicht die verbreitete Kurzform „DCF = Marktwert“. Ein DCF kann nur dann eine Marktwertmethode unterstützen, wenn sein Auftrag, seine Basis, seine Inputs und seine professionelle Würdigung marktteilnehmerbezogen sind. Der heutige NexImmo-Contract bildet diese Unterscheidung nicht ab. Das heutige DCF bleibt daher Investment Analysis.

### 2.3 ARGUS als Funktionsreferenz

ARGUS Enterprise/Intelligence trennt detaillierte Property-Cashflows und Valuation-/Yield-Analysen funktional: Lease-by-Lease, Market Leasing Assumptions, DCF, traditionelle Kapitalisierung/Yields, Debt, Szenarien, Sensitivität und Reporting. NexImmo übernimmt diese funktionale Transparenz als Zielbild, behauptet aber keinen ARGUS-Funktionsumfang und portiert keine proprietäre Methodik.

### 2.4 Primärquellen

Abruf und fachliche Prüfung am 2026-08-28:

- [§ 194 BauGB – Verkehrswert](https://www.gesetze-im-internet.de/bbaug/__194.html)
- [§ 6 ImmoWertV – Wertermittlungsverfahren und Ermittlung des Verkehrswerts](https://www.gesetze-im-internet.de/immowertv_2022/__6.html)
- [§ 8 ImmoWertV – Grundstücksmerkmale](https://www.gesetze-im-internet.de/immowertv_2022/__8.html)
- [§ 10 ImmoWertV – Modellkonformität](https://www.gesetze-im-internet.de/immowertv_2022/__10.html)
- [§ 24 ImmoWertV – Vergleichswertverfahren](https://www.gesetze-im-internet.de/immowertv_2022/__24.html)
- [§ 27 ImmoWertV – Ertragswertverfahren](https://www.gesetze-im-internet.de/immowertv_2022/__27.html)
- [§ 35 ImmoWertV – Sachwertverfahren](https://www.gesetze-im-internet.de/immowertv_2022/__35.html)
- [BMWSB – ImmoWertA](https://www.bmwsb.bund.de/SharedDocs/downloads/DE/veroeffentlichungen/wohnen/immowerta.html)
- [IVSC Standards Glossary](https://ivsc.org/standards-glossary/)
- [RICS Valuation – Global Standards](https://www.rics.org/profession-standards/rics-standards-and-guidance/sector-standards/valuation-standards/red-book)
- [ARGUS Enterprise – offizielle Produktbeschreibung](https://www.altusgroup.com/solutions/argus-enterprise/)

Die Quellen bestimmen Begriffe und Governance. Sie sind keine Aussage, dass der heutige NexImmo-Rechenweg norm- oder standardkonform implementiert ist.

## 3. Verbindliches Methodenregister

Statusbedeutung:

- **APPROVED:** bestehende Engine kann im angegebenen engen Zweck rehosted werden.
- **BLOCKED:** darf fachlich nicht als produktive Methode ausgegeben werden, bis das genannte Paket abgeschlossen ist.
- **FUTURE:** bewusst nicht Bestandteil der ersten Valuation-Version.

### 3.1 Market Valuation

| Methode | Zweck | Benötigte Inputs | Output | Bestehende Engine/Contract | Fachliche Grenzen | Status |
|---|---|---|---|---|---|---|
| Vergleichswertverfahren | marktnahe Ableitung aus geeigneten Transaktionen/Faktoren | Stichtag, vergleichbarer Grundstücks-/Rechtszustand, ausreichende Vergleichspreise oder geeigneter Faktor, Bezugsgröße, zeitliche/objektspezifische Anpassungen, Quellen | `Vergleichswert`/Verfahrenswert | `ComparisonApproachMethod`; Method Result im Valuation Contract | Cloud-Comparables fehlen; Legacy-Adapter übernimmt `sqft` als m² und verwendet ein generisches Gewicht als Preisfaktor; keine belastbare Markt-/Modellkonformität | **BLOCKED** `VALUATION-COMPS-01` |
| Ertragswertverfahren DE | objektive Marktwertableitung für ertragsorientierte Objekte | marktüblich erzielbarer Rohertrag, Bewirtschaftungskosten, Bodenwert, Restnutzungsdauer, objektspezifischer Liegenschaftszins, boG, Verfahrensvariante, Stichtag/Quelle | `Ertragswert`/Verfahrenswert | `IncomeApproachDeMethod`; Faktoren und Result Contract vorhanden | vereinfachter Modellumfang; keine explizite Verfahrensvariante; unklare NOI-/Rohertragsbasis; Platzhalter-Referenzdaten; Stichtag, Marktmodell und vollständige boG-Würdigung fehlen | **BLOCKED** für Marktwert; **APPROVED** nur als „technische Ertragswert-Modellrechnung“ ohne Publish/Freigabe |
| Sachwertverfahren DE | objektive Marktwertableitung für geeignete substanzorientierte Objekte | Bodenwert, NHK/Herstellungskostenmodell, BGF, Preisindex, Regionalfaktor, Rest-/Gesamtnutzungsdauer, Außenanlagen, objektspezifischer Sachwertfaktor, boG, Stichtag/Quelle | `Sachwert`/Verfahrenswert | `CostApproachDeMethod`; Faktoren und Result Contract vorhanden | harte Low-Confidence-Platzhalter; vereinfachte lineare Altersminderung; keine gesicherte Modellkonformität oder vollständige objektspezifische Würdigung | **BLOCKED** für Marktwert; **APPROVED** nur als „technische Sachwert-Modellrechnung“ ohne Publish/Freigabe |

Die technischen Modellrechnungen dürfen nicht als `indikative Marktwertbewertung` bezeichnet werden, solange das Market-Valuation-Gate aus Abschnitt 7 nicht erfüllt ist. Ihr sicherer Zweck ist ausschließlich interne Eingabe-/Engine-Prüfung.

### 3.2 Investment Analysis

| Methode | Zweck | Benötigte Inputs | Output | Bestehende Engine/Contract | Fachliche Grenzen | Status |
|---|---|---|---|---|---|---|
| Aggregate unlevered DCF | Barwert einer aggregierten Objekt-Cashflow-Projektion über eine Halteperiode | Jahresmiete, Wachstum, Leerstand, OpEx/Wachstum, Haltedauer, Diskontsatz, Terminal Exit Cap oder Gordon Growth, Verkaufskosten; optional Purchase Price für KPIs | `DCF Value`, jährliche Cashflows, PV NOI, PV Terminal; optional NPV, unlevered IRR, Equity Multiple | `DcfMethod`, `CashFlowProjectionEngine`, `InvestmentMetricsEngine`, Report Contract | jährliche Aggregation; keine Leases, CapEx, Debt, Steuern oder Mischwährungen; keine explizite Investor-Perspektive; semantische Wertebereichsprüfung unvollständig | **APPROVED** als interne indikative Investmentanalyse; nie automatisch Marktwert/Verkehrswert oder Investment Value |
| Direct Capitalization | stabilisierten NOI mit einer Cap Rate kapitalisieren | definierter stabilisierter NOI oder Miete/Leerstand/OpEx, Cap Rate; optional Preis/Fläche/Miete für Ratios | `Capitalized Value`, Cap Rate, Preis-/Mietmultiplikatoren | `DirectCapitalizationMethod`, Method Result Contract | kein deutsches Ertragswertverfahren; nur Einperioden-/Stabilized-View; `capRate = 0` wird heute nicht sicher abgefangen; NOI-Semantik muss vereinheitlicht werden | **BLOCKED** bis `VALUATION-VALIDATION-01`; danach **APPROVED** als Yield-Analyse |
| Lease-by-Lease DCF | vertragsscharfe Cashflows mit Lease Events und Wiedervermietung | Rent Roll, Lease-Dates/-Terms, Indexation, Free Rent, Breaks/Options, MLA, void, incentives, TI/LC, recoveries, CapEx | vertragsscharfer unlevered Cashflow und DCF Value | Cloud-Lease-/Rent-Roll-Quelle vorhanden; keine Valuation Engine/Contract | vorhandene Rent-Roll-Summen und Legacy-Indexation sind keine Lease-Cashflow-Engine | **FUTURE**, vorher **BLOCKED** `VALUATION-LEASE-CF-01` |
| CapEx-integrated DCF | Investitionen periodengerecht in Objekt-Cashflows berücksichtigen | Projekttermine, Auswahl Budget/Forecast/Actual, wiederkehrender CapEx, Währung, Szenario | unlevered Cashflow nach CapEx, DCF Value | Cloud-CapEx-Repository als Quelle; kein Mapping zur DCF Engine | keine fachliche Auswahl-/Periodisierungsregel; aktueller NOI/DCF enthält CapEx nicht | **FUTURE**, vorher **BLOCKED** `VALUATION-CAPEX-CF-01` |
| Levered/Equity DCF | Eigenkapital-Cashflow und Finanzierungsrendite | Debt Draws, Zins, Tilgung, Gebühren, Covenants, Refi, Restschuld, Steuernbasis, Objekt-Cashflow | levered IRR, Equity NPV/Multiple, Debt Cashflow | nur vereinfachte Legacy-Single-Loan-Proforma | SQLite-gebunden; kein Cloud-Contract; keine professionelle Debt-/Refi-Engine | **FUTURE**, vorher **BLOCKED** `VALUATION-DEBT-01` |

### 3.3 Explizit verworfene Legacy-Methoden

Folgende Legacy-Ausgaben sind keine Valuation Engines und dürfen nicht übernommen werden:

| Legacy-Bezeichnung | Tatsächliche Rechnung | Entscheidung |
|---|---|---|
| `Sachwertverfahren` in Legacy Export | Purchase Price + Rehab + Closing Costs | **REJECT**; Anschaffungskosten sind kein Sachwert |
| `DCF` in Legacy Export | Ziel-/Exit-Verkaufspreis | **REJECT**; ein Preis ist kein abgezinster Cashflow |
| `Ertragswertverfahren` in Legacy Export | NOI / Cap Rate | **REJECT** als deutsches Ertragswertverfahren; höchstens Direct Capitalization nach eigener Governance |
| ±10-%-Low/Mid/High | pauschale Spanne um Ersatzwert | **REJECT** als fachliche Unsicherheit oder Sensitivität |
| Legacy `NOI` mit CapEx-Prozentsatz in OpEx | aggregierter Proforma-Zwischenwert | **REJECT** als Cloud-NOI; Semantik ist mit dem Cloud-DCF nicht kompatibel |

## 4. Ergebnisbegriffe

| Begriff | Verbindliche Bedeutung | Darf verwendet werden, wenn | Darf nicht verwendet werden für |
|---|---|---|---|
| **Marktwert / Verkehrswert** | synonym gemäß § 194 BauGB; objektiver stichtagsbezogener Wert im gewöhnlichen Geschäftsverkehr | Professional Gate vollständig erfüllt, Wertbasis und Stichtag ausgewiesen, geeignete Market-Valuation-Verfahren fachlich gewürdigt, professionelle Person hat den Bericht freigegeben | DCF-/Yield-Ergebnis, automatisch gewichtete Opinion, Purchase Price, Offer, technische Modellrechnung |
| **Indikative Bewertung** | nicht zertifizierte, zweckgebundene Wertindikation mit offengelegten Daten, Annahmen, Methoden und Grenzen | mindestens ein fachlich freigegebenes Verfahren, Wertbasis, Stichtag, Quelle, Vollständigkeits-/Plausibilitätschecks und Hinweis „kein Verkehrswertgutachten“ vorhanden | unvalidierte Live-Vorschau oder gemischte Reconciliation |
| **Investment Value** | Wert für einen benannten Eigentümer/potenziellen Eigentümer mit individuellen Anlage- oder Betriebszielen | Investor-/Owner-Perspektive, Intended Use, individuelle Annahmen und Cashflow-Basis explizit im Contract/Report stehen | marktteilnehmerbezogener Wert ohne spezifische Perspektive; heutiger generischer DCF-Output |
| **DCF Value** | Barwert der im Modell enthaltenen Cashflows einschließlich Terminalkomponente | Periodizität, unlevered/levered, pre-/post-tax, Währung, Stichtag, Terminalmethode und Ausschlüsse stehen beim Ergebnis | Marktwert, Investment Value oder Price ohne zusätzlich erfüllte jeweilige Basis |
| **Capitalized Value** | stabilisierter NOI geteilt durch explizite Cap Rate | NOI-Definition, Periode, Cap Rate und Datenbasis stehen beim Ergebnis | deutsches Ertragswertverfahren, Marktwert/Verkehrswert, Purchase Price |
| **Purchase Price** | vereinbarter oder als Annahme eingegebener Kaufpreis | Quelle/Stand und Status als Input sind sichtbar | Value Opinion oder Offer ohne tatsächliches Angebot |
| **Offer** | konkreter Angebotsbetrag eines identifizierten Bieters oder von NexImmo vorgeschlagener Angebotsbetrag | Angebotsstatus, Partei/Entscheidungskontext und Datum sind vorhanden | Marktwert, DCF Value oder automatisch berechneter Kaufpreis |
| **NOI** | Nettobetriebsergebnis nach Leerstand/Forderungsausfall und eigentümergetragenem laufendem OpEx, vor CapEx, Finanzierung, Ertragsteuern und Abschreibung | Zeitraum, actual/forecast/stabilized, Währung und enthaltene/exkludierte Kosten sind sichtbar | Cashflow after debt, EBITDA, Rohertrag oder Legacy-NOI inklusive CapEx-Reserve |
| **IRR** | periodischer interner Zinsfuß der genau ausgewiesenen Cashflow-Reihe | unlevered/levered, pre-/post-tax, Periodizität, Haltedauer und Cashflow-Scope stehen beim Ergebnis | Zinssatz, Cap Rate, Objektrendite ohne Cashflow-Reihe oder Wertbetrag |

`NPV`, `Equity Multiple`, Gross Yield, Net Yield, Cap Rate und Preisfaktoren sind Kennzahlen, keine Wertbasen. Ein UI darf sie nicht als finalen „Value“ hervorheben.

### 4.1 Heutige sichere Labels

Bis die neuen Contracts existieren, verwendet der Rehost ausschließlich:

- `Technische Ertragswert-Modellrechnung`
- `Technische Sachwert-Modellrechnung`
- `Aggregate DCF Value (unlevered, indikativ)`
- `Capitalized Value (indikativ)` erst nach Validation Gap
- `NOI (Forecast, vor CapEx und Finanzierung)`
- `IRR (unlevered, vor Steuern, jährlich)`
- `Purchase Price (Input)`

Nicht zulässig im Rehost sind `Verkehrswert`, `Marktwert`, `Market Value Opinion`, `Approved Market Value`, `professionelle Bewertung` und ein unqualifiziertes `Value`.

## 5. Reconciliation

### 5.1 Verbindliche Regel

Die heutige `ReconciliationEngine` ist fachlich **BLOCKED**. Sie gewichtet alle verfügbaren aktivierten Methoden, renormalisiert fehlende Ergebnisse und erzeugt ein einziges `MarketValueOpinion`. Die Templates mischen Market Valuation, DCF und Direct Capitalization. Dieses Verhalten darf nicht rehosted, publiziert, freigegeben oder exportiert werden.

### 5.2 Market Valuation

Mehrere deutsche Verfahren dürfen nur dann gemeinsam gewürdigt werden, wenn:

1. alle dieselbe Wertbasis, denselben Stichtag, dieselbe Währung, denselben Bewertungsgegenstand und denselben Rechtszustand verwenden;
2. jedes Verfahren für Objekt, Marktgepflogenheit und Datenlage geeignet ist;
3. Daten und Modell je Verfahren validiert und Quellen nachvollziehbar sind;
4. Abweichungen untersucht und dokumentiert werden;
5. die professionelle Person Aussagefähigkeit und Reliance je Verfahren begründet.

Gewichtungen sind nur als dokumentierte Reliance innerhalb dieser Market-Valuation-Familie erlaubt. Sie dürfen nicht automatisch vorgeschlagen, nicht als arithmetischer Durchschnitt verwendet und bei fehlenden Verfahren nicht still renormalisiert werden. Prozentwerte müssen 100 % ergeben; 100 % auf ein Primärverfahren ist zulässig. Das fachliche Urteil und die Begründung sind maßgeblich.

Ein finales Ergebnis darf vor dem Professional Gate nur `indikative Marktwertableitung` heißen. Nach vollständig erfülltem Gate darf es `Marktwert (Verkehrswert)` heißen. NexImmo stellt dadurch weder öffentliche Bestellung noch Zertifizierung der freigebenden Person dar.

### 5.3 Investment Analysis

DCF Value und Capitalized Value dürfen nebeneinander als Cross-Check gezeigt werden. Sie dürfen nicht zu einem neuen „Investment Value“ gemittelt werden. Investment Value ist eine Schlussfolgerung auf definierter Investor-Basis; sie erfordert eine begründete Auswahl/Weighting im künftigen Method Contract. IRR, NPV, NOI und Kaufpreis sind nie Reconciliation-Komponenten eines Wertbetrags.

### 5.4 Verbotene Mischungen

- Vergleichswert/Ertragswert/Sachwert + DCF/Direct Capitalization in einer Gewichtung.
- Unlevered Asset Value + levered Equity Value.
- Pre-tax + post-tax Ergebnisse.
- Werte unterschiedlicher Stichtage, Währungen oder Property Interests.
- Purchase Price/Offer + Verfahrenswerte.
- Ergebniskennzahlen wie IRR/NOI + Geldwerte.
- technische Modellrechnung + professionell freigegebener Verfahrenswert ohne klare Trennung.

## 6. Analyse-, Indikations- und Professional-Approval-Stufen

| Stufe | Zulässiger Inhalt | Zulässige Freigabe | Verbotene Aussage |
|---|---|---|---|
| **Analysis** | Live-Rechnung, DCF-/Yield-Analyse, technische deutsche Modellrechnung, Szenarioentwurf | interne Workflow-Freigabe als Analyse, sofern der Contract dies explizit bezeichnet | Marktwert, Verkehrswert, professionelle Bewertung |
| **Indicative Valuation** | freigegebene Methode(n), Wertbasis, Stichtag, Quellen, Validierung, Scope, Annahmen und Grenzen | fachliche Review/Freigabe als indikative Bewertung | Verkehrswertgutachten, Zertifizierung, formelle Marktwertfreigabe |
| **Professional Market Valuation** | vollständige Market-Valuation-Akte mit geeignetem Verfahren, Begründung, Modell-/Datenkonformität, boG, Audit, reproduzierbarer Version und Bericht | namentlich verantwortliche fachlich qualifizierte Person; Organisation definiert Kompetenz-/Vier-Augen-Regel | Behauptung einer gesetzlichen, öffentlichen oder RICS-/IVS-Zertifizierung durch NexImmo |

### 6.1 Professional Gate

Ein Ergebnis darf **nicht** als professionelle Marktwertbewertung freigegeben werden, wenn mindestens einer der folgenden Punkte zutrifft:

- Value Basis, Intended Use, Intended Users, Stichtag, Währung oder Property Interest fehlen.
- persönliche Investor-Annahmen beeinflussen die Market-Valuation-Ergebnisse.
- Methode/Eignung und Reconciliation-Reliance sind nicht begründet.
- ein required Input fehlt, stammt aus Low-Confidence-Placeholdern oder besitzt keine belastbare Quelle.
- Markt-/Modellkonformität, boG oder Rechte/Belastungen sind nicht dokumentiert.
- Comparables sind Legacy-/unklarer Einheit, nicht ausreichend oder nicht nachvollziehbar angepasst.
- Ergebnis ist stale, Engine-/Contract-Version nicht reproduzierbar oder Version/Audit nicht lesbar.
- DCF, Direct Capitalization, Purchase Price oder Offer wurde mit deutschen Verfahren gemischt.
- Review und Approval erfolgen durch dieselbe Person, obwohl die Organisationsregel Vier-Augen-Prinzip fordert.
- der Export nennt Qualifikation/Zertifizierung, die NexImmo nicht verifiziert.

Der heutige Valuation Contract erfüllt dieses Gate nicht. `valuation.approve` ist derzeit nur eine technische Workflow-Berechtigung.

Die heutige angezeigte `confidence` ist aus Factor-Provenance abgeleitet. Sie misst weder Modellgüte noch Marktdatenqualität oder Ergebnisunsicherheit und darf deshalb nicht als „Bewertungssicherheit“ oder professionelle Konfidenz bezeichnet werden.

## 7. Current Engine Gap Matrix

| Methode/Fähigkeit | Engine Support heute | Contract Support heute | Fehlender Bestandteil | Paket | Klassifikation |
|---|---|---|---|---|---|
| Vergleichswert | Rechenweg vorhanden | Methode/Result vorhanden; Comparable-Port fällt auf Legacy zurück | Cloud-Comparables, Einheit/Qualität, Anpassungsmodell, Stichtag/Quellen-Snapshot | `VALUATION-COMPS-01` | **BACKEND/ENGINE GAP** |
| Ertragswert DE | vereinfachter Rechenweg vorhanden | Faktoren/Result vorhanden | Verfahrensvariante, vollständige Markt-/Modellkonformität, boG, geprüfte Referenzdaten, Value Basis | `VALUATION-MARKET-METHODS-01` | **BACKEND/ENGINE GAP** für Marktwert; technische Preview **REHOST NOW** |
| Sachwert DE | vereinfachter Rechenweg vorhanden | Faktoren/Result vorhanden | gesicherte NHK/GND/Index-/Regional-/Sachwertfaktordaten, Modellkonformität, boG | `VALUATION-MARKET-METHODS-01` | **BACKEND/ENGINE GAP** für Marktwert; technische Preview **REHOST NOW** |
| Aggregate DCF | jährliche unlevered Engine vorhanden | Faktoren, Report, Cashflow und KPIs vorhanden | Value-Basis-/Scope-Metadaten; vollständige fachliche Validation; Engine-Version | `VALUATION-METHOD-CONTRACT-01`, `VALUATION-VALIDATION-01` | **REHOST NOW** als interne Investmentanalyse |
| Direct Capitalization | Engine vorhanden | Faktoren/Result vorhanden | `capRate > 0`, einheitliche NOI-Semantik, Scope-/Label-Metadaten | `VALUATION-VALIDATION-01`, `VALUATION-METHOD-CONTRACT-01` | **BACKEND/ENGINE GAP** |
| Reconciliation | gemischte Default-Gewichtung vorhanden | Config, Templates und `MarketValueOpinion` vorhanden | Ergebnisfamilien, Basis, Eligibility, begründete Reliance, keine stille Renormalisierung | `VALUATION-METHOD-CONTRACT-01` | **BACKEND/ENGINE GAP**; heutige Engine **BLOCKED** |
| Lease-by-Lease Cashflow | nicht vorhanden | Lease/Rent-Roll nur als Quelle | Event-/MLA-Modell, Indexation, void/incentives/TI/LC, Cashflow Engine | `VALUATION-LEASE-CF-01` | **FUTURE** |
| CapEx Cashflow | nicht vorhanden | CapEx-Quelle vorhanden; keine Valuation-Kopplung | Auswahl Budget/Forecast/Actual, Periodisierung, recurring CapEx, DCF Mapping | `VALUATION-CAPEX-CF-01` | **FUTURE** |
| Debt Cashflow | vereinfachte Legacy-Proforma | kein Cloud-Valuation-/Finance-Contract | Draws, Fees, Tilgung, Refi, Covenants, Restschuld, levered KPIs | `VALUATION-DEBT-01` | **FUTURE** |
| Sensitivity | Legacy 5×5 vorhanden | kein Cloud-Contract | Achsen-/Range-Contract, Baseline-Version, serverreproduzierbare Runs, Ergebnisfamilie | `SCENARIO-VALUATION-01` | **BACKEND/ENGINE GAP** |
| Version History | Legacy-Snapshots/Diff vorhanden; Cloud nur Version Counter | Current-State/Expected-Version, keine History-Query | immutable Cloud-Snapshots, Engine-/Source-Version, Diff/Restore-as-new | `VALUATION-VERSION-01` | **BACKEND/ENGINE GAP** |
| Audit Read | Writes/Events vorhanden | keine Valuation-Audit-Query | lesbarer Timeline-Port, sichere Projektion/Permission | `VALUATION-AUDIT-READ-01` | **BACKEND GAP** |
| Export | Legacy JSON/CSV/PDF-Datasheet | Publish speichert Report, kein Artefakt | fachlich klassifizierter Report, Version/Quelle/Freigabenachweis, Artifact Contract | `VALUATION-REPORT-EXPORT-01` | **BACKEND GAP** |

### 7.1 Neues Pflichtpaket: `VALUATION-METHOD-CONTRACT-01`

Vor Publish/Review/Approval/Export muss der Contract mindestens tragen:

- `analysis_category`: `market_valuation` oder `investment_analysis`;
- `basis_of_value`: z. B. `market_value`, `investment_value`, `none_analysis_only`;
- Intended Use/Users, Valuation Date, Currency und Property Interest;
- methodenspezifischen Ergebnisbegriff und Scope;
- Engine-/Methoden-/Source-Snapshot-Version;
- Method Eligibility und dokumentierte Begründung;
- getrennte Reconciliation je Ergebnisfamilie, ohne Averaging oder stille Renormalisierung;
- Approval Class: `analysis`, `indicative_valuation`, `professional_market_valuation`;
- Gate-/Validation-Fehler als maschinenlesbare Gründe.

Dieses Paket ersetzt oder migriert die fachlich irreführende Annahme, jedes Case müsse ein `MarketValueOpinion` besitzen. Die konkrete Schema-/API-Lösung ist nicht Teil von `METHOD-GOV-01`.

### 7.2 Paketzuordnung

| Paket | Scope |
|---|---|
| `VALUATION-METHOD-CONTRACT-01` | Kategorien, Value Basis, Ergebnisbegriffe, Eligibility, getrennte Reconciliation, Approval Classes |
| `VALUATION-VALIDATION-01` | identische Domain-/Server-Grenzprüfung, NOI-Semantik, Terminalbedingungen |
| `VALUATION-MARKET-METHODS-01` | fachliche Modellkonformität von Ertrags-/Sachwert, Referenzdaten, boG, Verfahrensvarianten |
| `VALUATION-COMPS-01` | belastbare Cloud-Comparables und Vergleichswertmodell |
| `VALUATION-LEASE-CF-01` | Lease-by-Lease Cashflow und MLA |
| `VALUATION-CAPEX-CF-01` | CapEx-Auswahl, Periodisierung und Cashflow-Kopplung |
| `VALUATION-DEBT-01` | Debt Contract/Engine und levered Ergebnisfamilie |
| `SCENARIO-VALUATION-01` | Baselines, Szenarien und reproduzierbare Sensitivität |
| `VALUATION-VERSION-01` | immutable Versionen, Vergleich und Restore-as-new |
| `VALUATION-AUDIT-READ-01` | lesbarer Audit Trail |
| `VALUATION-REPORT-EXPORT-01` | klassifizierte, versionierte Berichte/Exporte |

## 8. Rehost Now, Backend/Engine Gap, Future

### A. REHOST NOW

Sicher ohne neue fachliche Engine/Schema:

1. Queue öffnen, suchen, filtern und Case-Navigation; keine Value-Spalte.
2. Cloud-Case als **interne Analyse** erstellen; die heutigen Templates dürfen keine professionelle Methodenempfehlung oder freigabefähige Gewichtung anzeigen.
3. Case-Header, Faktoren mit Provenance, Varianten und Stale-/Missing-States lesen/bearbeiten.
4. Einzelne technische Ertrags-/Sachwert-Modellrechnungen mit den Labels aus 4.1 zeigen.
5. Aggregate DCF-Cashflow, DCF Value und eindeutig unlevered Investment-KPIs zeigen.
6. Bestehende genehmigte/archivierte Datensätze read-only darstellen, dabei Legacy-`MarketValueOpinion` als „nicht klassifizierter Legacy-Ergebnisstand“ kennzeichnen.

Nicht Teil von Rehost Now: gemischte Opinion-Karte, Methoden-/Gewichts-Editor, Publish, Submit for Review, Approval und Export. Diese Aktionen schreiben oder bestätigen heute zwingend den fachlich unzulässigen gemischten Ergebnisstand.

### B. BACKEND/ENGINE GAP

- `VALUATION-METHOD-CONTRACT-01`
- `VALUATION-VALIDATION-01`
- `VALUATION-MARKET-METHODS-01`
- `VALUATION-COMPS-01`
- `SCENARIO-VALUATION-01`
- `VALUATION-VERSION-01`
- `VALUATION-AUDIT-READ-01`
- `VALUATION-REPORT-EXPORT-01`

Erst danach können indikative Bewertung, getrennte Reconciliation, fachliche Review/Freigabe, Versionsvergleich, Audit und Export implementiert werden.

### C. FUTURE

- Lease-by-Lease DCF und Market Leasing Assumptions;
- CapEx-integrierter Cashflow;
- Debt Cashflow, Refinanzierung und levered DCF;
- Portfolio-/Fund-Reconciliation;
- komplexe ARGUS-Yield-Methoden wie Hardcore, Term and Reversion oder Capval;
- Development/Residual Valuation, Steuer-, Fair-Value-, Beleihungswert- oder Versicherungswertverfahren;
- rechtliche oder berufsständische Zertifizierung durch NexImmo.

## 9. Verbindliche Auswirkungen auf die vier Valuation-Specs

### 9.1 `valuation_queue_v2`

- `Marktwert/Investmentwert` aus optionaler Phase-A-Listenprojektion entfernen.
- Ein künftiges Ergebnisfeld benötigt `analysis_category`, `basis_of_value`, spezifischen Ergebnisbegriff, Stichtag und Approval Class; kein generisches `Value`.
- Bestehende Cases dürfen Status zeigen; `approved` bedeutet ohne Approval Class nicht „professioneller Marktwert“.
- Queue-Rehost bleibt **APPROVED**.

### 9.2 `valuation_create_v2`

- Case-Art ist nicht gleich Wertbasis. Create muss Phase A als `Interne Analyse` erklären.
- Template-Methoden und -Gewichte sind read-only technische Legacy-Konfiguration; keine Empfehlung und keine Market-Value-Eignung.
- Methoden-/Gewichts-Editor bleibt bis `VALUATION-METHOD-CONTRACT-01` blockiert.
- Cloud-Create-Rehost bleibt **APPROVED**, professionelle/indikative Bewertungserstellung ist **BLOCKED**.

### 9.3 `valuation_case_workspace_v2`

- Bereiche in `Market Valuation – technische Modellrechnungen` und `Investment Analysis` trennen.
- `MarketValueCard` und gemischte Reconciliation im Rehost nicht anzeigen.
- DCF, NOI und IRR erhalten die Labels/Scopes aus Abschnitt 4.1; Direct Capitalization bleibt bis Validation ausgeblendet.
- Publish, Submit for Review und Approval bleiben für neue Rehost-Cases blockiert, bis der Method Contract getrennte Ergebnisfamilien und Approval Classes trägt.
- Existing approved cases nur read-only, als Legacy-Ergebnisstand gekennzeichnet.
- Case-Core-Rehost wird auf Read/Edit/Live-Preview/Varianten reduziert; Status-Transitions mit Ergebniswirkung sind nicht Rehost Now.

### 9.4 `valuation_v2_workflow`

- Methodenabschnitt und Gap-Matrix durch diese Entscheidung als verbindliche Quelle referenzieren.
- `METHOD-GOV-01` von **BLOCKED** auf **APPROVED** setzen; Umsetzung als neues **BLOCKED**-Paket `VALUATION-METHOD-CONTRACT-01` führen.
- Paket `P02` auf Case Read/Edit/Live-Preview begrenzen.
- Paket `P03` bleibt für vorhandene aggregate DCF-Visualisierung **APPROVED**.
- Publish/Review/Approval aus Rehost entfernen und vom Method Contract abhängig machen.
- Offene Methoden-/Begriffs-/Reconciliation-Fragen schließen; nur Implementierungsdetails offen lassen.

## 10. Abnahmeregeln für Folgepakete

1. Kein Contract-, Engine-, UI-, Audit- oder Exporttest darf Market- und Investment-Methoden in einer Opinion erwarten.
2. Jeder Geldwert besitzt Ergebnisbegriff, Kategorie, Basis, Stichtag, Währung, Scope und Engine-Version.
3. Tests beweisen, dass DCF/Capitalized Value/Purchase Price/Offer nicht als Marktwert serialisiert oder gerendert werden.
4. Reconciliation-Tests beweisen: keine Averaging-Defaults, keine Cross-Family-Gewichte, keine stille Renormalisierung.
5. Professional-Gate-Tests liefern konkrete Blocking Reasons.
6. Legacy-Ersatzmethoden werden weder migriert noch als neue Engines verwendet.

## 11. Abschluss

- Finales Methodenmodell: **Market Valuation** und **Investment Analysis**, plus getrennte Transaktions-/Entscheidungsebene.
- Erlaubte Ergebnisbegriffe: nur die in Abschnitt 4 definierten, jeweils mit Basis und Scope.
- Reconciliation: nur innerhalb derselben Wertbasis; begründete Reliance, kein Mitteln, nie Market + Investment.
- Rehost Now: Queue/Create als interne Analyse, Factors/Variants/Live-Preview, technische deutsche Modellrechnungen und aggregate unlevered DCF.
- Blockiert: heutige gemischte Opinion, Direct Capitalization bis Validation, Market-Value-Indikation/Freigabe, Publish/Review/Approval/Export sowie alle Gap-Fähigkeiten.
- Neue Pflichtpakete: `VALUATION-METHOD-CONTRACT-01`, `VALUATION-VALIDATION-01`, `VALUATION-MARKET-METHODS-01` plus die in 7.2 benannten Fachpakete.
- `METHOD-GOV-01` = **APPROVED**. Die Governance ist entschieden; die Umsetzung der neuen Contracts/Engines bleibt separat **BLOCKED**.
