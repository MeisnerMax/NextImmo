# Phase 2 Design System — Professional Enterprise UI

Status: `proposed`. Governs the design plan half of every screen entry in `04_screen_redesign_wave_plan.md`.

## Starting Point, Not Blank Page

`lib/ui/theme/app_theme.dart` already has a real token system worth keeping: `AppColorTokens`, `AppTypographyTokens`, `AppSpacing`, `AppLayout`/`AppBreakpoints`, `AppSemanticColors` as a `ThemeExtension`, density modes (comfort/compact/adaptive), the `Geist` font, and a component library under `lib/ui/components/` (`nx_card`, `nx_data_table_shell`, `nx_empty_state`, `nx_page_header`, `nx_section_header`, `nx_status_badge`, `nx_form_section_card`, `nx_action_toolbar`, `nx_content_frame`, `nx_chart_container`, `save_status_indicator`, `command_palette`, `responsive_constraints`). This is retained per `FTR-067`.

**The actual problem is not the tokens — it's inconsistent application.** Many of the 65 screens (see `01_system_inventory.md`) predate or bypass this system, building ad hoc `Row`/`Column`/`Container` layouts with hardcoded colors and spacing instead of the `nx_*` components. Phase 2's design work is therefore: (1) a deliberate, small refinement of the tokens toward a calmer, more distinctive "impressive but simple" aesthetic, and (2) **strict, universal application** of the resulting system to every screen — which is where most of the visible quality gap actually gets closed.

## Aesthetic Direction ("Claude Design" as clarified by the user)

Target look: the calm, warm-neutral, high-clarity register associated with Claude.ai's own interface — adapted for a dense, data-heavy desktop business app, not a chat UI. Concretely, evolve the existing tokens along these lines during Wave 0 (see `04_screen_redesign_wave_plan.md`):

| Aspect | Current | Direction |
|---|---|---|
| Neutrals | Cool slate (`#F8FAFC`/`#0F172A`/`#64748B`) | Keep slate as the base but warm it slightly (reduce blue cast in `background`/`surfaceAlt`) so dense data screens feel calmer, less "generic admin dashboard" |
| Primary accent | Saturated blue `#2563EB` | Keep blue as the primary action color (it already has good contrast and is proven across 65 screens) but reserve full-saturation primary strictly for primary actions and links — everywhere else, prefer neutral surfaces + the existing `accent`/semantic colors, so pages read as calm rather than busy |
| Typography | `Geist`, w300 display down to w400 body — already a good, restrained scale | Keep; enforce it everywhere (no per-screen custom `TextStyle`s bypassing `Theme.of(context).textTheme`) |
| Elevation | `elevation: 0` cards with a hairline border | Keep — this is already the "calm/flat" direction; do not introduce drop shadows |
| Density | comfort/compact/adaptive already exist | Keep; every redesigned screen must be verified in all three, not just comfort |
| Motion | mostly implicit (Material defaults) | Add restraint as an explicit rule (below) |

This is a refinement, not a rebuild — do not propose a new color system or a new font in Wave 0 unless a screen-level review finds the current tokens genuinely insufficient (e.g. contrast failure). Changing tokens is themselves the highest-leverage, lowest-risk part of this whole plan; changing them twice would waste both tokens and review effort.

## Mandatory Component Usage

Every screen touched in `04_screen_redesign_wave_plan.md` must use, not re-implement:

- `NxPageHeader` for the screen title/actions row — no custom `AppBar`-like `Row` per screen.
- `NxContentFrame` / `ResponsiveConstraints` for the outer page layout and max-width behavior.
- `NxCard` / `NxFormSectionCard` for grouped content — no bare `Container` with manual border/radius.
- `NxDataTableShell` for any tabular data (this app has 94 tables' worth of list screens — one table shell, used everywhere, is the single highest-leverage consistency fix).
- `NxEmptyState` for every empty condition — no screen may show a bare blank area or a raw "No data" `Text` widget.
- `NxStatusBadge` for every workflow status (`STM-*` states from `02_domain_map.md`) — consistent color/shape mapping per status across all screens, not per-screen ad hoc chips.
- `SaveStatusIndicator` for every autosave/debounce interaction (already a documented pattern per `Software_Goal.txt` workflow 2).
- `CommandPalette` stays the single search/quick-navigation entry point — resolves the `SearchScreen` orphan (`DEAD-001`) by either wiring it in here or retiring it, per `MOD-CLEAN-005`.

If a screen's needs genuinely don't fit an existing `nx_*` component, extend the component (and its tests) once — don't fork a one-off variant inline in the screen file.

## Mandatory Screen States

Every screen/panel gets an explicit, designed treatment for each state that applies to it — no state may fall through to a default Flutter error screen or a blank frame:

| State | Requirement |
|---|---|
| Loading | skeleton or scoped spinner matching the eventual layout, never a full-page blocking spinner for partial data |
| Empty | `NxEmptyState` with a specific next action, not a generic "nothing here" |
| Error (infrastructure) | retry action, no raw exception text shown to the user |
| Forbidden | explicit "you don't have access" state distinct from empty/error (mirrors `PropertyRepositoryFailureKind.forbidden`) |
| Version conflict | explicit conflict UI showing both versions and a resolve action, not a silent overwrite or silent failure (mirrors `PropertyVersionConflict`) |
| Offline/legacy-adapter blocked | for domains mid-migration, an explicit "read-only until migrated" notice rather than a mutation that silently no-ops |

This list already exists for the reference slice (`AC-REF-009`) — Phase 2 makes it the standard for every screen, not just Property.

## Layout and Responsiveness

Carry forward unchanged (these are already correct and tested):

- Breakpoints: mobile ≤767, tablet ≤1199, desktop above, via `AppBreakpoints`/`AppLayout.viewportForWidth`.
- No fixed widths/heights that break on small viewports; wrap wide `Row` children in `Expanded`/`Flexible`/`Wrap`; scroll targeted regions, not whole screens in one `SingleChildScrollView` (see `AGENTS.md` and `Update_V9.1_restore.md` item 2).
- Wide tables get horizontal scroll containers with the identifying column pinned where feasible (`Update_V9.1_restore.md` item 3's Rent Roll pattern generalized to every data table).
- Every redesigned screen is checked at the three golden widths already used for the reference slice: 390×844 (phone), 1024×768 (tablet), 1440×900 (desktop).

## Motion

- Use Flutter's default Material motion curves; do not add custom animation choreography.
- Reserve motion for state transitions that need it (dialog open/close, list reordering, save-status pulse) — no decorative animation on static content.
- Respect reduced-motion platform settings where Flutter exposes them.

## Accessibility

- Text contrast: minimum WCAG AA against its surface for both light and dark tokens — verify when adjusting any token in Wave 0.
- All interactive elements keyboard-reachable and focus-visible (desktop-first app; keyboard nav is a first-class path, not an afterthought).
- No color-only signaling: every `NxStatusBadge`/semantic color pairs with a text label or icon.
- Tooltips (`InfoTooltip`, existing `tooltipTheme`) explain non-obvious fields, especially financial/derived metrics (LTV, DSCR, IRR) — every derived number should be one hover away from its formula.

## UX Copy / Tone

- Plain, direct, professional — no jargon where a plain term exists, but keep precise financial/real-estate terminology where the audience expects it (DSCR, LTV, NOI stay; internal code terms like `entity_id` never reach UI copy).
- Error messages state what happened and what to do next; never surface raw exception strings or backend error codes to the user.
- Empty states name the next concrete action ("Add your first property" not "No properties").

## Per-Screen Design Plan Template

Every screen entry in `04_screen_redesign_wave_plan.md` fills this in:

1. **Zielbild** — one paragraph, what "done" looks like for this screen for a professional customer.
2. **Layout** — which `nx_*` components, how content is grouped, what changes at each breakpoint.
3. **States** — which of the mandatory states apply and any screen-specific variant.
4. **Data density** — for table/list screens: columns shown by default vs. behind a column picker, sort/filter affordances, pagination/keyset behavior tied to the screen's `PageRequest`/`PageResult` contract.
5. **Interactions** — primary action, secondary actions, destructive actions (with confirmation per this repo's existing safety conventions), autosave vs. explicit save.
6. **Before/after debt resolved** — which `BIG-*`/`DUP-*`/`DEBT-*` entries this screen's rebuild resolves, if any.
