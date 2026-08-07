# Welle 4 — `maintenance_capex`

## Backend-Voraussetzungen (erfüllt)

- **P2-D06** (`e80c2fd`, `20260806100000_p2_d06_maintenance_capex.sql` +
  `..._realtime.sql`): `maintenance_tickets` (AGG-008, STM-006) und
  `capex_projects` (AGG-009, STM-007), beide workspace-scoped, default-deny
  RLS, alle Mutationen über auditierte `SECURITY DEFINER`-RPCs. Contractor ist
  die bestehende P2-D02-Party-Rolle (`contractor_party_id`, serverseitig gegen
  eine offene `contractor`-Rolle validiert).
- **P2-D06-Dart-Contract** (`6b91e3a`): `lib/features/maintenance_capex/
  {domain,application,data}`, Supabase- und Legacy-SQLite-Adapter, Realtime-
  Invalidierung, Provider-Wiring, echter Integrationstest.
- **P2-D06-Workspace-Folge-Increment** (`21969a6`, `20260807100000_..._
  workspace_maintenance_tickets.sql`): `public.workspace_maintenance_tickets`
  — die einzige der drei Wellen-4-Flächen, die keinen Einzel-Objekt-Bezug hat
  (SCR-039), brauchte eine eigene RPC, weil `public.maintenance_tickets` einen
  Pflicht-`property_id` verlangt (kein Workspace-weiter Read serverseitig).
  Kein Analogon für CapEx nötig — jede CapEx-Fläche dieser Welle ist
  objektbezogen.

## Architektur-Entscheidung dieser Welle (Nutzerbestätigung 2026-08-07): Cloud-only, kein SQLite-Pfad

Anders als W2 (`04b`, backend-gewählte Contract-Konsumtion mit
read-only-bis-migriert-Zustand im SQLite-Modus) laufen die drei Wellen-4-
Flächen **ausschließlich im Supabase-Modus**. Der bestehende Legacy-SQLite-
Adapter (`legacy_sqlite_maintenance_capex_repository_adapter.dart`) bleibt
Teil des Contracts — er wird von den Adaptertests abgedeckt und ist die
künftige Lesequelle für den Migrations-Dry-Run-Mapper —, aber **kein neuer
Screen dieser Welle konsumiert ihn**. Die vier heutigen Legacy-Screens
(`property_detail/maintenance_screen.dart`, `maintenance/maintenance_screen
.dart`, `maintenance/contractors_screen.dart`, das „Hotel & Maßnahmen"-Tab in
`asset_workbook_screen.dart`) bleiben **unangetastet** und weiterhin die
einzige Fläche im SQLite-Modus — es gibt keinen halb-migrierten Zustand, weil
nichts an ihnen geändert wird.

Praktisch heißt das: kein `read-only-bis-migriert`-Pflichtzustand in dieser
Welle (der Zustand existiert nur, wenn ein Screen beide Backends bedient);
stattdessen sind die drei neuen Panels über additive Cloud-Routen erreichbar,
exakt dem P2-D03/W2-Präzedenzfall folgend (`propertyDocumentsRoute`,
`lib/ui/navigation/app_navigation.dart`) — `SupabaseSecurityGate` mountet sie
direkt in `AppScaffold.cloud(routeTarget:...)`, ohne den SQLite-Zweig von
`app.dart`/`AppScaffold` zu berühren.

## Drei Befunde vor Wellenstart geklärt, nicht still entschieden

1. **SCR-056 RenovationValueScreen existiert nicht mehr.** Wave 5 AP8 hat ihn
   zusammen mit Schnellbewertung/Verkauf entfernt; sein Anliegen
   (Wertwirkung einer Sanierungsmaßnahme) lebt jetzt als
   `ValuationCaseKind.renovation` im Bewertungs-Arbeitsbereich — eine reine
   Wertermittlungsfrage, ohne Budget-/Ist-/Status-Felder, disjunkt von der
   CapEx-Ausführungsverfolgung dieser Welle. Diese Welle ist damit **vier
   Screens, nicht fünf**, und für SCR-056 gibt es nichts zu bauen.
2. **SCR-034 (Objekt-Wartungs-Tab) und SCR-031 (Sanierungshälfte von
   AssetWorkbookScreen) sind eine Fläche, keine zwei.** Beide sind
   objektbezogene Sichten auf dieselben zwei Aggregate. Ein Panel mit zwei
   Tabs (Tickets / CapEx-Projekte) hinter einer Route deckt beide, statt zwei
   fast identische Panels zu bauen. Der riesige `AssetWorkbookScreen` selbst
   (2274 LOC, vier fachfremde Tabs) bleibt unangetastet — nur seine
   Sanierungshälfte bekommt eine Cloud-Entsprechung.
3. **SCR-039 (Portfolio-weite Wartungsliste) hatte kein Backend.** Siehe
   „Backend-Voraussetzungen" oben — mit Nutzerbestätigung durch die neue
   `workspace_maintenance_tickets`-RPC geschlossen, statt eines client-
   seitigen Fan-outs über jede Immobilie (das exakte N+1-Muster, das P2-D03s
   Workspace-Requirements-RPC schon einmal verworfen hat).

## Scope

Drei Panels, drei Controller, ein neuer Contractor-Rollen-Controller nach dem
`tenants_controller.dart`-Muster, additive Routing-Änderungen. Kein neuer
Backend abgesehen vom oben genannten Folge-Increment; SCR-040 (Contractors)
braucht laut ursprünglichem Auftrag ohnehin keinen — er ist reine
Party-/Rollen-Verwaltung auf dem bestehenden P2-D02-Contract.

## Reihenfolge und Begründung

1. **Arbeitspaket 0 — Routing-Grundlage** (kein Screen): neue Route
   `propertyMaintenanceRoute` (+ `..RouteFor(propertyId)`/Parser, Muster
   `propertyDocumentsRoute`); `GlobalPage.maintenance`/`GlobalPage.contractors`
   in `cloudReadinessForPage`s `ready`-Menge aufnehmen (heute `
   migrationRequired`, obwohl `cloudReadPermissionForPage` für beide schon
   eine Berechtigung nennt); `AppScaffold`s Cloud-Switch um die drei neuen
   Fälle erweitern. Ohne dieses Fundament ist keines der drei Panels
   erreichbar.
2. **ContractorsPanel (SCR-040)** — kein neuer Backend, geringste Komplexität,
   Pattern-Beweis für den `tenants_controller.dart`-Kompositionsstil mit
   `PartyRoleType.contractor` statt `.tenant`.
3. **MaintenanceTicketsPanel (SCR-039)** — konsumiert die neue Workspace-RPC
   direkt, keine Objekt-Navigation nötig.
4. **PropertyMaintenanceCapexPanel (SCR-034 + SCR-031)** — objektbezogen,
   braucht die Routing-Grundlage aus AP0 plus beide Suchports
   (`MaintenanceTicketSearchPort`/`CapexProjectSearchPort`).

## Arbeitspaket 0 — Routing-Grundlage (Voraussetzung, kein Screen)

**Kein Sechs-Punkte-Plan (keine UI).** In `lib/ui/navigation/app_navigation.dart`:
`const propertyMaintenanceRoute = '/property-maintenance';` +
`propertyMaintenanceRouteFor(propertyId)` + Parser (Muster `_idFromRoute`,
zwei Pfadsegmente); ein neuer `CloudRouteSurface`-Wert falls das Panel als
Unteroberfläche von `GlobalPage.properties` modelliert wird, sonst ein
eigener `GlobalPage`-Wert — Entscheidung fällt beim Implementieren anhand
dessen, wie `PropertyDocumentsPanel` es tatsächlich macht (Ist-Audit vor
Code, nicht Annahme). `cloudReadinessForPage`: `GlobalPage.maintenance` und
`GlobalPage.contractors` von `migrationRequired` in die `ready`-Menge heben.
`AppScaffold`s Cloud-Switch: drei neue Fälle, die die drei Panels direkt
mounten. Verifikation: `flutter analyze` sauber, ein schlanker
Routing-Test (Name → `CloudRouteTarget`, Rundreise für die neue
objektbezogene Route) — keine Screen-Tests hier.

## MaintenanceTicketsPanel (SCR-039)

1. **Zielbild**: Portfolio-weite Wartungsliste — jedes Ticket jeder Immobilie
   auf einen Blick, mit Status/Priorität/Objekt-Filter und direktem Absprung
   zum Objekt. Ersetzt die heutige `ListFilterTemplate`-Fläche (2899 LOC,
   6 Hilfswidgets, `rentRollRepositoryProvider`/`tasksRepositoryProvider`/…
   direkt gegen SQLite) durch eine schlanke, contractgeführte Sicht.
2. **Layout**: `NxPageHeader` (Titel „Wartung", Primäraktion „Ticket
   anlegen"); `NxDataTableShell` mit `MaintenanceTicketSummaryDto`-Spalten
   (Objekt-Name aufgelöst über die bekannte Objektliste, Titel, Status als
   `NxStatusBadge` über die STM-006-Abbildung, Priorität, fällig am, Kosten).
   Status-/Prioritäts-Filter als Header-Aktionen. Phone: horizontal
   scrollbar, Titelspalte gepinnt.
3. **States**: loading = Tabellen-Skeleton; empty = `NxEmptyState` „Keine
   offenen Tickets"; error = Retry ohne Roh-Exception; **forbidden** =
   explizit (`MaintenanceCapexRepositoryFailureKind.forbidden` — die
   Workspace-RPC antwortet das für fehlendes `maintenance.read`, anders als
   eine RLS-gefilterte Leseabfrage, die still leer bliebe); **versionConflict**
   = Konfliktdialog mit dem aktuellen Ticket aus `MaintenanceCapexVersionConflict
   .currentTicket`, Auflösen-Aktion. Kein read-only-Zustand (Cloud-only).
4. **Data density**: `maintenanceTicketSearchProvider.searchWorkspace(
   WorkspaceMaintenanceTicketListQuery)` — eine Abfrage, keine Objekt-Schleife.
   Objekt-Namen kommen aus der bestehenden `referenceSliceControllerProvider
   .properties`-Liste (bereits geladen für den Cloud-Host), kein neuer Read.
5. **Interactions**: Ticket anlegen (`MaintenanceTicketDraft`, Objekt-Auswahl
   Pflichtfeld — die Workspace-RPC liest, aber `create_maintenance_ticket`
   bleibt objektbezogen); Statusübergänge entlang STM-006 (inkl. der einen
   Reopen-Kante `resolved`→`in_progress`) über `TransitionMaintenanceTicketStatusCommand`,
   nur die vom Contract erlaubten Ziele anbieten (`allowedNextStatuses`);
   Contractor-Zuweisung über eine Party-Auswahl mit `roleType: contractor`
   (kein eigener Picker-Screen, Inline-Suche im Dialog).
6. **Debt resolved**: löst die heutige direkte SQLite-Repo-Kopplung für die
   Portfolio-Ansicht auf; erster contractgeführter Zustandssatz für dieses
   Aggregat (heute: Vollflächen-Spinner, kein `forbidden`/`versionConflict`).
   Widget-Test über alle Zustände + Responsive an 390/1024/1440.

## ContractorsPanel (SCR-040)

1. **Zielbild**: Dienstleister-Verzeichnis als Rollen-Sicht auf das
   P2-D02-Parteien-Verzeichnis — eine Partei mit offener `contractor`-Rolle,
   nicht die heutige eigenständige `ContractorRecord`-Tabelle (String-Abgleich
   `vendorName == companyName`, keine echte Verknüpfung zu Tickets). Löst
   damit strukturell dieselbe Identitätszersplitterung, die P2-D02 für
   Mieter/Kontakte schon gelöst hat.
2. **Layout**: Master/Detail wie das heutige `ContractorsScreen`, aber auf
   `NxDataTableShell`/`NxPageHeader` statt `ListTile`/`AlertDialog`: Liste
   (Firma/Name, Gewerk, Satz, Bewertung als `NxStatusBadge`/Sterne), Detail
   (`ContractorDetailsDto`: Gewerk, Satz, Einsatzgebiet, fünf Bewertungs-
   dimensionen, Versicherungsablauf). Responsive wie das Original (Phone
   Liste→Detail-Push, Tablet gestapelt, Desktop 4:6-Split).
3. **States**: loading/empty/error wie oben; **forbidden** (`party.read`
   fehlt); **versionConflict** bei gleichzeitigem Bearbeiten von Partei oder
   Rolle (`PartyVersionConflict`). Kein read-only-Zustand.
4. **Data density**: `partySearchProvider.search(PartyListQuery(roleType:
   PartyRoleType.contractor))`, `partyRoleProvider.getContractorDetails`.
   Kein Zugriff auf `maintenance_capex` in dieser Welle — Ticket-/Projekt-
   Historie je Contractor ist explizit **nicht** Teil dieses Panels (der
   ursprüngliche Auftrag nennt für SCR-040 nur den P2-D02-Contract; eine
   Cross-Referenz bräuchte die Workspace-RPC gefiltert nach
   `contractor_party_id`, die es nicht gibt — spätere Erweiterung, kein
   Nachtrag hier).
5. **Interactions**: Partei anlegen + `contractor`-Rolle zuweisen (zwei
   Commands, nicht einer — exaktes `tenants_controller.dart`-Muster:
   `_partyRepository.create` dann `_partyRoles.assign`, eigener
   `partiallyApplied`-Zustand, falls der zweite Schritt scheitert); Rolle
   bearbeiten (`ContractorDetailsInput`, Bewertungen); Rolle **beenden**
   (`PartyRoleRepository.end`), nie die Partei löschen.
6. **Debt resolved**: löst die undokumentierte String-Kopplung
   `vendorName == companyName` strukturell auf (kein Ersatz dafür in dieser
   Welle nötig — `contractor_party_id` ist bereits eine echte FK). Neuer
   `ContractorsController` nach `tenants_controller.dart`-Vorbild. Widget-Test
   über alle Zustände inkl. `partiallyApplied`.

## PropertyMaintenanceCapexPanel (SCR-034 + SCR-031)

1. **Zielbild**: Ein objektbezogenes Panel, zwei Tabs — „Tickets" (heutiges
   SCR-034) und „CapEx-Projekte" (heutige Sanierungshälfte von SCR-031).
   Ersetzt zwei getrennte, stark redundante Legacy-Flächen (SCR-034: 3915
   LOC/6 Hilfswidgets; SCR-031s Sanierungs-Abschnitt: ~60 Zeilen roher
   `DataTable` ohne Bearbeiten-Pfad, nur Anlegen/Löschen) durch eine.
2. **Layout**: `NxPageHeader` (Objektname im Titel, Tab-Umschalter als
   `TabBar` unter dem Header, je Tab eine Primäraktion). Tickets-Tab:
   `NxDataTableShell` wie im Workspace-Panel, ohne Objekt-Spalte, mit
   Status-/Prioritäts-/Einheit-Filtern. CapEx-Tab: `NxDataTableShell`
   (Projektcode, Kategorie, Status als `NxStatusBadge` über die STM-007-
   Abbildung, Budget/Ist/Abweichung, geplantes Ende). Erreichbar über
   `propertyMaintenanceRouteFor(propertyId)`.
3. **States**: je Tab unabhängig ladbar (ein Tab-Fehler blockiert den
   anderen nicht — Muster `PropertyDocumentsController`s pro-Zone-Phasen);
   loading/empty/error/forbidden wie oben, je Tab; **versionConflict** trägt
   `currentTicket` bzw. `currentProject`, nie beide. CapEx-Tab zusätzlich:
   **eigener `forbidden`-Zustand für die `approved`-Aktion**
   (`capex.approve` ist eine eigene Berechtigung, getrennt von `capex.manage`
   — die Freigabe-Aktion ist sichtbar, aber deaktiviert mit Erklärung, wenn
   sie fehlt, statt sie zu verstecken).
4. **Data density**: `maintenanceTicketSearchProvider.search`/
   `capexProjectSearchProvider.search` (beide objektbezogen, `propertyId`
   aus der Route, nicht aus Reference-Slice-State — Objekt-IDs kommen dort
   grundsätzlich aus der Route, siehe `PropertyDocumentsPanel`-Präzedenz).
5. **Interactions**: Tickets-Tab wie im Workspace-Panel. CapEx-Tab:
   Projekt anlegen (`CapexProjectDraft`), STM-007-Übergänge strikt linear
   (`nextStatus`, keine Zielauswahl über das eine erlaubte Ziel hinaus),
   Freigabe-Übergang (`approved`) nur mit sichtbarer Berechtigungsprüfung,
   Ist-Betrag nur eingebbar, wenn das Projekt schon eine Währung trägt
   (serverseitige Regel client-seitig gespiegelt, nicht neu erfunden).
6. **Debt resolved**: SCR-031s CapEx-Bearbeiten-Lücke (heute nur Anlegen/
   Löschen, kein Status, kein Contractor) schließt sich strukturell, weil der
   Contract das von Anfang an trägt. Zwei redundante Legacy-Flächen werden
   durch eine ersetzt (die Legacy-Flächen selbst bleiben unangetastet, siehe
   Architektur-Entscheidung oben — dies ist Konsolidierung im neuen Contract,
   keine Löschung im alten). Widget-Test über alle Zustände beider Tabs +
   Responsive.

## Querschnittsthemen der Welle

- **Cloud-only**: kein Screen dieser Welle liest einen Legacy-`maintenance_capex`-Provider; der Legacy-Adapter bleibt ausschließlich Adaptertest-/künftige-Migrations-Infrastruktur. Kein `read-only-bis-migriert`-Zustand in dieser Welle.
- **Geteilte STM-006/STM-007-Badge-Abbildung**: beide Ticket-Flächen (Workspace- und Objekt-Panel) und die CapEx-Fläche teilen eine `NxStatusBadge`-Abbildung je Zustandsmaschine — einmal gebaut, dreifach genutzt (Muster `DUP-007`s Dokument-Badges aus W2).
- **`capex.approve` sichtbar getrennt**: überall, wo ein CapEx-Übergang nach `approved` angeboten wird, ist die Berechtigungsprüfung eigenständig und sichtbar — nie in `capex.manage` versteckt.
- **Contractor-Auswahl ohne neuen Picker-Screen**: jede Stelle, die einen Contractor zuweist (Ticket-/Projekt-Dialoge), nutzt eine Inline-Party-Suche mit `roleType: contractor` — kein eigenständiger Auswahl-Screen, kein neuer Provider jenseits des bestehenden `partySearchProvider`.
- **Pflicht-Zustände vollständig** (`forbidden`/`versionConflict` echte, testpflichtige Fälle — beide Aggregate sind mutierend und versioniert).
- **Nicht in W4** (bewusst): Migration der vier Legacy-Screens selbst; tatsächlicher Migrationslauf des (noch nicht gebauten) Dry-Run-Mappers; Contractor-Ticket-Historie im ContractorsPanel (s. o.); ein workspace-weites CapEx-Panel (kein Auftrag, keine RPC).

## Definition of done

**Je Panel:** Sechs-Punkte-Plan im Chat gezeigt → Umsetzung gegen den
Feature-Contract → `flutter analyze --no-pub` sauber → gezielte Widget-Tests
grün (inkl. `forbidden`/`versionConflict`) → Responsive-Check an
390×844 / 1024×768 / 1440×900 → manueller Golden-Path im laufenden
App-Build (Cloud-Modus) → `00_phase_2_status.md` evidenzbasiert
fortgeschrieben. Volle Suite (`flutter test --no-pub`) mindestens am Ende
jedes Arbeitspakets.

**Wellenabschluss:** AP0 + alle drei Panels `done`; kein neuer Code liest
einen Legacy-`maintenance_capex`-Provider; volle Suite + analyze grün;
Zusammenfassung an den Nutzer.
