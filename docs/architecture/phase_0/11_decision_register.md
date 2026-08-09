# P0 Decision Register

| ID | Decision | Status | Evidence / reason | Revisit |
|---|---|---|---|---|
| DEC-001 | Retain Flutter/Dart for all clients and deterministic engines. | accepted | `pubspec.yaml`, `lib/core`, product roadmap | only after measured platform blocker |
| DEC-002 | Use Supabase PostgreSQL as central system of record. | accepted | relational domain, product roadmap | after reference-slice benchmark |
| DEC-003 | Start as modular monolith, not microservices. | accepted | current team/AI delivery shape and transactional domain | when independent scaling boundary is measured |
| DEC-004 | Use online-first for Web/Desktop reference slice. | accepted | sync conflict model is not yet implemented | after Phase 3 mobile pilot |
| DEC-005 | Preserve SQLite only as legacy source and optional later client cache. | superseded by DEC-024 (2026-08-06) | `lib/data/sqlite`, migration risk; review trigger "after data reconciliation succeeds" was reached — no legacy source data remains (`phase_2/04x`, 2026-08-04) | — |
| DEC-006 | Default-deny authorization must be server-enforced with RLS. | accepted | local guard cannot secure remote data | never weaken |
| DEC-007 | Missing or loading session must have no privileges. | accepted | P1-008 started in `security_state.dart`, `app_navigation.dart` and navigation/RBAC tests | verify before P1-008 completion |
| DEC-008 | Property reference slice is the first vertical cloud increment. | accepted | covers auth, tenancy, CRUD, audit and Realtime | after Phase-1 gate |
| DEC-009 | Critical updates use expected version plus mutation id. | accepted | prevents silent overwrite and duplicate retry | after concurrency tests |
| DEC-010 | Audit is append-only and atomically written with mutation. | accepted | financial/contract traceability | never weaken |
| DEC-011 | Money uses PostgreSQL `numeric` plus currency code. | accepted | current Dart `double` is unsuitable as storage contract | schema design |
| DEC-012 | Existing V1/V2 paths are dispositioned before removal. | accepted | feature flags and wrappers are active | Phase 2 UI consolidation |
| DEC-013 | PowerSync is optional and limited to selected mobile workflows. | accepted | Web support and conflicts require pilot | Phase 3 |
| DEC-014 | Legal/tax/accounting rules require external domain validation. | open | no authoritative source in repository | before relevant production feature |
| DEC-015 | Production runs in an EU region, target Frankfurt. Staging is placed in the same regulatory/geographic target region as far as the chosen Supabase environment model allows, so no cross-region architecture is introduced without cause. **This decides *where*, not *whether*: it authorizes no provisioning and no paid resource — that remains `DEC-017`.** | **accepted** (was `proposed` until 2026-08-08) | Owner decision 2026-08-08, confirming the 2026-08-02 owner decision preserved in `rescue/codex-ai-ph00-baseline` (`docs/ai/phase_01/owner_decisions.md`, `AI-PH01-DEC-001`). Rationale: low latency for German users and EU data residency | revisit only on a legal or operational requirement |
| DEC-016 | Privileged security and administration capabilities require AAL2, enforced **server-side and fail-closed** through RLS, RPC/DB guards or Supabase auth claims — never by the Flutter client alone. Not every ordinary action requires AAL2. Mandatory at least for capabilities affecting access control, memberships, roles/permissions and security-critical workspace administration; the exact capability matrix may be extended later. Passwordless email login stays the initial authentication method, and a pending `aal2` challenge keeps blocking client-side access. | **accepted** (was `proposed` until 2026-08-08) | Owner decision 2026-08-08, confirming the 2026-08-02 owner decision (`AI-PH01-DEC-002`). Already implemented for property mutation (restrictive RPC policy, local TOTP AAL2, fail-closed client state, all tested); the capability-by-capability rollout is implementation work, no longer an open decision | revisit only with an explicit security review |
| DEC-017 | **Exactly one isolated remote staging environment is authorized, with synthetic data only.** Covered: a separate Supabase staging project in `eu-central-1` (`DEC-015`); staging auth — passwordless magic link/PKCE, MFA/TOTP, self-signup **off**, synthetic test users created administratively; web redirects for the staging address *proven after deployment*, plus `neximmo://auth/callback` for Windows; custom SMTP for staging; the staging secrets; a controlled application of the repository migrations; the GitHub environment `staging`; an explicitly enabled staging deploy workflow; a Vercel **preview** deployment on a stable address without an own domain; and `GP-STAGING-WEB` / `GP-STAGING-WINDOWS`. Vercel Deployment Protection may be switched off for the app project as far as the real browser magic-link flow requires — that makes the static client publicly *loadable* and nothing more: auth, workspace membership, RLS, permissions and AAL2 keep protecting the data. **Cost rule:** resources that fit into existing quotas at no additional cost may be created; anything that would create a non-zero cost **stops** for an explicit owner approval naming provider, plan, one-off cost, monthly cost and cancellability. **Production stays unauthorized in every form** — no production Supabase or Vercel, no production secrets or SMTP, no real customer or inventory data, no migration out of production, no `app.neximmo.de`, no custom domain, no DNS, no production alias, deployment, cutover or installer, and no "temporary" production use. | **accepted** (was `open` until 2026-08-09) | Owner decision 2026-08-09, taken on the `STAGING-FOUNDATION-01` audit and after `STAGING-PREP-01` hardened the deployment path. Authorizing the environment is not creating it: provisioning is a separate work package | revisit before any production environment |
| DEC-018 | Realtime is a workspace-scoped query invalidation signal; repository readback remains canonical and the subscription lifecycle is bound to session, workspace and MFA state. | accepted | P1-011 adapter, controller lifecycle tests and local multi-client E2E | revisit only for an offline/sync pilot |
| DEC-019 | The legacy reference migration starts as a read-only dry run with explicit workspace/actor binding, deterministic UUIDv5 IDs and canonical SHA-256 reconciliation; reports contain no raw business or PII values. | accepted | P1-012 mapper, SQLite adapter and deterministic/negative tests | before any write-capable import executor |
| DEC-020 | The first backup/restore gate is a local, schema-scoped logical PostgreSQL drill into a new disposable database; database-global Realtime publication state is rebuilt from versioned migrations and then reconciled. | accepted | P1-014 target/corruption guards, non-empty restore, SHA-256 and invariant fingerprint | before authorized sandbox/staging drill |
| DEC-021 | SQLite und Supabase werden nur ueber explizite Environment-Auswahl initialisiert; der Supabase-Referenzschnitt besitzt stabile `/properties`- und `/properties/:id`-Routen. | accepted | `lib/main.dart`, `lib/app.dart`, Kaltstart-Deep-Link-Test und Web-Build | revisit only after routing-shell consolidation |
| DEC-022 | Entitlement-Aenderungen werden ueber private, nutzergebundene Realtime-Broadcasts signalisiert; kanonische Repository-Revalidation, Reconnect und ein begrenztes Intervall bleiben autoritativ. Client-Caches werden vor der Revalidation fail-closed geleert. | accepted | P1-017 Migration, Adapter-/Controller-Tests und lokaler Zwei-Client-Entzugstest | revisit for offline/sync or measured scale limits |

| DEC-024 | SQLite wird vollständig entfernt, nicht als Legacy-Quelle oder Client-Cache erhalten. Supabase ist die einzige Datenschicht; die Offline-Startfähigkeit des Desktop-Clients entfällt ersatzlos. Zielumgebung ist bis auf Weiteres der lokale Supabase-Stack; gehosteter Betrieb bleibt durch `DEC-015`..`DEC-017` gegated und ist vor dem Shipping zu entscheiden. Löst `DEC-005` ab und hebt die Offline-Zusage in `phase_2/00_phase_2_charter.md` (Z. 21) auf. | accepted | Nutzerentscheidung 2026-08-06; der Review-Trigger von `DEC-005` ist erreicht — die Legacy-Objektdaten waren reine Testdaten und wurden am 2026-08-04 bewusst entfernt, ein Datencutover ist damit gegenstandslos (`phase_2/04x`, Z. 337) | Umsetzungsplan und Gates: `phase_2/04y_p2_x02_sqlite_decommission.md` |

| DEC-023 | Bewertungsvarianten werden über zwei eigene Spalten auf `valuation_cases` gruppiert (`variant_group_id`, `variant_label`), nicht über den Legacy-Szenariobegriff und nicht über Titel-Konventionen. Eine Variante ist ein vollwertiger Fall mit eigener Version, eigenem Status und eigenem Bericht. | accepted | Nutzerentscheidung 2026-07-30; `scenario_id` als Gruppierung würde die gerade entkoppelte Legacy-Semantik wieder einführen, Titel-Konventionen wären implizite Semantik ohne Constraint | revisit only if variants ever need to differ structurally from a case |

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
| DEC-014 | external domain validation | this register | relevant later feature |

`DEC-015` (region) and `DEC-016` (privileged AAL2) left this index on 2026-08-08, `DEC-017`
on 2026-08-09; all three are `accepted` above.

**No open decision gates a remote *staging* environment any more.** `DEC-017` authorizes
exactly one, for synthetic data only — and authorizing is not creating: at the time of this
entry no remote environment exists and provisioning has not started. Production is a
different question and remains unauthorized; `DEC-017` says so explicitly rather than
leaving it to inference.

Where older documents name `DEC-015`..`DEC-017` together as a gate, or `DEC-017` alone as
open, those are point-in-time records and are deliberately not rewritten.
