# NexImmo Product Restore / Rebuild Master Plan

## 1. Goal

NexImmo is moving from infrastructure/security hardening back into product work. Existing screens are currently too rudimentary to treat as final product UI. The goal is therefore **not merely to restore old screens**, but to plan and rebuild every important screen properly, with consistent UX, complete functional requirements, explicit permissions/data contracts, and staging E2E proof before Production.

This file is the persistent master plan for all future planning and implementation chats.

## 2. Working model

Every new chat starts without assumed prior context. It must read the relevant repo documentation and current code before making decisions.

Use separate chats for separate responsibilities:

- **Planning chat:** deep product/UX planning for one screen or one shared foundation topic. Produces/updates a specification. Does not implement.
- **Claude Code implementation chat:** implements one approved specification in one isolated branch/worktree. It reads the current repo first and does not redesign the product on its own.
- **Integration chat:** coordinates merge order, resolves cross-feature conflicts, validates main/CI/staging, and performs wave-level E2E.

Planning and implementation are intentionally separate.

## 3. Non-negotiable principles

1. **Plan before code.** No major screen rebuild starts without an approved screen spec.
2. **One screen/topic per planning chat.** Deep context beats one huge product chat.
3. **One isolated worktree/branch per implementation chat.** No two agents write to the same branch.
4. **Shared foundation first.** Navigation, shell, layout patterns, tables, filters, forms, detail-page patterns, status/empty/error/loading states and common interaction rules must be stabilized before broad parallel screen implementation.
5. **Do not let screen agents silently change shared architecture.** Shared components, repository contracts, domain models, Supabase schema, RLS and permission catalog require explicit review/package when materially changed.
6. **Backend gaps are reported, not improvised.** A screen spec may identify a backend gap; that becomes a separate data/backend package unless the change is already clearly in scope and approved.
7. **Historical security guarantees stay intact.** AAL/RLS/auth/storage/realtime guarantees must not be weakened for UI convenience.
8. **Production remains a later gate.** Product restore is proven on Staging first.
9. **Integration happens after every wave, not at the very end.**
10. **Specs and tracker are source-of-truth artifacts.** Conversation memory is never required for continuity.

## 4. Product rebuild phases

### Phase A — PRODUCT-UX-FOUNDATION-01

Define and, where required, implement the common UX/system spine before parallel screen work.

At minimum decide:

- application shell
- primary/secondary navigation
- route hierarchy
- page widths and responsive breakpoints
- page header anatomy
- list/table pattern
- search/filter/sort pattern
- detail-page pattern
- tabs/sections/drawers/modals conventions
- form pattern and validation
- loading, empty, partial, error and permission-denied states
- status chips and actions
- notifications / non-blocking degraded-state messaging
- destructive-action confirmations
- responsive desktop/tablet/mobile behavior
- shared component ownership rules
- permission-driven navigation behavior
- accessibility baseline

This phase should prevent each screen from inventing its own UX language.

### Phase B — PRODUCT-SCREEN-MAP-01

Audit the actual repository and create `docs/product/PRODUCT_SCREEN_MAP.md` plus `docs/product/PRODUCT_RESTORE_TRACKER.md`.

For every real/planned screen record at least:

- module/domain
- screen name and route
- current file(s)
- whether reachable today
- current UI maturity
- repository/data source
- permissions/capability gate
- current CRUD/functions
- missing functions
- realtime dependency
- shared components used
- backend/data gaps
- dependencies on other screens/packages
- disposition: keep / redesign / rebuild / remove / merge
- planning status
- implementation status
- staging E2E status

Do not implement screens during this audit.

### Phase C — Screen planning

Each screen gets its own planning chat and its own specification under:

`docs/product/screens/<screen_slug>.md`

Use `docs/product/SCREEN_SPEC_TEMPLATE.md`.

A screen may only become implementation-ready when its spec has:

- purpose and user jobs
- information architecture
- complete function list
- data requirements
- permission behavior
- all important states
- navigation/relationships
- shared component dependencies
- responsive behavior
- backend gaps
- test/E2E requirements
- measurable acceptance criteria
- explicit out-of-scope items

### Phase D — Parallel implementation waves

Parallelism is allowed only after dependencies are understood.

Recommended shape:

#### Wave 1 — Shared/Core

Typical scope:

- app shell
- navigation
- dashboard/home framework
- shared table/list behavior
- shared detail layout
- shared forms/filters/search primitives
- notifications/degraded-state presentation

Wave 1 should minimize future merge conflicts.

#### Wave 2 — Relatively independent main modules

Candidate parallel tracks, subject to the Screen Map:

- Properties
- Parties / Contacts
- Documents / Compliance
- Valuation

#### Wave 3 — More interdependent operational modules

Candidate tracks:

- Units / Tenants
- Leases / Leasing Cases / Rent Roll / Rental Overview
- Maintenance / Operations / CapEx

The final grouping must come from the repository audit, not from this preliminary list alone.

## 5. Implementation lifecycle for every screen/package

Use this state machine:

`PLAN -> SPEC APPROVED -> IMPLEMENT -> PR -> REVIEW -> MERGE -> STAGING -> E2E -> DONE`

A package is not DONE merely because code was merged.

### Implementation-chat expectations

The implementation chat must:

1. verify current `origin/main` and create/use its dedicated branch/worktree
2. read the Master Plan, Screen Map, Tracker and exact approved screen spec
3. read all relevant current code before editing
4. identify any spec-vs-code conflicts before implementation
5. use red-first tests where the behavior can and should be pinned before the change
6. implement the smallest coherent solution matching the spec
7. avoid unrelated refactors
8. validate targeted tests, full test suite as appropriate, analyze, build and diff hygiene
9. review the diff for security/permission/data-contract regressions
10. commit, push and open a PR when authorized
11. stop before merge unless the prompt explicitly authorizes merge

## 6. Parallel branch/worktree rules

Recommended naming:

- `feature/property-detail-v2`
- `feature/documents-center-v2`
- `feature/parties-v2`
- `feature/valuation-v2`

Recommended local worktrees:

- `NexImmo-property`
- `NexImmo-documents`
- `NexImmo-parties`
- `NexImmo-valuation`

Rules:

- one agent owns one worktree/branch
- no agent edits another feature branch
- branches start from the approved wave base SHA
- if a shared dependency changes after branching, integration decides whether to rebase/update before continuing
- no large shared-component redesign inside a feature PR without explicit approval

## 7. Shared-component change policy

A screen agent may use shared components freely.

A small backwards-compatible extension may remain in the feature PR if it is clearly generic, tested and low-conflict.

A substantial shared change becomes its own package, e.g.:

- `SHARED-UI-TABLE-02`
- `SHARED-DETAIL-LAYOUT-01`
- `SHARED-FORM-FRAMEWORK-01`

This avoids three parallel agents redesigning the same component differently.

## 8. Backend/data-contract policy

Screen rebuilds must not silently introduce schema/RLS/permission changes.

If a screen needs missing data or capability, the planning spec records a **Backend Gap**.

Typical follow-up packages may be:

- `PROPERTY-DATA-02`
- `DOCUMENT-PERMISSIONS-01`
- `LEASING-DATA-01`

Schema, migrations, RLS and permission-catalog changes require dedicated review and Staging proof before a screen is considered E2E-complete.

## 9. Wave integration

After each implementation wave, run a dedicated integration package rather than accumulating many unmerged branches.

Example:

`PRODUCT-INTEGRATION-WAVE-02`

It should verify:

- intended PR set and merge order
- conflicts against current main
- shared component consistency
- route/navigation integration
- visual/interaction consistency
- permission gating across modules
- CI after each merge
- Staging deployment on the resulting main SHA
- browser smoke test
- cross-screen flows
- wave-level E2E

Only then start the next dependency-sensitive wave.

## 10. Staging product acceptance

After the core modules are rebuilt, run:

`PRODUCT-E2E-STAGING-01`

It should cover at least:

- login / MFA / logout / session recovery
- permission-driven navigation
- RLS negative cases
- Properties
- Documents
- Parties
- Leasing
- Maintenance / CapEx
- Valuation
- realtime live delivery and reconnect behavior where applicable
- reload/browser restart/token refresh/network interruption
- create/update/delete/archive flows that the final product supports
- empty/error/degraded states

The gate is: **Staging behaves like the intended product, not merely a collection of merged screens.**

Staging business fixtures and permissions should be created because the actual product modules need them, not merely to manufacture isolated infrastructure proofs.

## 11. Production path

Production work begins only after Staging product acceptance.

Planned packages:

### PROD-READINESS-01

Inventory and plan Production Supabase, Vercel, auth, redirects, SMTP, secrets, storage, realtime, migrations, backup/rollback and domain requirements.

### PROD-PROVISION-01

Provision/configure the Production environment from the proven Staging architecture. No normal customer access yet.

### PROD-SECURITY-PROOF-01

Before user access, prove at minimum:

- anonymous access boundaries
- AAL1 vs AAL2 boundary
- RLS
- permissions
- storage/signed URLs
- realtime
- no service-role or production secrets in client artifacts
- correct environment separation
- auth/recovery/redirect behavior

### PROD-CUTOVER-01

Activate the real Production application/domain and controlled user access.

### POST-GO-LIVE-01

Run immediate production smoke tests, auth/MFA, core CRUD/read flows, realtime, logs/health and rollback readiness before declaring Production fully DONE.

## 12. Known current project baseline

This section is a navigation aid, not a substitute for live repo verification.

As of the creation of this plan:

- `SECURITY-STORAGE-AAL-03` is CLOSED/PASS.
- `SECURITY-AAL-CLIENT-03` is PASS/CLOSED.
- `TEST-STABILITY-P2D03-01` is DONE.
- `DOCS-CURRENCY-01` is DONE.
- Property realtime live delivery and reconnect recovery have remote Staging proof.
- The same reconnect latch was fixed in party, document, leasing, maintenance and valuation adapters and is locally tested; representative remote closeout is blocked because Staging currently lacks those domain fixtures/permissions, not because of a known defect.
- `liveUpdatesDegraded` is rendered as a passive, non-blocking notice in the reference slice (`REALTIME-DEGRADED-UI-01`, merged 2026-08-26 as `b14c879`); the shared UX foundation should generalize that pattern, not invent it. The realtime docs closeout (`REALTIME-DOCS-CLOSEOUT-01`, `0af08e2`) records the whole proven state.
- Production remains locked until the explicit Production phases above.
- Rotation of the locally exported `SUPABASE_ACCESS_TOKEN` is intentionally not part of this plan unless explicitly reopened by the user.

Always verify current `origin/main`, current docs and current code before acting.

## 13. Persistent artifacts

The product rebuild should eventually contain:

- `docs/product/PRODUCT_RESTORE_MASTER_PLAN.md` — this file
- `docs/product/PRODUCT_SCREEN_MAP.md` — generated by the audit
- `docs/product/PRODUCT_RESTORE_TRACKER.md` — live status
- `docs/product/SCREEN_SPEC_TEMPLATE.md` — standard screen planning contract
- `docs/product/CHAT_START_PROMPTS.md` — context-independent chat starters
- `docs/product/screens/*.md` — approved per-screen specifications

These repo files, not conversation history, are the continuity mechanism across ChatGPT and Claude sessions.
