# NexImmo Context-Independent Chat Start Prompts

These prompts are designed for **new chats with zero conversational history**. The persistent context lives in the repository, not in previous chat memory.

Replace placeholders in `<ANGLE_BRACKETS>` before use.

---

## 1. PRODUCT-UX-FOUNDATION-01 — Planning Chat

Use in a fresh ChatGPT/Claude planning chat.

```text
NEXIMMO — PRODUCT-UX-FOUNDATION-01
Planning only

Repository: MeisnerMax/NextImmo

Assume you know nothing from previous chats.

Before proposing anything, read fully:
- docs/product/README.md
- docs/product/PRODUCT_RESTORE_MASTER_PLAN.md
- docs/product/SCREEN_SPEC_TEMPLATE.md
- current product/UI architecture and shared UI code
- current routes/navigation/app shell

Also verify current origin/main. Do not rely on SHAs written in old conversation logs.

Goal:
Define the common UX/system foundation that all rebuilt NexImmo screens must follow: shell, navigation, page/header patterns, lists/tables, filters/search, detail pages, forms, states, permissions-driven navigation, degraded/live-update messaging, responsive behavior, shared-component ownership and accessibility baseline.

Important:
- planning only; do not implement
- preserve existing security/AAL/RLS/auth guarantees
- do not design each domain screen in depth yet
- inspect and reuse good existing components where appropriate
- identify obsolete/rudimentary patterns instead of blindly preserving them

Output:
1. Current-state findings
2. Proposed UX foundation/design rules
3. Shared components/patterns to keep, change, create or remove
4. Decisions that affect every screen
5. Concrete acceptance criteria
6. Dependencies/risks
7. Exact repo document(s) that should be created/updated for implementation handoff

STOP after the plan/spec is implementation-ready.
```

---

## 2. PRODUCT-SCREEN-MAP-01 — Audit Chat

Use after the UX foundation is decided.

```text
NEXIMMO — PRODUCT-SCREEN-MAP-01
Repository audit only

Repository: MeisnerMax/NextImmo

Assume zero prior chat context.
Read fully first:
- docs/product/README.md
- docs/product/PRODUCT_RESTORE_MASTER_PLAN.md
- the approved PRODUCT-UX-FOUNDATION-01 document(s)
- current routes/navigation
- all current UI screen entry points
- relevant feature/domain folders

Verify current origin/main.

Goal:
Create the authoritative product screen map and restore tracker from the actual repository.

For every existing/planned screen capture:
- domain
- route
- files
- reachability
- current maturity
- functions/CRUD
- data/repository source
- permissions
- realtime dependency
- dependencies
- backend gaps
- disposition: keep/redesign/rebuild/remove/merge
- planning/dev/staging-E2E status

Required repo outputs:
- docs/product/PRODUCT_SCREEN_MAP.md
- docs/product/PRODUCT_RESTORE_TRACKER.md

Do not implement or redesign screens in this package.
Do not infer screens solely from old docs; reconcile docs against current code.

End with recommended planning order and safe parallel implementation waves.
STOP.
```

---

## 3. Per-Screen Planning Chat

Use one fresh chat per screen.

```text
NEXIMMO — SCREEN PLAN — <SCREEN_ID>
Planning/specification only

Repository: MeisnerMax/NextImmo
Screen: <SCREEN_NAME>
Domain: <DOMAIN>

Assume zero prior chat context.

Read fully before planning:
- docs/product/README.md
- docs/product/PRODUCT_RESTORE_MASTER_PLAN.md
- docs/product/SCREEN_SPEC_TEMPLATE.md
- docs/product/PRODUCT_SCREEN_MAP.md
- docs/product/PRODUCT_RESTORE_TRACKER.md
- approved PRODUCT-UX-FOUNDATION-01 document(s)
- current implementation/files for this screen
- relevant repositories/domain models/permissions/tests
- directly related screen specs if they already exist

Verify current origin/main.

Goal:
Plan this screen in depth as a finished product screen, not as a cosmetic rewrite of the current rudimentary UI.

Work through:
- user jobs
- information hierarchy
- layout/responsiveness
- complete functions/actions
- data requirements
- permissions/RLS expectations
- states/loading/errors/empty/degraded
- navigation and relationships
- search/filter/sort/forms where relevant
- shared-component reuse
- backend gaps
- test/E2E plan
- measurable acceptance criteria

Rules:
- no implementation
- do not silently invent schema/RLS/permission changes
- mark backend gaps explicitly
- follow the shared UX foundation
- challenge current UI where it is weak
- keep scope boundaries explicit

Required output:
Create/update:
docs/product/screens/<SCREEN_SLUG>.md
using SCREEN_SPEC_TEMPLATE.md.

The final status may only be APPROVED when material product decisions are resolved.
STOP.
```

---

## 4. Per-Screen Claude Code Implementation Chat

Use only after the screen spec is APPROVED.

```text
NEXIMMO — IMPLEMENT — <SCREEN_ID>

Repository: MeisnerMax/NextImmo
Approved spec:
docs/product/screens/<SCREEN_SLUG>.md

Assume zero prior chat context.

Before editing, read fully:
- docs/product/README.md
- docs/product/PRODUCT_RESTORE_MASTER_PLAN.md
- docs/product/PRODUCT_SCREEN_MAP.md
- docs/product/PRODUCT_RESTORE_TRACKER.md
- approved PRODUCT-UX-FOUNDATION-01 document(s)
- the exact approved screen spec above
- all relevant current production code and tests

Verify current origin/main and the approved wave base before creating/using the dedicated worktree/branch.

Your job is implementation, not product redesign.

1. Reconcile the approved spec against current code.
2. Report any material contradiction/backend gap before silently changing contracts.
3. Add red-first behavioral tests where appropriate.
4. Implement the smallest coherent solution matching the spec and shared UX foundation.
5. Preserve auth/AAL/RLS/security/realtime invariants.
6. Do not perform unrelated refactors.
7. Do not materially redesign shared components, schema, RLS, permission catalog or domain contracts without an explicitly approved package.
8. Run targeted tests, appropriate full tests, flutter analyze, web build and git diff --check.
9. Review the final diff for security, data-contract and cross-screen regressions.
10. Commit, push and create a PR when authorized by this chat's task.
11. Do not merge unless explicitly told to merge.

At the end report briefly:
- spec coverage
- implementation/files
- backend/shared-component gaps left separate
- Red→Green evidence
- validation
- branch/commit/PR/CI
- negative confirmations

STOP.
```

---

## 5. Shared Component Package Chat

Use when a screen plan discovers a material shared-UI dependency.

```text
NEXIMMO — SHARED UI — <PACKAGE_ID>

Assume zero prior context.
Read:
- docs/product/PRODUCT_RESTORE_MASTER_PLAN.md
- approved UX foundation
- PRODUCT_SCREEN_MAP.md
- all screen specs that require this shared capability
- current shared UI implementation/tests

Goal:
Implement exactly the shared capability required by the dependent approved specs without redesigning unrelated screens.

Requirements:
- define a stable, reusable contract
- preserve current consumers unless migration is explicitly in scope
- red-first where applicable
- migrate only the explicitly listed consumers
- validate affected screens and full suite as appropriate
- PR only; no merge unless explicitly authorized

Report dependent screens and any required follow-up before STOP.
```

---

## 6. Backend Gap Package Chat

Use when an approved screen spec requires missing data/schema/permission capability.

```text
NEXIMMO — BACKEND GAP — <PACKAGE_ID>

Assume zero prior context.
Read:
- PRODUCT_RESTORE_MASTER_PLAN.md
- PRODUCT_SCREEN_MAP.md
- the approved screen spec(s) that declared this gap
- current domain/repository/Supabase schema/RLS/permissions/tests
- relevant architecture/security docs

Goal:
Close only the explicitly documented backend gap needed by the approved product spec.

Before mutation, prove:
- current contract
- exact gap
- minimum schema/repository/RLS/permission change required
- security impact
- migration/rollback/test strategy

Do not weaken RLS or broaden permissions merely to make the UI easier.
Use Staging for remote proof before any Production consideration.
Production remains locked unless a later Production package explicitly authorizes it.

Finish with tests, migration/security evidence, PR/CI and STOP before merge unless explicitly authorized.
```

---

## 7. Wave Integration Chat

Use when a planned parallel wave has PRs ready.

```text
NEXIMMO — PRODUCT-INTEGRATION-WAVE-<N>

Assume zero prior context.
Read:
- PRODUCT_RESTORE_MASTER_PLAN.md
- PRODUCT_SCREEN_MAP.md
- PRODUCT_RESTORE_TRACKER.md
- approved UX foundation
- specs for every screen in this wave
- every PR/diff proposed for the wave

Goal:
Integrate this wave safely and prove the resulting product behavior together.

1. Verify each PR scope/CI/spec coverage.
2. Determine safe merge order and shared-file conflicts.
3. Do not merge a PR whose assumptions are stale against current main.
4. Merge sequentially only when authorized, checking main CI after each material merge.
5. Verify automatic Staging deploy on the final main SHA.
6. Run browser/cross-screen smoke tests.
7. Run wave-level E2E for navigation, permissions, shared UX and domain interactions.
8. Update PRODUCT_RESTORE_TRACKER.md with evidence-backed statuses.

Do not open unrelated architecture/security work.
Production remains locked.

End with:
- merged PRs/order
- final main SHA/CI/staging
- cross-screen findings
- E2E result
- remaining blockers
- wave PASS/BLOCKED/FAIL
STOP.
```

---

## 8. Continuation prompt when a planning chat runs out of context

Use this instead of trying to summarize the entire project manually.

```text
NEXIMMO — CONTINUE <PACKAGE_OR_SCREEN_ID>

This is a new chat with zero prior conversational context.
The repository is the source of truth.

Read first:
- docs/product/PRODUCT_RESTORE_MASTER_PLAN.md
- docs/product/PRODUCT_SCREEN_MAP.md
- docs/product/PRODUCT_RESTORE_TRACKER.md
- the relevant approved/draft spec under docs/product/screens/
- any package-specific handoff/status file named by that spec
- current relevant code

Verify current origin/main.

Continue only from the evidence/status written in those repo artifacts. Do not reconstruct decisions from guesses or reopen completed work without a concrete inconsistency.

Current requested task:
<TASK>
```

---

## Prompt maintenance rule

Do not paste the whole history of NexImmo into every new chat. Keep these start prompts short by placing durable context in the repo.

When project-wide facts change materially, update the Master Plan / Screen Map / Tracker rather than expanding every prompt.
