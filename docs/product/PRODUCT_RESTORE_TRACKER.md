# NexImmo Product Restore Tracker

Live-Status aller Rebuild-Pakete. Quelle der Wahrheit für Fortschritt (Master Plan §5: `PLAN → SPEC APPROVED → IMPLEMENT → PR → REVIEW → MERGE → STAGING → E2E → DONE`). Ein Paket ist erst DONE mit Staging-E2E. Grundlage: `PRODUCT_SCREEN_MAP.md` (Basis `9003392`, 2026-08-27).

Statuswerte: `todo` · `in_progress` · `spec_approved` · `implemented` · `merged` · `e2e_done` · `blocked(<worauf>)` · `n/a`.

## Wave 1 — Shared/Core

| Paket | Inhalt | Planung | Implementierung | Staging E2E |
|---|---|---|---|---|
| UX-FOUNDATION-IMPL-01 | Foundation §18: NxLiveUpdatesNotice, NxListSkeleton, splitViewMinWidth/NxSplitView, NxNotice, Retry-Sweep, Landing→properties | spec_approved | merged (2026-08-28, `791849f`, PR #43, Merge `3a11b09`) | todo |
| UI-HYGIENE-01 | 12 Orphans + toter Legacy-Shell-Ast entfernen (Liste: Screen Map §2 Orphans); Helper-Umzüge (propertyTypeOptions, operations_detail_support prüfen) | todo | todo | n/a (Test-/Analyze-Beweis) |
| REALTIME-DEGRADED-WIRING-01 | Degraded-Flag je Domäne (party, document, leasing, maintenance, valuation) bis in die Panels + NxLiveUpdatesNotice | todo | todo | todo |
| HELP-LINKS-01 | Help-Ziele nach cloudReadinessForPage filtern | n/a (trivial) | todo | n/a |
| SHELL-ROUTING-01 | URL ↔ Shell-State, Deep Links, Back/Forward und Section-State gemäß UX Foundation §2 | todo | todo | todo |

## Wave 2 — unabhängige Hauptmodule (parallel)

| Paket | Screens (Map-Referenz) | Disposition | Planung | Implementierung | Staging E2E |
|---|---|---|---|---|---|
| PROPERTY-WORKSPACE-01 | Host + Liste + Objekt + siebenstufige Maximal-IA; Childs nur bei Contract/Implementierung registrieren | KEEP+MERGE+REBUILD | spec_approved (`screens/PROPERTY_WORKSPACE_V2.md`; Readiness-Review 2026-08-28) | todo | todo |
| PROPERTY-OVERVIEW-DATA-01 (Backend-Gap) | Permission-gefilterte Property-KPI-/Attention-/Freshness-Projektionen; keine Client-Aggregate | — | blocked(material product/security contract decisions; Requirements in `screens/PROPERTY_OVERVIEW_V2.md`) | blocked(contract) | todo |
| PROPERTY-DATA-02 (Backend-Gap) | Create/Archive/Delete im portfolio_property-Contract (Voraussetzung für Wizard) | — | todo | todo | todo |
| PROPERTY-MEDIA-DATA-01 (Backend-Gap) | privates Property-Media-/Titelbild-Contract; Documents nicht zweckentfremden | — | blocked(product/contract/security decisions) | blocked(contract/security decision) | todo |
| PROPERTY-CREATE-01 | 12-Schritt-Wizard rehosten | REDESIGN | blocked(PROPERTY-DATA-02) | blocked | todo |
| VALUATION-REHOST-01 | Sicherer interner Analyse-Rehost; Parent für 01A–01C. Property-Host: `screens/PROPERTY_VALUATION_V2.md`; Specs: [Workflow](screens/valuation_v2_workflow.md), [Queue](screens/valuation_queue_v2.md), [Create](screens/valuation_create_v2.md), [Case](screens/valuation_case_workspace_v2.md) | MERGE | spec_approved (Property-Host 2026-08-28; Valuation V2 2026-09-01; `REHOST NOW`) | todo | todo |
| VALUATION-REHOST-01A | Queue öffnen und Case-/Create-Routen hosten; keine Value-Projektion | KEEP+REHOST | spec_approved (2026-09-01; `REHOST NOW`) | todo | todo |
| VALUATION-REHOST-01B | Create auf Cloud-Property-Read umstellen und neuen Case öffnen; nur interne Analyse | REHOST/FIX | spec_approved (2026-09-01; `REHOST NOW`) | todo | todo |
| VALUATION-REHOST-01C | Case Workspace mit Allowlist `overview/assumptions/cashflow/valuation/scenarios`; Factors/Provenance, Varianten, technische Ertrags-/Sachwertmodelle, aggregate unlevered DCF/KPIs; keine Source-/Baseline-Neuentwicklung oder Ergebnisaktionen | KEEP+REHOST | spec_approved (2026-09-01; `REHOST NOW`) | todo | todo |
| METHOD-GOV-01 | Verbindliche Kategorien, Ergebnisbegriffe, Reconciliation und Professional Gate für Valuation V2; [Decision](VALUATION_METHOD_GOVERNANCE.md) | — | spec_approved (2026-09-01; Contract-Umsetzung separat blockiert) | — | — |
| TASKS-NOTIFICATIONS-01 | Klammerpaket: Tasks + Property-Tasks (eine UI) + Notifications auf platform_audit_jobs. Vorlagen (Tab, Katalog, Generierung) sind **nicht** Teil von V1, sondern vollständig `TASK-SCHEDULER-01` (DEBT-009). Aufgeteilt in die drei Unterpakete darunter; **nicht pauschal freigegeben** — Teilumfänge sind blockiert, siehe `screens/tasks_notifications_shared.md` §0.2 | REBUILD/MERGE | teil-approved (2026-08-28; 6 Entscheidungen geschlossen; Property-Task-Teil zusätzlich spec_approved in `screens/PROPERTY_OPERATIONS_V2.md`) | todo | blocked(PERMISSION-CATALOG-02) |
| ├ TASKS-NOTIFICATIONS-CORE-01 | Inkrement A15: Provider `NotificationPort`/`PlatformQueryInvalidationSource`, Routen `/tasks`, `/tasks/:id`, `/notifications`, Fehlerklassifizierung `forbidden` vs. `infrastructureFailure`, stabile `mutationId` (+ Nachziehen `operations_alerts_controller`), Mapping-Test `cloudReadPermissionForPage` → Spec `screens/tasks_notifications_shared.md` | — | spec_approved (2026-08-28) | todo | n/a (Testbeweis) |
| ├ TASK-CENTER-01 | Eine Task-UI (Workspace + Objektkontext), Liste, Board (4 status-gebundene Keysets), CRUD/Status/„mir zuweisen", Bulk → Spec `screens/task_center.md`. **Ohne** Systemsichten/Termine/Suche/Zähler **und ohne Vorlagen-Tab** (alles blocked) | REBUILD/MERGE | spec_approved (2026-08-28, inkrementweise) | blocked(TASKS-NOTIFICATIONS-CORE-01) | blocked(PERMISSION-CATALOG-02) |
| └ NOTIFICATION-INBOX-01 | Adressierte Inbox, echte Deep Links, Read-Semantik, Glocken-Badge → Spec `screens/notification_inbox.md`. **Emitter sind blockiert** — die Fläche bleibt ohne `NOTIFICATION-EMITTER-01` leer | REBUILD | spec_approved (2026-08-28, inkrementweise) | blocked(TASKS-NOTIFICATIONS-CORE-01) | blocked(NOTIFICATION-EMITTER-01, PERMISSION-CATALOG-02) |
| MAINTENANCE-PARITY-01 | DTO-/RPC-Parität für Ticket/CapEx Create/Read/Update/Transition; Currency aus Daten; kein Delete/Document-Link/Notification im ersten Inkrement | KEEP+MERGE | spec_approved (`screens/PROPERTY_OPERATIONS_V2.md`, 2026-08-28) | todo | todo |
| DOCUMENTS-COMPLETE-01 | Property-Register/Requirements rehosten; Registry-Flächen workspace-weit separat; Media-Gap bleibt | KEEP+MERGE+REBUILD | Property-Teil spec_approved (`screens/PROPERTY_DOCUMENTS_V2.md`); Registry-Teil todo | todo | todo |
| ADMIN-AREA-01 | Admin-Workspace um ReferenceMembersScreen; UsersScreen-Harvest+REMOVE; Umzug aus reference_slice/ | KEEP+REMOVE | spec_approved (2026-08-28, `docs/product/screens/admin_members.md`; inkl. Foundation-AMD-001 „Mitglieder"; Paket B Invite-Accept → Core/Auth/Gate) | A1 implemented (2026-08-28, PR #44 `feature/admin-members-v2-a1`; A2 Aktivität + Paket B offen) | todo |

### Backend-Gaps aus TASKS-NOTIFICATIONS-01 (eigene Pakete, Master Plan §8)

Jeder Eintrag ist gegen Code/Migrationen belegt; Definitionen und Belege in `screens/tasks_notifications_shared.md` §14. Diese Pakete werden **nicht** in Screen-PRs gelöst.

| Paket | Inhalt | Blockiert | Planung | Implementierung |
|---|---|---|---|---|
| **TASK-QUERY-01** | serverseitige Due-/Status-/Sortier-Semantik für My Work: `due_at`-Range/Filter, mehrere Statuswerte bzw. passende serverseitige Semantik, `assigned_to`, Entity-Scope (denormalisierte `property_id`), definierte Sortierung nach Fälligkeit; dazu Titelsuche, Zähl-RPC, `search_index`-Befüllung für Tasks | Systemsichten, Termine-Ansicht, Suche, Zähler, Objekt-Rollup, Namensauflösung (auch 4 Deep-Link-Ziele der Inbox) | todo | todo |
| **TASK-ENTITY-REGISTRY-01** | `document` und `valuation_case` als erlaubte Entity-Targets in `public.document_link_entity_type`; `task` als Link-Ziel für `link_document`; Parity-Test nachziehen | Task ↔ Document, Task ↔ Valuation Case | todo | todo |
| **TASK-SCHEDULER-01 (DEBT-009)** | Vorlagen-Aggregat (Read- **und** Write-Contract) + Vorlagen-Tab als UI-Fläche + manuelles Instanziieren + serverseitiger Scheduler: recurring tasks, deadline events, scheduled notifications. Heute existiert weder ein Template-Contract noch `supabase/functions`/`pg_cron`/`pg_net`. **Muss die zehn Standardvorlagen aus `screens/tasks_notifications_shared.md` §7.6 übernehmen, bevor `UI-HYGIENE-02` den Legacy-Screen löscht.** | Vorlagenkatalog, Vorlagen-Tab, „Jetzt erzeugen", wiederkehrende Aufgaben, Frist-/Sammelereignisse | todo | todo |
| **PERMISSION-CATALOG-02** | Client-/Server-Permission-Vokabular zusammenführen (`rbac.dart` kennt `task.manage`/`notification.*` nicht; Server kennt `task.create/assign/resolve` nicht) **und** Rollen jenseits `admin` seeden | Nicht-Admin-Staging-E2E; Empfängerrechte `notification.read`; mittelbar die Notification-Emitter | todo | todo |
| **NOTIFICATION-EMITTER-01** | serverseitiger Fan-Out in `create_task`/`transition_task_status` inkl. Empfängerableitung, Self-Notify-Filter und Dedupe-Fenster. Grund: `create_notification` verlangt `notification.manage` **beim Auslöser** — ein Client-Emitter wäre entweder zu mächtig oder am falschen Ort | alle V1-Ereignisse; ohne dieses Paket bleibt die Inbox leer | todo | todo |
| TASK-ASSIGNEE-DIRECTORY-01 | für `task.manage`-Inhaber lesbares Mitgliederverzeichnis; heute nur `list_workspace_members` unter `security.manage` | Zuweisung an andere Personen | todo | todo |
| NOTIFICATION-READ-02 | Sammel-Lesen („Alle als gelesen markieren") | Aufräumen eines vollen Posteingangs | todo | todo |
| NOTIFICATION-QUERY-01 | Feed-Filter nach `kind`, `entity`, Zeitraum, Suche | Inbox-Filterleiste | todo | todo |
| NOTIFICATION-REALTIME-01 | empfängergenaues Wake (`notification.fanned_out` trägt weder `aggregate_id` noch Empfänger; ohne `notification.read` gar kein Signal) | Live-Frische der Inbox | todo | todo |
| NOTIFICATION-RETENTION-01 | `expires_at`, Dedupe-Fenster, Retention-Job — Backend/Governance. Nach Entscheidung OD-1 **kein Blocker** für Task Center und Inbox | Verfall als Produktverhalten | todo | todo |
| UI-HYGIENE-02 | Löschung der Legacy-Task-/Notification-Dateien (`tasks_screen`, `task_templates_screen`, `property_tasks_screen`, `tasks_repo`, `notifications_screen`, `notifications_repo`, `task_generation_service`, `startup_task_service`) **nach** nachgewiesenem Harvest; Entfernen des Enum-Werts `GlobalPage.taskTemplates` | — | todo | blocked(TASK-CENTER-01, TASK-SCHEDULER-01) |

Bereits geführte Pakete, die diese Flächen zusätzlich berühren: `SHELL-ROUTING-01` (die drei Minimalrouten reiten auf `TASKS-NOTIFICATIONS-CORE-01`), `SETTINGS-01` (Preferences für gespeicherte Sichten und Benachrichtigungseinstellungen), `MAINTENANCE-PARITY-01` (Ticket-Zuweisungsereignis).

## Wave 3 — abhängige Module

| Paket | Inhalt / Abhängigkeit | Planung | Implementierung | Staging E2E |
|---|---|---|---|---|
| IMPORTS-01 (Wizard-UX erhalten, Ausführung serverseitig) | platform_audit_jobs-Adoption (W2), Import-Pipeline-Backend | blocked(backend) | — | — |
| AUDIT-01 (Workspace- + Objekt-Audit auf sicherem App-Read-Port) | allowlisted DTO, Redaction, Property-Keyset, RLS-/Retention-Proof | blocked(contract/security decisions; `screens/PROPERTY_AUDIT_V2.md`) | blocked(app read port) | todo |
| PROPERTY-ACTIVITY-HOST-01 | Top-Level `Aktivität` mit getrennten Childs Aktivität/Audit/Berichte; Voraussetzung: mindestens ein implementierter Child | blocked(no implemented child; `screens/PROPERTY_ACTIVITY_REPORTS_V2.md`) | blocked | todo |
| PROPERTY-ACTIVITY-01 (verständliche Objekt-Timeline) | permission-gefiltertes Activity-Read-Model; Audit-/Domain-Sichtbarkeit entscheiden | blocked(activity/security contract; `screens/PROPERTY_ACTIVITY_V2.md`) | blocked(contract) | todo |
| SCENARIO-VALUATION-01 (Inputs/Analysis/Scenarios/Versions/Offer) | Scenario-Lifecycle-Contract (Welle-5-Modell), VALUATION-REHOST-01; Zielbild/Gaps in [Valuation V2 Workflow](screens/valuation_v2_workflow.md) | blocked(contract; 2026-08-28 Zielbild spezifiziert) | blocked(contract/engine) | — |
| VALUATION-METHOD-CONTRACT-01 | `METHOD-GOV-01`; Value Basis, Ergebnisfamilien, Eligibility, getrennte Reconciliation und Approval Classes technisch umsetzen | todo (Scope beschlossen) | blocked(contract/backend/engine) | — |
| VALUATION-VALIDATION-01 | `METHOD-GOV-01`; semantische Domain-/Server-Validation, NOI-Semantik und Terminalbedingungen | todo (Scope beschlossen) | blocked(contract/engine) | — |
| VALUATION-MARKET-METHODS-01 | `METHOD-GOV-01`; fachliche Modellkonformität Ertrags-/Sachwert, boG, Referenzdaten und Verfahrensvarianten | todo (Scope beschlossen) | blocked(data/engine) | — |
| VALUATION-COMPS-01 | P2-D07; Cloud-Comparables, Auswahl, Datenqualität und Vergleichswertmodell | todo (Scope beschlossen) | blocked(data/contract/engine) | — |
| VALUATION-LEASE-CF-01 | `METHOD-GOV-01`; Lease-by-Lease Cashflow und Market Leasing Assumptions | todo (FUTURE) | blocked(contract/engine) | — |
| VALUATION-CAPEX-CF-01 | `METHOD-GOV-01`; CapEx-Auswahl, Periodisierung und DCF-Kopplung | todo (FUTURE) | blocked(contract/engine) | — |
| VALUATION-DEBT-01 | P2-D08; Debt Contract/Engine, Schedules und levered Ergebnisfamilie | todo (FUTURE) | blocked(contract/engine) | — |
| VALUATION-VERSION-01 | `SCENARIO-VALUATION-01`; immutable Case-Versionen, Calculation Runs, Vergleich und Revision | todo | blocked(contract/backend) | — |
| VALUATION-AUDIT-READ-01 | `AUDIT-01`; case-gefilterter, redigierter Valuation-Audit-Leseweg | todo | blocked(contract/backend) | — |
| VALUATION-REPORT-EXPORT-01 | `VALUATION-METHOD-CONTRACT-01`, `VALUATION-VERSION-01`; klassifizierte, versionierte Report-Artefakte und Export | todo | blocked(contract/backend) | — |
| VALUATION-SOURCE-01 | `VALUATION-VERSION-01`; SourceRef/Snapshot, Stichtag und bewusster Source-Import/Refresh | todo (DRAFT Scope) | blocked(contract/backend) | — |
| VALUATION-LIST-01 | `VALUATION-METHOD-CONTRACT-01`; optionale Queue-Projektion für Property-Label/Stale/Approval Class ohne N+1; kein Wert vor Method Contract | todo (optional) | blocked(contract/backend) | — |
| VALUATION-LIST-SEARCH-01 | `VALUATION-LIST-01`; serverweite Queue-Suche mit stabiler Cursor-Semantik | todo (optional) | blocked(contract/backend) | — |
| VALUATION-REALTIME-01 | `REALTIME-DEGRADED-WIRING-01`; vollständige Invalidierung für Cases, Factors, Reports und Varianten | todo | blocked(backend/events) | — |
| VALUATION-TEMPLATE-VERSION-01 | `VALUATION-VERSION-01`; Template-Key/-Version für reproduzierbare Cases und Audit | todo | blocked(contract/backend) | — |
| VALUATION-CURRENCY-01 | `VALUATION-METHOD-CONTRACT-01`; Case-Währung und freigegebene FX-Policy | todo (FUTURE) | blocked(contract/data) | — |
| VALUATION-ACTUALS-01 | P2-D08; periodisierte Objekt-Ist-/Plan-Daten als Valuation-Quelle | todo (FUTURE) | blocked(data/contract) | — |
| VALUATION-OPEX-01 | `VALUATION-ACTUALS-01`; kategorisierte Operating-Plan-/Ist-Daten und Umlagefähigkeit | todo (FUTURE) | blocked(data/contract) | — |
| PROPERTY-LOOKUP-01 | `PROPERTY-DATA-02`; serverweite Property-Suche für Entity Picker, paginierte Auswahl reicht für Valuation-Rehost | todo (optional) | blocked(contract/backend) | — |
| FINANCE-01 (Ledger, Budgets, BvA-Aufteilung, Covenants, Asset Workbook) | P2-D08 finance_debt | blocked(P2-D08) | — | — |
| PORTFOLIO-REPORTING-01 (Portfolios, Detail+Analytics+Quality, ESG, Report Templates, Dashboard) | P2-D09 reporting_analytics | blocked(P2-D09) | — | — |
| COMPS-CRITERIA-01 (Comps, Criteria Check, Criteria Sets, Compare) | P2-D07-Rest | blocked(P2-D07) | — | — |
| SETTINGS-01 (Workspace-Settings vs. User-Preferences) | Settings-/Preferences-Contract (unbeplant) | blocked(decision) | — | — |
| SALE-HOTEL-01 (10 Detail-Pages) | Produktentscheidung + neue Domain oder REMOVE | blocked(product decision) | — | — |

## PROPERTY-WORKSPACE-V2 — Spec Readiness (Review 2026-08-28)

Die 15 Dateien sind Implementierungsgrenzen. Sie erzeugen keine 15 gleichrangigen Ziele. Die verbindliche Maximal-IA bleibt `Übersicht / Objekt / Vermietung / Betrieb / Dokumente / Investment / Aktivität`; Investment und Aktivität hosten ihre Child-Screens, nicht implementierte Childs bleiben verborgen.

| Spec | IA-Ebene | Status | Blocker / abgegrenzte Voraussetzung |
|---|---|---|---|
| `PROPERTY_WORKSPACE_V2.md` | Workspace Host | APPROVED | keine; UX-Foundation gelandet |
| `PROPERTY_LIST_V2.md` | Einstieg vor Workspace | APPROVED | Workspace Host-State |
| `PROPERTY_OVERVIEW_V2.md` | Übersicht | BLOCKED | `PROPERTY-OVERVIEW-DATA-01` |
| `PROPERTY_ASSET_V2.md` | Objekt | APPROVED | Workspace Host |
| `PROPERTY_LEASING_V2.md` | Vermietung Host | APPROVED | Workspace Host + Degraded-Wiring |
| `PROPERTY_OPERATIONS_V2.md` | Betrieb Host | APPROVED | Workspace Host + MAINTENANCE-/TASKS-UI-Pakete |
| `PROPERTY_DOCUMENTS_V2.md` | Dokumente | APPROVED | Workspace Host; Media ausdrücklich nicht enthalten |
| `PROPERTY_INVESTMENT_V2.md` | Investment Host | APPROVED | Workspace Host + erster Child Valuation |
| `PROPERTY_VALUATION_V2.md` | Investment → Bewertung | APPROVED | `VALUATION-REHOST-01` |
| `PROPERTY_SCENARIOS_V2.md` | Investment → Szenarien | BLOCKED | Scenario-Lifecycle-/Versions-/Calculation-Contract |
| `PROPERTY_PERFORMANCE_V2.md` | Investment → Performance | BLOCKED | `P2-D08` / `FINANCE-01` |
| `PROPERTY_ACTIVITY_REPORTS_V2.md` | Aktivität Host | BLOCKED | mindestens ein implementierter Child |
| `PROPERTY_ACTIVITY_V2.md` | Aktivität → Aktivität | BLOCKED | Activity-Read-/Security-Contract |
| `PROPERTY_AUDIT_V2.md` | Aktivität → Audit | BLOCKED | `AUDIT-01` App-Read-Port/Redaction |
| `PROPERTY_REPORTS_V2.md` | Aktivität → Berichte | BLOCKED | `P2-D09` / `PORTFOLIO-REPORTING-01` |

**DRAFT:** keine. Noch offene Materialentscheidungen liegen ausschließlich in den als BLOCKED markierten Contract-Paketen; sie dürfen nicht durch UI-Annahmen geschlossen werden.

## Bereits erledigt (vor diesem Tracker)

| Fläche | Status |
|---|---|
| Wellen 1–5 Cloud-Panels (16 Flächen, Screen Map §1) | merged; Staging-E2E nur teilweise (Property-Realtime remote bewiesen; W3/W4-Golden-Paths teils offen; Schwester-Domänen-E2E blocked auf Fixtures/RBAC) |
| UX Foundation (`PRODUCT_UX_FOUNDATION.md`) | merged `9003392` |
| Screen Map + dieser Tracker | dieses Paket |

## Führungsregeln

- Jede Statusänderung wird mit Datum + Commit/PR in der Zelle oder einer Fußnote vermerkt.
- Neue Pakete entstehen nur mit Eintrag hier; Screen-Specs entstehen unter `docs/product/screens/<slug>.md` und verlinken ihr Paket.
- Backend-Gaps wandern nie stillschweigend in Screen-PRs (Master Plan §8).
