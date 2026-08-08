# Phase 2 Domain Expansion Backlog

Status: `proposed`. Extends `docs/architecture/phase_0/12_phase_1_execution_backlog.md` (`P1-*`) with one vertical increment group per remaining domain (`P2-D01`..`P2-D09`). `portfolio_property` (`DOM-002`) is excluded — it is the completed reference slice and only needs the UI wave in `04_screen_redesign_wave_plan.md`.

## Shared Pattern (applies to every P2-D item)

Every domain expansion repeats the proven `P1-001`..`P1-021` shape:

1. **Schema migration** — new `supabase/migrations/*.sql` per domain, using the common contract types from `05_target_module_contracts.md`: `id`, `workspace_id`, `created_at`, `updated_at`, `created_by`, `updated_by`, `version`, optional `deleted_at`; money as `numeric` + currency; default-deny RLS from creation.
2. **pgTAP tests** — `supabase/tests/NNN_p2_dXX_<domain>.test.sql` covering schema, RLS (two-workspace isolation), RPC authorization, idempotency, audit.
3. **Rollback test** — `supabase/tests_rollback/NNN_p2_dXX_down.test.sql`, wired into the CI `database` job like the existing `tests_rollback/00X_p1_*` steps.
4. **Repository contract** — `lib/features/<domain>/{domain,application,data}/`: DTOs, `CommandContext`/`*RepositoryResult<T>` sealed types, abstract repository interface — no SDK types leak into `application/`.
5. **Adapters** — `legacy_sqlite_<domain>_adapter.dart` (read-only wrapper around the existing `lib/data/repositories/*_repo.dart`, blocks mutation with `dependencyConflict` exactly like `P1-006`) and `supabase_<domain>_repository_adapter.dart` (keyset pagination, RPC-only mutation, structured conflicts).
6. **Realtime invalidation** — workspace-scoped `UPDATE` subscription adapter, following `P1-011`/`P1-017`'s coalescing/generation-guard pattern.
7. **Dry-run migration mapper** — `sqlite_to_postgres_<domain>_dry_run_mapper.dart`, deterministic UUIDv5 + SHA-256 reconciliation, following `P1-012` exactly — read-only, no writes to source.
8. **Real local client integration test** — against local Supabase stack, mirroring `tool/verify_p1_007_integration.ps1`.
9. **CI wiring** — extend `.github/workflows/flutter.yml` job `database` with the new migration/test/rollback steps.

A domain is "done" only when all nine steps pass locally, matching the existing Definition of Done in `12_phase_1_execution_backlog.md`.

## Cross-Cutting Host Gate

| ID | Scope | Starts after | Completion gate |
|---|---|---|---|
| P2-X01 | Supabase main host, shared shell, route convergence, platform-honest transition and data cutover | P2-D07 / Wave 5 | all remaining domains cloud-capable, all 65 screens accounted for, full Web/Desktop golden path |

`P2-X01` is detailed in `04x_p2_x01_supabase_main_host.md`. AP0–AP3 block Wave 6: another domain must not be declared UI-complete while its Supabase screen is reachable only through an additive diagnostic route. AP4–AP6 run with P2-D08/P2-D09 and block the Phase-2 completion gate.

## Dependency Order

| ID | Domain | Depends on | Why this order | New/extends |
|---|---|---|---|---|
| P2-D01 | `identity_access` full expansion | P1-001..P1-020 (workspace/membership already exists) | Everything else needs invitation, role management and admin UI wired to Supabase, not just property-scoped auth | extends |
| P2-D02 | `contacts_parties` | P2-D01 | Canonical `Party` aggregate (`AGG-005`) is a hard dependency for leasing, maintenance and valuation counterparties; resolves `DUP-010`/`OPEN-001` | new |
| P2-D03 | `documents_compliance` | P2-D01 | Leasing and maintenance need document links before their own migration; introduces private Storage buckets (`MIG-BND-003`) | new |
| P2-D04 | `platform_audit_jobs` full expansion | P2-D01 | Tasks/notifications/import jobs become workspace-scoped and realtime for every domain migrated after this point, not just Property | extends |
| P2-D05 | `leasing_operations` | P2-D02, P2-D03, `portfolio_property` (done) | Units/Tenants/Leases/RentRoll need Party and Document contracts | new |
| P2-D06 | `maintenance_capex` | P2-D02, P2-D03, `portfolio_property` (done) | Tickets/CapEx need contractor Party and document links | new |
| P2-D07 | `valuation_transactions` | P2-D02, `portfolio_property` (done) | Scenarios/comps/offer need Property snapshot and counterparty references | new |
| P2-D08 | `finance_debt` | P2-D05, P2-D06, P2-D07, P2-D03, P2-X01 AP0–AP3 | Ledger/budget/covenants consume leasing receivables, maintenance cost commitments and approved valuations; its UI must enter through the real Supabase host | new |
| P2-D09 | `reporting_analytics` | all of the above | Read-model-only domain; must consume finished, versioned data from every other domain to avoid rebuilding KPIs twice | new |

## P2-D01 — `identity_access` Full Expansion

- Deliverable: Membership invitation flow (`invited -> active -> suspended -> revoked`, `STM-001`), role assignment UI backed by Supabase (replaces local-only `UsersScreen`/`lib/data/repositories/security_repo.dart` for cloud mode), `AuthorizationPort.authorize(permission, resourceRef)` used consistently instead of ad hoc RBAC checks scattered in screens.
- Open decision to resolve or explicitly default before merge: `DEC-016` (mandatory privileged-role MFA policy) — until resolved, ship with the existing AAL2-for-mutation gate and flag privileged-role enforcement as a named gap in the gate report, do not invent a policy.
- Gate: two-workspace membership isolation, invitation lifecycle test, role-permission matrix test, no privileged fallback state (extends `P1-008`).

## P2-D02 — `contacts_parties`

- Deliverable: single `parties` table + `party_roles` (tenant/contractor/buyer/bank/company as roles, not separate tables), replacing the parallel `ContactRecord`/`TenantRecord`/`ContractorRecord` models per `DUP-010`.
- Migration mapping: `tenants`, `contractors`, `contacts` legacy tables map into `parties`/`party_roles` via the dry-run mapper (`MIG-BND-001`); no legacy table is dropped until reconciliation passes.
- Resolves `OPEN-001` with the documented default assumption (separate functional roles, shared Party ID) unless the user overrides it before this item starts.
- Gate: duplicate-detection test (`DuplicateDetectionPort`), party-merge audit trail test, role-scoped read test.

## P2-D03 — `documents_compliance`

- Deliverable: `documents`/`document_versions`/`required_documents` cloud schema with private Supabase Storage buckets, signed-URL access (`SignedUrlPort`), replacing local `file_path` references (`DEBT-007`).
- Consolidates `DUP-011` (property onboarding checklist vs. general compliance model) into one requirement/workflow projection.
- Gate: upload → verify → supersede lifecycle test (`STM-008`), signed-URL expiry test, workspace-scoped storage isolation test.

## P2-D04 — `platform_audit_jobs` Full Expansion

- Deliverable: `tasks`, `notifications`, `import_jobs`, `search_index` become workspace-scoped Supabase tables with realtime, generalizing the audit/entitlement-invalidation pattern already proven for Property (`P1-011`, `P1-017`) to every domain event envelope (`CTR-005`).
- Gate: task idempotency test (`generated_key`, `AGG-019`), notification fan-out test, import job dry-run/reconciliation test (`AGG-020`).

## P2-D05 — `leasing_operations`

- Deliverable: `units`, `tenants` (as Party role), `leases`, `rent_roll_snapshots` cloud schema; `LeasingCase` pipeline (`STM-004`) as a first-class aggregate instead of UI-only status strings (resolves part of `FTR-024`).
- Resolves `OPN-DOM-001` (max one active lease per unit) with the documented default unless overridden.
- Gate: occupancy invariant test (`AGG-004`), rent-roll snapshot immutability test (`AGG-007`), two-session lease-mutation concurrency test.

## P2-D06 — `maintenance_capex`

- Deliverable: `maintenance_tickets`, `capex_projects` cloud schema with append-only status history (`AGG-008`), budget/forecast/actual separation (`AGG-009`); consolidates `renovation_projects` and the Asset Workbook renovation model per `DUP-013`.
- Gate: status-transition audit test (`STM-006`/`STM-007`), non-negative actual-cost constraint test.

## P2-D07 — `valuation_transactions`

- Deliverable: `scenarios`, `scenario_versions`, `criteria_sets`, `comps`, `acquisition_cases`, `disposition_cases` cloud schema; approved scenarios become server-immutable (`AGG-014`), matching the existing local `ScenarioWorkflowStatus` semantics.
- Consolidates `DUP-012` (Quick Screening vs. Acquisition Quick Evaluation) into one `AcquisitionCase` aggregate boundary.
- Gate: approval-immutability test (editing an approved scenario creates a new version, never mutates the approved one), deterministic-engine parity test against existing golden masters (`RISK-QA-001`).

## P2-D08 — `finance_debt`

- Deliverable: `ledger_accounts`/`ledger_entries` (append-only, `AGG-013`), `budgets`/`budget_lines` (`AGG-011`), `loans`/`covenants` (`AGG-012`), `capital_events` cloud schema; money fields as PostgreSQL `numeric` + currency (`DEC-011`, resolves `DEBT-010`).
- Gate: ledger append-only/counter-entry test, budget-version immutability test, covenant-check reproducibility test against a fixed input snapshot.

## P2-D09 — `reporting_analytics`

- Deliverable: read-only Postgres views/materialized read models per KPI (`KpiCatalogRepository`), `ReportRun` tracking (`AGG-017`) replacing local file-only report generation; every KPI names formula, source, as-of date, scope, currency and rounding (module contract invariant).
- Gate: report reproducibility test (same inputs, same `ReportRun` output), no-write-back test (confirms `DOM-009` never mutates source domains).

## Explicitly Out of Scope for Phase 2

- Remote/staging Supabase provisioning (blocked on `DEC-015`..`017`).
- Offline write queue beyond the cases already scoped in `08_sync_conflict_matrix.md` (`MIG-BND-006`).
- Legal/tax dunning automation (`OPN-DOM-003`), automatic urgency scoring (`FTR-033`), full bookkeeping/DATEV integration (`FTR-047`, `FTR-073`) — all remain `defer` per `06_feature_disposition.md`.
