# Property Workspace V2

## Metadata

- Package / screen ID: `PROPERTY-WORKSPACE-01` / `PROPERTY-WORKSPACE-V2`
- Domain: Portfolio Property / domainübergreifender Objektkontext
- Route: heute zustandsbasiert über `GlobalPage.properties` plus selektiertes Property und lokale Surface; zukünftige kanonische Basis `/properties/:propertyId/*` ausschließlich über `SHELL-ROUTING-01`
- Current implementation file(s): `lib/features/reference_slice/presentation/reference_slice_screen.dart`, `lib/features/reference_slice/presentation/reference_property_detail_panel.dart`, `lib/features/reference_slice/application/reference_slice_controller.dart`, `lib/ui/screens/property_detail/property_shell.dart`, `lib/ui/screens/v2/property_detail/property_shell_v2.dart`, `lib/ui/navigation/app_navigation.dart`, `lib/app.dart`
- Planning status: COMMITTED (FULL-V2-SCOPE-01, 2026-09-04)
- Technical readiness: READY — Host implementiert; jede weitere Domäne bringt ihre eigene Voraussetzung mit
- Former status: APPROVED (Implementation-Readiness-Review 2026-08-28)
- Dependencies: `PRODUCT-SCREEN-MAP-01`, `PRODUCT-UX-FOUNDATION-01` und `UX-FOUNDATION-IMPL-01` liegen auf `origin/main` `3a11b091b1c8565bc15d13267db57a8bcea1b0a9` (verifiziert 2026-08-28); URL-/Back-Verhalten separat `SHELL-ROUTING-01`
- Related screens: [Property List V2](PROPERTY_LIST_V2.md), [Property Overview V2](PROPERTY_OVERVIEW_V2.md), [Property Asset V2](PROPERTY_ASSET_V2.md), [Property Leasing V2](PROPERTY_LEASING_V2.md), [Property Operations V2](PROPERTY_OPERATIONS_V2.md), [Property Documents V2](PROPERTY_DOCUMENTS_V2.md), [Property Investment Host V2](PROPERTY_INVESTMENT_V2.md) mit [Valuation](PROPERTY_VALUATION_V2.md), [Scenarios](PROPERTY_SCENARIOS_V2.md) und [Performance](PROPERTY_PERFORMANCE_V2.md), [Property Activity & Reports Host V2](PROPERTY_ACTIVITY_REPORTS_V2.md) mit [Activity](PROPERTY_ACTIVITY_V2.md), [Audit](PROPERTY_AUDIT_V2.md) und [Reports](PROPERTY_REPORTS_V2.md)

## 1. Purpose

Der Property Workspace ist der dauerhafte Arbeitskontext für genau eine Immobilie. Er ersetzt sowohl das flache Edit-Formular des Properties-Reference-Slice als auch die fachlich wertvolle, aber navigativ und technisch ungeeignete 32-Seiten-Legacy-Shell.

Der Screen beantwortet zuerst vier Fragen:

1. Welches Property bearbeite ich?
2. Was braucht jetzt Aufmerksamkeit?
3. Welche Quelle und welcher Aktualitätsstand tragen eine Aussage?
4. In welchen fachlichen Workflow muss ich als Nächstes wechseln?

Er ist kein Dashboard mit nachgebauten Kennzahlen und kein Multi-Domain-Formular. Fachliche Daten bleiben in ihren Cloud-Contracts; der Workspace vereinheitlicht Kontext, Hierarchie, Navigation, Zustände und Drilldowns.

## 2. Primary users and jobs

| Rolle | Primärer Job | Zuerst benötigte Information | Entscheidung / Aktion |
|---|---|---|---|
| Asset Manager | Zustand, Risiko und nächste Maßnahme eines Assets verstehen | Property-Identität, belastbare KPIs, offene Aufmerksamkeitspunkte, Aktualität | in Leasing, Betrieb, Bewertung oder Aufgabe drillen |
| Property Manager | Tagesbetrieb steuern | Tickets, CapEx, Aufgaben, Dokumentanforderungen | Ticket/Projekt/Aufgabe bearbeiten, Nachweis öffnen |
| Leasing Manager | Leerstand und Vertragsereignisse bearbeiten | Flächenstatus, Verträge, Mieterbezug, Pipeline, Rent Roll | Fläche/Vertrag/Fall öffnen und Lifecycle fortführen |
| Investment / Valuation Manager | Wert und Annahmen prüfen | Valuation-Case-Status, Provenienz, Szenario-/Performance-Verfügbarkeit | Case öffnen, Faktoren pflegen, Review/Approval starten |
| Document / Compliance Manager | Vollständigkeit und Nachweise sichern | serverseitig bewertete Anforderungen, Version und Verifikation | hochladen, verknüpfen, verifizieren, archivieren |
| Auditor / Management | Änderungen und Berichte nachvollziehen | Ereignisquelle, Actor, Zeit, unveränderbarer Stand | Audit lesen oder freigegebenen Bericht öffnen |

## 3. Entry points and navigation

- Primärer Einstieg ist `Objekte` → Auswahl einer Property. Sobald der blockierte Overview-Contract implementiert ist, ist `Übersicht` das Standardziel; die erste freigegebene Implementierungswelle fällt bis dahin auf `Objekt` zurück und registriert kein leeres Overview-Ziel.
- Bestehende Property-Deep-Links zu Units, Leases, Pipeline, Rent Roll, Operations, Maintenance und Documents müssen zukünftig im selben Property-Kontext landen.
- Der Header zeigt auf jeder Unterfläche Property-Name, Ort/Adresse, Status und den Rückweg `Objekte`; ein Property-Wechsler darf optional aus dem bestehenden paginierten Property-Contract lesen.
- Ein Wechsel der Hauptdomäne bewahrt `workspaceId`, `propertyId` und pro Domäne den letzten gültigen Unterbereich. Eine selektierte Unit, ein Lease, Dokument oder Case wird nur innerhalb der zugehörigen Domäne bewahrt.
- Bei ungespeicherten Änderungen wird Property- oder Domainwechsel abgefangen; Speichern, Verwerfen oder Abbrechen sind explizit.
- Rückwärtslogik: Detail → zugehörige Liste mit Filter/Scroll/Selektion; Unterbereich → letzter Property-Bereich; Property-Root → Objektliste. Browser-History und URL-Roundtrip werden erst in `SHELL-ROUTING-01` implementiert.
- Direkte Ziele ohne Leseberechtigung zeigen den standardisierten Forbidden-State. Nicht lesbare Domänen erscheinen nicht in der lokalen Navigation.

Zukünftige, nicht in diesem Paket zu implementierende Route-Familie:

```text
/properties/:propertyId/overview
/properties/:propertyId/asset
/properties/:propertyId/leasing/{units|leases|pipeline|rent-roll}
/properties/:propertyId/operations/{maintenance|capex|tasks}
/properties/:propertyId/documents/:documentId?
/properties/:propertyId/investment/{valuations|scenarios|performance}
/properties/:propertyId/activity/{activity|audit|reports}
```

## 4. Information architecture

### Verbindliche Domänenstruktur

| Ebene 1 | Unterflächen, maximal vier je Gruppe | Begründung aus User Job und Contract | Status |
|---|---|---|---|
| Übersicht | keine Tabs; priorisierte Module mit Drilldown | Orientierung und nächste Aktion, keine zweite Arbeitsoberfläche | eigener Screen; Aggregat-Contract fehlt teilweise |
| Objekt | Stammdaten; später Medien | stabile Identität getrennt von operativen und Investment-Annahmen | Property list/get/update vorhanden; Media fehlt |
| Vermietung | Flächen; Verträge & Mieter; Pipeline; Rent Roll | durchgängiger Space-to-Lease-Job auf einem `lease.*`-Contract | Cloud-Contracts und Panels vorhanden |
| Betrieb | Wartung; CapEx; Aufgaben | Tagesgeschäft und Maßnahmen; Tasks verknüpfen andere Domains | Maintenance/CapEx/Task-Contracts vorhanden; Property-Task-UI fehlt |
| Dokumente | Register; Anforderungen | Nachweis, Version, Compliance und Quellbezug bilden einen Job | Cloud-Contract vorhanden |
| Investment | Bewertung; Szenarien; Performance | Entscheidungskette Wert → Annahmen → Ergebnis; keine Stammdatenvermischung | Bewertung vorhanden; Szenario/Finance fehlen |
| Aktivität | Aktivität; Audit; Berichte | Nachvollziehbarkeit und Outputs, nicht operative Bearbeitung | Task-Contract vorhanden; Audit-App-Port und Reports fehlen |

`Mieter` ist im Property Workspace kein eigenständiges Property-Stammdatum. Der Workspace zeigt den Mieter ausschließlich im Kontext eines Vertrags oder Leasing-Falls; die workspace-weite Tenant-/Party-Destination bleibt für Beziehungsmanagement zuständig.

### Lesereihenfolge

1. Globaler Cloud-Shell-Kontext (`AppScaffold.cloud`)
2. `NxPageHeader` mit Breadcrumb `Objekte / <Property> / <Bereich>`
3. dauerhaft sichtbarer Property-Kontext und lokale Hauptnavigation
4. optionaler Unterbereich-Navigator
5. aktiver route-fähiger Screen
6. passive Aktualitäts-/Degraded-Hinweise

### KPI-Hierarchie

1. **Identität:** Name, Adresse, Property-Status; niemals KPI.
2. **Primäre Asset-KPIs:** nur explizite serverseitige Overview-Projektion mit Einheit, `asOf`, Währung, Scope und Drilldown.
3. **Server-Fakten:** beispielsweise Rent-Roll-Rohsummen und -Zähler; nicht zu neuen Raten oder Risikoscores zusammenrechnen.
4. **Detaildaten:** Tabellen/Listen der verantwortlichen Domain.
5. **Nicht verfügbar:** fehlende Quelle wird nicht als `0`, grün oder „vollständig“ dargestellt.

### Referenzanalyse: VTS / MRI → User Job → Nutzen → NexImmo

Recherche-Stand: 2026-08-28. Verwendet wurden aktuelle offizielle Produktseiten, öffentlich eingebettete Produktbilder und öffentliche Demo-/Video-Ziele. Die offizielle [VTS Office Lease Tour](https://www.vts.com/office-lease-tour) bindet eine interaktive Navattic-Demo ein; der vollständige VTS-Lease-Help-Inhalt verlangt Login. MRI verlinkt eine öffentliche Investment-Central-Video-Demo, deren Player ohne JavaScript keine Screenabfolge ausliefert, sowie eine [offizielle Reporting-Demo/Kundenstory](https://www.mrisoftware.com/resources/ct-group-utilizes-mri-investment-central-to-provide-detail-reporting-across-their-portfolio/). Deshalb werden öffentlich belegbare Produktprinzipien und visuelle Hierarchiemuster übernommen, aber keine unbelegten Control-Details oder pixelgenauen Screens behauptet.

| Referenz-Feature | User Job | Nutzen | NexImmo-Relevanz |
|---|---|---|---|
| VTS: Asset-/Portfolio-Sicht mit Live-Performance | vom Portfolio zum einzelnen Asset und dessen Ursache drillen | ein Kontext statt isolierter Listen | hoch: Objektliste → Workspace → Domain-Detail |
| VTS: Lease Roll, Vacancy Exposure, Renewal Risk | bevorstehende Ertrags-/Belegungsrisiken erkennen | priorisiert Leasing-Arbeit | hoch, aber nur mit serverseitiger Projektion; vorhandene Verträge liefern noch keinen Renewal-Risk-Score |
| VTS: Lead-to-Lease-Pipeline | Fall vom Erstkontakt bis Vertragsabschluss steuern | gemeinsame, aktuelle Deal-Sicht | hoch: bestehende zehnstufige Leasing Cases adaptieren |
| VTS: Tenant-/Lease-Kontext | Beziehung, Vertrag und Opportunity gemeinsam verstehen | schnellere Renewal-/Expansion-Entscheidung | mittel/hoch: über Party-Rollen + Lease/Case, ohne Tenant-Duplikat |
| VTS: Lease Abstraction / Asset Intelligence mit Quellklausel | Dokumentaussage prüfen, nicht nur Antwort vertrauen | Provenienz und niedrigere Suchkosten | später: heute Dokumentversion/Verifikation/Entity-Link nutzen; Extraktion/AI nicht vortäuschen |
| VTS: Risks / Opportunities auf Asset-Ebene | Wichtiges vor vollständiger Detailprüfung erkennen | Fokus auf nächste Aktion | hoch: serverseitige Operations Signals und zukünftige Overview-Projektion |
| MRI PMX: operative und finanzielle Daten zusammenführen | Property ganzheitlich steuern | weniger Systembrüche | hoch als IA; Finance erst nach `P2-D08` |
| MRI Investment Central: Portfolio → Investment/Attribut Drilldown | Risiko vom Aggregate zur Quelle verfolgen | erklärbare Managementsicht | hoch: jede KPI und Attention-Zeile hat Domain-Drilldown |
| MRI: NOI, DCR, Cashflow, Tenant Exposure, Valuations | Investment-Performance und Varianz bewerten | standardisierte Entscheidungslage | fachlich hoch, aktuell Backend-Gap; keine Legacy-Berechnung übernehmen |
| MRI: Full Lifecycle, Workflows, Reporting | Entscheidung von Datenerfassung bis freigegebenem Output steuern | Nachvollziehbarkeit und Governance | hoch: Valuation-Lifecycle vorhanden; Scenarios/Reports getrennte Gaps |
| MRI: Source of Record + Validierung | auf belastbare Daten statt Excel-Kopien arbeiten | Vertrauen, weniger Datenjagd | sehr hoch: REST/RPC bleibt kanonisch, Quelle/Stand sichtbar |
| MRI Contract/Lease Intelligence | Klauseln, Termine und Dokumentquelle verbinden | Risiko und Pflicht werden prüfbar | mittel: vorhandene Dokument-/Lease-Links nutzen; Intelligence später |

Offizielle Evidenz: [VTS Lease](https://www.vts.com/vts-lease), [VTS Produkt-/AI-Fakten](https://www.vts.com/for-ai), [VTS Platform](https://www.vts.com/vts-platform), [VTS Portfolio Performance Release](https://www.vts.com/blog/vts-summer-release-24-lmd), [VTS Tenant Network](https://reports.vts.com/blog/complete-view-tenant-relationships-introducing-tenant-network-services), [VTS Help Center](https://www.vts.com/help-center), [MRI Property Management X](https://www.mrisoftware.com/products/property-management-x/), [MRI Investment Central](https://www.mrisoftware.com/products/investment-central/), [MRI Asset Management](https://www.mrisoftware.com/solutions/asset-management/), [MRI Global Valuations](https://www.mrisoftware.com/products/real-estate-investment-software/global-valuations/), [MRI Contract Intelligence](https://www.mrisoftware.com/uk/products/contract-intelligence/), [MRI Lease Management](https://www.mrisoftware.com/uk/solutions/lease-management-software/).

### ADOPT / ADAPT / REJECT

| Entscheidung | Muster | NexImmo-Ausprägung |
|---|---|---|
| ADOPT | ein Asset-Kontext und Drilldowns | Property-Header bleibt über allen Unterflächen sichtbar |
| ADOPT | Source-of-truth und Quellbezug | kanonischer Domain-Read, `asOf`/Freshness, Link zum Quelldatensatz |
| ADOPT | Leasing-Pipeline als Workflow | bestehende Cases und auditierte Lifecycle-Transitions |
| ADOPT | Risiko/Opportunity führt zur Aktion | Attention-Zeile öffnet verantwortliche Domain oder existierende Aufgabe |
| ADOPT | Lifecycle, Review, Approval, immutable Outputs | vorhandene Valuation-/Document-/Rent-Roll-Snapshot-Semantik |
| ADAPT | VTS Asset Performance | serverseitige NexImmo-Projektion; kein Markt-Benchmark oder Client-Score |
| ADAPT | Lease Roll / Vacancy / Renewal | Wohn-, Gewerbe- und Mixed-use-fähig; Rohdaten und Definition offenlegen |
| ADAPT | Tenant Network | Workspace-Party bleibt Master, Property-Kontext entsteht über Lease/Case |
| ADAPT | MRI KPI-/Variance-Hierarchie | erst nach Finance-Contract; je KPI Einheit, Währung, Zeitraum, Quelle |
| ADAPT | Document-to-data | heute Version, Entity-Link, Requirement und Verifikation; Extraktion später |
| REJECT | exaktes VTS/MRI-Layout, Logos oder Trade Dress | ausschließlich `PRODUCT-UX-FOUNDATION-01` |
| REJECT | VTS Predictive Demand, Sentiment oder proprietäre Benchmarks | keine Datenquelle/kein Contract in NexImmo |
| REJECT | conversational AI oder automatische Lease-Abstraktion im Workspace V2 | spätere Produktidee mit Provenienz- und Review-Contract |
| REJECT | MRI General Ledger/Fund Accounting als improvisierte Property-UI | wartet auf `P2-D08`/`P2-D09` |
| REJECT | Legacy-KPIs und Completion-Proxies | keine Client-Synthese, keine erfundenen NOI/IRR/DSCR/Score-Werte |
| REJECT | 32 gleichrangige Seiten und automatisch erzeugtes „Basis“-Szenario | gruppierte Domain-IA; keine Cross-Domain-Nebenwirkung |
| REJECT | Create/Archive/Delete über den Update-Contract | bleibt `PROPERTY-DATA-02` |

### Legacy-Workspace: behalten, zusammenführen, entfernen, neu konzipieren

| Legacy-Seiten | Disposition | Ziel |
|---|---|---|
| Overview | neu konzipieren | serverautoritatives Overview mit Attention und Drilldowns |
| Inputs, Analysis, Comps, Criteria, Offer | zusammenführen/neu konzipieren | Investment-Kontext; Valuation jetzt, Scenario/Finance/Comps nur nach Contract |
| Scenarios, Versions | behalten und rebuilden | Investment → Szenarien; Lifecycle und immutable Versionen, keine JSON-/SQLite-Hacks |
| Audit, Reports | zusammenführen | Aktivität → Audit/Berichte; nur Cloud-Read/Report-Contract |
| Documents | behalten/rehosten | Dokumente und Anforderungen auf vorhandenem Contract |
| Operations Overview, Alerts | zusammenführen | Overview-Attention + Betrieb; vorhandene serverseitige Signals, keine Client-Aggregate |
| Tasks, Maintenance | behalten/rehosten | Betrieb → Aufgaben/Wartung; Cloud-Contracts statt SQLite |
| Units, Tenants, Leases, Rent Roll | zusammenführen | Vermietung; Tenant bleibt Party-Rolle im Lease-Kontext |
| Asset Workbook, Budget vs Actual, Covenants | neu konzipieren | Investment → Performance nach `P2-D08`; keine Legacy-Formeln |
| Sale Data, Buyer Interests, Viewings, Sale Offers, Reservations | aus Workspace V2 entfernen | ungeklärte Sale-Domain; `SALE-HOTEL-01` Produktentscheidung |
| Guests, Housekeeping, Hotel Revenue | aus Workspace V2 entfernen | ungeklärte Hospitality-Domain; keine umbenannten Query-Screens |
| Parking Storage, Unit Sale Status | aus Workspace V2 entfernen | semantisch doppelte/ungeklärte Legacy-Flächen |

## 5. Layout and interaction model

### Desktop (>1199 px)

- Eine `AppScaffold.cloud`-Instanz; kein zweiter App-Shell.
- `NxContentFrame` bis 1440 px.
- `NxPageHeader` enthält Breadcrumb, Property-Identität, Status und zulässige Property-Aktionen.
- Darunter eine lokale, horizontal lesbare Domain-Navigation mit höchstens den sieben verbindlichen Zielen `Übersicht / Objekt / Vermietung / Betrieb / Dokumente / Investment / Aktivität`; sie ist eine Route-Navigation, keine Tab-Leiste. Noch nicht implementierte oder nicht lesbare Ziele bleiben verborgen. Untertabs gibt es nur innerhalb einer Domain und maximal vier.
- Inhalt nutzt je Surface das Foundation-Muster: Übersicht gestapelt, Listen/Details 3:2 über `NxSplitView`, Formulare mit begrenzter Lesebreite.

### Tablet (768–1199 px)

- Voller Property-Header, Domain-Navigation horizontal scrollbar oder als beschrifteter Domain-Selector; keine abgeschnittenen Ziele.
- Listen/Details wechseln in eine einzelne Ebene. Filter dürfen in einen Drawer, Kernfilter bleiben sichtbar.
- Property-Kontext bleibt oberhalb des aktiven Screens sichtbar, darf aber auf Name, Ort und Status verdichten.

### Mobile (≤767 px)

- Kompakter Header mit `Zurück`, Property-Name, Status und zugänglichem Domain-Selector.
- Detail ersetzt Liste. Der systemische Zurück-Button kehrt zur zuvor erhaltenen Liste zurück.
- Karten werden einspaltig; Tabellen erhalten die in der Foundation definierte mobile Karten-/Zeilenalternative.
- Kein horizontaler 32-Seiten-Navigator, keine abgeschnittene KPI-Reihe und keine sticky Vollbreiten-Aktionsleiste, die Inhalt verdeckt.

## 6. Functional requirements

### Property-Kontext öffnen

- Trigger: Property-Zeile/Karte oder gültiger Property-Deep-Link.
- Voraussetzung: aktive Session, Workspace ausgewählt, `property.read` für Entity-Scope.
- Erfolg: Property wird kanonisch geladen, Header und zulässige Domain-Navigation erscheinen, Standardziel ist Übersicht.
- Fehler: notFound und forbidden bleiben unterscheidbar, ohne unzulässige Entity-Daten zu leaken.

### Domain und Unterbereich wechseln

- Trigger: lokale Navigation.
- Voraussetzung: jeweilige Read-Permission.
- Erfolg: `propertyId` bleibt erhalten, Surface lädt unabhängig und ist zukünftig deep-link-fähig.
- Fehler: der bisherige Property-Kontext bleibt; nur der Inhaltsbereich zeigt Fehler/Retry.

### Property wechseln

- Trigger: Property-Wechsler im Header.
- Voraussetzung: `property.read`; keine unentschiedenen Änderungen.
- Daten: serverseitig paginierte Property-Suche/Liste, kein bereits geladenes Client-Subset als vermeintlich vollständiger Suchraum.
- Erfolg: Kindselektion und nicht kompatible Filter werden verworfen; dieselbe Domain wird geöffnet, wenn das Ziel dort lesbar ist, sonst Übersicht.

### Bearbeiten

- Bearbeitungsaktionen gehören der aktiven Domain und deren Spec.
- Global sichtbar ist höchstens „Stammdaten bearbeiten“ bei `property.update`; Create/Archive/Delete werden nicht angeboten.
- Mutationen bleiben versioniert, idempotent/auditiert gemäß bestehendem Contract und dürfen AAL-Anforderungen nicht abschwächen.

### Attention-Drilldown

- Jede serverseitige Attention-Zeile hat Quelle, Stand, semantischen Typ und ein gültiges Ziel.
- Ein Klick öffnet die verantwortliche Domain und, wenn vorhanden, den Datensatz.
- Fehlt Zielzugriff, wird keine Attention-Zeile mit sensiblen Inhalten ausgeliefert oder gerendert.

## 7. Data requirements

| Datenbereich | Vorhandene Cloud-Quelle | Workspace-Nutzung | Grenze |
|---|---|---|---|
| Property | `PropertyRepository.list/getById/update`, `PropertyDto` | Identität, Status, Stammdaten | kein Create/Archive/Delete-Workflow; kein Media |
| Units / Leases / Cases | jeweilige `Unit*`, `Lease*` und `LeasingCase*` Repository-/Search-Ports | Flächen, Verträge, Pipeline, Tenant-Bezug | Renewal Risk/Exposure nicht vorhanden |
| Rent Roll | Live-RPC + immutable Snapshots | serverseitige Rohzähler/-summen und Detail | `occupancyRate`-Getter nicht als Overview-KPI |
| Operations Signals | serverseitige Signal-Query | Attention/Datengüte mit Drilldown | keine clientseitige Neugewichtung |
| Parties / Tenant roles | Party-/Tenant-Contracts | Name/Rolle im Lease-/Case-Kontext | Tenant-Verzeichnis ist workspace-weit |
| Documents / Requirements | `DocumentRepository`, `DocumentContentPort`, `DocumentLinkPort`, `RequirementPolicyRepository`, `DocumentVerificationPort`, `SignedUrlPort` | Register, Versionen, Links, Verifikation, Requirement-Zustand | keine AI-Extraktion; Media unvollständig |
| Maintenance / CapEx | `MaintenanceTicketRepository`/`SearchPort`, `CapexProjectRepository`/`SearchPort` | Tickets, Projekte, Lifecycle | heutige Panel-Formulare nutzen nicht alle DTO-Felder |
| Tasks | `TaskRepository` | Entity-gefilterte Aufgaben | Property-UI fehlt; kein Legacy-Checklist/Delete/Cost |
| Valuation | `ValuationCaseRepository`, `ValuationFactorPort`, `ValuationReportPort` | Cases, Faktoren, Provenienz, Reports, Lifecycle | Property-Case-Route/Detail-Host fehlt; Comps nicht cloud-fähig |
| Audit | `audit_events` + `audit.read` RLS | vorgesehen für Objekt-Audit | kein App-DTO/Repository/Read-Port |
| Scenario / Finance / Reports | keine belastbaren Cloud-Contracts | nur Ziel-IA | separate Backend-Pakete |

Jeder Betrag zeigt Währung; gemischte Währungen werden nicht summiert. Jede Zeitraum-KPI zeigt Zeitraum/`asOf`. `null`, nicht geladen, forbidden und echter Wert `0` bleiben unterscheidbar.

## 8. Permissions and security behavior

- Einstieg: `property.read`; Mutation der Stammdaten: `property.update` plus die bereits serverseitig geforderte Assurance/AAL2-Semantik.
- Vermietung: `lease.read` / `lease.manage`; Tenant-Identität zusätzlich gemäß `party.read`/`party.manage`.
- Wartung: `maintenance.read` / `maintenance.manage`.
- CapEx: `capex.read` / `capex.manage`; Übergang zu `approved` zusätzlich `capex.approve`.
- Dokumente: `document.read` / `document.manage`; Verifikation separat `document.verify`.
- Bewertung: `valuation.read` / `valuation.manage`; Approval separat `valuation.approve`.
- Aufgaben: `task.read` / `task.manage`; Audit: `audit.read`.
- Es wird keine Permission, Rolle, RLS-Policy oder Entity-Scope-Erweiterung in diesem Screen-Paket geplant. Der lokale Legacy-Katalog wird nicht still erweitert.
- Navigation ohne Read-Permission ist verborgen; Direktzugriff zeigt Forbidden; Action ohne Manage-Permission ist verborgen oder sichtbar deaktiviert mit erklärendem Tooltip entsprechend Foundation und fachlichem Nutzen.
- Bei Permission-Revoke während der Session: laufende Mutation beenden lassen oder serverseitig ablehnen, betroffene Cache-Daten löschen, Navigation neu berechnen, keine stale sensiblen Daten anzeigen.
- Client-Gating ist nur UX; RLS/RPC-Autorisierung bleibt verbindlich.

## 9. Realtime / freshness behavior

- Jede Domain behält ihren bestehenden permission-scoped Invalidation-Stream; es entsteht kein breiter Workspace-Realtime-Topic.
- Events invalidieren ausschließlich betroffene Queries. Der kanonische Zustand kommt anschließend über REST/RPC.
- Nach Reconnect erfolgt je sichtbarer Domain genau ein koaleszierter Reconcile, kein Reload-Burst aller Workspace-Flächen.
- Hintergrund-Refresh behält vorhandene Daten sichtbar und zeigt einen passiven `NxLiveUpdatesNotice`/Freshness-Hinweis.
- Bei `liveUpdatesDegraded` bleiben Reads und Mutationen nutzbar, soweit deren Contract verfügbar ist; der Screen behauptet keine Live-Aktualität.

## 10. Screen states

| Zustand | Erwartung |
|---|---|
| Initial loading | Header-Skeleton plus `NxListSkeleton`/detailgerechter linearer Skeleton; kein globaler Spinner |
| Background refresh | bestehender Inhalt bleibt, passiver Fortschritt/Freshness-Hinweis |
| Empty Property-Liste | Empty-State mit erlaubter nächster Aktion; Create nur nach `PROPERTY-DATA-02` |
| Populated | Header, erlaubte Navigation und aktive Surface vollständig |
| Partial/incomplete | einzelne Domain-Zone mit Quelle/Fehler; übrige Zonen bleiben nutzbar |
| Validation error | feldnah in aktiver Domain, Kontext bleibt bestehen |
| Recoverable error | betroffene Zone + Retry, keine gesamte Shell ersetzen |
| Fatal/unavailable | `NxNotice` im Inhalt, Breadcrumb/Rückweg bleiben |
| Permission denied | standardisierter Forbidden-State ohne Property-Fachdaten |
| Session/auth transition | sichere Auth-/MFA-/Workspace-Phase; Entity-Daten werden entfernt |
| Realtime degraded | passive, nicht blockierende Meldung; `asOf` sichtbar |
| Action in progress/success/failure | Domain-spezifisch, doppeltes Submit verhindert; Feedback ohne Kontextverlust |
| Not found | Property-NotFound mit Rückweg zu `Objekte`, keine Forbidden-Details |

## 11. Search / filter / sort

- Der Shell-weite Property-Wechsler sucht Name, Adresse, PLZ und Ort nur, wenn der Property-List-Contract dies serverseitig vollständig unterstützt; bis dahin paginierte Browse-Liste statt irreführender globaler Suche.
- Domainfilter gehören den Child-Screens und bleiben beim Detail-Rückweg erhalten.
- Zukünftige URL-Filter werden erst mit `SHELL-ROUTING-01` festgelegt; die UI-States müssen schon serialisierbar und deterministisch sein.
- No-match ist ein eigener Zustand und bietet „Filter zurücksetzen“, nicht den Domain-Empty-State.

## 12. Forms and validation

- Die Shell besitzt kein Sammelformular.
- Dirty-State wird vom aktiven Child registriert; Property-/Domain-/Back-Wechsel löst einen einheitlichen Unsaved-Changes-Dialog aus.
- Kein Child darf beim Öffnen automatisch Szenarien, Inputs oder andere Domain-Daten erzeugen.
- Validierung, Konfliktauflösung und Serverfehler-Mapping sind in den Child-Specs beschrieben.

## 13. Shared components

### Existing components to reuse

- `AppScaffold.cloud`, `NxContentFrame`, `NxPageHeader`, Foundation-Breadcrumbs
- `NxKpiTile`/`NxKpiRow` ausschließlich für autoritative KPI-Werte
- bestehende Domain-Panels und Controller, ohne ihre Client-Aggregate in Overview zu übernehmen

### Small extensions needed

- bestehende Property-Selektion aus dem Reference Slice in einen wiederverwendbaren Property-Kontext-Controller extrahieren
- bestehende List/Detail-Panels auf Foundation-Breakpoints und Narrow-Detail-Replacement normalisieren
- Domain-Controller müssen Dirty-State und route-fähige Selektion an den Host melden können

### New shared component candidate

- `NxPropertyContextHeader`: Property-Identität, Breadcrumb, Status, Wechsler und zulässige Property-Aktion
- `NxWorkspaceSectionNav`: zugängliche, responsive Route-Navigation mit max. sieben Hauptzielen und klarer aktiver Ebene
- Umsetzung als separates Shared-UI-Inkrement innerhalb `PROPERTY-WORKSPACE-01`; kein verdeckter Designsystem-Rewrite. `NxLiveUpdatesNotice`, `NxListSkeleton`, `NxSplitView`, `NxNotice` kommen aus `UX-FOUNDATION-IMPL-01`.

## 14. Prerequisites (COMMITTED, prerequisite-first)

Diese Voraussetzungen sind seit FULL-V2-SCOPE-01, 2026-09-04 **COMMITTED**: Sie sind Teil des verbindlichen V2-Zielbildes und werden gebaut — prerequisite-first, unmittelbar gefolgt von der abhängigen Oberfläche und Staging-E2E. Eine fehlende technische Voraussetzung nimmt die Produktfähigkeit **nicht** mehr aus dem Scope; sie bestimmt nur die Reihenfolge. Der Produkt-Scope (COMMITTED) und die technische Bereitschaft (READY / PREREQUISITE REQUIRED) werden getrennt geführt.

| Gap | Exakter Bedarf | Bereich | Schema/RLS/Permission | Separates Paket |
|---|---|---|---|---|
| Create/Archive/Delete | autorisierte Property-Lifecycle-Aktionen | PropertyRepository | zu prüfen, nicht hier planen | bestehend `PROPERTY-DATA-02` |
| Overview-Projektion | serverautoritatives KPI-/Attention-Modell für Expiries, Vacancy Exposure, Renewal Risk, Aufgaben, Maintenance/CapEx, Compliance, Valuation-Freshness, Activity und Data Quality; Definition, Coverage, `asOf`, Drilldown-Ref | domainübergreifender Read-Contract | expliziter Security-/RLS-Review nötig; keine neue Permission voraussetzen | Vorschlag `PROPERTY-OVERVIEW-DATA-01`, vor Umsetzung in Tracker aufnehmen |
| Property Media | private Media-Liste, Titelbild, Upload/Version/Lifecycle | Property/Document | explizit zu entscheiden; Documents nicht zweckentfremden | Vorschlag `PROPERTY-MEDIA-DATA-01` |
| Scenario Lifecycle/Versions | create/duplicate/review/approve/archive, immutable Snapshot, Compare/Rollback | Scenario | vollständig separat spezifizieren | bestehend `SCENARIO-VALUATION-01` / Scenario-Contract |
| Financial Performance | Actual/Budget/Forecast/NOI/Cashflow/Debt/Covenant mit Währung/Zeitraum | Finance | `P2-D08`; keine Legacy-Formeln | bestehend `FINANCE-01` |
| Audit Read Port | property-gefilterte, paginierte Query und App-DTO/Repository | platform audit | Tabelle/RLS vorhanden; Contract/Adapter fehlt | bestehend `AUDIT-01` |
| Reports | serverseitige freigegebene Reports, Version, Status, Download | reporting | `P2-D09`; Permission-Modell explizit | bestehend `PORTFOLIO-REPORTING-01` |
| Renewal/Exposure | definierte Lease-Roll-/Vacancy-/Renewal-Projektion | leasing | darf nicht aus geladenen Seiten errechnet werden | Teil von `PROPERTY-OVERVIEW-DATA-01` oder separatem Leasing-Read-Paket |

## 15. Accessibility and usability

- Breadcrumb, Property-Wechsler, Haupt- und Unternavigation haben eindeutige Rollen, Namen, Fokusindikatoren und Tastaturnavigation.
- Nach Surface-Wechsel geht Fokus auf die neue H1; nach Detail-Schließen auf die auslösende Zeile.
- Status wird nie nur über Farbe codiert; Icon/Label und zugänglicher Text sind Pflicht.
- Touch-Ziele erfüllen Foundation-Mindestgröße; mobile Auswahl benötigt keine Hover-Aktion.
- Lange Property-Namen/Adressen umbrechen oder ellipsieren mit vollständigem zugänglichem Namen.
- Destruktive Actions sind bis `PROPERTY-DATA-02` nicht sichtbar.

## 16. Analytics / audit / history

- Navigations-Telemetrie darf Screen-ID, Domain und Ergebniszustand enthalten, aber keine Notizen, Dokumentnamen, Vertragswerte oder personenbezogenen Tenant-Inhalte.
- Domain-Mutationen verwenden ausschließlich bestehende auditierte RPCs; die Shell erzeugt keine Schatten-Audit-Events.
- Activity/Audit-Anzeige ist erst mit dem unter §14 benannten Read-Contract zulässig.

## 17. Test plan

### Unit/application

- Property-Kontext bleibt bei Domainwechsel stabil; Kindselektion wird nur regelgerecht erhalten.
- Navigation wird aus Read-Capabilities deterministisch abgeleitet.
- Dirty-Child verhindert Property-/Domainwechsel bis zur Nutzerentscheidung.
- Realtime-Invalidierungen werden pro Domain koalesziert; Reconnect führt zu genau einem Reconcile.

### Widget/UI

- Desktop, Tablet und Mobile für Header, Domain-Navigation, Narrow-Detail-Back und lange Namen.
- Loading, forbidden, notFound, partial error, no-match, degraded und Hintergrund-Refresh.
- Tastaturreihenfolge, Fokus-Rückgabe, Screenreader-Namen und keine Overflow-Fehler.

### Repository/integration

- Kein neuer Cross-Domain-Client-Join für Overview.
- Entity-scoped Permissions/RLS verhindern Property-Cross-Read.
- Kanonischer Readback nach Mutation und Realtime-Invalidierung.

### Staging E2E

1. Asset Manager öffnet Property A, wechselt Übersicht → Vermietung → Betrieb → Dokumente; Property A bleibt in Header und Queries erhalten.
2. Tablet-/Mobile-Nutzer öffnet eine Unit und geht zurück; Filter, Scrollposition und Property bleiben erhalten.
3. Nutzer mit `property.read`/`lease.read`, aber ohne `document.read`, sieht keine Dokument-Navigation; direkter Dokument-Link endet forbidden und leakt keine Metadaten.
4. Nutzer editiert Stammdaten, ein zweiter Nutzer aktualisiert denselben Stand; Konflikt erhält Eingaben und ermöglicht kanonisches Neuladen.
5. Realtime-Verbindung fällt aus; stale Inhalt bleibt mit Hinweis sichtbar; Reconnect erzeugt genau einen Readback.
6. Property-Permission wird während der Session entzogen; sichtbare Entity-Daten verschwinden und die Shell wechselt forbidden.
7. `SHELL-ROUTING-01` besitzt separat den späteren Integrations-E2E für Lease-/Document-/Valuation-Deep-Link, Refresh und Browser-Back; er ist kein Gate des freigegebenen Host-PRs.

## 18. Acceptance criteria

- Given ein lesbares Property, when eine erlaubte Domain geöffnet wird, then sind Property-Name, Status und `Objekte / <Property> / <Bereich>` sichtbar.
- Given ein Domainwechsel, then bleibt dieselbe `propertyId` in allen ausgelösten Queries erhalten.
- Given ≤767 px, when ein Detail geöffnet wird, then ersetzt es die Liste und Back stellt Liste, Filter, Scroll und Fokus wieder her.
- Given eine fehlende Domain-Read-Permission, then fehlt das Navigationsziel; ein Direktzugriff zeigt forbidden ohne Domain-Daten.
- Given eine fehlende Manage-/Approve-Permission, then ist die Aktion nicht ausführbar und der Server bleibt die Autorität.
- Given Realtime-Degradation, then bleiben vorhandene Daten sichtbar, werden nicht als live bezeichnet und nach Reconnect genau einmal abgeglichen.
- Given fehlende Overview-/Finance-/Scenario-Daten, then werden weder `0` noch berechnete Legacy-KPIs noch positive Completion-Zustände angezeigt.
- Kein Workspace-Render führt ungefragt Create, Archive, Delete, Scenario-Erzeugung oder Cross-Domain-Write aus.
- Alle sieben Hauptziele und maximal vier Unterziele pro Domain sind auf Desktop, Tablet und Mobile ohne abgeschnittene Controls erreichbar.

## 19. Non-Goals (REJECTED) und fremde Zuständigkeit

Ab FULL-V2-SCOPE-01, 2026-09-04 stehen hier **nur noch echte Nicht-Ziele (REJECTED)** sowie Umfänge, die fachlich in eine andere Spec gehören. Alles, was früher wegen Aufwand, fehlendem Backend oder fehlendem Query-Contract hier stand, ist jetzt COMMITTED und mit seiner Voraussetzung in §14 geführt. REJECTED gilt ausschließlich für fremdes Trade Dress und Logos, pixelgenaue Kopien, erfundene KPIs oder Client-Synthese fehlender Serverdaten, unsichere öffentliche Auslieferung und jede Umgehung von AAL/RLS/Entity-Scope.

- Implementierung von Produktcode, Navigation oder Router
- Property Create/Archive/Delete und Create-Wizard
- neue Schema-, RLS-, Rollen- oder Permission-Definitionen
- Portfolio-Dashboard, globales Tenant-Verzeichnis oder Admin-Workspace
- VTS/MRI Trade Dress, proprietäre Assets, Markt-Benchmarks oder AI-Abstraktion
- Sale-/Hospitality-Domain
- clientseitige Rekonstruktion fehlender KPI-/Report-/Scenario-Daten

## 20. Open decisions

Keine offene Material Product Decision für den Host.

Verbindlich geschlossen:

- Der Property-Wechsler startet als keyset-paginierter Browse-Dialog in der festen Contractsortierung; es gibt ohne Serversearch keine globale Textsuche.
- Nicht implementierte Childs werden nicht registriert. Bis `PROPERTY-OVERVIEW-DATA-01` landet, ist `Objekt` der erste Workspace-Screen; bis mindestens ein Activity-Child landet, fehlt das Ziel `Aktivität` in der Laufzeitnavigation.
- Overview-Endpointform, Activity-Sichtbarkeit und deren Permissions bleiben Blocker der jeweiligen Child-Spec und blockieren den Host nicht.
- URL-/Back-Serialisierung bleibt sauber als Voraussetzung `SHELL-ROUTING-01` abgegrenzt; der Host implementiert keinen Router-Workaround.

## 21. Implementation handoff

### Vorgeschlagene Inkremente

1. Auf dem gelandeten `UX-FOUNDATION-IMPL-01` Property-Kontext-Header, Domain-Navigation und Host innerhalb `PROPERTY-WORKSPACE-01` bauen.
2. Asset-Stammdaten aus dem Reference Slice rehosten und Konflikt-/Realtime-Verhalten unverändert sichern.
3. Vorhandene Leasing-Panels im Host rehosten und Responsive-/State-Verhalten normalisieren.
4. Parallel vorhandene Pakete `MAINTENANCE-PARITY-01`, `DOCUMENTS-COMPLETE-01`, `TASKS-NOTIFICATIONS-01` und `VALUATION-REHOST-01` property-scoped anschließen.
5. `PROPERTY-OVERVIEW-DATA-01` separat spezifizieren/implementieren; erst danach Overview-UI und das Laufzeitziel `Übersicht` gegen genau diesen Contract registrieren.
6. Erst nach ihren Contracts: `SCENARIO-VALUATION-01`, `FINANCE-01`, `AUDIT-01`, `PORTFOLIO-REPORTING-01`, Property Media.
7. `SHELL-ROUTING-01` integriert kanonische URLs und Browser-History separat; kein Child baut einen Router-Workaround.

### Parallelisierung

- Nach stabilem Host-API können Asset, Leasing-Normalisierung, Maintenance/CapEx, Documents, Tasks und Valuation parallel gebaut werden.
- Overview-Backend, Scenario-Contract, Finance, Audit-Read, Reporting und Media können als voneinander getrennte Backend-/Applikationsstreams parallel laufen; ihre jeweiligen UI-Teile folgen erst nach Contract-Freigabe.
- Shell/Host kommt vor Child-Integration; Overview-UI kommt nach Overview-Contract; Scenario/Performance/Audit/Reports bleiben bis zu ihren Abhängigkeiten bewusst nicht-funktionale IA-Ziele beziehungsweise verborgen.

Hard invariants: ein Property-Kontext; kein Client-KPI; keine ungeprüfte Permission; REST/RPC kanonisch; Entity-Scope bleibt erhalten; keine Legacy-Auto-Writes; keine Route außerhalb `SHELL-ROUTING-01`.

### Implementation-Readiness- und Dependency-Matrix (Review 2026-08-28)

Die 15 Specs sind Screen-/Host-Grenzen, nicht 15 Top-Level-Ziele. Verbindlich bleiben höchstens sieben Workspace-Ziele; Investment und Aktivität sind Hosts ihrer Child-Screens.

| Spec | Produkt-Scope | Technische Voraussetzung (prerequisite-first) | Kann parallel implementiert werden mit |
|---|---|---|---|
| Property Workspace | COMMITTED | READY — Host implementiert | nach Host-API: Asset, Leasing, Operations, Documents, Investment/Valuation |
| Property List | COMMITTED | READY; Suche/Lifecycle: PREREQUISITE REQUIRED — `PROPERTY-LOOKUP-01`, `PROPERTY-DATA-02` | Asset; Valuation-Rehost |
| Property Overview | COMMITTED | PREREQUISITE REQUIRED — `PROPERTY-OVERVIEW-DATA-01` | Backend parallel zu Scenario, Finance, Activity/Audit, Media |
| Property Asset | COMMITTED | READY; Lifecycle/Medien: PREREQUISITE REQUIRED — `PROPERTY-DATA-02`, `PROPERTY-MEDIA-DATA-01` | Leasing; Operations; Documents; Valuation |
| Property Leasing | COMMITTED | READY — Contracts und Panels vorhanden; Domain-Degraded-Wiring begleitet die Registrierung | Asset; Operations; Documents; Valuation |
| Property Operations | COMMITTED | READY für Aufgaben; Wartung/CapEx: PREREQUISITE REQUIRED — `MAINTENANCE-PARITY-01` | Leasing; Documents; Valuation |
| Property Documents | COMMITTED | READY — implementiert; Medien: PREREQUISITE REQUIRED — `PROPERTY-MEDIA-DATA-01` | Leasing; Operations; Valuation |
| Property Investment Host | COMMITTED | PREREQUISITE REQUIRED — erster Child `VALUATION-REHOST-01` | Documents; Operations |
| Property Valuation | COMMITTED | PREREQUISITE REQUIRED — `VALUATION-REHOST-01` | Leasing; Operations; Documents |
| Property Scenarios | COMMITTED | PREREQUISITE REQUIRED — Scenario-Lifecycle-/Versions-/Calculation-Contract (`SCENARIO-VALUATION-01`) | Backend parallel zu Overview, Finance, Activity/Audit, Media |
| Property Performance | COMMITTED | PREREQUISITE REQUIRED — `P2-D08` / `FINANCE-01` | Backend parallel zu Overview, Scenario, Activity/Audit, Media |
| Property Activity & Reports Host | COMMITTED | PREREQUISITE REQUIRED — erster implementierter Child; zuerst voraussichtlich `AUDIT-01` | Hostplanung parallel zu den drei Child-Backends |
| Property Activity | COMMITTED | PREREQUISITE REQUIRED — permission-gefilterter Activity-Read-/Security-Contract (`PROPERTY-ACTIVITY-01`) | parallel zu Audit und Reports |
| Property Audit | COMMITTED | PREREQUISITE REQUIRED — sicherer App-Read-Port/DTO/Redaction (`AUDIT-01`) | parallel zu Activity und Reports |
| Property Reports | COMMITTED | PREREQUISITE REQUIRED — `P2-D09` / `PORTFOLIO-REPORTING-01` | parallel zu Activity und Audit |
