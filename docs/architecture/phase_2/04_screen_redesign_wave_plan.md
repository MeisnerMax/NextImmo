# Phase 2 Screen Redesign Wave Plan

Status: `proposed`. Assigns all 65 screens from `docs/architecture/phase_0/01_system_inventory.md` (`SCR-001`..`SCR-065`) to the domain waves from `01_domain_expansion_backlog.md`, so backend migration and UI redesign for a given domain happen together instead of drifting apart.

## Why Waves, Not All 65 At Once

A screen's design plan is only trustworthy once its backend contract is stable (per `03_design_system.md`'s state requirements — forbidden/conflict/offline states need a real repository result type to design against). Building all 65 detailed plans now would either freeze prematurely against a backend that hasn't been built yet, or become stale before its wave starts. Instead:

- This document gives the **complete map** (every screen assigned to a wave, with its current known debt) so nothing is lost or forgotten.
- **Two screens are fully worked here** as the quality bar and template proof: `DashboardScreenV2` (Wave 1) and `PropertiesScreenV2`/`OverviewScreen` (Wave 1).
- Each subsequent wave gets its **own full detail document** (`04a_wave1_....md`, `04b_wave2_....md`, ...), written immediately before that wave starts, using the same template from `03_design_system.md` — this keeps every plan grounded in the domain's actual, just-finished backend contract instead of a six-month-old guess.

## Wave Overview

| Wave | Domain(s) | Depends on | Screens (count) |
|---|---|---|---|
| 0 | Foundation (shell, design system rollout, V1/V2 cleanup) | none | 4 |
| 1 | `identity_access` (UI) + `portfolio_property` (UI only — backend already done) | Wave 0 | 14 |
| 2 | `contacts_parties` + `documents_compliance` | P2-D02, P2-D03 | 4 (+1 new) |
| 3 | `leasing_operations` | P2-D05 | 10 |
| 4 | `maintenance_capex` | P2-D06 | 5 |
| 5 | `valuation_transactions` | P2-D07 | 12 |
| X01 | Supabase main host and cutover (cross-cutting, no new screen) | P2-D07; AP0–AP3 block Wave 6 | 0 |
| 6 | `finance_debt` | P2-D08 | 5 |
| 7 | `reporting_analytics` + `platform_audit_jobs` | P2-D04, P2-D09 | 10 |
| 8 | Deferred/specialized (property-type modules, help) | after Phase-2 gate | 2 |

65 screens total, matching the system inventory count exactly.

`P2-X01` does not add a 66th screen. It makes the canonical shell and the already assigned screens reachable from the authenticated Supabase runtime. Detailed sequence and gates: `04x_p2_x01_supabase_main_host.md`.

## Full Screen Assignment

| SCR | Screen | Domain | Wave | Known debt (from `04_duplicate_and_debt_register.md`) |
|---|---|---|---|---|
| SCR-001 | SecurityGate | IA | 0 | — |
| SCR-002 | LockScreen | IA | 0 | — |
| SCR-003 | AppScaffold | PA | 0 | `DUP-001`, `DUP-005` (V1/V2 shell + flags) |
| SCR-064 | SearchScreen | PA | 0 | `DEAD-001` — decide integrate-into-`CommandPalette` or remove |
| SCR-004 | DashboardScreenV2 | RA | 1 | `BIG-007` (2633 LOC) — **fully worked below** |
| SCR-005 | DashboardScreen (wrapper) | RA | 1 | `DUP-002` — remove |
| SCR-006 | PropertiesScreenV2 | PP | 1 | `BIG-026`, `DUP-003` — **fully worked below** |
| SCR-007 | PropertiesScreen (V1) | PP | 1 | `DUP-003` — merge then remove |
| SCR-008 | PropertyCreationWorkflowScreen | PP | 1 | `BIG-012` (1791 LOC) |
| SCR-009 | PropertyShellV2 (wrapper) | PP | 1 | `DUP-004` — remove |
| SCR-010 | PropertyShell | PP | 1 | `BIG-024` (1162 LOC) |
| SCR-011 | OverviewScreen | PP | 1 | `BIG-010` — **fully worked below** |
| SCR-043 | PortfoliosScreen | PP | 1 | `BIG-004` (3003 LOC, list+detail+nav in one file) |
| SCR-044 | PortfolioDetailScreen | PP | 1 | same file as SCR-043 — split during rebuild |
| SCR-045 | PortfolioAnalyticsScreen | RA | 1 | — |
| SCR-046 | DataQualityDashboardScreen | RA | 1 | — |
| SCR-061 | UsersScreen | IA | 1 | needs Supabase membership/role UI per `P2-D01` |
| SCR-062 | SettingsScreen | PA | 1 | `BIG-009` (2211 LOC, mixes platform/security/domain defaults, `DEBT-015`) |
| SCR-020 | PropertyDocumentsScreen | DC | 2 | `DUP-007`, `DUP-011` |
| SCR-051 | DocumentsScreen (global) | DC | 2 | `BIG-022`, `DUP-007` |
| SCR-052 | ComplianceDashboardScreen | DC | 2 | — |
| — | *(new)* Parties directory screen | CP | 2 | resolves `DUP-010`, `OPEN-001` — screen does not exist yet, created alongside `P2-D02` |
| SCR-022 | OperationsOverviewScreen | LO | 3 | — |
| SCR-024 | UnitsScreen | LO | 3 | `BIG-018` |
| SCR-025 | UnitDetailScreen | LO | 3 | `BIG-016` |
| SCR-026 | TenantsScreen | LO | 3 | `DUP-010` (Party consolidation lands here as consumer of Wave 2) |
| SCR-027 | TenantDetailScreen | LO | 3 | same |
| SCR-028 | LeasesScreen | LO | 3 | `BIG-020` |
| SCR-029 | LeaseDetailScreen | LO | 3 | — |
| SCR-030 | RentRollScreen | LO | 3 | `Update_V9.1_restore.md` items 3+4 (overflow, auto-populate) fold in here |
| SCR-032 | OperationsAlertsScreen | LO | 3 | `Update_V9.1_restore.md` item 6 (currently empty tab) folds in here |
| SCR-065 | RentalOverviewScreen | LO | 3 | `DEAD-002` — decide before rebuild: integrate as Portfolio sub-page or remove |
| SCR-034 | PropertyMaintenanceScreen | MC | 4 | `BIG-002` (3966 LOC), `Update_V9.1_restore.md` item 7 |
| SCR-039 | MaintenanceScreen (global) | MC | 4 | `BIG-005`, `DUP-006` (shared module with SCR-034) |
| SCR-040 | ContractorsScreen | MC | 4 | `BIG-027`; backing data becomes a Party role from Wave 2 |
| SCR-056 | RenovationValueScreen | MC | 4 | `BIG-028` |
| SCR-031 | AssetWorkbookScreen (renovation half) | MC/FD | 4 & 6 | `BIG-008` (2309 LOC), `DUP-013` — split file: renovation content in Wave 4, finance content in Wave 6 |
| SCR-012 | InputsScreen | VT | 5 | `BIG-006` (2858 LOC), `Update_V9.1_restore.md` items 13+14 |
| SCR-013 | AnalysisScreen | VT | 5 | `Update_V9.1_restore.md` item 1 (Sensitivity chart contrast) |
| SCR-014 | CompsScreen | VT | 5 | — |
| SCR-015 | CriteriaCheckScreen | VT | 5 | — |
| SCR-016 | OfferScreen | VT | 5 | — |
| SCR-017 | ScenariosScreen | VT | 5 | `BIG-013` |
| SCR-018 | ScenarioVersionsScreen | VT | 5 | — |
| SCR-054 | CompareScreen | VT | 5 | — |
| SCR-055 | QuickScreeningScreen | VT | 5 | `BIG-019`, `DUP-012` |
| SCR-057 | DispositionExitScreen | VT | 5 | `BIG-030` |
| SCR-058 | CriteriaSetsScreen | VT | 5 | `BIG-031` |
| SCR-059 | _CriteriaSetEditorScreen | VT | 5 | same file as SCR-058 — split during rebuild |
| SCR-033 | BudgetVsActualScreen | FD | 6 | `BIG-003` (3651 LOC), `Update_V9.1_restore.md` item 8 |
| SCR-035 | CovenantsScreen | FD | 6 | `Update_V9.1_restore.md` item 9 (auto-generate from inputs) |
| SCR-037 | LedgerScreen | FD | 6 | — |
| SCR-038 | BudgetsScreen | FD | 6 | `BIG-017`, `Update_V9.1_restore.md` item 12 (entity ID → name) |
| SCR-019 | PropertyAuditScreen | PA | 7 | — |
| SCR-021 | ReportsScreen | RA | 7 | — |
| SCR-023 | PropertyTasksScreen | PA | 7 | `BIG-015`, `Update_V9.1_restore.md` item 5 (task fields) |
| SCR-041 | TasksScreen (global) | PA | 7 | `BIG-011`, `DUP-007` |
| SCR-042 | TaskTemplatesScreen | PA | 7 | `BIG-021` |
| SCR-047 | PortfolioPackScreen | RA | 7 | — |
| SCR-048 | ImportsScreen | PA | 7 | `BIG-023` |
| SCR-049 | NotificationsScreen | PA | 7 | — |
| SCR-050 | EsgDashboardScreen | RA | 7 | — |
| SCR-053 | AuditScreen (global) | PA | 7 | `DUP-007` |
| SCR-060 | ReportTemplatesScreen | RA | 7 | — |
| SCR-036 | PropertyTypeModuleScreen | PP | 8 | `DEAD-003` — scope decision (`OPEN-005`) needed before real design work, currently a generic stand-in for Sale/Hotel/Parking |
| SCR-063 | HelpScreen | PA | 8 | — |

`SettingsScreen` (SCR-062) is listed once in Wave 1 as the platform shell, but its domain-specific sections (quality thresholds, security defaults, report defaults) get their content refreshed incrementally as each owning domain's wave lands — don't block Wave 1 on every other domain's settings.

## Worked Example 1 — `DashboardScreenV2` (SCR-004, Wave 1)

1. **Zielbild**: A workspace owner opens the app and immediately sees portfolio health (occupancy, overdue tasks, budget variance flags, upcoming lease/document expirations) without navigating anywhere — a genuine executive summary, not a grid of every available widget.
2. **Layout**: `NxPageHeader` (workspace name + date range picker), a responsive KPI row (`NxCard` tiles, wraps to 2 columns on tablet, 1 on phone), a two-column body on desktop (attention-needed list left, trend charts via `NxChartContainer` right) collapsing to stacked single column below desktop.
3. **States**: loading skeleton per KPI tile (not full-page spinner — tiles resolve independently since they come from different domains' read models); empty state for a workspace with zero properties (`NxEmptyState` → "Add your first property" leading into `PropertyCreationWorkflowScreen`); forbidden state not applicable (dashboard always available to any active member, content scoped by their permissions).
4. **Data density**: KPI tiles pull from `reporting_analytics` read models (`P2-D09`) once available; until then, from existing local aggregation — no dashboard content may block on a domain that hasn't migrated yet.
5. **Interactions**: date-range selector as the one piece of dashboard-wide state; every "attention needed" row navigates directly to the source screen/entity, never to a generic list.
6. **Debt resolved**: splits `BIG-007`'s 2633 LOC into KPI-tile widgets + attention-list widget + chart section, each independently testable; removes the `DashboardScreen` wrapper (`DUP-002`) by routing directly to this screen.

## Worked Example 2 — `PropertiesScreenV2` + `OverviewScreen` (SCR-006, SCR-011, Wave 1)

1. **Zielbild**: Properties list is the primary daily entry point — fast search/filter over potentially hundreds of properties, clear status at a glance, one click to a detail view that leads with the numbers a portfolio manager actually checks first (occupancy, NOI trend, next lease expiry, open tasks) before any raw field dump.
2. **Layout**: List uses `NxDataTableShell` with the columns already defined by the reference slice's `PropertySummaryDto` (`P1-020`) — name, address, status, plus one KPI column; column picker for anything beyond that. Desktop shows list + detail side-by-side per the existing reference-slice adaptive pattern (`10_reference_slice_spec.md` form factors); phone/tablet keep the already-implemented separate list/detail routes.
3. **States**: exactly the reference-slice set — loading/empty/error/unauthenticated/forbidden/conflict — already implemented and tested in `lib/features/reference_slice/`; this wave's job is to bring the *visual* design up to `03_design_system.md`'s bar, the state *logic* is already correct and must not regress.
4. **Data density**: keyset pagination already exists (`P1-020`); this wave adds saved filters/sort as a UI layer on top, no new backend needed.
5. **Interactions**: create → `PropertyCreationWorkflowScreen` wizard; row click → detail; inline status change requires confirmation (archiving is a real workflow transition, `STM-002`, not a soft toggle).
6. **Debt resolved**: merges `PropertiesScreen`/`PropertiesScreenV2` (`DUP-003`) after porting any V1-only test case; removes `PropertyShellV2` wrapper (`DUP-004`); splits `PortfoliosScreen`'s 3003 LOC (`BIG-004`) into list/detail/nav files when the same list+detail pattern is applied to Portfolios in the same wave.

## Cadence For Waves 2–8

Before each wave starts:

1. Confirm its `P2-D0x` backend item (from `01_domain_expansion_backlog.md`) has passed its local gate.
2. Write `04<letter>_wave<N>_<domain>.md` with one fully worked entry per screen in that wave, using the template from `03_design_system.md` and the two worked examples above as the quality bar.
3. Only then start implementation (see `05_claude_execution_prompt.md` for how this is executed turn by turn).

Do not pre-author Wave 3–8 detail documents now — they would be guessing against backend contracts that don't exist yet, and Wave 0/1 will likely refine the design-system rollout in ways later waves should inherit.

Before Wave 6 starts, complete `P2-X01` AP0–AP3. Before Phase 2 closes, complete AP4–AP6. No later screen wave may use an additive cloud route as its sole production entry point.
