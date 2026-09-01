# Property Operations V2

## Metadata

- Package / screen ID: `PROPERTY-WORKSPACE-01` / `PROPERTY-OPERATIONS-V2`
- Domain: Maintenance, CapEx, Platform Tasks
- Route: zukünftige Ziele `/properties/:propertyId/operations/maintenance`, `/capex`, `/tasks`; heute property-scoped Panels
- Current implementation file(s): `lib/ui/screens/property_detail/property_maintenance_capex_panel.dart`, `lib/features/maintenance_capex/application/property_maintenance_capex_controller.dart`, `lib/features/maintenance_capex/application/maintenance_capex_repository.dart`, `lib/features/platform_audit_jobs/application/platform_repository.dart`, `lib/features/platform_audit_jobs/domain/task_dto.dart`
- Planning status: APPROVED (Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Workspace V2](PROPERTY_WORKSPACE_V2.md), `UX-FOUNDATION-IMPL-01`, bestehende Pakete `MAINTENANCE-PARITY-01` und `TASKS-NOTIFICATIONS-01`
- Related screens: [Property Overview V2](PROPERTY_OVERVIEW_V2.md), [Property Documents V2](PROPERTY_DOCUMENTS_V2.md), [Property Activity & Reports V2](PROPERTY_ACTIVITY_REPORTS_V2.md)

## 1. Purpose

`Betrieb` bündelt die ausführbare Arbeit an einem Property: Wartungstickets, CapEx-Projekte und property-scoped Aufgaben. Es verbindet Maßnahmen über Entity-Referenzen, ohne Maintenance, CapEx und Tasks in ein gemeinsames Datenmodell zu pressen. Die Overview-Fläche zeigt Aufmerksamkeit; dieser Screen ist der Ort für Listen, Details, Bearbeitung und Lifecycle.

## 2. Primary users and jobs

| Rolle | Job | Zuerst benötigt | Aktion |
|---|---|---|---|
| Property Manager | Störungen und geplante Arbeit steuern | Ticketstatus, Priorität, Fälligkeit, Verantwortlicher | Ticket erstellen/editieren/transitionieren |
| Asset Manager | CapEx, Forecast und Freigaben beurteilen | Projektstatus, Budget/Forecast/Actual, Zeitraum, Owner, Approval | Projekt pflegen oder freigeben |
| Team Lead | property-bezogene Aufgaben koordinieren | offene Aufgaben, Assignee, Due, Quelle | Aufgabe erstellen/zuweisen/transitionieren |
| Auditor / Read-only | Maßnahme und Status nachvollziehen | kanonischer Datensatz, Zeit/Actor soweit verfügbar | Dokument/Audit öffnen |

## 3. Entry points and navigation

- Property Workspace → `Betrieb` → `Wartung`, `CapEx`, `Aufgaben`.
- Overview-Attention oder Operations Signal öffnet den verantwortlichen Datensatz oder gefilterten Unterbereich.
- Dokument-/Task-Links wechseln in die entsprechende Property-Domain und erhalten die auslösende Entity-Referenz für Back.
- Filter, Scroll und Selektion bleiben je Unterbereich erhalten; Property-Wechsel entfernt Entity-Selektion.
- Route-/Browser-History bleibt bei `SHELL-ROUTING-01`.

## 4. Information architecture

### Wartung

1. serverseitige Filter `status`, `priority` und optional `unitId`
2. Ticketliste mit Titel, Status, Priorität, Fälligkeit und Verantwortungs-/Kostenindikatoren nur aus DTO
3. Ticketdetail mit Beschreibung, Lifecycle, Kosten, Unit-, Contractor- und Insurance-Kontext aus `MaintenanceTicketDto`
4. Create/Edit/Transition

### CapEx

1. serverseitiger Statusfilter
2. Projektliste mit Status, Budget/Forecast/Actual plus Währung, Zeitraum, Owner
3. Projektdetail einschließlich Approval-Information
4. Create/Edit/Transition/Approve capability-gated

### Aufgaben

1. property-scoped Task-Liste, standardmäßig neueste Aktualisierung gemäß Contract
2. serverseitige Filter `status`, `assignedTo` und `includeArchived`
3. Taskdetail mit Entity-Quelle
4. Create/Edit/Assign/Transition

## 5. Layout and interaction model

### Desktop

- drei Unterbereiche, jeweils Liste/Detail über `NxSplitView` 3:2.
- Filterleiste oberhalb der Liste; Hauptaktion klar im Bereichsheader.
- Beträge als beschriftete Felder, nicht als unkommentierte KPI-Tiles.

### Tablet/Mobile

- Detail ersetzt Liste; Back restauriert Filter, Scroll und Fokus.
- Tabellen werden Fact Cards; Status/Priorität/Fälligkeit zuerst.
- Formulare einspaltig, lange Beschreibungen und Währungsfelder ohne Overflow.
- Approval/Statusaktionen als zugängliches Menü oder klarer Button, nie nur Swipe.

## 6. Functional requirements

### Wartungsticket

- Property-scoped list/get.
- Create/Edit/zulässige Status-Transition bei `maintenance.manage`, versioniert und auditiert.
- Alle im aktuellen Ticket-DTO vorhandenen fachlichen Felder müssen im Detail sichtbar sein; Editfelder werden in `MAINTENANCE-PARITY-01` gegen den Contract gedifft.
- Delete wird nicht angeboten, solange der Cloud-Contract fehlt.

### CapEx-Projekt

- Property-scoped list/get.
- Create/Edit/zulässige Lifecycle-Transitions bei `capex.manage`.
- Eintritt in `approved` benötigt zusätzlich `capex.approve`; andere zulässige Ziele bleiben nach Contract getrennt.
- Budget, Forecast und Actual zeigen immer gespeicherte Währung. Die heutige UI-Hardcodierung `EUR` ist zu entfernen, nicht als Contract zu behandeln.
- Kein Delete.

### Property-Aufgabe

- `TaskRepository.searchTasks` mit `TaskListQuery.entity = PlatformEntityRef(property, propertyId)`, keyset-paginiert.
- Create setzt Property-Entity-Referenz fest; Edit/Assign/Transition nur via `task.manage`.
- Generierte Tasks werden gekennzeichnet, nicht im Client rekonstruiert.
- Legacy Checklist, estimated cost und Delete sind nicht Teil des Cloud-Contracts und erscheinen nicht.

### Beziehungen öffnen

- Das freigegebene erste Inkrement zeigt unter `Aufgaben` ausschließlich Tasks mit `entityType=property` und `entityId=propertyId`.
- Ticket-/CapEx-spezifische Task-Zusammenführung, Dokumentlinks und Cross-Domain-Linkmutationen sind nicht Teil dieses Inkrements. Der heutige Document-Contract weist Maintenance-/CapEx-Entitytypen noch nicht als migrierte Linkziele aus.
- Contractor-Referenzen bleiben IDs beziehungsweise autorisierte Party-Drilldowns nur dort, wo der bestehende Contract und `party.read` dies bereits tragen.

## 7. Data requirements

| Bereich | Quelle | Werte | Beziehung |
|---|---|---|---|
| Ticket | `MaintenanceTicketDto`, `MaintenanceTicketRepository`/`MaintenanceTicketSearchPort` | Property-ID, Titel/Beschreibung, Status, Priorität, Due, Kosten, Contractor-/Insurance-Felder, Version/Auditzeiten | Property; optional Unit/Contractor-Party |
| CapEx | `CapexProjectDto`, `CapexProjectRepository`/`CapexProjectSearchPort` | Property-ID, projectCode, category/measure, Status, Budget/Forecast/Actual + Currency, Start/End, Owner/nextStep, Approval-Actor/-Zeit, Version | Property; optional Contractor-Party |
| Task | `TaskDto`, `TaskRepository` | title, status, priority, entityType/id, assignee, dueAt, generated, timestamps/version | Property oder referenzierte Operational Entity |
| Signal | Operations Signals | serverseitiger type/severity/reason/entityRef | primär Overview; Drilldown hier |

Summen, Overdue-Counts, Budgetvarianten und Forecast-Abweichungen sind nur zulässig, wenn ein Server-Contract sie explizit liefert. Ein Betrag ohne Currency wird als unvollständig markiert, nicht als EUR interpretiert.

## 8. Permissions and security behavior

- Host: `property.read`.
- Wartung read/manage: `maintenance.read` / `maintenance.manage`.
- CapEx read/manage/approve: `capex.read` / `capex.manage` / `capex.approve`.
- Aufgaben read/manage: `task.read` / `task.manage`.
- Verknüpfte Dokumente: `document.read`; Dokumentmutation zusätzlich `document.manage`.
- Unterbereiche ohne Read sind aus Navigation verborgen; Direktzugriff forbidden.
- Approval-Control erscheint nur bei `capex.approve` und passendem Contractstatus; Server prüft unabhängig.
- Permission-Revoke entfernt Domaincache; laufender Submit wird serverseitig autorisiert/abgelehnt.
- Keine neue Permission/RLS/Schemaannahme.

## 9. Realtime / freshness behavior

- Maintenance-, CapEx- und Task-Invalidierungen bleiben getrennt und permission-scoped.
- sichtbare Liste/Detail wird nach Event kanonisch nachgelesen; keine Eventpayload-Daten anwenden.
- Dirty-Form bleibt unverändert und zeigt Remote-Version-Konflikt.
- Reconnect: ein Reconcile pro sichtbarem Unterbereich, nicht alle drei und nicht Overview zusätzlich mehrfach.
- Degraded-Hinweis je Domain; bestehende Daten bleiben mit `asOf`/Updatezeit sichtbar.

## 10. Screen states

Je Unterbereich: initial loading, background refresh, empty, populated, partial, no-match, recoverable error, fatal error, forbidden, read-only, realtime degraded, action progress/success/failure, conflict und detail notFound.

Spezifisch:

- CapEx ohne Currency: incomplete-data Notice am Betrag.
- Approval forbidden: keine Approval-Daten/Action über Capability hinaus.
- Task-Relationship unavailable: Operational Record bleibt nutzbar, Taskzone degradiert.
- Cross-domain partial success: erfolgreicher Hauptrecord bleibt sichtbar; fehlgeschlagener Link/Create erhält eigene Recovery-Aktion und Audit-/Mutation-ID-Kontext ohne Secret.

## 11. Search / filter / sort

- Nur serverseitig vom jeweiligen Repository unterstützte Filter werden als vollständige Filter angeboten.
- Clientfilter über eine vollständig geladene, unpaginierte Propertyliste darf klar lokal sein; bei paginierten Tasks ist Loaded-set-Suche entsprechend zu kennzeichnen.
- Defaultsortierung muss stabil und fachlich benannt sein, zum Beispiel vom Contract gelieferte Aktualisierungsreihenfolge; kein versteckter Client-Risk-Score.
- Filter bleiben je Property/Unterbereich; No-match bietet Reset.

## 12. Forms and validation

- Formfelder werden vor Implementierung vollständig gegen aktuelle Ticket-/CapEx-/Task-DTOs gedifft; weder Legacy-Felder noch fehlende DTO-Felder still weglassen.
- Pflicht, Enum, Datum, Betrag, Currency, Statusübergang und Reason spiegeln Servervalidierung.
- Beträge werden als Decimal/Minor-unit gemäß Contract behandelt, niemals über binäre Float-Formeln aggregiert.
- `approved` ist kein frei wählbarer Status ohne Permission/Transition.
- Entity-Referenz einer Property-Aufgabe ist im Create-Kontext read-only.
- optimistic version, Mutation-ID, Dirty-Guard und Conflict-Erhalt sind Pflicht.

## 13. Shared components

### Existing components to reuse

- bestehendes Property Maintenance/CapEx Panel und Controller als Contract-/State-Basis
- `TaskRepository` und `TaskDto`; Foundation `NxSplitView`, `NxListSkeleton`, `NxNotice`, `NxLiveUpdatesNotice`

### Small extensions needed

- Maintenance-/CapEx-Formulare auf vollständige DTO-Parität und gespeicherte Currency bringen.
- property-scoped Task-Panel auf vorhandenem Task-Contract.
- capability-aware Entity-Link-Zeile für Documents/Tasks.

### New shared component candidate

- keine neue Board-Plattform im Workspace-Paket; ein späteres gemeinsames Entity-Link-Widget nur im zugehörigen Shared-UI-Paket.

## 14. Backend gaps

- `MAINTENANCE-PARITY-01` muss Edit/Delete/Document-/Task-Links/Filter/Notifications gegen den aktuellen Cloud-Contract diffen; Delete ist heute nicht vorhanden und darf nicht als UI-only geplant werden.
- serverseitige Overview-Aggregate/Priorisierung für Tickets, CapEx und Tasks: `PROPERTY-OVERVIEW-DATA-01`.
- Ein späterer gemeinsamer Property-Work-Read für direkte Property- sowie Ticket-/CapEx-Tasks wäre ein separates Query-Contract-Inkrement; der aktuelle Screen behauptet diese Zusammenführung nicht.
- keine Schema/RLS/Permission-Erweiterung wird vorausgesetzt; jede benötigte Änderung ist im jeweiligen Backend-Paket explizit zu entscheiden.

## 15. Accessibility and usability

- Status/Priorität/Approval immer mit Text; Beträge mit Currency in zugänglichem Namen.
- Listen/Details und Actions vollständig per Tastatur; Fokus nach Back und Submit deterministisch.
- Formfehler verknüpft, Due-Dates mit eindeutiger Zeitzone/Datumssemantik.
- destruktive Aktion ist derzeit nicht vorhanden; keine missverständliche „Entfernen“-UI.
- mobile Karten behalten Feldlabels und Touch-Zielgrößen.

## 16. Analytics / audit / history

- Domainmutationen ausschließlich über auditierte RPCs; Actor/Mutation-ID nicht als frei editierbare Felder.
- Telemetrie ohne Beschreibungen, Contractor-/Insurance-Details, Beträge oder Assignee-Personendaten.
- Audit-Verlauf wird über Activity/Audit angezeigt, sobald `AUDIT-01` existiert.

## 17. Test plan

### Unit/application

- Permission-Matrix inklusive separatem CapEx-Approve, DTO/Form-Parität, Currency, Conflict, Entity-Refs, keyset Tasks.

### Widget/UI

- alle drei Unterbereiche und Zustände; Desktop/Tablet/Mobile; lange Texte/Beträge; keine EUR-Hardcodierung; mixed permission.

### Repository/integration

- property-/workspace-scope, version/idempotency/audit, no delete; Cross-Domain-Links permission-gefiltert.

### Staging E2E

1. Maintenance-Manager erstellt und transitioniert Ticket, ohne CapEx-Rechte zu erhalten.
2. CapEx-Manager editiert Projekt; ohne `capex.approve` keine Approval-Aktion, Approver kann freigeben.
3. Property-Task wird erstellt/zugewiesen/transitioniert und bleibt im Property-Kontext.
4. Nutzer ohne `document.read` sieht keine verknüpften Dokumentmetadaten.
5. Mobile Detail-Back und Realtime-Conflict erhalten Zustand/Eingaben.
6. CapEx in Nicht-EUR-Währung bleibt auf Liste, Detail und Readback unverändert.

## 18. Acceptance criteria

- Wartung, CapEx und Aufgaben sind getrennte Unterflächen mit eigener Read-/Manage-Grenze.
- `capex.approve` wird separat von `capex.manage` geprüft und gerendert.
- Kein Betrag erhält eine clientseitig hardcodierte Währung.
- Kein Delete, Checklist oder estimated cost erscheint ohne Cloud-Contract.
- Formulare decken genehmigte DTO-Felder ab oder markieren einen expliziten Backend/UI-Gap.
- Mixed-Permission-Nutzer verlieren nicht die gesamte Operations-Domain, wenn nur ein Unterbereich forbidden ist.
- Mobile Detail ersetzt Liste und Back restauriert Zustand/Fokus.
- Realtime bleibt invalidation-only und überschreibt keine Dirty-Form.

## 19. Out of scope

- Facility-/IoT-System, Vendor Portal und präventive AI
- Client-Portfolioaggregation und KPI-Scores
- Maintenance-/CapEx-/Task-Delete ohne Contract
- Legacy Checklist/Kostenmodell für Tasks
- Notification Center redesign und Routerimplementierung

## 20. Open decisions

Keine für das freigegebene Inkrement. Verbindlich entschieden:

- `MAINTENANCE-PARITY-01` deckt Create, Read, Update und vorhandene Statusübergänge für alle DTO-/RPC-Felder ab. Delete, Benachrichtigungen und Document-/Cross-Domain-Links sind ausgeschlossen.
- Property-Tasks nutzen exakt `status`, `assignedTo`, `includeArchived` und Keyset-Pagination; kein Priority-/Generated-Vollfilterversprechen.
- Kosten-, Contractor- und Insurance-Felder sind gemäß `MaintenanceTicketDraft`/`MaintenanceTicketUpdateDto` beziehungsweise `CapexProjectDraft`/`CapexProjectUpdateDto` editierbar. Die aktuelle RPC-Semantik kann nullable Maintenance-/CapEx-Felder nicht wieder leeren; die UI muss diese Grenze erklären und darf kein erfolgreiches Clear vortäuschen.

## 21. Implementation handoff

Maintenance/CapEx und Property-Tasks können nach Workspace-Host parallel integriert werden, bleiben aber in ihren bestehenden Tracker-Paketen. Vor Codeänderung ist ein DTO/RPC/UI-Paritätsdiff Pflicht. Das erste Inkrement baut keine Cross-Domain-Linkschicht. Hard invariants: separate Permissions, Currency aus Daten, keine Delete-Attrappe, Entity-Scope, versionierte auditierte Mutationen und ehrliche Null-Clear-Grenze. Erforderlich sind bestehende Repositorytests plus neue Property-Task-, Approve-, Currency-, Host-/Responsive- und sechs Staging-Journeys.
