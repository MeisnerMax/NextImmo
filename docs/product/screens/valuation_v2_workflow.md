# Valuation V2 — gemeinsamer Workflow

## Metadata

- Spec-/Screen-ID (kein Arbeitspaket): `VALUATION-V2-WORKFLOW-01`
- Parent-Arbeitspaket: `VALUATION-REHOST-01`; freigegebene Teilpakete `VALUATION-REHOST-01A`–`01C`
- Domain: Valuation, Property, Leasing, CapEx, Reporting, Audit
- Routen: `/valuations`, `/valuations/new`, `/valuations/:valuationCaseId`
- Aktueller Einstieg: `lib/ui/screens/valuations/valuations_screen.dart`
- Aktueller Case-Host: `lib/ui/screens/property_detail/widgets/valuation/valuation_section_host.dart`
- Planning status: **APPROVED** für `REHOST NOW`; blockierte Ausbauumfänge stehen in Abschnitt 2
- Verbindliche Screen-Specs:
  - [Valuation Queue V2](valuation_queue_v2.md)
  - [Create Valuation V2](valuation_create_v2.md)
  - [Valuation Case Workspace V2](valuation_case_workspace_v2.md)
- Verbindliche Fachentscheidung: [Valuation Method Governance (`METHOD-GOV-01`)](../VALUATION_METHOD_GOVERNANCE.md)
- Abhängigkeiten: Foundation-Decision `PRODUCT-UX-FOUNDATION-01` (kein Arbeitspaket), `SHELL-ROUTING-01`, Cloud-Valuation-Contract, Cloud-Property-Contract
- Stand der Recherche: 2026-08-28
- Publish-Prüfung: 2026-09-02 auf `origin/main` = `2818ecb1191c837202bd4b57fd019ba12208308d`

## 1. Zweck und Leitentscheidung

Das Zielbild von Valuation V2 führt eine Bewertung von der Arbeitsliste bis zum freigegebenen, berichtsfähigen Stand. `REHOST NOW` endet dagegen ausdrücklich bei der internen Analyse; Review, Approval, Publish und professionelle Marktwertausgabe folgen erst nach den in Abschnitt 2 blockierten Contract-/Engine-Paketen. Das System verbindet die fachliche Nachvollziehbarkeit eines professionellen Bewertungsmodells mit einer geführten Oberfläche für Nutzer, die nicht täglich bewerten.

Der Zielweg nach Abschluss der benannten Folgepakete lautet:

`Queue → Case → Annahmen → Cashflow → Bewertung → Szenarien/Sensitivität → Review/Freigabe/Version → Reporting`

Der verbindliche Phase-A-Weg von `VALUATION-REHOST-01A`–`01C` endet bei:

`Queue → Create → Case → Annahmen → Cashflow → Bewertung → Varianten`

Die Planung ist **kein Auftrag, Formeln neu zu erfinden**. Vorhandene Cloud-Contracts und Calculation Engines bleiben die fachliche Basis. ARGUS, Brixx und BrickMetrics liefern Workflow- und Verständlichkeitsmuster, keine ungeprüften Bewertungsmethoden.

Die wichtigste fachliche Trennung ist:

1. **Market Valuation:** deutsche Ertragswert-, Sachwert- und Vergleichswertverfahren auf objektiver, stichtagsbezogener Marktwertbasis; heute nur technische Modellrechnungen, keine freigabefähige Marktwertindikation.
2. **Investment Analysis:** DCF, Direct Capitalization, NOI, IRR, NPV, Equity Multiple und künftig Finanzierung auf expliziter Analyse-/Investor-Basis. Diese Ergebnisse sind weder automatisch Markt-/Verkehrswert noch automatisch Investment Value.

Beide Ebenen dürfen im selben Case arbeiten, werden aber nie gemeinsam reconciled. Purchase Price/Offer bilden eine dritte Anzeigeebene für Transaktionsentscheidungen, keine Methodenkategorie.

## 2. Freigabestatus und harte Gates

| Teilumfang | Status | Begründung / Gate |
|---|---|---|
| Queue öffnen, filtern, paginieren | **APPROVED** | Cloud-Contract und UI existieren; nur Rehost/Navigation ergänzen. |
| Create mit Cloud-Property-Auswahl | **APPROVED** | Valuation-Create-Contract und Cloud-Property-Read existieren; Legacy-Provider ersetzen. |
| Case-Deep-Link und sicherer Rehost des vorhandenen Cloud-Workflows | **APPROVED** | Case, Faktoren, technische Ertrags-/Sachwert-Modellrechnungen, aggregate DCF und Varianten existieren. Gemischte Opinion und Ergebnis-Transitions sind ausgeschlossen. |
| Geführte Darstellung der heute vorhandenen Faktoren | **APPROVED** | Keine neue Mathematik; bestehender Faktorkatalog bleibt maßgeblich. |
| Methoden-Governance | **APPROVED** | `METHOD-GOV-01` entscheidet Kategorien, Begriffe, Reconciliation und Professional Gate verbindlich. |
| Getrennte Ergebnisfamilien, Reconciliation, Publish/Review/Approval | **BLOCKED** | `VALUATION-METHOD-CONTRACT-01`: heutiger Contract erzwingt eine gemischte `MarketValueOpinion`. |
| Vergleichswert im Cloud-Betrieb | **BLOCKED** | `VALUATION-COMPS-01`: Cloud-Comparable-Port ist ausdrücklich nicht verfügbar. |
| Lease-by-Lease-Cashflow | **BLOCKED** | `VALUATION-LEASE-CF-01`: Lease-Events, MLA und Bewertungsengine fehlen. |
| CapEx im DCF | **BLOCKED** | `VALUATION-CAPEX-CF-01`: Cloud-Quelldaten existieren, aber kein Cashflow-Mapping/Engine-Schema. |
| Levered Cashflow und Debt Modeling | **BLOCKED** | `VALUATION-DEBT-01`: Cloud-Finance-Contract und freigegebene Debt Engine fehlen. |
| Fachliche Szenarien und Sensitivitätsmatrix | **BLOCKED** | `SCENARIO-VALUATION-01`: Varianten sind vorhanden, aber kein Szenario-/Matrix-Contract. |
| Version History und Model Comparison | **BLOCKED** | `VALUATION-VERSION-01`: nur aktuelle Case-Version und Legacy-SQLite-Snapshots vorhanden. |
| Lesbarer Audit Trail | **BLOCKED** | `VALUATION-AUDIT-READ-01`: Writes sind auditiert, aber es gibt keinen Valuation-Audit-Query-Port. |
| Exportierbarer Bewertungsbericht | **BLOCKED** | `VALUATION-REPORT-EXPORT-01`: Publish speichert Ergebnisse, erzeugt aber kein Dokument/Exportartefakt. |

**Freigaberegel:** Das Rehost-Paket darf nur interne Analyseergebnisse zeigen. Gemischte Opinion, Publish, Review, Approval und jede Marktwert-/Verkehrswertbezeichnung bleiben bis `VALUATION-METHOD-CONTRACT-01` beziehungsweise vollständigem Professional Gate gesperrt.

## 3. Begriffe ohne vorausgesetztes Vorwissen

| Begriff | Bedeutung in NexImmo |
|---|---|
| Case | Eine eigenständige Bewertung eines Objekts mit Status, Annahmen, Berechnung und Freigabe. |
| Annahme / Faktor | Ein Eingabewert, der eine Berechnung beeinflusst, etwa Miete, Kosten oder Zinssatz. |
| Provenance / Herkunft | Kennzeichnet, ob ein Wert manuell, abgeleitet, vorgeschlagen, akzeptiert oder fehlend ist. |
| Baseline | Zielbegriff nach `SCENARIO-VALUATION-01`: ein explizit gewählter Bezugstand für Deltas. Phase A besitzt keine neue Baseline- oder Diff-Funktion. |
| Szenario / Variante | Eine alternative Kopie eines Cases mit bewusst abweichenden Annahmen. |
| DCF | Discounted Cash Flow: zukünftige Netto-Cashflows und Terminalwert werden auf heute abgezinst. |
| NOI / Reinertrag | Ertrag nach Leerstand und laufenden Bewirtschaftungskosten, vor Finanzierung und Steuern. |
| Cap Rate | Kapitalisierungszins zur Ableitung eines Werts aus einem stabilisierten NOI. |
| IRR | Interner Zinsfuß einer Cashflow-Reihe; hier aktuell unlevered, solange keine Finanzierung einfließt. |
| Stale / veraltet | Ein publizierter Rechenstand passt nicht mehr zur aktuellen Case-Version. |
| Approved | Technischer Legacy-Workflowstatus. Ohne Approval Class aus dem neuen Method Contract ist dies keine professionelle Marktwertfreigabe. |

## 4. Referenz-Benchmark

### 4.1 Offizielle Quellen

Primäre Referenzen:

- [ARGUS Enterprise](https://www.altusgroup.com/solutions/argus-enterprise/): Lease-by-Lease-Modellierung, DCF und Kapitalisierung, Debt Modeling, Szenarien, Sensitivität und Berichte.
- [ARGUS Intelligence](https://www.altusgroup.com/solutions/argus-intelligence/): verbundene Modelle, Annahmenvergleich und Szenariosimulation.
- [ARGUS Asset Manager](https://www.altusgroup.com/solutions/argus-intelligence/asset-manager/): Performance, Annahmenprüfung und Drilldown bis auf Mietvertragsebene.
- [ARGUS Portfolio Manager](https://www.altusgroup.com/solutions/argus-intelligence/portfolio-manager/): Ist/Plan/Hypothese, KPI-Drilldown und Dashboard-/PDF-Export.
- [ARGUS Intelligence Product Roadmap](https://www.altusgroup.com/solutions/argus-intelligence/product-roadmap/): als Zukunftsreferenz gekennzeichnete Annahmen- und Modellvergleiche.
- [ARGUS Intelligence Release März 2026](https://www.altusgroup.com/product-releases/argus-intelligence-release-mar26/): Szenariosimulation, Teilen und Bild/PDF-Export.
- [ARGUS Intelligence Release 30. März 2026](https://www.altusgroup.com/product-releases/argus-intelligence-release-30mar26/): Annahmenübersicht und Vergleich mehrerer Modelle gegen eine Referenz.
- [Altus zur Auditierbarkeit von Bewertungsprozessen](https://www.altusgroup.com/insights/top-3-data-hurdles-real-estate-valuations-process/): Who/When/What-Audit-Logs und nachvollziehbare Annahmen als Prozessprinzip, nicht als Beleg für ein bestimmtes ARGUS-Screenfeature.

Sekundäre Referenzen:

- [Brixx](https://brixx.com/): visuelle, geführte Modellbildung und verständliche Zukunfts-Cashflows.
- [Brixx Buy-to-let](https://brixx.com/solutions/buy-to-let/): Miete, Instandhaltung, Finanzierung und alternative Annahmen in einer vereinfachten Investment-UX.
- [Brixx Features](https://brixx.com/features/): Templates, Forecast versus Actuals, What-if und Exporte.
- [Brixx Feature Collection](https://brixx.com/features/feature-collection-list/): langfristige Modelle, Szenarien und Drei-Rechnungs-Berichte.
- [BrickMetrics Beta](https://www.brickmetrics.de/beta): geführte deutsche Immobilienanalyse, langfristiger Cashflow, Finanzierung und Real-/Best-/Worst-Szenarien. Als öffentliche Beta-Produktdarstellung, nicht als Bewertungsstandard, verwendet.

Die Recherche übernimmt öffentliche Funktions- und Workflow-Ideen. Proprietäre Screens, Assets, Begriffe und exakte Layouts werden nicht kopiert. Roadmap- oder „Coming soon“-Angaben gelten nicht als bestehende Funktion.

Öffentlich sichtbare Screen-/Demo-Muster, die die Planung beeinflusst haben:

| Quelle | Öffentlich gezeigtes Muster | Übertragene Idee, nicht UI-Kopie |
|---|---|---|
| ARGUS Enterprise | Cash Flow Summary, Valuations Summary, Tenant Summary und Sensitivity Matrix auf der offiziellen Produktseite | klar getrennte Cashflow-, Methoden-, Tenant- und Sensitivitätsansichten |
| ARGUS Intelligence Releases | Summary Assumptions, Vergleich mehrerer Modelle mit einer Referenz, Scenario Simulation | Baseline sichtbar halten und Annahmendeltas vor Ergebnisdeltas erklären |
| ARGUS Asset/Portfolio Manager | Drilldown von Portfolio/Property bis Lease sowie Ist/Plan/Hypothese | sourcebasierter Drilldown; Portfolio selbst bleibt außerhalb V2 |
| Brixx Produkt-/Feature-Seiten | visueller Model Builder, Timeline/What-if, Cashflow und Actual-vs-Forecast | geführte Eingabe, verständliche Wirkung einer Änderung und kuratierte Berichte |
| BrickMetrics Beta und eingebettete öffentliche Demo | geführte Immobilienanalyse, 30-Jahres-Cashflow, Real/Best/Worst und Finanzierung | deutsch verständliche Entscheidungsreise; Mathematik/Mehrdarlehen werden nicht übernommen |

### 4.2 Reference Feature Matrix

| Referenz | Funktion | User Job | NexImmo-Fit | Entscheidung |
|---|---|---|---|---|
| ARGUS Enterprise | Lease-by-Lease-Modell | Vertragslaufzeiten, Mieten und Optionen einzeln prognostizieren | Hoher Fit für Gewerbe; Cloud-Leases sind vorhanden, Valuation Engine fehlt | **ADAPT**, Zukunft |
| ARGUS Enterprise | Market Leasing Assumptions (MLA) | Anschlussvermietung, Marktmiete und Downtime modellieren | Fachlich sinnvoll bei Gewerbe, für einfache Wohnobjekte zu schwer | **ADAPT**, asset-klassenabhängig |
| ARGUS Enterprise | DCF | Langfristigen Objektwert aus Cashflows ableiten | Aggregate jährliche DCF existiert bereits | **ADOPT**, bestehende Engine |
| ARGUS Enterprise | Traditionelle Kapitalisierung / Initial Yield | Stabilisierten Ertrag schnell einordnen | Direktkapitalisierung und Renditekennzahlen existieren | **ADOPT**, als Investmentanalyse |
| ARGUS Enterprise | Debt Modeling | Unlevered und levered Renditen vergleichen | Nutzerjob relevant, Cloud-Finanzierung fehlt | **ADAPT**, später getrennte Ebene |
| ARGUS Enterprise | Szenariovergleich | Annahmen und Ergebnisfolgen vergleichen | Cloud-Varianten existieren, Detailvergleich fehlt | **ADAPT** |
| ARGUS Enterprise | Sensitivity Matrix | Wirkung zweier Werttreiber transparent sehen | Legacy-Engine kennt nur Kaufpreis/Miete; kein Cloud-Contract | **ADAPT**, nicht kopieren |
| ARGUS Enterprise | Assumptions vs Actuals | Modell gegen Ist-Daten prüfen | Finanz-/Actuals-Contract noch nicht vorhanden | **ADAPT**, Zukunft |
| ARGUS Intelligence | Baseline-/Modellvergleich | Änderungen zwischen Ständen nachvollziehen | Sehr hoher Fit für Review und Audit | **ADAPT**, neuer Version-Contract |
| ARGUS Intelligence | Property/Portfolio/Lease Drilldown | Abweichung bis zur Quelle verfolgen | Property und Lease sind vorhanden; Portfolio außerhalb dieses Pakets | **ADAPT**, Case zuerst |
| ARGUS | 40+ Berichte / umfangreiche KPI-Kataloge | Stakeholder-spezifisch berichten | Für NexImmo V2 unnötige Breite | **REJECT** als Umfang; kuratierte Berichte |
| ARGUS | Auditierbare Annahmen | Wer änderte welchen Wert, wann und warum? | Cloud-Writes sind auditiert, Read-Port fehlt | **ADOPT** |
| Brixx | Geführte Eingabe statt Tabellenwand | Ohne Spezialwissen ein belastbares Modell aufbauen | Kernziel der V2 | **ADOPT** |
| Brixx | Visueller langfristiger Cashflow | Liquidität und Werttreiber verstehen | Jährlicher DCF-Cashflow existiert | **ADOPT**, vorhandene Werte visualisieren |
| Brixx | Ein-/Ausschaltbare What-if-Varianten | Änderungen direkt testen | Cloud-Varianten passen, Toggle darf nicht heimlich speichern | **ADAPT** |
| Brixx | Verständliche Berichte | Investmententscheidung kommunizieren | Hoher Fit | **ADOPT**, kuratiert und quelloffen |
| Brixx | Generische Drei-Rechnungs-Planung | Cashflow, GuV und Bilanz gemeinsam planen | NexImmo Valuation ist keine Unternehmensplanung | **REJECT** für V2 |
| BrickMetrics | Geführter Analyseablauf | Analyse in wenigen verständlichen Schritten durchführen | Hoher Fit für Create und Annahmen | **ADOPT** |
| BrickMetrics | Langfristiger Immobilien-Cashflow | Halteperiode und Exit verstehen | Aggregate DCF vorhanden | **ADAPT** an vorhandene Engine |
| BrickMetrics | Real/Best/Worst | Entscheidung unter Unsicherheit treffen | Benennung ist verständlich; mathematische Definition fehlt | **ADAPT**, erst mit Szenario-Contract |
| BrickMetrics | Mehrere Darlehen | Finanzierungsstrukturen vergleichen | Aktuelles Legacy-Modell kennt nur ein vereinfachtes Darlehen | **REJECT** für V2; später neu spezifizieren |
| BrickMetrics | Steueroptimierung | Nachsteuerergebnis verstehen | Kein Steuer-Domainmodell, hohe Rechts-/Fachabhängigkeit | **REJECT** |
| BrickMetrics | Deal-Phasen / Datenraum | Analyse in Kaufentscheidung überführen | Gehört zu Deal-/Document-Domain, nicht Valuation Case | **REJECT** aus diesem Screen; separat verlinkbar |

## 5. Repository-Befund und Rehost-Grenze

| Bestand | Befund | V2-Entscheidung |
|---|---|---|
| Valuations Queue | Erreichbar; `onOpenCase` wird vom Cloud-Shell-Einstieg nicht übergeben | Rehost, keinen neuen List-Contract bauen |
| Create Dialog | Schreibt über Cloud-Case-Contract, liest Properties aber aus Legacy-Provider | Auf bestehenden Cloud-Property-Read-Port umverdrahten |
| `valuation_section_host` | Cloud-Case-Workflow existiert, aber nur über den toten Legacy-Analysis-Screen | Als eigenständigen Case-Workspace rehosten |
| Cloud Valuation Contract | Cases, Faktoren, Konfiguration, Varianten, Status, Reports, Optimistic Concurrency, RLS und Audit vorhanden | Beibehalten |
| Cloud Calculation Engines | vereinfachte Ertrags-/Sachwertrechnung, Comparison-Rechenweg, aggregate DCF, Direct Capitalization, gemischte Reconciliation und Kennzahlen vorhanden | sichere Einzelrechnungen behalten; Comparison, Direct Capitalization und gemischte Reconciliation gemäß Governance blockieren |
| Cloud Property Contract | Property-Liste und -Detail vorhanden; Detail ist für Bewertungsflächen und Kaufdaten zu dünn | Für Auswahl nutzen; Import-Gaps separat lösen |
| Cloud Leasing Contract | Units, Leases, Live-/Snapshot-Rent-Roll mit Version/RLS/Audit vorhanden | Als transparente Quelle nutzen; nicht mit einer Lease-DCF-Engine verwechseln |
| Cloud CapEx Contract | Projekte mit Budget/Forecast/Actual und Terminen vorhanden | Als Quelle nutzbar; DCF-Integration ist neues Engine-Paket |
| Legacy Inputs/Analysis | Breite Eingaben, Debt/CapEx, Exporte und Sensitivität, aber SQLite und vereinfachte Formeln | Nur UX-/Testmuster selektiv portieren |
| Legacy Scenarios | Eigener Lifecycle und Inline-Formeln, nicht Cloud-Valuation-kompatibel | Nicht rehosten |
| Legacy Versions | Unveränderliche JSON-Snapshots, Hash, Diff und Rollback-Sicherung | Muster übernehmen, Contract neu planen |
| Legacy Lease Engines | Rent-Roll- und einfache jährliche Indexationshelfer | Keine professionelle Valuation Engine; nur nach Golden-Model-Tests portierbar |
| Legacy Reporting | CSV/PDF/JSON-Helfer für lokale Records | Kein Ersatz für versionierten Cloud-Valuation-Bericht |

### Vertragsbasierter Widget-Bestand

| Widget | Heutige Funktion / Befund | V2-Verwendung |
|---|---|---|
| `valuations_screen.dart` | Contract-basierte Queue, Filter, Keyset „Mehr laden“, States; Row-Callback im Shell fehlt | vollständig behalten, Route verdrahten |
| `valuation_create_dialog.dart` | vier Templates und Suggestions; Property Read ist Legacy-defekt | Formlogik behalten, Cloud Property Lookup + Route |
| `valuation_section_host.dart` | löst heute Scenario → Case auf, hostet Controller/Workflow/Varianten/Approval | Case-ID zum primären Input machen, Scenario-Abhängigkeit entfernen |
| `valuation_section.dart` | Status, Live/Stored Report, Marktwertkarte, fünf Methodenkarten, KPIs, Assumption Ledger | nur als Harvest-Basis; `MarketValueCard`, Comparison, Direct Capitalization und gemischte Opinion in Phase A nicht rendern |
| `valuation_factors_section.dart` | gruppierter Batch Save und Draft-Erhalt; Parsingfehler werden teilweise still übersprungen | behalten; Phase A nur vorhandene Factor-Gruppen, Provenance und Parsing-/Validation-UX. Neue Source-/Delta-Darstellung bleibt `VALUATION-SOURCE-01`/`SCENARIO-VALUATION-01` |
| `valuation_factor_row.dart` | typisierte Money/Percent/Years/Area/Factor-Eingabe | behalten; vorhandene Herkunft/Provenance zeigen, neue SourceRef-/Baseline-Felder nicht im Rehost ergänzen |
| `valuation_workflow_stepper.dart` | Objekt, Faktoren, Report, Review, Freigabe in fünf Schritten | nur sichere Objekt-/Faktor-/Berechnungsanteile ernten; Report-/Review-/Freigabeschritte in Phase A nicht rendern |
| `valuation_variant_bar.dart` | Variantengruppe, Create/Switch, heutiger Wert und stale state | Gruppe/Create/Switch/Status/Stale behalten; einen aus gemischter Legacy-Opinion stammenden Wert nicht als reguläres Varianten-KPI rendern; Detailvergleich bleibt Contract-Gap |

Relevante Testbasis ist vorhanden für Queue/Create, Case Controller/Repository/Adapter/Invalidation, alle fünf Methoden, Reconciliation, Investment Metrics, Templates/Faktorkatalog sowie Section Host, Section, Factors, Workflow Stepper und Variant Bar. SQL-Contract-Tests decken RLS, Commands, Idempotenz, Versionierung, Report-Publish, Status, Approval-Immutability, Varianten und Audit ab. Die V2-Testpläne erweitern diese Basis; sie ersetzen sie nicht.

### Rehost

- Queue-Row und Create-Erfolg öffnen einen adressierbaren Case.
- Create verwendet Cloud-Properties.
- Bestehende Cloud-Widgets für Faktoren, sichere Einzelmethoden und Varianten werden in einen Case-Workspace gesetzt; `MarketValueCard`, gemischte Opinion und Ergebnis-Transitions nicht.
- Vorhandene jährliche DCF-Projektion wird als Cashflow-Tabelle/-Diagramm sichtbar gemacht, ohne neue Berechnung.

### Echte Neuentwicklung

- semantische Factor-Validierung im Domain-/Server-Contract;
- Contract-Umsetzung der beschlossenen Methodenkategorien, Wertbasen und Approval Classes;
- Comparable-Cloud-Port;
- Source-Import-Adapter und Source-Snapshot;
- Lease-/CapEx-/Debt-Cashflow-Schema und Engines;
- Szenario-/Sensitivitäts-Contract;
- Version-History-, Vergleichs- und Audit-Read-Contract;
- documentfähiger Report-/Export-Contract.

## 6. Fachlich benötigte Bewertungsmethoden

| Methode | Nutzerzweck | Heute unterstützt | V2-Einsatz | Status |
|---|---|---:|---|---|
| Ertragswertverfahren DE | objektive Marktwertableitung | vereinfachter Rechenweg | Phase A nur „technische Ertragswert-Modellrechnung“; Marktwert nach Modell-/Daten-Gap | **BLOCKED** für Marktwert, Preview **APPROVED** |
| Sachwertverfahren DE | objektive Marktwertableitung | vereinfachter Rechenweg | Phase A nur „technische Sachwert-Modellrechnung“; Marktwert nach Modell-/Daten-Gap | **BLOCKED** für Marktwert, Preview **APPROVED** |
| Vergleichswert | Marktvergleich anhand geeigneter Vergleichsobjekte | Engine ja, Cloud-Daten nein | Erst anzeigen, wenn Mindestanzahl belastbarer Comparables verfügbar ist | **BLOCKED** |
| Aggregate DCF | aggregierter unlevered Barwert aus Jahres-NOI und Exit | Ja | `Aggregate DCF Value (unlevered, indikativ)`; nicht automatisch Investment Value | **APPROVED** als interne Analyse |
| Direktkapitalisierung | Stabilisierten NOI kapitalisieren | Ja | `Capitalized Value`, getrennte Yield-Analyse | **BLOCKED** bis `VALUATION-VALIDATION-01` |
| Lease-by-Lease DCF | Vertragsgenaue Gewerbe-Cashflows | Nein | Spätere Commercial-Real-Estate-Ausbaustufe | **BLOCKED** |
| Yield-Varianten wie Term/Reversion | Spezielle internationale Bewertungslogik | Nein | Kein belegter NexImmo-Bedarf | **REJECT** bis eigener Business Case |
| Levered DCF | Eigenkapitalrendite unter Finanzierung | Legacy vereinfacht | Separat von Objektwert; erst nach Debt-Contract | **BLOCKED** |

Harte fachliche Invarianten:

- Investmentkennzahlen dürfen nicht als gesetzlicher oder gutachterlicher Verkehrswert bezeichnet werden.
- Nicht verfügbare Methoden zeigen Grund und fehlende Eingaben; sie liefern niemals `0 €` als Ersatzwert.
- Vorgeschlagene Defaults fließen erst nach expliziter Annahme in die Berechnung ein.
- Die aktuelle Engine darf nicht durch Legacy-Inline-Formeln ersetzt werden.
- `capRate <= 0`, nicht sinnvolle Quoten und technisch ungültige DCF-Terminalkombinationen müssen vor der Division/Berechnung abgewiesen werden. Die fehlende Direktkapitalisierungsprüfung ist `VALUATION-VALIDATION-01`.
- Market Valuation und Investment Analysis werden nie gemeinsam reconciled. Innerhalb einer Wertbasis ist nur begründete Reliance zulässig; bloßes Mitteln, Default-Gewichte und stille Renormalisierung sind verboten.

## 7. Finaler Workflow und Information Architecture

### 7.1 Hauptnavigation

| Route | Oberfläche | Aufgabe |
|---|---|---|
| `/valuations` | Queue | Cases finden, Status und Arbeitsvorrat sehen |
| `/valuations/new` | Create Valuation | Objekt, Case-Art und Startkonfiguration wählen |
| `/valuations/:valuationCaseId?section=overview` | Case Workspace | Phase A interne Analyse bearbeiten; später klassifiziert prüfen, freigeben und berichten |

`section` ist URL-Zustand. Die verbindliche Phase-A-Allowlist lautet exakt `overview`, `assumptions`, `cashflow`, `valuation`, `scenarios`. `scenarios` zeigt ausschließlich vorhandene Varianten und den Variant-Wechsel. Unbekannte Werte sowie die blockierten Zielwerte `review`, `versions` und `reporting` werden im Rehost kanonisch auf `overview` normalisiert; sie öffnen keine Platzhalter- oder Legacy-Oberfläche. Der Case muss per Deep Link neu ladbar sein. Shell-State und Browser-URL müssen synchron bleiben; die konkrete Routing-Lösung gehört zu `SHELL-ROUTING-01`.

### 7.2 Phase-A-Case-Navigation (`VALUATION-REHOST-01C`)

| Reihenfolge | Section-Key | Bereich | Phase-A-Inhalt |
|---:|---|---|---|
| 1 | `overview` | Überblick | Case, vorhandener Status, sichere KPIs, Vollständigkeit und Legacy-Stale-Hinweis; keine Baseline-Deltas |
| 2 | `assumptions` | Annahmen | vorhandener Faktorkatalog, vorhandene Provenance und `suggestedDefault/accepted/manual`-Semantik |
| 3 | `cashflow` | Cashflow | vorhandene jährliche aggregate-unlevered-DCF-Projektion |
| 4 | `valuation` | Bewertung | technische Ertrags-/Sachwert-Modellrechnungen und aggregate DCF; keine Comparables, Direct Capitalization oder Reconciliation |
| 5 | `scenarios` | Varianten | vorhandene Variantengruppe sowie Create/Switch; keine Baseline, Deltas oder Sensitivität |

### 7.3 Future / Blocked target IA

| Zielbereich | Voraussetzung | Phase-A-Verhalten |
|---|---|---|
| Review | `VALUATION-METHOD-CONTRACT-01` | keine Section, Fläche oder Aktion; `section=review` normalisiert auf `overview` |
| Versionen & Freigabe | `VALUATION-VERSION-01` + Method Contract | keine Section/History/Approval-Fläche; Legacy-Status nur read-only im Kopf/Overview |
| Bericht & Audit | `VALUATION-REPORT-EXPORT-01` + `VALUATION-AUDIT-READ-01` | keine Section/Export-/Audit-Fläche; vorhandene Legacy-Report-Metadaten nur read-only im Overview |

### 7.4 Nutzerreisen

**Analyst erstellt eine Bewertung**

1. Öffnet die Queue und wählt „Neue Bewertung“.
2. Wählt ein Cloud-Property und eine verständlich erklärte Case-Art.
3. Prüft vorhandene manuelle, vorgeschlagene und fehlende Annahmen getrennt; neue Source-Imports sind nicht Teil von Phase A.
4. Bestätigt jeden Vorschlag, der in die Berechnung einfließen soll.
5. Prüft Cashflow, Methodenwerte, fehlende Faktoren und Konfidenz.
6. Speichert die Annahmen und beendet Phase A mit einer internen Live-Analyse; Publish/Review ist blockiert.

**Analyst untersucht in Phase A eine Variante**

1. Öffnet einen Draft oder eine Variante.
2. Wechselt über die vorhandene Variantengruppe den aktiven Case oder erstellt eine Variante.
3. Prüft deren vorhandene Faktoren, sichere Methodenwerte und DCF-KPIs ohne automatische Delta-/Baseline-Aussage.
4. Ändert einen vorhandenen Faktor mit optionalem Änderungsgrund.
5. Berechnung wird lokal neu aufgebaut; ein vorhandener Legacy-Stand wird als veraltet markiert.
6. Ein neuer Stand wird in Phase A weder verglichen noch publiziert. Baseline-/Model-Diff folgt erst mit `SCENARIO-VALUATION-01`/`VALUATION-VERSION-01`.

**Approver gibt einen Stand frei — erst nach `VALUATION-METHOD-CONTRACT-01`**

1. Öffnet einen Case `in_review` über Queue oder Deep Link.
2. Sieht fehlende Annahmen, Methodenstatus, Source-Warnungen und Differenz zur Baseline.
3. Prüft den exakt publizierten, nicht einen ungespeicherten Live-Stand.
4. Gibt mit `valuation.approve` frei oder sendet mit Grund in Draft zurück.
5. Der freigegebene Case wird unveränderlich und ist eindeutig als Approved markiert.

**Auditor prüft Nachvollziehbarkeit**

1. Öffnet den approved Case.
2. Sieht Version, Rechenstand, Methode, Faktoren, Herkunft, Zeit und Akteur.
3. Vergleicht den freigegebenen Stand mit Vorgänger/Baseline.
4. Exportiert einen Report mit Case-ID, Version, Berechnungszeitpunkt und Quellenanhang.
5. Schritte 2–4 bleiben bis zu den Read-/Export-Gaps blockiert; Writes selbst sind bereits auditiert.

## 8. Gemeinsames Eingabe- und Herkunftsmodell

### 8.1 Regeln für jede Eingabe

Diese Regeln beschreiben das Zielmodell zusätzlich zu den Einzelfeldern. Für `VALUATION-REHOST-01C` gilt die harte Teilmenge: vorhandene Factor-Werte, Einheiten, Notes, Confidence und Provenance bleiben sichtbar; vorhandene `suggestedDefault` werden bewusst akzeptiert. Neue SourceRef-/Snapshot-Felder, Source-vs-Case-Comparison, Baseline-Auswahl und Delta-Engine sind keine Phase-A-Anforderung.

- Geldwerte tragen eine Währung. Die heutige Valuation Engine ist faktisch EUR-orientiert; ein Multi-Currency-Case ist bis `VALUATION-CURRENCY-01` blockiert.
- Prozentfelder werden als Prozent eingegeben und als Dezimalzahl gespeichert (`3,5 %` → `0,035`). Die UI zeigt immer das Prozentzeichen.
- Leere Eingabe ist `missing`, niemals automatisch `0`.
- Ein Template- oder Referenzwert startet als `suggestedDefault` und ist **nicht rechenwirksam**, bis der Nutzer ihn akzeptiert. Dann wird er `accepted`.
- Nach `VALUATION-SOURCE-01` wird ein Cloud-Property-, Rent-Roll-, Lease- oder CapEx-Wert als Source-Suggestion mit Stichtag gezeigt. Import bleibt bewusst und nachvollziehbar; kein stilles Überschreiben.
- Manuelle Eingaben erhalten `userProvided`; rechnerisch abgeleitete Werte `derived` mit lesbarer Formel/Quell-IDs.
- Nach Source-/Scenario-Contract zeigt jedes Feld zusätzlich strukturierten Stichtag und Baseline-Delta. Phase A zeigt nur die heute im Factor Contract vorhandene Herkunft/Provenance, Note und Confidence.
- Speichern verwendet `expectedVersion`, `mutationId` und `correlationId`. Bei Version Conflict bleibt die Nutzereingabe erhalten und wird mit dem Serverstand vergleichbar.
- Approved Cases sind unveränderlich. „Ändern“ erzeugt künftig einen Revision-Case; es editiert nie den Approved-Stand.

### 8.2 Case- und Methodenkonfiguration

| Eingabe | Bedeutung / Einheit | Validierung | Herkunft und Default | Manuell / Übernahme | Tracking |
|---|---|---|---|---|---|
| Property | Bewertetes Objekt | erforderlich; lesbar im Workspace | kein Default | Cloud-Property auswählen | Case-ID, Property-ID, Create-Audit |
| Titel | Verständlicher Case-Name | 1–200 Zeichen serverkonform | Vorschlag aus Property + Case-Art | editierbar | Case-Version/Audit |
| Case-Art | Ankauf, Halten, Sanieren, Verkauf | eine der vier Contract-Arten | kein stiller Default; Template-Vorschau | manuell | Case-Version/Audit |
| Asset-Klasse | Quelle für Referenzvorschläge | Contract-Wert oder leer | aus Property-Typ nur als Vorschlag | übernehmen oder manuell | Vorschlagsquelle/Akzeptanz |
| Gebäudetyp | verfeinert Referenzvorschläge | Contract-Wert oder leer | aus Property nur als Vorschlag | übernehmen oder manuell | Vorschlagsquelle/Akzeptanz |
| Aktivierte Methoden | technische Legacy-Engineauswahl in Phase A; künftig fachlich zulässige Methoden | Phase A read-only; künftig Eligibility je Kategorie/Wertbasis | Case-Template | erst nach Method Contract manuell | Case-Config-Version/Audit |
| Methodengewichte/Reliance | heutige gemischte Gewichte sind blockiert; künftig begründete Reliance nur innerhalb einer Wertbasis | kein Averaging, keine Cross-Family-Gewichte, keine stille Renormalisierung, Summe 100 % | kein fachlicher Default | erst nach Method Contract manuell | Case-Config-Version/Audit + Begründung |
| DCF-Terminalmethode | Exit Cap oder Gordon Growth | genau eine; passende Terminaleingabe erforderlich | Template | manuell | Case-Config-Version/Audit |
| Mindestanzahl Comparables | Datenqualitätsschwelle | positive Ganzzahl | Contract/Template, aktuell 3 | manuell erst nach Comparable-Gap | Case-Config-Version/Audit |
| Verknüpftes Szenario | Herkunft aus anderem Scenario-Domainmodell | optionale ID | derzeit nur Legacy-Host-Pfad | nicht in V2 Create bis Contract | Case-Audit |

### 8.3 Aktueller Valuation-Faktorkatalog

`Default: keiner` bedeutet: Kein impliziter Zahlenwert. Referenzwerte dürfen nur als nicht rechenwirksame Vorschläge erscheinen. `Quelle` nennt die fachlich mögliche V2-Quelle; heute sind Faktoren überwiegend manuell oder Template-Vorschläge.

| Faktor | Bedeutung / Einheit | Fachliche Validierung | Mögliche Quelle | Default / Eingabe | Änderungsverfolgung |
|---|---|---|---|---|---|
| `grossRentAnnual` | Rohertrag, €/Jahr | ≥ 0; Währung konsistent | manuell; akzeptierter Live-/Snapshot-Rent-Roll `totalBaseRentMonthly × 12` mit Stichtag | keiner; Import nur als Vorschlag | Provenance, Source, Stichtag, Version, Audit |
| `operatingExpensesAnnual` | Bewirtschaftungskosten, €/Jahr | ≥ 0 | manuell; Finance/Actuals künftig | keiner | wie oben |
| `landValue` | Bodenwert gesamt, € | ≥ 0; alternativ Fläche × Richtwert | manuell/Referenzquelle | keiner | wie oben |
| `landAreaSqm` | Grundstücksfläche, m² | > 0, wenn Ableitung gewählt | Property nach Contract-Erweiterung | keiner | wie oben |
| `landValuePerSqm` | Bodenrichtwert, €/m² | ≥ 0; Quellenstichtag erforderlich | offizielle/kuratierte Referenzdaten | keiner; Vorschlag muss akzeptiert werden | wie oben plus Referenzversion |
| `liegenschaftszinssatz` | Zinssatz für Ertragswert, % | > -100 %; fachliche Positiv-/Bandprüfung in `VALUATION-VALIDATION-01` | kuratierte Referenzspanne | kein Zahlen-Default; Mitte darf nur Vorschlag sein | wie oben |
| `remainingUsefulLifeYears` | Restnutzungsdauer, Jahre | positive Ganzzahl; alternativ Gesamtalter-Modell | manuell/abgeleitet | keiner | Ableitungsformel + Quellfelder |
| `otherValueAdjustment` | besondere objektspezifische Zu-/Abschläge, € | Vorzeichen erlaubt; Begründung erforderlich, wenn ≠ 0 | manuell | leer, nicht `0` | Wert, Grund, Akteur, Audit |
| `grossFloorAreaSqm` | Bruttogrundfläche, m² | > 0 | Property nach Contract-Erweiterung | keiner | Provenance/Property-Version |
| `normalHerstellungskostenPerSqm` | Normalherstellungskosten, €/m² | > 0; Referenzjahr/-werk erforderlich | kuratierte Referenzdaten | keiner | Referenzversion/Akzeptanz |
| `constructionPriceIndex` | Baupreisindex als Faktor | > 0; Basisjahr sichtbar | kuratierte Referenzdaten | keiner | Basis/Quelle/Akzeptanz |
| `regionalFactor` | Regionalanpassungsfaktor | > 0 | kuratierte Referenzdaten | keiner | Quelle/Akzeptanz |
| `buildingAgeYears` | Gebäudealter, Jahre | ≥ 0 und nicht größer als Gesamtnutzungsdauer für Ableitung | Baujahr aus Property → abgeleitet zum Stichtag | keiner | Formel, Stichtag, Property-Version |
| `totalUsefulLifeYears` | Gesamtnutzungsdauer, Jahre | positive Ganzzahl | manuell/kuratierte Referenz | keiner | Quelle/Akzeptanz |
| `sachwertfaktor` | Marktanpassungsfaktor | > 0 | Gutachterausschuss/kuratierte Referenz | keiner | Quelle/Stichtag/Akzeptanz |
| `outdoorFacilitiesValue` | Außenanlagen, € | ≥ 0; optional | manuell/CapEx nicht automatisch | leer | Provenance/Audit |
| `subjectLivingAreaSqm` | Wohn-/Nutzfläche des Objekts, m² | > 0 | Property/Units nach Mapping | keiner | Quell-IDs, Stichtag, Version |
| `vacancyRate` | Mietausfall-/Leerstandsquote, % | 0–100 %; Bewertungsdefinition sichtbar | manuell; Rent-Roll nur als transparent berechneter Vorschlag | keiner | Basis Einheiten/Fläche, Stichtag, Akzeptanz |
| `rentGrowthRate` | jährliches Mietwachstum, % | > -100 %; fachliche Bandwarnung | manuell/Marktannahme | keiner | Provenance/Audit |
| `expenseGrowthRate` | jährliches Kostenwachstum, % | > -100 %; fachliche Bandwarnung | manuell/Marktannahme | keiner | Provenance/Audit |
| `holdYears` | DCF-Betrachtungszeitraum, Jahre | positive Ganzzahl | manuell/Case-Art-Vorschlag | kein stiller Default | Provenance/Audit |
| `discountRate` | DCF-Kalkulationszins, % | > -100 %; bei Gordon größer als Terminalwachstum | manuell/Investment Committee | keiner | Provenance/Audit |
| `saleCostRate` | Exit-Verkaufskostenquote, % | 0–100 % | manuell | keiner | Provenance/Audit |
| `exitCapRate` | Kapitalisierungszins für Terminalwert, % | > 0; nur bei Exit-Cap-Terminal | manuell/Marktannahme | keiner | Provenance/Audit |
| `terminalGrowthRate` | ewiges Wachstum für Gordon, % | kleiner als Kalkulationszins; nur Gordon | manuell | keiner | Provenance/Audit |
| `capRate` | Kapitalisierungszins für Direktkapitalisierung, % | **> 0**; server-/domainseitige Lücke schließen | manuell/Marktannahme | keiner | Provenance/Audit |
| `stabilizedNoiAnnual` | stabilisierter Reinertrag, €/Jahr | Wert zulässig; negative Werte warnen; alternativ aus Miete/Leerstand/Kosten | manuell oder transparent abgeleitet | keiner | Formel/Quellfaktoren/Version |
| `purchasePrice` | Kaufpreis für Investmentkennzahlen, € | > 0, wenn Kennzahlen berechnet werden; optional für Wertmethoden | Deal/Property nach Contract | keiner | Provenance/Source/Audit |

**Contract-Gap:** Der Server validiert heute Payload-Form, Provenance und Konfidenz, aber nicht alle semantischen Wertebereiche oben. UI-Validation allein genügt nicht.

### 8.4 Rent-/Lease-Inputs — geplante Erweiterung

Diese Felder sind **BLOCKED** für Berechnung. Sie dürfen in Phase A höchstens als read-only Quelle gezeigt werden. Es gibt keine neuen Formeln.

| Eingabe | Bedeutung / Einheit | Validierung | Herkunft / Default | Eingabemodus | Tracking |
|---|---|---|---|---|---|
| Unit und Fläche | vermietbare Einheit, m² | Property-Zugehörigkeit; Fläche > 0, wenn vorhanden | Cloud Unit; kein Default | übernommen, nicht im Case editiert | Unit-ID/-Version, Stichtag |
| In-place Basismiete | vertragliche Grundmiete, €/Monat | aktiver Lease, Laufzeit deckt Stichtag, gemeinsame Währung | Cloud Lease/Rent Roll; kein Default | übernommen; manueller Case-Override separat | Lease-ID/-Version, Stichtag |
| Nebenkosten/Parking | wiederkehrende Zusatzbeträge, €/Monat | ≥ 0; nicht als Basismiete doppelt zählen | Cloud Lease | übernommen | Lease-ID/-Version |
| Start/Ende | Vertragslaufzeit, Datum | Start ≤ Ende | Cloud Lease | übernommen | Lease-ID/-Version |
| Mietfreie Zeit | Freimonate, Monate | ganze Zahl ≥ 0 und fachlich innerhalb Laufzeit | Cloud Lease | übernommen | Lease-ID/-Version |
| Break-/Renewal-Datum | Kündigungs-/Optionszeitpunkt | innerhalb plausibler Laufzeit | Cloud Lease | übernommen | Lease-ID/-Version |
| Marktmiete | Markt-/Zielmiete, €/Monat | ≥ 0, Währung konsistent | Cloud Unit | übernommen oder Case-Override | Unit-ID/-Version, Provenance |
| Indexation/Staffel | Regel oder fester Schritt | Regeltyp, Start, Cap/Floor konsistent | nur Legacy-Modell vorhanden | kein Import in Phase A | künftige Rule-ID/-Version |
| Renewal Probability | Wahrscheinlichkeit einer Verlängerung, % | 0–100 % | keine Cloud-Quelle | kein Default; manuell künftig | Provenance/Audit |
| Downtime | Leerstandsmonate bei Anschlussvermietung | ganze Zahl ≥ 0 | keine Cloud-Quelle | kein Default; manuell künftig | Provenance/Audit |
| Incentives/Leasing Costs | Incentives und Vermietungskosten, € oder definierte Rate | Einheit eindeutig; keine Doppelzählung | keine Cloud-Quelle | kein Default; manuell künftig | Provenance/Audit |

Der aktuelle Cloud-Rent-Roll summiert aktive, zum Stichtag laufende Leases und weist Mischwährungen ausdrücklich aus. Eine Bewertung darf bei Mischwährung keinen Gesamtbetrag ableiten. Die Legacy-Indexation arbeitet nur mit einfachen CPI-/Fixed-Step-Regeln und ist keine freigegebene MLA-/Lease-DCF-Engine.

### 8.5 Operating, CapEx und Finanzierung — geplante Erweiterung

| Eingabe | Bedeutung / Einheit | Validierung | Herkunft / Default | Eingabemodus | Tracking / Status |
|---|---|---|---|---|---|
| Kostenkategorie | Art laufender Objektkosten | kontrolliertes Vokabular erforderlich | Finance/Actuals fehlt | manuell künftig | **BLOCKED** `VALUATION-OPEX-01` |
| Betrag je Kostenkategorie | jährlicher/periodischer Aufwand, € | ≥ 0; Periode/Währung zwingend | Finance/Actuals fehlt | manuell/importiert künftig | Source-ID/-Periode/Audit |
| Umlagefähigkeit | welcher Anteil nicht beim Eigentümer verbleibt, % | 0–100 % | Lease-/Finance-Regel fehlt | manuell künftig | Provenance/Audit |
| CapEx-Projekt | Maßnahme/Kategorie | Property-Zugehörigkeit | Cloud CapEx | übernommen | Project-ID/-Version |
| CapEx-Betrag | Budget, Forecast oder Actual, € | Prioritätsregel bewusst wählen; Währung vorhanden | Cloud CapEx | übernommener Source-Snapshot | Betragstyp, Projektversion |
| CapEx-Zeitpunkt | Cashflow-Periode | gültiger Start-/Endtermin; keine automatische Verteilung ohne Regel | Cloud CapEx | übernommen | Datum/Projektversion |
| Wiederkehrender CapEx/Reserve | periodischer Ersatzbedarf | Rhythmus und Betrag explizit | keine Cloud-Quelle | kein Default | **BLOCKED** `VALUATION-CAPEX-CF-01` |
| Eigenkapital | Investor-Einsatz, € | ≥ 0; Quellen-/Mittelverwendung muss aufgehen | kein Cloud-Finance-Contract | manuell künftig | **BLOCKED** `VALUATION-DEBT-01` |
| Darlehensbetrag | Nominal, € | > 0; Währung konsistent | kein Cloud-Finance-Contract | manuell künftig | Provenance/Audit |
| Zinssatz | nominaler/effektiver Satz, % p.a. | > -100 %; Typ eindeutig | kein Cloud-Finance-Contract | manuell künftig | Provenance/Audit |
| Laufzeit / Amortisation | Jahre/Monate | positive Ganzzahl; Amortisation ≥ Laufzeit nach Modellregel | kein Cloud-Finance-Contract | manuell künftig | Provenance/Audit |
| Tilgungsart | annuitätisch, endfällig oder freigegebener Typ | Contract-Enum erforderlich | kein Cloud-Finance-Contract | manuell künftig | Provenance/Audit |
| Gebühren | Finanzierungsgebühren, € oder % | Einheit und Zeitpunkt zwingend | kein Cloud-Finance-Contract | manuell künftig | Provenance/Audit |
| Start / Fälligkeit | Auszahlungs- und Rückzahlungstermin | chronologisch und innerhalb/erklärt außerhalb Halteperiode | kein Cloud-Finance-Contract | manuell künftig | Provenance/Audit |

Finanzierung wirkt künftig auf levered Cashflow und Equity-KPIs, **nicht** auf den unlevered Objektwert. Das Legacy-Modell mit einem einfachen Darlehen darf erst nach fachlichen Golden-Model-Tests als Portierungsbasis dienen.

### 8.6 Szenario- und Sensitivitätsinputs

In Phase A sind ausschließlich Variantengruppe, Variantenlabel und aktiver Varianten-Case verfügbar. Baseline, Deltas, Sensitivitätsachsen/-stützstellen und Ziel-KPI-Runs bleiben durch `SCENARIO-VALUATION-01` blockiert.

| Eingabe | Bedeutung | Validierung | Herkunft / Default | Tracking |
|---|---|---|---|---|
| Variantengruppe | zusammengehörige Cases | gleiche Property; serverseitig vorhanden | bei erster Variante serverseitig erzeugt | Group-ID/Audit |
| Variantenlabel | verständlicher Name | nicht leer, eindeutig im sichtbaren Vergleich | manuell | Case-Version/Audit |
| Baseline | Referenz für Deltas | genau ein lesbarer Case derselben Gruppe | keine stille Auswahl außer aktuellem Source-Case | Baseline-ID/-Version |
| Aktives Szenario | Case, dessen Werte und Ergebnisse angezeigt werden | lesbar, nicht archiviert für Bearbeitung | Nutzerwahl; URL-Zustand | Case-ID in URL/State |
| Sensitivitätsachse X/Y | zwei vorhandene Faktoren | numerisch, rechenwirksam, nicht identisch | kein Default | **BLOCKED** Scenario-Contract |
| Stützstellen | explizite Faktorwerte oder Deltas | sortiert, begrenzte Matrixgröße serverseitig festlegen | keine von ARGUS/Brixx kopierten Defaults | Definition + Ersteller + Zeit |
| Ziel-KPI | zu vergleichendes Ergebnis | durch vorhandene Engine lieferbar | Marktwert/Investment-KPI bewusst wählen | Definition + Engine-Version |

Die Legacy-Sensitivität besitzt getestete Fünf-Punkt-Presets für Kaufpreis und Miete. Sie ist nur ein technischer Kandidat, weil sie nicht auf den Cloud-Faktorkatalog und dessen Versionierung arbeitet.

## 9. Berechnung, Cashflow und Wirkungserklärung

### 9.1 Phase A

- Rechenkanon bleibt `ValuationCaseController` + vorhandene Domain Engines.
- Live-Berechnung nutzt die aktuelle Case-Version und rechenwirksame Faktoren.
- Ein vorhandener publizierter Report ist ein read-only Legacy-Ergebnisstand mit `computedFromVersion`; Phase A erzeugt keinen neuen Report.
- Stimmen Case-Version und Legacy-Report-Version nicht überein, erscheint „Legacy-Berechnung veraltet“; Publish/Review/Approval bleiben unabhängig davon gesperrt.
- Die Cashflow-Ansicht zeigt ausschließlich vorhandene DCF-Jahreswerte: Rohertrag, Leerstandsverlust, Effective Gross Income, Bewirtschaftungskosten und NOI sowie Forward NOI, Terminalwert, Verkaufskostenwirkung und Barwerte.
- Jede Methodenkarte nennt verwendete Annahmen, fehlende Faktoren, Formelbeschreibung aus der Engine, Konfidenz und Wert.
- Eine Änderung zeigt „wirkt auf“ anhand der deklarativen Methodenzuordnung des Faktorkatalogs. Ein numerischer Marginaleffekt wird nur gezeigt, wenn eine freigegebene Sensitivitätsberechnung ihn tatsächlich berechnet.

### 9.2 Engine-Gaps

| Gap | Ist | Benötigt |
|---|---|---|
| `VALUATION-VALIDATION-01` | Semantische Wertebereiche unvollständig; Direktkapitalisierung kann durch `0` teilen | Domain- und serverseitig identische Validation, Tests für Grenzen |
| `VALUATION-METHOD-CONTRACT-01` | Reconciliation gewichtet alle verfügbaren aktivierten Methoden in eine `MarketValueOpinion` | Kategorien/Wertbasen, Eligibility, getrennte Ergebnisfamilien, Approval Classes und Reconciliation gemäß beschlossenem `METHOD-GOV-01` |
| `VALUATION-MARKET-METHODS-01` | vereinfachte Ertrags-/Sachwertmodelle und Low-Confidence-Referenzdaten | Modellkonformität, Verfahrensvarianten, boG und belastbare versionierte Referenzdaten |
| `VALUATION-COMPS-01` | Comparison Engine vorhanden, Cloud-Port nicht gebunden | Cloud Comparable Read/Selection, Stichtag und Datenqualität |
| `VALUATION-LEASE-CF-01` | jährlicher Aggregate-Cashflow | kanonische periodische Lease-Events, MLA und Engine |
| `VALUATION-CAPEX-CF-01` | CapEx-Projekte separat | fachliche Auswahl Budget/Forecast/Actual, Periodisierung und DCF-Integration |
| `VALUATION-DEBT-01` | nur Legacy-Ein-Darlehen-Rechner | Cloud Debt Contract, Schedule, levered KPIs, Golden Models |
| `SCENARIO-VALUATION-01` | Case-Varianten, kein Matrix-Job/Contract | versionierter Scenario Run und Sensitivity Results |
| `VALUATION-ACTUALS-01` | keine Objekt-Actuals im Valuation Contract | Ist-/Plan-Zeitreihe mit Perioden-/Source-Version |

## 10. Data Mapping

| V2-Information | Aktuelle Quelle | Mapping | Lücke / Regel |
|---|---|---|---|
| Queue-Zeile | `ValuationCaseRepository.search` | Titel, Kind, Status, Updated, Version | Phase A kein Wert; künftige Ergebnisprojektion erst mit Kategorie/Wertbasis/Approval Class, kein N+1 |
| Case-Kopf | `ValuationCaseRepository.getById` | Case, Config, Property-ID, Status, Version | Property-Anzeige separat lesen |
| Property-Auswahl | Cloud `PropertyRepository` | Summary ID/Name/Adresse/Status | Create muss Legacy-Provider entfernen |
| Property-Fakten | Cloud Property Detail | Type, Units, Sqft, Baujahr | deutsche Flächen-/Grundstücks-/Kaufdaten fehlen/uneindeutig |
| Annahmen | `ValuationFactorPort` | Factor-ID, Wert, Provenance, Source, Note, Confidence, Version | Source-Snapshot-/Baseline-Metadaten erweitern |
| Live-Ergebnis | lokale Cloud Domain Engines | Method Results, Opinion, DCF Projection, KPIs | Engine-Version nicht explizit persistiert |
| Publiziertes Ergebnis | `ValuationReportPort` | Results/Opinion + `computedFromVersion` | nur „latest“, keine Report-History, Export oder Report-Version |
| Rent Roll | Cloud `RentRollPort.readLive` / Snapshots | Base Rent, Occupancy, Units, As-of | Import-Adapter und Case-Source-Snapshot fehlen |
| Leases | Cloud `LeaseSearchPort` / `LeaseRepository` | Termine, Base Rent, Charges, Free Rent, Optionen | kein Indexation-Cloud-Contract, keine Lease-DCF Engine |
| CapEx | Cloud `CapexProjectSearchPort` | Budget/Forecast/Actual, Termine, Status | keine Auswahl-/Periodisierungsregel für DCF |
| Finanzierung | Legacy Scenario/Analysis | vereinfachte Loan Inputs/Schedule | nicht Cloud; nicht direkt übernehmen |
| Varianten | `createValuationVariant` + Group Load | geklonte Config/Faktoren, kein Report, Draft | bis zu acht Detail-Reads clientseitig; Compare Projection fehlt |
| Versionen | Case `version`; Legacy Version Repository | Optimistic Concurrency vs SQLite Snapshots | Cloud-History/Diff fehlt |
| Audit | serverseitige `audit_events` der RPCs | Mutation/Transition bereits append-only | kein Valuation-Audit-Read-Port |
| Export | Legacy Report Builder | lokale CSV/PDF/JSON | kein Cloud-Valuation-Dokumentvertrag |

## 11. Permissions und Sicherheit

Die UI spricht über Fähigkeiten, nicht über hart codierte Rollennamen.

| Fähigkeit | Sicht-/Aktionsrecht |
|---|---|
| `valuation.read` | Queue, Case, Faktoren, aktuelle/publizierte Ergebnisse und Varianten lesen |
| `valuation.manage` | Phase A: Case erstellen, sichere Draft-Faktoren speichern, Variante erstellen und ggf. sicher archivieren; Ergebnis-Publish/Review erst nach Method Contract |
| `valuation.approve` | technische Permission; Phase A keine neue Ergebnisaktion, künftig nur zusammen mit erfüllter Approval Class/Professional Gate |
| `property.read` | Cloud-Property-Auswahl/-Details im Create und Source Panel |
| `lease.read` | Rent-/Lease-Quelle lesen; fehlt das Recht, bleibt der Case lesbar, Quelle erscheint „nicht zugänglich“ statt als `0` |
| `capex.read` | CapEx-Quelle lesen; gleiche Partial-Data-Regel |
| `audit.read` | künftige Valuation-Audit-Timeline lesen |
| `reporting.generate` | künftigen Bericht erzeugen/exportieren; bestehende Reports lesen bleibt `valuation.read` |

Regeln:

- Sidebar/Route folgt `cloudReadPermissionForPage`; direkter unberechtigter Aufruf zeigt `Forbidden`, nicht `Not found`.
- Erlernbare Aktionen bleiben sichtbar und disabled mit Grund; irrelevante Aktionen werden ausgeblendet.
- Server-RLS und RPC-Permission-Gates bleiben die Autorität. Client-Gating ersetzt sie nie.
- Keine Valuation-Aktion benötigt nach heutigem Contract AAL2. Eine spätere Signatur-/Gutachtenfunktion wäre separat zu entscheiden.
- Entfallen Rechte während der Sitzung, werden vertrauliche Inhalte verworfen und der Screen reconciled auf Forbidden/Partial Data.

## 12. Zustandsmodell

### 12.1 Case-Lifecycle

Der folgende Lifecycle ist das **Ziel nach `VALUATION-METHOD-CONTRACT-01`**. Phase A erlaubt für neue Cases keine ergebnisbezogenen Übergänge nach `in_review` oder `approved`; Existing Legacy States bleiben read-only.

| Von | Nach | Fähigkeit | Regel |
|---|---|---|---|
| Draft | In Review | `valuation.manage` | aktueller publizierter Report und Review-Checks erforderlich |
| Draft | Archived | `valuation.manage` | Grund/Bestätigung |
| In Review | Draft | `valuation.manage` | Rückgabegrund sichtbar und auditiert |
| In Review | Approved | `valuation.approve` | nur aktueller publizierter Stand; Approved danach immutable |
| In Review | Archived | `valuation.manage` | Grund/Bestätigung |
| Approved | Archived | `valuation.manage` | kein Edit; Freigabestand bleibt nachweisbar |
| Archived | – | – | terminal |

Der abweichende Legacy-Scenario-Lifecycle (`rejected` usw.) wird nicht in den Cloud-Case hineingemischt.

### 12.2 Screen-/Datenzustände

- Workspace/Auth wird noch aufgelöst.
- Initial Loading mit Struktur-Skeleton.
- Ready mit gespeicherten und Live-Daten.
- Background Refresh erhält Inhalt und markiert Aktualisierung.
- Partial Data: Quelle nicht verfügbar/nicht berechtigt/Mischwährung.
- Missing Assumptions: Methoden bleiben begründet nicht verfügbar.
- Suggested but unaccepted: sichtbar, nicht rechenwirksam.
- Unsaved Draft: lokale Eingaben klar markiert.
- Validation Error: feldnah, Fokus zum ersten Fehler.
- Version Conflict: Eingabe bleibt erhalten; Serverstand und lokale Änderung vergleichbar.
- Report Stale: Live und publiziert getrennt; Review/Approval gesperrt.
- Action In Progress: nur betroffene Aktion gesperrt.
- Approved Immutable / Archived Read-only.
- Realtime Degraded: `NxLiveUpdatesNotice`, REST bleibt kanonisch.
- Recoverable Error mit Retry; Not Found; Forbidden; Infrastructure Unavailable.

## 13. Realtime und Konsistenz

- Kanonisch ist immer der Repository-Read, nicht ein Realtime-Payload.
- Aktuell beobachtet der Valuation-Adapter nur `valuation_cases`-Updates. Faktor-/Report-Invalidierung ist unvollständig (`VALUATION-REALTIME-01`).
- Nach eigener Mutation erfolgt Readback/Reconcile; Realtime ist nur Invalidierung.
- Reconnect löst genau einen debounced Reconcile aus, keinen Reload-Burst.
- Bei `liveUpdatesDegraded` bleiben Lesen und Schreiben möglich, sofern REST funktioniert; ein persistenter Hinweis nennt den möglichen Aktualitätsnachteil.
- Variantengruppen dürfen nicht durch acht unkoordinierte Realtime-Reloads flackern.

## 14. Source Transparency, Audit und Versionen

Dieser Abschnitt beschreibt das Ziel nach den benannten Source-, Scenario-, Version- und Audit-Paketen. `VALUATION-REHOST-01C` zeigt nur vorhandene Factor-Provenance/Source/Note/Confidence, Case-/Variant-Information und read-only Legacy-Status-/Report-Metadaten; es baut keine Source-Snapshot-, Baseline-, Diff- oder Audit-Read-Architektur.

Jeder sichtbare Ergebnisstand muss beantworten:

- Welche Annahmen gelten?
- Welche davon sind manuell, importiert, abgeleitet oder nur vorgeschlagen?
- Aus welcher Entity-Version und welchem Stichtag stammt ein Wert?
- Was hat sich gegenüber Baseline und Approved geändert?
- Welche Methoden und Gewichte liefen?
- Auf welcher Case-Version beruht der publizierte Report?
- Wer änderte, publizierte, reichte ein oder genehmigte wann und warum?

### Zielmodell für Versionen

- `CaseVersion`: unveränderlicher Snapshot von Config, Faktoren, Source-Refs und Metadaten.
- `CalculationRun`: unveränderliches Engine-Ergebnis mit CaseVersion-ID, Engine-Version und Zeitpunkt.
- `Approval`: verweist exakt auf CaseVersion und CalculationRun.
- `ReportArtifact`: verweist exakt auf Approval oder Draft CalculationRun und enthält Exportformat/Hash.
- `AuditEvent`: Actor, Zeitpunkt, Aktion, Entity, Vorher/Nachher-Zusammenfassung, Mutation-/Correlation-ID und Grund; keine sensitiven Rohpayloads.

Bis diese Objekte als Cloud-Contract existieren, simuliert die UI keine Version History aus dem aktuellen `version`-Zähler.

## 15. Reporting

### Kuratierte V2-Berichte

1. **Bewertungsübersicht:** Objekt, Zweck, Stichtag, Status, Ergebnisfamilien und Konfidenz.
2. **Annahmen- und Quellenanhang:** jeder rechenwirksame Faktor mit Einheit, Herkunft, Stichtag und Abweichung zur Baseline.
3. **Cashflow-Bericht:** vorhandene jährliche DCF-Reihe und Terminalwert-Breakdown.
4. **Methodenbericht:** Ergebnis und Breakdown je freigegebener Methode; fehlende Methoden mit Grund.
5. **Szenariovergleich:** erst nach Scenario-Contract; Baseline und Deltas.
6. **Review-/Approval-Nachweis:** Version, publizierter Run, Akteur und Zeit.

Kein Bericht behauptet Gutachtenqualität, Rechtskonformität oder eine Methode, die NexImmo nicht berechnet. Phase A darf vorhandene Werte als Bildschirmansicht zeigen; Download/Export bleibt bis `VALUATION-REPORT-EXPORT-01` gesperrt.

## 16. Backend-Gaps

| ID | Exakter Bedarf | Domain / möglicher Contract | Schema/RLS/Permission |
|---|---|---|---|
| `SHELL-ROUTING-01` | adressierbarer Case und Section-URL-State | App Navigation | kein Domain-Schema; Permission-Gate beibehalten |
| `VALUATION-LIST-01` | optional Property-Label, Stale und Approval Class ohne N+1; kein Wert vor Method Contract | Valuation Search Projection | RPC/View und `valuation.read` |
| `VALUATION-SOURCE-01` | immutable Source-Refs/Snapshots je Faktor | Valuation Factor/Case Version | Schema, audited RPC, RLS |
| `VALUATION-VALIDATION-01` | semantische Factor-Regeln serverseitig | Valuation Factor RPC | kein neues Recht; Contract/Error-Felder |
| `VALUATION-METHOD-CONTRACT-01` | Kategorien, Wertbasis, Ergebnisbegriffe, Eligibility, getrennte Reconciliation und Approval Classes gemäß `METHOD-GOV-01` | Valuation Config/Engine/Report | neues oder migriertes Contract-/Schema-Modell; Permission allein ist kein Professional Gate |
| `VALUATION-MARKET-METHODS-01` | fachliche Ertrags-/Sachwert-Modellkonformität, boG und Referenzdaten | Valuation Methods/Reference Data | Source-/Engine-Versionierung |
| `VALUATION-COMPS-01` | Cloud Comparables lesen/selektieren | Comparable Repository | P2-D07 Rest, RLS |
| `VALUATION-LEASE-CF-01` | Lease-/MLA-Input und periodische Cashflows | neuer Valuation Cashflow Contract | Schema/RLS; `lease.read` + `valuation.manage` |
| `VALUATION-CAPEX-CF-01` | CapEx-Source Selection und Periodisierung | Valuation Cashflow + CapEx | Schema/RLS; `capex.read` |
| `VALUATION-DEBT-01` | Debt Instruments/Schedules und levered Results | Finance P2-D08 / Valuation | Schema/RLS; Rechte noch entscheiden |
| `SCENARIO-VALUATION-01` | Baseline, versionierter Compare/Matrix Run | Valuation Scenario Contract | Schema/RLS; `valuation.manage` |
| `VALUATION-VERSION-01` | Snapshot/History/Diff/Revision | Valuation Version Repository | Schema, RLS, Audit |
| `VALUATION-AUDIT-READ-01` | Case-gefilterte Audit-Query | Audit Repository | `audit.read`, payload redaction |
| `VALUATION-REPORT-EXPORT-01` | server-/serviceerzeugtes Artifact mit Hash | Reporting/Document | Storage/RLS, `reporting.generate` |
| `VALUATION-REALTIME-01` | Invalidierung für Faktoren, Reports, Varianten | Query Invalidation | Publication/Events, keine Payload-Autorität |
| `VALUATION-CURRENCY-01` | definierte Case-Währung und FX-Policy | Valuation Config | Schema/Referenzdaten/RLS |

## 17. Implementierungspakete

Der [Product Restore Tracker](../PRODUCT_RESTORE_TRACKER.md) ist das alleinige Package-Inventar. Diese Sequenz verwendet ausschließlich dort geführte kanonische IDs; frühere lokale P-Aliase werden nicht weiter verwendet.

| Paket | Umfang | Typ | Voraussetzung | Status |
|---|---|---|---|---|
| `VALUATION-REHOST-01A` | Queue öffnen und Route Host | Rehost | `SHELL-ROUTING-01` | **APPROVED / REHOST NOW** |
| `VALUATION-REHOST-01B` | Create mit Cloud-Property-Read und Case-Navigation | Rehost/Fix | 01A | **APPROVED / REHOST NOW** |
| `VALUATION-REHOST-01C` | Allowlist-Case, Factors/Provenance, Varianten, technische Einzelmodelle, aggregate DCF/KPIs | Rehost | 01A | **APPROVED / REHOST NOW** |
| `METHOD-GOV-01` | verbindliche Fachentscheidung | Planning/Governance | Primärquellen und Repository-Audit | **APPROVED** |
| `VALUATION-METHOD-CONTRACT-01` | Value Basis, Ergebnisfamilien, Reconciliation und Approval Classes | Domain/Backend | Method Governance | **BLOCKED** |
| `VALUATION-SOURCE-01` | Source Snapshots und Source-vs-Case-Import | Backend + UI | Version Contract | **DRAFT/BLOCKED** |
| `SCENARIO-VALUATION-01` | Baseline, Deltas und Sensitivität | Backend + Engine + UI | Scenario Contract | **BLOCKED** |
| `VALUATION-VERSION-01` / `VALUATION-AUDIT-READ-01` | immutable History/Diff und Audit Timeline | Backend + UI | jeweilige Contracts | **BLOCKED** |
| `VALUATION-REPORT-EXPORT-01` | klassifizierte Report-/Export-Artefakte | Backend + UI | Method-/Version-Contract | **BLOCKED** |
| `VALUATION-LEASE-CF-01` / `VALUATION-CAPEX-CF-01` / `VALUATION-DEBT-01` | fortgeschrittene periodische Cashflows | neue Contracts/Engines | Cashflow-/Finance-Zielmodell | **FUTURE / BLOCKED** |

### Parallelisierbare Teile

- Nach Festlegung des Route Contracts können Queue/Create und Case-Core parallel arbeiten.
- Cashflow-Visualisierung kann parallel zur geführten Faktoren-UX entstehen, weil beide nur vorhandene Read-Models verwenden.
- Method-Governance/Validation, Source Contract und Version/Audit Contract können fachlich/backendseitig parallel spezifiziert werden.
- Reporting kann UI-seitig erst nach stabilem Calculation-/Version-Contract fertiggestellt werden.
- Lease-, CapEx- und Debt-Modellierung können nach einem gemeinsamen periodischen Cashflow-Event-Schema parallel entwickelt werden; vor diesem Schema würden sie inkompatible Mathematik erzeugen.

## 18. Gemeinsame Acceptance Criteria

- Given ein Nutzer mit `valuation.read`, when er einen Case-Link öffnet, then landet er nach Reload im selben Case und selben Bereich.
- Given ein Nutzer ohne `valuation.read`, when er Queue oder Case direkt öffnet, then sieht er Forbidden und keine Case-Daten.
- Given ein vorgeschlagener Wert, when er nicht akzeptiert wurde, then beeinflusst er keine Methode.
- Given eine Phase-A-Annahme, then sind die heute vorhandenen Werte für Einheit, Provenance/Source, Note und Confidence sichtbar; strukturierter Source-Stichtag und Baseline-Delta sind keine Rehost-Anforderung.
- Given eine ungültige Eingabe, when gespeichert wird, then stoppt die UI feldnah und der Server weist denselben ungültigen Zustand zurück.
- Given fehlende Faktoren, then zeigt die Methode „nicht ermittelbar“ mit Gründen und niemals einen erfundenen Wert.
- Given die aktuelle Case-Version unterscheidet sich von einem Legacy-`computedFromVersion`, then sind Legacy- und Live-Stand unterscheidbar; neue Ergebnisaktionen bleiben generell gesperrt.
- Given ein approved Case, when ein Nutzer mit Manage-Recht eine Eingabe ändern will, then wird keine In-place-Mutation angeboten.
- Given ein blockierter Section-Key `review`, `versions` oder `reporting`, then normalisiert Phase A sicher auf `overview` und rendert keine blockierte Fläche.
- Given Source-/Baseline-Funktionen werden künftig aktiviert, then gelten die Source-/Delta-Kriterien erst nach ihren Tracker-Paketen; Phase A simuliert sie nicht.
- Given Realtime ist degraded, then bleibt REST kanonisch und ein Reconnect erzeugt genau einen Reconcile.
- No existing calculation engine is replaced by inline UI arithmetic.

## 19. Staging E2E — Gesamtworkflow

1. Analyst mit `valuation.read/manage` öffnet `/valuations`; Queue lädt per Cloud-Contract.
2. Analyst erstellt über `/valuations/new` einen Holding-Case für ein Cloud-Property; kein Legacy-Provider wird gelesen.
3. Create-Erfolg öffnet `/valuations/{id}`; Reload erhält Case und Section.
4. Nicht akzeptierte Vorschläge bleiben aus der Berechnung ausgeschlossen.
5. Analyst speichert gültige Faktoren; Server-Audit, Version und Readback sind sichtbar konsistent.
6. Eine zweite Sitzung ändert denselben Case; erste Sitzung erhält Version Conflict und verliert ihre Eingabe nicht.
7. DCF-Cashflow stimmt zeilenweise mit dem vorhandenen Domain-Engine-Testmodell überein.
8. Eine fehlende DCF-Terminalannahme zeigt `nicht ermittelbar`; kein Fake-Amount wird ausgegeben.
9. Analyst erstellt eine Variante; Config/Faktoren sind geklont, Report nicht, Status Draft.
10. Publish, Submit und Approval sind für den neuen Case nicht verfügbar; kein gemischtes `MarketValueOpinion` wird erzeugt.
11. Ein bestehender publizierter Altstand wird read-only als nicht klassifizierter Legacy-Ergebnisstand gezeigt.
12. Archived-/Approved-Deep-Link bleibt lesbar für berechtigte Nutzer, ohne professionelle Marktwertaussage.
13. Deep Links mit `section=review`, `section=versions`, `section=reporting` oder unbekanntem Wert landen auf `overview` und exponieren keine Folgepaket-UI.
14. Realtime-Verbindung wird getrennt; Degraded Notice erscheint, REST-Aktionen funktionieren, Reconnect reconciled einmal.

Zusätzliche E2Es für Version, Audit, Scenario Matrix, Export und Advanced Cashflow werden erst aktiviert, wenn die benannten Contracts auf `main` gelandet sind.

## 20. Out of Scope

- vollständiger ARGUS-Enterprise-Funktionsumfang;
- proprietäre Referenz-UI, Branding, Assets oder exakte Screens;
- Steuerberechnung oder Rechts-/Gutachtenzusage;
- Portfolio-Aggregation, Deal Pipeline und Dokumenten-Datenraum;
- Multi-Currency-/FX-Berechnung ohne freigegebene Policy;
- neue Lease-, CapEx-, Debt-, Yield- oder Sensitivitätsformeln in einem Screen-Paket;
- Reaktivierung der Legacy-SQLite-Screens als Cloud-Produkt.

## 21. Offene Entscheidungen

1. Welcher Source-Stichtag wird beim Case Create eingefroren?
2. Darf `grossRentAnnual` aus Base Rent oder aus Total Rent inklusive Charges abgeleitet werden? V2 empfiehlt Base Rent, Entscheidung fachlich bestätigen.
3. Wie wird Leerstand definiert: nach Einheiten, Fläche, Marktmiete oder Mietausfall?
4. Welche Case-Währung und FX-Regel gilt?
5. Welche Rollen/Fähigkeiten dürfen Report-Artefakte erzeugen und Audit-Timeline lesen?
6. Welche Revision-Semantik gilt nach Approval: neuer Case, Child-Version oder beides?

Methodenkategorien, Ergebnisbegriffe, Reconciliation und Professional Gate sind durch [METHOD-GOV-01](../VALUATION_METHOD_GOVERNANCE.md) geschlossen. Offen ist nur ihre technische Contract-Umsetzung.

Diese Entscheidungen blockieren nicht den Rehost, aber die jeweils markierten professionellen Ausbaupakete.
