# Phase 2 Architecture Modernization Backlog

Status: `proposed`. This is the code-quality counterpart to `01_domain_expansion_backlog.md` — it resolves the debt catalogued in `docs/architecture/phase_0/04_duplicate_and_debt_register.md` (`DUP-*`, `DEBT-*`, `BIG-*`) so the codebase matches the module contracts in `05_target_module_contracts.md`, not just the database.

## Target Module Skeleton (per domain)

Every domain listed in `02_domain_map.md` converges on:

```
lib/features/<domain>/
  domain/        # DTOs, value objects (Money, Period, EntityRef)
  application/   # ports/interfaces, CommandContext, sealed Result types, use cases
  data/          # legacy_sqlite_*_adapter.dart, supabase_*_adapter.dart
  presentation/  # screens/widgets for this domain only; no other domain's adapters imported
```

This already exists for `portfolio_property` and `identity_access` (Phase 1) and `reference_slice`. Phase 2 extends it to `contacts_parties`, `documents_compliance`, `leasing_operations`, `maintenance_capex`, `finance_debt`, `valuation_transactions`, `reporting_analytics`, `platform_audit_jobs`, retiring the equivalent files under `lib/core/`, `lib/data/repositories/`, `lib/ui/screens/` one domain at a time as its `P2-D0x` backend item completes.

**Rule:** a screen only moves into `lib/features/<domain>/presentation/` once that domain's Supabase adapter exists and passes its gate. Moving UI files without a working backend contract is pure churn — don't do it out of order.

## V1/V2 Consolidation (blocks clean design work — do first)

**Status: `done` (2026-07-19).** All five items executed with parity/characterization tests written first and user sign-off before each delete; survivors renamed to canonical names (`*V2` suffixes dropped, `v2/` folders dissolved). Evidence in `00_phase_2_status.md`.

| ID | Action | Resolves |
|---|---|---|
| MOD-CLEAN-001 | ✅ Merged `AppScaffold` to the single (ex-V2) shell; legacy `Sidebar`/`TopBar` deleted; all four `UiScreenFlag`s + `ui_feature_flags.dart` removed; `SidebarV2`/`TopBarV2` renamed to `Sidebar`/`TopBar` | `DUP-001`, `DUP-005` |
| MOD-CLEAN-002 | ✅ `DashboardScreen` wrapper deleted; `DashboardScreenV2` renamed to `DashboardScreen`, routed directly | `DUP-002` |
| MOD-CLEAN-003 | ✅ V1 `PropertiesScreen` deleted (V2 was a functional superset, no V1-only test existed — a new characterization test covers the survivor); `PropertiesScreenV2` renamed to `PropertiesScreen` | `DUP-003` |
| MOD-CLEAN-004 | ✅ `PropertyShellV2` wrapper deleted; `PropertyShell` kept (modularization per `BIG-024` stays with Wave 1, unchanged) | `DUP-004` |
| MOD-CLEAN-005 | ✅ `SearchScreen` + its test deleted (redundant with `CommandPalette`, confirmed unrouted). `RentalOverviewScreen` kept for Wave 3 (leasing_operations); note: the "unused `AppScaffold` import" cited by `DEAD-002` no longer existed at execution time (already cleaned up earlier) — the screen is currently fully orphaned, which is expected until Wave 3 | `DEAD-001`, `DEAD-002`, `OPEN-003` (resolved) |

Each merge required a parity test written first (capture current behavior of both paths), then delete the losing path — never delete-then-hope. The parity tests were collapsed to the survivors and kept as permanent coverage (`test/ui/screens/properties_screen_parity_test.dart`, `test/ui/shell/shell_consolidation_parity_test.dart`).

## Canonical Domain Types (introduce once, use everywhere)

| Type | Replaces | Contract |
|---|---|---|
| `CommandContext` | ad hoc parameter lists per repository method | `CTR-001`; already exists in `lib/features/portfolio_property/application/property_repository.dart`, extend to a shared location once ≥2 domains use it |
| `EntityRef` | polymorphic `entity_type`/`entity_id` string columns (`notes`, `notifications`, `tasks`, `documents`, `budgets`, `ledger_entries`, `search_index`) | `CTR-002`, resolves `DEBT-006` |
| `Money` | raw `double`/SQLite `REAL` amounts | `CTR-003`, resolves `DEBT-010` |
| `Period` | mixing fiscal period with posting timestamp | `CTR-004` |
| `DomainEventEnvelope` | ad hoc realtime payloads | `CTR-005` |
| `PageRequest`/`PageResult` | unbounded list queries | `CTR-006`, already the pattern in `PropertyListQuery`/`PropertyPageResult` |
| `VersionConflict` | silent last-write-wins | `CTR-007`, already the pattern in `PropertyVersionConflict` |

Introduce these as a small shared package under `lib/core/contracts/` (or extend an existing shared location) the first time a second domain needs them — do not let each domain reinvent its own `Money` class.

## Large-File Decomposition (`BIG-*`, threshold ≥1000 LOC)

Split by responsibility (data loading / form editing / presentation), not by arbitrary line count. Priority follows the existing register's `kritisch`/`hoch` ratings, sequenced with the domain wave that owns each file so a screen is only touched once per wave:

| Priority | Files | Aligned wave |
|---|---|---|
| kritisch | `lib/data/sqlite/migrations.dart` (4390 LOC), `lib/data/repositories/property_repo.dart` (1437 LOC) | retire incrementally as each domain's SQLite adapter goes read-only; do not attempt a single rewrite |
| hoch | `maintenance_screen.dart` (both global 2896 and property-scoped 3966), `budget_vs_actual_screen.dart`, `portfolios_screen.dart`, `inputs_screen.dart`, `dashboard_screen_v2.dart`, `asset_workbook_screen.dart`, `settings_screen.dart`, `property_creation_workflow_screen.dart`, `scenarios_screen.dart`, `leases_screen.dart`, `documents_screen.dart`, `imports_screen.dart`, `property_shell.dart`, `asset_workbook_repo.dart` | Waves 1, 3, 4, 5, 6 respectively — see `04_screen_redesign_wave_plan.md` |
| mittel | remaining `BIG-010`..`031` | folded into their domain's wave |

Splitting happens as part of that screen's design+function rebuild in its wave — not as a separate mechanical pass, so it isn't done twice.

## Cross-Cutting Debt Items

| ID | Fix | Priority |
|---|---|---|
| DEBT-002/003 | Break the single 532-LOC `app_state.dart` composition root into one composition root per feature module, wired in `main.dart` per backend selection (pattern already used for `reference_slice`) | do per domain as it migrates |
| DEBT-009 | Move periodic task generation off the UI-shell timer onto a server-side scheduled job once `platform_audit_jobs` (`P2-D04`) is live locally; keep local idempotency as fallback | with P2-D04 |
| DEBT-012 | Replace `PropertyRepository.deletePermanently`'s manual cascade with archive/tombstone semantics plus a server-side transaction | with `portfolio_property` UI wave (Wave 1), since it's already the reference slice |
| DEBT-013 | Make `AuditWriter` a non-optional dependency for every mutation port, not just some repositories | ongoing, enforce via code review per domain migration |
| DEBT-015 | Split `app_settings` into User Preferences / Workspace Config / Secret-Auth State | with P2-D01 |
| DEBT-016 | Extend automated test coverage to a systematic contract/responsive/E2E matrix per screen (not just 81 ad hoc files) | one entry per screen in each wave's acceptance criteria, see `04_screen_redesign_wave_plan.md` |
| DEBT-TOKEN-001 | Two parallel color-token sources — `AppColors` (static, ~61 files) and `_lightTokens`/`_darkTokens` in `lib/ui/theme/app_theme.dart` — must be edited together; several `property_detail` screens also hardcode neutral hex literals instead of reading the theme (`overview_screen.dart`, `property_shell.dart`, `units_screen.dart` and text-only in `budget_vs_actual_screen.dart`, `maintenance_screen.dart`). **W0 part done (2026-07-19):** both sources now read from a single private `_Palette` const table in `app_theme.dart` (drift structurally impossible; guarded by `test/ui/theme/token_source_sync_test.dart`; zero visual change — goldens pixel-identical). Known and deliberate: `AppColors.background` stays white (= surface), not the warm canvas, until legacy screens migrate. Remaining: per-screen hardcoded hex + `AppColors.background` semantics. | remaining hex + background semantics per screen in its wave (1/3/6) |

## Explicit Non-Goals

- No rewrite of the deterministic calculation engines (`lib/core/engine/`, `lib/core/offer/`, `lib/core/criteria/`) — these are `retain` per `06_feature_disposition.md` and protected by golden-master tests (`RISK-QA-001`). Only their persistence adapters change.
- No microservice split — `DEC-003` (modular monolith) stands.
- No introduction of a declarative router as a prerequisite — `SYS-003`'s state-based navigation can host the new module structure; router migration is a separate decision if it ever becomes necessary, not a Phase 2 requirement.
