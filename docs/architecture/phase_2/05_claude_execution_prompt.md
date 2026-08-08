# Phase 2 Execution Prompt (for Claude Code)

This is a ready-to-paste prompt for a Claude Code session tasked with executing the Phase 2 plan. It is self-contained — a session with no memory of the planning conversation can start from just this file plus the repo.

---

## PROMPT — paste as-is into a new Claude Code session on this repo

You are executing Phase 2 of the NexImmo enterprise rebuild: extending Supabase to every remaining domain and rebuilding every screen to a professional standard. The full plan already exists — **do not re-plan it, execute it.**

### Before doing anything

1. Read `CLAUDE.md`, then `docs/architecture/phase_2/00_phase_2_charter.md` through `04_screen_redesign_wave_plan.md` in full. These five files are the plan; everything below tells you *how* to work through it, not *what* to build.
2. Read `docs/architecture/phase_0/00_phase_status.md` to see what's actually done vs. planned right now — the plan documents describe the target, this file describes current reality. Trust the status file over your assumptions.
3. Determine the next undone item: the next incomplete `P2-D0x` in `01_domain_expansion_backlog.md`, or if all backend items for the current wave are done, the next screen group in `04_screen_redesign_wave_plan.md`.
4. State in one message which item you're starting and why it's next (dependency order), then proceed to the mandatory pre-change plan below. Don't ask permission to start the next planned item — only stop for the checkpoints listed below.

### Mandatory pre-change plan — never start implementing cold

For **every** work item (a `P2-D0x` backend slice, a single screen, even a focused refactor inside `02_architecture_modernization_backlog.md`), write a short plan **before** touching files, and show it in your response before the first `Edit`/`Write` call:

- **Function plan**: what the contract/behavior must be when done (ports, states, invariants, acceptance criteria) — pull this from the relevant backlog entry, don't invent new scope.
- **Design plan**: for screens, fill in the six-point template from `03_design_system.md` (Zielbild, Layout, States, Data density, Interactions, Debt resolved) using that wave's detail document; for backend items, name which existing `P1-*` item you're mirroring and what differs.
- Keep this plan short (a few bullets, not an essay) — its job is to catch a wrong approach before code is written, not to restate the whole backlog entry.
- Only write this plan once per work item, not once per file touched within it.

### Working order (do not reorder)

Within a domain: schema migration → pgTAP tests → rollback test → repository contract (`domain/application/data`) → adapters (legacy + Supabase) → adapter tests → real local client integration test → realtime invalidation → CI wiring → **only then** the screens that depend on it, per `03_design_system.md`'s template.

Across domains: follow the dependency order in `01_domain_expansion_backlog.md` exactly (`identity_access` → `contacts_parties` → `documents_compliance` → `platform_audit_jobs` → `leasing_operations` → `maintenance_capex` → `valuation_transactions` → `finance_debt` → `reporting_analytics`). Do not start a domain whose dependencies aren't done, even if it looks easy in isolation.

Before starting a new wave's screens (Wave 2 onward per `04_screen_redesign_wave_plan.md`), write that wave's detail document (`04a_wave2_....md` etc.) first, using the two worked examples in `04_screen_redesign_wave_plan.md` as the quality bar — then implement from it.

### Model, effort and delegation choices

Pick deliberately, don't default to one setting for everything:

- **Schema/RLS design, migration authoring, module-contract decisions, and anything touching money/audit/versioning semantics** — do this yourself with high reasoning effort. These are the highest-blast-radius files in the repo; a cheap pass here creates the exact kind of debt this whole plan exists to remove.
- **Research before touching unfamiliar code** ("where else is this repository used", "what already exists for X") — delegate to an `Explore` agent rather than manually grepping across many turns. Give it a specific, scoped question, not "look at the codebase."
- **Independent, well-specified mechanical work** (porting one already-designed screen to `nx_*` components once the pattern is proven on the wave's worked example, writing repetitive adapter test cases from a known template) — delegate to a `general-purpose` agent per unit of work so it doesn't consume your main context, especially once several screens in a wave are unblocked at the same time and don't depend on each other.
- **Verification before marking anything done** — after implementing a vertical increment, either re-run the full check yourself or spawn a review pass (a fresh agent re-reading the diff against this wave's acceptance criteria) before updating status docs. Don't self-certify without re-checking against the written acceptance criteria.
- **Full multi-agent orchestration (the `Workflow` tool)** is available but is **opt-in only** — do not invoke it unless the user in this session explicitly asks for a workflow or says "ultracode". Default to direct work plus the `Agent` tool for the delegation described above.
- Match the size of delegation to the size of the task: a one-file mechanical edit doesn't need an agent at all; a "redesign these 6 independent screens using the established pattern" does.
- **Default to spawning a subagent whenever a sub-task has a clean, self-contained brief** — research, one independently-specified screen/adapter, or a verification pass. This keeps your own context free for orchestration and cross-item judgment instead of filling up with file contents you only needed once. Write each subagent brief so it stands alone (file paths, the relevant backlog entry, what "done" means) — a vague brief produces shallow work regardless of which agent runs it.

### Token discipline

- Read only the files a given step actually needs, and read each fully before editing it (this repo's existing convention — see `AGENTS.md`) — don't re-read unchanged planning docs every turn once you've internalized them earlier in the session.
- Prefer `Edit` (diffs) over rewriting whole files with `Write`.
- Don't paste full file contents back into your own responses when a file path + line number reference suffices.
- Don't dump raw command logs; summarize pass/fail and only quote the relevant failing lines.
- Batch independent read-only lookups (Glob/Grep/Read) in parallel tool calls instead of sequentially.
- Long-session compaction happens automatically in this harness — don't try to manually manage it. But don't rely on it to preserve state either: as long as `00_phase_status.md` (or `00_phase_2_status.md`) is kept current after every completed item, no session — compacted, fresh, or handed off — has to reconstruct progress from conversation history.

### When the session gets heavy — hand off instead of pushing through

Watch for the signs of a session that's run long: many completed items, a lot of accumulated tool output, or you noticing responses getting slower/context feeling crowded. When that happens, don't try to cram the remaining work into the same session. Instead, proactively:

1. Finish and verify the current work item first — don't hand off mid-edit.
2. Make sure `00_phase_status.md`/`00_phase_2_status.md` reflects everything done so far.
3. Write a fresh, self-contained handoff prompt (a few sentences: which wave/domain is active, what's the very next item, any in-flight decision the user hasn't confirmed yet) and give it to the user, telling them to paste it into a new session — new sessions start with a full context budget and re-read the plan docs cold, which is cheaper and more reliable than continuing in an increasingly compacted one.
4. This execution prompt itself is always a valid handoff prompt on its own (it's dependency-order-aware and reads current status from the repo) — only write a custom addendum if there's session-specific context (an open question, a partially-explored option) that isn't yet captured in the repo's own docs.

### Verification gate before calling anything "done"

For a backend item (`P2-D0x`): local `supabase start` → migration reset → `db lint` → security/performance advisors → `supabase test db` → the new rollback test → the new real local client integration test (mirror `tool/verify_p1_007_integration.ps1`'s shape) → `flutter analyze` → `flutter test`.

For a screen item: `flutter analyze` clean, targeted widget tests for all mandatory states from `03_design_system.md`, responsive check at 390×844 / 1024×768 / 1440×900, and a manual pass in the running app (see `run` skill / browser tooling) confirming the golden-path workflow actually works, not just that it compiles.

Update `docs/architecture/phase_0/00_phase_status.md` (or a new `docs/architecture/phase_2/00_phase_2_status.md` if you prefer to keep Phase 2 status separate — pick one and stay consistent) with the same evidence-based style already used there, after each completed item — this is how the next session (or the next wave) knows what's actually true without re-deriving it.

### Hard stops — ask the user before proceeding

- Before any remote/staging Supabase provisioning (blocked on `DEC-015`..`017` — don't do this even if it would make a step easier).
- Before resolving any item in `docs/architecture/phase_0/11_decision_register.md` marked `open`, or any `OPEN-*`/`OPN-DOM-*` item — propose the documented default assumption and get explicit confirmation rather than silently deciding.
- Before deleting any legacy table, file, or V1 UI path (`MOD-CLEAN-*`, `remove_candidate` items) — confirm the parity test actually passed and ask before the delete, per this repo's general safety rules around destructive actions.
- At the boundary between waves — give a short summary of what's done and verified, and what's next, and let the user redirect priorities before you continue into the next wave. Don't silently execute all 8 waves back to back across sessions without check-ins.
- If you discover the plan itself is wrong (a domain contract in `05_target_module_contracts.md` doesn't fit reality, a screen's actual current behavior differs from `01_system_inventory.md`) — stop and flag it rather than quietly improvising a different design. The plan docs should get corrected, not silently bypassed.

### Definition of done (per vertical increment, unchanged from Phase 1)

Implementation and tests committed together; server-side authorization and negative tests included; migration dry run and rollback documented; audit/concurrency behavior verified; no regression in local SQLite mode until its migration gate is approved; changed architecture artefacts (the `phase_2` docs, `00_phase_status.md`) updated in the same increment, not as a follow-up.

---

## Notes for the human running this

- This prompt assumes a fresh Claude Code session per wave (or per few work items) rather than one unbroken session across all of Phase 2 — context compacts automatically on long sessions, but starting each wave fresh with "read the phase_2 docs" keeps the executing session grounded in the current written state rather than conversational memory.
- The executing session will itself tell you when it's getting heavy and hand you a fresh prompt to paste into a new session (see the hand-off rule above) — that's expected, not a failure; take it and start a new session.
- If you want heavier parallelization for a specific wave (e.g. several independent screens at once), say so explicitly when you start that session — that's the trigger for the `Workflow` tool the prompt above deliberately doesn't invoke on its own. Note that the prompt already tells the session to spawn ordinary subagents liberally for self-contained sub-tasks; the `Workflow` opt-in is only for large fan-out orchestration beyond that.
- Re-run this same prompt text for every subsequent wave; it's dependency-order-aware and will pick up wherever the status doc says the project actually is.
