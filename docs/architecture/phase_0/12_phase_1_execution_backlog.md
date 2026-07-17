# Phase 1 Execution Backlog

Status: `in_progress`; `P1-001` bis `P1-005`, `P1-007`, `P1-008` und `P1-013` sind complete.

## Dependency Order

| ID | Work item | Depends on | Deliverable | Gate | Status |
|---|---|---|---|---|---|
| P1-001 | Add local Supabase project structure and environment contract without credentials. | Phase 0 | `supabase/config.toml`, environment documentation | local config validates | done |
| P1-002 | Create baseline schema for workspace, membership, role, permission and audit. | P1-001 | versioned SQL migrations | apply/rollback test | done |
| P1-003 | Implement default-deny RLS and helper functions. | P1-002, DEC-SEC-001 | policies and SQL tests | two-workspace isolation passes | done |
| P1-004 | Create property cloud schema with version, mutation and audit contract. | P1-002 | migration and RPC/function | atomic concurrency tests pass | done |
| P1-005 | Define Dart repository contracts independent of SQLite/Supabase. | Phase 0 | feature-scoped interfaces and DTOs | analyzer and contract tests pass | done |
| P1-006 | Wrap existing SQLite property access behind local adapter. | P1-005 | adapter with unchanged behavior | existing property tests pass | partial (read-only done; safe mutations blocked) |
| P1-007 | Add Supabase property adapter behind explicit environment selection. | P1-001, P1-003, P1-004, P1-005 | remote adapter | integration tests pass | done |
| P1-008 | Replace admin fallback with unauthenticated/no-permission state. | DEC-007 | security state change and tests | no privileged loading state | done |
| P1-009 | Implement auth/workspace/property reference-slice application state. | P1-007, P1-008, DEC-016 | controllers/use cases | state tests pass | proposed |
| P1-010 | Implement adaptive reference-slice UI using existing design system. | P1-009 | desktop/tablet/phone paths | screenshot and overflow tests pass | proposed |
| P1-011 | Implement Realtime invalidation for active property queries. | P1-007, P1-009 | scoped subscription lifecycle | two-client E2E passes | proposed |
| P1-012 | Build SQLite-to-PostgreSQL dry-run mapper for reference entities. | P1-002, P1-004 | read-only migration report | counts and checksums reconcile | proposed |
| P1-013 | Add CI gates for Dart, Flutter, SQL, RLS and migration tests. | P1-003, P1-005 | CI workflow | required checks green | done |
| P1-014 | Add backup/restore and operational runbook for sandbox/staging. | P1-001, DEC-015, DEC-017 | tested runbook | restore drill passes | proposed |
| P1-015 | Run reference-slice security and performance review. | P1-001..P1-014 | gate report | Phase-1 gate accepted | proposed |

## First Safe Local Increment

Implement the auth/workspace reference state in `P1-009`. `P1-006` remains read-only; safe mutations use the remote contract. Do not create a remote Supabase project until `DEC-015`, `DEC-016` and `DEC-017` are resolved.

## P1-001 Validation

- Local structure and TOML syntax are present without committed credentials.
- Supabase CLI `2.109.1`, local startup, migration reset and schema lint pass.
- P1-002 bis P1-004 add the versioned schema after the P1-001 foundation anchor.

## P1-004 Validation

- 160 pgTAP assertions cover schema, RLS, tenancy, RPC validation, authorization, idempotency and audit.
- 9 rollback assertions pass after `migration down`; reapplication and the full suite pass again.
- Two real concurrent sessions produce exactly one success, one version conflict, one audit event and version 2.

## P1-006 Validation

- Legacy SQLite reads are mapped through the feature repository contract and bound to one explicitly configured workspace; foreign workspace IDs fail closed.
- Property mutations are blocked with `dependencyConflict`: `properties` has no durable version and `audit_log` has no unique mutation ID. `updated_at` is a timestamp and is not presented as a version.
- Mapping, Scope und Mutation-Blocker sind getestet; der Feature-Analyzer ist fehlerfrei.
- Die vollstaendige Projektsuite besteht mit 187 Tests und 5 Skips. Der lokale Adapter bleibt fuer Mutationen bewusst gesperrt.

## P1-007 Validation

- Der Supabase-Adapter implementiert workspace-gescopte Keyset-Pagination, Detailzugriff und ausschliessliche RPC-Mutationen.
- Actor-Abgleich, strukturierte Konflikte, DTO-Mapping und fail-closed Fehlerbehandlung sind mit 9 Adaptertests abgedeckt.
- Ein echter Clienttest prueft Passwort-Login, RLS-Liste, RPC-Update, identischen Retry, Versionskonflikt und Readback gegen den lokalen Stack.
- Die Backendauswahl `sqlite|supabase` und alle erforderlichen Public-Defines werden fail-closed validiert.

## Responsive QA Validation

- Ein DB-freies Overflow-Gate prueft Dashboard, Immobilien-Dialog und Tabellenhuelle auf Mobile, Tablet und Desktop.
- Alle 9 Viewport-Tests bestehen; die parallele Gesamtsuite ist nach zustandsbasierter Stabilisierung des App-Flow-Tests gruen.
- Grenzwerttests direkt an den Breakpoints sowie das CI-Gate bleiben fuer P1-010 und P1-013 offen.

## Definition Of Ready

- dependencies completed
- owned files identified
- relevant source files read fully
- acceptance tests named
- schema/navigation/package changes explicitly in scope
- open decisions listed

## Definition Of Done

- implementation and tests committed as one vertical increment
- server authorization and negative tests included where applicable
- migration dry run and rollback path documented
- audit and concurrency behavior verified
- no regression in local SQLite mode until migration gate approves removal
- changed architecture artefacts updated
