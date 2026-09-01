# Task Center (TASKS-V2)

## Metadata

- Package / screen ID: `TASKS-NOTIFICATIONS-01` (Tracker Wave 2) / Unterpaket **`TASK-CENTER-01`** / Screen-ID `TASKS-V2`
- Domain: `platform_audit_jobs` (Aggregat `public.tasks`)
- Route: `GlobalPage.tasks`, Sidebar „Tagesgeschaeft → Aufgaben" (`app_navigation.dart:456-461`); neue Deep-Link-Routen `/tasks` und `/tasks/:taskId` (Inkrement A15 in `TASKS-NOTIFICATIONS-CORE-01`)
- Current implementation file(s) — alle Legacy, zur Laufzeit unerreichbar:
  - `lib/ui/screens/tasks/tasks_screen.dart` (1887) — fachliche Hauptquelle
  - `lib/ui/screens/tasks/task_templates_screen.dart` (1197) — wird Tab
  - `lib/ui/screens/property_detail/property_tasks_screen.dart` (1415) — wird ersetzt
  - `lib/data/repositories/tasks_repo.dart` (800), `lib/core/models/task.dart` (267), `lib/core/services/task_generation_service.dart` (304)
  - Zielvertrag: `lib/features/platform_audit_jobs/**`, `supabase/migrations/20260723130000_p2_d04_tasks_notifications.sql`
- Planning status: **APPROVED (2026-08-28; Entscheidungen in `tasks_notifications_shared.md` §20 geschlossen)** — Freigabe gilt **inkrementweise**, siehe §0. Die Systemsichten und die Termine-Ansicht sind ausdrücklich **BLOCKED**.
- Dependencies: **Shared §** (`tasks_notifications_shared.md`, normativ) · `UX-FOUNDATION-IMPL-01` (**auf main, `791849f`**) · Inkrement A15 aus `TASKS-NOTIFICATIONS-CORE-01`
- Related screens: `notification_inbox.md`, `admin_members.md`, Property-Workspace, Maintenance-Tickets, Operations-Alerts

**Basis der Analyse:** `origin/main` `bf0693c` (2026-08-28), neu gefetcht und verifiziert.

Abschnittsnummern folgen `SCREEN_SPEC_TEMPLATE.md`. „Shared §n" verweist auf `docs/product/screens/tasks_notifications_shared.md`.

---

## 0. Statusklassifizierung dieses Screens

Vollständige Matrix mit Blockern und Dependency-Matrix: Shared §0.2/§0.3.

**APPROVED (V1)** — A1 Grundfläche · A2 Liste mit contract-gedeckten Filtern · A3 Anlegen · A4 Bearbeiten · A5 Statuswechsel inkl. Archivieren · A6 „Mir zuweisen"/„Zuweisung entfernen" · A7 Kontextbindung auf die neun Registry-Werte · A8 Bulk auf A5/A6 · A9 Board als vier status-gebundene Keysets · A10 Vorlagen-Tab als ehrliche Leerfläche.

**BLOCKED** — B1 Systemsichten (Meine Aufgaben, Heute, Diese Woche, Überfällig, Nicht zugewiesen) · B2 Termine-Ansicht · B3 Fälligkeitssortierung, Prioritätsfilter, Mehrfachstatus, Titelsuche · B4 Objekt-Rollup · B5 serverseitige Zähler → **alle gegen `TASK-QUERY-01`**. B6 Zuweisung an andere → `TASK-ASSIGNEE-DIRECTORY-01`. B7/B8 Document- und Valuation-Case-Bezug → `TASK-ENTITY-REGISTRY-01`. B9 wiederkehrende Aufgaben und „Jetzt erzeugen" → `TASK-SCHEDULER-01 (DEBT-009)`. B17 Nicht-Admin-Staging-E2E → `PERMISSION-CATALOG-02`.

**FUTURE** — F1 Subtasks · F2 Checkliste · F3 Kommentare · F4 Anhänge · F5 Abhängigkeiten · F6 gespeicherte Nutzersichten · F8 Dashboards · F9 Automations-Editor · F10 `estimated_cost` · F12 Teams als Zuweisungsziel.

**Faustregel für die Implementierung (OD-2):** Was der Query-Contract nicht trägt, wird **nicht gebaut** — weder clientseitig nachgerechnet noch als „ungefähre" Zahl angezeigt. Eine fehlende Steuerung ist besser als eine falsche.

---

## 1. Purpose

Das Task Center ist die **eine** Fläche, auf der Arbeit in NexImmo entsteht, verteilt, verfolgt und abgeschlossen wird — workspaceweit und objektbezogen, mit demselben Modell und derselben Bedienung.

Es löst drei Probleme des Ist-Stands:

1. **Zwei Task-UIs über einer Tabelle.** `tasks_screen.dart` und `property_tasks_screen.dart` haben divergente Filter (`later`-Bucket fehlt global, `no_due_date`-Reihenfolge unterschiedlich), divergente Kategorie-Eingaben (Dropdown vs. Freitext), divergente Dezimalparser und divergente Datepicker-Grenzen. Screen Map zu *Property Tasks*: „REBUILD — Adapter existiert; gemeinsam mit Workspace-Tasks planen (eine Task-UI)" (`PRODUCT_SCREEN_MAP.md:72`).
2. **Kein Zugriff auf die Cloud.** Beide Screens lesen SQLite, das unter DEC-024 nicht mehr existiert; `cloudReadinessForPage` liefert für `tasks` `migrationRequired`. Der vollständige Serververtrag (Tabelle, RLS, fünf RPCs, Statusautomat, Idempotenz, Domain-Events) ist da und wird von nichts benutzt.
3. **Keine belastbare Priorisierung.** Der Legacy zählt „Überfällig / Heute / 7 Tage" clientseitig über alle geladenen Zeilen, mit zwei verschiedenen Stichtagsgrenzen für Filter und Kachel (`tasks_screen.dart:804-806` vs. `:1435`) — die Kachelzahl stimmt nicht mit der gefilterten Liste überein. **V1 löst dieses Problem nicht, sondern erkennt es an**: die Sichten bleiben BLOCKED, bis `TASK-QUERY-01` sie serverseitig korrekt beantworten kann.

---

## 2. Primary users and jobs

| Rolle | Erste Frage beim Öffnen | Wichtigste Aktion | V1 |
|---|---|---|---|
| Objektbetreuung / Hausmeister | „Was ist heute meins?" | Status weiterschalten | Frage **BLOCKED (B1)**, Aktion ✅ A5 |
| Asset Management | „Was ist überfällig oder blockiert — und bei wem?" | Priorisieren, neu zuweisen | Frage **BLOCKED (B1)**, Zuweisen **BLOCKED (B6)** |
| Vermietung | „Welche Fristen laufen an meinen Vorgängen?" | Termin setzen, abhaken | Kontextfilter ✅ A7, Fristensicht **BLOCKED** |
| Buchhaltung | „Was hängt an mir?" | Erledigen | ✅ über Zuständig-Filter (A2) |
| Bauleitung | „Was steht an meinen Projekten an?" | Zuweisen an Dienstleister | Kontext ✅ A7, Zuweisen **BLOCKED (B6)** |
| Admin | „Welche Vorlagen erzeugen was?" | Vorlage pflegen | **BLOCKED (B9)**, Tab als Leerfläche ✅ A10 |

**Standardzustand V1:** Die Seite öffnet auf **„Alle offenen Aufgaben"** — `status = open`, `includeArchived = false`, Sortierung `created_at DESC`. Das ist die einzige Voreinstellung, die der Contract vollständig deckt. Der Legacy öffnete auf `status = todo` über alle Nutzer; die eigentlich richtige Voreinstellung („meine, nach Fälligkeit") ist B1.

---

## 3. Entry points and navigation

1. Sidebar „Tagesgeschaeft → Aufgaben" — Standardeinstieg, workspaceweit.
2. Property-Workspace, Tab „Aufgaben" — dieselbe Fläche mit vorbelegtem Objektkontext (ersetzt `property_tasks_screen.dart`). **Wichtig:** der Kontextfilter greift auf `entity_type = 'property'` **dieses** Objekts; Aufgaben an dessen Einheiten, Verträgen oder Tickets erscheinen dort **nicht** (B4). Die Fläche sagt das offen: „Zeigt Aufgaben, die direkt an diesem Objekt hängen."
3. Deep Link `/tasks/:taskId` öffnet Liste + Detail (A13/A15).
4. Aus Domänenpanels: „Aufgabe erstellen" (Shared §5.2) — bleibt im Panel, öffnet nur den Dialog.
5. Aus `OperationsAlertsPanel` — heute der einzige produktive Task-Write (`operations_alerts_controller.dart:272-308`); bleibt erhalten und wird auf den geteilten Dialog umgestellt.

**Ausstiege:** Kontext-Chip → zugehörige Fläche über die vorhandenen `*RouteFor`-Builder. Vorlagen-Tab bleibt in der Seite.

**Kontexterhalt:** Filter- und Sichtzustand ist bildschirmlokal, überlebt einen Tabwechsel, wird beim Workspace-Wechsel zurückgesetzt (Foundation §7). URL-Persistenz erst mit `SHELL-ROUTING-01`. Kein eigener Navigator-Stack (Foundation §2); das Detail ist ein Split-Pane.

---

## 4. Information architecture

```
NxPageHeader   „Aufgaben"  ['Tagesgeschaeft','Aufgaben']
               [Sekundär: Aktualisieren] [Primär: Neue Aufgabe]
──────────────────────────────────────────────────────────
(optional) NxLiveUpdatesNotice                          ← Foundation §13
──────────────────────────────────────────────────────────
Tabs:  Aufgaben | Vorlagen                              ← Foundation §9
──────────────────────────────────────────────────────────
contextBar:  Kontext-Chip, wenn objektbezogen geöffnet
             (Systemsichten erscheinen erst mit TASK-QUERY-01)
──────────────────────────────────────────────────────────
ListFilterBar: Status · Zuständig · Kontext · Archivierte
               |  Ansicht: Liste / Board
──────────────────────────────────────────────────────────
┌──────────── Liste (flex 3) ───────┬──── Detail (flex 2) ────┐
│  NxTaskRow …                      │  Titel + Status-Badge    │
│  [Weitere laden]                  │  Kontext · Zuständig     │
│                                   │  Fälligkeit · Priorität  │
│                                   │  Beschreibung            │
│                                   │  Aktivität (audit.read)  │
└───────────────────────────────────┴──────────────────────────┘
```

Lesereihenfolge: **welcher Ausschnitt → was genau → welches Stück Arbeit.**

**Drei bewusste Streichungen gegenüber dem Legacy:**

- **Keine KPI-Zeile.** Jede clientseitig gerechnete Zahl über einem Keyset ist eine Untergrenze; eine Kachel „7 überfällig", die in Wahrheit „mindestens 7 unter den geladenen 50" heißt, ist genau die Vortäuschung, die OD-2 verbietet. Zähler kommen mit `TASK-QUERY-01` (B5).
- **Kein `Statusverteilung`-Balkendiagramm** (`tasks_screen.dart:1575-1642`) — Analytikfrage, gehört ins Dashboard-Paket (F8).
- **Keine `Kostenrahmen`-Kachel und kein Kostenfeld.** `estimated_cost` existiert im Cloud-Schema nicht und wird nach **OD-T5** aus Modell und UI entfernt statt simuliert (F10). Der Legacy-Wert (`double`, ohne Währung) wandert nicht mit; falls die Zahl fachlich gebraucht wird, gehört sie in CapEx/Budget und braucht ein eigenes Contract-Paket.

---

## 5. Layout and interaction model

| Viewport | Verhalten |
|---|---|
| **Desktop** (`width > AppLayout.splitViewMinWidth`, d. h. > 1199) | `NxSplitView` 3:2. Inhalt gedeckelt auf `AppLayout.desktopMaxContentWidth = 1440`, `context.adaptivePagePadding` |
| **Tablet** (768–1199) | `NxSplitView` narrow: Detail **ersetzt** die Liste, Rücksprung „Zur Liste" (Foundation §8) |
| **Mobil** (≤ 767) | `mobileChild` des `NxDataTableShell`: `ListTile`-Liste mit `chevron_right` (Foundation §6, Pflicht). Board-Ansicht ist auf Mobil **nicht** verfügbar — horizontale Spalten sind auf 390 px unbenutzbar; der Umschalter blendet sie aus, statt sie kaputt anzuzeigen |
| **320-px-Boden** | kein Overflow; Titel `maxLines: 2` mit Ellipse, Chips umbrechen |

Golden Viewports (Foundation §15): **390×844, 1024×768, 1440×900**, hell und dunkel.

**Auswahl:** Einfachauswahl per Zeilenklick (öffnet Detail). Mehrfachauswahl über eine Checkbox-Spalte, die erst nach Aktivierung von „Auswählen" erscheint — Bulk ist der Ausnahmefall und soll nicht permanent Platz kosten.

**Paginierung:** Keyset „Weitere laden", Seitengröße 50 (Foundation §6). Kein Infinite Scroll. Der Adapter fordert bereits `limit + 1` an und liefert `nextCursor` (`supabase_platform_repository_adapter.dart:259, :880-900`).

**Liste (Standardansicht, A2):** eine Abfrage, feste Sortierung `created_at DESC, id DESC`. Die Sortierung wird **nicht** als Steuerung angeboten, weil es nur einen Wert gibt; sie steht als Text in der Kopfzeile der Liste („Neueste zuerst"), damit niemand eine Fälligkeitssortierung vermutet.

**Board (A9):** vier Spalten `Offen` · `In Arbeit` · `Blockiert` · `Erledigt`, jede gespeist von einer **eigenen** `status.eq`-Abfrage mit eigenem Keyset und eigenem „Weitere laden". Archiviert erscheint nicht. Die Spaltenüberschrift zeigt die **geladene** Anzahl mit „+", solange eine weitere Seite existiert — nie eine erfundene Gesamtzahl.

**Kein Drag & Drop.** Jede Verschiebung wäre ein `transition_task_status`-RPC mit `expectedVersion`; ein fehlgeschlagener Drop müsste die Karte zurückspringen lassen, und STM-012 verbietet `open → done` — ein Drag über zwei Spalten wäre je nach Ziel gültig oder nicht. Ein expliziter „Status weiter"-Knopf auf der Karte (Legacy-Muster, `tasks_screen.dart:437-446`) ist ehrlicher und testbar.

**Termine-Ansicht: BLOCKED (B2).** Der Umschalter zeigt den Eintrag **nicht** an, solange `TASK-QUERY-01` fehlt. Ein deaktivierter Eintrag würde eine Funktion versprechen, die es nicht gibt.

---

## 6. Functional requirements

Je Aktion: Auslöser · Voraussetzung · Validierung · Erfolg · Fehler · Recht · Folgezustand. Fehler-Mapping durchgängig nach Shared §12.

### 6.1 Aufgabe anlegen — **APPROVED (A3)**
- **Auslöser:** Primäraktion „Neue Aufgabe" oder „Aufgabe erstellen" aus einem Panel.
- **Voraussetzung:** aktiver Workspace, `task.manage`, AAL2.
- **Erfolg:** `create_task` liefert die neue `TaskDto`; Liste lädt nach, Detail öffnet sie; SnackBar „Aufgabe angelegt."
- **Fehler:** `validation_failed` → inline; `forbidden` → SnackBar bzw. AAL-Zustand.
- **Keine Mitteilung.** Die Zuweisungs-Mitteilung (E-T1) ist **BLOCKED (B11)**; die UI löst keine aus und täuscht auch keine vor.

### 6.2 Aufgabe bearbeiten — **APPROVED (A4)**
- Felder: Titel, Beschreibung, Kategorie, Priorität, Fälligkeit. **Status ist nicht dabei** — `update_task` weist ihn ab (`20260723130000:684-707`). Zuständig: siehe §6.4.
- Braucht `task.manage` **und** `task.read` sowie `expectedVersion` aus dem geladenen DTO.
- `TaskFieldEdit` unterscheidet *nicht gesetzt* von *leeren*: „Termin entfernen" sendet `clear()`, ein unberührtes Feld sendet nichts (`task_dto.dart:186-197`).
- **Archivierte Aufgaben sind nicht editierbar** (Server: `validation_failed` „An archived task cannot be edited"). Die UI deaktiviert „Bearbeiten" bei `archived`, statt den Fehler zu provozieren.

### 6.3 Statuswechsel — **APPROVED (A5)**

| Aktueller Status | Angebotene Aktionen |
|---|---|
| `open` | „Starten" (→ `in_progress`) · „Blockiert" · „Archivieren" |
| `in_progress` | „Erledigt" · „Blockiert" · „Zurück auf Offen" · „Archivieren" |
| `blocked` | „Fortsetzen" (→ `in_progress`) · „Erledigt" · „Zurück auf Offen" · „Archivieren" |
| `done` | „Wieder öffnen" (→ `open`, auditiert) · „Archivieren" |
| `archived` | keine (terminal) |

- **„Erledigt" erscheint bei `open` nicht** — im Cloud-Modell wäre es ein Serverfehler (Shared §7.1).
- Jeder Wechsel braucht `expectedVersion`; bei `version_conflict` liefert der Server die vollständige `current_entity` mit, die UI zieht nach und zeigt den Konflikt-Banner.
- **„Blockiert" verlangt einen Grund** (Freitext im Bestätigungsdialog, geht als `reason` in den RPC). Ohne Grund ist ein Blocker für andere wertlos, und `reason` ist bis 2000 Zeichen vorgesehen.

### 6.4 Zuweisen — **teilweise APPROVED**

| Teilfunktion | Status |
|---|---|
| „Mir zuweisen" | **APPROVED (A6)** — die eigene `auth.uid()` ist bekannt, es braucht keine Auswahlliste |
| „Zuweisung entfernen" | **APPROVED (A6)** — `TaskFieldEdit.clear()` |
| Zuweisung an eine andere Person | **BLOCKED (B6)** |

Grund für B6: Das einzige Mitgliederverzeichnis ist `listMemberDirectory` → RPC `list_workspace_members`, serverseitig auf **`security.manage`** gegated (`20260722210000_p2_d01_member_directory.sql:37`); `listMembers` liefert Nicht-Admins höchstens die eigene Zeile. Ein `task.manage`-Inhaber ohne Adminrecht hat also keine lesbare Auswahlquelle. Serverseitig wäre `assigned_to` schreibbar — die UI hat nur nichts anzubieten.

**V1-Verhalten:** Im Dialog steht das Feld „Zuständig" mit den beiden erlaubten Aktionen („Mir zuweisen", „Zuweisung entfernen") und dem Hinweis „Zuweisung an andere Personen ist noch nicht verfügbar." Es gibt **kein** Freitextfeld und **keinen** halb funktionierenden Picker, der nur Admins Ergebnisse liefert.

### 6.5 Archivieren (statt Löschen) — **APPROVED (A5)**
- Es gibt **keinen Löschpfad**: keine DELETE-Policy, kein DELETE-Grant, kein RPC. `archived` ist terminal.
- Bestätigung nach Foundation §14: Titel „Aufgabe archivieren", Text nennt den Titel der Aufgabe und „Archivierte Aufgaben können nicht wieder geöffnet werden.", Bestätigung `FilledButton` in Fehlerfarbe „Archivieren".
- **Zusatz, der im Dialog stehen muss:** Trägt die Aufgabe einen `generated_key`, blockiert sie dauerhaft die Neuerzeugung unter demselben Schlüssel (AGG-019 konvergiert auch auf archivierte Zeilen). Text dann: „Diese Aufgabe stammt aus einer Vorlage. Nach dem Archivieren wird sie für diesen Zeitraum nicht erneut erzeugt."
- Der Legacy löschte hart und **ohne jede Rückfrage** (`tasks_screen.dart:600-603`, `property_tasks_screen.dart:945-948`) — der einzige Legacy-Bestandteil, der ersatzlos verschwindet.

### 6.6 Kontext setzen und lösen — **APPROVED (A7), mit zwei Lücken**
- Kontext = genau ein `PlatformEntityRef` (Shared §7.3).
- Picker in zwei Schritten: Typ → Entität. Verfügbar: Objekt, Einheit, Vertrag, Partei, Ticket, CapEx-Projekt, Portfolio, Szenario, Workspace.
- Objektbezogen geöffnet: Kontext vorbelegt und schreibgeschützt.
- **`document` und `valuation_case` erscheinen im Picker gar nicht** (B7/B8) — nicht als deaktivierte Optionen, das würde wie ein Rechteproblem wirken. Der Hilfetext des Pickers nennt die Lücke und das Paket.
- Solange die Namensauflösung fehlt (Teil von `TASK-QUERY-01`), zeigt `EntityRefChip` das **Typlabel** („Objekt"), niemals eine Roh-UUID.

### 6.7 Suchen, filtern, sortieren
Siehe §11. Grundsatz: **Was der Server nicht filtert, wird nicht angeboten.**

### 6.8 Systemsichten — **BLOCKED (B1)**
Geplant sind „Meine Aufgaben", „Überfällig", „Diese Woche", „Nicht zugewiesen", „Alle". Vier davon brauchen `due_at`-Filter/-Sortierung, Mehrfachstatus oder `assigned_to is null` — alles nicht im Contract.

**V1-Verhalten:** Der `contextBar` mit den Sicht-Chips **existiert nicht**. Es gibt keinen Platzhalter, keinen deaktivierten Chip und keine „kommt bald"-Kachel. Erst wenn `TASK-QUERY-01` gelandet ist, wird der `contextBar` in einem eigenen PR ergänzt.

Der Umfang von `TASK-QUERY-01` ist damit fachlich exakt definiert (aus OD-T1 wörtlich): `due_at`-Range/Filter, mehrere Statuswerte bzw. passende serverseitige Semantik, `assigned_to`, Entity-Scope, definierte Sortierung nach Fälligkeit.

### 6.9 Bulk-Aktionen — **APPROVED (A8), eng begrenzt**
- Verfügbar: `Status weiterschalten`, `Mir zuweisen`, `Zuweisung entfernen`, `Archivieren`. **Nicht** „an Person X zuweisen" (B6), **nicht** „Fälligkeit setzen" (das ist ein Feld-Update und wäre erlaubt — es bleibt trotzdem draußen, weil ein Massentermin ohne Fälligkeitssicht (B1) blind gesetzt würde).
- **Maximal 50 markierte Zeilen.** Es gibt keine Batch-RPC; jede Zeile ist ein eigener Aufruf mit eigener `mutationId` und eigenem `expectedVersion`.
- Fortschrittsdialog mit Abbruch, danach ein **Teilerfolgsbericht**: „38 von 42 aktualisiert. 4 übersprungen (2 Versionskonflikte, 2 unzulässige Statuswechsel)." — mit Filter „Nur fehlgeschlagene anzeigen".
- Ohne `task.manage` **ausgeblendet** (Foundation §3).
- Der Legacy hatte keine Bulk-Aktionen; dies ist die einzige Neuerung ohne Legacy-Beleg. Begründung: „12 Aufgaben eines abgeschlossenen Sanierungsprojekts archivieren" ist ein realer Vorgang, der sonst 12 Dialoge kostet.

### 6.10 Vorlagen-Tab — **APPROVED als Leerfläche (A10), Inhalt BLOCKED (B9)**
- **Lesen** mit `task.read`; **alle Mutationen** bräuchten `task.manage` — es gibt in V1 keine.
- Serverseitig existiert **kein Vorlagen-Aggregat**, kein Rhythmus-Feld, kein Scheduler. Der Tab zeigt deshalb `NxEmptyState` mit ehrlicher Begründung: „Wiederkehrende Aufgaben werden serverseitig erzeugt. Der dafür nötige Server-Job (DEBT-009) fehlt noch."
- Alternative „Tab weglassen" wurde verworfen: Der Tracker führt „Templates als Tab" als Paketinhalt, und die Fläche müsste sonst beim Nachziehen erneut in die Navigation eingebaut werden.
- **„Jetzt erzeugen" wird niemals als Client-Schleife gebaut.** Der Legacy-Pfad (`task_templates_screen.dart:734-756` → `task_generation_service.dart:32-134`) ist O(N·(4+M)) sequenzielle Roundtrips ohne Transaktion. Zielbild: ein Serverkommando (Shared §10.3 Regel 3).
- **Vor dem Löschen des Legacy-Screens** werden die zehn Standardvorlagen samt Checklisten als Fixture extrahiert (Shared §7.6) — Aufgabe von `TASK-SCHEDULER-01`.

### 6.11 Checkliste, Kommentare, Dokumentverweise — **FUTURE / BLOCKED**

| Funktion | Status | Grund |
|---|---|---|
| Checkliste | **F2** | kein Sub-Aggregat, kein RPC — nach **OD-3** nicht ehrlich persistierbar, also FUTURE. Parity-Verlust gegenüber `task_checklist_items` ist bewusst und protokolliert |
| Kommentare / Mentions | **F3** | kein Aggregat, keine Mention-Semantik |
| Dokumentverweis | **B7** | Registry kennt weder `document` noch `task` |

Sie werden im Detail **nicht angedeutet** — leere Platzhalter für nicht existierende Funktionen sind schlechter als ihre Abwesenheit.

### 6.12 Export — **FUTURE**
Der Legacy hatte keinen; ein CSV-Export über einen teilgeladenen Keyset wäre eine Halbwahrheit. Sinnvoll erst mit serverseitiger Aggregation.

---

## 7. Data requirements

Vollständiges Schema in Shared §7.1.

| Angezeigt | Quelle | Pflicht | Editierbar | Formatierung |
|---|---|---|---|---|
| Titel | `tasks.title` | ja | ja | 1 Zeile Liste / 2 Zeilen Detail, Ellipse |
| Status | `tasks.status` | ja | nur via `transition_task_status` | `NxStatusBadge`, Mapping `task_badges.dart` |
| Priorität | `tasks.priority` | ja | ja | Chip nur bei `high` |
| Zuständig | `tasks.assigned_to` (uuid) | nein | eingeschränkt (§6.4) | eigener Name auflösbar; fremde uuid ⇒ „Zugewiesen" ohne Namen, **nie die Roh-uuid** |
| Fälligkeit | `tasks.due_at` (timestamptz) | nein | ja | Datum in Workspace-Zeitzone; relativ bei ≤ 7 Tagen |
| Kategorie | `tasks.category` (Freitext) | nein | ja | typisiert im Client (Shared §7.5), unbekannte Werte werden angezeigt und erhalten |
| Kontext | `entity_type` + `entity_id` | nein | ja | `EntityRefChip`; ohne Namensauflösung Typlabel |
| Beschreibung | `tasks.description` | nein | ja | Klartext, ≤ 10 000, kein Rich Text |
| Aus Vorlage erzeugt | `generated_key ≠ null` | – | **nie** (protected column) | dezenter Hinweis |
| Version | `tasks.version` | – | – | nicht angezeigt, jedem Schreibvorgang beigelegt |
| Erstellt/Geändert | `created_by/at`, `updated_by/at` | – | – | im Detail unten; Namen nur, soweit auflösbar |
| Archiviert am | `archived_at` | – | – | nur bei `archived` |

**Nicht im Modell:** `estimated_cost` (OD-T5, F10), Checkliste (F2), Kommentare (F3), Anhänge (F4), Mehrfachbezug (Shared §7.3).

**Namensauflösung** (`assigned_to` → Person, `entity_id` → Objektname) darf **nicht** N+1 werden wie im Legacy (`tasks_repo.dart:65-84`, 2–5 Zusatzabfragen je Zeile). In V1 wird sie gar nicht versucht — außer für die eigene Person. Zielbild ist `public.search_index` als Auflösungstabelle (`unique (workspace_id, entity_type, entity_id)` → `title`), heute für Tasks von keinem Producer befüllt. Teil von `TASK-QUERY-01`.

---

## 8. Permissions and security behavior

Vollständig in Shared §8.

| Ebene | Regel |
|---|---|
| Seite sichtbar | `task.read`; Sidebar blendet ohne Recht aus, Deep Link zeigt `Key('cloud-destination-forbidden')` mit „(task.read)" |
| Liste lesen | RLS `tasks_select_task_read` |
| „Neue Aufgabe" | `task.manage` — deaktiviert mit Tooltip „Benötigt task.manage" |
| Bearbeiten / Status / Zuweisen | `task.manage` + `task.read` — deaktiviert |
| Bulk | `task.manage` — ausgeblendet |
| Vorlagen-Tab | `task.read` (V1 schreibt nichts) |
| Aktivitäts-Abschnitt | `audit.read` — **ausgeblendet** ohne Recht |
| Alles | **AAL2** (DEC-025); aal1 ⇒ 0 Zeilen beim Lesen, `forbidden` beim Schreiben ⇒ eigener Zustand (§10) |

Client-Gating liest ausschließlich das Server-Permission-Set, **niemals** `lib/core/security/rbac.dart`. **`PERMISSION-CATALOG-02` wird nicht still hier gelöst** — kein Katalogeintrag, kein Seed, kein Mapping wird in diesem Paket angefasst.

Eingefrorene Mapping-Grobheit: `taskTemplates` teilt sich `task.read` mit `tasks` (`app_navigation.dart:281`). Da der Vorlagen-Screen zum Tab wird, verschwindet das Problem faktisch. `test/ui/navigation/app_navigation_test.dart` sichert die konkreten Schlüssel **nicht** ab (Shared §8.2); ein ergänzender Mapping-Test gehört in A15.

---

## 9. Realtime / freshness behavior

- **Abonniert:** `PlatformQueryInvalidationSource.watchWorkspace`, Aggregat `PlatformAggregate.task`. Topic `workspace:<id>:task.read` — Permission-Konstante `platformTaskEventPermission` (`supabase_domain_event_consumer_adapter.dart:13`), Topic-String gebaut in `:48-50`.
- **Live aktualisiert wird nichts direkt.** Realtime ist invalidierungsbasiert, REST bleibt kanonisch (Foundation §13). Ein Ereignis stößt einen entprellten Reload der aktuellen Filtermenge an.
- **Ereignisse:** `task.created`, `task.updated`, `task.status_changed` (`20260723130000:660, :992, :1210`).
- **Nach Reconnect:** ein Reconcile je wiederverbundenem Topic (`:203-217`); die drei Plattform-Topics laufen in einem Stream zusammen (`:170-174`), ein vollständiger Reconnect liefert also bis zu drei Signale, die der Screen zu **einem** Reload entprellt.
- **`liveUpdatesDegraded`:** `NxLiveUpdatesNotice` unter dem Header, passiv, selbstlöschend. Der Controller führt das Flag wie `ReferenceSliceState.liveUpdatesDegraded`.
- **Ein offenes Bearbeitungsformular wird nie live überschrieben.** Eine Invalidierung aktualisiert die Liste, nicht das Formular; ein Konflikt zeigt sich beim Speichern über `version_conflict` mit erhaltenem Input.
- **Im Board** invalidiert ein Ereignis alle vier Spalten-Keysets; jede Spalte lädt ihre erste Seite neu.

---

## 10. Screen states

| Zustand | Rendering | Key |
|---|---|---|
| idle (kein Workspace) | `NxEmptyState(Icons.workspaces_outline, 'Kein Arbeitsbereich aktiv')` | `task-center-idle` |
| loading | `NxListSkeleton` (kein Spinner) | `task-center-loading` |
| background refresh | Inhalt bleibt sichtbar, dezenter Fortschritt im Header | `task-center-refreshing` |
| empty | „Noch keine Aufgaben. Lege die erste an." + CTA, gated auf `task.manage` | `task-center-empty` |
| no-match (Filter aktiv) | `Icons.filter_alt_off_outlined`, „Keine Treffer für diesen Filter.", Aktion „Filter zurücksetzen" | `task-center-no-match` |
| populated | Liste bzw. Board | `task-center-ready` |
| partial | geladene Seiten + „Weitere laden"; **keine Gesamtzahlen** | `task-center-partial` |
| forbidden | `NxEmptyState(Icons.lock_outline, 'Kein Zugriff auf Aufgaben', '… benötigt die Berechtigung (task.read).')` | `task-center-forbidden` |
| **AAL2 erforderlich** | `NxEmptyState(Icons.shield_outlined, 'Zweiter Faktor erforderlich', 'Aufgaben sind erst nach der Zwei-Faktor-Anmeldung sichtbar.')` — **nicht** als Leer- oder Fehlerzustand | `task-center-aal-required` |
| recoverable error | `NxEmptyState.error(description: …, onRetry: …)` (Foundation-Fabrik auf main) | `task-center-error` |
| Detail: notFound | „Diese Aufgabe wurde entfernt oder zusammengeführt, während die Liste geöffnet war." | `task-detail-not-found` |
| Detail: idle | „Wähle eine Aufgabe." | `task-detail-idle` |
| realtime degraded | `NxLiveUpdatesNotice` | `task-center-live-degraded` |
| action in progress | Button im Ladezustand, Zeile dezent gedimmt | – |
| action success / failure | SnackBar über `ref.listen` + `clearAction()` (Foundation §12) | – |
| version conflict | Inline-Banner, Eingabe bleibt erhalten (Foundation §10) | `task-detail-conflict` |

Der **partial**-Zustand ist gegenüber dem Legacy neu und notwendig: bei Keyset-Paginierung ist jede clientseitig gerechnete Zahl eine Untergrenze. Der Legacy zeigte sie als Wahrheit an. V1 zeigt sie gar nicht.

---

## 11. Search / filter / sort

### V1 — serverseitig gedeckt (A2)

| Steuerung | Umsetzung |
|---|---|
| Status | `TaskListQuery.status` — **ein** Wert: „Offen / In Arbeit / Blockiert / Erledigt / Alle" (wobei „Alle" = kein Filter) |
| Archivierte einbeziehen | `includeArchived` (Schalter, Standard aus) |
| Zuständig | `assignedTo` — in V1 mit den Werten „Alle" und „Mir zugewiesen"; eine Personenauswahl braucht B6 |
| Kontext | `entity` — nur wirksam, wenn **Typ und ID** gesetzt sind (der Adapter filtert sonst gar nicht, `:89-91`). Ein reiner Typfilter ist deshalb nicht möglich und wird nicht angeboten |
| Sortierung | fest `created_at DESC` — keine Steuerung, stattdessen der Hinweis „Neueste zuerst" |

### V1 — bewusst NICHT vorhanden (alle **BLOCKED**, `TASK-QUERY-01`)

Prioritätsfilter · Fälligkeitsbereich · Mehrfachstatus · „Nicht zugewiesen" · Sortierung nach Fälligkeit · Objekt-Rollup · **Volltextsuche**.

**Zur Suche im Besonderen:** Eine clientseitige Suche über die geladenen Seiten wäre technisch trivial und wird trotzdem **nicht** gebaut. Ein Suchfeld erzeugt beim Nutzer die Erwartung, alles zu durchsuchen; „In geladenen Aufgaben suchen" als Platzhaltertext ändert daran nichts, sobald die Liste mehr als eine Seite hat. Das fällt unter OD-2 („keine Funktionalität vortäuschen") und wandert vollständig in `TASK-QUERY-01`.

### Persistenz
Filterzustand lebt im Screen-State, überlebt Tabwechsel, wird beim Workspace-Wechsel geleert. Keine URL-Persistenz bis `SHELL-ROUTING-01`. Nutzerdefinierte gespeicherte Sichten sind F6.

---

## 12. Forms and validation

### Dialog „Neue Aufgabe" / „Aufgabe bearbeiten" (der eine Dialog, Shared §5.2)

| Feld | Pflicht | Standard | Steuerung | Validierung |
|---|---|---|---|---|
| Titel | ja | – | `TextField` | „Pflichtfeld"; getrimmt 1–300 |
| Beschreibung | nein | – | `TextField`, 3–6 Zeilen | ≤ 10 000 |
| Kategorie | nein | `general` | `DropdownButtonFormField<TaskCategory?>` | Vokabular Shared §7.5; unbekannter Serverwert wird angezeigt und erhalten |
| Priorität | ja | `normal` | Dropdown | `low`/`normal`/`high` |
| Zuständig | nein | leer | zwei Aktionen: „Mir zuweisen" / „Zuweisung entfernen" + Hinweistext (§6.4) | – |
| Fälligkeit | nein | leer | Datumsfeld + `showDatePicker` **mit Löschen-Knopf** | Datum; keine Vergangenheitssperre (Nacherfassung ist real) |
| Kontext | nein | vorbelegt bei Panel-Aufruf | Typ-Picker → Entitäts-Picker | beide oder keins |
| Grund (nur bei „Blockiert") | ja | – | `TextField` | 1–2000 |

**Regeln**
- Einheitlicher Datepicker-Bereich; die Legacy-Divergenz (2000–2100 global vs. 2020–2100 objektbezogen) entfällt.
- **Keine Zahleneingaben** — kein `estimated_cost` (OD-T5). Damit entfällt auch der Legacy-Bug, dass nur einer der beiden Dialoge Komma-Dezimaltrennung normalisierte.
- Buttons: `TextButton('Abbrechen')` + `FilledButton('Anlegen'/'Speichern')`; Submit zeigt Fortschritt und ist währenddessen deaktiviert (Foundation §10).
- Dirty-Close ⇒ „Änderungen verwerfen?"
- **`mutationId` wird beim Öffnen des Dialogs erzeugt** und über alle Wiederholungen desselben Absendens beibehalten (Shared §12). Nur „Abbrechen + neu öffnen" erzeugt eine neue.
- **`reason`** wird gesetzt: manuelle Anlage „Manuell angelegt (Task Center)", aus einem Panel der Panelname, bei Bulk „Massenaktion: <Aktion>".
- Serverfehler-Mapping nach Shared §12; `validation_failed` mit `fields` markiert das genannte Feld inline.

---

## 13. Shared components

**Wiederverwenden:** `NxPageHeader`, `NxBreadcrumbs`, `NxActionToolbar`, `NxCard`, `NxSectionHeader`, `NxDataTableShell`, `NxEmptyState` (inkl. `NxEmptyState.error`), `NxStatusBadge`, `ResponsiveConstraints`, `NxContentFrame`; `ListFilterTemplate` und `ListFilterBar` aus `lib/ui/templates/list_filter_template.dart`.

**Seit `791849f` auf main, keine Vorleistung nötig:** `NxSplitView` (Flex 3:2, `backLabel` „Zur Liste"), `NxListSkeleton`, `NxLiveUpdatesNotice`, `NxNotice`, `NxEmptyState.error`, `AppLayout.splitViewMinWidth`.

**Nicht verwendet:** `NxKpiTile`/`NxKpiRow` — es gibt in V1 keine belastbaren Kennzahlen (§4).

**Kleine Erweiterungen im Feature-PR:** `task_badges.dart`, `TaskCategory`-Enum, Prioritäts-Labels.

**Neue geteilte Kandidaten:** `NxTaskRow` (`SHARED-UI-TASKROW-01`), `EntityRefChip` (`SHARED-UI-ENTITYREF-01`), `TaskCreateDialog` (in diesem Paket, exportiert).

**Nicht neu bauen:** kein eigenes Skelett-Widget (der Legacy-Baum hat sechs Kopien), kein privates KPI-Widget, kein eigenes Toast-System, kein `'__all__'`-Sentinel (typisierte nullable Dropdowns, Foundation §7).

---

## 14. Backend gaps

Vollständig mit Belegen in Shared §14. Für diesen Screen:

| Paket | Wirkung hier | Ohne das Paket |
|---|---|---|
| **TASK-QUERY-01** | **schwerwiegend** | keine Systemsichten, keine Termine-Ansicht, keine Suche, keine Zähler, kein Objekt-Rollup, keine Namensauflösung |
| **TASK-ASSIGNEE-DIRECTORY-01** | Arbeit lässt sich nicht verteilen | nur „mir zuweisen" |
| **TASK-ENTITY-REGISTRY-01** | Kontextauswahl unvollständig | kein Dokument-, kein Bewertungsbezug |
| **TASK-SCHEDULER-01 (DEBT-009)** | Vorlagen-Tab bleibt leer | keine wiederkehrenden Aufgaben |
| **PERMISSION-CATALOG-02** | Test- und Staging-Nachweis | Negativtests „ohne `task.manage`" nicht fahrbar |
| A15 (Core) | Routen, Provider, Fehlerklassifizierung | kein Deep Link, keine stabile `mutationId` |

Kein Gap wird in diesem Screen-PR implementiert (Master Plan §8).

---

## 15. Accessibility and usability

- Tastatur: `Tab` durch Filterleiste → Liste → Detail; `Enter` auf einer Zeile öffnet das Detail; Dialoge fangen den Fokus, `Escape` bricht ab, Fokus landet auf dem ersten Feld.
- Alle Icon-Buttons mit `tooltip`; Statusaktionen sind Text, nicht nur Icon.
- Farbe ist nie das einzige Signal: „Überfällig" steht als Wort, `high` als Chip mit Text.
- Touchziele ≥ 44 px auf Mobil; Tabellenzeilen nicht unter `dataRowMin`.
- Kontraste ausschließlich über Tokens (`app_theme.dart`), kein Roh-Hex.
- Semantik: Zeilen exponieren Titel, Status und Fälligkeit als Text; die Bulk-Checkbox trägt „Aufgabe auswählen: <Titel>".
- Destruktives nennt Objekt und Konsequenz (§6.5).

---

## 16. Analytics / audit / history

- Kein UI-seitiges Audit-Schreiben. Der Server schreibt `task.create`, `task.update`, `task.status_changed`, `task.generation_deduplicated`.
- Abschnitt „Aktivität" im Detail liest den Audit-Trail, gated auf `audit.read`, ohne das Recht ausgeblendet.
- Keine Aufgabeninhalte in Client-Logs (Titel und Beschreibung können Mieter- und Objektdaten enthalten).
- Produktkennzahlen zu Aufgaben sind nicht Teil dieses Screens (F8, P2-D09).

---

## 17. Test plan

### Unit / application
- Statusaktions-Matrix je Ausgangsstatus (§6.3) als Tabellentest gegen `TaskStatus.canTransitionTo`, deckungsgleich mit der SQL-Matrix.
- **Vortäuschungs-Regression:** Ein Test iteriert die angebotenen Filter-, Sortier- und Zählelemente und schlägt fehl, sobald eines davon nicht auf ein Feld von `TaskListQuery` abbildbar ist. Das ist die maschinelle Fassung von OD-2.
- `mutationId`-Stabilität über Retries; neue Id nach Dialog-Neuöffnung.
- Fehler-Mapping (Shared §12) vollständig.
- Bulk: Teilerfolgsbericht zählt Erfolge, Konflikte und unzulässige Übergänge korrekt.
- Kategorie: unbekannter Serverwert überlebt einen Bearbeitungszyklus unverändert.
- Board: vier unabhängige Keysets; ein Ereignis invalidiert alle vier.

### Widget / UI
- Alle Zustände aus §10 an den dort genannten Keys, hell und dunkel.
- Drei Viewports (390/1024/1440) plus 320-px-Boden ohne Overflow.
- Board erscheint auf Mobil nicht; Termine-Ansicht erscheint nirgends.
- „Erledigt" fehlt bei `open`; „Bearbeiten" ist bei `archived` deaktiviert.
- Ohne `task.manage`: Primäraktion deaktiviert mit Tooltip, Bulk ausgeblendet.
- Archivierungsdialog nennt Titel und — bei `generated_key ≠ null` — den Vorlagenhinweis.
- **Keine Zeile und keine Kachel zeigt eine Roh-UUID.**

### Repository / integration
- Keine Duplikate der bestehenden 29 Adaptertests; neu nur, was der Screen-Controller ergänzt (Query-Aufbau, Paginierung, Entprellung der Invalidierungs-Reloads).

### Staging E2E
- **Nur Admin-Pfade fahrbar (B17).** Fahrbar: Anmeldung mit MFA → Aufgabe anlegen → mir zuweisen → `in_progress` → `done` → archivieren → Deep Link `/tasks/:id` → zwei Sitzungen erzeugen genau einen `version_conflict` mit erhaltener Eingabe.
- Negativtests ohne `task.manage` sind **blockiert**, bis `PERMISSION-CATALOG-02` Rollen jenseits `admin` seedet.

---

## 18. Acceptance criteria

1. Gegeben ein Nutzer mit `task.read` + `task.manage` + aal2, wenn er „Neue Aufgabe" mit Titel absendet, dann existiert die Aufgabe und das Detail zeigt sie.
2. Gegeben eine Aufgabe im Status `open`, dann bietet die UI **keine** Aktion „Erledigt" an.
3. Gegeben zwei Sitzungen an derselben Aufgabe, dann erhält die zweite einen Konflikt-Banner **mit erhaltener Eingabe**.
4. Gegeben ein Absendevorgang mit Timeout und Wiederholung, dann existiert danach **eine** Aufgabe, nicht zwei.
5. Gegeben ein Nutzer ohne `task.manage`, dann sind alle Mutationsaktionen deaktiviert bzw. ausgeblendet **und** ein direkter RPC-Aufruf scheitert serverseitig mit `forbidden`.
6. Gegeben eine aal1-Sitzung, dann zeigt die Seite „Zweiter Faktor erforderlich" und nicht „Keine Aufgaben".
7. Gegeben eine Bulk-Aktion über 42 Zeilen mit 4 Konflikten, dann meldet die UI „38 von 42 aktualisiert" und lässt die 4 gezielt nachbearbeiten.
8. Gegeben eine archivierte Aufgabe mit `generated_key`, dann nennt der Dialog vor der Bestätigung die Folge für die Vorlagenerzeugung.
9. Gegeben ein Realtime-Reconnect (bis zu drei Reconcile-Signale), dann führt die Fläche **genau einen** entprellten Reload aus.
10. **Die UI zeigt keine Gesamtzahl, keine Fälligkeitssortierung, keinen Fälligkeitsfilter, keinen Prioritätsfilter und kein Suchfeld**, solange `TASK-QUERY-01` nicht gelandet ist — und der Vortäuschungs-Regressionstest (§17) beweist das.
11. Es gibt kein Feld, keine Kachel und keine Summe für `estimated_cost`.
12. Nach dem Paket gibt es keinen erreichbaren Einstieg mehr in `tasks_screen.dart` oder `property_tasks_screen.dart`.

---

## 19. Out of scope

- Implementierung (Planungspaket).
- Alles unter §14 — jedes Gap ist ein eigenes Paket.
- Systemsichten, Termine-Ansicht, Suche, Zähler (B1–B5) — erst nach `TASK-QUERY-01`, dann als eigener PR.
- Zuweisung an andere Personen (B6).
- Checkliste, Kommentare, Anhänge, Abhängigkeiten (F2–F5).
- Vorlagen-Engine und Serverjob (B9).
- Export (F-Kandidat), Aufgabenkennzahlen im Dashboard (F8).
- Löschen der Legacy-Dateien und Entfernen von `GlobalPage.taskTemplates` — Hygiene-Folgepaket (`UI-HYGIENE-02`) nach nachgewiesenem Harvest.
- Änderungen an Schema, RLS, RPCs, Permission-Katalog oder Seiten-Mapping.

---

## 20. Closed decisions

Die sechs Entscheidungen sind in Shared §20 verbindlich geschlossen. Wirkung auf diesen Screen:

| Entscheidung | Wirkung hier |
|---|---|
| **OD-1 Retention** | keine clientseitige Retention; betrifft diesen Screen nicht direkt |
| **OD-2 Implementation order** | Maßstab der Klassifizierung in §0; Vortäuschungs-Regressionstest §17; Akzeptanzkriterium 10 |
| **OD-3 Subtasks** | Checkliste ist nicht ehrlich persistierbar ⇒ **F2**; keine Hierarchie |
| **OD-T1 Due-Filter/Sortierung** | Client-Vollladen mit Deckel **gestrichen**; B1–B5 gegen `TASK-QUERY-01`; §6.8 baut den `contextBar` gar nicht erst |
| **OD-T5 `estimated_cost`** | Feld, Kachel und Summe entfernt (§4, §7, §12); Akzeptanzkriterium 11 |
| **OD-N6 Event catalog** | dieser Screen löst **keine** Mitteilungen aus (§6.1) |

**Keine offenen Planungsentscheidungen mehr.** Was bleibt, sind Backend-Pakete.

---

## 21. Implementation handoff

### Umfang von `TASK-CENTER-01` (Welle T-2)
1. Präsentationsschicht für die Task-Fläche; Controller auf `TaskRepository` (bereits über `taskRepositoryProvider` verdrahtet).
2. Liste + `NxSplitView`-Detail + Board (vier status-gebundene Keysets), Filterleiste im gedeckten Umfang, Zustände nach §10.
3. `TaskCreateDialog` als exportierter geteilter Dialog; Umstellung von `OperationsAlertsPanel` darauf.
4. Vorlagen-Tab als Fläche mit ehrlichem Leerzustand.
5. Bulk-Aktionen mit Teilerfolgsbericht.
6. Property-Workspace-Tab bindet dieselbe Fläche mit vorbelegtem Kontext.
7. Vortäuschungs-Regressionstest (§17).

### Muss vorher auf `main` sein
- `UX-FOUNDATION-IMPL-01` — **erledigt, `791849f`**.
- Inkrement **A15** aus `TASKS-NOTIFICATIONS-CORE-01` (Provider, Routen, Fehlerklassifizierung, stabile `mutationId`).

### Nach diesem Paket, in dieser Reihenfolge
`TASK-QUERY-01` → Nach-PR „Systemsichten + Termine-Ansicht + Suche + Zähler" (B1–B5) → `TASK-ASSIGNEE-DIRECTORY-01` → Nach-PR „Zuweisung" (B6).

### Invarianten, die nicht regredieren dürfen
- `test/app_runtime_guard_test.dart` — kein SQLite, kein `StartupTaskService`.
- `test/ui/navigation/app_navigation_test.dart` — deterministische Readiness/Permission je `GlobalPage`.
- pgTAP 013/026/027 und die Policy-Inventur von exakt **41** Policies (`security_aal_mutation_matrix.sql` MUT-6b) — **kein Screen-PR fasst Policies an**.
- Actor-Guard im Adapter (`supabase_platform_repository_adapter.dart:723-728`).
- Keine zweite Task-UI, kein zweiter Anlege-Dialog.
- `PERMISSION-CATALOG-02` bleibt unberührt.
