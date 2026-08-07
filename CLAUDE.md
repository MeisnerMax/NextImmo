# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

NexImmo ("Deal Analyzer Desktop") is an offline-first Flutter desktop app for real-estate deal
analysis, portfolio and property management, valuation, operations, and reporting. It ships on
Windows/desktop and web, backed historically by a local SQLite core, and is being incrementally
migrated to a Supabase (Postgres) backend behind the same repository interfaces. See
[Software_Goal.txt](Software_Goal.txt) for the full product scope and per-version workflows, and
[docs/architecture/enterprise_target_architecture.md](docs/architecture/enterprise_target_architecture.md)
for the target architecture (module responsibilities, entity lifecycles, permission model, audit
concept, guardrails).

The migration is tracked as a phased backlog under `docs/architecture/`:
- `phase_0/` — inventory, domain map, data dictionary, security/tenancy baseline, decision register,
  and the Phase 1 execution backlog (`12_phase_1_execution_backlog.md`, items `P1-001`..`P1-021`).
- `phase_1/` — environment contract, backup/restore runbook, and the reference-slice gate review.
- `phase_0/00_phase_status.md` is the living gate/status log — read it before touching
  identity/access, property repositories, or Supabase migrations to see what's already `done` vs
  `partial`/open, and which risk IDs are still outstanding.

## Commands

Flutter/Dart (run from repo root):
```
flutter pub get --enforce-lockfile     # install locked deps (CI uses --enforce-lockfile)
flutter analyze --no-pub               # static analysis, must be clean before finishing work
flutter test --no-pub                  # full test suite
flutter test test/core/engine/some_test.dart          # single test file
flutter test --plain-name "some test description"     # single test by name
flutter build web --no-pub             # web build, a required CI gate
```

Local Supabase stack (Supabase CLI is pinned to `2.109.1` via `package.json`; use `npx supabase`):
```
npx supabase start                     # start local stack
npx supabase status -o env             # print local API_URL / PUBLISHABLE_KEY / etc.
npx supabase db reset --local --no-seed
npx supabase db lint --local --schema public --level error --fail-on error
npx supabase db advisors --local --type security --level info --fail-on error
npx supabase db advisors --local --type performance --level info --fail-on error
npx supabase test db --local           # run pgTAP tests in supabase/tests
npx supabase stop --no-backup
```

Backend-specific Flutter runs use `--dart-define` (never commit real values, see Environment below):
```
flutter run --dart-define=NEXIMMO_ENV=local --dart-define=NEXIMMO_DATA_BACKEND=sqlite
flutter run --dart-define=NEXIMMO_ENV=local --dart-define=NEXIMMO_DATA_BACKEND=supabase \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

Integration/E2E guard scripts under `tool/` (PowerShell; each starts from a fresh local Supabase
reset, so they are destructive to local dev data and mirror what CI runs — see
`.github/workflows/flutter.yml` job `database` for the exact sequence and ordering):
```
./tool/verify_p1_004_concurrency.ps1
./tool/verify_p1_007_integration.ps1
./tool/verify_p1_011_e2e.ps1
./tool/verify_p1_018_postgrest.ps1
./tool/verify_p1_014_backup_restore.ps1 [-TestCorruptArchive]
./tool/test_p1_014_backup_restore_guard.ps1
./tool/test_p1_014_crash_recovery.ps1
./tool/test_p1_021_performance_profile_guard.ps1
./tool/verify_p1_021_performance_profile.ps1 -PropertyCount 250 -WarmupRuns 1 -MeasuredRuns 5
```

CI (`.github/workflows/flutter.yml`) has two jobs: `verify` (pub get, analyze, test, build web) and
`database` (local Supabase reset, lint, security/performance advisors, pgTAP tests, targeted
migration-rollback replays, then the `tool/verify_*`/`test_*` scripts above). Match this locally
before considering Supabase-related work done.

## Environment contract

See [docs/architecture/phase_1/01_environment_contract.md](docs/architecture/phase_1/01_environment_contract.md).

- `NEXIMMO_ENV` (`local`/`staging`/`production`) and `NEXIMMO_DATA_BACKEND` (`sqlite`/`supabase`)
  are required and **fail closed** on missing/unknown values — see
  [lib/core/config/app_environment.dart](lib/core/config/app_environment.dart). There is no
  implicit fallback between environments or backends.
- Only `NEXIMMO_ENV`, `NEXIMMO_DATA_BACKEND`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` may reach
  the Flutter client (via `--dart-define`).
- `SUPABASE_SECRET_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_PASSWORD`,
  `SUPABASE_ACCESS_TOKEN` are server-only and must never be committed, dart-defined, put in
  `supabase/config.toml`, logged, or exported.
- Remote (non-local) Supabase provisioning is **not authorized** yet — pending decisions
  `DEC-015`..`DEC-017` in `docs/architecture/phase_0/11_decision_register.md`. Don't wire up or
  suggest staging/production Supabase provisioning without checking that register first.

## Architecture

### Two coexisting data layers

- `lib/core/`, `lib/data/repositories/`, `lib/data/sqlite/` — the original, larger local-first
  application: deterministic engines (valuation, finance, criteria, offer solver, reports, quality,
  operations, audit, notifications, versioning, security) plus SQLite-backed repositories consumed
  directly by `lib/ui/screens/*`. This is most of the app today and is being migrated feature-by-
  feature, not rewritten wholesale.
- `lib/features/<feature>/{domain,application,data}/` — the new target-architecture pattern used
  for features that have been migrated. Each feature defines:
  - `domain/` — DTOs (e.g. `property_dto.dart`).
  - `application/` — backend-agnostic contracts: abstract repository interfaces, command/query
    objects, sealed `*RepositoryResult<T>` success/failure types with typed failure kinds (e.g.
    `PropertyRepositoryFailureKind.versionConflict`), invalidation-source interfaces. No SDK types
    leak into this layer.
  - `data/` — concrete adapters implementing the application contracts, one per backend, e.g.
    `legacy_sqlite_property_repository_adapter.dart` vs `supabase_property_repository_adapter.dart`,
    or `supabase_identity_access_repository_adapter.dart`. `main.dart` selects which adapter to wire
    into Riverpod providers based on `AppEnvironment.dataBackend` (see `lib/main.dart`).
  - This is the pattern to follow when migrating another feature or adding new
    Supabase-backed functionality — don't call `Supabase.instance.client` directly from UI or core
    code; add/extend an adapter behind the feature's application contract.
- `lib/features/reference_slice/` is the working reference implementation of the target
  architecture (property list/detail, auth/MFA, realtime invalidation) — read it together with
  [docs/architecture/phase_0/10_reference_slice_spec.md](docs/architecture/phase_0/10_reference_slice_spec.md)
  and [docs/architecture/phase_1/03_reference_slice_gate_review.md](docs/architecture/phase_1/03_reference_slice_gate_review.md)
  before extending it.

### Enterprise architecture guardrails (binding, from `enterprise_target_architecture.md`)

1. No direct SQL access from UI code — UI depends on repositories/providers, not the database.
2. Every critical mutation goes through a repository or dedicated service.
3. Every critical mutation must be audit-ready; most must write append-only audit records (no
   delete/edit path for audit entries).
4. Every workflow entity (Property, Scenario, Unit, Lease, Tenant, Document, Task) has explicit
   status logic — see the entity lifecycle section of that doc before adding new states.
5. New core model changes must consider cloud-readiness (workspace scoping, actor metadata,
   version/concurrency tokens) even when the feature is currently local-only.
6. Permissions are fine-grained capabilities (e.g. `property.update`, `scenario.approve`,
   `document.verify`) aggregated into roles (`admin`, `manager`, `analyst`, `operations`,
   `viewer`), not broad role checks scattered in UI — see `lib/ui/state/security_state.dart`.

### Supabase/Postgres layer

- `supabase/migrations/` — forward SQL migrations, currently implementing `P1-001`..`P1-018`
  (workspace/role/permission/audit baseline, default-deny RLS, property contract with optimistic
  versioning, realtime invalidation, AAL2/MFA hardening, entitlement revalidation). Every migration
  needs default-deny RLS and a corresponding rollback test.
- `supabase/tests/*.test.sql` — pgTAP schema/RLS/behavior tests, run via `supabase test db`.
- `supabase/tests_rollback/*_down.test.sql` — verifies each migration's down-path; CI replays these
  by running `supabase migration down --last N` then the matching rollback test, then migrating
  back up.
- `supabase/tests_concurrency/`, `tests_integration/`, `tests_ops/`, `tests_performance/` — fixtures
  consumed by the `tool/verify_*`/`test_*` PowerShell scripts (real two-session concurrency, real
  HTTP client integration against local PostgREST/Auth, backup/restore/crash-recovery drills,
  parameterized performance profiling with `EXPLAIN ANALYZE` capture).
- Mutations are workspace-scoped, tied to `auth.uid()`, versioned (optimistic concurrency via
  `expectedVersion`/`PropertyVersionConflict`), idempotent (`mutationId`), and audited
  (`correlationId`, `reason`). Follow this shape for any new Supabase-backed mutation rather than
  inventing a new one.

### Legacy → Supabase migration tooling

`lib/features/portfolio_property/data/sqlite_reference_migration_source_adapter.dart` and
`sqlite_to_postgres_reference_dry_run_mapper.dart` implement a **read-only, deterministic dry-run**
(UUIDv5 IDs, SHA-256 checksums, explicit workspace/actor mapping, no source mutation) for migrating
legacy SQLite property data into Postgres. Treat this as the template for migrating other legacy
tables — do not write ad hoc one-off migration scripts.

### UI

- `lib/ui/navigation/` — app-wide navigation/routing, gated by role/capability
  (`lib/ui/state/security_state.dart`); missing/unknown security state grants no access (fail
  closed), matching the permission model above.
- `lib/ui/screens/` — one directory per domain area (`properties`, `property_detail`, `portfolio`,
  `ledger`, `budgets`, `maintenance`, `tasks`, `audit`, `security`, `admin`, plus a `v2`/`shell/v2`
  in-progress redesign track).
- `lib/ui/state/` — screen-level Riverpod state/orchestration; no direct SQL/DB access (delegates
  to repositories).
- Responsive rules (desktop/web/tablet/phone all must work; see `AGENTS.md` for the exhaustive
  German-language checklist the previous agent config used): avoid fixed widths/heights that break
  on small screens, wrap `Row`s with wide children in `Expanded`/`Flexible`/`Wrap`, handle text
  overflow explicitly, use `LayoutBuilder`/`MediaQuery`/`ConstrainedBox` over ad hoc breakpoints, and
  scroll targeted regions rather than wrapping whole screens in `SingleChildScrollView`. Reuse
  existing breakpoint/theme/component helpers (`lib/ui/theme/`, `lib/ui/utils/`, `lib/ui/widgets/`)
  before building new responsive primitives.

## Testing structure

`test/` mirrors `lib/` (`test/core/...`, `test/data/...`, `test/features/...`, `test/ui/...`), plus:
- `test/integration/` — real local-client integration tests (Supabase/PostgREST), including
  `supabase_property_realtime_integration_test.dart` and
  `supabase_postgrest_authorization_integration_test.dart`. These need a running local Supabase
  stack (see Commands above), unlike the rest of `flutter test` which is self-contained.
- `test/features/reference_slice/goldens/` — golden screenshots for phone/tablet/desktop
  breakpoints of the reference slice; regenerate deliberately, not incidentally.
- Prefer targeted `flutter test <path>` while iterating, but run the full suite plus
  `flutter analyze` before considering a change done — both are CI gates.

## Working conventions

- Don't change database structure, tables, columns, migration logic, existing routes, existing
  state management, existing models, existing navigation, or the existing design system without an
  explicit request.
- Reuse existing widgets/styles/breakpoints; only split large screens when it clearly improves
  maintainability. Keep business logic out of UI widgets.
- No new packages without an explicit request; no unnecessary refactors alongside a targeted
  change.
- When touching Supabase, check `docs/architecture/phase_0/00_phase_status.md` first for what's
  already `done`/`partial` and which `RISK-*`/`DEC-*` items are still open — several security/AAL/
  MFA/performance-budget items are intentionally still unresolved and shouldn't be assumed fixed.
