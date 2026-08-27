# NexImmo Product Restore Tracker

Live-Status aller Rebuild-Pakete. Quelle der Wahrheit für Fortschritt (Master Plan §5: `PLAN → SPEC APPROVED → IMPLEMENT → PR → REVIEW → MERGE → STAGING → E2E → DONE`). Ein Paket ist erst DONE mit Staging-E2E. Grundlage: `PRODUCT_SCREEN_MAP.md` (Basis `9003392`, 2026-08-27).

Statuswerte: `todo` · `in_progress` · `spec_approved` · `implemented` · `merged` · `e2e_done` · `blocked(<worauf>)` · `n/a`.

## Wave 1 — Shared/Core

| Paket | Inhalt | Planung | Implementierung | Staging E2E |
|---|---|---|---|---|
| UX-FOUNDATION-IMPL-01 | Foundation §18: NxLiveUpdatesNotice, NxListSkeleton, splitViewMinWidth/NxSplitView, NxNotice, Retry-Sweep, Landing→properties | todo (kleiner Spec) | todo | todo |
| UI-HYGIENE-01 | 12 Orphans + toter Legacy-Shell-Ast entfernen (Liste: Screen Map §2 Orphans); Helper-Umzüge (propertyTypeOptions, operations_detail_support prüfen) | todo | todo | n/a (Test-/Analyze-Beweis) |
| REALTIME-DEGRADED-WIRING-01 | Degraded-Flag je Domäne (party, document, leasing, maintenance, valuation) bis in die Panels + NxLiveUpdatesNotice | todo | todo | todo |
| HELP-LINKS-01 | Help-Ziele nach cloudReadinessForPage filtern | n/a (trivial) | todo | n/a |

## Wave 2 — unabhängige Hauptmodule (parallel)

| Paket | Screens (Map-Referenz) | Disposition | Planung | Implementierung | Staging E2E |
|---|---|---|---|---|---|
| PROPERTY-WORKSPACE-01 | Reference-Slice-Liste+Detail, PropertiesScreen-Harvest, Workspace-Anatomie (PropertyShell-Nav als Vorlage) | KEEP+MERGE+REBUILD | todo | todo | todo |
| PROPERTY-DATA-02 (Backend-Gap) | Create/Archive/Delete im portfolio_property-Contract (Voraussetzung für Wizard) | — | todo | todo | todo |
| PROPERTY-CREATE-01 | 12-Schritt-Wizard rehosten | REDESIGN | blocked(PROPERTY-DATA-02) | blocked | todo |
| VALUATION-REHOST-01 | Case-Section als Queue-Detail (`onOpenCase`), Create-Dialog auf Contract, Badge-Umzug | MERGE | todo | todo | todo |
| TASKS-NOTIFICATIONS-01 | Tasks + Property-Tasks (eine UI) + Notifications auf platform_audit_jobs; Templates als Tab; Generierung serverseitig (DEBT-009) | REBUILD/MERGE | todo | todo | todo |
| MAINTENANCE-PARITY-01 | Ticket-Edit/Delete/Doc-/Task-Links/Filter/Benachrichtigungen in Contract+Panels; Legacy-Boards danach löschen (vorher Bauteilzustand/Gewährleistung diffen) | KEEP+MERGE | todo | todo | todo |
| DOCUMENTS-COMPLETE-01 | Registry-Flächen (Typen/Pflichtregeln) contract-basiert, Tab-Host + toter Palette-Jump weg, Media-Gap benannt | KEEP+MERGE+REBUILD | todo | todo | todo |
| ADMIN-AREA-01 | Admin-Workspace um ReferenceMembersScreen; UsersScreen-Harvest+REMOVE; Umzug aus reference_slice/ | KEEP+REMOVE | todo | todo | todo |

## Wave 3 — abhängige Module

| Paket | Abhängigkeit | Planung | Implementierung | Staging E2E |
|---|---|---|---|---|
| IMPORTS-01 (Wizard-UX erhalten, Ausführung serverseitig) | platform_audit_jobs-Adoption (W2), Import-Pipeline-Backend | blocked(backend) | — | — |
| AUDIT-01 (Workspace- + Objekt-Audit auf Adapter) | platform_audit_jobs-Adoption | todo | todo | todo |
| SCENARIO-VALUATION-01 (Inputs/Analysis/Scenarios/Versions/Offer) | Scenario-Lifecycle-Contract (Welle-5-Modell), VALUATION-REHOST-01 | blocked(contract) | — | — |
| FINANCE-01 (Ledger, Budgets, BvA-Aufteilung, Covenants, Asset Workbook) | P2-D08 finance_debt | blocked(P2-D08) | — | — |
| PORTFOLIO-REPORTING-01 (Portfolios, Detail+Analytics+Quality, ESG, Report Templates, Dashboard) | P2-D09 reporting_analytics | blocked(P2-D09) | — | — |
| COMPS-CRITERIA-01 (Comps, Criteria Check, Criteria Sets, Compare) | P2-D07-Rest | blocked(P2-D07) | — | — |
| SETTINGS-01 (Workspace-Settings vs. User-Preferences) | Settings-/Preferences-Contract (unbeplant) | blocked(decision) | — | — |
| SALE-HOTEL-01 (10 Detail-Pages) | Produktentscheidung + neue Domain oder REMOVE | blocked(product decision) | — | — |

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
