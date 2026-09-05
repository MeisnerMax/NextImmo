# Property Overview V2

## Metadata

- Package / screen ID: `PROPERTY-WORKSPACE-01` / `PROPERTY-OVERVIEW-V2`
- Domain: domainübergreifende Property-Zusammenfassung
- Route: zukünftiges Ziel `/properties/:propertyId/overview`; heute zustandsbasiert im Property-Host
- Current implementation file(s): `lib/features/portfolio_property/presentation/property_overview_panel.dart`, `lib/features/portfolio_property/domain/property_overview_dto.dart`, `supabase/migrations/20260906100000_property_overview_data_01.sql`. Legacy (nicht übernommen, nur User-Job-Inventar): `lib/ui/screens/property_detail/overview_screen.dart`, `lib/ui/screens/property_detail/overview/overview_view_model.dart`, `lib/ui/screens/property_detail/leasing/operations_overview_panel.dart`, `lib/ui/screens/property_detail/leasing/operations_alerts_panel.dart`
- Planning status: COMMITTED (FULL-V2-SCOPE-01, 2026-09-04)
- Technical readiness (Stand 2026-09-06): READY für die gezählten Domänenfakten und die serverseitig geordnete Attention-Liste — `PROPERTY-OVERVIEW-DATA-01` ist implementiert und `Übersicht` ist zur Laufzeit registriert. PREREQUISITE REQUIRED bleibt für drei Module: Finanzkennzahlen (`P2-D08`/`FINANCE-01`), Letzte Aktivität (`AUDIT-01`) sowie Lease Roll / Vacancy Exposure / Renewal Risk als vollständige Projektion (`LEASING-SUMMARY-01`). Diese Module sind abwesend und als abwesend beschriftet, nicht geschätzt
- Former status: BLOCKED (`PROPERTY-OVERVIEW-DATA-01`; Implementation-Readiness-Review 2026-08-28), aufgehoben 2026-09-06
- Dependencies: [Property Workspace V2](PROPERTY_WORKSPACE_V2.md), `UX-FOUNDATION-IMPL-01`, vorgeschlagener Backend-Contract `PROPERTY-OVERVIEW-DATA-01`
- Related screens: alle Property-Domain-Screens; globales Dashboard ist nicht dieses Overview

## 1. Purpose

Die Übersicht liefert innerhalb von höchstens einer Arbeitsminute eine belastbare Antwort auf: Was ist der aktuelle Zustand dieses Properties, was braucht Aufmerksamkeit und wohin muss der Nutzer drillen? Sie ist eine entscheidungsorientierte Zusammenfassung, keine zweite Bearbeitungsoberfläche.

Legacy-Overview und heutiges Operations Overview dürfen nur als User-Job-Inventar dienen. Deren clientseitige NOI-, Cap-Rate-, Cashflow-, IRR-, ROI-, DSCR-, Flächen-, Expiry- und Completion-Berechnungen werden nicht übernommen.

## 2. Primary users and jobs

| Rolle | Job | Erste Information | Nächste Aktion |
|---|---|---|---|
| Asset Manager | Risiko und Performance eines Assets einordnen | autoritative KPI-Hierarchie, Attention, Quelle/Stand | in Ursache drillen oder Aufgabe öffnen |
| Property Manager | akute betriebliche Arbeit erkennen | fällige Tickets/CapEx/Aufgaben | verantwortlichen Datensatz bearbeiten |
| Leasing Manager | Leerstand, Expiries und Renewal-Arbeit priorisieren | serverseitige Exposure-/Lease-Roll-Sicht | Fläche, Vertrag oder Case öffnen |
| Investment Manager | Bewertungs- und Performance-Stand prüfen | letzter freigegebener/aktueller Valuation-Status; Finance-Verfügbarkeit | Valuation/Performance öffnen |
| Compliance Manager | fehlende/ungültige Nachweise erkennen | serverseitig evaluierte Requirement-Zustände | Anforderung/Dokument öffnen |

## 3. Entry points and navigation

- Standardziel nach Property-Auswahl und sichere Rückfallfläche, falls die zuletzt geöffnete Domain nicht mehr lesbar ist.
- Property-Kontext, Breadcrumb und Domain-Navigation kommen aus dem Host.
- Jede KPI-, Attention-, Task-, Expiry-, Ticket-, CapEx-, Requirement-, Valuation- und Activity-Zeile hat genau ein fachliches Drilldown-Ziel.
- Zurück aus dem Drilldown stellt die Overview-Scrollposition wieder her.
- URL-/Back-Serialisierung bleibt `SHELL-ROUTING-01`.

## 4. Information architecture

1. Property-Kontext-Header
2. Freshness-/Coverage-Zeile: `Stand`, verfügbare Quellen, Degraded-Zustand
3. autoritative KPI-Reihe, nur soweit der Summary-Contract Werte liefert
4. `Aufmerksamkeit`: serverseitig priorisierte Risiken, Chancen und Datenqualitätsprobleme
5. `Vermietung`: Lease Expiries / Vacancy / Pipeline-Kontext
6. `Betrieb`: aktuelle Aufgaben, Maintenance und CapEx
7. `Dokumente & Compliance`
8. `Bewertung & Performance`
9. `Letzte Aktivität`

### KPI-Definitionen

Der Screen plant KPI-Slots, aber keine Formel. Ein Slot wird nur gerendert, wenn der Server neben dem Wert mindestens `metricKey`, menschenlesbares Label, Einheit/Währung, Scope, Periode oder `asOf`, Coverage und Drilldown liefert.

| KPI-Slot | Fachliche Aussage | Zulässige Quelle | Nicht zulässig |
|---|---|---|---|
| Belegung / Leerstand | belegte und freie Einheiten/Fläche im Property | serverseitige Overview-/Rent-Roll-Projektion | `occupied / total` im Client; DTO-Getter als neue Wahrheit |
| Lease Roll / Expiry Exposure | auslaufende Verträge nach serverdefiniertem Zeitfenster | serverseitige Leasing-Projektion mit Fensterlabel | aus maximal drei geladenen Seiten zählen |
| Renewal Risk / Opportunity | explizit begründete Renewal-Risiken/-Chancen | neuer serverseitiger Signal-Contract | Score aus Ablaufdatum, Sentiment oder Pipeline erfinden |
| Rent Roll | serverseitige Monats-/Jahressummen nach Währung | bestehender Live-Rent-Roll-Read oder Overview-Projektion | gemischte Währungen summieren |
| Betrieb | fällige/überfällige Tickets, CapEx und Aufgaben | serverseitige Summary/Attention-Projektion | Listen laden und im Client zählen/sortieren |
| Compliance | Requirement-Zustand und offene Handlungsbedarfe | serverseitige Requirement-Evaluation/Summary | „vollständig“ aus Dokumentanzahl ableiten |
| Valuation | Status/Freshness einer autoritativen Bewertung | Valuation-Summary mit Case/Report-Referenz | Wert aus Faktoren oder Legacy-Analyse berechnen |
| Financial Performance | NOI/Cashflow/Budget-Varianz mit Periode | zukünftiger `P2-D08`-Contract | Legacy-Formeln oder lokale Inputs |

Ohne `PROPERTY-OVERVIEW-DATA-01` kann eine erste UI ausschließlich klar beschriftete serverseitige Rohfakten und direkte Signalzeilen anzeigen. Fehlende Slots werden weggelassen oder als „Für diese Kennzahl ist noch keine autoritative Quelle verfügbar“ erklärt; nie als `0`.

### Umgesetzter Stand (2026-09-06)

`property_overview(workspace, property)` liefert `as_of`, die Property-Identität, sechs permission-gescopte Sektionen und eine serverseitig geordnete Attention-Liste. Jede Zahl ist eine gespeicherte Zählung; keine Quote, kein Score, kein Wert.

| Sektion | Permission | Gelieferte Fakten |
|---|---|---|
| leasing | `lease.read` | Flächen gesamt/vermietet/leer/nicht vermietbar, Verträge aktiv, Ende in 90 Tagen, abgelaufen aber aktiv, offene Vermietungsfälle |
| maintenance | `maintenance.read` | offene, überfällige und dringende Tickets |
| capex | `capex.read` | offene Projekte, Projekte vor Freigabe |
| tasks | `task.read` | offene, überfällige, blockierte Aufgaben |
| documents | `document.read` | verknüpfte Dokumente, Anforderungen gesamt/überfällig/verzichtet |
| valuation | `valuation.read` | Fälle gesamt/in Arbeit, letzte Bearbeitung (kein Wert) |

### `Lease Roll & Leerstand` (LEASING-SUMMARY-01, 2026-09-05)

`property_leasing_summary(workspace, property)` füllt drei der oben geplanten KPI-Slots — *Belegung / Leerstand* nach Fläche, *Lease Roll / Expiry Exposure* mit Fensterlabel und *Rent Roll* je Währung. Zwei Gates: entity-scoped `property.read` **und** `lease.read`; wer nur eines hat, bekommt eine benannte Absage statt eines halben Bildes.

| Block | Gelieferte Fakten | Bewusst nicht geliefert |
|---|---|---|
| Einheiten & Fläche | Einheiten gesamt/vermietet/leer/gesperrt, Fläche gesamt/vermietet/leer, Einheiten ohne erfasste Fläche | Belegungsquote — „nach Einheit“ und „nach Fläche“ sind verschiedene Zahlen; beide Eingangsgrößen werden veröffentlicht, die Entscheidung bleibt offen |
| Leerstandsdauer | längster Leerstand in Tagen, leere Einheiten ohne erfassten Beginn | kein „leer seit heute“ für einen fehlenden Beginn |
| Lease Roll | aktiv, unbefristet, abgelaufen aber aktiv, vier kumulative Fenster (30/90/180/365) mit servergesetztem Label | keine clientseitig geschnittenen Fenster |
| Fristen | Kündigungs-, Verlängerungs- und Sonderkündigungstermine in 90 Tagen | Renewal Risk — braucht den offenen Signal-Contract |
| Sollmiete | Monatsbasis je Währung, Vertragszahl je Währung | keine währungsübergreifende Summe |

Die Fläche wird nur dort summiert, wo sie erfasst ist; die Zahl der Einheiten ohne Fläche reist mit der Summe. Erfasst keine einzige Einheit eine Fläche, zeigt die UI einen Strich statt `0 m²`.


Eine Sektion ohne Permission liefert `available: false` samt der benötigten Permission und **ohne jede Zahl** — die UI kann daraus kein `0` machen, weil keine da ist. Attention entsteht ausschließlich aus den erlaubten Sektionen, ist server-priorisiert (`critical` → `warning` → `info`, danach feste Typreihenfolge) und trägt keinen Score, den der Client neu interpretieren könnte.

Nicht enthalten und als „noch nicht abgedeckt“ beschriftet: Finanzkennzahlen, Letzte Aktivität, Lease-Roll-/Renewal-Projektion, Belegungsquote.

## 5. Layout and interaction model

### Desktop

- KPI-Reihe über `NxKpiRow`; Anzahl passt sich dem gelieferten Contract an, ohne leere Platzhalter aufzufüllen.
- Darunter 3:2-Hauptaufteilung: links Attention und Leasing, rechts Aufgaben/Betrieb/Compliance; Bewertung und Activity folgen über volle Breite.
- Module sind keine beliebig verschiebbaren Dashboard-Widgets. Reihenfolge folgt Risiko → Aktion → Evidenz.

### Tablet

- KPI-Tiles umbrechen kontrolliert auf zwei Spalten.
- Module werden in derselben Prioritätsreihenfolge einspaltig oder 2:1 gestapelt; keine horizontale Mini-Tabelle.

### Mobile

- Property-Header kompakt; KPI-Tiles einspaltig beziehungsweise als kompakte Faktenliste.
- Attention zuerst, danach nächste Aufgaben; Sekundärmodule progressiv darunter.
- Jede Zeile besitzt eine ausreichend große gesamte Klickfläche und klare Domainbezeichnung.

## 6. Functional requirements

### Overview laden

- Trigger: Property-Root oder `Übersicht`.
- Voraussetzung: `property.read`.
- Erfolg: Basisproperty plus alle serverseitig autorisierten Module werden unabhängig geladen; Quelle und Aktualität sind sichtbar.
- Fehler: Modulfehler degradieren nur das Modul; Basisproperty-Fehler ist fatal für den Screen.

### KPI öffnen

- Trigger: KPI-Tile.
- Voraussetzung: KPI enthält gültigen Drilldown und Nutzer besitzt Ziel-Read-Permission.
- Erfolg: verantwortliche Domain wird mit dem vom Server gelieferten Scope/Filter geöffnet.
- Fehler: Ziel bleibt gesperrt; keine sensible KPI darf zuvor clientseitig sichtbar gewesen sein.

### Attention bearbeiten

- Trigger: Attention-Zeile oder Primäraktion.
- Voraussetzung: serverseitiger Typ und Entity-Referenz; Read für Drilldown, Manage für Mutation.
- Erfolg: Domain-Detail oder existierende Task wird geöffnet.
- Acknowledge/Resolve ist nur zulässig, wenn der verantwortliche Domain-Contract diese Transition besitzt; keine lokale Dismiss-Liste.

### Aufgabe öffnen/erstellen

- Existierende Property-Tasks können über `TaskRepository.searchTasks(TaskListQuery(entity: PlatformEntityRef(property, propertyId)))` gelistet und geöffnet werden.
- Create benötigt `task.manage`, Titel sowie Property-Entity-Referenz und nutzt den bestehenden auditierten Contract.
- Overview erhält kein eigenes Task-Modell; Checklist, geschätzte Kosten und Delete aus Legacy sind nicht verfügbar.

### Manuell aktualisieren

- Trigger: Retry/Refresh eines Moduls.
- Erfolg: genau die betroffene kanonische Query wird gelesen; vorhandene Daten bleiben währenddessen sichtbar.

## 7. Data requirements

### Basisfelder

| Wert | Quelle | Pflicht | Format / Beziehung |
|---|---|---|---|
| Property name/status/address/type | `PropertyRepository.getById`, `PropertyDto` | Name/Status Pflicht, Rest optional | Header; Status als Label, keine Farbcodierung allein |
| Summary `asOf`/coverage | neuer Overview-Contract | Pflicht je Summary-Aussage | Zeitzone sichtbar/zugänglich; Coverage nicht als implizit vollständig |
| KPI | neuer Overview-Contract oder explizites serverseitiges Rent-Roll-Feld | optional | Einheit, Währung, Zeitraum, Quelle, Drilldown |
| Attention | Operations Signals + zukünftige domainübergreifende Projection | optional | severity/type/reason/source/entityRef/asOf/actionRef |
| Property tasks | `TaskRepository` | optional | title/status/priority/assignee/dueAt/updatedAt/entityRef |
| Lease expiry/vacancy/renewal | neuer Leasing-Summary-Read | optional | Serverfenster und Scope zwingend |
| Maintenance/CapEx summary | neuer Overview-Summary-Read | optional | keine Clientzählung aus DTO-Listen |
| Requirement summary | serverseitige Requirement-Evaluation/Summary | optional | Statusdefinition vom Server |
| Valuation summary | neuer Valuation-Summary-Read auf vorhandenem Lifecycle | optional | caseId/reportId/status/asOf/staleness |
| Activity | zukünftiger Audit-/Activity-Read | optional | eventType/actor/time/entityRef; Payload minimiert |

## 8. Permissions and security behavior

- `property.read` ist Voraussetzung für den Screen.
- Jedes Modul ist zusätzlich domain-gated: `lease.read`, `maintenance.read`, `capex.read`, `task.read`, `document.read`, `valuation.read`, später `audit.read`/Reporting-Permission.
- Ein gemeinsamer Summary-Endpoint muss serverseitig Felder/Zeilen nach Entity-Scope und Domain-Permission filtern. Alternativ bleiben Summary-Endpunkte je Domain getrennt. Der Client darf keine verbotenen Module nachträglich „verstecken“, nachdem Daten geliefert wurden.
- Fehlende Domain-Read-Permission führt zu keinem Modul und keiner KPI-Lücke, aus der Entity-Existenz ableitbar wäre. Direktdrilldown zeigt forbidden.
- Aktionen benötigen jeweilige Manage-/Approve-Permission; Read-only-Nutzer erhalten keine aktiven Mutationscontrols.
- Keine neuen Permission-Schlüssel oder RLS-Regeln werden in dieser Spec vorausgesetzt.

## 9. Realtime / freshness behavior

- Property-, Lease-, Operations-Signal-, Document-, Maintenance-/CapEx-, Task- und Valuation-Invalidierungen dürfen nur ihr Modul neu lesen.
- Invalidation enthält keine fachlichen Nutzdaten; REST/RPC ist kanonisch.
- Refreshes werden pro Query koalesziert; schneller Event-Sturm erzeugt keinen Fanout-Loop.
- `liveUpdatesDegraded` ist pro Quelle sichtbar. Ein globaler Hinweis darf nicht behaupten, alle Quellen seien degraded, wenn nur eine betroffen ist.
- Nach Reconnect je sichtbare Quelle genau ein Reconcile. Nicht sichtbare/unerlaubte Module werden nicht geladen.

## 10. Screen states

| Zustand | Darstellung |
|---|---|
| Initial loading | Property-Header-Skeleton, KPI-/Listen-Skeletons in stabiler Geometrie |
| Background refresh | stale Inhalte bleiben, kleine Progress-/Freshness-Anzeige |
| Empty | „Für dieses Property liegen noch keine Overview-Summaries vor“ plus erlaubte Domain-Links; keine Null-KPIs |
| Populated | nur gelieferte autoritative Module |
| Partial/incomplete | Quellen-/Coverage-Hinweis direkt im Modul |
| Recoverable module error | Modul-`NxNotice` mit Retry |
| Fatal property error | Screen-Notice mit Rückweg `Objekte` |
| Permission denied | Property-Forbidden ohne Inhalte |
| Session/auth transition | Daten entfernen, Host-Auth-State |
| Realtime degraded | passiver Hinweis je Quelle; `asOf` bleibt sichtbar |
| Task action in progress/success/failure | Zeile bleibt sichtbar, doppelte Aktion gesperrt, kanonischer Readback |
| No authorized modules | Basisproperty + neutrale Erklärung, keine Namen verbotener Records |

## 11. Search / filter / sort

- Overview besitzt keine globale Suche.
- Attention ist serverseitig priorisiert; der Client darf lediglich die gelieferten Typen `Alle / Risiken / Chancen / Datenqualität` filtern, ohne Reihenfolge oder Counts neu zu interpretieren.
- Stand 2026-09-06 gibt es diesen Filter **nicht**: der Server liefert Severity (`critical/warning/info`), aber noch keine Risk-/Opportunity-/Data-Quality-Taxonomie — die ist offene Entscheidung in §20. Einen Filter über eine clientseitig erfundene Taxonomie anzubieten wäre genau die Neuinterpretation, die dieser Punkt verbietet.
- Optionaler Zeitraumfilter wird erst eingeführt, wenn der Summary-Contract zulässige Fenster und vollständige Neuberechnung serverseitig unterstützt.
- Filterzustand soll später URL-fähig sein, wird aber nicht vor `SHELL-ROUTING-01` in Routen umgesetzt.

## 12. Forms and validation

- Kein KPI- oder Summary-Edit auf Overview.
- Zulässig ist ein kompakter Task-Create-Dialog auf bestehendem Contract: Titel Pflicht; Status/Prio/Assignee/Due gemäß `TaskDto`; Entity fest auf Property; Serverfehler feldnah.
- Unsaved Task-Create wird bei Domainwechsel bestätigt.
- Attention-Acknowledge nur über existierende Domain-Transition; keine generische Freitextauflösung.

## 13. Shared components

### Existing components to reuse

- `NxPageHeader`, `NxKpiRow`, `NxKpiTile`, Foundation-Karten/Listenzeilen
- `NxLiveUpdatesNotice`, `NxListSkeleton`, `NxNotice` nach `UX-FOUNDATION-IMPL-01`
- bestehende Operations-Signal- und Task-DTOs; keine Übernahme der Aggregationslogik aus `OperationsOverviewPanel`

### Small extensions needed

- KPI-Tile benötigt zugängliche Quelle/`asOf`/Coverage und optionalen Drilldown.
- Modulcontainer benötigt unabhängige Loading/Error/Degraded-Zeile.

### New shared component candidate

- `NxAttentionList` für serverpriorisierte, quellbelegte Zeilen mit Severity, Grund, Stand und Drilldown; als Shared-UI-Kandidat separat reviewen.

## 14. Prerequisites (COMMITTED, prerequisite-first)

Diese Voraussetzungen sind seit FULL-V2-SCOPE-01, 2026-09-04 **COMMITTED**: Sie sind Teil des verbindlichen V2-Zielbildes und werden gebaut — prerequisite-first, unmittelbar gefolgt von der abhängigen Oberfläche und Staging-E2E. Eine fehlende technische Voraussetzung nimmt die Produktfähigkeit **nicht** mehr aus dem Scope; sie bestimmt nur die Reihenfolge. Der Produkt-Scope (COMMITTED) und die technische Bereitschaft (READY / PREREQUISITE REQUIRED) werden getrennt geführt.

1. `PROPERTY-OVERVIEW-DATA-01` — **erledigt 2026-09-06.** Permission-gefilterte Summary- und Attention-Projektion mit `as_of`, Drilldown-Ziel je Eintrag und Coverage über `available`/`permission`. Keine neuen Permission-Schlüssel, keine RLS-Änderung: die Funktion ist `security definer` mit `search_path = ''` und prüft `auth.uid()`, AAL2 (`DEC-025`) und entity-scoped `property.read`, danach je Sektion die Domain-Permission.
2. Lease Roll / Vacancy Exposure / Renewal Risk: vollständige serverseitige Projektion; keine Ableitung aus paginierten Units/Leases. **Offen (`LEASING-SUMMARY-01`).** Geliefert sind bisher nur gezählte Zustände (leer, aktiv, Ende in 90 Tagen), keine Exposure-Kennzahl und kein Renewal-Risiko.
3. Maintenance-/CapEx-/Task-Summary: priorisierte offene Arbeit ohne Clientzählung. **Erledigt 2026-09-06** als Teil von 1.
4. Document-Compliance-Summary: serverseitige Aggregation der bereits bewerteten Requirements. **Erledigt 2026-09-06** als Teil von 1.
5. Valuation-Summary: expliziter aktueller Case/Report/Freshness-Read statt „erste Zeile ist aktuell“. **Teilweise:** Fallzahlen und letzte Bearbeitung stehen; welcher Case/Report autoritativ ist, entscheidet `VALUATION-REHOST-01` zusammen mit `METHOD-GOV-01`.
6. Financial KPI: wartet auf `P2-D08` / `FINANCE-01`. **Offen.**
7. Recent Activity: Audit-App-Read-Port über `AUDIT-01`; kein Direktzugriff auf Tabelle aus UI. **Offen.**

## 15. Accessibility and usability

- KPI-Wert, Label, Einheit, Periode und Freshness werden in sinnvoller Lesereihenfolge angekündigt.
- Attention-Severity hat Text und Icon zusätzlich zur Farbe.
- Fokus springt nach Drilldown-Back auf auslösende Zeile; nach Modul-Retry nicht an Seitenanfang.
- Karten sind per Tastatur auslösbar, wenn sie navigieren; sonst keine falsche Button-Semantik.
- Mobile Zielgrößen und Textumbruch nach Foundation.

## 16. Analytics / audit / history

- Erfasst werden dürfen Screen geladen, Modul technisch unavailable und Drilldown-Typ; keine KPI-Werte, Tenant-Namen, Dokumenttitel oder Attention-Begründungen in Telemetrie.
- Task-/Signal-Mutationen bleiben über bestehende RPC-Auditierung nachvollziehbar.
- Overview selbst schreibt kein „gesehen“-Event, solange kein genehmigter Contract existiert.

## 17. Test plan

### Unit/application

- Nur servergelieferte KPI-Werte werden in View-Modelle gemappt; `null` erzeugt keine Null-Tile.
- Domainpermission entfernt Query und Modul vollständig.
- Invalidation refreshes nur betroffene Quelle und koalesziert Events.

### Widget/UI

- volle, leere, teilweise, forbidden, module-error, degraded und stale-refresh Zustände.
- lange Beträge/Labels, mehrere Währungen, fehlender Drilldown, Tablet/Mobile-Wrap.
- kein Legacy-KPI-Text ohne entsprechenden Contractwert.

### Repository/integration

- Summary-Read kann keine Daten eines anderen Properties/Entity-Scopes liefern.
- Währung/Periode/Coverage/`asOf` roundtrippen unverändert.
- Mischberechtigungen werden serverseitig korrekt reduziert.

### Staging E2E

1. Asset Manager öffnet Property mit vollständigen Fixtures; jede Overview-Zeile drillt in richtigen Datensatz und Back stellt Scroll wieder her.
2. Nutzer ohne `document.read` sieht keine Compliance-Daten, behält aber Leasing/Betrieb.
3. Property ohne Finance-/Valuation-Summary zeigt keine Null- oder Grün-KPI.
4. Lease-/Task-Änderung durch zweiten Nutzer invalidiert nur relevante Module; Reconnect liest genau einmal nach.
5. Gemischte Währungen erscheinen getrennt und werden nie zu einer Summe verbunden.

## 18. Acceptance criteria

- Jede sichtbare KPI besitzt Wert, Einheit/Währung, Scope/Periode oder `asOf`, Quelle und gültigen Drilldown.
- Keine sichtbare KPI wird aus geladenen Listen, DTO-Gettern oder Legacy-Formeln berechnet.
- Fehlende Quelle, echter Nullwert, Fehler und forbidden sind visuell und semantisch unterscheidbar.
- Ein Modulfehler ersetzt nicht den gesamten Overview.
- Attention-Reihenfolge entspricht exakt der serverseitigen Priorität; der Client erzeugt keinen Score.
- Nutzer ohne Domain-Read erhält weder Modulquery noch Domaininhalte.
- Background refresh und Realtime-Degradation lassen stale, als stale markierte Daten sichtbar.
- Alle Overview-Drilldowns erhalten dieselbe `propertyId`.

## 19. Non-Goals (REJECTED) und fremde Zuständigkeit

Ab FULL-V2-SCOPE-01, 2026-09-04 stehen hier **nur noch echte Nicht-Ziele (REJECTED)** sowie Umfänge, die fachlich in eine andere Spec gehören. Alles, was früher wegen Aufwand, fehlendem Backend oder fehlendem Query-Contract hier stand, ist jetzt COMMITTED und mit seiner Voraussetzung in §14 geführt. REJECTED gilt ausschließlich für fremdes Trade Dress und Logos, pixelgenaue Kopien, erfundene KPIs oder Client-Synthese fehlender Serverdaten, unsichere öffentliche Auslieferung und jede Umgehung von AAL/RLS/Entity-Scope.

- KPI-Formeln, Schema, RLS oder Permission-Erweiterungen
- Portfolioübergreifendes Dashboard und Benchmarking
- Prognose-AI, Tenant Sentiment, Market Demand und Dokumentabstraktion
- Bearbeitung von Lease, Ticket, CapEx, Dokument oder Valuation direkt in Overview
- Clientseitige Vollständigkeits-, Risiko- oder Opportunity-Scores

## 20. Open decisions

- gemeinsamer permission-gefilterter Overview-Endpoint versus fachliche Summary-Endpunkte
- genehmigte KPI-Definitionen, Zeitfenster, Coverage- und Staleness-Schwellen
- serverseitige Priorisierung und Taxonomie von Risk / Opportunity / Data Quality
- welche Activity-Typen unter `task.read`, `audit.read` und zukünftig Reporting-Rechten erscheinen

## 21. Implementation handoff

Produkt-Scope: COMMITTED (FULL-V2-SCOPE-01). `PROPERTY-OVERVIEW-DATA-01` ist am 2026-09-06 prerequisite-first gelandet, unmittelbar gefolgt von dieser Oberfläche; `Übersicht` ist seitdem zur Laufzeit registriert und das Standardziel nach der Property-Auswahl. Belegt durch pgTAP 032 (40 Assertions: Gate-Reihenfolge, Sektions-Scoping ohne Zahlen, Leak-Kanarienvogel-Property, Attention-Ordnung und Attention-Leak-Test), Rollback 038 sowie Widget-Tests für volle, leere, teilweise, forbidden, module-error, stale-refresh und Step-up-Zustände über fünf Viewports.

Noch nicht erledigt und offen ausgewiesen: die drei Prerequisites aus §14 (Finanz-KPIs, Letzte Aktivität, Lease-Roll-/Renewal-Projektion) sowie die fünf Staging-Journeys. Hard invariant: Der Client visualisiert Fakten; er erfindet keine Asset-Performance.
