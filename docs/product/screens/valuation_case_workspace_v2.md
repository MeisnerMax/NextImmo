# Valuation Case Workspace V2

## Metadata

- Screen-ID (kein Arbeitspaket): `VALUATION-V2-CASE-01`
- Implementierungspaket: `VALUATION-REHOST-01C`
- Domain: Valuation; read-only Property-/Leasing-/CapEx-Source-Panels sind ausschließlich DRAFT-Zielbild nach `VALUATION-SOURCE-01`
- Route: `/valuations/:valuationCaseId?section=<section>`
- Current implementation files:
  - `lib/ui/screens/property_detail/widgets/valuation/valuation_section_host.dart`
  - `lib/ui/screens/property_detail/widgets/valuation/valuation_section.dart`
  - `lib/ui/screens/property_detail/widgets/valuation/valuation_factors_section.dart`
  - `lib/ui/screens/property_detail/widgets/valuation/valuation_factor_row.dart`
  - `lib/ui/screens/property_detail/widgets/valuation/valuation_workflow_stepper.dart`
  - `lib/ui/screens/property_detail/widgets/valuation/valuation_variant_bar.dart`
  - `lib/features/valuation/application/valuation_case_controller.dart`
- Legacy references inspected, not to be rehosted wholesale:
  - `lib/ui/screens/property_detail/analysis_screen.dart`
  - `lib/ui/screens/property_detail/inputs_screen.dart`
  - `lib/ui/screens/property_detail/scenarios_screen.dart`
  - `lib/ui/screens/property_detail/scenario_versions_screen.dart`
- Planning status:
  - **APPROVED / REHOST NOW:** eigenständiger Case-Rehost, vorhandene Faktoren, technische Ertrags-/Sachwert-Modellrechnungen, aggregate DCF-Cashflow-Darstellung und Varianten
  - **DRAFT:** geführte Source-/Baseline-Darstellung
  - **BLOCKED:** gemischte Opinion, Direct Capitalization bis Validation, Publish/Review/Approval, indikative/professionelle Marktwertfreigabe, Lease/CapEx/Debt-Cashflow, Sensitivität, Version History, Audit Read und Export
- Publish-Prüfung: 2026-09-02 auf `origin/main` = `2818ecb1191c837202bd4b57fd019ba12208308d`
- Dependencies: [Method Governance](../VALUATION_METHOD_GOVERNANCE.md), [gemeinsamer Workflow](valuation_v2_workflow.md), Foundation-Decision `PRODUCT-UX-FOUNDATION-01` (kein Arbeitspaket), `SHELL-ROUTING-01`
- Related screens: [Valuation Queue V2](valuation_queue_v2.md), [Create Valuation V2](valuation_create_v2.md)

## 1. Purpose

Der Workspace ist der Arbeitsraum eines einzelnen Valuation Cases. Phase A führt von Annahmen zu nachvollziehbaren internen Analyseergebnissen; ein fachlicher Review-/Freigabestand folgt erst mit `VALUATION-METHOD-CONTRACT-01`.

Der Workspace muss jederzeit sichtbar machen:

- welches Property, welcher Case, welche Case-Version und welche vorhandene Variante aktiv sind;
- welche Annahmen gelten, welche fehlen und woher jeder Wert stammt;
- nach den Folgepaketen: was gegenüber Baseline und Approved geändert wurde; Phase A baut keinen Baseline-/Model-Diff;
- welche Methoden verfügbar sind und welcher Faktor auf welche Methode wirkt;
- ob der sichtbare Wert live, publiziert, veraltet oder freigegeben ist;
- bei Altbestand: welcher technische Legacy-Status/-Reportstand read-only vorliegt, ohne neue Genehmigungsfläche oder professionelle Aussage.

Die ca. 2.000 LOC große cloud-contract-basierte UI wird aus dem toten Legacy-Analysis-Screen herausgelöst. Ihre funktionierende Mathematik und ihre Contract-Grenzen bleiben erhalten.

## 2. Primary users and jobs

| Fähigkeit / Nutzer | Job | Zuerst benötigte Information | Zentrale Aktionen |
|---|---|---|---|
| Analyst, `valuation.manage` | Annahmen vervollständigen und interne Analyse rechnen | Status, Vollständigkeit, aktive Variante | Faktoren speichern, technische Ergebnisse prüfen |
| Investment Manager | Cashflow, Rendite und Variantenwirkung verstehen | sichere KPI Summary, DCF/NOI, aktive Variante | Variante wählen/erstellen, deren interne Ergebnisse prüfen; kein Phase-A-Baseline-Diff |
| Valuer | technische Methoden und vorhandene Herkunft fachlich prüfen | Methode, Inputs und Factor-Provenance | Annahmen prüfen, technisches Methodenergebnis erklären; Comparables erst nach `VALUATION-COMPS-01` |
| Approver, `valuation.approve` | bestehende Legacy-Stände lesen; künftig klassifizierten Stand genehmigen | Phase A: technischer Legacy-Status/Stale; Approval Class und Review-Checks erst nach Method Contract | in Phase A keine neue Ergebnisfreigabe |
| Reader/Auditor | vorhandenen Legacy-Stand nachvollziehen | technischer Status, Case-Version und Legacy-Report-Metadaten | read-only lesen; vergleichen/exportieren/auditieren erst nach Folgepaketen |

## 3. Entry points and navigation

- Queue-Zeile und Create-Erfolg öffnen den Case-Deep-Link.
- `valuationCaseId` ist die kanonische Auswahl; der Workspace hängt nicht von einem zuvor ausgewählten Scenario im Legacy-Screen ab.
- Phase-A-Allowlist für `section`: exakt `overview`, `assumptions`, `cashflow`, `valuation`, `scenarios`.
- `scenarios` umfasst in Phase A ausschließlich vorhandene Varianten und Variant-Wechsel.
- Fehlende, unbekannte oder blockierte Werte – insbesondere `review`, `versions`, `reporting` – werden kanonisch auf `overview` normalisiert und dürfen keine Legacy-/Folgepaket-Oberfläche öffnen.
- Ein Variantenwechsel navigiert zum Case-ID-Link der Variante und erhält den Bereich.
- Breadcrumb/Back: „Bewertungen“ → Queue. Filterzustand wird von der Queue wiederhergestellt.
- Property-Name öffnet optional den Property Workspace in neuem Shell-State, sofern `property.read`.
- Deep Link muss nach Reload, Workspace-Wechsel und Permission-Reconcile deterministisch sein.

## 4. Information architecture

### 4.1 Persistenter Case-Kopf

1. Breadcrumb und Case-Titel.
2. Property-Name/Adresse und Case-Art.
3. Status, Case-Version und aktive Variante.
4. Standindikatoren: „Live“, „Publiziert aus Version n“, „Veraltet“ sowie technischer Legacy-Status „Approved“ read-only.
5. Phase-A-Primäraktion: Faktoren speichern. Publish, Review und Approval werden nicht gerendert.
6. Phase-A-Secondary-Aktionen: Variante erstellen sowie Archivieren nur bei sicherem bestehendem Command. Return-to-Draft und Export gehören nicht in `VALUATION-REHOST-01C`.

### 4.2 Phase-A-Bereiche (`VALUATION-REHOST-01C`)

1. **Überblick (`overview`):** sichere KPI Summary, Methodenstatus, Vollständigkeit, Legacy-Stale-Hinweis und nächste zulässige Aktion.
2. **Annahmen (`assumptions`):** vorhandene Factor-Eingabe, Provenance/Source/Note/Confidence und `suggestedDefault/accepted/manual`-Semantik; keine neue Source-/Baseline-Architektur.
3. **Cashflow:** vorhandene jährliche DCF-Reihe und Terminal Breakdown.
4. **Bewertung:** getrennte technische Market-Valuation-Modellrechnungen und Investment Analysis; keine Reconciliation.
5. **Varianten (`scenarios`):** vorhandene Variantengruppe sowie Create/Switch; keine Baseline, Deltas, Model Comparison oder Sensitivität.

### 4.3 Future / Blocked target IA

- **Review (`review`):** erst nach `VALUATION-METHOD-CONTRACT-01`; keine Phase-A-Section oder Review-Fläche.
- **Versionen & Freigabe (`versions`):** erst nach `VALUATION-VERSION-01` und Method Contract; Phase A zeigt nur Case-Version und vorhandenen Legacy-Status im Kopf/Overview.
- **Bericht & Audit (`reporting`):** erst nach `VALUATION-REPORT-EXPORT-01` und `VALUATION-AUDIT-READ-01`; Phase A erzeugt keine Section, Export- oder Audit-Fläche.

### 4.4 Annahmengruppen

Phase A gruppiert ausschließlich die heute im `ValuationFactorCatalog` vorhandenen und für die freigegebenen technischen Ertrags-/Sachwertmodelle beziehungsweise aggregate DCF benötigten Faktoren. Sie baut keine neue Datenquellen-, Lease-, Operating-, CapEx- oder Finanzierungsgruppe.

Die folgende geführte Reihenfolge ist **Future / Blocked target IA** nach den jeweiligen Source-/Cashflow-Paketen:

1. Objekt und Datenquellen.
2. Miete / Leases.
3. Operating Assumptions.
4. Markt- und Bewertungsannahmen.
5. CapEx.
6. Finanzierung.
7. Methoden- und Exit-Konfiguration.

Lease-/CapEx-/Debt-/Operating-Source-Panels und neue Read Models gehören nicht zu `VALUATION-REHOST-01C`; diese Zielgruppen werden weder als Tabs noch als Attrappenfelder gerendert.

## 5. Layout and interaction model

### Desktop ≥ 1200 px

- `NxContentFrame` + `NxPageHeader`.
- Unter dem Header horizontale Section Tabs, bei Platzmangel „Mehr“-Menü.
- In Arbeitsbereichen ein 3:2-Split:
  - links Eingaben/Hauptinhalt;
  - rechts sticky „Aktiver Stand“ mit sicheren KPIs, Vollständigkeit und vorhandener Methoden-/Faktorwirkung; keine Baseline-Deltas.
- Cashflow und Variantenübersicht dürfen die volle Breite nutzen.
- Details zu Annahme/Methode öffnen einen kontextuellen Side Panel, nicht einen verschachtelten Modal-Stack.

### Tablet 768–1199 px

- Section Tabs horizontal scrollbar oder Dropdown, semantisch weiterhin Navigation.
- Summary Panel steht oberhalb des Hauptinhalts, nicht als zu schmale zweite Spalte.
- Tabellen reduzieren Spalten und bieten Zeilendetails.

### Mobile ≤ 767 px

- Case-Kopf kompakt; Section Picker statt fünf gequetschter Tabs.
- Hauptinhalt einspaltig.
- Annahmegruppen als Cards/Accordion, aber Fehler- und Vollständigkeitsstatus bleiben sichtbar.
- Cashflow als scrollbare semantische Tabelle plus KPI Cards; Chart ist Ergänzung, nie einzige Darstellung.
- „Zur Queue“ als eindeutiger Back-Pfad.

### Auswahl- und Save-Modell

- Faktorentwürfe bleiben lokal, bis „Änderungen speichern“ ausgelöst wird; kein Save pro Tastenanschlag.
- Dirty-Anzeige auf Bereich und Feldern.
- Navigation zu anderem Bereich/Case mit Dirty State fordert Speichern, Verwerfen oder Bleiben.
- Version Conflict behält lokale Werte und öffnet einen Feldvergleich.
- Variante und erlaubte Section sind URL-/Case-State, kein versteckter Legacy-Provider-State. Eine aktive Baseline existiert erst nach `SCENARIO-VALUATION-01`.

## 6. Functional requirements

### 6.1 Überblick

- Zeigt Case/Property/Status/Version und die Herkunft des sichtbaren Berechnungsstands.
- KPI Summary Phase A:
  - getrennte Methodenwerte;
  - keine aktuelle gemischte Opinion oder `MarketValueCard`;
  - `Aggregate DCF Value (unlevered, indikativ)`, `NOI (Forecast, vor CapEx und Finanzierung)`, optional `IRR (unlevered, vor Steuern, jährlich)`/NPV/Equity Multiple aus vorhandener Engine;
  - Vollständigkeit je aktivierter Methode;
  - Report aktuell/veraltet.
- Jede KPI öffnet den erklärenden Bereich/Methode.
- Keine KPI wird als `0` gezeigt, wenn sie nicht berechenbar ist.

### 6.2 Annahmen bearbeiten

- Trigger: Feld ändern und gruppenweises/batchweises Speichern.
- Voraussetzung: `valuation.manage`, Case `draft`, rechenwirksame Value/Provenance-Kombination.
- Controls, Einheiten und Alternativanforderungen kommen aus `ValuationFactorCatalog`.
- UI validiert Format und fachliche Grenzen aus der Workflow-Spec; Server muss sie über `VALUATION-VALIDATION-01` spiegeln.
- Alternative Inputs werden erklärt:
  - Bodenwert direkt **oder** Fläche × Bodenrichtwert;
  - Restnutzungsdauer direkt **oder** Gesamtnutzungsdauer − Gebäudealter;
  - DCF Terminal Exit Cap **oder** Gordon Growth.
- Direct-Capitalization-spezifische Eingabeflächen bleiben bis `VALUATION-VALIDATION-01` ausgeblendet.
- Bestehende Draft-Werte dürfen beim Rebuild nicht verloren gehen.
- Ungültiges Parsing darf nicht wie heute still übersprungen werden; es erzeugt Feldfehler.
- Speichern nutzt Batch Upsert/Remove + Expected Version.
- Erfolg: kanonischer Readback, neue Case-Version, Live-Berechnung, Report wird stale.
- Failure: lokale Eingabe erhalten; Fehler feld-/formnah.

### 6.3 Vorschlag akzeptieren / Source übernehmen

- Phase A: vorhandenen `suggestedDefault` explizit akzeptieren; erst dann rechenwirksam.
- Vorhandene Factor-Provenance, Source-Text, Note und Confidence werden ohne Contract-Erweiterung angezeigt.
- **DRAFT/BLOCKED durch `VALUATION-SOURCE-01`:** Source Value vs. Case Value, strukturierter Source-Snapshot, „Übernehmen/Aktualisieren“ und Source-Deltas. Diese Punkte sind keine Implementierungsanforderung von `VALUATION-REHOST-01C`.

### 6.4 Case Config ändern

- Methoden, Gewichte, Terminalmodus und Mindest-Comparables sind im heutigen Repository updatefähig, aber die Methoden/Gewichte bilden eine fachlich blockierte Legacy-Konfiguration.
- Phase A darf nur den für die sichere aggregate DCF benötigten Terminalmodus und sonstige freigegebene Config read-only erklären. Legacy-Methodengewichte, Mixed-Opinion-Konfiguration und Comparables-Schwelle werden nicht gerendert.
- Editierbare Methoden-/Gewichte-Konfiguration landet erst mit `VALUATION-METHOD-CONTRACT-01`.
- Änderung nur Draft + `valuation.manage`, Expected Version, Audit; Report wird stale.

### 6.5 Cashflow prüfen

- Phase A rendert exakt die `DcfValuation.years` der vorhandenen Engine.
- Tabelle je Jahr: Rohertrag, Leerstandsverlust, Effective Gross Income, Bewirtschaftungskosten, NOI.
- Terminal Summary: Forward NOI, Terminal Value, Verkaufskostenwirkung/Net Terminal Value, PV laufender NOI, PV Terminal, Asset Value.
- Chart optional: gestapelte Ertrag/Kosten/NOI-Darstellung; zugängliche Tabelle bleibt vollständig.
- Umschalter „Nominal / Barwert“ nur, wenn beide Reihen aus Engine/Read Model geliefert werden; UI berechnet keine neue Reihe.
- Ohne DCF/fehlende Faktoren: Missing-State mit direkten Links zu fehlenden Annahmen.
- Lease, CapEx und Debt zeigen in Phase A eine klare „noch nicht in diesem Cashflow enthalten“-Notice.

### 6.6 Bewertungsmethoden prüfen

- Eine Karte pro in Phase A freigegebener Methode: technische Ertragswert-Modellrechnung, technische Sachwert-Modellrechnung und aggregate DCF. Template-aktivierte, aber blockierte Methoden erzeugen keine Karte.
- Karte zeigt verfügbar/nicht verfügbar, Wert, Konfidenz, verwendete Annahmen, Breakdown/Formeltext und Missing Factors.
- Ertrags- und Sachwert stehen unter „Market Valuation – technische Modellrechnungen“; sie heißen nicht Marktwertindikation. Vergleichswert bleibt blockiert.
- DCF steht unter „Investment Analysis“. Direct Capitalization bleibt bis `VALUATION-VALIDATION-01` ausgeblendet.
- Die aktuelle gemischte Opinion wird nicht gerendert, publiziert, freigegeben oder exportiert. Bei bestehenden Approved Cases ist sie nur dann sichtbar, wenn der Read Contract sie für den Altbestand zwingend mitliefert, und dann read-only als „nicht klassifizierter Legacy-Ergebnisstand“.
- Vergleichswert/Comparables werden in Phase A nicht als Karte oder navigierbare Unterfläche exponiert; sie folgen erst mit `VALUATION-COMPS-01`.

### 6.7 Variante erstellen und wechseln

- Trigger: „Variante erstellen“.
- Voraussetzung: `valuation.manage`, lesbarer Source Case, serverseitig erlaubter Status.
- Dialog: Variantenlabel, optionaler Grund. Keine mathematische Annahme im Dialog.
- Erfolg: Server klont Config/Faktoren, nicht Report; neuer Case ist Draft und wird geöffnet.
- Variantengruppe zeigt maximal die vorhandenen Contract-/UI-Grenzen; aktuell bis acht Detail-Fan-outs beachten.
- Karten zeigen Label, Status, Version und gegebenenfalls den vorhandenen Stale-Hinweis. Ein aus der gemischten Legacy-Opinion stammender Variantenwert wird nicht als reguläres KPI angezeigt.
- Detailvergleich/Deltas bleiben bis `SCENARIO-VALUATION-01` blockiert.

### 6.8 Sensitivitätsanalyse

- Ziel: zwei explizit gewählte vorhandene Faktoren gegen einen Engine-KPI als Matrix.
- Keine Phase-A-Aktion und kein lokal berechnetes Grid.
- Erst nach versioniertem Scenario/Sensitivity Contract:
  - X/Y-Achsen und Stützstellen bewusst wählen;
  - Baseline-Zelle markieren;
  - Zelle zeigt KPI und Delta;
  - Klick öffnet die verwendeten Faktorwerte/Calculation Run;
  - Jobs können `in progress/failed/completed` sein.
- Legacy Kaufpreis×Miete-Presets werden nicht automatisch übernommen.

### 6.9 Berechnung publizieren

- **BLOCKED** in Phase A. Der heutige Command persistiert zwingend eine gemischte `MarketValueOpinion`.
- Publish wird erst mit `VALUATION-METHOD-CONTRACT-01` wieder spezifiziert: getrennte Ergebnisfamilie, Value Basis, Scope, Engine-/Source-Version und Approval Class sind Pflicht.
- Bestehende publizierte Reports bleiben für berechtigte Nutzer read-only und werden als Legacy-Ergebnisstand gekennzeichnet.

### 6.10 Review / Approval

- Neue Phase-A-Cases bieten keine Submit-/Approve-Aktion. `valuation.approve` ist nur eine technische Permission und keine professionelle Qualifikation.
- `VALUATION-METHOD-CONTRACT-01` muss vor der UI-Implementierung Analysis, Indicative Valuation und Professional Market Valuation als getrennte Approval Classes tragen.
- Bestehende Approved/Archived Cases sind read-only; ihr Status wird nicht als professionelle Marktwertfreigabe erklärt.
- Archive bleibt nur zulässig, wenn es ohne Report-/Opinion-Neuberechnung über den bestehenden Contract sicher ausgeführt werden kann.

### 6.11 Versionen vergleichen

- Phase A zeigt nur aktuelle technische Case-Version und publizierte Report-Version; es nennt dies **nicht** Version History.
- Ziel nach `VALUATION-VERSION-01`:
  - chronologische immutable Snapshots;
  - Approved-/Baseline-Markierung;
  - Vergleich von Config, Faktoren, Quellen und Ergebnissen;
  - Feld-Deltas mit Einheit und Herkunft;
  - „Revision erstellen“ statt Approved mutieren;
  - kein direktes Legacy-Rollback auf einen Cloud-Case ohne neuen auditierten Command.

### 6.12 Reporting / Export / Audit

- Phase A zeigt einen vorhandenen publizierten Report ausschließlich als read-only Legacy-Ergebnisstand; neue Reports werden nicht erzeugt.
- Ziel nach Gaps: kuratierter Bewertungs-, Annahmen-, Cashflow-, Methoden- und Approval-Bericht aus der Workflow-Spec.
- Export braucht `reporting.generate`; Report lesen braucht `valuation.read`.
- Artefakt enthält Case-ID, CaseVersion-ID, CalculationRun-ID, Engine-/Template-Version, Stichtag, Status und Hash.
- Audit Timeline braucht `audit.read`; sie zeigt Who/When/What/Reason und redigiert sensitive Rohpayloads.

## 7. Data requirements

Die vollständige Bedeutung, Einheit, Validation, Herkunft, Default-, Import- und Trackingregel **jedes Inputs** steht normativ in den Abschnitten 8.2–8.6 der [Workflow-Spec](valuation_v2_workflow.md). Dieser Screen darf davon nicht abweichen.

### 7.1 Case Header

| Wert | Quelle | Pflicht | Editierbar | Format / Beziehung |
|---|---|---:|---:|---|
| Case-ID | `ValuationCase.id` | ja | nein | Deep Link, Copy-ID sekundär |
| Titel | Case | ja | Draft später | Klartext |
| Property-ID | Case | ja | nein | Property Lookup |
| Property-Name/Adresse | Cloud Property | Anzeige ja | nein | Partial State bei fehlendem `property.read` |
| Case-Art | Case | ja | nein nach Create | deutsches Label |
| Status | Case | ja | nur Transition | Badge + Text |
| Version | Case | ja | servergeneriert | Ganzzahl |
| Variante/Gruppe | Case | optional | Servercommand | Label + Case-ID |
| Created/Updated | Case | ja | nein | lokalisierte Zeit |

### 7.2 Factors

| Wert | Quelle | Pflicht | Editierbar | Regel |
|---|---|---:|---:|---|
| Factor-ID/Label | `ValuationFactorCatalog` + Factor | ja | nein | stabiler Domain-Key |
| Value | Factor | nach Methode | Draft + manage | Einheit aus Catalog |
| Provenance | Factor | ja für rechenwirksam | durch bewusste Aktion | `userProvided/derived/suggestedDefault/accepted/missing` |
| Source | Factor | optional heute, Ziel Pflicht für Import | nicht frei überschreiben | menschenlesbar + strukturierte SourceRef künftig |
| Note/Reason | Factor | optional; bei Adjustment/Rückgabe fachlich erforderlich | Draft | keine Secrets |
| Confidence | Factor | optional | Draft/Derived | Contract-Enum |
| Factor Version | Factor | ja | servergeneriert | Concurrency/Audit |

### 7.3 Results

| Wert | Quelle | Format | Aktualität |
|---|---|---|---|
| Method Result | Domain Engine / published Report | € + Confidence + Breakdown | live oder `computedFromVersion` |
| Missing Factors | Engine | Liste mit Links | live |
| Legacy Opinion | vorhandener Report | nur als „nicht klassifizierter Legacy-Ergebnisstand“, falls für Altbestand zwingend sichtbar | read-only; nie aktuelles KPI oder Reconciliation-Input |
| DCF Years | `DcfValuation` | jährliche €-Reihe | live/published abhängig Read Model |
| Investment Metrics | Engine | %, €, Multiplikator | unlevered klar kennzeichnen |
| Report metadata | Report Port | Zeitpunkt, Case-Version | stored latest only |

### 7.4 Source data

Die folgende Tabelle ist Ziel-/Gap-Dokumentation. `VALUATION-REHOST-01C` baut daraus keine Source Panels, Snapshots oder Source-vs-Case-Comparison; Phase A verwendet nur bereits am Factor vorhandene Provenance-/Source-Felder.

| Source | Aktueller Contract | Verwendbare Felder | V2-Regel |
|---|---|---|---|
| Property | Property Repository | Name, Adresse, Type, Units, Sqft, Baujahr | Kontext; Faktorimport erst nach Mapping/Source Snapshot |
| Live Rent Roll | RentRoll Port | Base/Ancillary/Parking/Total monthly, Occupancy, As-of, Currencies | Base Rent annualized nur als bewusst akzeptierter Vorschlag |
| Rent Roll Snapshot | RentRoll Port | immutable Header/Lines, Generated/As-of | bevorzugte auditierbare Source, wenn fachlicher Stichtag passt |
| Lease | Lease Repository | Dates, Base Rent, Charges, Free Rent, Options | read-only Quelle; keine Lease-DCF |
| Unit | Unit Repository | Area, Target/Market Rent, Status | Vorschlags-/Drilldown-Quelle |
| CapEx Project | CapEx Repository | Budget/Forecast/Actual, Dates, Status | read-only; nicht in DCF bis Engine-Gap |

## 8. Permissions and security behavior

### 8.1 Matrix

| Funktion | Permission | Zusätzlich |
|---|---|---|
| Case lesen | `valuation.read` | Workspace/RLS |
| Factors/Config speichern | `valuation.manage` | Draft, expected version |
| Variante erstellen | `valuation.manage` | Serverstatus |
| Report publizieren | `valuation.manage` + künftige Approval-Class-Gates | **BLOCKED** bis `VALUATION-METHOD-CONTRACT-01` |
| Review einreichen/zurückgeben | `valuation.manage` + künftige Approval-Class-Gates | **BLOCKED** für neue Phase-A-Cases |
| Genehmigen | `valuation.approve` + erfülltes fachliches Gate | **BLOCKED** für neue Phase-A-Cases; Permission ist keine Qualifikation |
| Archivieren | `valuation.manage` | erlaubte Transition/Grund |
| Property Source | `property.read` | Source-Workspace |
| Lease/Rent Roll Source | `lease.read` | Source-Workspace |
| CapEx Source | `capex.read` | Source-Workspace |
| Audit Timeline | `audit.read` | künftiger Read-Port |
| Export erzeugen | `reporting.generate` | künftiger Artifact-Contract |

### 8.2 Verhalten

- Ohne `valuation.read`: gesamter Screen Forbidden, keine Titel/KPI.
- Fehlt nur Source-Permission: Partial Data im Source Panel; Case und manuelle Faktoren bleiben lesbar.
- Erlernbare, status- oder permissionbedingt nicht mögliche Aktion ist disabled mit Grund. Reines Rauschen wird hidden.
- Server autorisiert jede Mutation; UI prüft zur Verständlichkeit vor.
- Permission-Entzug: lokale ungespeicherte Daten dürfen nicht an einen anderen Nutzer/Workspace durchsickern; Screen reconciled.
- Kein AAL2 nach aktuellem Contract.

## 9. Realtime / freshness behavior

- Subscribed heute: Case UPDATE; Ziel: Case, Factor, Report und Variant Group invalidieren.
- Realtime-Nachricht setzt einen dirty invalidation flag; Repository Read ist kanonisch.
- Bei lokaler Dirty Form wird nicht still überschrieben. Banner: „Neuer Serverstand verfügbar“ mit „Vergleichen“.
- Eigene Mutation → Command Result + Readback; ein folgendes Realtime-Event darf keinen zweiten sichtbaren Ladezyklus erzeugen.
- Reconnect → ein debounced Reconcile.
- `liveUpdatesDegraded` → Notice; Save nur nach REST-Preflight/Expected Version. Publish bleibt fachlich blockiert.
- Report-Änderungen müssen den Latest Report Provider invalidieren (`VALUATION-REALTIME-01`).

## 10. Screen states

### Global

| Zustand | Darstellung |
|---|---|
| Auth/Workspace resolving | geschütztes Skeleton, keine alten Case-Daten |
| Initial loading | Header-/Section-Skeleton |
| Not found | Case nicht vorhanden; Rückweg Queue |
| Forbidden | keine Case-Daten; Rückweg |
| Infrastructure failure | Retry, Case nicht als „leer“ darstellen |
| Background refresh | Inhalt bleibt; dezenter Indikator |
| Realtime degraded | Notice, REST bleibt kanonisch |

### Case/Faktoren

| Zustand | Darstellung |
|---|---|
| Draft ready | editierbare Felder nach Permission |
| Missing | Vollständigkeit + fehlende Felder/Methodengründe |
| Suggested | Vorschlag optisch getrennt; Accept-Aktion |
| Dirty | Feld-/Section-Marker; Save/Discard |
| Validation error | feldnah + Summary |
| Saving | betroffene Gruppe gesperrt; andere Reads sichtbar |
| Save failure | Eingabe erhalten; Retry |
| Version conflict | lokaler/serverseitiger Wertvergleich, kein Datenverlust |
| In Review | Existing Legacy State read-only; keine Phase-A-Return-/Approve-Aktion |
| Approved | Existing Legacy State immutable; Approval Class unbekannt, keine professionelle Marktwertaussage |
| Archived | terminal read-only |

### Berechnung/Report

| Zustand | Darstellung |
|---|---|
| Method available | Wert/Confidence/Breakdown |
| Method unavailable | Missing Factors/Source Gap, kein Amount |
| Live only | „Interne Live-Analyse – Publish blockiert“ |
| Legacy current | read-only; `computedFromVersion == case.version`, Approval Class unbekannt |
| Legacy stale | Live/Legacy-Stand getrennt; keine Ergebnisaktion |
| Calculation in progress | nur für künftige Jobs; Poll/Reconcile nach Contract |

## 11. Search / filter / sort

- Case Workspace hat keine globale Suche.
- Annahmen können optional nach „Fehlend“, „Geändert“, „Vorgeschlagen“ und Methode gefiltert werden; der Default zeigt alle in geführter Reihenfolge.
- Source Tables können nach Unit/Lease/Status filtern, aber nur serverseitig/contractkonform.
- Der künftige Szenariovergleich sortiert nach `SCENARIO-VALUATION-01` Baseline zuerst; Phase A besitzt nur den Variant-Wechsel.
- Version History sortiert nach `VALUATION-VERSION-01` neueste zuerst; Phase A rendert keine History-/Diff-Fläche.
- Section und aktiver Varianten-Case sind URL-State. Annahmenfilter müssen nicht zwingend URL-State sein.

## 12. Forms and validation

### 12.1 Valuation Factors Form

- Fields/Units: vollständig in Workflow 8.3.
- Controls: Money, Percent, Years, Area, Factor gemäß Catalog.
- Required/Alternative: gemäß `ValuationFactorGroup`, nicht pauschal alle Felder erforderlich.
- Defaults: keine stillen Zahlenwerte; Suggested Default unaccepted.
- Dependent fields: Alternativen und Terminalmodus.
- Unsaved changes: Save/Discard/Stay bei Navigation.
- Submit: Batch, expectedVersion, mutation/correlation.
- Server mapping: `validationFailed`, `versionConflict`, `approvedImmutable`, `forbidden`, `mutationConflict/inProgress`, infrastructure.

### 12.2 Variant dialog

- Label erforderlich, getrimmt, Contract-Maximum festlegen/anzeigen.
- Optionaler Grund.
- Keine Übernahmeoptionen, die der Server nicht unterstützt: Config/Faktoren werden geklont, Report nicht.

### 12.3 Review/Approval dialogs

- Phase A rendert keine Submit-, Return- oder Approve-Dialoge für neue Cases.
- Die vorhandenen Dialoge sind Legacy-Bestand und dürfen erst nach `VALUATION-METHOD-CONTRACT-01` mit Approval Class, Value Basis und Professional Gate neu spezifiziert werden.
- Archive: Name/Status und irreversible Folge verständlich, Grund; nur wenn der bestehende Command keine Ergebnis-Neuberechnung erzeugt.

### 12.4 Künftige Forms

- Lease/Operating/CapEx/Debt/Sensitivity Inputs werden erst aktiviert, wenn die Felder und Validierungen aus Workflow 8.4–8.6 durch Contracts/Engines getragen werden.
- Bis dahin keine disabled „Excel-Wand“; stattdessen Source Summary + benannter Gap.

## 13. Shared components

### Existing components to reuse

- `NxContentFrame`, `NxPageHeader`, `NxNotice`
- `NxLiveUpdatesNotice`
- `NxSplitView`
- bestehende Valuation Status/Confidence Badges
- bestehender `ValuationWorkflowStepper` nur als Harvest-Basis für sichere Objekt-/Faktor-/Berechnungsstände; Report-/Review-/Freigabeschritte nicht rehosten
- bestehende Factor Groups/Fields
- bestehende Method/KPI Cards nach sicherer Auswahl; keine Opinion-/`MarketValueCard`
- bestehende Variant Cards/Dialog
- vorhandene Approval Dialogs **nicht** rehosten

### Small extensions needed

- Section Navigation + URL-State;
- Case Stand Badge (`live/published/stale/approved`);
- vorhandene Field-Provenance/Source-Anzeige; strukturierte Source-/Delta-Row erst mit `VALUATION-SOURCE-01`;
- Validation Summary und nicht-stilles Parsing;
- DCF Cashflow Table aus vorhandenem `DcfValuation`;
- Missing Factor Links;
- Dirty Navigation Guard.

### New shared component candidates

- `NxProvenanceBadge` nur, wenn Imports/Property/Finance dieselbe Semantik verwenden.
- `NxVersionDelta` erst mit freigegebenem Version Contract.
- `NxCashflowTable` erst dann shared, wenn Portfolio/Finance dasselbe periodische Read Model nutzt.

## 14. Backend gaps

| Gap | Exakter Bedarf | Domain / Package | Schema/RLS/Permission |
|---|---|---|---|
| `VALUATION-METHOD-CONTRACT-01` | verbindliche Kategorien/Wertbasen, Ergebnisbegriffe, Eligibility, getrennte Reconciliation und Approval Classes gemäß `METHOD-GOV-01` | Valuation Domain/Config/Report | neues oder migriertes Contract-/Schema-Modell, bestehende Rechte reichen nicht als Fachgate |
| `VALUATION-MARKET-METHODS-01` | fachliche Modellkonformität für Ertrags-/Sachwert, Referenzdaten und boG | Valuation Domain/Reference Data | Source-/Method-Versionen |
| `VALUATION-VALIDATION-01` | semantische Servervalidation aller Factors | Factor RPC/Domain | Error Contract, keine neue Permission |
| `VALUATION-SOURCE-01` | SourceRef, Source-Version, Stichtag, Import/Aktualisierung | Factor/Case Version | Schema, audited RPC, RLS |
| `VALUATION-COMPS-01` | Cloud Comparables und Auswahl | Comparison Domain | P2-D07, RLS |
| `VALUATION-LEASE-CF-01` | periodische Lease-/MLA-Inputs und Cashflows | Valuation Cashflow | neues Schema/Engine, lease.read |
| `VALUATION-OPEX-01` | kategorisierte Plan-/Ist-Operating-Daten | Finance/Valuation | P2-D08/Actuals, RLS |
| `VALUATION-CAPEX-CF-01` | Project Selection/Periodisierung | CapEx/Valuation | neues Mapping, capex.read |
| `VALUATION-DEBT-01` | Debt Contract, Schedules, levered Results | Finance/Valuation | neues Schema/Rechte |
| `SCENARIO-VALUATION-01` | Baseline, Compare Projection, Sensitivity Runs | Valuation Scenario | neues Schema/RLS |
| `VALUATION-VERSION-01` | immutable Case Versions/Calculation Runs/Diff/Revision | Valuation Version | Schema/RLS/Audit |
| `VALUATION-AUDIT-READ-01` | casegefilterte Audit Timeline | Audit Repository | audit.read, Redaction |
| `VALUATION-REPORT-EXPORT-01` | versioniertes Dokumentartefakt | Reporting/Documents | Storage/RLS/reporting.generate |
| `VALUATION-REALTIME-01` | Factor/Report/Variant Invalidation | Realtime Adapter | Events/Publications |
| `VALUATION-CURRENCY-01` | Case Currency/FX Policy | Valuation Config | Schema/Reference Data |

Die Screen-Implementierung darf keinen Gap mit clientseitiger Persistenz oder neuer Inline-Mathematik umgehen.

## 15. Accessibility and usability

- Section Navigation ist Tastatur- und Screen-Reader-nutzbar und hat sichtbaren Fokus.
- Felder besitzen sichtbares Label, Einheit, Hint, Fehler, Herkunft und Change Status; Placeholder ersetzt kein Label.
- Prozent-/Geldformat wird beim Fokus erklärt; Copy/Paste aus deutsch formatierten Werten robust validiert.
- Status, Confidence, Stale und Provenance werden nicht nur farblich vermittelt.
- Cashflow-Tabelle hat Header-Assoziation; Chart hat Textzusammenfassung.
- Nach Save wird Erfolg angekündigt und Fokus bleibt sinnvoll.
- Archive-Dialog benennt Konsequenzen, Stand und Case; Approval-Dialog ist in Phase A nicht vorhanden.
- Mobile Touchziele mindestens 44×44 px; Sticky Footer verdeckt keine Felder.

## 16. Analytics / audit / history

### Bereits vorhanden

- Cloud Mutations sind idempotent, expected-version-basiert und schreiben append-only Audit Events.
- Factors tragen Provenance/Source/Note/Confidence.
- Report trägt `computedFromVersion`.

### V2-Erwartung

- Audit Actions: Case Create/Config Update, Factor Upsert/Remove, Variant Create, Report Publish, Status Transition, künftig Source Accept/Refresh, Version/Export.
- Reason ist bei Return/Archive und besonderen Adjustments fachlich erforderlich.
- Audit-UI erst mit `audit.read` und Read-Port.
- Keine sensiblen Lease-/Finanzierungsrohwerte in Produkt-Analytics oder Fehlerlogs.
- UI-Analytics darf Section-Nutzung, Fehlerklasse und Completion State ohne Business Values messen.

## 17. Test plan

### Unit/application

- Case-ID lädt unabhängig von Legacy Scenario State.
- Section URL Codec und Variant Switch.
- Factor Parsing/Validation für Money/Percent/Years/Area/Factor.
- Suggested Default nicht rechenwirksam; Accept ändert Provenance.
- Alternative Requirements/Progress je Methode.
- Save Batch und Live Result; vorhandener Report wird bei Änderung stale; keine neue Publish-/Approval-Aktion in Phase A.
- Version Conflict hält lokale Drafts und bildet Field Diff.
- Permission-/Status-Actions Matrix.
- Realtime Debounce, Dirty Conflict, Reconnect.
- Existing Engine Golden Tests bleiben unverändert; neue UI rechnet nicht parallel.

### Widget/UI

- Loading/Not found/Forbidden/Partial/Degraded.
- Alle fünf erlaubten Phase-A-Sections Desktop/Tablet/Mobile; blockierte/ungültige Section-Werte normalisieren auf `overview`.
- Header zeigt aktiven Case/Version/Szenario/Stand.
- Factor errors statt silent skip.
- Missing Factor Link fokussiert Feld.
- DCF Tabelle stimmt mit Controller Read Model.
- Methods unavailable ohne Fake Amount.
- Variant Create/Switch und no-report Draft.
- Legacy Report/Stale/Approved read-only; Publish/Review/Approve sind für neue Cases nicht verfügbar.
- Approved/Archived ohne Edit Controls.
- Dirty Navigation Guard und Conflict Compare.

### Repository/integration

- bestehende SQL Tests für RLS, Status, Factors, Reports, Audit, Approval und Varianten bleiben Pflicht.
- zusätzliche semantische Validation Tests nach `VALUATION-VALIDATION-01`, insbesondere `capRate = 0`, Quoten außerhalb 0–100 %, DCF Terminalbedingungen.
- Source-Import Cross-workspace/RLS/Version Tests.
- Künftiger Report Publish speichert keine Amounts für unavailable Methods und keine Cross-Family-Opinion; Phase A testet, dass der Command nicht erreichbar ist.
- Approved bleibt immutable; Revision erzeugt neues Objekt nach künftiger Semantik.

### Staging E2E

Siehe Gesamtworkflow plus:

1. Deep Link lädt Case ohne zuvor geöffneten Scenario/Analysis Screen.
2. Section Reload bleibt stabil.
3. Factor Save zeigt Source/Provenance und bumpte Version.
4. Fehlerhafte Prozent-/Money-Eingabe bleibt sichtbar und wird nicht ausgelassen.
5. DCF Cashflow entspricht Engine-Werten und zeigt Ausschluss von Debt/CapEx/Lease-by-Lease.
6. Variante klont Config/Faktoren, nicht Report.
7. Ein vorhandener Legacy-Report wechselt nach zulässiger Draft-Änderung korrekt auf stale; kein neuer Report wird publiziert.
8. Zwei Sessions erzeugen verständlichen Version Conflict.
9. Weder Reviewer noch Approver können in Phase A einen neuen Ergebnisstand genehmigen.
10. Existing Approved ist nach Reload unveränderlich und als Legacy Approval Class unbekannt gekennzeichnet.

## 18. Acceptance criteria

### Case und Navigation

- Given eine Case-ID, when der Link ohne vorherigen App-State geöffnet wird, then lädt genau dieser Cloud Case.
- Given ein gültiger Section-Key, when die Seite neu geladen wird, then bleibt der Bereich aktiv.
- Der Workspace liest keinen Legacy Scenario-/Analysis-Provider als Voraussetzung.

### Annahmen und Transparenz

- Jeder rechenwirksame Faktor zeigt Bedeutung, Einheit, Herkunft, Provenance und Change State.
- Ein Suggested Default verändert kein Ergebnis, bis der Nutzer ihn akzeptiert.
- Eine ungültig formatierte Eingabe wird nie still übersprungen.
- Nach Source-Übernahme bleibt der verwendete Source-Stichtag reproduzierbar; bis zum Source Contract ist diese Aktion nicht verfügbar.

### Cashflow und Methoden

- Die Phase-A-Cashflow-Tabelle enthält ausschließlich Werte der vorhandenen DCF Engine.
- Lease, CapEx und Debt werden nicht als enthalten dargestellt, solange ihre Engines fehlen.
- Eine unavailable Method zeigt Missing Reasons und keinen Amount.
- DCF wird als Investmentanalyse getrennt von den technischen deutschen Modellrechnungen gezeigt; Direct Capitalization bleibt bis `VALUATION-VALIDATION-01` ausgeblendet.

### Stand, Szenario, Version

- Phase A zeigt aktiven Case/Variante, Case-Version und vorhandenen Legacy-Report-/Statusstand. Baseline, History und Approval-Flächen folgen ausschließlich ihren Folgepaketen.
- Case-Änderung setzt einen vorhandenen Legacy-Report sichtbar stale.
- Neue Publish-/Approval-Aktionen sind bis `VALUATION-METHOD-CONTRACT-01` nicht verfügbar.
- Approved wird nicht in place editiert.
- Die UI nennt einen Version-Zähler nicht „Version History“, solange immutable Snapshots fehlen.

### Permission und Fehler

- Server-Forbidden überschreibt optimistische UI-Annahmen und zeigt keine geschützten Daten.
- Version Conflict verliert keine lokale Eingabe.
- Realtime Degraded lässt kanonische REST-Reads/-Commands nutzbar und reconciled nach Reconnect einmal.

## 19. Out of scope

- komplette Neuentwicklung der funktionierenden Cloud-Widgets aus ästhetischen Gründen;
- Reaktivierung der Legacy Analysis-/Inputs-/Scenarios-/Versions-Screens;
- neue Bewertungs-, Debt-, Tax-, Lease-, CapEx- oder Sensitivitätsformeln;
- ARGUS-UI/Assets/Branding oder 40+ Reports;
- Portfolio-/Fund-Level-Modellierung;
- rechtliche Aussage, dass ein Screen ein Verkehrswertgutachten ersetzt.

## 20. Open decisions

Material und deshalb den jeweiligen Ausbau blockierend:

1. Source-Stichtag, Rent Definition und Leerstandsdefinition.
2. Case Currency/FX.
3. Revision-Semantik nach Approval.
4. Baseline-Wahl und erlaubte Sensitivitätsachsen/-größen.
5. Report-Artefaktformat und Signatur-/Freigabenachweis.

Methodenkategorien, Ergebnisbegriffe, Reconciliation und Approval Classes sind durch [METHOD-GOV-01](../VALUATION_METHOD_GOVERNANCE.md) entschieden; ihre Contract-Umsetzung ist kein offener Screen-Entscheid.

Nicht blockierend für Rehost:

- genaue Tab-vs-Section-Picker-Darstellung innerhalb der UX Foundation;
- ob die DCF-Visualisierung zusätzlich zur Tabelle ein Chart erhält.

## 21. Implementation handoff

### APPROVED Rehost Scope

- Implementierungspaket ist ausschließlich `VALUATION-REHOST-01C`.
- `valuation_section_host` anhand Case-ID eigenständig routen;
- nur `overview`, `assumptions`, `cashflow`, `valuation`, `scenarios` erlauben; alle anderen Section-Werte auf `overview` normalisieren;
- vorhandene Controller/Widgets für Case, Factors, einzelne sichere Method Results und Varianten wiederverwenden;
- Case Header/Section Navigation und Standindikatoren ergänzen;
- bestehende DCF-Jahresprojektion anzeigen;
- Parsing-/Dirty-/Conflict-UX schließen;
- Cloud-Rechte, Existing-Approved-Immutability, Expected Version und Stale-Regel bewahren;
- `MarketValueCard`, gemischte Reconciliation sowie Publish/Review/Approval für neue Cases nicht rehosten.
- keine neue Source-/Baseline-/Model-Diff-, Comparables-, Version-, Audit- oder Export-Fläche implementieren.

### Voraussetzungen

- Route Host aus `VALUATION-REHOST-01A` auf `main`;
- Queue/Create öffnen die neue Route;
- gemeinsame Wave-1-Komponenten, soweit verfügbar.

### Nicht im Rehost-Paket

- alle in Abschnitt 14 benannten Backend-/Engine-Gaps;
- `VALUATION-METHOD-CONTRACT-01`, professionelle Reportbezeichnung und alle Ergebnis-Transitions;
- Source Imports, Version History, Audit Timeline und Export.

### Pflichtprüfungen

- bestehende Valuation Widget-/Controller-/Repository-/SQL-Tests;
- neue Route-, Deep-Link-, Responsive-, Dirty-, Conflict- und DCF-Presentation-Tests;
- kein Regression in Idempotency, RLS, Audit, unavailable-no-amount, Report Stale oder Approved Immutable.
