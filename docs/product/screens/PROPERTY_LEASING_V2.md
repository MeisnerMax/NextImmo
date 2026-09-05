# Property Leasing V2

## Metadata

- Package / screen ID: `PROPERTY-WORKSPACE-01` / `PROPERTY-LEASING-V2`
- Domain: Leasing Operations
- Route: zukünftige Ziele `/properties/:propertyId/leasing/units`, `/leases/:leaseId?`, `/pipeline/:caseId?`, `/rent-roll`; heute property-scoped Navigation-State
- Current implementation file(s): `lib/ui/screens/property_detail/leasing/units_panel.dart`, `leases_panel.dart`, `leasing_pipeline_panel.dart`, `rent_roll_panel.dart`, `tenant_detail_view.dart`, `lib/features/leasing_operations/application/leasing_repository.dart`
- Planning status: COMMITTED (FULL-V2-SCOPE-01, 2026-09-04)
- Technical readiness: READY — im Workspace-Host registriert (2026-09-05): vier Unterbereiche auf den vorhandenen Unit-/Lease-/Case-/Rent-Roll-Contracts, gated `lease.read`; die Exposure-Projektion liegt seit `LEASING-SUMMARY-01` (2026-09-05) serverseitig vor. PREREQUISITE REQUIRED bleibt für Suche, Renewal-Risk-Signal und Mietstaffel-Contract
- Former status: APPROVED (Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Workspace V2](PROPERTY_WORKSPACE_V2.md), `UX-FOUNDATION-IMPL-01`, `SHELL-ROUTING-01` nur für spätere URLs
- Related screens: [Property Overview V2](PROPERTY_OVERVIEW_V2.md), workspace-weite Tenants/Parties-Surface

## 1. Purpose

`Vermietung` führt die zusammenhängende Arbeitskette Fläche → Interessent/Fall → Vertrag → Rent Roll innerhalb eines Property-Kontexts. Die bestehende Cloud-Funktionalität wird nicht neu erfunden, sondern als vier verständliche, route-fähige Unterflächen rehostet. Tenant-Stammdaten bleiben im workspace-weiten Party-Contract; hier erscheint Tenant-Kontext nur, wenn er an Lease oder Case gebunden ist.

## 2. Primary users and jobs

| Rolle | Job | Zuerst benötigt | Aktion |
|---|---|---|---|
| Leasing Manager | verfügbare Flächen und Dealfortschritt steuern | Unit-Status, offene Cases, Vertragsbezug | Unit/Case/Lease erstellen oder Lifecycle fortführen |
| Asset Manager | Lease Roll und Exposure bis zur Quelle prüfen | serverseitige Rent-Roll-Fakten, Laufzeiten, Pipeline | in Unit/Lease/Case drillen |
| Property Manager | Belegung und Vertragskontext eines Spaces verstehen | Unit, effektiver Lease, Tenant-Kontext | Detail lesen; bei Recht Status pflegen |
| Lease Administrator | Vertragsdaten und Laufzeiten aktuell halten | Vertrag, Parteienreferenz, Termine, Status | editieren/transitionieren, Snapshot erzeugen |

## 3. Entry points and navigation

- Property Workspace → `Vermietung` → `Flächen`, `Verträge & Mieter`, `Pipeline`, `Rent Roll`.
- Overview-Drilldowns öffnen Zielunterbereich und Datensatz/Serverfilter.
- Selektion und Filter bleiben je Unterfläche beim Wechsel und Detail-Back erhalten; beim Property-Wechsel werden Entity-IDs verworfen.
- Workspace-weites Tenant-Profil kann aus einem verknüpften Lease/Case geöffnet werden; Back kehrt zum Property-Lease-Kontext zurück.
- Deep links werden vorbereitet, aber nur `SHELL-ROUTING-01` schreibt Router/Browser-History.

## 4. Information architecture

### Flächen

1. Statusfilter und serverseitige Liste
2. Unit-Zeile: Bezeichnung/Nummer, Typ/Fläche soweit vorhanden, servergelieferter Status
3. Unit-Detail: Attribute, aktuelle Lease-Referenzen, Auditmetadaten
4. Create/Edit/Lifecycle-Aktionen

### Verträge & Mieter

1. Lease-Filter: Status, Unit, Tenant-Referenz, Effektivitätskontext soweit Contract unterstützt
2. Lease-Liste und Detail
3. Tenant-Kontext als verknüpfte Party-Rolle, nicht als duplizierter Property-Datensatz
4. Create/Edit/Lifecycle-Aktionen

### Pipeline

1. Open/terminal Filter
2. zehn serverdefinierte Stages in Contractreihenfolge
3. Case-Karte mit Unit/Party-/Lease-Kontext, Verantwortlichkeit und Stand
4. Create/Edit/Forward/Cancel gemäß Lifecycle; kein Archive/Delete

### Rent Roll

1. Live-Stand mit serverseitigen Zählern und Währungssummen
2. Lines als Quell-/Drilldown-Tabelle
3. immutable Snapshots und Snapshot-Detail
4. Snapshot erstellen bei `lease.manage`

## 5. Layout and interaction model

### Desktop

- Unterbereich-Navigation mit vier Zielen.
- Units/Leases/Rent-Roll-Snapshots als `NxSplitView` 3:2: Liste links, Detail rechts.
- Pipeline darf ab 900 px als horizontal scrollbares Stage-Board erscheinen; Spaltenzahl wird nicht künstlich verdichtet. Boardscroll und Seiten-Navigation sind getrennt.

### Tablet

- Liste ersetzt Detail; Zurück stellt Filter/Scroll/Fokus her.
- Pipeline nutzt je nach verfügbarer Breite ein kontrolliert scrollbares Board oder gestapelte Stage-Gruppen.

### Mobile

- einspaltige Listen/Karten; Detail ersetzt Liste.
- Pipeline immer als vertikale Stage-Gruppen mit sichtbarer Stage-Bezeichnung und Fallzahl nur, wenn serverseitig/aus vollständig geladenem Stage-Ergebnis belastbar. Keine abgeschnittenen Karten.
- Rent-Roll-Lines als mobile Fact Cards statt breiter Finanztabelle.

## 6. Functional requirements

### Units

- List/get mit Property-Scope und Keyset-Pagination.
- Create/Edit bei `lease.manage`, versioniert und auditiert.
- Status-/Offline-Transition nur über vorhandenen Repository-Contract; ein erforderlicher Grund ist Pflicht und wird servervalidiert.
- Kein Delete.

### Leases

- List/get mit Property-Scope und vorhandenen Serverfiltern.
- Create/Edit/Lifecycle bei `lease.manage`; Unit-, Tenant- und Datumsbeziehungen werden vor Submit validiert und serverseitig autorisiert.
- Effektiver/terminaler Status wird nicht im Client aus Daten abgeleitet.
- Kein Delete.

### Tenant-Kontext

- Lease-/Case-Felder unter `lease.read` dürfen angezeigt werden, soweit der Server sie liefert.
- Party-Profil/Relationship benötigt `party.read`; Party-Edit `party.manage` und erfolgt nicht im Lease-Formular.
- Fehlt `party.read`, degradiert nur der Profilbereich; Lease bleibt nach seinem Contract lesbar.

### Pipeline Cases

- List/get/create/update und auditierte Stage-Transitions gemäß zehnstufigem Contract.
- Forward-, Cancel- und terminale Aktionen zeigen Voraussetzungen und Fehler; kein Drag-and-drop als einzige Eingabemethode.
- `openOnly=true` trennt die zehn aktiven Stufen von den terminalen Zuständen `completed` und `cancelled`; beide Terminalzustände bleiben über den exakten Statusfilter erreichbar. Es gibt keinen Archive-Zustand.

### Rent Roll

- Live-Read zeigt ausschließlich servergelieferte Counts, Totals und Lines.
- `occupancyRate` als lokaler DTO-Getter darf nicht als autoritative Property-KPI promoted werden.
- Snapshot-Erzeugung bei `lease.manage`; Snapshot ist immutable und erhält serverseitigen Stand.
- gemischte Währungen werden getrennt und ehrlich dargestellt.

### Search / load more

- Keyset `Load more` bleibt kanonisch; kein Offset.
- Im freigegebenen Inkrement gibt es keine Textsuche. Keyset-Listen werden nicht clientseitig als vollständig durchsuchbar dargestellt.

## 7. Data requirements

| Bereich | DTO / Repository | Kernwerte | Beziehungen |
|---|---|---|---|
| Unit | `UnitDto`, `UnitRepository`/`UnitSearchPort` | id/propertyId, Kennung/Name, Typ/Fläche, Status, Offline-Grund, version/timestamps | Property; Leases; Cases |
| Lease | `LeaseDto`, `LeaseRepository`/`LeaseSearchPort` | id/propertyId/unitId/tenantPartyId, Status, Termine, Mietwerte/Währung, version/timestamps gemäß DTO | Unit; Party; Rent Roll |
| Leasing Case | `LeasingCaseDto`, `LeasingCaseRepository`/`LeasingCaseSearchPort` | id/propertyId, caseName, Status, Source, openedAt, optionale Unit-/Prospect-/Lease-IDs, version | Unit; Party; resultierender Lease |
| Live Rent Roll | `RentRollLiveDto`, `RentRollPort.readLive` | serverseitige Unit-/Lease-Counts, Beträge nach Contract, Lines, `asOf` | Unit/Lease |
| Snapshot | `RentRollPort` | immutable Header/Lines/Stand | Property, erzeugender Actor |
| Tenant | Party/Tenant role contracts | Name/Rolle/Profil nur nach jeweiliger Permission | Lease/Case referenzieren Party-ID |

Alle Beträge zeigen Währung. Fläche zeigt die Contract-Einheit. Das UI berechnet keine Exposure-, Renewal-, NOI- oder Performancewerte.

## 8. Permissions and security behavior

- gesamte Domain: `property.read` plus `lease.read`.
- Mutationen: `lease.manage`; Tenant-Profil `party.read`, Tenant-Mutation `party.manage`.
- Read-only-Nutzer sehen keine aktiven Create/Edit/Transition/Snapshot-Aktionen.
- Entity-Scope/RLS muss Property-Cross-Read verhindern; ein `propertyId` aus UI ist kein Autorisierungsbeweis.
- Direktlink ohne `lease.read` zeigt forbidden; ohne `party.read` bleibt Lease lesbar, Party-Profil ist forbidden/degraded ohne Profilmetadaten.
- Permission-Revoke leert betroffene Leasing-/Party-Caches und berechnet Unterbereich-Navigation neu.
- Keine neue Permission oder RLS-Erweiterung in dieser Spec.

## 9. Realtime / freshness behavior

- bestehende permission-scoped leasing invalidation topics wiederverwenden.
- Unit-, Lease-, Case- und Rent-Roll-Events invalidieren nur betroffene Queries; Nutzdaten kommen per REST/RPC.
- Board- oder Listenselektion bleibt bei Hintergrund-Refresh, wenn Record noch vorhanden ist; sonst klarer notFound/removed Zustand.
- Dirty-Form wird nicht überschrieben; Remote-Version-Hinweis und kanonischer Conflict-Flow.
- nach Reconnect genau ein Reconcile je sichtbarer Unterfläche; `NxLiveUpdatesNotice` bei Degraded.

## 10. Screen states

Für jeden Unterbereich: idle/initial loading, background refresh, forbidden, recoverable error, fatal error, empty, no-match, ready und realtime degraded. Zusätzlich:

- Detail notFound/removed
- Read-only bei fehlendem Manage
- action in progress/success/failure
- version conflict mit erhaltenen Eingaben
- partially loaded/paginated mit sichtbarem `Load more`
- Party-profile forbidden bei weiterhin lesbarem Lease
- Rent Roll empty unterscheidet „keine Daten“ von Betrag `0`
- Snapshot-Empty zeigt erlaubte Create-Aktion nur bei `lease.manage`

## 11. Search / filter / sort

- Units: serverseitiger Statusfilter; Sortierung nach Contract stabil; keine Textsuche.
- Leases: vorhandene serverseitige Filter Status, Unit, Tenant und effective; Default klar ausgewiesen.
- Pipeline: `openOnly`, `status` und optional `unitId`; kein Archivefilter. Stage-Reihenfolge folgt `stageRank`, nicht Alphabet oder Clientscore.
- Rent Roll: Live versus Snapshots; Snapshotliste keyset-paginiert, neueste zuerst gemäß Contract.
- Filterzustand bleibt pro Property/Unterbereich; No-match hat Reset.
- URL-Serialisierung später über `SHELL-ROUTING-01`.

## 12. Forms and validation

- Bestehende Unit-, Lease- und Case-DTO-Felder sind alleinige Formquelle; keine Legacy-Felder ohne Contract.
- Pflichtfelder, Datumsreihenfolge, Betrags-/Währungsbezug, Entity-IDs und Statusübergänge spiegeln Servervalidierung.
- Offline/Cancel/sonstige begründungspflichtige Transitions verlangen Reason.
- optimistic version und Mutation-ID sind Pflicht für Update/Transition.
- Dirty-State meldet sich beim Host; Serverfehler bleiben feldnah, Conflict erhält Eingaben.
- Party-Stammdaten werden nicht innerhalb eines Lease-Forms nebenbei editiert.

## 13. Shared components

### Existing components to reuse

- Units-, Leases-, Pipeline- und Rent-Roll-Panels, Controller und DTOs
- Foundation `NxSplitView`, `NxListSkeleton`, `NxNotice`, `NxLiveUpdatesNotice`

### Small extensions needed

- alle Panels auf einheitliche Host-Selektion, Dirty-State und Narrow-Detail-Replacement normalisieren.
- Textsuche ehrlich als Loaded-set-Filter kennzeichnen.
- Tenant-Link capability-aware machen.

### New shared component candidate

- keine Leasing-spezifische Komponente globalisieren; Stage-Board bleibt Domain-Komponente.

## 14. Prerequisites (COMMITTED, prerequisite-first)

Diese Voraussetzungen sind seit FULL-V2-SCOPE-01, 2026-09-04 **COMMITTED**: Sie sind Teil des verbindlichen V2-Zielbildes und werden gebaut — prerequisite-first, unmittelbar gefolgt von der abhängigen Oberfläche und Staging-E2E. Eine fehlende technische Voraussetzung nimmt die Produktfähigkeit **nicht** mehr aus dem Scope; sie bestimmt nur die Reihenfolge. Der Produkt-Scope (COMMITTED) und die technische Bereitschaft (READY / PREREQUISITE REQUIRED) werden getrennt geführt.

- vollständige serverseitige Textsuche für Units/Leases/Cases, falls globales Suchversprechen gewünscht; Schema/RLS separat prüfen.
- serverseitige Lease-Roll- und Vacancy-Exposure-Projektion für Overview: **GELIEFERT** durch `LEASING-SUMMARY-01` (`property_leasing_summary(workspace, property)`, 2026-09-05). Renewal Risk bleibt offen und ist bewusst nicht Teil davon — ein Score braucht einen begründeten Signal-Contract, kein Ablaufdatum.
- explizite indexed rent schedule/renewal option/notice obligation, soweit nicht im aktuellen `LeaseDto`; separater Leasing-Contract, nicht Legacy-Felder imitieren.
- keine Delete-Operationen vorhanden; werden hier nicht gefordert.

## 15. Accessibility and usability

- Listen/Boards vollständig per Tastatur; Stage-Transition braucht Alternative zu Drag-and-drop.
- Tabellenköpfe, Beträge/Währungen und Status semantisch ausgezeichnet.
- Fokus nach Detail-Back auf Ursprungszeile; Dialogfehler fokussieren erstes ungültiges Feld.
- Status/Stage nie nur Farbe; mobile Karten behalten Feldlabels.
- horizontales Desktop-Board besitzt zugängliche Scrollmöglichkeit und sichtbaren Fokus.

## 16. Analytics / audit / history

- sämtliche Mutationen über bestehende auditierte RPCs; keine Client-Audit-Nachbildung.
- Telemetrie darf Surface, Aktionstyp und Ergebnis enthalten, nicht Tenant-Namen, Mietwerte oder Gründe.
- Snapshot zeigt Erstellzeit/Actor soweit Contract autorisiert; unveränderbar.

## 17. Test plan

### Unit/application

- Property-Scope, Filter, Cursor, selection restore, permission split lease/party, conflict und invalidation coalescing.

### Widget/UI

- alle vier Unterflächen in Desktop/Tablet/Mobile; narrow detail replacement, Board stack, mixed currency, empty/no-match/forbidden/degraded.

### Repository/integration

- list/get/mutations bleiben keyset-, version-, idempotency-, audit- und RLS-konform.
- Rent-Roll-Werte werden unverändert gemappt, keine UI-Aggregation.

### Staging E2E

1. Unit erstellen → Leasing Case durch zulässige Stages → Lease öffnen; Property-Kontext bleibt.
2. Lease-Manager ohne `party.read` liest Lease, aber nicht Party-Profil.
3. Read-only-Nutzer kann Listen/Details/Rent Roll lesen, aber keine Mutation/Snapshot auslösen.
4. Mobile Detail-Back stellt Filter, Cursorstand und Fokus wieder her.
5. zweiter Nutzer ändert Case/Lease; Realtime invalidiert einmal, Dirty-Conflict erhält Eingaben.
6. Rent Roll mit zwei Währungen zeigt getrennte Summen und unveränderte Snapshotwerte.

## 18. Acceptance criteria

- Genau vier Unterflächen sind sichtbar und fachlich wie §4 geschnitten.
- Jede Query und Mutation trägt dieselbe Workspace-/Property-ID und wird serverseitig autorisiert.
- Tenant-Stammdaten werden nicht im Property-Datensatz dupliziert.
- Keine Liste behauptet vollständige Textsuche, wenn nur geladene Seiten gefiltert werden.
- Mobile Detailansicht ersetzt Liste und Back restauriert Zustand/Fokus.
- Rent-Roll-Counts/-Totals bleiben servergeliefert; keine KPI wird clientseitig erzeugt.
- Ohne `lease.manage` ist keine Leasingmutation ausführbar; ohne `party.read` leakt kein Party-Profil.
- Realtime ist Invalidation-only und REST/RPC kanonisch.

## 19. Non-Goals (REJECTED) und fremde Zuständigkeit

Ab FULL-V2-SCOPE-01, 2026-09-04 stehen hier **nur noch echte Nicht-Ziele (REJECTED)** sowie Umfänge, die fachlich in eine andere Spec gehören. Alles, was früher wegen Aufwand, fehlendem Backend oder fehlendem Query-Contract hier stand, ist jetzt COMMITTED und mit seiner Voraussetzung in §14 geführt. REJECTED gilt ausschließlich für fremdes Trade Dress und Logos, pixelgenaue Kopien, erfundene KPIs oder Client-Synthese fehlender Serverdaten, unsichere öffentliche Auslieferung und jede Umgehung von AAL/RLS/Entity-Scope.

- globales Tenant-/Party-Verzeichnis redesignen
- Renewal-Risk-AI, Markt-Demand oder Sentiment
- Leasing-Delete, Finance- oder Valuation-Berechnungen
- Client-generierte Lease Roll/Exposure-KPI
- Routerimplementierung

## 20. Open decisions

Keine für das freigegebene Inkrement. Verbindlich entschieden:

- `Verträge & Mieter` bleibt Lease-zentriert. Es gibt keine eingebettete zweite Tenant-Liste; ein autorisierter Link öffnet das workspace-weite Party-/Tenant-Profil.
- Es werden nur die vorhandenen Serverfilter und Contractsortierungen angeboten. Textsuche bleibt aus, statt ein geladenes Teilset als vollständig darzustellen.
- Renewal-, Option- und Notice-Felder sind ein späterer Leasing-Contract und weder UI-Gap noch Voraussetzung dieses Rehosts.

## 21. Implementation handoff

Die vorhandenen Cloud-Panels werden in den Workspace-Host eingebunden, nicht neu geschrieben. Vor Implementierung: Foundation Shared UI und Host-API auf `main`. Kritisch sind die Normalisierung des Narrow-Detail-Verhaltens, ehrliche Loaded-set-Suche, lease/party Permission-Split, unveränderte Rent-Roll-Fakten und keine clientseitigen Overview-Aggregate. Bestehende Controller-/Adaptertests werden um Host-, Responsive-, Deep-link-ready-State- und Staging-Journeys ergänzt.
