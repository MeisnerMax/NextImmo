# Notification / Inbox Center (NOTIFICATIONS-V2)

## Metadata

- Package / screen ID: `TASKS-NOTIFICATIONS-01` (Tracker Wave 2) / Unterpaket **`NOTIFICATION-INBOX-01`** / Screen-ID `NOTIFICATIONS-V2`
- Domain: `platform_audit_jobs` (Aggregat `public.notifications`)
- Route: `GlobalPage.notifications`, Sidebar „Start → Mitteilungen", `routeKey start.notifications` (`app_navigation.dart:409-414`); neue Deep-Link-Route `/notifications` (Inkrement A15)
- Current implementation file(s):
  - `lib/ui/screens/notifications_screen.dart` (122, SQLite, in der Cloud-Shell unerreichbar)
  - `lib/data/repositories/notifications_repo.dart` (102), `lib/core/models/notification.dart` (49), `lib/core/notifications/notification_rules.dart` (90)
  - Zielvertrag: `lib/features/platform_audit_jobs/application/platform_repository.dart` (`NotificationPort`), `domain/notification_dto.dart`, `data/supabase_platform_repository_adapter.dart`, `supabase/migrations/20260723130000_p2_d04_tasks_notifications.sql`, `20260812100000_security_aal_enforcement.sql`
- Planning status: **APPROVED (2026-08-28; Entscheidungen in `tasks_notifications_shared.md` §20 geschlossen)** — Freigabe gilt **inkrementweise**, siehe §0. Die **Emitter** sind ausdrücklich BLOCKED; die Fläche selbst ist freigegeben.
- Dependencies: **Shared §** (normativ) · `UX-FOUNDATION-IMPL-01` (**auf main, `791849f`**) · Inkrement A15 aus `TASKS-NOTIFICATIONS-CORE-01`
- Related screens: `task_center.md`, Maintenance-Tickets, Operations-Alerts, Compliance-Dashboard, Property-Workspace

**Basis der Analyse:** `origin/main` `bf0693c` (Commit 2026-08-29; final verifiziert 2026-09-01), neu gefetcht und verifiziert.

Abschnittsnummern folgen `SCREEN_SPEC_TEMPLATE.md`. „Shared §n" verweist auf `docs/product/screens/tasks_notifications_shared.md`.

---

## 0. Statusklassifizierung dieses Screens

Vollständige Matrix: Shared §0.2/§0.3.

**APPROVED (V1)** — A11 Grundfläche mit Feed, `unreadOnly`, Zeitgruppierung, Split-Detail, Zustände · A12 Read-Semantik (einzeln, idempotent, `not_found`-Behandlung) · A13 echte Deep Links für die auflösbaren Ziele · A14 Glocken-Badge mit ehrlicher Zählung.

**BLOCKED** — B11 **alle Emitter** (`task.assigned`, `task.unassigned`, `task.blocked`, `task.done`) → `NOTIFICATION-EMITTER-01` + `PERMISSION-CATALOG-02` · B10 Fristereignisse → `TASK-SCHEDULER-01` · B12 `maintenance.ticket_assigned` → `MAINTENANCE-PARITY-01` · B13 `operations.signal_raised` → kein Emitter · B14 „Alle als gelesen markieren" → `NOTIFICATION-READ-02` · B15 Filter nach Art/Kontexttyp/Zeitraum und Suche → `NOTIFICATION-QUERY-01` · B16 empfängergenaues Realtime-Wake → `NOTIFICATION-REALTIME-01` · B17 Nicht-Admin-Staging-E2E → `PERMISSION-CATALOG-02`.

**FUTURE** — F7 Benachrichtigungseinstellungen · F11 Retention als Produktverhalten (OD-1) · F13 E-Mail-/Push-/Desktop-Kanäle · F3 Kommentar- und Mention-Mitteilungen.

**Die zentrale Konsequenz, die im Review ausgesprochen sein muss:** V1 liefert eine vollständige, ehrliche Inbox — die **leer bleibt**, bis `NOTIFICATION-EMITTER-01` existiert. Das ist kein Versehen, sondern die Folge von OD-N6 (nur Ereignisse mit realem Emitter) und des Befunds in §6.1. Die Fläche trotzdem jetzt zu bauen ist richtig, weil sie klein ist, den Deep-Link-Vertrag festzurrt und der Emitter sonst gegen nichts entwickeln würde.

---

## 1. Purpose

Die Inbox ist der Ort, an dem eine Person erfährt, **was sie persönlich betrifft und wohin sie springen muss** — nicht, was im Workspace alles passiert ist.

Der Ist-Stand ist davon weit entfernt:

- Der Legacy-Screen rendert `item.message` roh und darunter eine Debug-Zeile `'${item.kind} | ${item.entityType}:${item.entityId} | <ISO-8601-UTC>'` (`notifications_screen.dart:91-94`) — Nutzer sehen eine **rohe UUID und einen UTC-Zeitstempel**.
- **Kein `ListTile` hat ein `onTap`.** Es gibt keinen Weg von einer Mitteilung zu ihrem Gegenstand. Screen Map: „Deep-Links statt Rohtext" (`PRODUCT_SCREEN_MAP.md:50`).
- Es gibt **keinen Empfänger**: `NotificationRecord` hat kein `recipient_user_id`; jede Mitteilung war für jeden.
- Sechs Ereignisarten existieren (`threshold`, `task_due_soon`, `task_overdue`, `maintenance_due_soon`, `maintenance_overdue`, `covenant_breach`), **drei Produzenten schreiben roh in die Tabelle** (`task_generation_service.dart:158-167`, `maintenance_repo.dart:251-260`, `covenant_repo.dart:206-215`) — vorbei an Repository, Audit und Suchindex, mit drei unterschiedlichen Dedupe-Regeln und einer Regel ganz ohne Dedupe.
- Nichts löscht je eine Zeile.
- `due_at` wird gespeichert, **nie angezeigt** und bei der Cloud-Migration bewusst verworfen (`mapping.notification_due_at_dropped`).

Der Cloud-Vertrag ist demgegenüber vollständig und ungenutzt: `recipient_user_id not null`, normalisierter `kind`, `title` + `body` getrennt, `entity_type`/`entity_id` als Sprungziel, `read_at`, Version, Audit, AAL2-Policy. Es fehlt der Screen — und der Provider, der `NotificationPort` überhaupt erreichbar macht (`platform_providers.dart` exponiert allein `taskRepositoryProvider`).

---

## 2. Primary users and jobs

| Rolle | Job | Erwartetes Ergebnis |
|---|---|---|
| Objektbetreuung | „Was ist neu für mich?" | zugewiesene Aufgabe → ein Klick zur Aufgabe |
| Asset Management | „Was ist eskaliert?" | überfällige Arbeit, blockierte Vorgänge |
| Vermietung | „Welche Frist läuft?" | Vertragsfrist, Übergabetermin |
| Buchhaltung | „Was muss ich bestätigen?" | Beleg- oder Dokumentfrist |
| Bauleitung | „Welches Ticket ist meins?" | Ticketzuweisung |
| Alle | „Was kann weg?" | gelesen markieren, ohne die Zeile zu verlieren |

Die Inbox ist eine **Aktionsliste**, keine Chronik. Sie öffnet deshalb auf „Ungelesen" — wie der Legacy (`_unreadOnly = true`) und wie die monday-Glocke.

In V1 werden diese Jobs mangels Emitter nicht bedient (B10–B13). Was V1 bedient: alles, was ein Admin oder eine Migration bereits als adressierte Mitteilung angelegt hat, wird korrekt gelesen, gruppiert, verlinkt und als gelesen markiert.

---

## 3. Entry points and navigation

1. Sidebar „Start → Mitteilungen".
2. **Glocken-Indikator in der `CloudTopBar`** mit Ungelesen-Badge (A14). Existiert heute nicht und ist der wichtigste Einstieg — eine Inbox, die man aktiv aufsuchen muss, wird nicht gelesen. Kleine, generische Shell-Erweiterung (Foundation §17); wächst sie über Badge + Klick hinaus, wird sie ein eigenes Shell-Paket.
3. Deep Link `/notifications` (A15).

**Ausstiege — der eigentliche Zweck:** Jede Mitteilung springt auf ihr Ziel (§9). Nach dem Sprung bleibt die Inbox als Rücksprungziel bekannt („Zurück zu Mitteilungen" im Zielheader, solange der Sprung in derselben Sitzung erfolgte).

**Kein Panel-Einstieg von außen.** Anders als Aufgaben sind Mitteilungen personenbezogen; Panels sind objektbezogen.

---

## 4. Information architecture

```
NxPageHeader  „Mitteilungen"  ['Start','Mitteilungen']
              [Sekundär: Aktualisieren]
──────────────────────────────────────────────────────────
(optional) NxLiveUpdatesNotice
──────────────────────────────────────────────────────────
contextBar:  [Ungelesen] [Alle]
──────────────────────────────────────────────────────────
┌──────── Liste (flex 3) ──────────┬──── Detail (flex 2) ────┐
│ ▸ Heute                          │  Titel                   │
│   ● Titel                        │  Body                    │
│     Art · Objekt · vor 2 Std     │  Art · Zeitpunkt         │
│     [Öffnen] [Gelesen]           │  Kontext (EntityRefChip) │
│ ▸ Diese Woche                    │  [Zum Vorgang öffnen]    │
│ ▸ Älter                          │  [Als gelesen markieren] │
│   [Weitere laden]                │                          │
└──────────────────────────────────┴──────────────────────────┘
```

**Zwei Streichungen gegenüber der Vorfassung:**

- **Keine `ListFilterBar`.** Alle geplanten Filter (Art, Kontexttyp, Zeitraum, Suche) sind serverseitig nicht möglich (B15); eine clientseitige Fassung über einem Keyset fällt unter OD-2. Die Leiste entfällt vollständig, statt leer oder deaktiviert dazustehen.
- **Nur zwei Tabs statt vier.** „Meine Aufgaben" und „Fristen" wären Filter über `kind` — B15. Bleiben „Ungelesen" (Standard) und „Alle", beide über `NotificationFeedQuery.unreadOnly`.
- Die Aktion **„Alle als gelesen markieren" ist nicht im Header** — sie existiert im Contract nicht (B14). Sichtbar-aber-deaktiviert wurde verworfen: ein dauerhaft toter Knopf ist schlechter als seine Abwesenheit; die Lücke steht im Leerzustandstext und im Tracker.

**Gruppierung ist zeitlich, nicht thematisch:** Heute · Diese Woche · Älter. Der Auslöser für einen Inbox-Besuch ist „was ist neu", nicht „zeig mir alle Wartungsmeldungen".

**Warum Gruppierung erlaubt ist, Filtern aber nicht:** Der Feed ist serverseitig streng `created_at DESC, id DESC` sortiert. Die geladenen Seiten sind damit ein exaktes Zeit-Präfix — alles Nichtgeladene ist strikt älter. „Heute" und „Diese Woche" sind deshalb **vollständig**, sobald die erste Seite über die Wochengrenze hinausreicht; nur „Älter" ist naturgemäß unvollständig und trägt „Weitere laden". Gruppierung ordnet also nur, was ohnehin exakt ist — sie behauptet keine Vollständigkeit, die der Contract nicht hergibt. Ein `kind`-Filter könnte das nicht leisten.

**Detail-Pane trotz kurzem Inhalt**, weil der Body bis 4000 Zeichen tragen kann und der Kontext sichtbar sein soll, bevor man springt. Auf schmalen Viewports ersetzt das Detail die Liste (`NxSplitView`, Foundation §8).

---

## 5. Layout and interaction model

| Viewport | Verhalten |
|---|---|
| Desktop (> 1199) | `NxSplitView` 3:2, Inhalt ≤ 1440, `context.adaptivePagePadding` |
| Tablet (768–1199) | Detail ersetzt Liste, „Zur Liste" |
| Mobil (≤ 767) | `ListTile`-Liste mit `chevron_right`; **Tap = direkt springen**, nicht Detail öffnen — auf dem Telefon ist der Zwischenschritt reine Reibung. Der Body steht in der Zeile mit `maxLines: 2` |
| 320-px-Boden | kein Overflow; Titel 2 Zeilen, Metazeile 1 Zeile mit Ellipse |

**Zeilenanatomie**
```
● Wohnungsübergabe Musterstr. 4 — dir zugewiesen
  Aufgabe · Musterstr. 4 · vor 2 Stunden          [Öffnen] [✓]
```
- `●` = Ungelesen-Punkt **plus** kräftigere Schrift **plus** `Semantics(label: 'Ungelesen')`. Der Legacy nutzte allein `FontWeight.w700` vs. `w500` — für Screenreader unsichtbar.
- Zeit **relativ** bis 7 Tage („vor 2 Stunden"), danach Datum. Nie ISO-8601, nie UTC.
- Kontext als Name, sonst als Typlabel — **nie** als UUID.
- Zeilenklick = Detail (Desktop) bzw. Sprung (Mobil). Das Häkchen markiert gelesen, **ohne** zu springen.

**Automatisches Lesen beim Springen: ja.** Wer eine Mitteilung öffnet, hat sie gelesen — die monday-Semantik, und sie erspart den doppelten Klick. Das Häkchen bleibt für „gesehen, kein Handlungsbedarf".

**Kein Löschen, kein Archivieren einzelner Mitteilungen.** Der Vertrag bietet keinen Pfad; ein UI-seitiges „Ausblenden" ohne Serverzustand wäre pro Gerät verschieden. Nach **OD-1** gibt es in V1 auch **keine clientseitige Retention**: Die Liste zeigt, was der Server liefert, ohne eigene Ausblendlogik und ohne clientseitig gerechnetes Relevanzende.

---

## 6. Functional requirements

### 6.1 Warum in V1 keine Mitteilung entsteht — der Kernbefund

`create_notification` verlangt **`notification.manage` beim Auslöser** (`20260723130000:1326-1331`) und leitet keine Empfänger her: `p_recipient_user_ids` ist die einzige Quelle (`:1310-1353`). Ein Client-Emitter hätte damit nur zwei Formen, und beide sind falsch:

- jeder Aufgaben-Bearbeiter bekommt `notification.manage` — dann kann er beliebige Personen im Workspace mit beliebigem Text anschreiben; oder
- nur Admins lösen Mitteilungen aus — dann entsteht die Mitteilung nicht dort, wo die Arbeit passiert.

Die richtige Lösung ist der **serverseitige Fan-Out innerhalb von `create_task` und `transition_task_status`**: dort ist der Empfängerkreis eindeutig aus der Zeile ableitbar (`assigned_to`, `created_by`), der Auslöser braucht kein Zusatzrecht, AS-1 („kein Self-Notify") ist strukturell erfüllt, und `mutationId`/Audit bleiben in einem Vorgang. Das ist ein Schema-/RPC-Paket: **`NOTIFICATION-EMITTER-01`** (B11).

**Konsequenz für diesen Screen:** Es gibt in V1 **keinen** UI-Pfad, der eine Mitteilung erzeugt — weder hier noch im Task Center. Der Ereigniskatalog aus Shared §6.3 ist die Anforderung an das Emitter-Paket, nicht eine Liste dessen, was V1 tut.

### 6.2 Feed lesen — **APPROVED (A11)**
- **Auslöser:** Seitenaufruf, Tabwechsel, Invalidierung, „Aktualisieren".
- **Aufruf:** `notificationFeed(NotificationFeedQuery{ workspaceId, recipientUserId, unreadOnly, page })`.
- **Empfängerbindung:** `recipientUserId` ist **immer** der angemeldete Nutzer. Der Server erlaubt `notification.read`-Trägern breiteres Lesen (Policy `notifications_select_own_or_read`), aber „fremde Mitteilungen lesen" ist kein Produktfeature dieser Fläche — das wäre ein Admin-Werkzeug.
- **Sortierung:** `created_at DESC, id DESC` (fest, Adapter `:123-148`). Hier trifft die Vertragsbeschränkung genau die richtige Anzeige (§4).
- **Paginierung:** Keyset „Weitere laden", 50 je Seite.
- **Fehler:** `infrastructureFailure` → `NxEmptyState.error` mit Retry. Der Adapter unterscheidet heute nicht zwischen RLS-Ablehnung und Infrastrukturfehler (`:431`) — die UI darf deshalb **nicht** „Kein Zugriff" behaupten (Klassifizierung ist Teil von A15).

### 6.3 Als gelesen markieren — **APPROVED (A12)**
- **Auslöser:** Häkchen in der Zeile, Knopf im Detail, oder implizit beim Öffnen des Ziels.
- **Aufruf:** `markNotificationRead(MarkNotificationReadCommand{ context, notificationId })` — **ohne** `expectedVersion` (per Vertrag, `platform_repository.dart:227-238`).
- **Erlaubt für jeden Empfänger**, keine Permission-Prüfung; Autorisierung ist die Empfängerbindung im Row-Lookup.
- **Idempotent:** erneutes Markieren ist Erfolg; ein Doppelklick ist harmlos.
- **`not_found` heißt nicht „kein Recht", sondern „nicht deine oder nicht mehr da"** (`:1529-1537`). UI-Text: „Diese Mitteilung ist nicht mehr verfügbar." — nie „Kein Zugriff".
- **Kein Domain-Event.** Andere Sitzungen desselben Nutzers erfahren nichts. Der Badge wird lokal dekrementiert und beim nächsten Reconcile korrigiert.
- Optimistisches UI: Zeile sofort als gelesen darstellen, bei Fehler zurücksetzen + SnackBar.

### 6.4 Zum Vorgang springen — **APPROVED (A13)**
Kernfunktion. Auflösung und Übergangsverhalten in §9.

### 6.5 Alle als gelesen markieren — **BLOCKED (B14)**
Der Legacy hatte es (`notifications_screen.dart:52-62`); der Cloud-Vertrag hat es nicht. N Einzelaufrufe sind bei 200 Ungelesenen kein Produktionspfad (200 RPCs, 200 Audit-Zeilen, 200 `mutationId`). Die Aktion existiert in V1 **nicht** — auch nicht als deaktivierter Knopf. Lücke: `NOTIFICATION-READ-02`.

### 6.6 Verfall und Aufräumen — **FUTURE (F11), nach OD-1**
- **V1 hat keine clientseitige Retention und kein clientseitiges Löschen.** Die UI zeigt, was der autoritative Server liefert.
- Insbesondere wird **kein** clientseitig gerechnetes Relevanzende zum Ausblenden oder Nicht-Zählen benutzt — das wäre eine unsichtbare Zweitwahrheit neben dem Server.
- Die fachlichen Relevanzfenster bleiben als Anforderung an `NOTIFICATION-RETENTION-01` dokumentiert (`expires_at`, Dedupe-Fenster, Retention-Job). Das Schema hat heute keins davon.

### 6.7 Was die Inbox nicht tut

| Nicht | Warum |
|---|---|
| Aktivitätsstrom des Workspace zeigen | Shared §4: das ist ACTIVITY. monday hat Glocke *und* Update-Feed; NexImmo übernimmt bewusst nur die Glocke |
| `liveUpdatesDegraded`, Job-Status, Rechteänderungen zeigen | SYSTEM EVENT — gehört unter den Page-Header der betroffenen Fläche |
| Mitteilungen erzeugen | §6.1 |
| Antworten / kommentieren | F3 |
| Einstellungen bieten | F7, kein Contract (§12) |
| Fremde Postfächer zeigen | §6.2 |

---

## 7. Data requirements

| Angezeigt | Quelle | Formatierung / Regel |
|---|---|---|
| Titel | `notifications.title` (1–300) | 2 Zeilen, Ellipse. **Faktisch unveränderlich** (kein UPDATE-Pfad, Shared §4 Regel 4) — nie eine Zahl oder einen Status hineinschreiben, der veralten kann |
| Body | `notifications.body` (≤ 4000, optional) | Liste 2 Zeilen, Detail vollständig; Klartext |
| Art | `notifications.kind` | **nie roh anzeigen.** Client-Mapping `kind → deutsches Label + Icon`; unbekannte Art → „Hinweis" + `notifications_none`, Rohwert nur im Tooltip |
| Zeit | `created_at` | relativ ≤ 7 Tage, sonst Datum, in Workspace-Zeitzone |
| Gelesen | `read_at` | Punkt + Schriftstärke + Semantik |
| Kontext | `entity_type` + `entity_id` | `EntityRefChip` mit aufgelöstem Namen; ohne Auflösung Typlabel („Objekt"), **niemals** die UUID |
| Empfänger | `recipient_user_id` | nicht angezeigt (immer der Nutzer selbst) |
| Version, `created_by`/`updated_by` | – | nicht angezeigt |

**Kind-Katalog** — die Labels und Ziele, die die UI kennt. Nach **OD-N6** ist er geschlossen; neue Arten entstehen nur durch explizite Contract-Erweiterung. Alle Arten sind in V1 ohne Emitter (§6.1), das Mapping existiert trotzdem, damit vorhandene oder migrierte Zeilen korrekt gerendert werden:

| `kind` | Label | Icon | Ziel | Emitter |
|---|---|---|---|---|
| `task.assigned` | „Aufgabe zugewiesen" | `assignment_ind_outlined` | `/tasks/:id` | **B11** |
| `task.unassigned` | „Zuweisung entfernt" | `assignment_late_outlined` | `/tasks` | **B11** |
| `task.blocked` | „Aufgabe blockiert" | `block_outlined` | `/tasks/:id` | **B11** |
| `task.done` | „Aufgabe erledigt" | `check_circle_outline` | `/tasks/:id` | **B11** |
| `task.due_soon` | „Aufgabe wird fällig" | `schedule_outlined` | `/tasks/:id` | **B10** |
| `task.overdue` | „Aufgabe überfällig" | `error_outline` | `/tasks/:id` | **B10** |
| `task.digest.due` | „Fällige Aufgaben" | `summarize_outlined` | `/tasks` | **B10** |
| `document.expiring` | „Dokument läuft ab" | `description_outlined` | Compliance-Dashboard | **B10** |
| `maintenance.ticket_assigned` | „Ticket zugewiesen" | `build_outlined` | Maintenance-Ticket | **B12** |
| `operations.signal_raised` | „Betriebshinweis" | `warning_amber_outlined` | Operations-Alerts des Objekts | **B13** |

Der Legacy-Katalog wird **nicht** übernommen: `threshold` deckte zwei fachlich verschiedene Regeln unter einem Namen ab (Leerstand und NOI-Rückgang, `notification_rules.dart:52-85`) und war nur über den Meldungstext unterscheidbar.

**Keine Severity-Spalte.** `public.notifications` hat keine. Dringlichkeit kommt aus der Art (`task.overdue` rot, `task.done` neutral), nicht aus einem eigenen Feld. Ein Severity-Feld wäre ein Schema-Gap, den V1 nicht braucht.

---

## 8. Permissions and security behavior

| Ebene | Regel |
|---|---|
| Seite sichtbar | `notification.read` (`app_navigation.dart:282`); ohne Recht Sidebar aus, Deep Link → `Key('cloud-destination-forbidden')` „(notification.read)" |
| Feed lesen | Policy `notifications_select_own_or_read` — eigene Zeilen **oder** `notification.read` |
| Als gelesen markieren | **keine Permission**; Empfängerbindung im RPC |
| Mitteilungen erzeugen | `notification.manage` — in dieser Fläche gar nicht angeboten (§6.1) |
| Alles | **AAL2.** Besonders scharf: Die Policy wurde für DEC-025 eigens umgeschrieben, weil der Selbst-Disjunkt den AAL-Helfer sonst umgangen hätte (`20260812100000:437-448`). Bei aal1 sieht der Nutzer **null eigene Mitteilungen** — pgTAP 027 A6 pinnt das |

**Zwei Fallen, die die UI korrekt behandeln muss**

1. **aal1 ⇒ leerer Feed.** Ohne den eigenen Zustand „Zweiter Faktor erforderlich" (§10) sieht eine korrekt gesicherte Sitzung wie Datenverlust aus.
2. **Widerspruch Seiten-Gate vs. Datenzugriff.** Die Seite ist auf `notification.read` gegated, aber ein Nutzer **ohne** dieses Recht kann seine eigenen Mitteilungen sehr wohl lesen (Policy-Disjunkt) — er kommt nur nicht auf die Seite. Genau dieser Fall ist als Fixture angelegt (`supabase/tests_integration/p2_d04_setup.sql:70-77`: „recipient" mit `task.read` + `workspace.read`, ohne Notification-Recht). Zusätzlich bekommt er kein Realtime-Wake, weil das Topic `workspace:<id>:notification.read` heißt.

   **Empfehlung, aber ausdrücklich nicht hier gelöst:** `notification.read` gehört in jedes Rollenprofil, das Mitteilungen empfangen soll. Das ist eine Katalog- und Seed-Frage und damit **`PERMISSION-CATALOG-02`** — dieses Paket fasst weder Katalog noch Seeds noch das Seiten-Mapping an (Foundation §3 friert es ein).

---

## 9. Realtime / freshness behavior

- **Abonniert:** `PlatformQueryInvalidationSource.watchWorkspace`, Aggregat `PlatformAggregate.notification`; Topic `workspace:<id>:notification.read`.
- **Ereignis:** nur `notification.fanned_out`, `aggregate_type = notification_batch`, Payload `{kind, recipient_count}` — **ohne** `aggregate_id`, **ohne** Empfängerliste (`20260723130000:1408-1416`). Der Adapter mappt `notification` und `notification_batch` auf dasselbe Aggregat (`supabase_domain_event_consumer_adapter.dart:284-296`).
- **Folge:** Jeder Fan-Out invalidiert workspaceweit; die Inbox lädt entprellt nach und stellt fest, ob für sie etwas dabei war. Grob, aber korrekt und ohne Leck.
- **Empfänger ohne `notification.read` bekommen gar kein Wake** → **B16 / `NOTIFICATION-REALTIME-01`**. Für sie ist der Feed erst nach manuellem Aktualisieren oder Reconnect frisch. Das muss im Review bewusst akzeptiert werden.
- **`mark_notification_read` publiziert nichts** — Mehrgeräte-Nutzung sieht den Lesestatus erst beim nächsten Reload.
- **Reconnect:** ein Reconcile je wiederverbundenem Topic (`:203-217`), vom Screen zu **einem** Reload entprellt.
- **Glocken-Badge (A14):** gespeist aus demselben `unreadOnly`-Feed. **Es gibt keine Count-RPC.** Der Badge zeigt die exakte Zahl bis zur Seitengröße und darüber „50+" — **niemals** eine erfundene Gesamtzahl. Der Tooltip nennt die Semantik.

### Deep-Link-Auflösung (A13) — und die verbleibende Lücke

Ziel: `(entity_type, entity_id)` → In-Shell-Navigation.

| `entity_type` | Ziel | V1 |
|---|---|---|
| `property` | Property-Workspace | ✅ |
| `party` | Parteien / Mieter (workspaceweit) | ✅ |
| `workspace` | Task Center bzw. gemeinte Sammelfläche | ✅ |
| Task selbst (`/tasks/:taskId`) | Task-Detail | ✅ über A15 |
| `unit` | `unitsRouteFor(propertyId)` | ⚠️ **braucht die propertyId**, die die Mitteilung nicht trägt |
| `lease` | `leasesRouteFor(propertyId)` | ⚠️ dito |
| `maintenance_ticket` | `maintenance` bzw. `propertyMaintenanceRouteFor` | ⚠️ dito |
| `capex_project` | Property-Maintenance/CapEx | ⚠️ dito |
| `portfolio` | Portfolios | ❌ Fläche noch nicht cloudfähig (P2-D09) |
| `scenario` | Szenario | ❌ noch nicht cloudfähig |

**Der Grund für die vier ⚠️:** Property-scoped Routen sind `'<route>/<propertyId>'` (`app_navigation.dart:60-70`), weil es in der Cloud keine `PropertyShell` gibt, aus der die Id käme. Die Inbox müsste das übergeordnete Objekt auflösen — im Legacy waren das bis zu vier Zusatzabfragen je Zeile (`tasks_repo.dart:501-593`). Das ist derselbe Bedarf wie das Objekt-Rollup im Task Center und gehört in **`TASK-QUERY-01`** (denormalisierte `property_id` bzw. `search_index`-Auflösung).

**Verhalten, bis das fällt:** Ein nicht auflösbares Ziel zeigt einen **deaktivierten** „Öffnen"-Knopf mit Tooltip „Ziel ist noch nicht verfügbar" — keine Roh-ID, kein toter Klick, kein Fehler. Die Mitteilung bleibt lesbar und markierbar. Das ist bewusst *kein* Widerspruch zu OD-2: der Knopf verspricht nichts, er benennt eine Lücke.

---

## 10. Screen states

| Zustand | Rendering | Key |
|---|---|---|
| idle (kein Workspace) | `NxEmptyState(Icons.workspaces_outline, 'Kein Arbeitsbereich aktiv')` | `notification-inbox-idle` |
| loading | `NxListSkeleton` | `notification-inbox-loading` |
| empty — Tab „Ungelesen" | `NxEmptyState(Icons.mark_email_read_outlined, 'Alles gelesen', 'Neue Mitteilungen erscheinen hier automatisch.')` — **positiv formuliert**, das ist der Zielzustand | `notification-inbox-empty-unread` |
| empty — Tab „Alle" | „Noch keine Mitteilungen." | `notification-inbox-empty-all` |
| populated | gruppierte Liste | `notification-inbox-ready` |
| partial | + „Weitere laden"; Badge „50+" statt Gesamtzahl | `notification-inbox-partial` |
| forbidden | `NxEmptyState(Icons.lock_outline, 'Kein Zugriff auf Mitteilungen', '… benötigt die Berechtigung (notification.read).')` | `notification-inbox-forbidden` |
| **AAL2 erforderlich** | `NxEmptyState(Icons.shield_outlined, 'Zweiter Faktor erforderlich', 'Mitteilungen sind erst nach der Zwei-Faktor-Anmeldung sichtbar.')` | `notification-inbox-aal-required` |
| error | `NxEmptyState.error(description: …, onRetry: …)` | `notification-inbox-error` |
| Detail: notFound | „Diese Mitteilung ist nicht mehr verfügbar." | `notification-detail-not-found` |
| Detail: idle | „Wähle eine Mitteilung." | `notification-detail-idle` |
| Ziel nicht auflösbar | „Öffnen" deaktiviert + Tooltip | `notification-target-unavailable` |
| realtime degraded | `NxLiveUpdatesNotice` | `notification-inbox-live-degraded` |
| Aktion läuft / Erfolg / Fehler | optimistische Zeile; SnackBar bei Fehler mit Rücksetzung | – |

Der Unterschied zwischen **empty-unread** („Alles gelesen") und **empty-all** („Noch keine Mitteilungen") ist wichtig: Der Legacy zeigte in beiden Fällen dasselbe nüchterne „No notifications." und ließ den erfolgreich abgearbeiteten Posteingang wie einen Defekt aussehen.

**Ein Sonderfall für V1:** Solange kein Emitter existiert, ist **empty-all** der Normalzustand. Der Text nennt das ehrlich: „Noch keine Mitteilungen. Automatische Hinweise zu Aufgaben und Fristen werden serverseitig erzeugt und sind noch nicht aktiv."

---

## 11. Search / filter / sort

### V1 — serverseitig gedeckt (A11)

| Steuerung | Umsetzung |
|---|---|
| Ungelesen / Alle | `NotificationFeedQuery.unreadOnly` |
| Empfänger | fest der angemeldete Nutzer |
| Sortierung | fest `created_at DESC` — keine Steuerung nötig, weil es genau die richtige ist |

### V1 — bewusst NICHT vorhanden (**BLOCKED B15**, `NOTIFICATION-QUERY-01`)

Filter nach Art, nach Kontexttyp, nach Zeitraum sowie Volltextsuche. `NotificationFeedQuery` kennt nur `recipientUserId`, `unreadOnly`, `page`. Eine clientseitige Fassung über einem Keyset würde Vollständigkeit behaupten, die es nicht gibt (OD-2) — anders als die Zeitgruppierung, die aus der Sortierung folgt und deshalb exakt ist (§4).

Die vier zusätzlichen Tabs der Vorfassung („Meine Aufgaben", „Fristen") entfallen aus demselben Grund.

### Persistenz
Tab-Zustand bildschirmlokal, zurückgesetzt beim Workspace-Wechsel.

---

## 12. Forms and validation

Die Inbox hat **keine Formulare**. Zwei Punkte gehören trotzdem hierher:

1. **Einstellungen sind FUTURE (F7).** Der Auftrag fragte „notification preferences soweit Contract vorhanden" — die ehrliche Antwort: **kein Contract vorhanden.** Keine Preferences-Tabelle, keine Ereignis-Abonnements, kein Vorwarnfenster je Nutzer. Das Zielbild (persönlich × Ereignisart × Objekt) ist beschrieben, aber ohne Contract nicht planbar. V1 kompensiert durch einen sehr schmalen Ereigniskatalog statt durch Stummschalter — wo wenig gesendet wird, braucht niemand einen Regler.
2. **Fehler-Mapping** nach Shared §12, mit einer Abweichung: `not_found` ist hier **kein** Detail-Zustandswechsel, sondern die Meldung „Diese Mitteilung ist nicht mehr verfügbar." plus Entfernen der Zeile aus der Liste.

---

## 13. Shared components

**Wiederverwenden:** `NxPageHeader`, `NxBreadcrumbs`, `NxActionToolbar`, `NxCard`, `NxEmptyState` (inkl. `NxEmptyState.error`), `NxSectionHeader`, `ResponsiveConstraints`, `NxContentFrame`.

**Seit `791849f` auf main:** `NxSplitView`, `NxListSkeleton`, `NxLiveUpdatesNotice`, `NxNotice`, `NxEmptyState.error`.

**Nicht verwendet:** `ListFilterTemplate`/`ListFilterBar` — V1 hat keine Filterleiste (§4/§11). `NxDataTableShell` — eine Mitteilungsliste ist keine Tabelle: keine Spalten, keine Sortierung, keine Spaltenauswahl.

**Geteilt mit dem Task Center:** `EntityRefChip` (`SHARED-UI-ENTITYREF-01`) — dieselbe Kontextdarstellung und dieselbe Namensauflösung.

**Neu, klein:** `NotificationRow` (bleibt zunächst im Feature), `notification_kind_labels.dart` (Katalog aus §7).

**Shell-Erweiterung:** Glocken-Indikator in der `CloudTopBar` — klein und generisch genug, um im Feature-PR zu reiten (Foundation §17).

---

## 14. Backend gaps

Vollständig mit Belegen in Shared §14. Für diesen Screen:

| Paket | Wirkung hier |
|---|---|
| **NOTIFICATION-EMITTER-01** | **entscheidend** — ohne ihn entsteht keine einzige Mitteilung (§6.1) |
| **PERMISSION-CATALOG-02** | `notification.read` fehlt in allen Rollen außer `admin`; ohne das seeded niemand Empfänger, und Nicht-Admin-E2E ist blockiert |
| **TASK-SCHEDULER-01 (DEBT-009)** | keine Frist- und Sammelereignisse |
| **TASK-QUERY-01** | vier Deep-Link-Ziele (Einheit, Vertrag, Ticket, CapEx) nicht adressierbar (§9) |
| **NOTIFICATION-READ-02** | kein Sammel-Lesen |
| **NOTIFICATION-QUERY-01** | keine Filter, keine Suche |
| **NOTIFICATION-REALTIME-01** | kein empfängergenaues Wake |
| **NOTIFICATION-RETENTION-01** | kein Verfall (F11, OD-1) |
| A15 (Core) | ohne Provider ist `NotificationPort` unerreichbar; ohne `/tasks/:id` hat die wichtigste Mitteilungsart kein Ziel |

---

## 15. Accessibility and usability

- Ungelesen ist **dreifach** kodiert: Punkt, Schriftstärke, `Semantics(label: 'Ungelesen')`.
- Badge und Tab-Zähler haben ein Textäquivalent („3 ungelesene Mitteilungen"; bei Deckelung „mehr als 50 ungelesene Mitteilungen").
- Tastatur: Pfeiltasten durch die Liste, `Enter` = öffnen/springen, `M` = als gelesen markieren (im Hilfetext dokumentiert), `Escape` schließt das Detail auf schmalen Viewports.
- Zeitangaben für Screenreader absolut: `Semantics(label: '28. August 2026, 14:12')` hinter der relativen Anzeige.
- Icon-Buttons mit `tooltip`; das Häkchen heißt „Als gelesen markieren: <Titel>".
- Touchziele ≥ 44 px; das Häkchen ist auf Mobil nicht kleiner als der Rest.
- Kontraste ausschließlich über Tokens.

---

## 16. Analytics / audit / history

- `mark_notification_read` schreibt serverseitig eine Audit-Zeile (`notification.read`) — auch beim wiederholten Markieren.
- `create_notification` schreibt **eine** Audit-Zeile je Fan-Out (`notification.fan_out`, `aggregate_type = notification_batch`, `entity_id = null`).
- Die Inbox schreibt kein Audit und zeigt keins.
- **Keine Mitteilungsinhalte in Logs oder Fehlermeldungen** — Titel und Body können Mieter- und Objektdaten enthalten; pgTAP 027 pinnt genau diesen Vertraulichkeitsanspruch serverseitig („Body that must stay hidden at aal1").

---

## 17. Test plan

### Unit / application
- Feed-Query trägt **immer** `recipientUserId` = angemeldeter Nutzer.
- Kind→Label/Icon/Ziel-Mapping vollständig; unbekannte Art fällt auf „Hinweis" zurück, ohne den Rohwert anzuzeigen.
- Zeitgruppierung an Tagesgrenzen inklusive Zeitzonen-Randfall; „Heute"/„Diese Woche" sind vollständig, sobald das geladene Präfix die Grenze überschreitet.
- Optimistisches Lesen: Fehler setzt die Zeile zurück.
- `not_found` entfernt die Zeile und meldet „nicht mehr verfügbar", **nicht** „Kein Zugriff".
- Deep-Link-Auflösung: für jedes `entity_type` entweder ein Ziel oder der Zustand „nicht verfügbar" — nie eine Roh-ID.
- **Vortäuschungs-Regression:** kein Filter, keine Suche, keine Gesamtzahl, die `NotificationFeedQuery` nicht trägt; der Badge zeigt oberhalb der Seitengröße „50+".

### Widget / UI
- Alle Zustände aus §10, hell und dunkel, an den dortigen Keys.
- Drei Viewports + 320-px-Boden.
- Mobil: Tap springt direkt, öffnet kein Detail.
- Ungelesen-Kodierung ohne Farbe erkennbar (Test gegen `Semantics`).
- **Keine Zeile rendert eine UUID oder einen ISO-8601-Zeitstempel** — expliziter Regressionstest gegen den Legacy-Fehler.
- Es gibt weder eine Filterleiste noch einen „Alle als gelesen"-Knopf.

### Repository / integration
- **Neu:** Adaptertest für den in A15 verdrahteten `NotificationPort` (heute existiert kein Provider).
- Keyset-Fortsetzung auf `(created_at, id)`.
- Bestehende Abdeckung nicht duplizieren: `supabase_platform_repository_adapter_test.dart` (29), `supabase_domain_event_consumer_adapter_test.dart` (12), `test/integration/supabase_platform_repository_integration_test.dart:95` (empfängergebundener Feed, fremde Mitteilung → `not_found`).

### Staging E2E
- **Nur Admin-Pfade fahrbar (B17).** Fahrbar mit administrativ erzeugten Mitteilungen: Feed lesen → Deep Link → automatisch gelesen → Badge korrekt → zweites Gerät sieht den Lesestatus **nicht** live (dokumentiertes Verhalten), aber nach Reload → aal1-Sitzung zeigt „Zweiter Faktor erforderlich".
- Der Ende-zu-Ende-Pfad „A weist B eine Aufgabe zu → B bekommt eine Mitteilung" ist **blockiert (B11)** und wird mit `NOTIFICATION-EMITTER-01` nachgezogen.

---

## 18. Acceptance criteria

1. Jede angezeigte Mitteilung hat entweder ein aufrufbares Sprungziel oder einen sichtbar deaktivierten „Öffnen"-Knopf mit Begründung. **Keine Zeile zeigt eine Roh-ID oder einen ISO-8601-Zeitstempel.**
2. Gegeben eine ungelesene Mitteilung, wenn der Nutzer ihr Ziel öffnet, dann ist sie danach gelesen und der Badge um eins kleiner.
3. Gegeben eine fremde oder gelöschte Mitteilung, wenn „als gelesen" versucht wird, dann meldet die UI „nicht mehr verfügbar" und **nicht** „Kein Zugriff".
4. Gegeben ein leerer Ungelesen-Tab, dann zeigt die Seite „Alles gelesen" — nicht denselben Text wie ein leerer Gesamtposteingang.
5. Gegeben eine aal1-Sitzung, dann zeigt die Seite „Zweiter Faktor erforderlich" und nicht „Noch keine Mitteilungen".
6. Gegeben ein Fan-Out im Workspace, dann lädt die Inbox genau einmal entprellt nach; ein Reconnect führt zu genau einem Reload.
7. Doppeltes „Als gelesen markieren" führt zu keinem Fehler und keiner zweiten Zustandsänderung.
8. Die Ungelesen-Markierung ist ohne Farbwahrnehmung erkennbar.
9. Es existiert **kein** Weg, aus der UI eine Mitteilung zu erzeugen.
10. Die Inbox zeigt keinen Workspace-Aktivitätsstrom und keine Systemzustände.
11. **Der Badge zeigt oberhalb der Seitengröße „50+" und niemals eine erfundene Gesamtzahl**; es gibt keine Filterleiste und keinen „Alle als gelesen"-Knopf, solange die zugehörigen Pakete fehlen.

---

## 19. Out of scope

- Implementierung (Planungspaket).
- Erzeugen von Mitteilungen (`NOTIFICATION-EMITTER-01`).
- Benachrichtigungseinstellungen (F7).
- E-Mail-, Push- oder Desktop-Zustellung (F13) — kein Kanal-Contract; monday hat drei, NexImmo V1 hat einen (in-App).
- Mentions und Kommentar-Mitteilungen (F3).
- Fristbasierte Arten (`TASK-SCHEDULER-01`).
- Retention und Verfall (`NOTIFICATION-RETENTION-01`, F11).
- Sammel-Lesen (`NOTIFICATION-READ-02`), Feed-Filter (`NOTIFICATION-QUERY-01`), empfängergenaues Wake (`NOTIFICATION-REALTIME-01`).
- Admin-Sicht auf fremde Postfächer.
- Änderungen an Schema, RLS, RPCs, Permission-Katalog oder Seiten-Mapping — **`PERMISSION-CATALOG-02` wird nicht still hier gelöst.**

---

## 20. Closed decisions

Die sechs Entscheidungen sind in Shared §20 verbindlich geschlossen. Wirkung auf diesen Screen:

| Entscheidung | Wirkung hier |
|---|---|
| **OD-1 Retention** | **keine clientseitige Retention, kein clientseitig gerechnetes Relevanzende** (§6.6). Die Liste zeigt, was der Server liefert. Echte Policy = `NOTIFICATION-RETENTION-01` (F11), blockiert diese Fläche nicht |
| **OD-2 Implementation order** | Filterleiste, Zusatz-Tabs, Suche und „Alle als gelesen" entfallen (§4, §11); Zeitgruppierung bleibt, weil sie aus der Sortierung folgt und exakt ist; Vortäuschungs-Regressionstest §17 |
| **OD-3 Subtasks** | betrifft diesen Screen nicht |
| **OD-T1 Due-Filter/Sortierung** | wirkt indirekt: vier Deep-Link-Ziele hängen an der Objektauflösung aus `TASK-QUERY-01` (§9) |
| **OD-T5 `estimated_cost`** | betrifft diesen Screen nicht |
| **OD-N6 Event catalog** | §7 ist der geschlossene Katalog; **keine generische Notification-Erzeugung**, kein UI-Pfad, der Mitteilungen anlegt (§6.1). Neue Arten nur durch Contract-Erweiterung |

**Keine offenen Planungsentscheidungen mehr.**

---

## 21. Implementation handoff

### Umfang von `NOTIFICATION-INBOX-01` (Welle T-3)
1. Präsentationsschicht für die Inbox; Controller auf `NotificationPort` — **der Provider kommt aus A15 und existiert heute nicht.**
2. Liste mit Zeitgruppierung, zwei Tabs, `NxSplitView`-Detail, alle Zustände aus §10.
3. Kind-Katalog `notification_kind_labels.dart` (§7) und Deep-Link-Auflösung (§9) inklusive „Ziel nicht verfügbar".
4. Optimistisches Lesen mit `markNotificationRead` und stabiler `mutationId`.
5. Glocken-Indikator in der `CloudTopBar` (Badge „50+" bis eine Count-Quelle existiert).
6. Vortäuschungs-Regressionstest (§17).

### Muss vorher auf `main` sein
- `UX-FOUNDATION-IMPL-01` — **erledigt, `791849f`**.
- Inkrement **A15** aus `TASKS-NOTIFICATIONS-CORE-01` (Provider, Route `/notifications` und `/tasks/:id`, Fehlerklassifizierung).

### Nach diesem Paket, in dieser Reihenfolge
`PERMISSION-CATALOG-02` (damit Empfänger überhaupt `notification.read` haben) → `NOTIFICATION-EMITTER-01` (damit Mitteilungen entstehen) → `TASK-SCHEDULER-01` (Fristereignisse) → Komfortpakete `NOTIFICATION-READ-02`, `-QUERY-01`, `-REALTIME-01`.

### Invarianten, die nicht regredieren dürfen
- pgTAP 027 A6/B4/F1/F2 — die AAL2-Grenze der Notifications inklusive `mark_notification_read`.
- pgTAP 013 (57 Tests) — Fan-Out, empfängergebundenes Lesen, `not_found` statt `forbidden`.
- Policy-Inventur von exakt **41** Policies (`security_aal_mutation_matrix.sql` MUT-6b) — kein Screen-PR fasst Policies an.
- `test/ui/navigation/app_navigation_test.dart` — deterministische Readiness/Permission je `GlobalPage`; die konkrete Zuordnung `notifications → notification.read` ist dort **nicht** gepinnt (Shared §8.2), ein ergänzender Test gehört in A15.
- Actor-Guard im Adapter (`supabase_platform_repository_adapter.dart:723-728`).
- Kein Client erzeugt Mitteilungen.
