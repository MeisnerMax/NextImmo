# P0 Decision Register

| ID | Decision | Status | Evidence / reason | Revisit |
|---|---|---|---|---|
| DEC-001 | Retain Flutter/Dart for all clients and deterministic engines. | accepted | `pubspec.yaml`, `lib/core`, product roadmap | only after measured platform blocker |
| DEC-002 | Use Supabase PostgreSQL as central system of record. | accepted | relational domain, product roadmap | after reference-slice benchmark |
| DEC-003 | Start as modular monolith, not microservices. | accepted | current team/AI delivery shape and transactional domain | when independent scaling boundary is measured |
| DEC-004 | Use online-first for Web/Desktop reference slice. | accepted | sync conflict model is not yet implemented | after Phase 3 mobile pilot |
| DEC-005 | Preserve SQLite only as legacy source and optional later client cache. | accepted | `lib/data/sqlite`, migration risk | after data reconciliation succeeds |
| DEC-006 | Default-deny authorization must be server-enforced with RLS. | accepted | local guard cannot secure remote data | never weaken |
| DEC-007 | Missing or loading session must have no privileges. | accepted | P1-008 started in `security_state.dart`, `app_navigation.dart` and navigation/RBAC tests | verify before P1-008 completion |
| DEC-008 | Property reference slice is the first vertical cloud increment. | accepted | covers auth, tenancy, CRUD, audit and Realtime | after Phase-1 gate |
| DEC-009 | Critical updates use expected version plus mutation id. | accepted | prevents silent overwrite and duplicate retry | after concurrency tests |
| DEC-010 | Audit is append-only and atomically written with mutation. | accepted | financial/contract traceability | never weaken |
| DEC-011 | Money uses PostgreSQL `numeric` plus currency code. | accepted | current Dart `double` is unsuitable as storage contract | schema design |
| DEC-012 | Existing V1/V2 paths are dispositioned before removal. | accepted | feature flags and wrappers are active | Phase 2 UI consolidation |
| DEC-013 | PowerSync is optional and limited to selected mobile workflows. | accepted | Web support and conflicts require pilot | Phase 3 |
| DEC-014 | Legal/tax/accounting rules require external domain validation. | open | no authoritative source in repository | before relevant production feature |
| DEC-015 | Production region is Frankfurt. | proposed | roadmap and EU data residency target | before paid provisioning |
| DEC-016 | Initial authentication method is passwordless email login; enrolled MFA is represented through Supabase AAL and pending `aal2` blocks client-side access. Property-Mutation verlangt serverseitig AAL2; eine allgemeine verpflichtende MFA-Regel fuer privilegierte Rollen bleibt offen. | proposed | bedienbare passwordless-/TOTP-/Logout-Aktionen, fail-closed Client-State, lokales TOTP-AAL2 und restriktive Property-RPC-Policy sind getestet; die allgemeine privilegierte Rollenmatrix fehlt | before production auth and privileged-role enforcement |
| DEC-017 | Supabase project creation and paid resources require explicit credentials/authority. | open | external state and cost | Phase 1 provisioning |
| DEC-018 | Realtime is a workspace-scoped query invalidation signal; repository readback remains canonical and the subscription lifecycle is bound to session, workspace and MFA state. | accepted | P1-011 adapter, controller lifecycle tests and local multi-client E2E | revisit only for an offline/sync pilot |
| DEC-019 | The legacy reference migration starts as a read-only dry run with explicit workspace/actor binding, deterministic UUIDv5 IDs and canonical SHA-256 reconciliation; reports contain no raw business or PII values. | accepted | P1-012 mapper, SQLite adapter and deterministic/negative tests | before any write-capable import executor |
| DEC-020 | The first backup/restore gate is a local, schema-scoped logical PostgreSQL drill into a new disposable database; database-global Realtime publication state is rebuilt from versioned migrations and then reconciled. | accepted | P1-014 target/corruption guards, non-empty restore, SHA-256 and invariant fingerprint | before authorized sandbox/staging drill |
| DEC-021 | SQLite und Supabase werden nur ueber explizite Environment-Auswahl initialisiert; der Supabase-Referenzschnitt besitzt stabile `/properties`- und `/properties/:id`-Routen. | accepted | `lib/main.dart`, `lib/app.dart`, Kaltstart-Deep-Link-Test und Web-Build | revisit only after routing-shell consolidation |

## Open Decision Rule

Open decisions do not block independent local work. Each implementation backlog item must name any decision that must be resolved before merge or deployment.

## Central Open-Decision Index

This index is authoritative for completeness; details and defaults remain in the named source artefact.

| IDs | Topic | Source | Latest blocking point |
|---|---|---|---|
| OPEN-001..OPEN-005 | Party model, legacy users, dead screens, acquisition model, property-type scope | `04_duplicate_and_debt_register.md` | Phase 1 routing or Phase 2/5 schema as specified |
| OPN-DOM-001..OPN-DOM-005 | Lease, ownership, dunning, approvals, retention | `02_domain_map.md` | relevant module contract |
| DEC-SEC-001..DEC-SEC-005 | role matrix, scope, PII, retention, upload policy | `07_security_and_tenancy_baseline.md` | RLS/upload/import pilot as specified |
| DEC-SYN-001..DEC-SYN-005 | offline engine, field scope, tombstones, merge UX, checklist conflicts | `08_sync_conflict_matrix.md` | Phase 3 offline pilot |
| DEC-014..DEC-017 | external domain validation, region, auth method, paid provisioning | this register | relevant Phase 1 provisioning or later feature |
