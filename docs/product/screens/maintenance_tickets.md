# MAINTENANCE TICKETS (Instandhaltung, workspace-weit)

## Metadata

- Package / screen ID: **MAINTENANCE-V2** — implementiert als `MAINTENANCE-PARITY-01` (Tracker Wave 2); Screen Map §1 „Maintenance Tickets" (die ID `SCR-039` stammt aus `04d_wave4_maintenance_capex.md` / `01_system_inventory.md`, nicht aus der Screen Map)
- Domain: `maintenance_capex`
- Route: `GlobalPage.maintenance`, Sidebar *Tagesgeschaeft › Instandhaltung* (`app_navigation.dart:456-462`); gemountet in `app_scaffold.dart:360-361`
- Current implementation file(s):
  - UI: `lib/ui/screens/maintenance/maintenance_tickets_panel.dart` (525 LOC)
  - Badges: `lib/ui/screens/maintenance/widgets/maintenance_capex_badges.dart`
  - Controller: `lib/features/maintenance_capex/application/maintenance_tickets_controller.dart`
  - Contract: `lib/features/maintenance_capex/application/maintenance_capex_repository.dart`
  - DTOs: `lib/features/maintenance_capex/domain/maintenance_ticket_dto.dart`
  - Adapter: `lib/features/maintenance_capex/data/supabase_maintenance_capex_repository_adapter.dart`
  - SQL: `supabase/migrations/20260806100000_p2_d06_maintenance_capex.sql`, `20260807100000_p2_d06_workspace_maintenance_tickets.sql`, `20260812100000_security_aal_enforcement.sql`
  - Legacy-Quelle für den Parity-Harvest (laufzeit-tot): `lib/ui/screens/maintenance/maintenance_screen.dart` (2899 LOC)
- Planning status: **APPROVED (Flows) / BLOCKED (Lesepfad dieser Fläche)** — Final-Approval-Review 2026-08-28; alle vier zuvor offenen Entscheidungen sind in §20 verbindlich geschlossen. Statusabgrenzung und Dependency-Matrix: §22
- Basis: `origin/main` `3a11b09` (neu gefetcht und verifiziert, 2026-08-28). Enthält gegenüber der ersten Planungsrunde (`46effab`): `UX-FOUNDATION-IMPL-01` implementiert (`791849f`, PR #43) und `ADMIN-MEMBERS-V2` spec_approved (`de8e979`, PR #42) samt Foundation-Amendment **AMD-001**
- Dependencies: `UX-FOUNDATION-IMPL-01` — **erledigt, liegt auf `main`** · `MAINTENANCE-QUERY-01` (blockiert den Lesepfad dieser Fläche, §20-D1) · `REALTIME-DEGRADED-WIRING-01` · nicht blockierend: `PERMISSION-CATALOG-02` (blockiert nur die Non-Admin-Staging-E2E)
- Related screens: `property_maintenance_capex.md` (objektbezogene Schwesterfläche, gleiche Domäne) · Contractors (SCR-040) · Documents Workspace · Tasks (`TASKS-NOTIFICATIONS-01`)

**Sprachregel dieses Dokuments:** Abschnittstitel Englisch (Template-Vergleichbarkeit), Fließtext Deutsch (Präzedenz: `PRODUCT_SCREEN_MAP.md`, `PRODUCT_RESTORE_TRACKER.md`). Bezeichner, Keys, Status-Vokabular und Berechtigungsnamen bleiben Englisch (Foundation §19).

---

# A. PlanRadar benchmark

Recherchiert an offizieller PlanRadar-Dokumentation (help.planradar.com), Produktseiten und Preisseite, Stand August 2026. Quellen am Ende dieses Abschnitts. „Dokumentiert" = wörtlich in offizieller Doku belegt; „abgeleitet" = aus vollständiger Abwesenheit jeder Konfigurationsdoku geschlossen.

## A.1 Die eine Architekturentscheidung

PlanRadar kennt **kein** separates Work-Order-, Asset-, Wartungsplan- oder Inspektionsobjekt. Es gibt genau ein Arbeitsobjekt: das **Ticket**. Ein Ticket ist „a customizable form, optional attachments, a communication chat, and can be positioned on digital plans or BIM models". Mängelmanagement, FM-Aufträge, Brandschutz-Checklisten, Bautagesberichte, RFIs, Abnahmen — laut PlanRadars eigener Doku alles dasselbe Ticket mit einem anderen **Form**.

Objektmodell: `Account → Project → Layer (beliebig tief schachtelbar) → Plan (2D/BIM)`, Tickets hängen an Project + Layer. Es gibt **keine typisierten Entitäten** Gebäude/Etage/Raum — Layer sind generische Container, die Kunden per Konvention als Gebäude/Etage/Gewerk nutzen.

## A.2 Lifecycle

Sechs ausgelieferte Status (dokumentiert, wörtlich):

| Status | Dokumentierte Bedeutung |
|---|---|
| **Open** | Default bei Erstellung |
| **In Progress** | „Typically set by the assignee once work has started" |
| **Resolved** | „Issue has been resolved by a subcontractor and needs to be reviewed and closed by an in-house user" |
| **Feedback** | „Assignee requires feedback to continue" |
| **Rejected** | „Used when there is a reason that the ticket cannot be resolved" |
| **Closed** | „Work is done" |

**Status sind nicht konfigurierbar** (abgeleitet: Status ist ein „predefined field with special functionality"; in keinem Form-/Feld-Admin-Artikel existiert ein Pfad zum Hinzufügen/Umbenennen/Umsortieren; es gibt keine Workflow-Engine). Flexibilität kommt aus benutzerdefinierten List-Feldern, nicht aus dem Statusfeld.

Es gibt **keine erzwungene Reihenfolge**: von Open direkt auf In Progress oder Closed ist ein Klick. Die einzige Sperre ist eine **Berechtigungssperre**: „Subcontractors cannot set tickets to Closed" — der externe Handwerker kann nur bis `Resolved`, die Freigabe auf `Closed` macht ein interner Nutzer. Optional pro Rolle: „All tickets, but only the ticket author can set the status to closed".

**Progress** ist ein separater 0–100-%-Slider, ausdrücklich *nicht* an den Status gekoppelt („have to be updated manually").

**Approvals** (Pro/Enterprise) ist ein *paralleler* Freigabe-Track über Tickets, Dokumente und Planversionen: Workflows mit bis zu 20 Schritten, Reviewer je Schritt, Fristen je Schritt, Ergebnis `Approved / Approved with comments / Rejected`. Eine Freigabe **bewegt den Ticketstatus nicht**.

## A.3 Zuweisung und externe Handwerker

- **Assignee**: genau *einer* pro Ticket (Nutzer oder Nutzergruppe). **Receiver (CC)**: mehrere. Beides sind Formularfelder, die erst aktiviert werden müssen. Zuweisung löst Push + E-Mail aus.
- Drei Nutzertypen: **In-house user** (kostenpflichtiger Seat, alles, einziger Typ der `Closed` setzen darf), **Subcontractor** (**kostenlos, unbegrenzt**, sieht nur die ihm zugewiesenen Tickets, darf Status/Progress ändern, kommentieren, Anhänge hinzufügen, Freigaben bearbeiten), **Watcher** (kostenlos, unbegrenzt, nur lesen + exportieren).
- **Harte Feldgrenze:** Für Subcontractors ist Schreibrecht ausschließlich auf `status`, `progress` und Attachment-Felder gewährbar — „for subcontractors you cannot grant edit permission for any other fields". Ein Handwerker kann also **keine** Kosten, kein Abnahmeformular und keine Checkliste ausfüllen.
- **Kein Gast-/Magic-Link-Zugang.** Externe brauchen ein benanntes Konto mit Login und App. PlanRadar löst die *Kosten*-, nicht die *Onboarding*-Hürde.

## A.4 Priorität, Fristen, Overdue

- Priorität: genau drei Werte **Low / Normal (Default) / High**.
- **Due Date** (Vergangenheit erlaubt) plus ein zweites, getrenntes Feld **Extension Date** — die ursprüngliche Frist bleibt beweiserhaltend stehen, „Extension dates are not allowed to precede due dates". Das ist explizit gewährleistungsorientiert.
- Filter „Due in [X days]" und „Overdue by at least [X days]"; Dashboard zeigt Overdue-Zähler und Fälligkeiten der nächsten sechs Tage; konfigurierbare Vorlauf-Erinnerung.
- **Keine SLA-Engine, keine Eskalationsregeln, keine Reaktionszeit-Ziele, keine Geschäftszeiten-Kalender** (nirgends dokumentiert; gezielt gesucht). Eskalation ist ein Mensch, der eine gefilterte Liste liest.

## A.5 Medien, Kommentare, Journal

- Anhänge: Bilder (JPG/PNG/GIF/HEIC), Dokumente (PDF, Office, **DWG/DXF**, EML/MSG), Archive, Video, Audio. **Max 100 MB je Anhang.** Zwei Sorten: ticketweite Anhänge und feldgebundene Anhänge.
- **Photo Editor** (Markup auf Fotos, Web + Mobile), **Plan Annotations** (markierter Planausschnitt ans Ticket, Mobile), **Sprachmemo** (nur Mobile). Webapp kann nur hochladen, nicht aufnehmen.
- Kommentare pro Form aktivierbar („communication chat"); Subcontractors dürfen kommentieren.
- **Journal** = der Audit-Trail: „information in a ticket is changed or a comment is sent, an entry is added to the journal"; **das Journal ist in den PDF-Ticketreport einbindbar**. Das ist PlanRadars Nachweismechanismus.
- Benachrichtigungen: E-Mail (Sofort oder Tagesdigest, Scope wählbar), Push (Ticket erstellt, Kommentar, Anhang, Fälligkeit — Fälligkeits-Push **nur Android**), In-App Message Center (**Meldungen werden nach drei Monaten gelöscht**).
- **@Mentions: nirgends dokumentiert** (abgeleitet: existiert nicht; Routing läuft über Assignee/Receiver).

## A.6 Wiederkehrende Wartung — der wichtigste Befund

> „Set a repetition date or interval for recurrent tasks to **automatically set the ticket status to 'Open'**."

**Die Wiederholung öffnet dasselbe Ticket erneut. Es entsteht keine neue Ticket-Instanz.** Intervalle: täglich/wöchentlich/monatlich (nach Datum oder Wochentagsmuster)/jährlich.

Konsequenz: PlanRadar hat **keine diskrete Historie je Wartungszyklus**. Der Nachweis jedes Durchgangs liegt im *einen* mitwachsenden Journal desselben Tickets. Es gibt **kein Wartungsplan-Objekt**, keine anlagenbezogene Schedule-Vorlage, kein Regelwerk für automatische Zuweisung.

## A.7 Inspektionen und Checklisten

Kein Inspektionsmodul — eine Inspektion ist ein Form + ein Ticket. Formularbaukasten (nur Web) mit Feldtypen: Text, Zahl, Datum/Zeit, Checkbox, **List** (mit optionaler Hierarchie, Mehrfachauswahl), **User Field**, **Attachment Field**, **Checklist Field**.

**Checklist Field** ist das Inspektions-Primitiv: Antwortsets `Yes/No/N/A`, `True/False/N/A`, `Pass/Fail/N/A`, je Zeile optional Anhang und Notiz — so entsteht „Nachweis je Prüfpunkt". Pro-Feature.

Erzwungene Vollständigkeit gibt es nicht hart, sondern als **Completion Bar** (Prozent gefüllter Felder). **Lock + Sign**: ein Ticket wird gesperrt und unterschrieben („as a final approval or handover for completed tickets"), Assignee/Receiver/Progress/Status/Kommentare bleiben danach änderbar. Das ist PlanRadars Abnahme-Primitiv. Eine **In-Product-Vorlagenbibliothek für Formulare ist nicht dokumentiert** — Kunden bauen Forms selbst.

## A.8 Anlagen/Equipment — die schwächste Stelle

**Es gibt kein Anlagenregister.** Keine Asset-Entität, keine Asset-Attribute, keine Asset-Ticket-Beziehung, kein Gewährleistungsablauf je Anlage.

Stattdessen: **QR-Codes** (Pro; werden **nicht im Produkt erzeugt**, sondern bei PlanRadar bestellt) und **NFC-Tags** (Pro; „put NFC tags on devices, inventory, tools, doors"), beide verlinken **einen Tag auf ein Ticket**.

Das faktische Muster (abgeleitet, konsistent mit Doku und Marketing): **ein langlebiges Ticket je Anlage**, mit QR/NFC beklebt, „Recurring activity" aktiv, und das Journal wächst als Anlagenhistorie mit.

## A.9 Filter, Ansichten, Reporting, Compliance

- **Filter** (stark): Projekt, Layer, Form, *Involved user* (Autor ODER Assignee ODER Receiver gleichzeitig), Hat Anhänge/Bilder/Dokumente/Videos, Assignee, Autor, Status, Priorität, „Due in X", „Overdue by X", **Assignee's company**, Progress, Erstelldatum, plus alle Custom Fields. Kriterien UND-verknüpft, Werte innerhalb eines Kriteriums ODER.
- **Gespeicherte Filter** mit zwei Sichtbarkeitsachsen (nur ich / In-house / alle × dieses Projekt / alle Projekte). Subcontractors dürfen speichern, aber nicht teilen.
- Ansichten: **Plan view, List view, Calendar view** (nur Monat, Feld wählbar), BIM view. Schnellfilter „Hide closed tickets". **Kein Kanban/Board für Tickets** (nicht dokumentiert). List view kann Spalten wählen/sortieren/umsortieren, Sub-Tickets nesten, **Bulk-Edit, Bulk-Delete, Bulk-Report**, Excel-Export, Ticket-Import.
- **Planpins** sind der Schwerpunkt des Produkts: Ticket per Rechtsklick/Long-Tap auf dem Plan anlegen, Pins **statusfarbig**, Planversionierung mit ausdrücklicher Warnung, dass **Pins bei Planwechsel nicht automatisch mitwandern** („position review").
- **Reporting** (zweite Säule): PDF/Excel, bis **2000 Tickets je Report**, Basic- und Advanced-Templates, Titel-/Schlussseite, Header-Bild, Ersetzungs-Tokens, Optionen u. a. „Include plan with annotations", „Show signatures", **Journal (activity log and comments)**. Reports können ans Ticket zurückgehängt und mobil signiert werden. **Zeitgesteuerter Reportversand ist nicht dokumentiert.**
- **Statistics** (rechtegeschützt, nur In-house): Linie/Torte/Balken, in **Boards** gruppierbar, Excel-Export. KPIs baut der Nutzer aus Ticketfeldern; es gibt **kein vorgefertigtes FM-KPI-Set** und kein Contractor-Scorecard-Produkt.
- **Compliance-Positionierung** (DACH-Marketing, wörtlich): „beweissichere Datenerfassung", „gerichtsfeste Dokumentation", „lückenlose Reports", Fristsetzung nach BGB/VOB/B, generierte Mängelrüge. Produktseitig getragen von Journal + Lock/Sign + Extension Date + Approvals + zeitgestempelten, geotaggten, planverankerten Medien. **Kein Gewährleistungs-Objekt, keine Restlaufzeit-Logik** — Gewährleistungsfristen sind gewöhnliche Due Dates.

## A.10 Lizenzmodell, soweit es Zusammenarbeit bestimmt

Preis je **In-house-Nutzer** (Basic 1 Nutzer, Starter/Pro bis 10, Enterprise custom). **Unbegrenzte Subcontractors und Watcher in jedem Tarif, auch Basic.** Externe Zusammenarbeit kostet nichts. FM-relevante Funktionen (QR/NFC, Checklist-Felder, Signaturen, Approvals, Custom-Report-Builder, Dokumentenmanagement, API) sind faktisch **ab Pro**.

## A.11 Kern-Identität vs. Peripherie

**Kern:** Ticket-auf-Form-Modell · Planpin-/BIM-Verankerung · mobile Felderfassung mit Offline · Sechs-Status-Lifecycle mit `Resolved→Closed`-Prüfschritt · kostenlose unbegrenzte Externe · Reportgenerierung mit Journal als Beweis · Filter/gespeicherte Filter · Mängel- und Beweissicherungs-Positionierung.

**Peripherie/Add-on:** Approvals · Schedules/Gantt · Dokumentenmanagement · QR/NFC · SiteView 360° · BIM/AR · Statistics-Boards · AI-Agents · Connect-Integrationen.

**Fehlt / schwach:** Anlagenregister · SLA-/Eskalations-Engine · konfigurierbare Status · diskrete Historie je Wartungszyklus · Gast-Zugang für Externe · @Mentions · Board-Ansicht · geplanter Reportversand · typisierte Gebäude/Etage/Raum · Ersatzteile/Zeiterfassung/Kostenrechnung · Formularvorlagen-Galerie.

## A.12 Quellen

help.planradar.com: Tickets (13977954738845) · Set Status & Progress (13195317110685) · Create a Ticket (13120675758365) · Fill in the Form (13122119433245) · Assignee & Receivers (13195509797917) · Due/Extension Date (13258070058013) · Repetition Date (13194751947677) · Filter Tickets (12808793846813) · List View (13256839157149) · Plan View (13256828893469) · Calendar View (13540904045085) · Tickets Toolbar (14294350237469) · BIM View (22256972289309) · Manage Layers (16773066395037) · Forms (12435483382429) · Create & Edit Forms (13920728614685) · Field Types (12471906434717) · Edit Form Settings (16128348722461) · Edit Field Properties (33382164425245) · Edit Field Permissions (13784591249437) · Shared Fields (37625463480605) · Permissions (13285464167965) · User Types (12477784742941) · Quick Start Subcontractors (12726597749917) · Attachments (37826559209245) · Plan Annotations (13125309937693) · Voice Recording (13125298328477) · GPS Position (13125873526685) · E-Mail Notifications (15191969506461) · Push Notifications (16469516123549) · Message Center (13256441318557) · Approvals (31373315559837) · Approval Workflows (31201392549533) · QR Codes (9991872178717) · NFC Tags (15090843045917) · Plan Position (13125911372573) · Update Plans (16894067857437) · Ticket Reports (13791785308317) · Basic Report Templates (13258121771293) · Advanced Report Templates (13258004011549) · Webapp Dashboard (13103632294173) · Viewing Statistics (13944847487133) · Schedules (14734630163613) · Pricing & Subscription (12634288569501).
planradar.com: /pricing/ · /platform/ · /product/maintenance-and-repairs/ · /property-maintenance-software/ · /us/product/checklists/ · /us/product/building-inspections/ · /customers/facility-management-software/ · /de/produkt/bauen/gewaehrleistungsabnahmen/ · /de/beweissicherungsverfahren-bau/ · /at/maengelmanagement/.

---

# B. Adopt / Adapt / Reject

Regel des Auftrags: **funktionaler Referenz-Klon** — Workflow und User Jobs übernehmen, kein Branding, kein UI-Nachbau.

## B.1 ADOPT (unverändert übernehmen)

| # | PlanRadar-Verhalten | Warum für NexImmo |
|---|---|---|
| A1 | **Ein Ticket = das Arbeitsobjekt.** Der Ticketstatus *ist* der Arbeitsfortschritt; es entsteht nicht automatisch ein zweites Objekt daneben. | Löst die Legacy-Krankheit: das alte Board legte per default-aktivem Schalter zu jedem Ticket eine Task an (`maintenance_screen.dart:1305`), deren Status danach unabhängig driftete. Siehe §6 „Tasks". |
| A2 | **Zwei-Stufen-Abschluss mit Rollentrennung:** „fertig gemeldet" ≠ „abgenommen". | NexImmos `resolved → invoiced → archived` bildet das bereits ab (STM-006). Die *Semantik* wird übernommen: `resolved` = Arbeit gemeldet, nicht abgenommen. |
| A3 | **Due Date + separates Extension Date** — die ursprüngliche Frist bleibt stehen. | Beweiskern für Mängelrüge/VOB-Fristen. Heute nur `due_at`. → Backend-Gap `MAINTENANCE-DATA-04`. |
| A4 | **Journal als Beweismittel, exportierbar in den Bericht.** | NexImmos serverseitiger Audit-Trail ist *reicher* als PlanRadars Journal (pgTAP `023:398-405`: 12 auditierte `maintenance_ticket`-Events, RLS-lesbar mit `audit.read`) — er ist nur nirgends sichtbar. → §16, Gap. |
| A5 | **„Involved user"-Filter** (Autor ODER Zuständiger ODER Beteiligter in einem Kriterium). | Genau die Frage „was liegt bei mir?", die eine Instandhaltungsliste zuerst beantworten muss. |
| A6 | **Gespeicherte Filter mit Sichtbarkeitsachse.** | „Meine überfälligen Heizungstickets" ist der tägliche Einstieg, nicht ein neu geklickter Filter. → Gap (`MAINTENANCE-QUERY-01`, Persistenz). |
| A7 | **Statusfarbige Darstellung, Label trägt die Bedeutung.** | Deckt sich mit Foundation §12 (`NxStatusBadge`, nie farb-only). Bereits erfüllt. |
| A8 | **Overdue als eigene, prominente Zahl**, nicht als Sortierung versteckt. | Kern des Auftrags („overdue"). |
| A9 | **Bulk-Aktionen auf der Liste** (Status setzen, Zuweisen, Bericht). | Die realistische Massenoperation im Objektbetrieb (Heizungswartung über 40 Einheiten). → Gap. |

## B.2 ADAPT (Idee übernehmen, Umsetzung ändern)

| # | PlanRadar | NexImmo-Anpassung | Begründung |
|---|---|---|---|
| P1 | 6 flache, frei springbare Status | **10 Status mit gerichteter STM-006-Kette, aber mit Abkürzungen** | Die deutsche Beschaffungsrealität (Angebot → Beauftragung → Terminierung → Abrechnung) ist echte Arbeit, keine Bürokratie; PlanRadars 6 Status verstecken sie in Custom Fields. Aber: die *erzwungene* Linearität ist ein Bedienfehler — siehe §D.1. Ergebnis: Kette bleibt, Abkürzungskanten kommen dazu. |
| P2 | `Rejected` als Status | **Abkürzungskante `new/triage → archived` mit Pflicht-`reason`** | Ein eigener Status verbreitert die Enum ohne Gegenwert; das Reason-Feld ist im Command-Envelope bereits vorhanden (`MaintenanceCapexCommandContext.reason`). |
| P3 | Freies Formular je Ticketart (Form-Builder) | **Feste Ticket-Felder + eine `category`-Liste** | Ein Form-Builder ist ein eigenes Produkt (Feldregistry, Rechte je Feld, Migration). NexImmo hat eine feste, geprüfte Spalte `category text` (1–100 Zeichen). Der Gewinn steckt in einer *kuratierten Kategorienliste*, nicht in Selbstbau. |
| P4 | Layer-Hierarchie beliebiger Tiefe | **`property → unit` + Freitext `damage_location`** | NexImmo hat mit Property und Unit zwei *typisierte*, referenzierte Ebenen — fachlich stärker als generische Layer. Tiefe darunter (Etage/Raum) trägt heute `damage_location` (bis 2000 Zeichen). |
| P5 | Recurrence öffnet **dasselbe** Ticket wieder | **Ein Schedule erzeugt je Fälligkeit ein *neues* Ticket** | Für Betreiberpflichten/Prüffristen braucht man je Durchgang einen eigenen, abgeschlossenen, auditierten Nachweis (wer, wann, Ergebnis). PlanRadars Modell verliert genau das. Das Konvergenzmuster existiert bereits: `TaskDto.generatedKey` (AGG-019) verhindert Doppelerzeugung. → `MAINTENANCE-PREVENTIVE-01`. |
| P6 | Anlage = langlebiges Ticket mit QR-Tag | **Anlagenregister explizit *nicht* als Ticket** | Das PlanRadar-Muster ist ein Workaround, kein Vorbild. NexImmo braucht dafür entweder eine echte Anlagen-Entität oder gar nichts. Für v2: gar nichts. → §19 out of scope, Bewertung in `MAINTENANCE-PREVENTIVE-01`. |
| P7 | Checklist-Feld im Formular | **Checkliste als Teil des Preventive-Modells, nicht als Task-Liste** | Die Legacy-Lösung (jede Checklistenzeile eine `tasks`-Zeile, `maintenance_screen.dart:998-1060`) ist falsch: eine Prüfzeile ist kein zuweisbares, terminiertes Arbeitsobjekt. → `MAINTENANCE-PREVENTIVE-01`. |
| P8 | Kommentar-Chat am Ticket | **Zunächst kein Kommentarsystem; Verlauf = Audit-Trail** | Ein Kommentar-Store ist eine eigene Tabelle mit eigenem RLS und eigener Aufbewahrungsfrage. Der auditierte Verlauf beantwortet 80 % („wer hat wann was geändert"). Kommentare später als eigenes Paket, wenn Externe wirklich im System arbeiten. Bewusste Abweichung, §20-D3. |
| P9 | Kostenlose externe Subcontractor-Accounts | **Kein externes Konto. Handwerker = Party-Rolle.** | Auftragsvorgabe („keinen externen Portal-Account erfinden, wenn der Contract ihn nicht trägt") und Identity-Contract: es gibt keinen externen Nutzertyp, und einer wäre eine AAL/RLS-Änderung. |
| P10 | Reports bis 2000 Tickets, Template-Builder | **Ein fester Ticketbericht (PDF) mit Audit-Verlauf** | Der Nachweiszweck braucht *einen* verlässlichen Bericht, keinen Baukasten. Report-Generierung hängt an P2-D09 → out of scope v2, benannt. |

## B.3 REJECT (bewusst nicht übernehmen)

| # | PlanRadar-Feature | Ablehnungsgrund |
|---|---|---|
| R1 | **Planpins / Floorplan-Positionierung** | NexImmo hat heute kein Plan-Asset: der Documents-Contract kennt keine Bildrolle und kein Plan-Objekt (Screen Map §0.9: Media gestrandet), es gibt keine Layer/Planversionierung und keinen Viewer. Der Nutzen entsteht erst *nach* Documents-Media und einem Plan-Contract — vorher baut man einen Pin auf ein Bild, das niemand hochladen kann. **Future Scope**, nicht bauen. Siehe §D.5. |
| R2 | **Progress-Slider (0–100 %) neben dem Status** | PlanRadar dokumentiert selbst, dass beide entkoppelt sind und manuell gepflegt werden müssen — zwei Wahrheiten über denselben Fortschritt. Die 10-stufige Kette *ist* der Fortschritt. |
| R3 | **Konfigurierbare/eigene Status je Kunde** | Widerspricht Guardrail 4 (explizite Lifecycle-Logik je Workflow-Entität) und der serverseitigen STM-006-Durchsetzung. |
| R4 | **QR-/NFC-Tags** | Setzt ein Anlagenregister voraus (R6/P6). Ohne Anlage klebt man einen Tag auf ein Ticket — das PlanRadar-Workaround-Muster. |
| R5 | **Sprachmemo, 360°-Erfassung, AR, BIM** | Kein mobiler Erfassungs-Client im Scope; NexImmo ist Desktop/Web-first. |
| R6 | **Delete (auch der Legacy-Parity-Punkt „Delete")** | Weder Cloud-Contract noch Domäne kennen ein Delete (OPN-DOM-005, ausdrücklich auch kein Tombstone). Ein Screen-PR darf das nicht einführen (Master Plan §8). Das *Bedürfnis* hinter „Delete" — ein irrtümlich angelegtes Ticket loswerden — wird durch P2 (`new/triage → archived` mit Grund) korrekt und auditierbar bedient. **Das ist die Antwort auf die Parity-Lücke „Delete", nicht ihr Nachbau.** |
| R7 | **Approval-Workflows über Tickets** | NexImmo hat den Freigabegedanken bereits an der richtigen Stelle: `capex.approve` am CapEx-Projekt. Ein zweiter, generischer Freigabe-Track über Tickets dupliziert das. |
| R8 | **Message-Center mit 3-Monats-Löschung** | Für Nachweiszwecke ein Anti-Pattern; NexImmos Audit-Trail ist append-only. |

---

# C. Parity matrix — cloud (heute) vs. legacy vs. target

Legende: ✅ vorhanden · ⚠️ teilweise · ❌ fehlt · ⛔ bewusst nicht vorgesehen · 🔒 blockiert durch benannten Backend-Gap.

## C.1 Ticket-Kernfunktionen

| Funktion | Cloud heute (`maintenance_tickets_panel.dart`) | Legacy-Board (`maintenance_screen.dart`) | **Target v2** | Aufwand |
|---|---|---|---|---|
| Liste anzeigen | ✅ 6 Spalten, unpaginiert | ✅ ListTile-Liste | ✅ Tabelle + Mobile-Fallback (Foundation §6) | UI |
| **Anlegen** | ⚠️ 4 Felder (Objekt, Titel, Beschreibung, Priorität) | ✅ 20+ Felder in 5 Gruppen | ✅ volles Formular, siehe §12.1 | UI (Contract trägt alles) |
| **Bearbeiten** | ❌ **fehlt komplett** | ✅ Vollformular | ✅ | **UI only** — `update_maintenance_ticket` existiert und ist im Contract (`MaintenanceTicketRepository.update`), wird nur von keinem Screen aufgerufen |
| **Löschen** | ❌ | ✅ Hard Delete | ⛔ **Reject (R6)** — der Bedarf wird durch die Abbruch-Kante nach `archived` bedient | — (die Kante selbst: 🔒 `MAINTENANCE-DATA-03`) |
| Detailansicht | ❌ keine (nur Tabellenzeile) | ✅ reiche Detailspalte | ✅ Split-Pane-Detail (Foundation §8) | UI |
| Statuswechsel | ✅ PopupMenu über `allowedNextStatuses` | ✅ freier Dropdown über alle 10 | ✅ nur erlaubte Kanten + Abkürzungen | UI + 🔒 DATA-03 |
| Status-Historie sichtbar | ❌ | ⚠️ letzte 4 Einträge | ✅ vollständiger Audit-Verlauf | 🔒 `AUDIT-01` |
| Objekt (Property) | ✅ Pflicht, Name aufgelöst | ✅ | ✅ | — |
| **Einheit (Unit)** | ❌ nie gesetzt/gezeigt (`unit_id` existiert + FK + Index) | ✅ Dropdown + Anzeige | ✅ | UI only |
| **Kategorie** | ❌ immer `'general'` | ✅ 7 Werte | ✅ kuratierte Liste, §7.2 | UI only |
| **Fälligkeit** | ❌ nie gesetzt/gezeigt (`due_at` existiert + Index) | ✅ + Start/Ende | ✅ `due_at`; Start/Ende → CapEx (§D.3) | UI only |
| **Extension Date** | ❌ | ❌ | ✅ (A3) | 🔒 `MAINTENANCE-DATA-04` |
| **Handwerker zuweisen** | ❌ nie gesetzt (`contractor_party_id` existiert, serverseitig gegen offene Contractor-Rolle validiert) | ⚠️ **Freitext** `vendorName`, kein FK | ✅ Party-Picker (Rolle `contractor`, offen) | UI only |
| Interner Bearbeiter | ❌ | ⚠️ Freitext `assigneeName` + deutschsprachige `assigneeType`-Gruppe | ✅ eigenes Feld, getrennt vom Auftragnehmer | 🔒 **`MAINTENANCE-ASSIGNEE-01`** (§20-D2) |
| Kosten (Schätzung/Ist) | ⚠️ Ist-Kosten nur beim Statuswechsel, **defekt** (§C.4) | ✅ beide Felder + Abweichung | ✅ beide + Währung + Abweichung | UI + Fix |
| Versicherungsfall | ❌ (3 Spalten existieren) | ✅ Schalter + Status + Schadennummer | ✅ | UI only |
| Schadenort | ❌ (`damage_location` existiert) | ✅ + 4 weitere Ortsfelder | ✅ ein Feld | UI only |
| Optimistic Locking | ✅ mit Konfliktdialog | ❌ blindes Update | ✅ Foundation §10 (Eingabe bleibt erhalten) | UI |

## C.2 Liste, Filter, Übersicht

| Funktion | Cloud heute | Legacy-Board | **Target v2** | Aufwand |
|---|---|---|---|---|
| Filter Status | ✅ serverseitig | ✅ | ✅ | — |
| Filter Priorität | ✅ serverseitig | ✅ | ✅ | — |
| Filter Objekt | ❌ | ✅ | ✅ serverseitig | 🔒 QUERY-01 |
| Filter Einheit | ❌ | ✅ | ✅ serverseitig (objektbezogen heute schon) | 🔒 QUERY-01 (nur hier) |
| Filter Kategorie | ❌ | ✅ | ✅ serverseitig | 🔒 QUERY-01 |
| Filter Handwerker | ❌ | ⚠️ über Freitext-Vendor | ✅ serverseitig (Index `maintenance_tickets_contractor_idx` besteht bereits) | 🔒 QUERY-01 |
| **Filter Fälligkeit/Overdue** | ❌ | ✅ 5 Buckets | ✅ serverseitig (Index `maintenance_tickets_due_idx` besteht bereits) | 🔒 QUERY-01 |
| Volltextsuche | ❌ | ❌ | ✅ serverseitig über Titel/Beschreibung/Schadenort | 🔒 QUERY-01 |
| Sortierung | ❌ | ❌ | ✅ definierte serverseitige Sortierung | 🔒 QUERY-01 |
| Gespeicherte Filter | ❌ | ❌ | ⚠️ Welle B nur Session | 🔒 QUERY-01 |
| „Keine Treffer" ≠ „leer" | ⚠️ eine gemeinsame Empty-Copy | ⚠️ | ✅ Foundation §7 | UI |
| **KPI-Kopf** | ❌ | ✅ 6 Kacheln + Statusverteilung | ✅ 5 Kacheln, §4.2 | UI |
| Board-Ansicht | ❌ | ✅ 10 Spalten, kein Drag&Drop | FUTURE (§20-D4) | 🔒 QUERY-01 + DATA-03 |
| Termin-/Kalenderansicht | ❌ | ✅ Timeline + Buckets | FUTURE (§20-D4) | 🔒 QUERY-01 + DATA-03 |
| Bulk-Aktionen | ❌ | ❌ | ⚠️ Welle A/B nicht | 🔒 QUERY-01 |
| Export | ❌ | ❌ | ⚠️ v2 nicht | 🔒 P2-D09 |
| **Paginierung** | ❌ RPC liefert alles | ❌ | ✅ Keyset, ~50/Seite | 🔒 **QUERY-01 — blockiert diese Fläche** (§20-D1) |

## C.3 Verknüpfungen

| Funktion | Cloud heute | Legacy-Board | **Target v2** | Aufwand |
|---|---|---|---|---|
| **Dokumente verknüpfen** | ❌ | ⚠️ nur *Umhängen* vorhandener Objektdokumente (zerstörerisch: setzt `entityType`/`entityId` um) | ✅ echte `document_links` mit `entity_type='maintenance_ticket'` | UI — Server trägt es bereits (pgTAP `023:568-575`) |
| **Fotos/Nachweise** | ❌ | ❌ (nur Dateinamen-Endung als „Bild"-Heuristik) | ⚠️ Upload+Link über Documents-Contract, Rolle über `link_role` | UI + 🔒 `DOCUMENTS-COMPLETE-01` (Bildrolle/Media) |
| **Task verknüpfen** | ❌ | ⚠️ Auto-Task je Ticket (default an) + Checklisten-Tasks | ✅ explizit, nie automatisch (§6.9) | UI — `PlatformEntityType.maintenanceTicket` existiert |
| CapEx verknüpfen | ❌ | ⚠️ implizit über Kategorie `renovation` | ✅ | 🔒 `MAINTENANCE-CAPEX-LINK-01` |
| Handwerker-Stammsatz | ❌ | ⚠️ Namensgleichheit als „Join" | ✅ echte Party-Referenz | UI |
| Tickets je Handwerker | ❌ | ⚠️ clientseitig über Namensgleichheit | ✅ über den Contractor-Filter | 🔒 QUERY-01 |
| Benachrichtigung fällig/überfällig | ❌ | ✅ manueller Knopf „Run Due Notifications" | ⚠️ v2 nur visuell | 🔒 `MAINTENANCE-NOTIFY-01` |
| Realtime-Invalidierung | ✅ mit Coalescing | ❌ | ✅ + Degraded-Notice | 🔒 `REALTIME-DEGRADED-WIRING-01` |

## C.4 Bestätigte Defekte im heutigen Cloud-Screen

| # | Defekt | Beleg | Wirkung |
|---|---|---|---|
| **DEF-1** | **Ist-Kosten-Eingabe schlägt immer fehl.** `showMaintenanceTicketCostDialog` liefert eine nackte Zahl; `transition` sendet `p_cost_actual` ohne Währung. `transition_maintenance_ticket_status` setzt `cost_actual = coalesce(p_cost_actual, cost_actual)` und rührt `currency_code` nie an. Die Tabellen-Constraint `maintenance_tickets_currency_required_check` verlangt aber eine Währung, sobald ein Betrag existiert — und das Anlege-Dialog setzt nie eine. | `maintenance_tickets_panel.dart:498-525`, `20260806100000_...:1301-1310`, Constraint `:146-148` | Jede Ist-Kosten-Eingabe endet in einer **Check-Constraint-Verletzung**, die als geworfene `PostgrestException` im `catch (_)` des Kommandopfads landet und zu `infrastructureFailure` mit der generischen Meldung „Supabase maintenance_capex command failed." wird (`supabase_maintenance_capex_repository_adapter.dart:183-186`). Nutzer sieht „Verbindung fehlgeschlagen", Ticket bleibt unverändert. **Nicht durch Tests abgedeckt** — der Integrationstest erzeugt Tickets mit Währung. |
| **DEF-2** | Anlegen ist bei leerer Objektliste stumm deaktiviert (`onCreate: properties.isEmpty ? null : …`) — ohne Hinweis, ohne Tooltip. | `maintenance_tickets_panel.dart:53-55` | In einem Arbeitsbereich ohne Objekte (oder wenn der Reference-Slice-Load scheitert) ist der Knopf tot und nennt die Ursache nicht. **Kein** Berechtigungsfall — die Seite selbst ist auf `property.read` gegated. |
| **DEF-3** | Kein `NxPageHeader`, keine Breadcrumbs, hand­gerollte `Wrap`-Toolbar statt `ListFilterBar`/`ListFilterTemplate`; private Skeleton-Kopie; kein Mobile-Fallback der Tabelle. | `:223-290`, `:376-399`, `:318-373` | Foundation §§5–6, 11 verletzt (bekannt und in Foundation §0 als Wave-3/4-Muster benannt). |
| **DEF-4** | Vertragskommentar behauptet „no AAL2 (ordinary business data)", tatsächlich verlangt DEC-025 seit `20260812100000` AAL2 für jeden Maintenance-Read und -Write. | `maintenance_capex_repository.dart:8` vs. `20260812100000_...:52-59` (`is_aal2`) und `:76-83` (Aufruf in `has_workspace_permission`) | Dokumentationsdefekt, kein Verhaltensdefekt. In §14 als Doku-Gap geführt, damit ihn kein Screen-PR „korrigiert" indem er Verhalten ändert. |
| **DEF-5** | Berechtigungs-Mismatch: Seite unter `property.read` (`app_navigation.dart:266-271`), Daten unter `maintenance.read`. | Screen Map §0.6 | Nutzer mit nur `property.read` erreicht die Seite und landet in der Forbidden-Sackgasse. **Gehört ausschließlich zu `PERMISSION-CATALOG-02` und wird hier nicht gelöst** (Foundation §3 friert das Mapping ein). |

---

# D. Final lifecycle

## D.1 Ist-Zustand (serverseitig durchgesetzt, STM-006)

`private.maintenance_ticket_status_transition_allowed`, gespiegelt in `MaintenanceTicketStatus.allowedNextStatuses`:

```
new → triage → quote_requested → commissioned → scheduled → in_progress
                                                                  ├→ waiting → in_progress
                                                                  └→ resolved
                                                                        ├→ in_progress   (Reopen)
                                                                        └→ invoiced → archived
```

Zusatzregeln (Server): `resolved_at` wird beim Eintritt in `resolved|invoiced|archived` gesetzt, beim Reopen **geleert**, und bleibt beim Vorwärtsschritt `invoiced → archived` stehen (Constraint `maintenance_tickets_resolved_marker_check` erzwingt die Äquivalenz). Kein Delete, kein Tombstone (OPN-DOM-005).

## D.2 Abgleich mit der geforderten Ziel-Sequenz

| Geforderte Stufe | STM-006-Entsprechung | Wird sie gebraucht? |
|---|---|---|
| Report | `new` | **Ja.** Eingang, noch niemand hat draufgeschaut. |
| Triage | `triage` | **Ja.** Der Sichtungsschritt trennt „gemeldet" von „bewertet" — die einzige Stelle, an der Kategorie, Priorität und Fälligkeit verantwortlich gesetzt werden. |
| Assign | `quote_requested`, `commissioned`, `scheduled` | **Ja, alle drei.** Das ist keine Bürokratie, sondern die reale Beschaffungskette: Angebot angefragt (wartet auf den Handwerker) ≠ beauftragt (verbindlich, Kostenrisiko steht) ≠ terminiert (Zugang/Mieter organisiert). Genau diese drei Zustände beantworten die häufigste Rückfrage im Objektbetrieb („woran hängt es?"). PlanRadar kennt sie nicht und zwingt sie in Custom Fields. |
| In Progress | `in_progress` | **Ja.** |
| Waiting / Blocked | `waiting` | **Ja.** Deckt Materialwartezeit und Rückmeldungswartezeit ab (Legacy trennte `waiting_material` / `waiting_reply` — die Trennung trägt keine Entscheidung und wird **nicht** wiederbelebt; der Grund gehört in `reason`/Beschreibung). |
| Completed | `resolved` | **Ja.** Semantik nach A2: *gemeldet* fertig, nicht abgenommen. |
| Verified / Closed | `invoiced` → `archived` | **Ja, aber neu belegt.** Siehe D.3. |

**Ergebnis: alle 10 Zustände werden gebraucht. Keiner wird gestrichen.** Zwei Kanten fehlen (D.4).

## D.3 Entscheidung zu „Verified/Closed"

Es wird **kein zusätzlicher `verified`-Status eingeführt.** Begründung:

- STM-006 hat bereits zwei Nachlaufstufen nach `resolved`. Ein dritter Zustand für dieselbe Sache wäre eine Schemaänderung für ein einzelnes Bit.
- Semantik wird verbindlich festgelegt:
  - **`resolved`** — Arbeit ist als erledigt *gemeldet*. Ist-Kosten werden hier erfasst.
  - **`invoiced`** — kaufmännisch geprüft und abgerechnet. **Das ist der Abnahmeschritt**: wer hierher transitioniert, bestätigt, dass die Leistung erbracht ist. Der Audit-Trail hält Actor und Zeitpunkt fest.
  - **`archived`** — abgelegt, terminal.
- Die *Rollentrennung*, die PlanRadar über Nutzertypen erzwingt (Handwerker darf nur bis `Resolved`), ist in NexImmo heute nicht möglich: es gibt keinen externen Nutzertyp, und `resolved` wie `invoiced` verlangen beide `maintenance.manage`. Eine eigene Fähigkeit `maintenance.verify` wäre die saubere Lösung — sie ist eine **Permission-Catalog-Änderung** und gehört zu `PERMISSION-CATALOG-02`, nicht in diesen Screen. Hier nur als Empfehlung notiert.

## D.4 Fehlende Kanten — Backend-Gap `MAINTENANCE-DATA-03`

Die Kette ist von `new` bis `in_progress` **strikt linear und nicht abkürzbar**. Konsequenzen im Betrieb:

1. **Der Hausmeister-Fall.** Ein tropfender Wasserhahn, den der eigene Hausmeister in zehn Minuten repariert, muss durch `triage → quote_requested → commissioned → scheduled`, bevor jemand „in Bearbeitung" sagen darf. Vier auditierte Transitionen, die nie stattgefunden haben. Das ist genau die operative Einfachheit, die der Auftrag von PlanRadar übernehmen will — und sie fehlt.
2. **Der Irrläufer.** Ein doppelt gemeldetes oder gegenstandsloses Ticket kann heute **überhaupt nicht** geschlossen werden: kein Delete (R6), und `archived` ist erst nach acht Transitionen erreichbar. Jedes Fehl-Ticket bleibt unsterblich in der Liste.

Eine UI-seitige „Schnellspur", die die Zwischenschritte als Kette einzeln absetzt, wird **ausdrücklich abgelehnt**: sie fabriziert Audit-Ereignisse, die nicht stattgefunden haben (Guardrail 3, Audit-Ehrlichkeit).

**Beantragte Kanten** (Paket `MAINTENANCE-DATA-03`, Server + Contract + pgTAP):

| Von | Nach | Zweck | Bedingung |
|---|---|---|---|
| `new` | `in_progress` | Selbst ausgeführte Sofortmaßnahme (Hausmeister) | — |
| `triage` | `in_progress` | dito, nach Sichtung | — |
| `triage` | `scheduled` | interner Termin ohne Fremdvergabe | — |
| `new` | `archived` | Abbruch/Dublette/gegenstandslos | **`reason` verpflichtend** |
| `triage` | `archived` | dito nach Sichtung | **`reason` verpflichtend** |

`resolved_at` folgt beim Abbruch derselben Regel wie heute (wird gesetzt). Alles andere an STM-006 bleibt unverändert; insbesondere bleiben Rückwärtskanten außer dem bestehenden Reopen ausgeschlossen.

**Bis das Paket liegt:** die UI bietet ausschließlich `allowedNextStatuses` an (heutiges Verhalten, korrekt) und zeigt bei `new`/`triage` einen Hinweis, dass Abkürzung und Abbruch noch nicht verfügbar sind. Kein Workaround.

## D.5 Entscheidung zu Floorplan/Plan-Pins

**Future Scope. Jetzt nicht bauen, nicht als Gap beantragen.** (R1)

Voraussetzungskette, in dieser Reihenfolge: (1) `DOCUMENTS-COMPLETE-01` schließt die Media-/Bildrollen-Lücke; (2) ein Plan-/Grundriss-Contract mit Versionierung entsteht (existiert nirgends, in keinem P2-Dxx-Paket); (3) ein Viewer mit Zoom/Pan und Pin-Koordinaten; (4) eine Antwort auf PlanRadars eigenes ungelöstes Problem, dass Pins beim Planwechsel nicht mitwandern. Erst danach ist die Frage sinnvoll. Platzhaltername für die spätere Diskussion: `MAINTENANCE-PLAN-PINS-01` — **kein Tracker-Eintrag**, damit er nicht als geplante Arbeit gelesen wird.

---

## 1. Purpose

Die Fläche ist die **portfolioweite Arbeitsliste der Instandhaltung**: alles, was an allen Objekten des Arbeitsbereichs kaputt ist, geprüft werden muss oder auf jemanden wartet — in einer Liste, nach Dringlichkeit und Fälligkeit sortierbar, mit dem Weg vom Eingang bis zur Abrechnung.

Sie beantwortet drei Fragen, in dieser Reihenfolge:
1. **Was ist überfällig oder dringend?** (heute nicht beantwortbar — es gibt keine Fälligkeit in der UI)
2. **Woran hängt es?** (Status als Antwort, nicht als Etikett)
3. **Was kostet es und wer macht es?**

Sie ist zugleich der Nachweisort: jede Zustandsänderung ist serverseitig auditiert, jedes Foto und jedes Angebot hängt als verknüpftes Dokument am Vorgang statt in einem zweiten Ablagesystem.

## 2. Primary users and jobs

| Rolle (fachlich) | Job | Braucht zuerst | Entscheidet hier |
|---|---|---|---|
| **Objektbetreuer / Property Manager** | Tagesliste abarbeiten | Überfällig + dringend, objektübergreifend | Priorität, Kategorie, Fälligkeit, Beauftragung |
| **Technischer Leiter** | Steuern, nicht abarbeiten | Verteilung über Status und Objekte, Kostenrisiko | Eskalation, Umverteilung, Freigabe von Kosten |
| **Kaufmännische Sachbearbeitung** | Abrechnen | Was ist `resolved`, aber nicht `invoiced`? Ist-Kosten vollständig? | Abnahme/Abrechnung (`invoiced`), Versicherungsfall |
| **Eigentümer / Reporting** | Nachweis führen | Historie eines Vorgangs, verknüpfte Belege | nichts — reine Lesesicht |
| **Handwerker (extern)** | Auftrag ausführen | — | **arbeitet nicht in NexImmo**, siehe §B.2-P9 |

## 3. Entry points and navigation

- **Eintritt:** Sidebar *Tagesgeschaeft › Instandhaltung* (`GlobalPage.maintenance`). Kein Deep-Link auf ein einzelnes Ticket, solange `SHELL-ROUTING-01` fehlt — Foundation §2: die Fläche muss ohne URL vollständig erreichbar bleiben.
- **Ausgänge:**
  - Objektzelle → `propertyMaintenanceRouteFor(propertyId)` (`/property-maintenance/<id>`). **Diese Liste ist der einzige In-App-Einstieg** in die objektbezogene Fläche, die keine eigene Sidebar-Destination hat (heute schon so, durch `maintenance_tickets_panel_test.dart:84-102` gepinnt, tragende Zusicherung auf `:101` — Verhalten muss erhalten bleiben).
  - Handwerker-Chip im Detail → *Handwerker* (`GlobalPage.contractors`).
  - Verknüpftes Dokument → Documents Workspace.
  - Verknüpfte Aufgabe → Tasks (nach `TASKS-NOTIFICATIONS-01`; bis dahin nur Anzeige ohne Sprung).
- **Erhaltener Kontext:** Filterzustand und Auswahl überleben Tabwechsel innerhalb der Fläche, werden beim Arbeitsbereichswechsel zurückgesetzt (Foundation §7).

## 4. Information architecture

1. `NxPageHeader` — Titel „Instandhaltung", Breadcrumbs `['Tagesgeschaeft', 'Instandhaltung']`, Primäraktion **„Ticket anlegen"**, Sekundäraktionen „Aktualisieren".
2. `NxLiveUpdatesNotice` (nur wenn degraded, Foundation §13).
3. **KPI-Zeile** (`NxKpiRow`, §4.2) — klickbar, setzt den passenden Filter.
4. `ListFilterBar` — Suche, dann typisierte Dropdowns (§11).
5. **Split-Pane**: links Tabelle, rechts Detail (Foundation §8, 3:2, `> AppBreakpoints.tabletMax`).
6. Fußzeile: Trefferzahl + Ladehinweis.

### 4.2 KPI-Kacheln (fünf)

**Bezugsmenge:** die Kacheln zählen den **gesamten** Arbeitsbereich, nicht die aktuell geladene Seite — eine Kachel „Überfällig", die nur die erste Seite zählt, ist eine falsche Zahl. Sie setzen damit `MAINTENANCE-QUERY-01` voraus (gefilterte Zählungen bzw. Count-Ergebnisse) und gehören zu Welle B. Auf der objektbezogenen Schwester-Fläche sind die Kacheln bereits heute korrekt, weil dort der vollständige Satz eines Objekts geladen wird.

| Kachel | Definition | Klick setzt |
|---|---|---|
| **Offen** | Status ∉ {`resolved`,`invoiced`,`archived`} | Fälligkeitsfilter „alle", Statusfilter „offen" (Sammelwert) |
| **Überfällig** | offen ∧ `dueAt < heute 00:00` — Ton `error`, bei 0 `success` | Fälligkeitsfilter `overdue` |
| **Diese Woche** | offen ∧ `heute ≤ dueAt < heute+7d` | Fälligkeitsfilter `week` |
| **Dringend** | offen ∧ `priority == urgent` | Prioritätsfilter `urgent` |
| **Kostenrisiko** | Σ (`costActual ?? costEstimate ?? 0`) über offene Tickets, mit Währung | — |

Aus dem Legacy-Dashboard **nicht** übernommen: „Schäden" (Kategoriezählung ohne Entscheidungswert) und „Versicherung" (gehört als Filter, nicht als Kachel). Das Statusverteilungs-Balkendiagramm wandert als optionale Sekundärdarstellung in §20-D4.

## 5. Layout and interaction model

- **Rahmen:** `ListFilterTemplate` (Foundation §6). Die heutige handgerollte `Column`+`Wrap`-Toolbar konvergiert.
- **Desktop (`> 1199`):** Split-Pane 3:2 (`AppLayout.splitViewMinWidth`, seit `791849f` auf `main`).
- **Tablet/Mobile (`≤ 1199`):** Auswahl **ersetzt** die Liste, Rücksprung „Zur Liste" (Foundation §8; das Wave-3/4-Stapeln ohne Rücksprung konvergiert).
- **Tabelle:** `DataTable(showCheckboxColumn: false)` in `NxDataTableShell`. Spalten: Objekt · Titel · Status · Priorität · Fällig · Handwerker · Kosten. Über sechs Spalten ⇒ **Spaltenwähler** (`PopupMenuButton<enum>`, Foundation §6) mit optionalen Spalten Einheit, Kategorie, Gemeldet am. Zahlen in `context.tabularNumericStyle`, Beträge in `context.dataMonoStyle`, `'—'` für null.
- **`mobileChild` ist Pflicht** (`ListTile` + `chevron_right`, Muster `party_table.dart:144`).
- **Auswahl:** `DataRow(selected:, onSelectChanged:)`; genau ein Ticket zur Zeit.
- **Paginierung:** `workspace_maintenance_tickets` liefert heute unpaginiert. Vollständiges Laden ist **kein freigegebener Produktionspfad** und ein Client-Hard-Cap ist ausdrücklich kein Ersatz (§20-D1). Diese Fläche wird deshalb **erst mit `MAINTENANCE-QUERY-01`** gebaut und verwendet dann die Keyset-„Weitere laden"-Mechanik der Foundation §6 (Seitengröße ~50).
- **Statuswechsel:** im Detail als eigene Aktionsleiste (nicht mehr als versteckter PopupMenu in der letzten Tabellenspalte) — jeder erlaubte Folgestatus ein `OutlinedButton`, Abnahme (`invoiced`) als hervorgehobene Aktion.

## 6. Functional requirements

Für jede Aktion: Auslöser · Voraussetzung · Validierung · Erfolg · Fehler · Berechtigung · Folgezustand.

| # | Aktion | Spezifikation |
|---|---|---|
| **F1** | **Liste laden** | Auslöser: Mount, Arbeitsbereichswechsel, Filteränderung, Realtime-Invalidierung (250 ms coalesced), „Erneut versuchen". Ruft `searchWorkspace(WorkspaceMaintenanceTicketListQuery)`. Erfolg → `ready`/`empty`. `forbidden` → Forbidden-State mit `(maintenance.read)`. Sonst → Error-State mit Retry. Berechtigung: `maintenance.read` (serverseitig; die RPC liefert bei fehlender Berechtigung **`forbidden`, nicht eine leere Liste** — für die workspace-weite RPC bewiesen in pgTAP `024:156-164`, für die objektbezogene zusätzlich im Integrationstest `:419-433`). |
| **F2** | **Ticket anlegen** | Auslöser: Primäraktion oder Empty-CTA. Voraussetzung: ≥1 Objekt lesbar; ohne Objekt ist der Knopf **deaktiviert mit Tooltip** „Es ist kein Objekt verfügbar" (behebt DEF-2). Formular §12.1. Validierung: Objekt und Titel Pflicht; Titel 1–200 Zeichen; Beträge ≥ 0; **Betrag ohne Währung wird clientseitig verhindert** (behebt DEF-1 an der Quelle). Erfolg: Liste neu laden, Snackbar „Ticket angelegt.", neues Ticket ist selektiert. Fehler: `dependencyConflict` bei ungültigem Handwerker → Feldfehler am Handwerker-Feld („Diese Partei hat keine offene Handwerker-Rolle"); `validationFailed` → Feldzuordnung; sonst Snackbar. Berechtigung `maintenance.manage`, ohne sie **deaktiviert mit Tooltip** (Foundation §3). Neues Ticket startet immer `new`. |
| **F3** | **Ticket bearbeiten** | **Neu — größter Parity-Gewinn ohne Backend-Arbeit.** Auslöser: „Bearbeiten" im Detail. Ruft `MaintenanceTicketRepository.update` mit `expectedVersion` aus dem geladenen DTO. Felder §12.2. **Semantik-Warnung:** `update_maintenance_ticket` ist serverseitig `coalesce(param, existing)` — ein Feld kann per Update **nicht auf null zurückgesetzt** werden. Die UI muss das ehrlich abbilden: Felder, die einen Wert tragen, zeigen den Hinweis „kann nicht mehr geleert werden" statt eines wirkungslosen Löschknopfs. Konflikt → Foundation §10 (Dialog bleibt offen, Eingabe erhalten, „Neu laden" / „Erneut speichern"). Berechtigung `maintenance.manage`. |
| **F4** | **Status wechseln** | Auslöser: Aktionsleiste im Detail. Angeboten wird **ausschließlich** `status.allowedNextStatuses` (Client spiegelt STM-006, der Server entscheidet). Bei Ziel `resolved` oder `invoiced`: Ist-Kosten-Dialog **mit Währungsfeld** (behebt DEF-1). Erfolg: Liste + Detail neu laden, Snackbar „Status aktualisiert.". `validationFailed` mit `field: target_status` → „Dieser Schritt ist nicht erlaubt" + Neuladen (Rennen mit einem anderen Nutzer). Versionskonflikt → §10. Berechtigung `maintenance.manage`. |
| **F5** | **Abbrechen/Verwerfen** | 🔒 `MAINTENANCE-DATA-03`. Bis dahin: nicht angeboten; im Detail eines `new`/`triage`-Tickets erscheint ein `NxNotice`, dass Abbruch noch nicht möglich ist. **Kein Ersatz-Workaround.** |
| **F6** | **Handwerker zuweisen** | Teil von F2/F3. Auswahl aus Parteien mit **offener** `contractor`-Rolle (`PartyListQuery(roleType: contractor)`, serverseitig gefiltert). Serverseitig gegen `private.maintenance_contractor_party_valid` geprüft; Verstoß → `dependencyConflict`. Zuweisung erzeugt **keine** Benachrichtigung (🔒 `MAINTENANCE-NOTIFY-01`) — die UI verspricht sie nicht. |
| **F7** | **Dokument verknüpfen** | Auslöser: „Dokument verknüpfen" im Detail-Abschnitt *Belege*. Zwei Wege: (a) vorhandenes Workspace-Dokument wählen → `DocumentLinkPort.link(entityType: maintenanceTicket, entityId: ticketId, linkRole: <Rolle>)`; (b) neue Datei hochladen → `DocumentUploadPort.upload` → `create_document` → `link_document`. **Weg (b) ist nicht atomar** (Documents-Contract kennt keine kombinierte RPC, `property_documents_controller.dart:419-424`); ein erfolgreicher Create mit fehlgeschlagenem Link wird als eigenes Ergebnis gemeldet („Dokument wurde gespeichert, aber nicht mit dem Ticket verknüpft"), nicht als stiller Erfolg. Berechtigung `document.manage` (zusätzlich zu `maintenance.read`); ohne sie ist nur Weg (a) sichtbar und auch der nur mit `document.manage` — sonst wird der ganze Abschnitt schreibgeschützt. |
| **F8** | **Dokument-Verknüpfung lösen** | `DocumentLinkPort.unlink`. Destruktive Bestätigung nach Foundation §14 mit **Namensnennung**; Text macht explizit, dass das **Dokument erhalten bleibt** und nur die Verknüpfung entfällt (Abgrenzung zum Legacy-Verhalten, das Dokumente umgehängt hat). |
| **F9** | **Aufgabe erzeugen** | Auslöser: „Aufgabe anlegen" im Detail — **nie automatisch** (§6.9). Legt `TaskDraft(entity: PlatformEntityRef(type: PlatformEntityType.maintenanceTicket, id: ticketId), title: …, priority: …, dueAt: …, description: …)` an — der Konstruktor ist benannt-parametrig. **Prioritätsabbildung nötig:** `TaskPriority` kennt kein `urgent` → `urgent` bildet auf `high` ab, und die UI sagt das im Dialog. Muster: `OperationsAlertsController.createTaskFrom` (`operations_alerts_controller.dart:272-308`) — mit der Abweichung, dass Mutation-/Correlation-IDs hier **UUIDs** sein müssen (der maintenance-Controller nutzt bereits `Uuid().v4`, der Operations-Controller nutzt Zeitstempel-Strings; die UUID-Variante ist die richtige). Berechtigung `task.manage`. |
| **F10** | **Verknüpfte Aufgaben anzeigen** | `TaskListQuery(entity: PlatformEntityRef(type: PlatformEntityType.maintenanceTicket, id: ticketId))`. **Achtung:** `tasks.entity_id` hat serverseitig **keine Existenzprüfung** (`20260723130000_...:513-522` prüft nur „beides oder keins") — eine verwaiste Aufgabe ist möglich und darf die Ansicht nicht brechen. Berechtigung `task.read`; ohne sie entfällt der Abschnitt. |
| **F11** | **Filtern / suchen / sortieren** | §11. Heute kennt die RPC nur Status und Priorität; alle weiteren Dimensionen sowie Sortierung und Paginierung kommen mit `MAINTENANCE-QUERY-01`. **Kein clientseitiger Ersatz über einen vollgeladenen Satz** (§20-D1). |
| **F12** | **Verlauf anzeigen** | 🔒 `AUDIT-01`. Bis dahin zeigt der Detailabschnitt *Verlauf* nur `createdAt/createdBy` und `updatedAt/updatedBy` aus dem DTO und benennt offen, dass der vollständige Audit-Verlauf noch nicht lesbar ist. **Kein clientseitig rekonstruierter Pseudo-Verlauf.** |
| **F13** | **Objekt öffnen** | Sprung auf `/property-maintenance/<propertyId>` (Bestandsverhalten, testgepinnt). |

### 6.9 Wann ist das Ticket die Arbeit — und wann entsteht zusätzlich eine Aufgabe?

Verbindliche Regel:

> **Das Ticket ist die Arbeit.** Ein Ticket erzeugt niemals automatisch eine Aufgabe.

Eine **Aufgabe** entsteht nur, wenn ein Arbeitsschritt *drei* Bedingungen erfüllt:
1. Er hat einen **anderen Verantwortlichen** als das Ticket, und
2. er hat eine **eigene Frist**, die nicht die Ticketfrist ist, und
3. sein Abschluss ist **kein Ticket-Statuswechsel**.

Beispiele, die eine Aufgabe rechtfertigen: „Drei Vergleichsangebote einholen" (Einkauf, vor `commissioned`), „Mieter über Zugangstermin informieren" (Vermietung, vor `scheduled`), „Rechnung kontieren und freigeben" (Buchhaltung, nach `invoiced`), „Versicherungsmeldung nachfassen".

Beispiele, die **keine** Aufgabe rechtfertigen: „Handwerker beauftragen" (= Statuswechsel `commissioned`), „Reparatur durchführen" (= das Ticket selbst), „Prüfpunkte abhaken" (= Checkliste, `MAINTENANCE-PREVENTIVE-01`).

Damit wird die Legacy-Krankheit beendet: das alte Board legte per default eingeschaltetem Schalter zu **jedem** Ticket eine Aufgabe an und benutzte Aufgaben zusätzlich als Checklistenzeilen — zwei Objekte mit zwei Status über einen Vorgang, die auseinanderlaufen.

## 7. Data requirements

### 7.1 Ticketfelder

Quelle für alle: `public.maintenance_tickets` über `MaintenanceTicketDto`. „Neu" = im Cloud-Screen heute nicht sichtbar/setzbar.

| Feld | Bedeutung | Pflicht | Editierbar | Format / Regel | Neu in v2 |
|---|---|---|---|---|---|
| `id` | Identität | — | nein | UUID, `dataMonoStyle` | — |
| `propertyId` | Objekt | ja | **nein** (geschützte Spalte, Trigger `maintenance_tickets_protected_columns`) | Name über Property-Liste aufgelöst, Fallback: rohe Id | — |
| `unitId` | Einheit | nein | **nein — nur beim Anlegen setzbar** | FK `(workspace_id, unit_id)`; „Gesamtobjekt" wenn null. `create_maintenance_ticket` hat `p_unit_id`, **`update_maintenance_ticket` hat keinen Einheiten-Parameter**, und `MaintenanceTicketUpdateDto` kennt kein `unitId` — eine falsch gesetzte Einheit ist heute nicht korrigierbar (→ §14-G3) | **ja** |
| `title` | Kurzbezeichnung | ja | ja | 1–200 Zeichen (Server-Check) | — |
| `description` | Beschreibung | nein | ja | ≤ 10 000 Zeichen | — |
| `category` | Ticketart | ja (Default `general`) | ja | 1–100 Zeichen **freier Text serverseitig**; UI führt eine kuratierte Liste, §7.2 | **ja** |
| `status` | Lifecycle | ja | **nur per Transition** | Enum, §D | — |
| `priority` | Dringlichkeit | ja (Default `normal`) | ja | `low\|normal\|high\|urgent` (Server-Check) | — |
| `reportedAt` | Eingang | ja | nein | Datum | **ja** (Anzeige) |
| `dueAt` | Frist | nein | ja | Datum; Grundlage für Overdue | **ja** |
| `resolvedAt` | Abschlusszeitpunkt | — | nein | serverseitig gestempelt/geleert | **ja** (Anzeige) |
| `costEstimate` | Schätzung | nein | ja | ≥ 0, **verlangt `currencyCode`** | **ja** |
| `costActual` | Ist-Kosten | nein | ja (auch per Transition) | ≥ 0, **verlangt `currencyCode`** | ⚠️ heute defekt |
| `currencyCode` | Währung | bedingt | ja | `^[A-Z]{3}$`; **Pflicht, sobald ein Betrag existiert** (DEC-011) | **ja** |
| `contractorPartyId` | Handwerker | nein | ja | Party mit **offener** `contractor`-Rolle, serverseitig geprüft | **ja** |
| `damageLocation` | Schadenort | nein | ja | ≤ 2000 Zeichen | **ja** |
| `insuranceCase` | Versicherungsfall | ja (Default false) | ja | bool | **ja** |
| `insuranceStatus` | Regulierungsstand | nein | ja | 1–100 Zeichen frei; UI-Liste `gemeldet/in Prüfung/freigegeben/abgelehnt/reguliert` | **ja** |
| `insuranceClaimNumber` | Schadennummer | nein | ja | ≤ 200 Zeichen | **ja** |
| `version` | Optimistic Lock | — | nein | `expectedVersion` bei jeder Mutation | — |
| `createdAt/By`, `updatedAt/By` | Herkunft | — | nein | Anzeige im Verlauf | **ja** |

**Nicht vorhanden und nicht erfunden:** interner Bearbeiter (**fachlich bejaht, Contract fehlt** — §20-D2, `MAINTENANCE-ASSIGNEE-01`; bis dahin wird er weder angezeigt noch behauptet, das Contractor-Feld wird **nicht** überladen), Startdatum, Enddatum, Gebäude/Bereich/Technik/Außenanlage als eigene Spalten (Legacy V37-Felder), Extension Date, Wiederholung, Checkliste, Kommentare (§20-D3). Siehe §14.

### 7.2 Kategorien (UI-Liste über freiem Serverfeld)

`category` ist serverseitig freier Text; die UI führt eine kuratierte Liste und toleriert unbekannte Bestandswerte (Anzeige roh, wie `_categoryItems` es im Legacy tat):

`damage` Schaden · `defect` Mangel · `repair` Reparatur · `maintenance` Wartung · `inspection` Prüfung/Begehung · `minor_repair` Kleinreparatur · `general` Allgemein.

**Bewusst gestrichen** gegenüber Legacy: `renovation` und `modernization` — das sind **CapEx-Maßnahmen**, keine Tickets (Schwester-Spec §B.2/§B.3; die fehlende Verknüpfung: §14-G5). `warranty` (Legacy-Schattenwert, in keinem Dropdown erzeugbar) entfällt ebenfalls; Gewährleistung wird in der Schwester-Spec behandelt. Neu: `inspection`, als Anker für `MAINTENANCE-PREVENTIVE-01`.

### 7.3 Beziehungen (Datenmodell-Sicht)

```
workspace 1─n property 1─n maintenance_ticket
                    │              │
                    └─n unit ──────┘ (optional, FK)
                                   │
              party(role=contractor, offen) ──┘ (optional, FK + Prüffunktion)
                                   │
    document ──n document_links(entity_type='maintenance_ticket') ──┘
                                   │
    task(entity_type='maintenance_ticket', entity_id) ──────────────┘   (KEINE Existenzprüfung)
                                   │
    capex_project ─── ✗ keine Verknüpfung ────────────────────────────┘   🔒 MAINTENANCE-CAPEX-LINK-01
                                   │
    audit_events(entity_type='maintenance_ticket') ─────────────────┘   (existiert, nicht lesbar in der UI)
```

Belege: `document_links`-Enum + `private.document_entity_ref_state` akzeptiert `maintenance_ticket` (`20260806100000_...:2069-2076`, pgTAP `023:568-575`); `tasks.entity_type` nutzt dieselbe Enum (`PlatformEntityType.maintenanceTicket`); Audit-Zählung über RLS mit `audit.read` (pgTAP `023:398-405`).

**Beide Verknüpfungswege existieren serverseitig und werden von keinem Aufrufer geschrieben** — das ist der eigentliche Inhalt der Parity-Lücke „Document-/Task-Links". Die Documents-Fläche rendert für beide Entitätstypen bereits ein Label (`lib/ui/screens/docs/widgets/document_badges.dart:70-71`), erzeugt aber keine solche Verknüpfung; `PlatformEntityType.maintenanceTicket` kommt in `lib/` außerhalb der Enum-Deklaration überhaupt nicht vor.

### 7.4 Dokumente statt doppelter Dateiablage

Verbindlich: **Ein Foto oder Beleg wird als Dokument gespeichert und mit dem Ticket verknüpft. Das Ticket speichert keine Datei und keinen Pfad.**

- Ablage: Bucket `documents`, Pfad `{workspace_id}/{document_id}/{version_no}/{datei}`, max 50 MB, erzeugt ausschließlich von `DocumentUploadPort.storageObjectPath`. Kein Update-/Delete-Policy auf `storage.objects` — Versionen werden nie überschrieben.
- Verknüpfung: `document_links(entity_type='maintenance_ticket', entity_id=<ticketId>, link_role=<Rolle>)`, eindeutig je (Dokument, Entität).
- **`link_role` wird endlich benutzt.** Das Feld existiert (≤ 100 Zeichen, Server-Check `20260723100000_...:355-358`) und wird von **keinem** heutigen Aufrufer geschrieben. Kuratierte Rollen: `photo_before`, `photo_after`, `quote` (Angebot), `order` (Auftrag), `invoice` (Rechnung), `report` (Protokoll), `evidence` (Nachweis), `warranty` (Gewährleistung).
- Damit trägt die Verknüpfung die Semantik, ohne Schema-Änderung — das ist die Antwort auf „Dokument-/Foto-Verknüpfungen statt doppelter Dateispeicherung".
- **Grenze:** Der Documents-Contract kennt keine Bildrolle und keine Vorschau-/Miniaturansicht; `mime_type` wird gespeichert und angezeigt (`document_detail_panel.dart:274`), aber nirgends für Bilderkennung, Vorschau oder Rollenlogik ausgewertet. Fotos sind in v2 also verknüpfte Dateien mit Rolle, keine Galerie. → `DOCUMENTS-COMPLETE-01`.

## 8. Permissions and security behavior

| Ebene | Regel |
|---|---|
| Sidebar-Sichtbarkeit | `cloudReadPermissionForPage(GlobalPage.maintenance) == 'property.read'` — **eingefroren** (Foundation §3). Sidebar **versteckt** ohne diese Berechtigung. |
| Direktaufruf ohne `property.read` | Forbidden-State `Key('cloud-destination-forbidden')`. |
| Datenlesen | `maintenance.read`, serverseitig. Fehlt sie, liefert `workspace_maintenance_tickets` **`forbidden`**, nicht leer (pgTAP `024:156-164`; für die objektbezogene RPC zusätzlich Integrationstest `:419-433`). UI zeigt Forbidden-State mit „(maintenance.read)". |
| **Mismatch** | Wer `property.read`, aber nicht `maintenance.read` hat, erreicht die Seite und sieht den Forbidden-State. **Bekannt, hier nicht lösbar, gehört zu `PERMISSION-CATALOG-02`** (Screen Map §0.6). Die Spec ändert das Mapping nicht und schlägt keinen Client-Workaround vor. Die Forbidden-Copy muss deshalb *besonders* verständlich sein und die fehlende Fähigkeit beim Namen nennen. |
| Mutationen | `maintenance.manage`. Aktionen ohne sie **deaktiviert mit Tooltip** (entdeckbar, Foundation §3). Der Server bleibt Autorität — der Controller-Gate ist Komfort, nicht Sicherheit. |
| Dokumentaktionen | zusätzlich `document.manage`; Verifikation `document.verify` ist **nicht** Teil dieser Fläche. |
| Aufgabenaktionen | zusätzlich `task.manage` (Anlegen), `task.read` (Anzeigen). |
| **AAL** | **AAL2 ist Pflicht für jeden Read und jeden Write** (DEC-025: `private.is_aal2()` steht in `private.has_workspace_permission` — `20260812100000_...:52-59` und `:76-83`). Der Vertragskommentar behauptet das Gegenteil (DEF-4) — Dokufehler, kein Verhaltensspielraum. Die Fläche prüft AAL **nicht selbst**; erzwungen wird sie ausschließlich serverseitig. `SupabaseSecurityGate` prüft nur Authentifizierung, gewählten Arbeitsbereich und abgeschlossene TOTP-Einschreibung — **keine AAL-Stufe** (`lib/ui/screens/security/supabase_security_gate.dart:19-22`). |
| RLS | `maintenance_tickets_select_maintenance_read`, `force row level security`, keine DML-Grants für `anon`/`authenticated`. Mutation ausschließlich über die auditierten RPCs. |
| Entzug während der Sitzung | Zustand fällt fail-closed über die bestehende Entitlement-Revalidierung; die Fläche kämpft nicht dagegen (Foundation §3), sondern rendert den Forbidden-State. |
| Workspace-Isolation | Aufruf auf einen fremden Arbeitsbereich → `forbidden` (pgTAP `024:148-155`); der Adapter verweigert zusätzlich Kommandos, deren Actor ≠ angemeldeter Nutzer ist (Adaptertest `:283`). |

## 9. Realtime / freshness behavior

- Quelle: `MaintenanceCapexQueryInvalidationSource.watchWorkspace`; die Tabellen `maintenance_tickets` und `capex_projects` sind in der `supabase_realtime`-Publikation (`20260806110000`).
- **Invalidierung, keine Datenlieferung** — REST bleibt kanonisch. Eintreffende Invalidierungen fremder Aggregate werden verworfen; Reconciliation-Signale gelten immer.
- Debounce 250 ms (`invalidationCoalesceWindow`, `maintenance_tickets_controller.dart:103`). Die Gateway-Quelle reconciled bei **jedem** Join erneut — bewusst so, `supabase_maintenance_capex_query_invalidation_adapter_test.dart:113-132` pinnt genau das („a rejoin must reconcile again, not stay latched on the first"). Erst das Coalescing im Controller (`maintenance_tickets_controller.dart:330-335`) macht daraus **einen** Reload statt eines Bursts. Beide Hälften dieser Garantie dürfen nicht geschwächt werden.
- Hintergrund-Reload **leert nie sichtbare Daten** (Foundation §11) — das heutige `state.copyWith(listPhase: loading)` in `load()` blendet die Liste bei jeder Invalidierung auf Skeleton um. Das muss auf „Refresh ohne Blanking" umgestellt werden (nur der erste Ladevorgang zeigt Skeleton).
- `liveUpdatesDegraded` ist im Maintenance-Controller **nicht vorhanden** — das Flag muss wie in `ReferenceSliceState` durchgereicht und über `NxLiveUpdatesNotice` gerendert werden. Gehört zu `REALTIME-DEGRADED-WIRING-01`, nicht in diesen Screen-PR (Foundation §13).

## 10. Screen states

| Zustand | Rendering (Foundation §11) |
|---|---|
| idle (kein Arbeitsbereich) | `NxEmptyState(Icons.workspaces_outline, 'Kein Arbeitsbereich aktiv')` |
| initial loading | **`NxListSkeleton`** (Foundation §18, seit `791849f` auf `main`; die private Kopie `_TicketsSkeleton` entfällt) |
| background refresh | Liste bleibt sichtbar, dezenter Fortschrittshinweis im Header |
| empty (ohne Filter) | „Noch keine Wartungstickets" + CTA „Ticket anlegen", auf `maintenance.manage` gegated |
| **no-match (mit Filter)** | eigener Zustand: `Icons.filter_alt_off_outlined`, „Keine Treffer für diesen Filter.", Aktion „Filter zurücksetzen" |
| forbidden | `Icons.lock_outline`, „Kein Zugriff auf Wartungstickets", „… benötigt die Berechtigung (maintenance.read)." |
| error | `Icons.cloud_off_outlined` + `FilledButton.icon(Icons.refresh, 'Erneut versuchen')` |
| partial | Objektname nicht auflösbar → rohe Id in `dataMonoStyle` (Bestandsverhalten, testgepinnt); Handwerkername nicht auflösbar → „Handwerker (nicht mehr verfügbar)" |
| Detail: idle | „Wähle ein Ticket aus der Liste." |
| Detail: loading | `LinearProgressIndicator` in `NxCard` |
| Detail: notFound | **Pflicht** — „Dieses Ticket wurde entfernt oder zusammengeführt, während die Liste geöffnet war." (praktisch nur bei Rechteentzug erreichbar, da es kein Delete gibt) |
| Detail: forbidden / error / ready | wie oben |
| validation error | Feldfehler im Dialog; Serverfehler mit `field` werden auf das Feld gemappt, sonst §12 Fallback |
| action in progress | Submit-Button zeigt Fortschritt und ist deaktiviert |
| action success | SnackBar, dann `clearAction()` |
| action failure | SnackBar mit Controller-Meldung |
| **conflict** | Foundation §10: Dialog bleibt **offen**, Eingabe bleibt erhalten, Banner nennt die Serverversion, Aktionen „Neu laden" und „Erneut speichern". Der heutige Verwerfen-Dialog (`maintenance_tickets_panel.dart:146-173`) konvergiert. |
| realtime degraded | `NxLiveUpdatesNotice` unter dem Header, passiv, max 2 Zeilen |
| Session-/Auth-Übergang | Shell-Sache; die Fläche rendert `idle` |

## 11. Search / filter / sort

| Dimension | Werte | Ort | Default |
|---|---|---|---|
| Suche | Titel, Beschreibung, Schadenort, Schadennummer | 🔒 `MAINTENANCE-QUERY-01` | leer |
| Status | 10 Einzelwerte + „Alle Status" + Sammelwert **„Nur offene"** | Einzelwert **serverseitig** heute; der Sammelwert braucht einen **Status-Mengenparameter** → `MAINTENANCE-QUERY-01` (§14-G2) | „Nur offene", sobald der Mengenparameter existiert |
| Priorität | 4 Werte + „Alle Prioritäten" | **serverseitig** | alle |
| Objekt | Objekte des Arbeitsbereichs + „Alle Objekte" | 🔒 `MAINTENANCE-QUERY-01` | alle |
| Einheit | nur wenn ein Objekt gewählt ist | serverseitig auf der objektbezogenen Fläche; hier 🔒 `MAINTENANCE-QUERY-01` | alle |
| Kategorie | §7.2 + „Alle" | 🔒 `MAINTENANCE-QUERY-01` | alle |
| Handwerker | Parteien mit offener `contractor`-Rolle + „Nicht zugewiesen" + „Alle" | 🔒 `MAINTENANCE-QUERY-01` | alle |
| Fälligkeit | `overdue` · `today` · `week` · `later` · `none` · alle | 🔒 `MAINTENANCE-QUERY-01` | alle |
| Versicherungsfall | ja / nein / alle | 🔒 `MAINTENANCE-QUERY-01` | alle |

- Dropdowns sind **typisiert und nullable** (`DropdownButtonFormField<T?>`, `null` = „Alle …"). Kein `'__all__'`-Sentinel (Foundation §7).
- **Default „Nur offene"** ist eine bewusste Produktentscheidung: die Fläche ist eine Arbeitsliste, kein Archiv. Sie muss sichtbar als aktiver Filter dargestellt werden (nicht als heimliche Vorauswahl), sonst wirken fehlende Tickets wie Datenverlust. Sie setzt einen **serverseitigen Status-Mengenparameter** voraus — eine clientseitige Reduktion einer paginierten Seite wäre genau der von §20-D1 abgelehnte Weg.
- **Sortierung:** serverseitig definiert und stabil (Teil von `MAINTENANCE-QUERY-01`). Default: `dueAt` aufsteigend, Tickets ohne Frist zuletzt, danach `priority` absteigend. Clientseitiges Sortieren eines teilgeladenen Keysets ist nach Foundation §7 ausgeschlossen und wird auch nicht als Übergangslösung eingeführt.
- **Persistenz:** nur Session/Screen-lokal; Reset beim Arbeitsbereichswechsel. Gespeicherte Filter → 🔒 `MAINTENANCE-QUERY-01`.
- **Zuordnung server- vs. clientseitig:** heute sind nur Status und Priorität serverseitige Parameter. Alle übrigen Dimensionen dieser Tabelle setzen `MAINTENANCE-QUERY-01` voraus — sie werden **nicht** ersatzweise über einen clientseitig vollgeladenen Satz gelöst (§20-D1). Auf der objektbezogenen Schwester-Fläche filtert der Server zusätzlich nach `unitId`.

## 12. Forms and validation

Alle Formulare sind modale Dialoge (Foundation §9/§10), Breite über `ResponsiveConstraints.dialogWidth`, Rückgabe eines Ergebnisobjekts via `Navigator.pop`. Sie gehören in `lib/ui/screens/maintenance/widgets/maintenance_ticket_dialogs.dart` (die heutigen Inline-`// --- Dialogs ---`-Blöcke konvergieren).

### 12.1 „Ticket anlegen"

| Gruppe | Feld | Pflicht | Steuerelement | Validierung |
|---|---|---|---|---|
| Objekt & Ort | Objekt | ja | Dropdown | Pflichtfeld |
| | Einheit | nein | Dropdown, „Gesamtobjekt (keine Einheit)" | lädt erst nach Objektwahl |
| | Schadenort | nein | Textfeld | ≤ 2000 Zeichen |
| Vorgang | Titel | ja | Textfeld | „Pflichtfeld"; 1–200 Zeichen |
| | Beschreibung | nein | Textfeld, 3 Zeilen | ≤ 10 000 Zeichen |
| | Kategorie | ja | Dropdown §7.2 | Default `general` |
| | Priorität | ja | Dropdown | Default `normal` |
| | Fällig am | nein | Datumsauswahl mit Löschknopf | keine Vergangenheitssperre (bewusst — Nacherfassung) |
| Zuweisung | Handwerker | nein | Party-Picker (offene `contractor`-Rolle) | Server prüft; `dependencyConflict` → Feldfehler |
| Kosten | Kostenschätzung | nein | Zahlenfeld, deutsche Dezimaltrennung über `lib/ui/utils/number_parse.dart` | ≥ 0 |
| | Währung | **bedingt** | Dropdown **ohne Vorauswahl** (leer, bis der Nutzer wählt); trägt das Ticket bereits eine Währung, wird sie übernommen und schreibgeschützt gezeigt | **Pflicht, sobald ein Betrag steht** — sonst Feldfehler „Betrag benötigt eine Währung". Keine implizite Vorbelegung: es gibt keine autoritative Währungsquelle (§20.1) |
| Versicherung | Versicherungsfall | nein | Schalter | — |
| | Regulierungsstand | nein | Dropdown, nur wenn Schalter an | 1–100 Zeichen |
| | Schadennummer | nein | Textfeld, nur wenn Schalter an | ≤ 200 Zeichen |

Buttons `TextButton('Abbrechen')` + `FilledButton('Anlegen')`; Submit zeigt Fortschritt und sperrt. Bei ungespeicherten Eingaben fragt das Schließen nach („Änderungen verwerfen?"). Fokus landet auf dem ersten Feld.

**Kein Schalter „Verknüpfte Aufgabe erstellen".** (§6.9)

### 12.2 „Ticket bearbeiten"

Dieselben Felder außer **Objekt** (serverseitig geschützte Spalte), **Einheit** (der Update-Pfad kennt sie nicht, §7.1) und **Status** (nur per Transition). Zusätzlich **Ist-Kosten**. Die Einheit wird im Bearbeiten-Dialog **schreibgeschützt angezeigt**, nicht weggelassen — sonst wirkt sie wie nicht gesetzt.

**Coalesce-Semantik sichtbar machen:** Da `update_maintenance_ticket` einen Wert nicht auf null zurücksetzen kann, zeigen befüllte optionale Felder statt eines Löschknopfs den Hinweistext „kann nicht mehr geleert werden". Ein Löschknopf, der nichts tut, ist schlimmer als kein Löschknopf. (Alternative — ein Server-seitiges Clear-Flag — ist in `MAINTENANCE-DATA-04` benannt.)

### 12.3 „Ist-Kosten erfassen" (bei `resolved` / `invoiced`)

Wird **nur angeboten, wenn das Ticket bereits eine Währung trägt** (§20.1-3). Dann ein Feld: **Betrag**, die Währung wird daneben schreibgeschützt angezeigt. Leer lassen = überspringen.

Trägt das Ticket noch keine Währung, zeigt der Dialog statt eines Betragsfeldes einen `NxNotice` mit dem Verweis auf „Ticket bearbeiten", wo Betrag und Währung in **einem** Kommando gesetzt werden. So erreicht nie ein Betrag ohne Währung den Server, und es entsteht keine nicht-atomare Zwei-Kommando-Folge.

### 12.4 Serverfehler-Zuordnung

| Fehler | Anzeige |
|---|---|
| `validationFailed` mit `field` | Feldfehler an genau diesem Feld |
| `dependencyConflict` | Feldfehler am Handwerker-Feld |
| `versionConflict` | Konflikt-Banner im offenen Dialog (§10) |
| `mutationInProgress` / `mutationConflict` | „Diese Änderung läuft bereits." — kein zweiter Absendeversuch |
| `forbidden` | SnackBar + Aktion bleibt deaktiviert |
| `infrastructureFailure` | SnackBar mit Retry-Angebot |

## 13. Shared components

**Wiederverwenden:** `ListFilterTemplate`, `ListFilterBar`, `NxPageHeader`, `NxBreadcrumbs`, `NxActionToolbar`, `NxCard`, `NxSectionHeader`, `NxDataTableShell`, `NxEmptyState`, `NxStatusBadge`, `NxKpiRow`/`NxKpiTile`, `ResponsiveConstraints`, `maintenance_capex_badges.dart` (die einzige Statusabbildung der Domäne — Foundation §12), `lib/ui/utils/number_parse.dart`.

**Aus Wave 1 — liegt seit `791849f` auf `main` und ist verbindlich zu verwenden:** `NxListSkeleton({rows, rowHeight})` · `NxSplitView({list, detail, showDetail, onBackToList, backLabel: 'Zur Liste', 3:2 ab AppLayout.splitViewMinWidth})` · `NxNotice({message, kind: NxNoticeKind.info|warning|error, title, icon, action})` · `NxLiveUpdatesNotice({message?})` · **`NxEmptyState.error({title, description, onRetry, retryLabel})`** als die eine Fehler-/Retry-Darstellung. Die privaten `_TicketsSkeleton`/`_Skeleton`-Kopien und jede hand­gerollte Retry-Variante entfallen ersatzlos.

**Kleine, rückwärtskompatible Erweiterungen (dürfen im Feature-PR reiten):** Datums-Zellformatierung in der Tabelle; ein `Overdue`-Kennzeichen als `NxStatusBadge(kind: error)` neben dem Fälligkeitsdatum.

**Neuer geteilter Kandidat:** `PartyPickerField` (Auswahl einer Partei nach Rolle) — wird von dieser Fläche, der objektbezogenen Schwester-Fläche und perspektivisch von Leasing gebraucht. Wenn er mehr als ein Dropdown mit serverseitigem Rollenfilter wird, ist er ein eigenes `SHARED-UI-*`-Paket, kein Feature-PR-Anhängsel (Master Plan §7).

**Entfällt:** private `_TicketsSkeleton`-Kopie, handgerollte `Wrap`-Toolbar, Verwerfen-Konfliktdialog.

## 14. Backend gaps

Kein Screen-PR implementiert etwas hiervon (Master Plan §8).

| ID | Bedarf | Domäne / Repo | Schema / RLS / Permission? | Paket |
|---|---|---|---|---|
| **G1** | Abkürzungs- und Abbruchkanten in STM-006 (§D.4), `reason` verpflichtend beim Abbruch | `maintenance_capex`, `private.maintenance_ticket_status_transition_allowed`, `transition_maintenance_ticket_status` | Funktion + pgTAP + Rollback-Test; **kein** Spaltenwechsel | `MAINTENANCE-DATA-03` |
| **G2** | **Skalierbarer Lesepfad** — Keyset-Paginierung, Statusfilter **als Einzelwert und als Menge** (Sammelwert „Nur offene"), Property-/Entity-Scope, Contractor-Filter (Assignee-Filter sobald G18 existiert), definierte serverseitige Sortierung, Zeit-/Terminfilter. Für `workspace_maintenance_tickets` **und** `maintenance_tickets`. Unpaginiertes Vollladen ist kein freigegebener Produktionspfad, ein Client-Hard-Cap kein Ersatz (§20-D1) | `maintenance_capex` | RPC-Signatur (breaking) + pgTAP + Rollback-Test | **`MAINTENANCE-QUERY-01`** |
| **G3** | Feld-Gaps: `extension_date` (A3); eine Möglichkeit, optionale Felder per Update **auf null zurückzusetzen** (Clear-Flags statt reinem `coalesce`); **`p_unit_id` am Update-Pfad**, damit eine falsch zugeordnete Einheit korrigierbar wird | dito | Spalte + Constraint (`extension_date >= due_at`) + RPC-Parameter | `MAINTENANCE-DATA-04` (nur noch Feld-Gaps; der Query-Teil ist nach G2 gewandert) |
| ~~G4~~ | **entfällt.** Der Ist-Kosten-/Währungs-Defekt (DEF-1) ist **kein** Backend-Gap: `create_maintenance_ticket` und `update_maintenance_ticket` tragen `p_currency_code` bereits (`20260806100000_...:711`, `:909`). Der Fix ist Bestandteil von `MAINTENANCE-PARITY-01`, red-first (§20.1). Das frühere Platzhalterpaket `MAINTENANCE-COST-FIX-01` ist ersatzlos gestrichen | — | — | — |
| **G5** | Verknüpfung Ticket ↔ CapEx-Projekt (Mangel aus einer Maßnahme; Maßnahme aus gehäuften Tickets) | `maintenance_capex` | Spalte `capex_project_id` **oder** Nutzung von `document_links`-Muster; Entscheidung im Paket | `MAINTENANCE-CAPEX-LINK-01` |
| **G6** | Wiederkehrende Wartung: Schedule-Entität, Intervall, Generierung je Fälligkeit mit `generated_key`-Konvergenz (AGG-019-Muster), Checklisten-Definition und -Ergebnis, Pflichtnachweis, Erinnerungen | neu | Tabellen + RLS + Permissions (`maintenance.schedule.*`?) + STM | `MAINTENANCE-PREVENTIVE-01` |
| **G7** | Serverseitiger Fälligkeits-/Überfälligkeits-Job, der Notifications erzeugt (Ersatz für den Legacy-Knopf `createDueNotifications`; der Index `maintenance_tickets_due_idx` existiert bereits genau dafür) | `platform_audit_jobs` + `maintenance_capex` | Job/Function + Notification-Kind | `MAINTENANCE-NOTIFY-01` |
| **G8** | Lesbarer Audit-Verlauf je Ticket in der UI (die Events existieren und sind mit `audit.read` RLS-lesbar) | `platform_audit_jobs` | vermutlich nur Read-Port + Adapter | `AUDIT-01` (Tracker Wave 3) |
| **G9** | Bild-/Medienrolle im Documents-Contract, Vorschau, Mehrfach-Upload; **atomares** create+link | `documents_compliance` | RPC (kombiniert) + ggf. Spalte | `DOCUMENTS-COMPLETE-01` |
| **G10** | Feinere Berechtigungen: Seite unter `maintenance.read` statt `property.read` (DEF-5); optional `maintenance.verify` für den Abnahmeschritt (§D.3) | Permission-Katalog | Katalog + Rollen + Navigation | `PERMISSION-CATALOG-02` |
| **G18** | **Interner Bearbeiter** als eigenes Feld, fachlich getrennt vom Auftragnehmer (§20-D2). Verifiziert: `public.maintenance_tickets` hat kein solches Feld, und `contractor_party_id` ist über `private.maintenance_contractor_party_valid` an eine **offene `contractor`-Rolle** gebunden — eine Zweckentfremdung würde serverseitig mit `dependency_conflict` scheitern | `maintenance_capex` (+ `identity_access` für die Modellfrage Workspace-Mitglied vs. Party) | Spalte + Constraint + Filterparameter in G2 + pgTAP | **`MAINTENANCE-ASSIGNEE-01`** |
| **G19** | **Freie Kommentare/Threads** am Ticket (§20-D3). Es existiert kein persistenter Comment-/Activity-Contract | neu | Tabelle + RLS + Aufbewahrung | **`MAINTENANCE-COMMENTS-01`** (FUTURE) |
| **G11** | *Dokufehler, kein Verhalten*: `maintenance_capex_repository.dart:8` behauptet „no AAL2", DEC-025 verlangt AAL2 (DEF-4). Gleiche falsche Aussage in `document_repository.dart:10-11` und `party_repository.dart:7-8` | Doku | nein | `DOCS-CURRENCY-02` (trivial) |

**Nicht beantragt:** Planpins (§D.5), Anlagenregister (B.3-R4/P6), externer Handwerker-Zugang (B.2-P9), Delete (B.3-R6), Board/Kalender (§20-D4). Als **FUTURE** geführt statt „nicht beantragt": `MAINTENANCE-COMMENTS-01` (G19), `MAINTENANCE-PREVENTIVE-01`, `WARRANTY-01` — Statusübersicht in §22.2.

## 15. Accessibility and usability

- Tastatur: Dialoge fangen den Fokus, `Escape` bricht ab, `Enter` sendet einfeldrige Formulare; Fokus landet beim Öffnen auf dem ersten Feld. Tabellenzeilen sind über Tab erreichbar und mit `Enter` auswählbar.
- Kontrast ausschließlich über Tokens; kein Roh-Hex. Overdue wird **nie nur** rot dargestellt — das Wort „Überfällig" trägt die Aussage (`NxStatusBadge`).
- Icon-only-Buttons tragen `tooltip`. Deaktivierte Aktionen nennen im Tooltip die fehlende Fähigkeit (`maintenance.manage`).
- Touch-Ziele ≥ 44 px mobil; Zeilenhöhe nicht unter `dataRowMin`.
- Semantik: Zeileninhalt ist textfirst; Badges tragen Text, nicht nur Farbe; dekorative Glasflächen bleiben aus dem Semantikbaum.
- Destruktive Klarheit: Das Lösen einer Dokumentverknüpfung (F8) sagt im Dialogtext ausdrücklich, dass die Datei erhalten bleibt.

## 16. Analytics / audit / history

- **Serverseitig ist alles bereits auditiert**: `create`, `update` und `transition_status` schreiben append-only über `private.finish_maintenance_mutation` mit `correlationId`, `reason`, Vorher-/Nachher-Snapshot. pgTAP zählt 12 `maintenance_ticket`-Events im Fixturelauf und liest sie über RLS mit `audit.read`.
- **In der UI ist davon nichts sichtbar.** v2 zeigt im Detailabschnitt *Verlauf* ausschließlich, was das DTO trägt (`createdAt/By`, `updatedAt/By`, `resolvedAt`) und benennt offen, dass der vollständige Verlauf noch nicht lesbar ist (F12). Es wird **kein** clientseitiger Pseudo-Verlauf konstruiert.
- Nach `AUDIT-01`: Verlaufsliste mit Zeitpunkt, Akteur, Kommando, geänderten Feldern und `reason` — das ist NexImmos Äquivalent zu PlanRadars Journal und der Kern der Nachweisfähigkeit (A4).
- Keine Geheimnisse und keine Nutzdaten in Logs; `reason`-Freitext ist Nutzereingabe und wird als solche behandelt.

## 17. Test plan

### Unit / application (`test/features/maintenance_capex/`)
- Abbildung der Filterdimensionen aus §11 auf die Query-Parameter: jede Dimension einzeln und kombiniert; Fälligkeits-Buckets an den Grenzen (23:59 gestern, heute 00:00, heute+7d). Geprüft wird, **welche Anfrage gestellt wird** — nicht eine clientseitige Reduktion.
- KPI-Berechnung inkl. Summe mit gemischten/fehlenden Währungen.
- Sortierung: der Controller fordert den Default `dueAt` aufsteigend, Nullwerte zuletzt, **serverseitig** an und sortiert nicht selbst nach.
- Statusangebot = `allowedNextStatuses`, nie mehr.
- Prioritätsabbildung `urgent → high` beim Erzeugen einer Aufgabe (F9).
- Controller: `forbidden` → Forbidden-Phase (nicht Error); `versionConflict` trägt `currentTicket` und nie `currentProject`; Hintergrund-Reload setzt **nicht** auf `loading`.

### Widget / UI (`test/ui/screens/maintenance/`)
- Alle Zustände aus §10, jeder mit stabilem `Key('maintenance-<element>')`; Tests binden an Keys, nie an deutsche Copy (Foundation §17).
- Forbidden-State nennt wörtlich `maintenance.read` (Bestandstest erhalten).
- Objektzelle springt auf `/property-maintenance/<propertyId>` (Bestandstest erhalten).
- Aktionen ohne `maintenance.manage` sind **deaktiviert und tragen einen Tooltip** (nicht versteckt).
- Konfliktdialog **behält** Formulareingaben (Foundation §10) — Regressionstest gegen das heutige Verwerfen.
- Kein Overflow bei 390×844, 1024×768, 1440×900 und 320 px Breite, hell und dunkel.
- Split-Pane wechselt bei `> tabletMax`; darunter ersetzt das Detail die Liste und der Rücksprung „Zur Liste" existiert.

### Repository / integration (`test/integration/`, lokale Supabase)
- **Neu, deckt DEF-1 (red-first, zwingend)**: Transition nach `resolved` mit `costActual` auf einem Ticket **ohne** `currencyCode`. Der Test dokumentiert den heutigen Zustand (Check-Constraint-Verletzung → `infrastructureFailure` mit generischer Meldung) und wird grün, sobald die UI diesen Aufruf gar nicht mehr erzeugt. Der zugehörige Widget-Test ist der eigentliche Regressionsschutz: bei fehlender Ticketwährung erscheint **kein** Betragsfeld.
- Dokumentverknüpfung: `link_document(entity_type='maintenance_ticket')` auf ein existierendes Ticket → `ok`; auf ein nicht existierendes → `not_found`; doppelte Verknüpfung → `validation_failed`.
- `link_role` wird gespeichert und wieder gelesen.
- Aufgabe mit `entity_type='maintenance_ticket'` anlegen und über `TaskListQuery.entity` zurücklesen.
- Handwerkerzuweisung: Partei ohne offene `contractor`-Rolle → `dependencyConflict` (Bestandsverhalten).

### pgTAP (nur bei Backend-Paketen)
- `MAINTENANCE-DATA-03`: jede neue Kante erlaubt, jede nicht beantragte weiterhin `validation_failed`; Abbruch ohne `reason` abgelehnt; `resolved_at`-Constraint hält; Rollback-Test.

### Staging E2E
1. Anmelden mit MFA → AAL2 → Instandhaltung öffnen.
2. Ticket mit vollem Formular anlegen (Einheit, Kategorie, Frist, Handwerker, Schätzung + Währung, Versicherungsfall).
3. Bearbeiten: Priorität und Frist ändern → Version steigt.
4. Zwei Sitzungen: beide bearbeiten dasselbe Ticket → zweite bekommt Konflikt, **Eingabe bleibt erhalten**, „Erneut speichern" gelingt.
5. Ganze Kette `new → … → invoiced → archived` durchlaufen; `resolved_at` erscheint bei `resolved`, verschwindet beim Reopen.
6. Ist-Kosten mit Währung erfassen → Betrag erscheint in Liste und Detail.
7. Dokument hochladen und mit Rolle `invoice` verknüpfen; Verknüpfung lösen → Dokument bleibt im Documents Workspace.
8. Aufgabe aus dem Ticket erzeugen; im Tasks-Screen wieder auffindbar.
9. **Negativ:** Nutzer mit `property.read` ohne `maintenance.read` → Forbidden-State (nicht leere Liste). Nutzer mit `maintenance.read` ohne `maintenance.manage` → alle Mutationsaktionen deaktiviert mit Tooltip.
10. **Negativ:** fremder Arbeitsbereich → `forbidden`.
11. Realtime: Änderung in Sitzung A erscheint in Sitzung B ohne Reload; Netz trennen und wiederherstellen → **ein** Reconcile, Degraded-Notice erscheint und verschwindet.
12. Filter setzen → „Keine Treffer" ist als eigener Zustand mit „Filter zurücksetzen" erkennbar.

Staging-Fixtures (Objekte, Einheiten, Parteien mit offener Contractor-Rolle, Rollen `manager`/`reader`/`noperm`) müssen existieren, weil die Module sie brauchen — nicht um isolierte Infrastrukturbeweise zu fabrizieren (Master Plan §10).

## 18. Acceptance criteria

1. **AC-1** Ein Nutzer mit `maintenance.manage` legt ein Ticket mit Einheit, Kategorie, Fälligkeit, Handwerker, Kostenschätzung und Währung an; alle Werte sind nach dem Neuladen unverändert in Liste und Detail sichtbar.
2. **AC-2** Ein bestehendes Ticket kann bearbeitet werden. (Heute unmöglich — das ist der zentrale Parity-Punkt.)
3. **AC-3** Ist-Kosten werden beim Übergang nach `resolved` gespeichert, **wenn** das Ticket eine Währung trägt; trägt es keine, wird kein Betragsfeld angeboten, sondern auf „Ticket bearbeiten" verwiesen. Ein Betrag ohne Währung erreicht den Server nie. Nirgends wird eine Währung stillschweigend vorbelegt. Ein red-first-Test belegt den Defektzustand vor dem Fix (§20.1).
4. **AC-4** Die KPI-Kachel „Überfällig" zeigt exakt die Anzahl offener Tickets mit `dueAt` vor heute 00:00; ein Klick filtert die Liste auf genau diese Menge.
5. **AC-5** Angeboten werden ausschließlich die Statusziele aus `allowedNextStatuses`; ein serverseitig abgelehnter Übergang erzeugt eine erklärende Meldung und ein Neuladen, keinen stillen Fehlschlag.
6. **AC-6** Ein Versionskonflikt **verwirft keine Eingabe**: der Dialog bleibt offen, nennt die Serverversion und bietet „Neu laden" und „Erneut speichern".
7. **AC-7** Ein Dokument kann mit Rolle verknüpft und wieder gelöst werden; das Lösen **löscht das Dokument nicht** und der Bestätigungstext sagt das.
8. **AC-8** Es wird **niemals** automatisch eine Aufgabe zu einem Ticket erzeugt; eine Aufgabe entsteht nur durch explizite Nutzeraktion und ist über die Ticket-Entitätsreferenz wieder auffindbar.
9. **AC-9** Ein Nutzer mit `property.read`, aber ohne `maintenance.read` sieht den Forbidden-Zustand mit dem Namen der fehlenden Fähigkeit — nicht eine leere Liste und nicht einen Infrastrukturfehler.
10. **AC-10** Ein Nutzer ohne `maintenance.manage` sieht alle Mutationsaktionen **deaktiviert mit Tooltip**, nicht versteckt und nicht scheinbar bedienbar.
11. **AC-11** Ein Reconnect erzeugt genau **einen** kanonischen Reconcile; ein Hintergrund-Reload **leert die sichtbare Liste nicht**.
12. **AC-12** „Keine Treffer bei aktivem Filter" ist ein eigener Zustand mit „Filter zurücksetzen" und unterscheidbar von „noch keine Tickets".
13. **AC-13** Kein horizontaler Überlauf bei 320/390/1024/1440 px in hell und dunkel; unter `tabletMax` ersetzt das Detail die Liste und ist über „Zur Liste" verlassbar.
14. **AC-14** Jede sichtbare Zahl stammt aus dem Contract. Es gibt keine aus Konstanten erfundene Kennzahl (Screen Map §0.7).
15. **AC-15** Der Screen enthält keine Delete-Aktion und keinen Client-Workaround für die fehlenden STM-Kanten; fehlende Fähigkeiten werden benannt, nicht umgangen.

## 19. Out of scope

- **Planpins / Grundrissverortung** (§D.5) — Future Scope, kein Paket.
- **Anlagen-/Equipment-Register**, QR-/NFC-Tags.
- **Kommentarsystem** am Ticket (§B.2-P8).
- **Externer Handwerker-Zugang** in jeder Form (Portal, Gastlink, E-Mail-Antwort) (§B.2-P9).
- **Delete** in jeder Form (§B.3-R6).
- **Wiederkehrende Wartung, Inspektionen, Checklisten** — FUTURE, `MAINTENANCE-PREVENTIVE-01`; dieser Screen baut keinen Vorgriff.
- **Board- und Kalenderansicht** — FUTURE (§20-D4).
- **Freie Kommentare/Threads** — FUTURE, `MAINTENANCE-COMMENTS-01` (§20-D3). Erlaubt sind nur `description` und `reason`.
- **Interner Bearbeiter** — bis `MAINTENANCE-ASSIGNEE-01` weder angezeigt noch simuliert (§20-D2).
- **Berichte/Export/Statistik** — hängt an P2-D09.
- **Benachrichtigungen** — `MAINTENANCE-NOTIFY-01`; die Fläche verspricht keine, die es nicht gibt.
- **Berechtigungs-Mapping** korrigieren — `PERMISSION-CATALOG-02`.
- **CapEx-Projekte** in jeder Hinsicht — Schwester-Spec `property_maintenance_capex.md`.
- **Legacy-Screens löschen** — eigenes Hygiene-Paket, erst nach abgeschlossenem Harvest und der Bauteilzustand-/Gewährleistungs-Bewertung der Schwester-Spec.
- **Legacy-Freitextfelder** `assigneeName`/`assigneeType` — werden nicht wiederbelebt; der interne Bearbeiter kommt als echtes Feld (§20-D2).

## 20. Closed decisions

Alle vier zuvor offenen Punkte sind am **2026-08-28** im Final-Approval-Review verbindlich entschieden. Sie sind hier als getroffene Entscheidungen festgehalten, nicht mehr als Optionen.

**D1 — Unpaginiertes workspace-weites Laden: ABGELEHNT.**
Das vollständige Laden aller Tickets eines Arbeitsbereichs ohne Cursor ist **kein freigegebener Produktionspfad**. Ein clientseitiges Hard-Cap ist ausdrücklich **kein** Ersatz — es verschweigt Daten, statt sie zu liefern. Der workspace-weite Lesepfad wird deshalb als eigenes Backend-Paket **`MAINTENANCE-QUERY-01`** geführt und diese Fläche ist bis dahin **BLOCKED** (§22). `MAINTENANCE-QUERY-01` muss mindestens tragen: serverseitige Paginierung (Keyset, Foundation §6) · Statusfilter · Property-/Entity-Scope · Contractor-Filter und — sobald `MAINTENANCE-ASSIGNEE-01` existiert — Assignee-Filter · definierte, serverseitig stabile Sortierung · Zeit-/Terminfilter (`due_at`, überfällig) für die KPI- und Fälligkeitssichten dieses Screens.
Die **objektbezogenen Reads bleiben nutzbar**: `public.maintenance_tickets(workspace, property, unit?, status?, priority?)` und `public.capex_projects(workspace, property, status?)` sind vollständig, contract-getragen und auf einen fachlich natürlichen Scope begrenzt. Die Schwester-Fläche ist damit **APPROVED** und trägt die erste Implementierungswelle. Restrisiko, benannt statt versteckt: auch diese RPCs sind unpaginiert; ein Objekt mit sehr vielen Tickets lädt viel. `MAINTENANCE-QUERY-01` soll die Paginierung deshalb für **beide** Lesepfade liefern, nicht nur für den workspace-weiten.

**D2 — Interner Bearbeiter: fachlich bejaht, Contract fehlt.**
Ein Ticket **darf** einen internen verantwortlichen Bearbeiter haben, fachlich getrennt vom externen Auftragnehmer. Geprüft: `public.maintenance_tickets` trägt dafür **kein Feld** — die Spaltenliste (§7.1) kennt nur `contractor_party_id`, und `private.maintenance_contractor_party_valid` verlangt für dieses Feld eine Partei mit **offener `contractor`-Rolle**. Eine Zweckentfremdung wäre nicht nur falsch, sie würde vom Server mit `dependency_conflict` abgelehnt.
Also: **`MAINTENANCE-ASSIGNEE-01`** als eigener Backend-Gap (§14-G18). Bis dahin gilt ausdrücklich **nicht**: das Contractor-Feld überladen · automatisch eine Aufgabe erzeugen · einen UI-lokalen Bearbeiter speichern. Das Ticket bleibt die Arbeit; eine Aufgabe entsteht weiterhin nur nach der Regel in §6.9. Die Fläche zeigt bis dahin keinen internen Bearbeiter und behauptet auch keinen.

**D3 — Kommentare: nicht Bestandteil von Core V1.**
Freie Ticket-Kommentare setzen einen echten persistenten Comment-/Activity-Contract voraus, den es nicht gibt. Verwendet werden dürfen ausschließlich die **vorhandenen strukturierten Felder**: `description` am Ticket und `reason` im Command-Envelope (`MaintenanceCapexCommandContext.reason`), das serverseitig in den Audit-Datensatz wandert. Ein freier Kommentar-/Thread-Bereich ist **FUTURE** → **`MAINTENANCE-COMMENTS-01`**. Ausdrücklich verboten: lokaler Widget-State als Kommentarspeicher und ein aus Client-Ereignissen zusammengesetzter Pseudo-Activity-Feed. Der lesbare Verlauf kommt aus dem serverseitigen Audit-Trail über `AUDIT-01` (§16).

**D4 — Board und Kalender: FUTURE.**
Welle 1 dieser Fläche ist **Liste + Detail**. Board- und Kalenderansicht kommen frühestens, wenn Query-, Termin- und Statussemantik serverseitig belastbar sind — also nach `MAINTENANCE-QUERY-01` (Sortierung, Terminfilter) und `MAINTENANCE-DATA-03` (Statuskanten). **Keine zusätzliche Ansicht allein zur Legacy-Parity.** Das Statusverteilungs-Diagramm des Legacy-Dashboards fällt damit ebenfalls aus Welle 1.

### 20.1 Verbindliche Disposition des Ist-Kosten-/Währungs-Defekts

`IST-KOSTEN-CURRENCY-DEFECT` (DEF-1) ist **kein Future-Gap**. Prüfung des Contracts:

- `MaintenanceTicketDraft.currencyCode` und `MaintenanceTicketUpdateDto.currencyCode` existieren; die RPCs `create_maintenance_ticket` und **`update_maintenance_ticket` tragen `p_currency_code`** (`20260806100000_...:909`). Der Contract trägt Währung also bereits vollständig.
- Nur `transition_maintenance_ticket_status` trägt sie **nicht** — dort wird `cost_actual` per `coalesce` gesetzt, ohne `currency_code` zu berühren.

**Daraus folgt (Fix ist Bestandteil von `MAINTENANCE-PARITY-01`, nicht eines Folgepakets):**

1. **Währung wird zur echten Pflichteingabe, sobald ein Betrag erfasst wird** — im Anlege- und im Bearbeiten-Formular, über die bestehenden Contract-Felder. Es gibt **keine Vorauswahl**: NexImmo besitzt keine autoritative Währungsquelle (weder `public.workspaces` noch `public.properties` führen eine Währungsspalte), und eine vorausgewählte Währung ist eine stille Annahme.
2. **Autoritative Quelle ist der Datensatz selbst**, wenn er bereits eine Währung trägt: dann wird sie übernommen und schreibgeschützt angezeigt, nicht erneut erfragt.
3. **Die Ist-Kosten-Eingabe beim Statuswechsel wird nur angeboten, wenn das Ticket bereits eine Währung trägt.** Andernfalls verweist der Dialog auf „Ticket bearbeiten", wo Betrag und Währung gemeinsam und in **einem** Kommando gesetzt werden. Damit erreicht nie wieder ein Betrag ohne Währung den Server, und es entsteht kein nicht-atomares Zwei-Kommando-Manöver.
4. **Red-first-Regressionstest ist zwingend**: ein Test, der heute rot ist, weil ein Betrag ohne Währung als `infrastructureFailure` mit generischer Meldung endet, und nach dem Fix grün, weil die Eingabe den Server gar nicht erst erreicht. Zusätzlich ein Integrationstest, der das Serververhalten dokumentiert (§17).
5. Ein zusätzlicher `p_currency_code` an der Transition-RPC wird **nicht** beantragt: er wäre nach (3) wirkungslos. Das frühere Platzhalterpaket `MAINTENANCE-COST-FIX-01` entfällt ersatzlos.

Dieselbe Regel gilt für das stille `'EUR'` beim CapEx-Anlegen (DEF-7) — Einzelheiten in der Schwester-Spec §5.2. **Keine implizite EUR-Annahme, an keiner Stelle.**

Präzedenz im eigenen Code, die diese Entscheidung stützt: `create_rent_roll_snapshot` leitet die Währung aus den beitragenden Verträgen ab und verlangt sie sonst ausdrücklich vom Aufrufer — mit dem Kommentar *„Nothing contributes, so nothing implies a currency. Guessing here would invent data"* (`20260730120000_...:1625-1637`).

## 21. Implementation handoff

**Umfang (`MAINTENANCE-PARITY-01`, ein Branch/Worktree, Welle A):** die gemeinsamen Ticket-Komponenten und alle contract-getragenen Ticket-Flows. Die **workspace-weite Liste dieser Fläche gehört nicht in Welle A** — ihr Lesepfad ist auf `MAINTENANCE-QUERY-01` blockiert (§20-D1). Welle A liefert die Flows deshalb auf der objektbezogenen Schwester-Fläche; diese Fläche folgt in Welle B unverändert nach denselben Spezifikationen.

**Welle A — Reihenfolge:**

| # | Schritt | Status |
|---|---|---|
| A1 | Gemeinsame Ticket-Komponenten extrahieren (Tabelle, Detail, Dialoge, Filterleiste) — aus den heutigen zwei Kopien **eine** | APPROVED |
| A2 | Objektbezogene Fläche: volles Anlege- **und Bearbeiten**-Formular, Split-Pane-Detail, erlaubte Transitionen, Konflikt-UX nach Foundation §10, KPI-Zeile, Einheiten-Filter | APPROVED |
| A3 | Währungs-Defekt beheben (§20.1) — **red-first**, Ticket **und** CapEx | APPROVED |
| A4 | Dokument-Verknüpfungen über `document_links` + `link_role`; Aufgaben-Verknüpfung explizit, nie automatisch | APPROVED |
| A5 | CapEx-Ausbau: Detail, Bearbeiten, volle Spalten, explizite Währung; `capex.approve`-Gating unverändert erhalten | APPROVED |
| A6 | Minimaler Defektfix im heutigen workspace-weiten Panel: Ist-Kosten-Dialog nur bei vorhandener Währung. **Ohne** Rebuild der Liste — ein datenschädigender Defekt auf einer erreichbaren Fläche wartet nicht auf ein Query-Paket | APPROVED |
| A7 | Neue Test-Keys `Key('maintenance-*')` / `Key('property-maintenance-*')` und die Zustandsmatrix | APPROVED |

**Welle B (nach `MAINTENANCE-QUERY-01`):** Rebuild dieser workspace-weiten Fläche auf denselben Komponenten, mit serverseitigen Filtern, Sortierung und Keyset-Paginierung.

**Beteiligte Dateien / Contracts:**
- Ändern: `lib/ui/screens/property_detail/property_maintenance_capex_panel.dart` (Welle A), `lib/features/maintenance_capex/application/property_maintenance_capex_controller.dart`; in A6 punktuell `lib/ui/screens/maintenance/maintenance_tickets_panel.dart`. Welle B: Rebuild von `maintenance_tickets_panel.dart` und `maintenance_tickets_controller.dart`.
- Neu: gemeinsame Ticket-Widgets unter `lib/ui/screens/maintenance/widgets/` (`maintenance_ticket_dialogs.dart`, `maintenance_ticket_detail.dart`, `maintenance_ticket_table.dart`, `maintenance_ticket_filters.dart`), CapEx-Pendants unter `lib/ui/screens/property_detail/widgets/`.
- Lesend anbinden: `documents_compliance` (`DocumentLinkPort`, `DocumentUploadPort`, `SignedUrlPort`), `platform_audit_jobs` (`TaskRepository`), `contacts_parties` (`PartySearchPort` mit `roleType: contractor`) — **nur über deren application-Contracts**, Muster `OperationsAlertsController`.
- Unverändert: `maintenance_capex_repository.dart`, beide DTO-Dateien, der Supabase-Adapter, **alle** Migrationen.

**Liegt bereits auf `main` (keine Vorbedingung mehr):** `UX-FOUNDATION-IMPL-01` ist implementiert und gemerged (`791849f`, PR #43). Nutzbar und verbindlich zu verwenden: `NxListSkeleton` (`rows`, `rowHeight`), `NxSplitView` (`list`, `detail`, `showDetail`, `onBackToList`, Default-Label „Zur Liste", 3:2 ab `AppLayout.splitViewMinWidth`), `NxNotice` (`NxNoticeKind.info/warning/error`), `NxLiveUpdatesNotice`, `NxEmptyState.error(...)` als **die** Fehler-/Retry-Darstellung. Die privaten `_TicketsSkeleton`/`_Skeleton`-Kopien und die hand­gerollten Retry-Varianten entfallen ersatzlos.

**Getrennt behandelte Backend-Gaps:** §14 und §22. Insbesondere gilt in jedem Screen-PR: **kein** Delete · **keine** neue Statuskante · **keine** RPC-Signaturänderung · **keine** Migration · **kein** interner Bearbeiter · **kein** Kommentarspeicher.

**Erforderliche Tests:** §17, mindestens die Widget-Zustandsmatrix, der Konflikt-Regressionstest (Eingabe bleibt erhalten), der **red-first Währungstest** aus §20.1 und die vier Viewports (320/390/1024/1440). Bestehende Tests bleiben grün: Forbidden-Copy nennt `maintenance.read`; Objektzelle navigiert auf `/property-maintenance/<id>`; „Freigeben" ist ohne `capex.approve` deaktiviert; ein Ticket-`forbidden` blockiert den CapEx-Tab nicht.

**Harte Invarianten, die nicht regredieren dürfen:**
1. Fehlende `maintenance.read` erzeugt `forbidden`, niemals eine leere Liste.
2. Jede Mutation trägt `expectedVersion`, `mutationId` und `correlationId`; Idempotenz-Replay liefert dieselbe Version.
3. Angeboten wird nur, was STM-006 erlaubt; der Server bleibt Autorität.
4. Realtime bleibt invalidation-only; die Gateway-Quelle reconciled je Join, das 250-ms-Coalescing macht daraus einen Reload.
5. Kein direkter `Supabase.instance.client`-Zugriff aus UI oder Controller.
6. Keine Schema-, RLS- oder Permission-Änderung im Screen-PR.
7. Kein fabrizierter Wert, kein Pseudo-Audit-Verlauf, keine implizite Währung.

## 22. Status classification and dependency matrix

Stand 2026-08-28, Basis `origin/main` `3a11b09`. Gilt für **beide** Maintenance-Specs.

### 22.1 Spec-Status

| Fläche | Status | Begründung |
|---|---|---|
| **`property_maintenance_capex.md`** (objektbezogen) | **APPROVED** | Alle Lesepfade und alle geplanten Flows sind vollständig contract-getragen (§20-D1). Trägt Welle A. |
| **`maintenance_tickets.md`** (workspace-weit) | **BLOCKED** — Lesepfad | Die Fläche hat genau einen Read, und der ist unpaginiert (§20-D1). Blocker: `MAINTENANCE-QUERY-01`. **Alle Ticket-Flows dieser Spec sind inhaltlich APPROVED** und werden in Welle A auf der Schwester-Fläche gebaut; blockiert ist nur die Liste selbst. Ausnahme A6 (Defektfix) ist freigegeben. |

### 22.2 Dependency-Matrix

| Package | Scope | Status | Blocker | Parallelisierbar mit |
|---|---|---|---|---|
| **MAINTENANCE-PARITY-01** Welle A | Gemeinsame Ticket-Komponenten, objektbezogene Fläche, Create/Edit/Transitions, Documents+`link_role`, Task-Link, Konflikt-UX, Währungsfix, CapEx-Ausbau, Test-Keys | **APPROVED** | — (Foundation liegt auf `main`) | DOCUMENTS-COMPLETE-01 · TASKS-NOTIFICATIONS-01 · ADMIN-AREA-01 · PROPERTY-WORKSPACE-01 |
| **MAINTENANCE-PARITY-01** Welle B | Rebuild der workspace-weiten Fläche auf denselben Komponenten | **BLOCKED** | MAINTENANCE-QUERY-01 | — (setzt Welle A voraus) |
| **MAINTENANCE-QUERY-01** | Keyset-Paginierung, Status-/Scope-/Contractor-/Assignee-/Terminfilter, definierte Sortierung; für den workspace-weiten **und** den objektbezogenen Read | **BLOCKED** (Backend) | Backend-Kapazität | MAINTENANCE-DATA-03 · MAINTENANCE-ASSIGNEE-01 — beide parallel entwickelbar; nur der Assignee-**Filter** innerhalb von QUERY-01 setzt MAINTENANCE-ASSIGNEE-01 voraus und wird sonst nachgereicht |
| **MAINTENANCE-DATA-03** | Fünf Lifecycle-Kanten (Abkürzung + Abbruch mit Pflicht-`reason`), §D.4 | **BLOCKED** (Backend) | Backend-Kapazität | MAINTENANCE-QUERY-01 · Welle A |
| **MAINTENANCE-ASSIGNEE-01** | Interner Bearbeiter als eigenes Feld, §20-D2 | **BLOCKED** (Contract fehlt, verifiziert) | Backend-Kapazität; Modellfrage Workspace-Mitglied vs. Party | MAINTENANCE-QUERY-01 |
| **MAINTENANCE-DATA-04** | Feld-Gaps: `extension_date`, Clear-Flags gegen die `coalesce`-Semantik, `p_unit_id` am Update-Pfad | **BLOCKED** (Backend) | Backend-Kapazität | alles außer Welle A |
| **MAINTENANCE-CAPEX-LINK-01** | Verknüpfung Ticket ↔ CapEx-Projekt | **BLOCKED** (Backend) | Backend-Kapazität | Welle A |
| **CAPEX-CANCEL-01** | Echter Abbruch-Lifecycle für CapEx-Projekte, Schwester-Spec §15-D2 | **BLOCKED** (Contract fehlt, verifiziert) | Produktentscheidung zur Freigabe-Rücknahme; Backend | Welle A — blockiert **nur** die Abbruch-Aktion, nicht das übrige CapEx-Management |
| **CAPEX-DATA-01** | `workspace_capex_projects` (portfolioweite CapEx-Lesefläche) | **BLOCKED** (Backend) | Backend-Kapazität | MAINTENANCE-QUERY-01 |
| **MAINTENANCE-NOTIFY-01** | Serverseitiger Fälligkeits-/Überfälligkeits-Job → Notifications | **BLOCKED** (Backend) | TASKS-NOTIFICATIONS-01 (Notification-Fläche) | MAINTENANCE-QUERY-01 |
| **AUDIT-01** | Lesbarer Audit-Verlauf je Ticket/Projekt | **todo (fremdes Paket)** — offene Fähigkeit für diese Flächen, kein Blocker der Implementierung | platform_audit_jobs-Adoption | Welle A (die Fläche hält den Platz frei und behauptet nichts) |
| **PERMISSION-CATALOG-02** | Seite unter `maintenance.read` statt `property.read`; optional `maintenance.verify` | **BLOCKED** | Katalog-/Rollenentscheidung | Welle A. **Blockiert die Non-Admin-Staging-E2E** (§17), nicht die Implementierung |
| **DOCUMENTS-COMPLETE-01** | Bild-/Medienrolle, Vorschau, atomares create+link | **todo (fremdes Paket)** — begrenzt die Fotodarstellung, blockiert die Verknüpfung nicht | eigenes Wave-2-Paket | Welle A — Fotos sind bis dahin verknüpfte Dateien mit Rolle, keine Galerie |
| **MAINTENANCE-COMMENTS-01** | Freie Kommentare/Threads | **FUTURE** | echter Comment-/Activity-Contract | — |
| **MAINTENANCE-PREVENTIVE-01** | Wiederkehrende Wartung, Prüffristen, Checklisten, Nachweise, Anlagen-/Bauteilregister | **FUTURE** | eigene Spec + Backend | — |
| **WARRANTY-01** | Gewährleistung als eigenes Konzept | **FUTURE** | MAINTENANCE-CAPEX-LINK-01 | — |
| **Planpins** | Grundriss-Positionierung | **FUTURE** | Plan-Contract + Documents-Media | — (kein Tracker-Eintrag) |
| **Board / Kalender** | Zusätzliche Ansichten | **FUTURE** | MAINTENANCE-QUERY-01 + MAINTENANCE-DATA-03 | — |
| **UI-HYGIENE-01** (Legacy-Löschung) | Legacy-Maintenance-Screens entfernen | **BLOCKED** | §7 des Reviews: erreichbare Ersatzfläche · migrierte Funktionen · targeted + full tests grün · Staging-E2E des Replacements bestanden | nach Welle A/B, eigener Cleanup-Schritt |

### 22.3 Was ausdrücklich **nicht** blockiert ist

Keiner der oben genannten Backend-Gaps blockiert: Ticket anlegen · Ticket bearbeiten über den bestehenden `update`-Command · die erlaubten Lifecycle-Transitionen · Dokument-Verknüpfungen über `document_links`/`link_role` · die bestehenden CapEx-Flows inklusive Freigabe · den Währungs-Defektfix · die Foundation-konforme Konflikt-UX · die neuen Shared- und Screen-Test-Keys. Diese Flows sind heute contract-getragen und gehören in Welle A.
