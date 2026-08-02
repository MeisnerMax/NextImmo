# Phase 2 Design System — "Liquid Enterprise"

Status: `adopted (tokens + core components)`. Governs the design plan half of every screen entry in
`04_screen_redesign_wave_plan.md`.

Supersedes the earlier "calm, warm-neutral / Claude.ai register" direction, which was `proposed` and
never applied beyond the token table. Source of truth for the visual language is the user-authored
Stitch asset suite (`code.html` + reference screenshot). Where that asset's YAML frontmatter
disagrees with its own markup — it describes a neutral-grey/lavender theme while the markup and
screenshot are navy/cyan — **the markup and screenshot win**; the frontmatter is a generator
artifact and is not authoritative.

## Starting Point, Not Blank Page

`lib/ui/theme/app_theme.dart` already had a real token system worth keeping: `AppColorTokens`,
`AppTypographyTokens`, `AppSpacing`, `AppLayout`/`AppBreakpoints`, `AppSemanticColors` as a
`ThemeExtension`, density modes (comfort/compact/adaptive), and a component library under
`lib/ui/components/`. This is retained per `FTR-067` — Liquid Enterprise changed the *values* and
added depth tokens, not the structure.

**The actual problem is not the tokens — it's inconsistent application.** Many of the 65 screens
predate or bypass this system, building ad hoc `Row`/`Column`/`Container` layouts with hardcoded
colors instead of the `nx_*` components. Phase 2's design work is therefore: (1) the token/identity
change below, and (2) **strict, universal application** to every screen — which is where most of the
visible quality gap actually gets closed.

## Aesthetic Direction

Glassmorphic-Industrial. A deep-space canvas, translucent panels, and depth built from luminance
rather than shadow — a heads-up display for high-stakes asset decisions, adapted for a dense
desktop business app.

| Aspect | Direction |
|---|---|
| Canvas | Deep Midnight Navy `#020617`, panels `#0F172A`/`#1E293B` |
| Accent | Action Cyan `#22D3EE` — primary actions, active states, selection. Solid cyan fill with near-black text for primary buttons |
| Status | Emerald `#10B981` / Amber `#F59E0B` / Red `#F87171` |
| Typography | Hanken Grotesk (headlines), Inter (UI/body), JetBrains Mono (IDs and financial values) |
| Elevation | Translucent fill + hairline stroke + top-edge inner highlight. **No drop shadows and no glow** |
| Shape | 8px containers, 6px inputs (deliberately sharper/more technical), pill status chips |
| Density | Maximum data density: 8px vertical padding in lists/tables, background alternates instead of divider lines |
| Selection | A left "bracket" (vertical cyan bar), not an enclosing fill |

### Two deliberate departures from the source design

1. **`#64748B` is not a text color.** The source uses it for breadcrumbs, placeholders and muted
   labels; on the navy canvas that is **4.24:1**, below WCAG AA for body text. Muted text is
   slate-400 `#94A3B8` (**7.9:1**). `#64748B` remains acceptable for non-text affordances only.
2. **Light mode survives.** Dark is the leading identity and where the design is fully expressed;
   light keeps the same structure, layout, typography, shapes and density but drops glass and glow.
   Light's accent is cyan-700 `#0E7490` (5.1:1 on white), not Action Cyan — `#22D3EE` on white is
   ~1.9:1 and unusable. Light was retained rather than removed because the app has 65 screens,
   golden coverage in both brightnesses, and working light/dark plumbing; removing it buys nothing.

## Depth tokens and the glass policy

`AppSemanticColors` carries three depth tokens beyond the semantic colors: `glassFill`,
`glassStroke`, `innerHighlight`.

**There is no glow.** The source design specified an Action Cyan bloom on primary buttons, hovered
panels and selected items; it was removed on the author's call after seeing it in the running app.
Depth now comes from the fill/stroke/highlight triplet alone, hover is signalled by the stroke
shifting to the accent, and `ElevatedButton` is `elevation: 0`. Do not reintroduce a colored
`BoxShadow` — this is a deliberate decision, not an omission.

**No drop shadows either.** Three screens (`tenants`, `units`, `leases`) had independently grown the
same selected-row drop shadow plus two hardcoded hex fills behind a `Brightness` check. All three
are on tokens now.

**Real `BackdropFilter` is restricted to `NxGlassPanel`** — shell chrome (sidebar, top bar), modals,
popovers, docked detail panels. Surfaces that exist once or twice and genuinely overlap scrolling
content.

**Never blur a repeating element.** Cards, list rows, table cells use `NxCard`, which produces the
same look from an alpha-blended fill plus a top-edge inner-highlight gradient. Every
`BackdropFilter` forces a `saveLayer` and a framebuffer re-read; dozens in a dense grid is the
difference between a smooth and a stuttering web build — and `flutter build web` is a CI gate.
Against a flat canvas the cheap treatment is visually equivalent.

## Typography

Three bundled families under `assets/fonts/` (all SIL OFL 1.1, license texts ship alongside).
Bundled rather than CDN-loaded because the app is offline-first.

- **Inter** — base `fontFamily`, static instances at 400/500/600/700, so `fontWeight` resolves
  natively everywhere.
- **Hanken Grotesk** — headlines only (`displaySmall`, `headlineSmall`, `titleLarge`). Ships as a
  **variable** font. Flutter does not map `fontWeight` onto a variable font's `wght` axis, so the
  weight comes from `fontVariations` in the text theme. This is contained because headline styles
  are defined in exactly one place; **do not** introduce Hanken Grotesk into per-screen `TextStyle`s,
  where the weight would silently collapse to the default instance.
- **JetBrains Mono** — `context.dataMonoStyle`, for technical IDs and financial values. Use where
  the user compares figures vertically; never for prose.

`labelMedium` carries `0.05em` tracking in the token itself — uppercase-with-tracking is how this
system marks metadata as distinct from content, so screens must not re-apply it ad hoc.

## Charts

Multi-series charts use `AppChartPalette.series` — a fixed five-slot categorical order, assigned by
entity and **never cycled**. Beyond five categories the tail folds into "Sonstige" or the chart
becomes small multiples; a sixth generated hue is not an option, because the set was solved for
exactly five.

- **Colour follows the entity, never its rank or its state.** A bar must not repaint itself when it
  crosses a threshold — that encodes state in the slot reserved for identity, and the state is
  already carried by a chip or badge next to it.
- **Status colours are not series colours.** The amber slot is yellow-700, deliberately one step off
  the warning token.
- **One axis.** Never two y-scales; use two charts or index to a common base.
- **Text wears text tokens, not the series colour.** Values and labels stay in
  `bodySmall`/`labelMedium` with the mono face for figures; the swatch beside them carries identity.

The palette was verified with the dataviz validator across **all pairs** (legends show every series
simultaneously, so adjacent-only checking is insufficient) against both surfaces. Re-run it before
changing any value — violet-next-to-blue and teal-next-to-cyan both looked fine and were rejected on
measurement: ΔE 1.3 under deuteranopia and 6.9 under normal vision respectively.

This supersedes the source design's "lines use a cyan-to-emerald gradient" note, which describes a
single-series accent and says nothing about separating categories.

## Mandatory Component Usage

Every screen touched in `04_screen_redesign_wave_plan.md` must use, not re-implement:

- `NxPageHeader` for the screen title/actions row — no custom `AppBar`-like `Row` per screen.
- `NxBreadcrumbs` for every breadcrumb trail. This exists because `detail_template.dart` had forked
  its own slash-joined variant, which drifted the moment the header changed — the canonical example
  of why the rule below matters.
- `NxContentFrame` / `ResponsiveConstraints` for outer page layout and max-width behavior.
- `NxCard` / `NxFormSectionCard` for grouped content — no bare `Container` with manual
  border/radius, and no hand-rolled glass.
- `NxGlassPanel` for chrome and overlays only (see the glass policy above).
- `NxDataTableShell` for any tabular data — one table shell used everywhere is the single
  highest-leverage consistency fix in this app.
- `NxEmptyState` for every empty condition — no bare blank area, no raw "No data" `Text`.
- `NxStatusBadge` for every workflow status (`STM-*` states) — consistent color/shape mapping across
  all screens, not per-screen ad hoc chips.
- `SaveStatusIndicator` for every autosave/debounce interaction.
- `CommandPalette` stays the single search/quick-navigation entry point (`DEAD-001`,
  `MOD-CLEAN-005`).

If a screen's needs genuinely don't fit an existing `nx_*` component, extend the component (and its
tests) once — don't fork a one-off variant inline in the screen file.

## Mandatory Layout Audit (run before touching any screen)

Applying the tokens re-skins a screen; it does not fix its **structure**. Properties proved this:
after the tokens landed it had correct colors, fonts and shapes and still read as cluttered. Every
screen therefore starts with this audit, and the findings go into its wave-plan entry before any
code is written.

The checks below are not generic advice — each one is a defect that was actually found on the
properties screen and is likely repeated elsewhere.

1. **Do sibling elements share one structure?** The KPI row had one tile crammed with two figures
   (`value / value`) at one type size and three tiles with a single figure at another. Siblings must
   share a fixed skeleton — here label / value / context — even when a slot is empty.
2. **Is any text auto-scaled?** `FittedBox(fit: scaleDown)` around a value lets every tile settle at
   a different optical size, which is the single biggest source of "looks ragged". Fix the size and
   ellipsis instead.
3. **Is status carried by color on the value?** Three differently-colored numbers side by side read
   as three simultaneous alarms and burn the accent. Status belongs on a dot, chip or bracket next
   to the label; the value stays neutral. Sign-carrying figures (cashflow ±) are the exception.
4. **Are figures in the mono face?** Money, percentages, IDs, counts and dates in tables use
   `context.dataMonoStyle`. Prose does not.
5. **Does any media element dictate the layout?** A 1:1 cover in a ~320px card produced ~590px
   tall tiles. Media is landscape (16:9) in list contexts and never the tallest thing in a card.
6. **Are grid cells sized by aspect ratio?** A ratio has to be re-guessed per breakpoint and still
   yields a different card height at every width. Use `SliverGridDelegateWithMaxCrossAxisExtent`
   with an explicit `mainAxisExtent` — one card height everywhere, more columns as space allows.
7. **Does every full-width band actually span the content?** The filter bar shrink-wrapped and sat
   in the left third with two thirds dead space. Bars that filter or summarise a region span it,
   with secondary context right-aligned.
8. **Do tables use lines or alternates?** Divider lines plus zebra is noise; the system uses
   background alternates and `dividerThickness: 0`.
9. **Does content fill the viewport?** Check for a large dead band under the content at 1440×900.
   `scrollable: true` with `expandContent: false` leaves the page looking unfinished when the list
   is short.
10. **Is the information order right?** State what the screen is about before how it is filtered:
    header → portfolio-level context → filters → content.

Record the answers in the screen's wave-plan entry under "Layout", then implement. A screen is not
done when it compiles in the right colors.

## Mandatory Screen States

Every screen/panel gets an explicit, designed treatment for each state that applies to it — no state
may fall through to a default Flutter error screen or a blank frame:

| State | Requirement |
|---|---|
| Loading | skeleton or scoped spinner matching the eventual layout, never a full-page blocking spinner for partial data |
| Empty | `NxEmptyState` with a specific next action, not a generic "nothing here" |
| Error (infrastructure) | retry action, no raw exception text shown to the user |
| Forbidden | explicit "you don't have access" state distinct from empty/error (mirrors `PropertyRepositoryFailureKind.forbidden`) |
| Version conflict | explicit conflict UI showing both versions and a resolve action, not a silent overwrite or silent failure (mirrors `PropertyVersionConflict`) |
| Offline/legacy-adapter blocked | for domains mid-migration, an explicit "read-only until migrated" notice rather than a mutation that silently no-ops |

## Layout and Responsiveness

Carry forward unchanged (already correct and tested):

- Breakpoints: mobile ≤767, tablet ≤1199, desktop above, via `AppBreakpoints`/`AppLayout`.
- No fixed widths/heights that break on small viewports; wrap wide `Row` children in
  `Expanded`/`Flexible`/`Wrap`; scroll targeted regions, not whole screens in one
  `SingleChildScrollView`.
- Wide tables get horizontal scroll containers with the identifying column pinned where feasible.
- Every redesigned screen is checked at 390×844 (phone), 1024×768 (tablet), 1440×900 (desktop).

One Liquid-Enterprise-specific constraint: the source design sets navigation labels at **10px**
uppercase. That is desktop-only sizing — do not carry it below the desktop breakpoint.

## Motion

- Use Flutter's default Material motion curves; do not add custom animation choreography.
- The one system-specific motion rule: hovering an interactive panel intensifies its glow/stroke
  ("responsive glass"). This is a 120ms property animation, not choreography.
- Reserve other motion for state transitions that need it (dialog open/close, list reordering,
  save-status pulse) — no decorative animation on static content.
- Respect reduced-motion platform settings where Flutter exposes them.

## Accessibility

- Text contrast: minimum WCAG AA against its surface in **both** brightnesses — verify when
  adjusting any token. See the two departures above; contrast is why both exist.
- All interactive elements keyboard-reachable and focus-visible (desktop-first app).
- No color-only signaling: the cyan selection bracket always pairs with a text/weight change, and
  every `NxStatusBadge` pairs color with a label.
- Tooltips explain non-obvious derived financial fields (LTV, DSCR, IRR).

## UX Copy / Tone

- Plain, direct, professional — keep precise financial/real-estate terminology where the audience
  expects it (DSCR, LTV, NOI stay; internal code terms like `entity_id` never reach UI copy).
- Error messages state what happened and what to do next; never surface raw exception strings.
- Empty states name the next concrete action ("Add your first property", not "No properties").

## Status

**Done**
- Token tables, depth tokens, shape scale, bundled typography (`app_theme.dart`, `pubspec.yaml`).
- `NxCard`, `NxGlassPanel`, `NxBreadcrumbs`, `NxPageHeader`, `NxStatusBadge`, `NxActionToolbar`,
  `ListFilterBar`, and the shared `dataTableTheme` density (8px rows, no dividers).
- Reference slice (`lib/features/reference_slice/`) rebuilt on the system as the proof screen:
  bracket selection, zebra rows, mono postal codes. Goldens regenerated in both brightnesses at all
  three breakpoints.
- **Properties (list view)** — first screen through the layout audit. Fixed: KPI tile structure and
  status-on-dot, mono figures, 16:9 cover, fixed-height grid cells, full-width filter bar with
  result count, table density.
- **Tenants overview** (`tenants_screen.dart`, the building detail view) — second screen through the
  audit. Fixed: whole-page `SingleChildScrollView` replaced by a scrolling list pane, fixed 420px
  column replaced by a 4:6 split, 190px KPI tiles replaced by a full-width band, primary action
  lifted out of the filter strip into a title row, bracket selection (the 5px left bar had been
  spent on *status*, leaving selection to be signalled by fill + border + drop shadow using two
  hardcoded hex colors behind a `Brightness` check), per-row third line folded away, `Colors.red`
  and `Colors.orange` replaced by tokens, and a raw-exception error state in
  `tenant_detail_screen.dart` replaced by `NxEmptyState` with retry.
- `NxKpiTile` / `NxKpiRow` / `NxKpiTileSkeleton` extracted — the KPI tile had been forked **five**
  times (portfolio header, tenants overview, units, budget, `lib/ui/widgets/kpi_tile.dart`), each
  drifting differently. All five are migrated. `KpiTile` survives as a thin wrapper because its
  mandatory `InfoTooltip` is a real capability, not a fork; `NxKpiTile` gained `trailing` and
  `delta` to absorb it. The label is uppercased **inside** the component — leaving that to call
  sites is how half the bands ended up in sentence case.
- **Property overview** (`overview/`) — measured clean on colour (zero hex literals, zero raw
  `Colors.*`) and architecturally sound already, but its two charts drew on `colorScheme.primary`
  and `colorScheme.secondary`. The latter resolves to `#CBD5E1` in dark: a near-neutral slate that
  fails the chart palette's chroma floor, so the rent projection was rendered in grey. Both now use
  `AppChartPalette`.

**Open — properties**
- Content still does not fill the viewport at 1440×900 (`scrollable: true` +
  `expandContent: false`); a short list leaves a large dead band. Audit item 9.
- The header subtitle wraps to two lines at desktop width and reads as filler.

**Why the property-detail screens still look unmigrated**

Measured across `lib/ui/screens/property_detail/`: ~180 raw Material `Card(...)`, 68 `Color(0x…)`
literals, ~120 raw `Colors.*`, ~70 `fontSize:` literals. The tokens reach these screens, but the
screens sit on Material `Card` rather than `NxCard` and hardcode type and colour on top. Worst
offenders by bypass count: `budget_vs_actual_screen` (135), `asset_workbook_screen` (59),
`maintenance_screen` (56), `units_screen` (38).

`cardTheme` has been aligned to `NxCard`'s fill and stroke so every raw `Card` lands close to the
system without touching each screen. The remaining gap per screen is the inner-highlight gradient
(not expressible in `CardThemeData`) plus the hardcoded colour and type — which is exactly what the
per-screen audit removes.

- **Budget vs. Ist** (`budget_vs_actual_screen.dart`, 3684 lines, 7 tabs) — third screen through the
  audit, and the one that explained the pattern: it had the **pre-Liquid-Enterprise palette baked in
  as literals** (`#2563EB`, the old primary blue; `#16A34A`, the old success green). It was not
  missing the design — it was actively rendering the previous one next to it. All 42 hex literals
  and 35 of 37 raw `Colors.*` are now tokens (`Colors.transparent` and two legitimate cases remain).
  Also: `_SummaryTile` was the *fourth* KPI fork and `_VarianceStatusChip` another status-chip fork —
  both on the shared components; the two duplicated inline chart-colour lists replaced by
  `AppChartPalette`; light-mode-only status tints (`#FEE2E2`, `#DCFCE7`) that rendered as bright
  blocks on the dark canvas replaced by token-derived tints; donut share labels moved from ~3:1
  white-on-fill into the legend.

- **Instandhaltung** (`maintenance_screen.dart`, 3947 lines) — fourth screen through the audit, and
  it confirmed the pattern is systemic: it carried `#D97706`, the *previous* warning token, plus the
  same light-only status tints. All 15 hex literals and 17 of 20 raw `Colors.*` are now tokens
  (`Colors.transparent` remains, legitimately). Two findings beyond colour:
  - A **data model owned a `statusColor` getter** with hardcoded colours. Models cannot see the
    theme, so the mapping could never follow the design system. Now `statusColorOf(BuildContext)`.
  - `_bauteilSummaryCard` took the background tint as a *separate parameter* next to the status
    colour, so the two could — and did — drift. Derived from the status colour now.

- **Einheiten** (`units_screen.dart`) — fifth screen through the audit. All 10 hex literals gone
  (including `#F9F8F5`, the *previous* warm canvas token) and 4 of 5 raw `Colors.*`. Findings:
  - `Material(color: Colors.white)` behind the tab bar painted a **white band across the top of the
    screen in dark mode**.
  - A fifth `_KpiTile` fork and a third hand-rolled status chip — both on the shared components.
  - The row signalled status **twice** (a 5px colour bar *and* the badge) while wrapping each unit
    in its own bordered card with a 10px margin, so a floor of units read as a stack of boxes. Now
    bracket-for-selection, badge-for-status, background alternates.

- **Sweep across the remaining UI** (`scenarios`, `contractors`, `lease_detail`, `tenant_detail`,
  `operations_alerts`, `asset_workbook`, `unit_detail`, `portfolio_detail`, `reports`, `offer`,
  `compare`, `lock`, …) — 80 raw `Colors.*` migrated to tokens in one pass. `lib/ui` now holds
  **zero** hardcoded colours outside `app_theme.dart` (which is the palette) and the legitimate
  `Colors.transparent` / white-on-saturated-fill cases. Fixed along the way:
  - `Card(color: Colors.white)` in the units prospect list — a white block per row on the dark canvas.
  - `Border.all(color: Colors.black12)` in the audit panel — invisible in dark.
  - A second context-free colour helper (`_severityColor` in `operations_alerts_screen`), same
    defect class as the maintenance model's `statusColor`.
  - `#2B78B8`, one last hardcoded blue in `scenarios_screen`.

  **A caution from doing it mechanically:** the sweep rewrote `Colors.green`/`Colors.orange` inside
  `AppThemeContext.semanticColors` — the extension's own fallback — into `context.semanticColors.…`,
  i.e. infinite recursion. It was caught immediately, but a blanket regex over a token accessor is
  exactly where that class of bug hides. Read the diff on `app_theme.dart` after any such pass.

**Open — tenants overview**
- Every row still carries its own "Bearbeiten" button. With the detail pane one click away this is
  redundant repetition; removing it is a behavioural change and needs a decision.
- `lib/ui/widgets/kpi_tile.dart` is the third KPI fork and has not yet been migrated to `NxKpiTile`.

**Open**
- Shell chrome (`app_navigation.dart`): sidebar and top bar still render flat; `NxGlassPanel` is
  built but not yet applied there. Sidebar *tokens* are already on the new palette.
- The remaining 64 screens, per `04_screen_redesign_wave_plan.md`.
- `NxDataTableShell` has not yet been moved to 8px row padding + background alternates.
- Golden tests do not load the bundled fonts, so they verify layout and color but **not**
  typography. Now that type is load-bearing in this system, adding a font loader to the golden
  harness would close a real gap — it will invalidate every existing golden once.
- The "Einheiten-Atlas" unit-grid screen and the two-level navigation in the source screenshot are
  **new IA/screen concepts**, not part of this design system. They need their own entry in the wave
  plan before anyone builds them.
