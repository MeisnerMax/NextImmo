# NexImmo Product Restore Tracker

Live-Status aller Rebuild-Pakete. Quelle der Wahrheit für Fortschritt (Master Plan §5: `PLAN → SPEC APPROVED → IMPLEMENT → PR → REVIEW → MERGE → STAGING → E2E → DONE`). Ein Paket ist erst DONE mit Staging-E2E. Grundlage: `PRODUCT_SCREEN_MAP.md` (Basis `9003392`, 2026-08-27).

Statuswerte: `todo` · `in_progress` · `spec_approved` · `implemented` · `merged` · `e2e_done` · `blocked(<worauf>)` · `n/a`.

## Wave 1 — Shared/Core

| Paket | Inhalt | Planung | Implementierung | Staging E2E |
|---|---|---|---|---|
| UX-FOUNDATION-IMPL-01 | Foundation §18: NxLiveUpdatesNotice, NxListSkeleton, splitViewMinWidth/NxSplitView, NxNotice, Retry-Sweep, Landing→properties | spec_approved | merged (`3a11b09`, 2026-08-28) | todo |
| UI-HYGIENE-01 | 12 Orphans + toter Legacy-Shell-Ast entfernen (Liste: Screen Map §2 Orphans); Helper-Umzüge (propertyTypeOptions, operations_detail_support prüfen) | todo | todo | n/a (Test-/Analyze-Beweis) |
| REALTIME-DEGRADED-WIRING-01 | Degraded-Flag je Domäne (party, document, leasing, maintenance, valuation) bis in die Panels + NxLiveUpdatesNotice | todo | todo | todo |
| HELP-LINKS-01 | Help-Ziele nach cloudReadinessForPage filtern | n/a (trivial) | todo | n/a |

## Wave 2 — unabhängige Hauptmodule (parallel)

| Paket | Screens (Map-Referenz) | Disposition | Planung | Implementierung | Staging E2E |
|---|---|---|---|---|---|
| PROPERTY-WORKSPACE-01 | Host + Liste + Objekt + siebenstufige Maximal-IA; Childs nur bei Contract/Implementierung registrieren | KEEP+MERGE+REBUILD | spec_approved (`screens/PROPERTY_WORKSPACE_V2.md`; Readiness-Review 2026-08-28) | todo | todo |
| PROPERTY-OVERVIEW-DATA-01 (Backend-Gap) | Permission-gefilterte Property-KPI-/Attention-/Freshness-Projektionen; keine Client-Aggregate | — | blocked(material product/security contract decisions; Requirements in `screens/PROPERTY_OVERVIEW_V2.md`) | blocked(contract) | todo |
| PROPERTY-DATA-02 (Backend-Gap) | Create/Archive/Delete im portfolio_property-Contract (Voraussetzung für Wizard) | — | todo | todo | todo |
| PROPERTY-MEDIA-DATA-01 (Backend-Gap) | privates Property-Media-/Titelbild-Contract; Documents nicht zweckentfremden | — | blocked(product/contract/security decisions) | blocked(contract/security decision) | todo |
| PROPERTY-CREATE-01 | 12-Schritt-Wizard rehosten | REDESIGN | blocked(PROPERTY-DATA-02) | blocked | todo |
| VALUATION-REHOST-01 | Property-Queue → Case-Detail; vorhandene Engine/Factors/Reports/Variants/Lifecycle, kein Overview-„aktuell“-Heuristik | MERGE | spec_approved (`screens/PROPERTY_VALUATION_V2.md`, 2026-08-28) | todo | todo |
| TASKS-NOTIFICATIONS-01 | Tasks + Property-Tasks (eine UI) + Notifications auf platform_audit_jobs; Templates als Tab; Generierung serverseitig (DEBT-009) | REBUILD/MERGE | Property-Task-Teil spec_approved (`screens/PROPERTY_OPERATIONS_V2.md`); Gesamtpaket todo | todo | todo |
| MAINTENANCE-PARITY-01 | DTO-/RPC-Parität für Ticket/CapEx Create/Read/Update/Transition; Currency aus Daten; kein Delete/Document-Link/Notification im ersten Inkrement | KEEP+MERGE | spec_approved (`screens/PROPERTY_OPERATIONS_V2.md`, 2026-08-28) | todo | todo |
| DOCUMENTS-COMPLETE-01 | Property-Register/Requirements rehosten; Registry-Flächen workspace-weit separat; Media-Gap bleibt | KEEP+MERGE+REBUILD | Property-Teil spec_approved (`screens/PROPERTY_DOCUMENTS_V2.md`); Registry-Teil todo | todo | todo |
| ADMIN-AREA-01 | Admin-Workspace um ReferenceMembersScreen; UsersScreen-Harvest+REMOVE; Umzug aus reference_slice/ | KEEP+REMOVE | spec_approved (2026-08-28, `docs/product/screens/admin_members.md`; inkl. Foundation-AMD-001 „Mitglieder"; Paket B Invite-Accept → Core/Auth/Gate) | A1 implemented (2026-08-28, PR #44 `feature/admin-members-v2-a1`; A2 Aktivität + Paket B offen) | todo |

## Wave 3 — abhängige Module

| Paket | Abhängigkeit | Planung | Implementierung | Staging E2E |
|---|---|---|---|---|
| IMPORTS-01 (Wizard-UX erhalten, Ausführung serverseitig) | platform_audit_jobs-Adoption (W2), Import-Pipeline-Backend | blocked(backend) | — | — |
| AUDIT-01 (Workspace- + Objekt-Audit auf sicherem App-Read-Port) | allowlisted DTO, Redaction, Property-Keyset, RLS-/Retention-Proof | blocked(contract/security decisions; `screens/PROPERTY_AUDIT_V2.md`) | blocked(app read port) | todo |
| PROPERTY-ACTIVITY-HOST-01 | Top-Level `Aktivität` mit getrennten Childs Aktivität/Audit/Berichte | mindestens ein implementierter Child | blocked(no implemented child; `screens/PROPERTY_ACTIVITY_REPORTS_V2.md`) | blocked | todo |
| PROPERTY-ACTIVITY-01 (verständliche Objekt-Timeline) | permission-gefiltertes Activity-Read-Model; Audit-/Domain-Sichtbarkeit entscheiden | blocked(activity/security contract; `screens/PROPERTY_ACTIVITY_V2.md`) | blocked(contract) | todo |
| SCENARIO-VALUATION-01 (Inputs/Analysis/Scenarios/Versions/Offer) | Scenario-Lifecycle-Contract (Welle-5-Modell), VALUATION-REHOST-01 | blocked(contract) | — | — |
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
