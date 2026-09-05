# NexImmo Product Restore Tracker

Live-Status aller Rebuild-Pakete. Quelle der Wahrheit für Fortschritt (Master Plan §5: `PLAN → SPEC APPROVED → IMPLEMENT → PR → REVIEW → MERGE → STAGING → E2E → DONE`). Ein Paket ist erst DONE mit Staging-E2E. Grundlage: `PRODUCT_SCREEN_MAP.md` (Basis `9003392`, 2026-08-27).

Statuswerte: `todo` · `in_progress` · `spec_approved` · `committed` · `implemented` · `merged` · `e2e_done` · `blocked(<worauf>)` · `n/a`.

**FULL-V2-SCOPE-01 (Product-Owner-Entscheidung, 2026-09-04):** Eine Produktfähigkeit wird nicht mehr wegen Aufwand, fehlendem Backend oder fehlendem Query-Contract aus dem V2-Zielbild genommen. Solche Fähigkeiten stehen auf `committed` und führen ihre technische Voraussetzung offen mit (`prerequisite-first`): `missing capability → prerequisite package → dependent feature → staging E2E → DONE`. `committed` heißt ausdrücklich **nicht**, dass das Backend existiert — es heißt, dass wir es bauen. Deshalb wird je Eintrag der Produkt-Scope von der technischen Bereitschaft getrennt geführt (`READY` vs. `PREREQUISITE REQUIRED: <Paket>`). `blocked(...)` bleibt nur für echte externe Sperren, `REJECTED` nur für bewusste Nicht-Ziele (fremdes Trade Dress, Fake-KPIs, Client-Synthese fehlender Serverdaten, Security-/AAL-/RLS-Bypass). Dieser Normalisierungsstand ist bisher für den **Property-Bereich** vollzogen; die übrigen Domänen folgen in ihren eigenen Normalisierungs-PRs.

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
| PROPERTY-WORKSPACE-01 | Host + Liste + Objekt + siebenstufige Maximal-IA; Childs nur bei Contract/Implementierung registrieren | KEEP+MERGE+REBUILD | spec_approved (`screens/PROPERTY_WORKSPACE_V2.md`; Readiness-Review 2026-08-28) | implemented (Stand 2026-09-06): Host, Liste, Objekt (A1, PR #52), `Betrieb` (TASK-CENTER-01), `Dokumente` (DOCUMENTS-COMPLETE-01), `Vermietung` (PR #64), Objekt-Lifecycle (PR #63), Objektwechsler und `Übersicht` (PROPERTY-OVERVIEW-DATA-01) als Standardziel. Offen: `Investment` (VALUATION-REHOST-01), `Aktivität` (erster Child) | todo |
| PROPERTY-OVERVIEW-DATA-01 (Prerequisite) | Permission-gefilterte Property-KPI-/Attention-/Freshness-Projektionen serverseitig; keine Client-Aggregate | — | committed (Scope beschlossen FULL-V2-SCOPE-01; Requirements in `screens/PROPERTY_OVERVIEW_V2.md`) | implemented (2026-09-06, `feature/property-overview-data-01`): `property_overview`-RPC, je Sektion permission-gescoped (`lease/maintenance/capex/task/document/valuation.read`), serverseitig geordnete Attention-Liste, `as_of`; pgTAP 032 (40) und Rollback 038. Nur gezählte Fakten — Finanzkennzahlen (`P2-D08`) und Activity (`AUDIT-01`) bleiben abwesend statt geschätzt | todo |
| PROPERTY-DATA-02 (Prerequisite) | Property-Lifecycle im portfolio_property-Contract: Anlegen, Archivieren, Wiederherstellen. `create_property`-RPC mit AAL2-Gate, `property.create` im Katalog (admin/manager), Idempotenz über `mutation_receipts`, Append-only-Audit; Archivieren/Wiederherstellen über den bestehenden auditierten `update_property`-Tombstone (DEBT-012) als benannte, bestätigte Aktion. Kein Hard-Delete | — | committed (Scope beschlossen FULL-V2-SCOPE-01) | implemented (2026-09-05, `feature/property-data-02-lifecycle`; Migration + Contract + Adapter + Anlegen-Dialog + Archivieren/Wiederherstellen; pgTAP 031 und Rollback 037) | todo |
| PROPERTY-MEDIA-DATA-01 (Prerequisite) | privates Property-Media-/Titelbild-Contract (Storage-Bucket, Version, Lifecycle, signierte Auslieferung); Documents nicht zweckentfremden | — | committed (Scope beschlossen FULL-V2-SCOPE-01; Security-/Storage-Contract ist Inhalt des Pakets) | committed — prerequisite-first (Technical readiness: PREREQUISITE REQUIRED — Media-Contract + Storage-Policy; kein Security-Downgrade, keine öffentlichen Signed URLs) | todo |
| PROPERTY-CREATE-01 | Objekt anlegen (Wizard-UX aus dem Legacy-12-Schritt-Flow geerntet, auf den Cloud-Contract reduziert) | REDESIGN | committed (Scope beschlossen FULL-V2-SCOPE-01) | implemented (2026-09-05, erstes Inkrement: Anlegen-Dialog auf genau den Contractfeldern, Objekt entsteht als Entwurf; `PROPERTY-DATA-02` gelandet). Weitere Wizard-Schritte folgen mit ihren eigenen Contracts | todo |
| VALUATION-REHOST-01 | Sicherer interner Analyse-Rehost; Parent für 01A–01C. Property-Host: `screens/PROPERTY_VALUATION_V2.md`; Specs: [Workflow](screens/valuation_v2_workflow.md), [Queue](screens/valuation_queue_v2.md), [Create](screens/valuation_create_v2.md), [Case](screens/valuation_case_workspace_v2.md) | MERGE | spec_approved (Property-Host 2026-08-28; Valuation V2 2026-09-01; `REHOST NOW`) | todo | todo |
| VALUATION-REHOST-01A | Queue öffnen und Case-/Create-Routen hosten; keine Value-Projektion | KEEP+REHOST | spec_approved (2026-09-01; `REHOST NOW`) | todo | todo |
| VALUATION-REHOST-01B | Create auf Cloud-Property-Read umstellen und neuen Case öffnen; nur interne Analyse | REHOST/FIX | spec_approved (2026-09-01; `REHOST NOW`) | todo | todo |
| VALUATION-REHOST-01C | Case Workspace mit Allowlist `overview/assumptions/cashflow/valuation/scenarios`; Factors/Provenance, Varianten, technische Ertrags-/Sachwertmodelle, aggregate unlevered DCF/KPIs; keine Source-/Baseline-Neuentwicklung oder Ergebnisaktionen | KEEP+REHOST | spec_approved (2026-09-01; `REHOST NOW`) | todo | todo |
| METHOD-GOV-01 | Verbindliche Kategorien, Ergebnisbegriffe, Reconciliation und Professional Gate für Valuation V2; [Decision](VALUATION_METHOD_GOVERNANCE.md) | — | spec_approved (2026-09-01; Contract-Umsetzung separat blockiert) | — | — |
| TASKS-NOTIFICATIONS-01 | Klammerpaket: Tasks + Property-Tasks (eine UI) + Notifications auf platform_audit_jobs. Vorlagen (Tab, Katalog, Generierung) sind **nicht** Teil von V1, sondern vollständig `TASK-SCHEDULER-01` (DEBT-009). Aufgeteilt in die drei Unterpakete darunter; **nicht pauschal freigegeben** — Teilumfänge sind blockiert, siehe `screens/tasks_notifications_shared.md` §0.2 | REBUILD/MERGE | teil-approved (2026-08-28; 6 Entscheidungen geschlossen; Property-Task-Teil zusätzlich spec_approved in `screens/PROPERTY_OPERATIONS_V2.md`) | todo | blocked(PERMISSION-CATALOG-02) |
| ├ TASKS-NOTIFICATIONS-CORE-01 | Inkrement A15: Provider `NotificationPort`/`PlatformQueryInvalidationSource`, Routen `/tasks`, `/tasks/:id`, `/notifications`, Fehlerklassifizierung `forbidden` vs. `infrastructureFailure`, stabile `mutationId` (+ Nachziehen `operations_alerts_controller`), Mapping-Test `cloudReadPermissionForPage` → Spec `screens/tasks_notifications_shared.md` | — | spec_approved (2026-08-28) | merged (2026-09-03, `2afc439`, PR #53) | n/a (Testbeweis) |
| ├ TASK-CENTER-01 | Eine Task-UI (Workspace + Objektkontext), Liste, Board (4 status-gebundene Keysets), CRUD/Status/„mir zuweisen", Bulk → Spec `screens/task_center.md`. **Ohne** Systemsichten/Termine/Suche/Zähler **und ohne Vorlagen-Tab** (alles blocked) | REBUILD/MERGE | spec_approved (2026-08-28, inkrementweise) | merged (2026-09-03, PR #54, Merge `3ebce78`; Readiness `tasks` → ready) | blocked(PERMISSION-CATALOG-02) |
| └ NOTIFICATION-INBOX-01 | Adressierte Inbox, echte Deep Links, Read-Semantik, Glocken-Badge → Spec `screens/notification_inbox.md`. **Emitter sind blockiert** — die Fläche bleibt ohne `NOTIFICATION-EMITTER-01` leer | REBUILD | spec_approved (2026-08-28, inkrementweise) | merged (2026-09-03, PR #55, Merge `62fa788`; Readiness `notifications` → ready) | blocked(NOTIFICATION-EMITTER-01, PERMISSION-CATALOG-02) |
| MAINTENANCE-PARITY-01 | DTO-/RPC-Parität für Ticket/CapEx Create/Read/Update/Transition; Currency aus Daten; kein Delete/Document-Link/Notification im ersten Inkrement | KEEP+MERGE | spec_approved (`screens/PROPERTY_OPERATIONS_V2.md`, 2026-08-28) | todo | todo |
| DOCUMENTS-COMPLETE-01 | Property-Register/Requirements rehosten; Registry-Flächen workspace-weit separat; Media-Gap bleibt | KEEP+MERGE+REBUILD | Property-Teil spec_approved (`screens/PROPERTY_DOCUMENTS_V2.md`); Workspace-/Registry-Teil spec_approved (2026-09-02, `screens/documents.md`: A Host+Register, B1 Registry, C Compliance; B2 Katalog-Entscheidung sowie Query/Realtime/Reminders blocked) | implemented (2026-09-04, PR #61 `feature/documents-v2-a1`: A V2-Host + Register, B1 Registry, C Compliance, Signed-URL-Open-Flow, Legacy-Host/Provider/Palette-Abriss; Property-Dokumente als Domäne im Property-Workspace-Host; B2/Query/Realtime/Reminders/Access-Audit/Media weiterhin blocked) | todo |
| ADMIN-AREA-01 | Admin-Workspace um ReferenceMembersScreen; UsersScreen-Harvest+REMOVE; Umzug aus reference_slice/ | KEEP+REMOVE | spec_approved (2026-08-28, `docs/product/screens/admin_members.md`; inkl. Foundation-AMD-001 „Mitglieder"; Paket B Invite-Accept → Core/Auth/Gate) | A1 implemented (2026-08-28, PR #44 `feature/admin-members-v2-a1`; A2 Aktivität + Paket B offen) | todo |

### Backend-Gaps aus TASKS-NOTIFICATIONS-01 (eigene Pakete, Master Plan §8)

Jeder Eintrag ist gegen Code/Migrationen belegt; Definitionen und Belege in `screens/tasks_notifications_shared.md` §14. Diese Pakete werden **nicht** in Screen-PRs gelöst.

| Paket | Inhalt | Blockiert | Planung | Implementierung |
|---|---|---|---|---|
| **TASK-QUERY-01** | serverseitige Due-/Status-/Sortier-Semantik für My Work: `due_at`-Range/Filter, mehrere Statuswerte bzw. passende serverseitige Semantik, `assigned_to`, Entity-Scope (denormalisierte `property_id`), definierte Sortierung nach Fälligkeit; dazu Titelsuche, Zähl-RPC, `search_index`-Befüllung für Tasks | Systemsichten, Termine-Ansicht, Suche, Zähler, Objekt-Rollup, Namensauflösung (auch 4 Deep-Link-Ziele der Inbox) | direkt umgesetzt (Klammerpaket-Beschreibung, 2026-09-03) | implemented (2026-09-03, `feature/task-query-01`): `tasks.property_id` (Trigger + Backfill, protected), `count_tasks` (Definer #66, `task.read`-Gate), Due-Range halboffen, Multi-Status, `unassigned`, Titel-`ilike` (escaped), Due-Sort (ASC-Keyset, nur terminierte), `search_index`-Projektion + Backfill für property/unit/lease/party/ticket/capex (Namensauflösung; Tasks selbst nicht indizierbar — Registry ohne `task`-Wert, siehe TASK-ENTITY-REGISTRY-01); Contract `TaskListQuery`/`TaskCountQuery`/`SearchIndexQuery.entities` |
| **TASK-ENTITY-REGISTRY-01** | `document` und `valuation_case` als erlaubte Entity-Targets in `public.document_link_entity_type`; `task` als Link-Ziel für `link_document`; Parity-Test nachziehen | Task ↔ Document, Task ↔ Valuation Case | todo | todo |
| **TASK-SCHEDULER-01 (DEBT-009)** | Vorlagen-Aggregat (Read- **und** Write-Contract) + Vorlagen-Tab als UI-Fläche + manuelles Instanziieren + serverseitiger Scheduler: recurring tasks, deadline events, scheduled notifications. Heute existiert weder ein Template-Contract noch `supabase/functions`/`pg_cron`/`pg_net`. **Muss die zehn Standardvorlagen aus `screens/tasks_notifications_shared.md` §7.6 übernehmen, bevor `UI-HYGIENE-02` den Legacy-Screen löscht.** | Vorlagenkatalog, Vorlagen-Tab, „Jetzt erzeugen", wiederkehrende Aufgaben, Frist-/Sammelereignisse | todo | todo |
| **PERMISSION-CATALOG-02** | Client-/Server-Permission-Vokabular zusammenführen (`rbac.dart` kennt `task.manage`/`notification.*` nicht; Server kennt `task.create/assign/resolve` nicht) **und** Rollen jenseits `admin` seeden | Nicht-Admin-Staging-E2E (nach Merge + Staging-Rollout + echtem E2E) | direkt umgesetzt (2026-09-04) | implemented (2026-09-04, `feature/permission-catalog-02`): kanonischer 29-Key-Katalog (`Permission.serverCatalog` ⇄ pgTAP 030, Server autoritativ; Fake-Trio `task.create/assign/resolve` entfernt → `task.manage`); Seeder `private.ensure_permission_catalog` + `private.seed_workspace_role_catalog` (idempotent, Migration seedet bestehende Workspaces — lokal leer = No-op; bewusst kein Trigger wegen pgTAP-Fixture-Kollisionen); Fünf-Rollen-Bündel least-privilege (admin voll; manager/analyst/operations mit task.manage+search.read; viewer read-only); **Befund korrigiert:** eigener Feed braucht kein Recht (recipient-scoped Policy) → Inbox/Nav-Gate entfernt, `notification.read` bleibt Admin-Oversight — nicht an Empfänger geseedet |
| **NOTIFICATION-EMITTER-01** | serverseitiger Fan-Out in `create_task`/`transition_task_status` inkl. Empfängerableitung, Self-Notify-Filter und Dedupe-Fenster. Grund: `create_notification` verlangt `notification.manage` **beim Auslöser** — ein Client-Emitter wäre entweder zu mächtig oder am falschen Ort | alle V1-Ereignisse; ohne dieses Paket bleibt die Inbox leer | direkt umgesetzt (Klammerpaket + §6.3-Katalog, 2026-09-03) | implemented (2026-09-03, `feature/notification-emitter-01`, gestackt auf TASK-QUERY-01): AFTER-Trigger auf `tasks` statt RPC-Body-Kopien (Replays re-emittieren strukturell nicht; `update_task` trägt `assigned_to`, also feuern E-T1/E-T2 auch dort — bewusste Präzisierung des Wortlauts); Korrelation via txn-lokalem GUC aus `platform_command_gate`; AS-1 strukturell, AS-3 als Unread-Dedupe je (recipient, kind, task) — besitz- statt zeitbasiert, Zeitfenster bleibt NOTIFICATION-RETENTION-01; Audit je Emission (`notification.emitted`, `mutation_id` null wegen Unique-Slot); `notification.fanned_out`-Invalidation; Registry-Wert `task` (nur der Wert; Guard `tasks_entity_not_task_check`, Rest bleibt TASK-ENTITY-REGISTRY-01) |
| TASK-ASSIGNEE-DIRECTORY-01 | für `task.manage`-Inhaber lesbares Mitgliederverzeichnis; heute nur `list_workspace_members` unter `security.manage` | Zuweisung an andere Personen | todo | todo |
| NOTIFICATION-READ-02 | Sammel-Lesen („Alle als gelesen markieren") | Aufräumen eines vollen Posteingangs | todo | todo |
| NOTIFICATION-QUERY-01 | Feed-Filter nach `kind`, `entity`, Zeitraum, Suche | Inbox-Filterleiste | todo | todo |
| NOTIFICATION-REALTIME-01 | empfängergenaues Wake (`notification.fanned_out` trägt weder `aggregate_id` noch Empfänger; ohne `notification.read` gar kein Signal) | Live-Frische der Inbox | todo | todo |
| NOTIFICATION-RETENTION-01 | `expires_at`, Dedupe-Fenster, Retention-Job — Backend/Governance. Nach Entscheidung OD-1 **kein Blocker** für Task Center und Inbox | Verfall als Produktverhalten | todo | todo |
| UI-HYGIENE-02 | Löschung der Legacy-Task-/Notification-Dateien (`tasks_screen`, `task_templates_screen`, `property_tasks_screen`, `tasks_repo`, `notifications_screen`, `notifications_repo`, `task_generation_service`, `startup_task_service`) **nach** nachgewiesenem Harvest; Entfernen des Enum-Werts `GlobalPage.taskTemplates` | — | todo | blocked(TASK-CENTER-01, TASK-SCHEDULER-01) |

### Infrastruktur (Deploy-Pfad)

| Paket | Inhalt | Blockiert | Planung | Implementierung |
|---|---|---|---|---|
| **STAGING-DB-MIGRATION-DEPLOY-01** | manueller, fail-closed `workflow_dispatch` „Supabase Staging Migrations" (`.github/workflows/staging_db_deploy.yml` + `tool/staging_migration_history_gate.sh`): nur main, Kill-Switch `STAGING_DB_DEPLOY_ENABLED`, CI-Checks-Gate, Environment `staging` (`SUPABASE_ACCESS_TOKEN`/`SUPABASE_PROJECT_REF_STAGING`/`SUPABASE_DB_PASSWORD_STAGING`), Project-Ref-Allowlist, History-Reconciliation (remote-only/divergent ⇒ STOP, kein repair), Dry-Run, forward-only `db push --linked`, Post-Verify + Read-only-Artefakt-Dump; Doku Runbook §12 | Staging-DB erhält B-1/B-2-Migrationen (`20260903100000`/`20260903120000`); danach erst Nicht-Web-E2E | direkt umgesetzt (2026-09-03) | implemented (2026-09-03, `chore/staging-db-migration-deploy-01`); erster Rollout erst NACH Owner-Merge + Secrets + Variable, manuell |

Bereits geführte Pakete, die diese Flächen zusätzlich berühren: `SHELL-ROUTING-01` (die drei Minimalrouten reiten auf `TASKS-NOTIFICATIONS-CORE-01`), `SETTINGS-01` (Preferences für gespeicherte Sichten und Benachrichtigungseinstellungen), `MAINTENANCE-PARITY-01` (Ticket-Zuweisungsereignis).

## Wave 3 — abhängige Module

| Paket | Inhalt / Abhängigkeit | Planung | Implementierung | Staging E2E |
|---|---|---|---|---|
| IMPORTS-01 (Wizard-UX erhalten, Ausführung serverseitig) | platform_audit_jobs-Adoption (W2), Import-Pipeline-Backend | blocked(backend) | — | — |
| AUDIT-01 (Workspace- + Objekt-Audit auf sicherem App-Read-Port) | allowlisted DTO, Redaction, Property-Keyset, RLS-/Retention-Proof | blocked(contract/security decisions; `screens/PROPERTY_AUDIT_V2.md`) | blocked(app read port) | todo |
| PROPERTY-ACTIVITY-HOST-01 | Top-Level `Aktivität` mit getrennten Childs Aktivität/Audit/Berichte; registriert wird erst mit dem ersten implementierten Child (kein leerer Tab) | committed (Scope beschlossen FULL-V2-SCOPE-01; `screens/PROPERTY_ACTIVITY_REPORTS_V2.md`) | committed — prerequisite-first (Technical readiness: PREREQUISITE REQUIRED — erster Child aus `PROPERTY-ACTIVITY-01` bzw. `AUDIT-01`) | todo |
| PROPERTY-ACTIVITY-01 (verständliche Objekt-Timeline) | permission-gefiltertes Activity-Read-Model; Audit-/Domain-Sichtbarkeit ist Inhalt des Pakets | committed (Scope beschlossen FULL-V2-SCOPE-01; `screens/PROPERTY_ACTIVITY_V2.md`) | committed — prerequisite-first (Technical readiness: PREREQUISITE REQUIRED — Activity-Read-Contract + Redaction-Review) | todo |
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
| PROPERTY-LOOKUP-01 | serverweite Property-Suche (Name/Adresse/PLZ/Ort) für Objektliste, Property-Wechsler und Entity Picker; ersetzt die ehrliche paginierte Browse-Auswahl | committed (Scope beschlossen FULL-V2-SCOPE-01) | implemented (2026-09-06, `feature/property-lookup-01`): generierte `search_text`-Spalte + Trigram-Index, kein neuer Lesepfad (die Suche filtert den bestehenden RLS-Read, Entity-Scope inklusive); Liste und Objektwechsler suchen serverweit; pgTAP 033 (24) und Rollback 039. Offen: Relevanz-Ranking, Diakritikfaltung, Entity Picker | todo |
| FINANCE-01 (Ledger, Budgets, BvA-Aufteilung, Covenants, Asset Workbook) | P2-D08 finance_debt | blocked(P2-D08) | — | — |
| PORTFOLIO-REPORTING-01 (Portfolios, Detail+Analytics+Quality, ESG, Report Templates, Dashboard) | P2-D09 reporting_analytics | blocked(P2-D09) | — | — |
| COMPS-CRITERIA-01 (Comps, Criteria Check, Criteria Sets, Compare) | P2-D07-Rest | blocked(P2-D07) | — | — |
| SETTINGS-01 (Workspace-Settings vs. User-Preferences) | Settings-/Preferences-Contract (unbeplant) | blocked(decision) | — | — |
| SALE-HOTEL-01 (10 Detail-Pages) | Produktentscheidung + neue Domain oder REMOVE | blocked(product decision) | — | — |

## PROPERTY-WORKSPACE-V2 — Spec Readiness (FULL-V2-SCOPE-01, Stand 2026-09-04)

Die 15 Dateien sind Implementierungsgrenzen. Sie erzeugen keine 15 gleichrangigen Ziele. Die verbindliche Maximal-IA bleibt `Übersicht / Objekt / Vermietung / Betrieb / Dokumente / Investment / Aktivität`; Investment und Aktivität hosten ihre Child-Screens, nicht implementierte Childs bleiben aus der Laufzeitnavigation verborgen — das ist eine Anzeigeregel, **keine** Scope-Aussage: jede Fläche unten gehört zum verbindlichen Zielbild.

Produkt-Scope und technische Bereitschaft werden getrennt geführt. `COMMITTED` heißt: wir bauen es. `PREREQUISITE REQUIRED` benennt, was vorher entsteht (prerequisite-first, unmittelbar gefolgt von der abhängigen UI und Staging-E2E). Der frühere Status bleibt als Historie in der letzten Spalte.

| Spec | IA-Ebene | Produkt-Scope | Technische Bereitschaft | Früherer Status |
|---|---|---|---|---|
| `PROPERTY_WORKSPACE_V2.md` | Workspace Host | COMMITTED | READY — Host implementiert; wächst mit jeder Domain | APPROVED |
| `PROPERTY_LIST_V2.md` | Einstieg vor Workspace | COMMITTED | READY für Liste, Keyset, Filter, Anlegen und serverweite Suche (`PROPERTY-DATA-02`, `PROPERTY-LOOKUP-01` gelandet); Ranking/Diakritik: PREREQUISITE REQUIRED | APPROVED |
| `PROPERTY_OVERVIEW_V2.md` | Übersicht | COMMITTED | READY für die gezählten Domänenfakten und die serverseitige Attention-Ordnung (`PROPERTY-OVERVIEW-DATA-01` gelandet); Finanz-KPIs: PREREQUISITE REQUIRED — `P2-D08`/`FINANCE-01`; Letzte Aktivität: PREREQUISITE REQUIRED — `AUDIT-01`; Lease-Roll-/Renewal-Projektion: PREREQUISITE REQUIRED — `LEASING-SUMMARY-01` | APPROVED |
| `PROPERTY_ASSET_V2.md` | Objekt | COMMITTED | READY für Stammdaten und Archivieren/Wiederherstellen (implementiert); Medien: PREREQUISITE REQUIRED — `PROPERTY-MEDIA-DATA-01` | APPROVED |
| `PROPERTY_LEASING_V2.md` | Vermietung Host | COMMITTED | READY — im Host registriert (2026-09-05): vier Unterbereiche Flächen/Verträge/Pipeline/Rent Roll auf den `lease.*`-Contracts, gated `lease.read` | APPROVED |
| `PROPERTY_OPERATIONS_V2.md` | Betrieb Host | COMMITTED | READY für Aufgaben (implementiert); Wartung/CapEx: PREREQUISITE REQUIRED — `MAINTENANCE-PARITY-01` | APPROVED |
| `PROPERTY_DOCUMENTS_V2.md` | Dokumente | COMMITTED | READY (implementiert); Medien bleiben eigenes Paket: PREREQUISITE REQUIRED — `PROPERTY-MEDIA-DATA-01` | APPROVED |
| `PROPERTY_INVESTMENT_V2.md` | Investment Host | COMMITTED | PREREQUISITE REQUIRED — erster Child `VALUATION-REHOST-01` | APPROVED |
| `PROPERTY_VALUATION_V2.md` | Investment → Bewertung | COMMITTED | PREREQUISITE REQUIRED — `VALUATION-REHOST-01` (Valuation-Domäne normalisiert separat) | APPROVED |
| `PROPERTY_SCENARIOS_V2.md` | Investment → Szenarien | COMMITTED | PREREQUISITE REQUIRED — `SCENARIO-VALUATION-01` (Lifecycle-/Versions-/Calculation-Contract) | BLOCKED |
| `PROPERTY_PERFORMANCE_V2.md` | Investment → Performance | COMMITTED | PREREQUISITE REQUIRED — `P2-D08` / `FINANCE-01` | BLOCKED |
| `PROPERTY_ACTIVITY_REPORTS_V2.md` | Aktivität Host | COMMITTED | PREREQUISITE REQUIRED — erster implementierter Child (`PROPERTY-ACTIVITY-01` oder `AUDIT-01`) | BLOCKED |
| `PROPERTY_ACTIVITY_V2.md` | Aktivität → Aktivität | COMMITTED | PREREQUISITE REQUIRED — `PROPERTY-ACTIVITY-01` (Activity-Read-Model + Redaction) | BLOCKED |
| `PROPERTY_AUDIT_V2.md` | Aktivität → Audit | COMMITTED | PREREQUISITE REQUIRED — `AUDIT-01` (App-Read-Port, allowlisted DTO, Redaction) | BLOCKED |
| `PROPERTY_REPORTS_V2.md` | Aktivität → Berichte | COMMITTED | PREREQUISITE REQUIRED — `P2-D09` / `PORTFOLIO-REPORTING-01` | BLOCKED |

**DRAFT:** keine. Offene Materialentscheidungen (Overview-Endpointform, Activity-Sichtbarkeit, Media-/Sharing-Security, Scenario-Lifecycle) sind ab FULL-V2-SCOPE-01 **Inhalt** ihrer prerequisite-Pakete, nicht mehr deren Sperre. Sie dürfen weiterhin nicht durch UI-Annahmen geschlossen werden: keine Client-Synthese fehlender Serverdaten, keine erfundenen KPIs, kein Security-/AAL-/RLS-Bypass.

### Property — Non-Goals (REJECTED, bleiben ausgeschlossen)

Bewusste Nicht-Ziele. Sie werden **nicht** in COMMITTED überführt; „aufwendig" ist kein Grund für diese Liste, sondern nur echte fachliche, rechtliche oder Sicherheitsgründe.

| Non-Goal | Grund |
|---|---|
| Exaktes VTS-/MRI-Layout, Logos, Trade Dress, pixelgenaue Kopie | fremdes geistiges Eigentum; übernommen werden Workflow-Muster, Informationsarchitektur, Interaction Patterns und funktionale Dichte |
| Client-seitig synthetisierte Overview-/Portfolio-KPIs aus geladenen Listen oder Teilmengen | erfundene Kennzahl statt Serverwahrheit; KPIs kommen ausschließlich aus `PROPERTY-OVERVIEW-DATA-01` |
| Completion-Proxies, Legacy-Formeln, fabrizierte NOI/IRR/DSCR/Scores | Legacy-Defekt (Screen Map §0.7); ersetzt durch contract-basierte Werte |
| Hard-Delete von Objekten | Datenverlust ohne Wiederherstellung; Lifecycle bleibt der auditierte, restaurierbare Tombstone (DEBT-012) |
| Öffentlich teilbare, ungeschützte URLs für Property-Medien/Dokumente | Security-Downgrade; externes Teilen nur über ein eigenes Sharing-Contract-Paket mit Ablauf, Widerruf und Audit |
| Rohes Tabellen-JSON, lokale Dateisystem-Exporte oder Client-Volltextsuche über Audit-Payloads | Leak-Risiko und Umgehung der serverseitigen Redaction |
| Automatisch erzeugtes „Basis"-Szenario und andere Cross-Domain-Writes beim Öffnen eines Objekts | Legacy-Nebenwirkung; Öffnen bleibt seiteneffektfrei |
| Umgehen von AAL2/RLS/Entity-Scope für UI-Komfort | historische Sicherheitsgarantien bleiben bindend (DEC-025) |
| Sale-/Hospitality-Flächen im Property Workspace | ungeklärte Produktdomäne; eigene Entscheidung unter `SALE-HOTEL-01` |

### Property — verbindliche Umsetzungsreihenfolge (prerequisite-first)

Backend-Voraussetzung zuerst, unmittelbar gefolgt von der abhängigen UI und Staging-E2E — keine langlaufenden Backend-Backlogs ohne konsumierende Oberfläche.

| Welle | Inhalt | Voraussetzung → abhängige Fläche |
|---|---|---|
| P-1 **abgeschlossen** (2026-09-05) | Lifecycle (Anlegen/Archivieren/Wiederherstellen), `Vermietung` im Host und der Objektwechsler stehen | `PROPERTY-DATA-02` ✓ → `PROPERTY-CREATE-01` (erstes Inkrement ✓) und Asset-Lifecycle-Aktionen ✓; Leasing-Panels → `Vermietung` ✓; Objektwechsler als keyset-paginierter Browse-Dialog ✓ (echte Suche bleibt `PROPERTY-LOOKUP-01`) |
| P-2 **abgeschlossen** (2026-09-06) | `Übersicht` ist Standardziel des Hosts: gezählte Domänenfakten, serverseitig geordnete Attention mit Drilldown, `Stand`-Zeile | `PROPERTY-OVERVIEW-DATA-01` ✓ → `PROPERTY_OVERVIEW_V2` ✓. Weiterhin offen und offen ausgewiesen: Finanz-KPIs (`P2-D08`), Letzte Aktivität (`AUDIT-01`), Lease-Roll-/Renewal-Projektion (`LEASING-SUMMARY-01`) |
| P-3 (Suche ✓, Medien offen) | Objektmedien/Titelbild; serverweite Objektsuche in Liste und Objektwechsler | `PROPERTY-LOOKUP-01` ✓ → Liste und Objektwechsler suchen serverweit ✓; `PROPERTY-MEDIA-DATA-01` → Objektmedien (offen) |
| P-4 | `Investment` mit Bewertung, danach Szenarien und Performance | `VALUATION-REHOST-01`; `SCENARIO-VALUATION-01`; `P2-D08` |
| P-5 | `Aktivität` mit Timeline, Audit und Berichten | `PROPERTY-ACTIVITY-01`; `AUDIT-01`; `P2-D09` |

Eine Property-Fläche gilt erst als DONE, wenn ihr vollständiger COMMITTED-Scope implementiert ist, die prerequisite-Pakete stehen, die benchmark-definierten Kernworkflows vorhanden sind, Responsive/Permissions/AAL bewiesen sind und Staging-E2E grün ist — ein erster Slice allein ist nicht DONE.

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
