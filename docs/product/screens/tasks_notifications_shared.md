# TASKS & NOTIFICATIONS — GEMEINSAME INTERAKTIONSLOGIK (TASKS-NOTIFICATIONS-V2)

## Metadata

- Package / screen ID: **TASKS-NOTIFICATIONS-CORE-01** (Tracker-Klammerzeile `TASKS-NOTIFICATIONS-01`, Wave 2)
- Domain: `platform_audit_jobs` (Aggregate `public.tasks`, `public.notifications`)
- Route: keine eigene — dieses Dokument ist der normative Vertrag hinter `task_center.md` und `notification_inbox.md`
- Current implementation file(s):
  - `lib/features/platform_audit_jobs/application/platform_repository.dart` (467), `platform_providers.dart` (24, **nur** `taskRepositoryProvider`), `platform_domain_event.dart`, `platform_query_invalidation_source.dart`
  - `lib/features/platform_audit_jobs/domain/{task_dto,notification_dto,platform_entity_type}.dart`
  - `lib/features/platform_audit_jobs/data/{supabase_platform_repository_adapter,supabase_outbox_adapter,supabase_domain_event_consumer_adapter}.dart`
  - `supabase/migrations/20260723120000_p2_d04_domain_event_envelope.sql`, `20260723130000_p2_d04_tasks_notifications.sql`, `20260812100000_security_aal_enforcement.sql`
  - Legacy (fachliche Quelle, zur Laufzeit tot): `lib/ui/screens/tasks/tasks_screen.dart` (1887), `task_templates_screen.dart` (1197), `lib/ui/screens/property_detail/property_tasks_screen.dart` (1415), `lib/data/repositories/tasks_repo.dart` (800), `lib/core/services/task_generation_service.dart` (304), `lib/ui/screens/notifications_screen.dart` (122), `lib/data/repositories/notifications_repo.dart` (102), `lib/core/notifications/notification_rules.dart` (90)
- Planning status: **APPROVED (2026-08-28)** — die sechs offenen Entscheidungen sind in §20 verbindlich geschlossen. Freigabe gilt **inkrementweise**: §0.2 klassifiziert jedes Inkrement als APPROVED / BLOCKED / FUTURE. Der Paketstatus ist damit *nicht* pauschal APPROVED.
- Dependencies: `UX-FOUNDATION-IMPL-01` (**auf main, `791849f`**) · `TASK-QUERY-01`, `TASK-ENTITY-REGISTRY-01`, `TASK-SCHEDULER-01`, `PERMISSION-CATALOG-02` (Backend, separat) · `SHELL-ROUTING-01` (Minimalrouten reiten hier mit)
- Related screens: `task_center.md`, `notification_inbox.md`, `admin_members.md` (Mitgliederverzeichnis), Maintenance-Tickets, Operations-Alerts, Documents-Workspace, Property-Workspace

**Basis der Analyse:** `origin/main` `bf0693c` (Commit 2026-08-29; final verifiziert 2026-09-01), neu gefetcht und verifiziert. Alle Aussagen zu Contracts, RPCs, RLS, Policies und Tests sind gegen Code und Migrationen geprüft, nicht aus Dokumenten übernommen. Die Vorgängerfassung stand auf `46effaba`; seither sind `UX-FOUNDATION-IMPL-01` (`791849f`, PR #43), die `ADMIN-MEMBERS-V2`-Spec (`de8e979`) und deren Paket A1 (`53c9eb9`, PR #44, gemergt 2026-08-29) gelandet und in dieser Fassung berücksichtigt.

**Sprachkonvention:** Abschnittsüberschriften englisch (die beiden Screen-Specs bleiben so gegen `SCREEN_SPEC_TEMPLATE.md` diffbar), Fließtext deutsch wie Screen Map, Tracker und `admin_members.md`; Bezeichner, Wire-Namen, Permission-Keys und UI-Copy wörtlich.

**Struktur-Hinweis:** Dies ist kein Screen und folgt der Vorlage nur teilweise. §§1–8 und §§12–21 entsprechen der Vorlagen-Nummerierung; §9 (Monday reference matrix) und §10 (Automation) ersetzen die dort stehenden Screen-Abschnitte, weil beide Themen flächenübergreifend sind. Vorlagenkonformität wird an `task_center.md` und `notification_inbox.md` geprüft.

---

## 0. Freigabe

### 0.1 Warum es dieses dritte Dokument gibt

Task Center und Notification Inbox teilen ein Aggregatpaar, einen Adapter, eine Realtime-Topologie und eine Automations-Grenze. Zwei Screen-Specs, die diese Verträge je für sich beschreiben, erzeugen zwei Wahrheiten über dieselbe Sache — genau der Fehler, den Master Plan §5/§7 verhindern soll. Dieses Dokument ist normativ für beide; die Screen-Specs zitieren es als „Shared §n". Es ist außerdem der Ort, an dem die vier Begriffe getrennt werden, deren Vermischung im Legacy-Stand die Hauptquelle von Rauschen war (§4).

### 0.2 Statusklassifizierung je Inkrement (verbindlich)

Maßstab ist ausschließlich: **trägt der heute existierende Contract das Inkrement vollständig und ehrlich?** Kein Inkrement ist APPROVED, wenn die UI dafür Funktionalität vortäuschen müsste, die der Query-Contract nicht korrekt liefert (Entscheidung OD-2).

#### APPROVED — implementierbar mit dem bestehenden Contract

| ID | Inkrement | Vertragliche Deckung |
|---|---|---|
| **A1** | Task Center Grundfläche: Shell, `NxPageHeader`, Tabs, Liste, Split-Detail, Zustandsvokabular, Responsive, Realtime-Invalidierung, Degraded-Notice | Foundation-Komponenten auf main; `PlatformQueryInvalidationSource` |
| **A2** | Task-Liste lesen: Filter `status` (ein Wert), `assignedTo`, Entity-Paar, `includeArchived`; feste Sortierung `created_at DESC, id DESC`; Keyset „Weitere laden" | `searchTasks` / `TaskListQuery` |
| **A3** | Aufgabe anlegen: Titel, Beschreibung, Kategorie, Priorität, Fälligkeit, Kontext | `create_task` (`task.manage`) |
| **A4** | Aufgabe bearbeiten (ohne Status) mit `expectedVersion` und `TaskFieldEdit`-Semantik | `update_task` (`task.manage` + `task.read`) |
| **A5** | Statuswechsel entlang STM-012 inkl. Archivieren | `transition_task_status` |
| **A6** | „Mir zuweisen" und „Zuweisung entfernen" | `update_task.assignedTo`; braucht **kein** Mitgliederverzeichnis — der Auslöser kennt die eigene `auth.uid()` |
| **A7** | Kontextbindung auf die neun Registry-Werte; Objekt-Scope über das Entity-Paar | `tasks.entity_type`/`entity_id`, `document_link_entity_type` |
| **A8** | Bulk-Aktionen auf A5/A6, max. 50 Zeilen, Teilerfolgsbericht | N Einzel-RPCs mit je eigener `mutationId`/`expectedVersion` |
| **A9** | Board-Ansicht als **vier status-gebundene Keysets** (`open`/`in_progress`/`blocked`/`done`), je Spalte eigenes „Weitere laden" | vier `status.eq`-Abfragen; keine erfundenen Spaltensummen |
| ~~A10~~ | **gestrichen (QC 2026-09-01).** War „Vorlagen-Tab als Fläche mit Leerzustand". Eine leere UI-Fläche ist nicht contract-getragen: „keine Schreiboperation nötig" ersetzt kein Aggregat. Vorlagen sind vollständig **BLOCKED (B9)**. Die Nummer bleibt bewusst unbesetzt, damit A11–A15 stabil bleiben. | — |
| **A11** | Notification-Inbox Grundfläche: Feed, `unreadOnly`, Zeitgruppierung, Split-Detail, Zustände | `notificationFeed` / `NotificationFeedQuery` |
| **A12** | Read-Semantik: einzeln als gelesen markieren, idempotent, `not_found`-Behandlung | `mark_notification_read` |
| **A13** | Echte Deep Links für die auflösbaren Ziele + Route `/tasks/:taskId` | `entity_type`/`entity_id`; Routen reiten auf A14 |
| **A14** | Glocken-Badge mit ehrlicher Zählung („50+" statt erfundener Gesamtzahl) | `unreadOnly`-Feed; **es gibt keine Count-RPC**, die Anzeige gibt das offen zu |
| **A15** | Core-Verdrahtung: `notificationPortProvider` + `platformQueryInvalidationSourceProvider`, Routen `/tasks`, `/tasks/:id`, `/notifications`, Fehlerklassifizierung `forbidden` vs. `infrastructureFailure`, stabile `mutationId`, Readiness-Flip | vorhandener Adapter implementiert alle vier Ports bereits |

#### BLOCKED — Contract reicht nicht; exakter Blocker benannt

| ID | Inkrement | Exakter Blocker |
|---|---|---|
| **B1** | Systemsichten „Meine Aufgaben", „Heute", „Diese Woche", „Überfällig", „Nicht zugewiesen" | **TASK-QUERY-01** — `searchTasks` kann weder auf `due_at` filtern noch danach sortieren, kennt nur *einen* `status`-Wert und kein `assigned_to is null` |
| **B2** | Termine-Ansicht (Fälligkeitskübel) | **TASK-QUERY-01**, wie B1 |
| **B3** | Sortierung nach Fälligkeit, Prioritätsfilter, Mehrfachstatus, Titelsuche | **TASK-QUERY-01** — Sortierung ist fest `created_at DESC`; kein Prioritätsfilter, kein `ilike`, kein FTS auf `tasks` |
| **B4** | Objekt-Rollup („alle Aufgaben zu Objekt X inkl. seiner Einheiten, Verträge, Tickets") | **TASK-QUERY-01** — der Entity-Filter braucht **beide** Hälften, es gibt keine denormalisierte `property_id` und keine Rollup-Beziehung |
| **B5** | Serverseitige Zähler / KPI-Zeile | **TASK-QUERY-01** — keine Aggregat-RPC; jede clientseitige Zahl über einem Keyset ist eine Untergrenze |
| **B6** | Aufgabe **an andere Personen** zuweisen | **TASK-ASSIGNEE-DIRECTORY-01** — das einzige Mitgliederverzeichnis (`list_workspace_members`, `20260722210000_p2_d01_member_directory.sql:37`) ist auf `security.manage` gegated; ein `task.manage`-Inhaber ohne Adminrecht bekommt `forbidden`. Serverseitig ist `assigned_to` schreibbar, aber es gibt keine für ihn lesbare Auswahlquelle. |
| **B7** | Task ↔ Document (in beide Richtungen) | **TASK-ENTITY-REGISTRY-01** — `document_link_entity_type` (`20260723100000:73-83`) hat weder den Wert `document` noch `task` |
| **B8** | Task ↔ Valuation Case | **TASK-ENTITY-REGISTRY-01** — kein Wert `valuation_case`; `scenario` ist ein anderes Aggregat |
| **B9** | **Vorlagen insgesamt**: Vorlagenkatalog, Vorlagen-Tab als sichtbare Fläche, manuelles Instanziieren, „Jetzt erzeugen", wiederkehrende Aufgaben | **TASK-SCHEDULER-01 / DEBT-009** — es gibt **kein Vorlagen-Aggregat, keinen Template-Read-Contract, keinen Template-Write-Contract und keinen Scheduler**; kein `supabase/functions`, kein `pg_cron`, kein `pg_net`. In V1 gibt es deshalb **keinen sichtbaren Vorlagen-Tab**, keinen Platzhalter und keinen Leerzustand, der eine verfügbare Funktion suggeriert |
| **B10** | Fristereignisse `task.due_soon`, `task.overdue`, `task.digest.due`, `document.expiring` | **TASK-SCHEDULER-01** — kein Emitter existiert |
| **B11** | **Alle** Notification-Emitter aus diesem Paket (`task.assigned`, `task.unassigned`, `task.blocked`, `task.done`) | **NOTIFICATION-EMITTER-01** + **PERMISSION-CATALOG-02** — `create_notification` verlangt `notification.manage` **beim Auslöser** (`20260723130000:1326-1331`). Entweder bekäme jeder Aufgaben-Bearbeiter das Recht, beliebige Personen anzuschreiben, oder der Fan-Out gehört serverseitig in `create_task`/`transition_task_status`. Letzteres ist die richtige Lösung und ein Backend-Paket. |
| **B12** | `maintenance.ticket_assigned` | **MAINTENANCE-PARITY-01** (fremdes Paket) |
| **B13** | `operations.signal_raised` | kein Emitter; serverseitige Auswertung fehlt |
| **B14** | „Alle als gelesen markieren" | **NOTIFICATION-READ-02** — kein Bulk-RPC; N Einzelaufrufe sind bei 200 Ungelesenen kein Produktionspfad |
| **B15** | Inbox-Filter nach Art, Kontexttyp, Zeitraum und Volltextsuche | **NOTIFICATION-QUERY-01** — `NotificationFeedQuery` kennt nur `recipientUserId`, `unreadOnly`, `page` |
| **B16** | Empfängergenaues Realtime-Wake | **NOTIFICATION-REALTIME-01** — `notification.fanned_out` trägt weder `aggregate_id` noch Empfängerliste; wer `notification.read` nicht hat, bekommt gar kein Signal |
| **B17** | Staging-E2E mit Nicht-Admin-Rollen | **PERMISSION-CATALOG-02** — außer `admin` existieren keine geseedeten `role_permissions`; alle anderen Rollen leben nur in Testfixtures |

#### FUTURE — bewusst nicht in V1, ohne Contract-Erweiterung nicht diskutieren

| ID | Thema | Warum |
|---|---|---|
| **F1** | Subtask-Hierarchie nach monday-Vorbild | Entscheidung OD-3: keine neue Hierarchie ohne Contract |
| **F2** | Checkliste am Task | heute **nicht ehrlich persistierbar** — kein Sub-Aggregat, keine Tabelle, kein RPC. Nach OD-3 damit FUTURE, nicht BLOCKED. Parity-Verlust gegenüber dem Legacy (`task_checklist_items`) ist bewusst und protokolliert. |
| **F3** | Kommentare / @-Mentions am Task | kein Aggregat, keine Mention-Semantik |
| **F4** | Anhänge am Task | siehe F3 und B7 |
| **F5** | Abhängigkeiten zwischen Aufgaben | §9 #9 REJECT für V1 |
| **F6** | Nutzerdefinierte gespeicherte Sichten | Preferences-Contract fehlt (`SETTINGS-01`, Tracker `blocked(decision)`) |
| **F7** | Notification-Einstellungen je Ereignisart/Objekt | wie F6 |
| **F8** | Dashboards, Portfolio-Rollups zu Aufgaben | P2-D09 |
| **F9** | Automations-Regel-Editor, erweiterte monday-Automationen | §10 |
| **F10** | `estimated_cost` am Task | Entscheidung OD-T5: aus Modell und UI entfernt, kein Feld simulieren |
| **F11** | Retention/Verfall als Produktverhalten | Entscheidung OD-1: eigenes Backend-/Governance-Paket, blockiert V1 nicht |
| **F12** | Teams/Gruppen als Zuweisungsziel | kein Team-Aggregat |
| **F13** | E-Mail-, Push-, Desktop-Zustellung | kein Kanal-Contract |

### 0.3 Dependency-Matrix

| Inkrement | braucht auf `main` | braucht Backend-Paket | blockiert |
|---|---|---|---|
| A15 (Core) | `UX-FOUNDATION-IMPL-01` ✅ `791849f` | — | A1–A9, A11–A14 |
| A1–A9 (Task Center) | A15 | — | — |
| A11–A14 (Inbox) | A15 | — | — |
| A13 Deep Links | A15 (Routen) | — | — |
| B1–B5 | A1, A2 | **TASK-QUERY-01** | „My Work"-Produktwert |
| B6 | A3/A4 | **TASK-ASSIGNEE-DIRECTORY-01** | echte Arbeitsverteilung |
| B7, B8 | A7 | **TASK-ENTITY-REGISTRY-01** | Dokument-/Bewertungsbezug |
| B9, B10 | A1 (Fläche existiert) | **TASK-SCHEDULER-01 (DEBT-009)** | Vorlagen komplett (Katalog, Tab, Erzeugung), Fristereignisse |
| B11 | A11 | **NOTIFICATION-EMITTER-01** (+ PERMISSION-CATALOG-02) | Inbox mit Inhalt |
| B14, B15, B16 | A11 | NOTIFICATION-READ-02 / -QUERY-01 / -REALTIME-01 | Komfort, Live-Frische |
| B17 | alle | **PERMISSION-CATALOG-02** | Staging-Abnahme |
| F1–F13 | — | jeweils eigenes Contract-Paket | — |

**Konsequenz, die im Review ausgesprochen sein muss:** V1 liefert eine vollständige, ehrliche Task-Fläche und eine vollständige, ehrliche Inbox — aber die Inbox bleibt leer, solange `NOTIFICATION-EMITTER-01` nicht existiert, und das Task Center hat kein „My Work", solange `TASK-QUERY-01` nicht existiert. Beides ist Absicht: lieber eine kleine wahre Fläche als eine große, die Zahlen erfindet.

---

## 1. Purpose

1. **Eine einzige Aufgabenwahrheit.** Heute existieren zwei Task-UIs über einer Tabelle, mit divergenten Kategorie-Vokabularen, divergenten Filtern und divergenten Parsern. Ziel: ein Aggregat, eine UI, zwei Einstiegs-Scopings.
2. **Zustellung statt Rauschen.** Der Legacy erzeugt Notifications pro Task genau einmal für immer (`task_generation_service.dart:149-157`), ohne Empfänger, ohne Deep Link, ohne Verfall. Ziel: ein Ereignismodell mit definiertem Auslöser, Empfängerkreis, Relevanzgrund und Sprungziel — und in V1 nur solche Ereignisse, die es wirklich gibt.
3. **Immobilien-Kontext statt generischem PM.** Eine Aufgabe ohne Objektbezug ist in NexImmo die Ausnahme. Der Kontextbezug ist erstklassiges Feld, kein Label.

---

## 2. Primary users and jobs

| Rolle (fachlich) | Job | Braucht zuerst | Entscheidet hier |
|---|---|---|---|
| Asset Management | portfolioweite Kontrolle | was überfällig/blockiert ist *(B1)* | Priorisierung, Neuzuweisung *(B6)* |
| Objektbetreuung / Hausmeister | „Was ist heute meins?" | eigene Aufgaben nach Fälligkeit *(B1)* | Status weiterschalten *(A5)* |
| Vermietung | Fristen im Leasing-Prozess | Aufgaben zu Lease/Unit/Party *(A7)* | Termin, Erledigung |
| Buchhaltung | Belege und Fristen | Aufgaben der Kategorie `finance` | Erledigung |
| Bauleitung / CapEx | Arbeit an Projekten und Tickets | Aufgaben zu `capex_project`/`maintenance_ticket` *(A7)* | Status, Zuweisung *(B6)* |
| Admin | „Wer bekommt was, warum" | Ereignis-/Empfängermatrix | Regeln (später) |

Die kursiven Verweise zeigen, wie stark die Rollenjobs an `TASK-QUERY-01` und `TASK-ASSIGNEE-DIRECTORY-01` hängen. Diese sechs Assignee-Gruppen entsprechen dem Legacy-Vokabular (`asset_management`, `hausmeister`, `bauleitung`, `bauarbeiter`, `buchhaltung`, `vermietung`, `dienstleister`, `task_templates_screen.dart:412-452`) und sind fachlich belastbar; ihre Abbildung auf das Cloud-Modell steht in §7.4.

---

## 3. Entry points and navigation

- Sidebar „Tagesgeschaeft → Aufgaben" (`GlobalPage.tasks`, `routeKey daily_business.tasks`, `app_navigation.dart:456-461`) — unverändert.
- Sidebar „Start → Mitteilungen" (`GlobalPage.notifications`, `routeKey start.notifications`, `:402-408`) — unverändert.
- `GlobalPage.taskTemplates` verliert seine eigene Sidebar-Destination (Screen Map: `MERGE(tasks)`). **Der Zielort ist ein Tab im Task Center — der aber erst mit `TASK-SCHEDULER-01` entsteht (B9); V1 hat keinen Vorlagen-Tab.** Der Enum-Wert bleibt bis dahin bestehen, damit `app_navigation.dart` exhaustiv bleibt; seine Entfernung ist ein Hygiene-Folgepaket (§19).
- Aus Domänenpanels wird über **einen** geteilten Dialog eine Aufgabe erzeugt (§5.2).
- Aus der Inbox springt jede Mitteilung auf ihr Ziel (Auflösung in `notification_inbox.md` §9).

**Deep-Link-Lage:** `cloudRouteTargetFromName` (`app_navigation.dart:121-245`) kennt weder `/tasks` noch `/notifications`. Beide Flächen sind heute nur über den Sidebar-State erreichbar. Die drei Minimalrouten sind Teil von **A15** und damit die einzige Verhandlungsmasse gegenüber `SHELL-ROUTING-01` — ohne sie hat keine Mitteilung ein Ziel.

---

## 4. Information architecture — die vier Begriffe

| Begriff | Was es ist | Speicher | Lebensdauer | Wer sieht es | UI-Ort |
|---|---|---|---|---|---|
| **TASK** | zu erledigende Arbeit mit Verantwortlichem, Termin, Status | `public.tasks` | bis `archived`; kein Delete-Pfad | jeder mit `task.read` im Workspace | Task Center |
| **ACTIVITY** | was an einem Aggregat passiert ist — neutrale, unadressierte Historie | `public.audit_events` + `public.domain_events` | append-only | `audit.read` bzw. `required_permission` der Zeile | Detail-Tab „Aktivität" |
| **NOTIFICATION** | **an eine Person adressierter** Hinweis mit Sprungziel und Lesestatus | `public.notifications` (`recipient_user_id not null`) | serverseitig bestimmt (V1: unbegrenzt, §6.5) | nur Empfänger (+ `notification.read`) | Inbox, Glocken-Badge |
| **SYSTEM EVENT** | technischer Plattformzustand (Realtime unterbrochen, Job fehlgeschlagen, Rechteänderung) | flüchtig im Client-State | Sitzung / bis Reconnect | wer die Fläche offen hat | `NxLiveUpdatesNotice` / `NxNotice` |

**Vier harte Regeln:**

1. **ACTIVITY erzeugt niemals automatisch eine NOTIFICATION.** Jedes Domain-Event zuzustellen ist exakt der Spam-Mechanismus, den §6 verhindert.
2. **SYSTEM EVENT landet niemals in der Inbox.** `liveUpdatesDegraded` ist ein passiver Hinweis unter dem Page-Header (Foundation §13), keine Mitteilung.
3. **TASK ist kein Nachrichtenkanal.** Eine Aufgabe wird zugewiesen, nicht verschickt. Die Zuweisung *löst* eine Mitteilung aus — die Aufgabe bleibt die Arbeit.
4. **NOTIFICATION ist nie die Quelle einer Wahrheit.** Sie trägt Titel, Body, Sprungziel; jede Zahl und jeder Status wird am Ziel neu gelesen. Eine geschriebene Mitteilung ist faktisch unveränderlich: es gibt keine UPDATE-Policy, keinen Write-Grant und außer `mark_notification_read` keinen RPC, der sie anfassen könnte; `notifications_protected_columns` (`20260723130000:153-157`) friert zusätzlich `id`, `workspace_id`, `recipient_user_id`, `kind`, `created_at`, `created_by` ein. Ein Titel mit einer Zahl darin veraltet dauerhaft.

---

## 5. Layout and interaction model — geteilte Muster

### 5.1 Task-Zeile (überall identisch)

```
[NxStatusBadge status] Titel                          [Fällig-Chip]
Kategorie · Zuständig: <Name>            [Kontext-Chip: Objekt/Einheit/…]
```

- Status → Badge-Kind: `open` = `neutral`, `in_progress` = `info`, `blocked` = `warning`, `done` = `success`, `archived` = `neutral` gedimmt. Mapping in `task_badges.dart`, Vorbild `maintenance_capex_badges.dart` (Foundation §12).
- „Überfällig" überschreibt den **Fällig-Chip** (`error`, Text „Überfällig"), nicht das Status-Badge. Der Legacy überschrieb das Prioritätslabel (`tasks_screen.dart:556-562`) und verlor damit die Priorität aus der Zeile.
- Priorität ist ein eigener Chip, sichtbar nur bei `high`.

Geteilter Baustein `NxTaskRow` — Kandidat für `SHARED-UI-TASKROW-01`, siehe §13.

### 5.2 Ein Einstieg „Aufgabe erstellen", überall

Heute existieren drei divergente Anlege-Dialoge (`tasks_screen.dart:959-1268`, `property_tasks_screen.dart:697-943`, `operations_alerts_panel.dart:291-310`) mit unterschiedlichen Feldern, Parsern und Datepicker-Grenzen. Verbindlich wird **ein** `TaskCreateDialog(context: PlatformEntityRef?)`:

- aus einem Domänenpanel geöffnet: `entity` vorbelegt und schreibgeschützt, mit Kontext-Chip;
- aus dem Task Center geöffnet: `entity` ist ein Picker über die neun Registry-Werte;
- Felder, Validierung und Fehler-Mapping definiert `task_center.md` §12. Kein Panel definiert eigene Felder.

### 5.3 Realtime

Beide Flächen konsumieren `PlatformQueryInvalidationSource.watchWorkspace` (`platform_query_invalidation_source.dart:67-75`) über das existierende Debounce-Reload-Muster (Foundation §13). Der Adapter abonniert alle drei Topics (`supabase_domain_event_consumer_adapter.dart:170-174`); jedes wiederverbundene Topic liefert **einen** Reconcile (`:203-217`), ein vollständiger Reconnect also bis zu drei Signale, die der Screen zu **einem** Reload entprellt.

Bekannte Grobheit, benannt und nicht gelöst: `notification.fanned_out` trägt weder `aggregate_id` noch Empfängerliste (`20260723130000:1408-1416`) und invalidiert workspaceweit; ein Empfänger **ohne** `notification.read` bekommt gar kein Wake, weil das Topic `workspace:<id>:notification.read` heißt. → **B16 / NOTIFICATION-REALTIME-01**.

---

## 6. Functional requirements — Ereignismodell

### 6.1 Grundregel

> Eine Notification entsteht nur, wenn **eine benannte Person** wegen dieses Ereignisses **etwas tun oder wissen** muss, das sie sonst verpassen würde.

Alles andere ist ACTIVITY und wird am Objekt gelesen.

### 6.2 Anti-Spam-Mechanik

| # | Regel | Begründung | Durchsetzung |
|---|---|---|---|
| AS-1 | **Kein Self-Notify.** Der Auslöser bekommt nie eine Mitteilung über die eigene Handlung. | Er weiß, was er getan hat. | Emitter filtert `actorId` |
| AS-2 | **Ein Ereignis, ein Empfängerkreis, eine Zeile.** Kein Fan-Out an „alle mit `task.read`". | `create_notification` prüft Mitgliedschaft, deckelt aber nichts (`:1310-1353`); Broadcast wäre sofort Rauschen. | Ereignistabelle §6.3 |
| AS-3 | **Dedupe-Fenster je (Empfänger, kind, Entity).** | verhindert tägliche Wiederholung derselben Meldung | serverseitig nicht vorhanden → Teil von `NOTIFICATION-EMITTER-01`; bis dahin deterministische `mutationId` aus `(kind, entityId, periodKey, recipient)` |
| AS-4 | **Bündeln statt Einzelzustellung bei Massenereignissen.** 40 fällige Aufgaben ergeben *eine* Mitteilung. | Der Legacy-Overdue-Sweep (`task_generation_service.dart:115-134`) erzeugt eine Zeile je Task — bei 200 Objekten unbenutzbar. | Emitter |
| AS-5 | **Statuswechsel benachrichtigen den Verantwortlichen bzw. Ersteller, nie einen Verteiler.** | sonst bekommt der Asset Manager jede Häkchen-Setzung | Ereignistabelle §6.3 |

Der Legacy verletzt AS-1 bis AS-5 vollständig: keine Empfänger, kein Fenster, kein Bündeln, ein `kind` für zwei fachlich verschiedene Regeln (`notification_rules.dart:52-85`), und drei von sechs Produzenten schreiben roh in die Tabelle, vorbei an Repository und Audit.

### 6.3 Ereigniskatalog (geschlossen nach OD-N6)

Aufnahmekriterium: **realer Emitter + eindeutiger Empfänger + Relevanzgrund + gültiger Deep Link.** Wer eines davon nicht erfüllt, ist nicht in V1. `kind` folgt dem Servermuster `^[a-z0-9]+(?:[._-][a-z0-9]+)*$`, Länge 2–100.

**V1-Kandidatenkatalog — vier Ereignisse, alle über `NOTIFICATION-EMITTER-01`:**

| ID | `kind` | Auslöser | Empfänger | Warum | Deep Link | Status |
|---|---|---|---|---|---|---|
| E-T1 | `task.assigned` | `assigned_to` wird auf X gesetzt | X | X hat neue Arbeit | `/tasks/:id` | **BLOCKED (B11)** |
| E-T2 | `task.unassigned` | `assigned_to` wird von X entfernt | X | X soll nicht weiterarbeiten | `/tasks` | **BLOCKED (B11)** |
| E-T5 | `task.blocked` | Transition nach `blocked` | Ersteller, falls ≠ Auslöser | Blockade muss aufgelöst werden | `/tasks/:id` | **BLOCKED (B11)** |
| E-T6 | `task.done` | Transition nach `done` | Ersteller, falls ≠ Auslöser | Abnahme / Weiterarbeit | `/tasks/:id` | **BLOCKED (B11)** |

**Warum auch diese vier blockiert sind — der entscheidende Befund dieser Review:** Sie wären clientseitig auslösbar, aber `create_notification` verlangt `notification.manage` **beim Auslöser** (`20260723130000:1326-1331`). Damit gäbe es nur zwei Wege, und beide sind falsch:

- jeder Aufgaben-Bearbeiter bekommt `notification.manage` — dann kann er beliebige Personen im Workspace mit beliebigem Text anschreiben; oder
- nur Admins lösen Mitteilungen aus — dann entsteht die Mitteilung nicht dort, wo die Arbeit passiert.

Die richtige Lösung ist der **serverseitige Fan-Out innerhalb von `create_task` und `transition_task_status`**: dort ist der Empfängerkreis eindeutig aus der Zeile ableitbar, der Auslöser braucht kein zusätzliches Recht, AS-1 ist strukturell erfüllt, und `mutationId`/Audit bleiben in einem Vorgang. Das ist ein Schema-/RPC-Paket, kein Screen-Detail → **NOTIFICATION-EMITTER-01**.

**Nicht in V1, mit Blocker:**

| ID | `kind` | Blocker |
|---|---|---|
| E-T3/E-T4/E-T7 | `task.due_soon`, `task.overdue`, `task.digest.due` | TASK-SCHEDULER-01 (B10) |
| E-D1 | `document.expiring` | TASK-SCHEDULER-01 + fehlende Objektverantwortlichkeit (B10) |
| E-M1 | `maintenance.ticket_assigned` | MAINTENANCE-PARITY-01 (B12) |
| E-O1 | `operations.signal_raised` | kein Emitter (B13) |
| — | `task.commented`, `task.mentioned` | F3 |

**Neue Ereignisarten entstehen ausschließlich durch explizite Contract-Erweiterung** (OD-N6). Es gibt keinen generischen Notification-Erzeugungspfad in der UI.

### 6.4 Empfängerherleitung

`create_notification` leitet **nichts** her: `p_recipient_user_ids uuid[]` ist die einzige Quelle, wird dedupliziert, auf aktive Mitgliedschaft geprüft, leere Liste ist `validation_failed` (`:1310-1353`). Keine Abonnements, keine Permission-Expansion, kein Limit.

Für die vier V1-Kandidaten ist der Kreis trivial ableitbar (`assigned_to`, `created_by`) — genau deshalb gehört er in den Server-RPC. Für alles Weitere fehlt zusätzlich der Begriff **Objektverantwortlichkeit**: weder `properties` noch `workspace_memberships` tragen eine Zuständigkeit. Das ist eine Voraussetzung von `TASK-SCHEDULER-01`/`NOTIFICATION-EMITTER-01`, kein eigenes Screen-Thema.

### 6.5 Relevanz und Verfall (geschlossen nach OD-1)

- **V1 hat keine clientseitige Retention und kein clientseitiges Löschen.** Die UI zeigt, was der autoritative Server liefert — nicht mehr und nicht weniger.
- Insbesondere wird **kein** clientseitig gerechnetes Relevanzende zur Ausblendung oder Nicht-Zählung benutzt. Ein solches Fenster wäre eine unsichtbare Zweitwahrheit neben dem Server.
- Fachliche Relevanzfenster bleiben als **Anforderung an das Governance-Paket** dokumentiert (`NOTIFICATION-RETENTION-01`, F11): `expires_at`, Dedupe-Fenster, Retention-Job. Das Schema hat heute keins davon; `due_at` wurde bei der Migration bewusst verworfen (`sqlite_to_postgres_platform_audit_jobs_dry_run_mapper.dart:628-633`).
- Die Zeitgruppierung der Inbox ist **keine** Retention: sie ordnet nur, was geladen ist (Begründung in `notification_inbox.md` §11).

### 6.6 Read-Semantik

- Gelesen = `read_at is not null`; einziger Schreibpfad `mark_notification_read` (`:1436-1576`).
- Empfängergebunden **ohne Permission-Check**: fremde Mitteilung ⇒ `not_found`, nie `forbidden` (`:1529-1537`). Die UI rendert das als „nicht mehr verfügbar", nicht als Rechteproblem.
- Idempotent; erneutes Markieren ist Erfolg und schreibt eine Audit-Zeile (`:1547-1554`).
- Publiziert **kein** Domain-Event: andere Sitzungen desselben Nutzers erfahren nichts vom Lesen.
- „Alle als gelesen" existiert nicht → **B14**.
- Ein Zurücksetzen auf ungelesen gibt es nicht und ist nicht geplant.

---

## 7. Data requirements

### 7.1 Was der Vertrag heute trägt

`public.tasks` (`20260723130000:27-104`): `id`, `workspace_id`, `title` (1–300), `description` (≤ 10 000), `category` (Freitext 1–100), `assigned_to` (uuid, muss **aktives** Mitglied sein, `:569-583`), `priority` (`low`/`normal`/`high`), `status` (`open`/`in_progress`/`blocked`/`done`/`archived`), `due_at` (timestamptz), `entity_type`/`entity_id` (beide oder keins), `generated_key` (unveränderlich, partiell unique je Workspace), `archived_at`, Audit- und Versionsspalten.

**Es gibt keine Kostenspalte.** `estimated_cost` existiert im Cloud-Schema nicht und wird nach OD-T5 aus Modell und UI entfernt statt simuliert.

`public.notifications` (`:112-173`): `id`, `workspace_id`, `recipient_user_id` (not null), `kind` (normalisiert), `title` (1–300), `body` (≤ 4000), `entity_type`/`entity_id`, `read_at`, Audit- und Versionsspalten. Keine Severity, kein `expires_at`.

**Statusautomat STM-012** (`private.task_status_can_transition`, `:437-459`), serverseitig erzwungen:

| von \ nach | open | in_progress | blocked | done | archived |
|---|---|---|---|---|---|
| **open** | – | ✅ | ✅ | ❌ | ✅ |
| **in_progress** | ✅ | – | ✅ | ✅ | ✅ |
| **blocked** | ✅ | ✅ | – | ✅ | ✅ |
| **done** | ✅ (auditierter Reopen) | ❌ | ❌ | – | ✅ |
| **archived** | ❌ | ❌ | ❌ | ❌ | terminal |

Zwei Konsequenzen für die UI:
- **`open → done` ist verboten.** Der Legacy-„Mark Done"-Knopf direkt aus `todo` (`tasks_screen.dart:582-588`) hat kein Gegenstück; „Erledigt" erscheint erst ab `in_progress`.
- **Ein No-op-Übergang ist ein Fehler**, kein stiller Erfolg (`:1174-1181`). Die UI deaktiviert den Knopf, statt den Fehler zu provozieren.

### 7.2 Was der Lesepfad nicht kann

`TaskRepository.searchTasks` (Vertrag `platform_repository.dart:372-374`; Adapter `supabase_platform_repository_adapter.dart:246-278`, Gateway-Abfrage `listTasks` ebenda `:71-104`) filtert auf `workspace_id`, **einen** `status`, `entity_type`+`entity_id` (nur wenn **beide** gesetzt), `assigned_to`, `includeArchived`. Sortierung fest `created_at DESC, id DESC`, Keyset über `created_at`.

Damit nicht möglich: Fälligkeitsfilter und -sortierung, Mehrfachstatus, Prioritätsfilter, `assigned_to is null`, Objekt-Rollup, Titelsuche, serverseitige Zähler. Das ist der Inhalt von **TASK-QUERY-01** und der Grund für B1–B5.

### 7.3 Beziehungsmodell

Abgleich der neun gewünschten Bezüge mit `public.document_link_entity_type` (`20260723100000:73-83`), das P2-D04 bewusst wiederverwendet:

| Gewünscht | Registry-Wert | V1 |
|---|---|---|
| Property | `property` | ✅ A7 |
| Unit | `unit` | ✅ A7 |
| Lease | `lease` | ✅ A7 |
| Tenant / Party | `party` | ✅ A7 (Mieter ist eine Partei-Rolle, kein eigener Typ) |
| Maintenance Ticket | `maintenance_ticket` | ✅ A7 |
| CapEx | `capex_project` | ✅ A7 (Projektebene) |
| Portfolio | `portfolio` | ✅ A7 |
| Szenario | `scenario` | ✅ A7 |
| Workspace | `workspace` | ✅ A7 (Träger gebündelter Mitteilungen) |
| **Document** | — | ❌ **B7** |
| **Valuation Case** | — | ❌ **B8** |

Zwei Befunde: **Task ↔ Document ist in beide Richtungen unmöglich** (kein Wert `document` für das Ziel, kein Wert `task` als Link-Ziel für `link_document`) — der Legacy konnte Ersteres (`tasks_repo.dart:566-589`), also ein Parity-Verlust. **Valuation Case fehlt ebenfalls**; `scenario` ist kein Ersatz (`lib/features/valuation/domain/valuation_case_dto.dart`).

**Ein Bezug, nicht viele.** Das Schema erlaubt genau ein `(entity_type, entity_id)`-Paar je Aufgabe. Mehrfachbezüge sind nicht modellierbar und werden in V1 nicht geplant — bewusste Ablehnung des monday-Musters „Connect Boards Column".

**Kein Rollup.** `tasks_entity_idx` ist `(workspace_id, entity_type, entity_id)`; es gibt keine denormalisierte `property_id`. „Alle Aufgaben zu Objekt X inklusive seiner Einheiten" wäre heute N+1 auf dem Client — genau der Fehler von `listWorkflowTasks` (`tasks_repo.dart:65-84`). → B4 / TASK-QUERY-01.

### 7.4 Zuweisung

Legacy `assigned_to` ist ein **freier String**, der Personennamen und Assignee-*Gruppen* mischt (`task_generation_service.dart:66`). Cloud `assigned_to` ist eine **uuid mit Mitgliedschaftsprüfung**.

- **„Mir zuweisen" ist V1-fähig (A6)** — die eigene `auth.uid()` ist bekannt, es braucht keine Auswahlliste.
- **Zuweisung an andere ist BLOCKED (B6).** Der einzige Verzeichnis-Read `listMemberDirectory` → RPC `list_workspace_members` ist auf `security.manage` gegated (`20260722210000_p2_d01_member_directory.sql:37`); `listMembers` liefert für Nicht-Admins höchstens die eigene Zeile. Ein `task.manage`-Inhaber ohne Adminrecht hat also keine lesbare Quelle für den Picker. Fachlich ist das eine Berechtigungsfrage, keine UI-Frage → `TASK-ASSIGNEE-DIRECTORY-01` (fachlich benachbart zu `ADMIN-AREA-01`, das den Verzeichnis-Read produktiv macht).
- **Gruppenzuweisung ist nicht abbildbar** („alle Hausmeister" ist keine uuid). Übergangsweise trägt die fachliche Gruppe die `category`; Teams sind F12.
- **Nur ein Verantwortlicher.** Kein Multi-Assignee, keine Beobachter — damit auch keine Abonnement-Semantik.

### 7.5 Kategorie-Vokabular

Drei divergente Vokabulare über einer schemalosen Spalte: Task-Dialog (`general`, `leasing`, `maintenance`, `finance`, `documents`, `compliance`), Template-Dialog (`general`, `letting`, `maintenance`, `renovation`, `finance`, `document`), Property-Tab (Freitext). Verbindliches Zielvokabular, typisiert im Client, Freitext im Schema:

`general` · `letting` · `maintenance` · `renovation` · `finance` · `document` · `compliance` · `valuation`

Die Template-Schreibweise gewinnt, weil die zehn Standardvorlagen sie tragen und die Migration sonst Inhalte umschreiben müsste. Ein Client-Enum `TaskCategory` mit `fromWire`/Fallback `general` kapselt das; unbekannte Serverwerte werden **angezeigt und erhalten**, aber nicht angeboten.

### 7.6 Fachlicher Inhalt, der erhalten bleiben muss

Die zehn Standardvorlagen (`task_templates_screen.dart:831-1002`) sind echtes Domänenwissen und dürfen mit dem Legacy-Screen nicht verschwinden:

| Vorlage | Bereich | Kategorie | Gruppe | Objektart | Prio | Rhythmus | Fällig |
|---|---|---|---|---|---|---|---|
| Vermietung – Wohnungsübergabe | property | letting | vermietung | residential | high | none | +7 |
| Vermietung – Mietvertrag erstellen | property | letting | vermietung | residential | high | none | +5 |
| Vermietung – Schufa prüfen | property | letting | vermietung | residential | normal | none | +3 |
| Vermietung – Kaution anlegen | property | letting | buchhaltung | residential | normal | none | +10 |
| Instandhaltung – Heizungswartung | asset_property | maintenance | dienstleister | all | high | yearly ×1 | +30 |
| Instandhaltung – Rauchwarnmelderprüfung | asset_property | maintenance | hausmeister | residential | high | yearly ×1 | +30 |
| Instandhaltung – Dachkontrolle | asset_property | maintenance | hausmeister | all | normal | yearly ×1 | +30 |
| Sanierung – Angebot einholen | asset_property | renovation | bauleitung | project | high | none | +14 |
| Sanierung – Beauftragung | asset_property | renovation | bauleitung | project | high | none | +7 |
| Sanierung – Abnahme | asset_property | renovation | bauleitung | project | high | none | +3 |

Je 3–4 Checklistenpunkte in deutscher Fachsprache. Sieben haben `recurrence_rule = 'none'` und konnten vom Legacy-Generator nie erzeugt werden (`task_generation_service.dart:33-35`) — sie sind faktisch ein Katalog zum manuellen Instanziieren.

**Bewahrungspflicht (QC 2026-09-01, verbindlich):** Diese Tabelle samt Checklisteninhalten ist der einzige verbleibende Ort dieses Domänenwissens, seit der Vorlagen-Tab aus V1 gestrichen wurde (B9). Sie **darf nicht verloren gehen**. `TASK-SCHEDULER-01` übernimmt sie in das Vorlagen-Aggregat, **bevor** `UI-HYGIENE-02` `task_templates_screen.dart` löscht; die Reihenfolge ist im Tracker als Blocker abgebildet. Kein anderes Paket darf den Legacy-Screen vorher entfernen.

---

## 8. Permissions and security behavior

### 8.1 Serverseitige Lage (nicht verhandelbar)

| Fläche | Lesen | Schreiben |
|---|---|---|
| Tasks | `tasks_select_task_read` → `task.read` | **keine** Write-Policy, **kein** Write-Grant → nur RPC |
| Notifications | `notifications_select_own_or_read` → `is_aal2() AND (recipient = auth.uid() OR has_workspace_permission(ws,'notification.read'))` (`20260812100000:437-448`) | nur RPC |
| `create_task` | – | `task.manage` |
| `update_task`, `transition_task_status` | – | `task.manage` **und** `task.read` |
| `create_notification` | – | `notification.manage` **beim Auslöser** (Grund für B11) |
| `mark_notification_read` | – | keine Permission; Autorisierung ist die Empfängerbindung |
| `list_workspace_members` | `security.manage` | – (Grund für B6) |

**AAL2 gilt für alles** (DEC-025): `private.platform_command_gate` liefert ohne `aal2` `forbidden` „AAL2 is required for platform mutations", bevor irgendetwas validiert wird (`20260812100000:309-358`); die Lese-Policies laufen über `private.has_workspace_permission`, das mit `is_aal2()` beginnt (`:76-96`). Ein aal1-Nutzer sieht **null** eigene Mitteilungen (pgTAP 027 A6). Die UI darf daraus keinen Leer-Zustand machen.

### 8.2 Clientseitige Lage — der Bruch

`cloudReadPermissionForPage` (`app_navigation.dart:267-291`) bildet `tasks` und `taskTemplates` auf `task.read`, `notifications` auf `notification.read` ab. Das ist korrekt und bleibt.

`lib/core/security/rbac.dart` kennt dagegen `task.read`, `task.create`, `task.assign`, `task.resolve` — Schlüssel, die es **serverseitig nicht gibt** — und kennt `task.manage`, `notification.read`, `notification.manage` **nicht**; `Rbac.canPermission` (`:123-133`) weist jeden Schlüssel außerhalb `Permission.all` ab.

**Verbindliche Regel:** Aktions-Gating liest ausschließlich das **Server**-Permission-Set des aktiven Workspace, niemals `Rbac`. **`PERMISSION-CATALOG-02` wird nicht still im Screen-Paket gelöst** — weder das Vokabular noch die Rollen-Seeds noch das Seiten-Mapping werden hier angefasst.

Hinweis zur Testlage: `test/ui/navigation/app_navigation_test.dart` prüft nur, dass jede `GlobalPage` deterministisch *irgendeine* Readiness und Permission liefert; die konkreten Schlüssel sind nirgends gepinnt (weder `'task.read'` noch `'notification.read'` kommt unter `test/ui/` vor). Ein ergänzender Mapping-Test gehört in A15.

### 8.3 Sichtbar/deaktiviert-Matrix (Foundation §3)

| Aktion | Ohne Recht |
|---|---|
| Seite „Aufgaben" / „Mitteilungen" | Sidebar blendet aus; Deep Link → `Key('cloud-destination-forbidden')` mit „(task.read)" bzw. „(notification.read)" |
| „Neue Aufgabe" | **deaktiviert** mit Tooltip „Benötigt task.manage" |
| Zeilenaktionen Status/Bearbeiten | **deaktiviert** |
| Bulk-Aktionen | **ausgeblendet** |
| Vorlagen-Tab | existiert in V1 nicht (B9); mit `TASK-SCHEDULER-01` gilt: lesen `task.read`, mutieren `task.manage` |
| „Als gelesen markieren" | immer erlaubt |
| Fremde Mitteilung | erscheint nicht; RPC darauf → `not_found` |

### 8.4 Rechteänderung während der Sitzung

Die bestehende Entitlement-Revalidierung räumt fail-closed auf; beide Screens folgen Foundation §3 und kämpfen nicht dagegen. Ein Reload, der `forbidden` liefert, wechselt in den Forbidden-State und verwirft die Liste, statt veraltete Zeilen stehenzulassen.

---

## 9. Monday reference matrix — ADOPT / ADAPT / REJECT

Referenz: monday **Work Management**, öffentliche Produktdokumentation (Stand August 2026). Übernommen werden **User Jobs und Interaktionsmodelle** — kein Branding, keine Assets, kein pixelgenaues UI. Die Spalte „V1" trägt die Klassifizierung aus §0.2.

| # | monday-Konzept | Entscheidung | V1 | NexImmo-Begründung |
|---|---|---|---|---|
| 1 | **Board** (Container mit frei definierten Spalten) | **REJECT** | — | NexImmo hat ein festes Fachschema mit RLS und Audit. Nutzerdefinierte Spalten wären ein zweites, ungeprüftes Datenmodell neben dem Domänenmodell (Bruch von Guardrail 1–5). Der Container ist bei uns das **Objekt**. |
| 2 | **Item** | **ADOPT** | A2 | = `public.tasks`-Zeile |
| 3 | **Subitem** (eigene Zeile, eigene Spalten) | **ADAPT → Checkliste** | **F1/F2** | OD-3: keine neue Hierarchie ohne Contract; die Checkliste ist heute nicht ehrlich persistierbar |
| 4 | **Group** (manuelle farbige Abschnitte) | **REJECT** | — | dritte Ordnungsachse neben Status und Kontext; in NexImmo ist Gruppierung immer ableitbar |
| 5 | **People column / Assignee** | **ADAPT** | A6 / **B6** | genau *eine* uuid, aktives Mitglied; „mir zuweisen" geht, an andere nicht |
| 6 | **Status column** (frei definierbare Labels) | **ADAPT** | A5 | fest, mit serverseitigem Übergangsautomaten STM-012 — der Automat *ist* der Wert |
| 7 | **Priority column** | **ADOPT** | A3/A4 | `low`/`normal`/`high`, nur `high` visuell hervorgehoben |
| 8 | **Date / Timeline column** | **ADAPT** | A3/A4 | nur ein `due_at`. NexImmo-Aufgaben sind Fristen, keine Phasen; Phasen leben in CapEx-Projekten |
| 9 | **Dependency column** (FS/SS/FF/SF, strict/flexible) | **REJECT** | **F5** | Projektplanungs-Feature. Reihenfolgen kommen bei uns aus Vorlagen-Sequenzen, nicht aus einem Gantt |
| 10 | **Updates / Kommentare** | **ADAPT** | **F3** | wichtigster fehlender Kollaborationsbaustein, aber ohne Aggregat. Reaktionen, Pins, GIFs, AI-Zusammenfassung: REJECT |
| 11 | **Activity log** | **ADOPT — existiert** | A1 | `audit_events` + `domain_events`; wird gelesen, nicht neu gebaut. Bei uns rechtlich relevant, bei monday Komfort |
| 12 | **Attachments** | **ADAPT** | **F4/B7** | kein eigener Dateispeicher am Task; NexImmo hat einen geprüften Dokumenten-Contract. Verweis blockiert durch die Registry |
| 13 | **My Work** (Zeitkübel, „hide done") | **ADOPT (Konzept)** | **B1/B2** | wertvollster monday-Job und deckungsgleich mit dem Legacy-KPI-Verhalten. NexImmo-Kübel: Überfällig · Heute · Diese Woche · Später · Ohne Termin. Braucht TASK-QUERY-01 |
| 14 | **Inbox / Update-Feed** (alles aus abonnierten Boards) | **REJECT** | — | genau die ACTIVITY/NOTIFICATION-Vermischung aus §4. NexImmo bekommt eine adressierte Inbox, keinen Aktivitätsstrom |
| 15 | **Bell notifications** (Tabs, Häkchen, Badge, Sprung ins Item) | **ADOPT (Struktur)** | A11–A14 | Sprungziel-Pflicht ist genau das, was heute fehlt. Tabs in V1 auf „Alle/Ungelesen" reduziert (B15) |
| 16 | **Notification settings** (persönlich × Board) | **ADAPT** | **F7** | zweistufig richtig, zweite Achse bei uns Ereignisart × Objekt. Kein Contract. V1 kompensiert durch einen sehr schmalen Katalog statt Stummschalter |
| 17 | **Automations** (Trigger → Bedingung → Aktion) | **ADAPT (konzeptionell)** | §10 | Grammatik übernommen, Ausführung ist Backend. Ein Client-Runner wäre der Legacy-Fehler in neu |
| 18 | **Recurring items** + Vorlagenkatalog | **ADOPT (Konzept)** | **B9** | `generated_key` + partieller Unique-Index ist die Idempotenz-Hälfte davon und existiert; der Scheduler fehlt |
| 19 | **Board views** (12 Ansichten) | **ADAPT auf 2 in V1** | A2/A9 | V1: **Liste** + **Board**. **Termine** ist B2. Kein Gantt, Workload, Map, Form, Pivot — jedes bräuchte Daten, die es nicht gibt |
| 20 | **Saved views** | **ADAPT → Systemsichten** | **B1/F6** | feste Systemsichten statt nutzerdefinierter; beide brauchen TASK-QUERY-01 bzw. einen Preferences-Contract |
| 21 | **Dashboards** | **REJECT hier** | **F8** | Aufgaben-Kennzahlen gehören ins Dashboard-Paket (P2-D09) |
| 22 | **Portfolio rollups** | **REJECT** | **F8** | setzt Board-Hierarchie voraus; NexImmo rollt über die Objekt-Hierarchie auf |
| 23 | **Bulk actions** | **ADAPT, eng** | A8 | nur Status, „mir zuweisen", Archivieren; max. 50, weil es keine Batch-RPC gibt |
| 24 | **Filter / Sort / Search** | **ADOPT (Muster), ADAPT (Umfang)** | A2 / **B3** | über `ListFilterBar`. Was der Server nicht filtert, wird nicht angeboten — lieber weniger Filter als Halbwahrheiten über teilgeladenen Keysets |
| 25 | **Item card / Peek-Panel** | **ADOPT** | A1 | deckt sich mit dem Foundation-Split-Pane (Foundation §8) |
| 26 | **Form view** (externe Eingabe) | **REJECT** | — | anonyme Schreibpfade kollidieren mit AAL2 + RLS (DEC-025) |
| 27 | **@everyone / Team-Mentions** | **REJECT** | — | kein Team-Aggregat; AS-2 verbietet Broadcast-Fan-Out |

**Bilanz:** 8× ADOPT (#2, #7, #11, #13, #15, #18, #24, #25), 11× ADAPT (#3, #5, #6, #8, #10, #12, #16, #17, #19, #20, #23), 8× REJECT (#1, #4, #9, #14, #21, #22, #26, #27). Übernommen wird, was einen *User Job* trägt; abgelehnt wird, was ein *freies Datenmodell* voraussetzt — denn NexImmos Wert ist genau das feste, geprüfte Domänenmodell.

---

## 10. Automation — Vision und Grenze

### 10.1 Grammatik

```
WHEN   <Ereignis>
[IF    <Bedingung>]
THEN   <Aktion>
```

Bewusst identisch zu monday, weil die Grammatik verstanden ist.

### 10.2 Kandidatenkatalog

| ID | Regel | Ausführungsort | V1 |
|---|---|---|---|
| A-01 | WHEN Lease endet in 90 Tagen THEN Aufgabe „Verlängerung prüfen" | Server-Job | **BLOCKED (B9)** |
| A-02 | WHEN Maintenance-Ticket auf `in_progress` THEN Aufgabe „Abnahme terminieren" | RPC-Aufrufer | **BLOCKED (B12)** — gehört zu MAINTENANCE-PARITY-01 |
| A-03 | WHEN Pflichtdokument läuft in 30 Tagen ab THEN Aufgabe + Mitteilung | Server-Job | **BLOCKED (B10)** |
| A-04 | WHEN Vorlage mit Rhythmus fällig THEN Aufgaben je Objekt (idempotent über `generated_key`) | Server-Job | **BLOCKED (B9, DEBT-009)** |
| A-05 | WHEN Aufgabe überfällig THEN Mitteilung an Verantwortlichen | Server-Job | **BLOCKED (B10)** |
| A-06 | WHEN Aufgabe zugewiesen THEN Mitteilung | serverseitig in `create_task`/`update_task` | **BLOCKED (B11)** |
| A-07 | WHEN Operations-Signal hoch THEN Aufgabe | manuell heute vorhanden: `OperationsAlertsController.createTaskFrom` (`operations_alerts_controller.dart:272-308`), ausgelöst aus `operations_alerts_panel.dart:318` | manuell ✅, automatisch **BLOCKED (B13)** |
| A-08 | WHEN CapEx-Projekt in Phase X THEN Aufgabenpaket aus Vorlagensequenz | Server-Job | **BLOCKED (B9)** |

### 10.3 Automation boundaries (verbindlich)

1. **Kein Client führt Automationen aus.** Kein Timer, kein `initState`-Job, kein „beim Öffnen nachgenerieren". Der Legacy-Weg (`app_scaffold.dart:92, 208-236` plus die zweite Kopie in `startup_task_service.dart`) ist **DEBT-009** und steht auf der Verbotsliste von `test/app_runtime_guard_test.dart:49`. Die Sperre bleibt.
2. **Jede Regel, die ohne Nutzerinteraktion feuern muss, ist ein Backend-Paket** — auch wenn sie clientseitig schnell hinzubekommen wäre. Multi-Client-Betrieb macht aus jedem Client-Job einen Wettlauf.
3. **Ein manueller Auslöser ist keine Automation** — aber „Jetzt erzeugen" für eine Vorlage, die auf *alle* Objekte fan-outet, ist ein Serverkommando, kein Client-Loop (Legacy: O(N·(4+M)) sequenzielle Roundtrips ohne Transaktion, `task_generation_service.dart:32-134`).
4. **Idempotenz ist Pflicht.** Jede erzeugende Regel schreibt `generated_key = "<ruleId>:<entityType>:<entityId>:<periodKey>"`. AGG-019 macht daraus eine konvergente Operation: eine zweite Erzeugung liefert `ok:true` mit der **bestehenden** Aufgabe und schreibt `task.generation_deduplicated` (`:615-632`). Stärker als der Legacy-Check-then-Insert und ausdrücklich beibehalten.
5. **Kein Automations-Editor in V1.** Regeln sind Backend-Konfiguration, nicht nutzerdefiniert (F9).
6. **Keine Automation ohne Audit.** Jede erzeugte Aufgabe und Mitteilung trägt `reason` mit der Regel-ID, damit „warum habe ich das bekommen" beantwortbar ist. Heute wird `reason` nirgends gesetzt (§12).

---

## 11. Screen states

Geteilte Zustände sind Foundation §11. Drei domänenspezifische Ergänzungen, die beide Screens gleich behandeln:

| Zustand | Auslöser | Darstellung |
|---|---|---|
| **AAL-Übergang** | aal1: Leseabfragen liefern 0 Zeilen, Mutationen `forbidden` „AAL2 is required for platform mutations" | eigener Zustand `NxEmptyState(Icons.shield_outlined, 'Zweiter Faktor erforderlich', …)`. **Nicht** als Leer-Zustand — sonst wirkt eine korrekt gesicherte Sitzung wie Datenverlust |
| **`infrastructureFailure` beim Lesen** | Der Adapter fängt alles in `catch (_)` und meldet `infrastructureFailure`, auch eine RLS-Ablehnung (`supabase_platform_repository_adapter.dart:277, :431`) | `NxEmptyState.error(...)` (Foundation-Fabrik auf main). Die UI darf **nicht** „Kein Zugriff" behaupten; sie weiß es nicht. Präzisere Klassifizierung ist Teil von A15 |
| **`versionConflict`** | zwei Bearbeiter | Foundation §10: Eingabe bleibt erhalten, Inline-Banner nennt die Serverversion, „Neu laden" / „Erneut speichern". Der Server liefert die vollständige `current_entity` mit (`:949-961`) — sie wird zum Nachziehen benutzt |

---

## 12. Forms and validation

Fehler-Mapping RPC → UI, einmal definiert, von beiden Screens benutzt:

| Server-Code | UI-Verhalten |
|---|---|
| `validation_failed` mit `fields` | Inline-Fehler am genannten Feld; Dialog bleibt offen |
| `version_conflict` | Konflikt-Banner (Foundation §10) |
| `mutation_conflict` | „Diese Aktion wurde bereits mit anderen Daten ausgeführt." — kein Retry mit derselben `mutationId` |
| `in_progress` | Button bleibt im Ladezustand, ein Retry nach kurzer Verzögerung |
| `not_found` | Detail wechselt in `notFound` (Foundation §8) |
| `forbidden` | SnackBar mit Servermeldung; bei „AAL2 is required…" stattdessen der AAL-Zustand aus §11 |
| `infrastructureFailure` | `NxEmptyState.error` bzw. SnackBar „Aktion konnte nicht ausgeführt werden." + Retry |

- **`mutationId` muss stabil pro Absicht sein, nicht pro Versuch.** Der einzige heutige Aufrufer erzeugt sie aus `DateTime.now().microsecondsSinceEpoch` (`operations_alerts_controller.dart:283-290`) — ein Retry nach Timeout legt damit eine zweite Aufgabe an. Verbindlich: einmal beim Öffnen des Dialogs erzeugen, über alle Wiederholungen desselben Absendens beibehalten. Der Fix zieht den bestehenden Aufrufer mit (A15).
- **`reason` wird gesetzt** (heute nie, obwohl bis 2000 Zeichen erlaubt): mindestens die auslösende Fläche („Operations-Alert", „Bulk-Zuweisung").

---

## 13. Shared components

**Wiederverwenden:** `NxPageHeader`, `NxBreadcrumbs`, `NxActionToolbar`, `NxCard`, `NxSectionHeader`, `NxDataTableShell`, `NxEmptyState` (inkl. `NxEmptyState.error`), `NxStatusBadge`, `NxKpiTile`/`NxKpiRow`, `ResponsiveConstraints`, `NxContentFrame` (`lib/ui/components/`) sowie `ListFilterTemplate` und `ListFilterBar` (`lib/ui/templates/list_filter_template.dart`). Dispositionsliste: Foundation §17.

**Wave-1-Bausteine — seit `791849f` auf main, keine Vorleistung mehr nötig:** `NxListSkeleton` (`rows`, `rowHeight`, Zeilen-Keys `nx-list-skeleton-row-<n>`), `NxLiveUpdatesNotice` (optionale `message`), `NxNotice` (`message`, `kind`, `title`, `icon`, `action`), `NxSplitView` (`list`, `detail`, `showDetail`, `onBackToList`, `backLabel` = „Zur Liste", Flex 3:2), `NxEmptyState.error(...)`, `AppLayout.splitViewMinWidth = AppBreakpoints.tabletMax + 1`.

**Kleine Erweiterungen im Feature-PR:** `task_badges.dart` (Status → Badge-Kind), `TaskCategory`-Enum, `notification_kind_labels.dart`.

**Neue geteilte Kandidaten:**

| Kandidat | Zweck | Paket |
|---|---|---|
| `NxTaskRow` | die eine Aufgabendarstellung (§5.1) | `SHARED-UI-TASKROW-01` |
| `EntityRefChip` | einheitliche Darstellung eines `PlatformEntityRef` inkl. Sprungziel | `SHARED-UI-ENTITYREF-01` |
| `TaskCreateDialog` | der eine Anlege-Dialog (§5.2) | Teil von A3, exportiert |

`EntityRefChip` braucht eine Namensauflösung `(type, id) → Anzeigename`. Die gibt es nicht; der Legacy löste sie mit bis zu vier Zusatzabfragen je Zeile (`tasks_repo.dart:608-742`). Serverseitig existiert die passende Projektion — `public.search_index` mit `unique (workspace_id, entity_type, entity_id)` und `title` —, wird aber für Tasks von keinem Producer befüllt. Das ist die wirtschaftlichste Lösung und Teil von **TASK-QUERY-01**. **Bis dahin zeigt der Chip das Typlabel („Objekt"), niemals eine Roh-UUID.**

---

## 14. Backend gaps

Fünf getrennt geführte Pakete. Jedes ist gegen Code/Migrationen belegt; keins wird in einem Screen-PR implementiert (Master Plan §8).

| Paket | Bedarf | Belegt durch | Blockiert |
|---|---|---|---|
| **TASK-QUERY-01** | `due_at`-Filter und -Sortierung, Mehrfachstatus (oder passende serverseitige Semantik), Priorität, `assigned_to is null`, Entity-Scope inkl. Objekt-Rollup (denormalisierte `property_id`), Titelsuche, Zähl-RPC, `search_index`-Befüllung für Tasks | `platform_repository.dart:120-136`, `supabase_platform_repository_adapter.dart:71-104`, `tasks_entity_idx` | B1–B5 |
| **TASK-ENTITY-REGISTRY-01** | Registry-Werte `document` und `valuation_case`; `task` als Link-Ziel für `link_document` | `20260723100000:73-83`, `platform_entity_type.dart:19-28`, Parity-Test `platform_entity_type_parity_test.dart` | B7, B8 |
| **TASK-SCHEDULER-01 (DEBT-009)** | Vorlagen-Aggregat (Read- **und** Write-Contract) + Vorlagen-Tab als UI-Fläche + manuelles Instanziieren + serverseitiger Scheduler für wiederkehrende Aufgaben, Fristereignisse und geplante Mitteilungen; **Voraussetzung: Übernahme der zehn geharvesteten Standardvorlagen aus §7.6, bevor der Legacy-Screen gelöscht wird** | kein Vorlagen-Aggregat, kein Template-Contract, kein `supabase/functions`, kein `pg_cron`, kein `pg_net`; `docs/architecture/phase_0/04_duplicate_and_debt_register.md:83` | B9, B10 |
| **PERMISSION-CATALOG-02** | Client-/Server-Vokabular zusammenführen (`rbac.dart` kennt `task.manage`/`notification.*` nicht, der Server kennt `task.create/assign/resolve` nicht) **und** Rollen jenseits `admin` seeden | `supabase/seed.sql:120-160`, `lib/core/security/rbac.dart:17-133` | B11 (mit), B17 |
| **NOTIFICATION-EMITTER-01** | serverseitiger Fan-Out in `create_task`/`transition_task_status` samt Empfängerableitung, AS-1-Filter und Dedupe-Fenster; Voraussetzung: Objektverantwortlichkeit als Datum für spätere Ereignisse | `create_notification` verlangt `notification.manage` beim Auslöser (`20260723130000:1326-1331`); keine Zuständigkeitsspalte in `properties`/`workspace_memberships` | B11 |

**Kleinere, ebenfalls belegte Gaps** (eigene Zeilen im Tracker, aber kein eigener Planungsaufwand):

| Paket | Bedarf | Blockiert |
|---|---|---|
| `TASK-ASSIGNEE-DIRECTORY-01` | für `task.manage`-Inhaber lesbares Mitgliederverzeichnis; heute nur `list_workspace_members` unter `security.manage`. Seit `ADMIN-AREA-01` A1 (`53c9eb9`, PR #44) wird `listMemberDirectory` produktiv genutzt — die Leseform steht also, nur die Berechtigungsstufe passt nicht für Aufgaben-Bearbeiter | B6 |
| `NOTIFICATION-READ-02` | Sammel-Lesen nach Filter | B14 |
| `NOTIFICATION-QUERY-01` | Feed-Filter nach `kind`, `entity`, Zeitraum | B15 |
| `NOTIFICATION-REALTIME-01` | empfängergenaues Wake | B16 |
| `NOTIFICATION-RETENTION-01` | `expires_at`, Dedupe-Fenster, Retention-Job (Governance, OD-1) | F11 |

**Nicht mehr als Gap geführt** (gegenüber der Vorfassung gestrichen, weil sie entweder FUTURE sind oder in A15 aufgehen): Checkliste/Kommentare (→ F2/F3), Preferences (→ F6/F7, `SETTINGS-01` existiert), Objektverantwortlichkeit (→ Bestandteil von `NOTIFICATION-EMITTER-01`), Adapter-Fehlerklassifizierung und Minimalrouten (→ A15).

---

## 15. Accessibility and usability

Foundation §16 gilt. Domänenspezifisch:

- Status und Priorität nie nur über Farbe; das Badge-Label trägt die Bedeutung.
- „Überfällig" ist Text, nicht nur rote Schrift.
- Die Ungelesen-Markierung ist zusätzlich zur Schriftstärke ein Punkt-Indikator mit `Semantics(label: 'Ungelesen')` — Schriftstärke allein (Legacy `FontWeight.w700` vs. `w500`, `notifications_screen.dart:84-89`) ist für Screenreader unsichtbar.
- Tastatur: `Enter` öffnet das Detail; destruktiv-nahe Aktionen brauchen einen bewussten Klick, keine Leertaste auf der markierten Zeile.

---

## 16. Analytics / audit / history

- Jede Task-Mutation erzeugt serverseitig eine Audit-Zeile (`task.create`, `task.update`, `task.status_changed`, `task.generation_deduplicated`) und ein Domain-Event. Die UI schreibt nichts.
- Der „Aktivität"-Abschnitt am Task-Detail liest den Audit-Trail und wird **ohne `audit.read` ausgeblendet** (nicht deaktiviert).
- `mark_notification_read` schreibt Audit, publiziert aber **kein** Domain-Event.
- Keine Klartext-Inhalte in Logs: `notifications.title`/`body` und Task-Titel können Mieter- und Objektdaten enthalten; pgTAP 027 pinnt diesen Vertraulichkeitsanspruch serverseitig.

---

## 17. Test plan (geteilte Anteile)

### Unit / application
- Ereignis-Router: für jedes V1-Ereignis der korrekte Empfängerkreis inkl. AS-1 und AS-5 — als reine Regelprüfung, solange der Emitter blockiert ist.
- `mutationId`-Stabilität: zwei Absendeversuche derselben Absicht tragen dieselbe Id, zwei Absichten nicht.
- Statusautomat-Spiegel: Client-`canTransitionTo` (`task_dto.dart:33-60`) und SQL-Matrix deckungsgleich, als Tabellentest, damit Drift bricht.
- Fehler-Mapping (§12) vollständig.
- Kategorie: unbekannter Serverwert wird angezeigt und überlebt einen Bearbeitungszyklus.
- **Regressionstest gegen Vortäuschung:** kein Filter, keine Sortierung und keine Zahl in der UI, die `TaskListQuery`/`NotificationFeedQuery` nicht serverseitig trägt.

### Widget / UI
- Beide Screens rendern alle Zustände aus Foundation §11 plus die drei aus §11, gebunden an `Key('task-*')` / `Key('notification-*')`, nie an deutsche Copy.

### Repository / integration
- Bestehende Abdeckung wird nicht dupliziert: `supabase_platform_repository_adapter_test.dart` (29), `supabase_domain_event_consumer_adapter_test.dart` (12), `supabase_outbox_adapter_test.dart` (4), `platform_entity_type_parity_test.dart` (3), `test/integration/supabase_platform_repository_integration_test.dart` (3 große Tests inkl. AGG-019-Konvergenz und empfängergebundenem Feed).
- **Neu:** ein Adaptertest je in A15 verdrahtetem Port (`NotificationPort`, `PlatformQueryInvalidationSource`) und ein Mapping-Test für `cloudReadPermissionForPage` (§8.2).

### Staging E2E
- **Nicht-Admin-Szenarien sind BLOCKED (B17)**: außer `admin` existieren keine geseedeten Rollenrechte. Bis `PERMISSION-CATALOG-02` sind nur Admin-Pfade fahrbar — dieselbe Fixture-Lücke, die laut Master Plan §12 schon die Schwester-Domänen betrifft.
- Fahrbar mit Admin: Anmeldung mit MFA → Aufgabe anlegen → mir zuweisen → Status öffnen/erledigen → Deep Link `/tasks/:id` → Inbox lesbar, Read-Semantik korrekt → Reconnect erzeugt einen Reload.

---

## 18. Acceptance criteria (geteilte)

1. Es existiert genau **eine** Task-UI; `property_tasks_screen.dart` und `tasks_screen.dart` haben keinen erreichbaren Einstieg mehr.
2. Kein Client führt zeit- oder intervallgesteuerte Erzeugungslogik aus; `test/app_runtime_guard_test.dart` bleibt grün, `StartupTaskService` bleibt auf der Verbotsliste.
3. Jede angezeigte Mitteilung hat ein aufrufbares Sprungziel oder einen sichtbar deaktivierten „Öffnen"-Knopf mit Begründung; **keine Zeile zeigt eine Roh-UUID oder einen ISO-8601-Zeitstempel.**
4. **Kein Filter, keine Sortierung und keine Zahl in der UI ohne serverseitige Deckung.** Wo der Contract nicht trägt, ist die Steuerung abwesend oder sichtbar als BLOCKED gekennzeichnet — nicht clientseitig nachgebaut.
5. Ein Nutzer ohne `task.manage` kann in der UI nichts anlegen oder ändern **und** ein direkter RPC-Versuch scheitert serverseitig mit `forbidden`.
6. Ein aal1-Nutzer sieht den AAL-Zustand, nicht einen Leer-Zustand.
7. Ein Wiederholversuch nach Timeout erzeugt keine zweite Aufgabe.
8. Ein Reconnect führt zu genau einem entprellten Reload je Fläche.
9. Für jedes Ereignis aus §6.3 gibt es genau eine Stelle, die den Empfängerkreis bestimmt — und in V1 ist diese Stelle serverseitig oder gar nicht.
10. Kein Screen liest `Rbac` für Cloud-Rechte; `PERMISSION-CATALOG-02` bleibt unangetastet.

---

## 19. Out of scope

- Implementierung. Dieses Paket ist Planung (Master Plan §2).
- Änderungen an `public.tasks`, `public.notifications`, deren RLS, den RPCs, dem Permission-Katalog oder dem Seiten-Permission-Mapping. Alles unter §14 ist eigenes Paket.
- Import- und Audit-Screen, obwohl sie denselben Adapter benutzen (`IMPORTS-01`, `AUDIT-01`, Wave 3).
- Dashboard-Kennzahlen zu Aufgaben (P2-D09).
- Maintenance-Ticket-Parity (`MAINTENANCE-PARITY-01`); dieses Paket liefert nur den geteilten Task-Baustein.
- URL-Sync insgesamt (`SHELL-ROUTING-01`); nur die drei Minimalrouten reiten auf A15.
- Löschen der Legacy-Dateien und Entfernen von `GlobalPage.taskTemplates` — eigenes Hygiene-Folgepaket nach nachgewiesenem Harvest (im Tracker als `UI-HYGIENE-02` geführt).
- Migration der Legacy-SQLite-Daten (`legacy_cutover`; der Dry-Run-Mapper existiert und ist mit 37 Tests abgedeckt).

---

## 20. Closed decisions

Alle sechs Entscheidungen sind am 2026-08-28 verbindlich geschlossen. Sie sind ab hier Vertrag, nicht Vorschlag.

| # | Entscheidung | Wirkung in dieser Spec |
|---|---|---|
| **OD-1 Retention** | **Keine clientseitige automatische Retention oder Löschung in V1.** Die UI zeigt, was der autoritative Server liefert. Eine echte Retention-Policy ist ein separates Backend-/Governance-Paket und blockiert Task Center und Inbox nicht. | §6.5 neu gefasst; das clientseitig gerechnete Relevanzfenster der Vorfassung ist **gestrichen**. `NOTIFICATION-RETENTION-01` als F11 geführt. |
| **OD-2 Implementation order** | **Backend-first für fehlende Kern-Query-Fähigkeiten.** Contract-getragene Task-/Inbox-Flächen dürfen parallel implementiert werden. **Keine UI darf Funktionalität vortäuschen, die der Query-Contract nicht korrekt liefern kann.** | Maßstab der Klassifizierung in §0.2; Akzeptanzkriterium 4; Regressionstest in §17. |
| **OD-3 Subtasks** | **Keine monday-Subtask-Hierarchie in V1.** Keine neue Hierarchie ohne Contract. Einfache Checkliste nur, wenn bereits ehrlich persistierbar — andernfalls FUTURE. | Checkliste ist **nicht** persistierbar (kein Aggregat, kein RPC) ⇒ **F2**. §9 #3 entsprechend. |
| **OD-T1 Due-Filter/Sortierung** | **Vollständiges Client-Laden mit Hard Cap ist kein freigegebener Produktionspfad.** „Heute / Diese Woche / Überfällig" brauchen ein Server-Query-Paket mit mindestens: `due_at`-Range/Filter, mehreren Statuswerten bzw. passender serverseitiger Semantik, `assigned_to`, Entity-Scope, definierter Sortierung nach Fälligkeit. My-Work-/Systemsichten bleiben bis dahin BLOCKED. | Der Lade-mit-Deckel-Vorschlag der Vorfassung ist **ersatzlos gestrichen**. B1–B5 gegen `TASK-QUERY-01`; dessen Umfang in §14 wörtlich übernommen. |
| **OD-T5 `estimated_cost`** | **Aus Task-V2-UI und -Modell entfernt.** Kein Feld simulieren. Wiederaufnahme nur mit explizitem Schema-/Contract-Paket. | §7.1; kein Feld, keine Kachel, keine Summe. F10. |
| **OD-N6 Event catalog** | **V1 enthält nur Eventtypen mit realem Emitter, eindeutigem Empfänger, Relevanzgrund und gültigem Deep Link.** Keine generische Notification-Erzeugung. Neue Typen nur durch explizite Contract-Erweiterung. | §6.3 auf vier Kandidaten reduziert — die alle an `NOTIFICATION-EMITTER-01` hängen, weil `create_notification` `notification.manage` beim Auslöser verlangt. Kein UI-Pfad erzeugt Mitteilungen. |

**Damit sind keine Planungsentscheidungen mehr offen.** Was bleibt, sind Backend-Pakete (§14), nicht Produktfragen.

---

## 21. Implementation handoff

### Erste Implementation-Wave

**Welle T-1 — Fundament (`TASKS-NOTIFICATIONS-CORE-01`, Inkrement A15).** Ein PR, klein und prüfbar:

1. `notificationPortProvider` und `platformQueryInvalidationSourceProvider` in `platform_providers.dart`; Bindung in `app_backend_wiring.dart` auf die **bereits existierende** `SupabasePlatformRepositoryAdapter`-Instanz (`:62`, `:117`). Kein neuer Adapter.
2. Routen `/tasks`, `/tasks/:taskId`, `/notifications` in `cloudRouteTargetFromName` plus die zugehörigen `CloudRouteSurface`-Werte.
3. Adapter-Fehlerklassifizierung: `forbidden` von `infrastructureFailure` auf dem Lesepfad trennen.
4. Stabile `mutationId`-Erzeugung inkl. Nachziehen des bestehenden Aufrufers (`operations_alerts_controller.dart:283-290`) und Setzen von `reason`.
5. Geteilte Bausteine: `task_badges.dart`, `TaskCategory`, Fehler-Mapping (§12), Mapping-Test für `cloudReadPermissionForPage`.
6. **`cloudReadinessForPage` bleibt zunächst auf `migrationRequired`** — der Flip auf `ready` gehört an das Ende von T-2/T-3, sonst wird eine leere Fläche erreichbar.

**Welle T-2 — Task Center (A1–A9)** und **Welle T-3 — Inbox (A11–A14)** dürfen nach T-1 parallel laufen (OD-2), in getrennten Branches/Worktrees (Master Plan §6).

**Parallel und unabhängig, Backend-first (OD-2):** `TASK-QUERY-01`, danach `NOTIFICATION-EMITTER-01`. Beide sind Voraussetzung dafür, dass die Flächen aus T-2/T-3 ihren eigentlichen Produktwert bekommen.

### Schlüsseldateien
`platform_providers.dart` · `app_backend_wiring.dart` · `app_navigation.dart` · `supabase_platform_repository_adapter.dart` (nur Fehlerklassifizierung) · `operations_alerts_controller.dart` (nur `mutationId`/`reason`).

### Bereits auf `main`
`UX-FOUNDATION-IMPL-01` (`791849f`) — `NxSplitView`, `NxListSkeleton`, `NxLiveUpdatesNotice`, `NxNotice`, `NxEmptyState.error`, `AppLayout.splitViewMinWidth`, Landing → `properties`. Keine Vorleistung mehr nötig.

### Harte Invarianten
- `test/app_runtime_guard_test.dart` — kein SQLite, kein `StartupTaskService` im Composition Root.
- pgTAP 013 (57), 026 (33), 027 (30) und die Policy-Inventur von exakt **41** Policies in `supabase/tests_mutation/security_aal_mutation_matrix.sql` (MUT-6b): **jede** neue Policy auf `public.tasks` oder `public.notifications` lässt sie fallen. Kein Screen-PR fasst Policies an.
- Actor-Guard im Adapter (`supabase_platform_repository_adapter.dart:723-728`): `context.actorId` muss der authentifizierte Nutzer sein.
- `PERMISSION-CATALOG-02` bleibt unberührt.

---

*Zitierweise: Screen-Specs verweisen als „Shared §n". Abweichungen von §0.2, §4, §6.2, §6.3, §10.3 oder §20 sind keine Screen-Entscheidung; sie brauchen eine Änderung dieses Dokuments.*
