# NexImmo Product UX Foundation (PRODUCT-UX-FOUNDATION-01)

Status: APPROVED-FOR-PLANNING (binding for all screen specs; implementation items are listed in §18)
Basis: `main` `ca8c0f7` (2026-08-27). Verified against the actual code; file references name the authoritative implementations.

This document is the **binding UX/system spine** demanded by the Master Plan Phase A. Screen planning chats follow it; they do not re-decide anything settled here. Where this document changes an existing pattern, the older pattern is named explicitly so implementation chats know what to converge on. Security invariants (AAL/RLS/auth/storage/realtime) are out of scope and must not be touched by UX work.

## 0. Current-state findings this foundation resolves

The repo carries **three UI generations** that must converge:

1. **Reference slice** (`lib/features/reference_slice/presentation/`) — stable `Key('reference-*')` test keys, English copy, split at `> AppBreakpoints.tabletMax` with flex 5:6, conflict UX that preserves form input, the only realtime-degraded notice.
2. **Wave-2 panels** (parties, documents) — `ListFilterTemplate`/`ListFilterBar`, German copy, split at a per-file `_splitViewBreakpoint = 1200` with flex 3:2, narrow mode replaces the list with the detail (“Zur Liste”), `NxDataTableShell(loading: true)` spinner, column-chooser tables with `tabularNumericStyle`, conflict UX that discards input via modal dialog.
3. **Wave-3/4/5 panels** (leasing, maintenance, valuation) — hand-rolled toolbars (partly without `NxPageHeader`), narrow mode stacks list+detail without a back affordance, six copies of a private skeleton widget, `Icons.cloud_off_outlined` + `FilledButton` retry vs. Wave 2’s `Icons.error_outline` + `ElevatedButton`, three private KPI widgets, two private warning notices, `'__all__'` filter sentinels vs. typed nullable dropdowns.

Solid and kept as-is: the token system (`app_theme.dart`: `_Palette` single source, `AppSpacing`, `AppRadiusTokens`, `AppBreakpoints`, typography incl. `tabularNumericStyle`/`dataMonoStyle`, dark “Liquid Enterprise” identity), the `Nx*` component family, the six-phase list-state vocabulary, keyset “load more” pagination, the `ref.listen` action-feedback pattern, permission-gated navigation with fail-closed defaults, and the golden/test policy.

## 1. App shell

- **One shell:** `AppScaffold.cloud(routeTarget)` (`lib/ui/shell/app_scaffold.dart`) mounted behind `SupabaseSecurityGate`. The gate’s rule stays: only `authenticated + workspace selected + no pending TOTP enrollment` reaches the shell; everything else renders the full-screen auth/MFA/workspace surface. Screens never build their own scaffold, top bar or sidebar.
- Desktop/tablet: `Row[Sidebar, Expanded(NxContentFrame(Column[CloudTopBar, page]))]`. Mobile (`<= AppBreakpoints.mobileMax`): `Scaffold` + `Drawer(width: 320)` with `Sidebar(forceExpanded: true, drawerMode: true)` and a top bar with menu button. This structure is fixed.
- The sidebar keeps its **six groups / 23 destinations** (`appNavigationGroups`, `lib/ui/navigation/app_navigation.dart:390`) and the theme-independent dark-navy sidebar tokens (“the shell reads as the frame”). Group order and grouping are product decisions of this foundation and stay as they are; renaming/moving a destination requires a foundation amendment, not a screen spec.
- Shell chrome (sidebar, top bar) and modals are the only legitimate users of `NxGlassPanel` (real blur). Page content uses `NxCard` (gradient, no `BackdropFilter`) — this performance rule is binding.

## 2. Navigation and route hierarchy

- **State-first navigation:** in-shell navigation sets `globalPageProvider` (plus surface providers); inbound URLs are one-shot deep links resolved by `cloudRouteTargetFromName`. This stays the model for the rebuild waves.
- **URL sync is a declared gap, not a screen concern:** the browser URL does not follow in-shell navigation today, and the first sidebar navigation drops an inbound surface/propertyId. Screens must not build their own `Navigator` flows to compensate. Follow-up package: `SHELL-ROUTING-01` (URL <-> state sync, back/forward, preserved surface targets). Until it lands, every screen must remain fully reachable without a URL.
- **Route naming:** kebab-case top-level routes (`/properties`, `/rent-roll`, …) and property-scoped forms `'<route>/<propertyId>'` via the existing `*RouteFor` builders. New screens register their route in `app_navigation.dart` and their binding in `_buildCloudPage` — nowhere else.
- **Default landing:** `CloudRouteTarget.dashboard` currently lands users on a `migrationRequired` empty state. **Decision:** until the dashboard is cloud-ready, the post-login landing target is `GlobalPage.properties`. (One-line change in the initial-route fallback; listed in §18.)
- **Command palette:** disabled in cloud mode today (“Cloud-Suche noch nicht verfügbar”). Its return is `SHELL-PALETTE-01` and must filter entries by the same permission mapping as the sidebar. No screen re-implements quick-nav.

## 3. Permission-driven navigation

- The single mapping is `cloudReadPermissionForPage` (`app_navigation.dart:261`); `null` means always allowed (dashboard, help). Sidebar **hides** what the workspace’s permission set does not allow; a direct deep link to a disallowed page renders the forbidden state (`Key('cloud-destination-forbidden')`, “Kein Zugriff”). Missing workspace/permissions ⇒ empty set ⇒ fail closed. This split — *sidebar hides, direct access shows forbidden* — is the binding rule; screens never invent their own gate.
- Inside a page: **read** gates the page, **per-action capabilities** gate actions. Actions the user lacks are **disabled with a tooltip naming the capability** when they are discoverable-and-learnable (e.g. “Neue Partei” without `party.manage`), and **hidden** when they would only be noise (bulk/admin actions). The forbidden list/detail states name the missing capability in parentheses, e.g. “(maintenance.read)” — existing wave convention, now mandatory.
- Known mapping coarseness (maintenance/budgets/ledger/esg/portfolios all under `property.read`) is **frozen**: refining it means touching the permission catalog and is a dedicated backend package (`PERMISSION-CATALOG-02`), never a screen PR.
- Client gating never replaces RLS; screens must tolerate mid-session revocation (state clears fail-closed via the existing entitlement revalidation — do not fight it in the UI).

## 4. Breakpoints, widths, density

- **The only viewport scale:** `AppBreakpoints.mobileMax = 767`, `tabletMax = 1199`; `AppViewport {mobile, tablet, desktop}` via `AppLayout.viewportForWidth`. Desktop zones `>=1100 medium`, `>=1440 large`; content max width `AppLayout.desktopMaxContentWidth = 1440` (enforced by `NxContentFrame`).
- **Page padding:** always `context.adaptivePagePadding` (compact 16; otherwise 20/24/64 for mobile/tablet/desktop). Hard-coded page paddings (e.g. `EdgeInsets.all(24)` in `property_maintenance_capex_panel.dart:62`) are defects to fix on touch.
- **Split view:** the seven per-file `_splitViewBreakpoint = 1200` constants and the reference slice’s `> tabletMax` comparison are unified: **split when `width > AppBreakpoints.tabletMax`**, implemented once as `AppLayout.splitViewMinWidth` (§18). Ratio **list : detail = 3 : 2** (`Expanded(flex: 3)` / `flex: 2`); the reference slice’s 5:6 converges on rebuild.
- Component-internal breakpoints (table mobile fallback 900/640, `NxKpiRow` 640/1100, `ResponsiveConstraints.useVerticalSplit` 1024) are part of those components’ contracts and are referenced by name, not duplicated as magic numbers in screens.
- Density: `comfort/compact/adaptive` via `AppDensityConfig`; components already respond through `context.compactLayout`. Screens must not read density directly for layout decisions beyond what tokens provide.

## 5. Page header

- Every page starts with **`NxPageHeader`** (glass container: title, `NxBreadcrumbs`, optional subtitle, `trailing` for scoping controls like the workspace selector, `NxActionToolbar` with `secondaryActions` + one `primaryAction`). Wave-3/4 bare toolbars converge on this.
- Breadcrumbs mirror the sidebar group: `['<Gruppentitel>', '<Zieltitel>']`, property-scoped screens `['Objekte', <Property-Name>, '<Bereich>']`. Breadcrumbs are labels, not navigation (until `SHELL-ROUTING-01`).
- Exactly **one** `FilledButton`/`FilledButton.icon` primary action per page (typically “Neu …”), disabled (not hidden) without its capability. Everything else is `OutlinedButton`/icon in `secondaryActions`.

## 6. Lists and tables

- **Frame:** list screens use `ListFilterTemplate` (`lib/ui/templates/list_filter_template.dart`) — header, optional `contextBar`, `ListFilterBar`, content, footer, `adaptivePagePadding`. Hand-rolled `Column[NxPageHeader, …]` converges on it.
- **Table:** Material `DataTable(showCheckboxColumn: false)` inside **`NxDataTableShell`** (owns scrollbars, `minTableWidth`, loading/error/empty branches, `mobileChild` fallback). The Wave-2 table style is the standard: uppercase `labelMedium` headers, optional-column chooser (`PopupMenuButton<enum>`) where columns exceed ~6, numeric cells in `context.tabularNumericStyle`, IDs/money in `context.dataMonoStyle`, `'—'` for null, `DataRow(selected:, onSelectChanged:)` for selection.
- **Mobile fallback (`mobileChild`) is mandatory** for every primary list: a `ListTile`-based list with `chevron_right`, as in `party_table.dart:144`. Wave-3/4 tables without fallback are non-conforming.
- **Pagination:** keyset **“load more”**, never infinite scroll: an `OutlinedButton.icon(Icons.expand_more)` under the table, label “Weitere … laden” / “Lädt …”, disabled while loading. Page size ~50.
- Board/calendar layouts (leasing pipeline) are screen-specific exceptions a spec must justify; they still use tokens and the state vocabulary.

## 7. Search, filter, sort

- Filters live in **`ListFilterBar`** (glass, full-width, `Wrap`): search `TextField` first (width 180 mobile / 260 otherwise, `prefixIcon: Icons.search`), then typed dropdowns, then `trailing` for view toggles.
- **Dropdowns are typed and nullable** (`DropdownButtonFormField<T?>` with `null` = “Alle …”). The `'__all__'` string sentinel is retired; converge on touch.
- Search is client-side over loaded pages until a server search exists; a spec that needs server search records a **Backend Gap** — never an ad-hoc query.
- **“Keine Treffer” is its own state**, distinct from empty: `Icons.filter_alt_off_outlined`, copy “Keine Treffer für diesen Filter.”, action “Filter zurücksetzen”. Sort: column-header sorting only where the repository supports it; default sort documented per screen spec; no client-side sorting of partially loaded keysets.
- Filter state is screen-local and resets on workspace switch; URL persistence arrives with `SHELL-ROUTING-01`.

## 8. Detail pages

- **Split-pane detail is the default** (no route change): desktop 3:2 beside the list; narrow (`<= tabletMax`) **replaces the list** with the detail and shows a back affordance “Zur Liste” (Wave-2 pattern wins; the Wave-3/4 stacking without back affordance converges).
- Detail state vocabulary is binding: `idle` (“Wähle …”), `loading`, `notFound` (mandatory — “… wurde entfernt oder zusammengeführt, während die Liste geöffnet war.”), `forbidden` (names the capability), `error` (retry), `ready`.
- Detail loading indicator: **`LinearProgressIndicator` inside `NxCard`** (one standard; Wave 2’s `CircularProgressIndicator` converges).
- Detail anatomy: title row (name + `NxStatusBadge`), key facts as label/value pairs (`labelMedium` label, `dataMonoStyle` for identifiers/amounts), sections as `NxCard`s, activity/history last. Full-page detail routes (property detail) reuse the same anatomy inside the shell.

## 9. Tabs, sections, drawers, modals

- **Tabs** subdivide one destination into parallel sub-areas (max ~5, `isScrollable`, `TabAlignment.start`, wrapped in `NxCard` as in `documents_screen.dart:73`). Tabs never hide the primary action of the page.
- **Sections** within a page are `NxCard`s with `NxSectionHeader`; no nested cards.
- **Drawers:** only the shell navigation drawer on mobile. No content drawers/side sheets — the split pane is the detail surface.
- **Modals** (`AlertDialog`) are for create/edit forms, confirmations and focused pickers; sized via `ResponsiveConstraints.dialogWidth`; no modal opens another modal (a confirmation may follow a form submit). Everything else is inline.

## 10. Forms and validation

- Create/edit forms are **modal dialogs** returning a result object via `Navigator.pop`, driven by `GlobalKey<FormState>`; the panel calls the controller with `expectedVersion` from the loaded DTO. Shared dialogs live in `<feature>/widgets/*_dialogs.dart` (Wave-4’s inline “// --- Dialogs ---” blocks converge on touch).
- Validators return short German messages; required fields use exactly “Pflichtfeld”. Buttons: `TextButton('Abbrechen')` + `FilledButton('Anlegen'/'Speichern')`; the submit button shows progress and disables while submitting. German decimal input is parsed with the shared helpers (`lib/ui/utils/number_parse.dart`).
- **Version-conflict UX (binding, replaces the discard-dialog):** user input is never thrown away. In-dialog: the dialog stays open, shows an inline conflict banner naming the server version, offers “Neu laden” (reseeds fields, keeps nothing) and “Erneut speichern” (against the shown version). Inline forms follow the reference-slice contract (`reference_property_detail_panel.dart:64-97`): conflict keeps input and reseeds only the version. Rationale: the reference slice proved the friendlier semantics; “Deine Änderung wurde nicht gespeichert” + forced reload loses work.
- Unsaved-changes: dialogs confirm discard on close when dirty (“Änderungen verwerfen?”); inline autosave forms (inputs screen) keep using `SaveStatusIndicator` semantics.
- Server validation failures map onto fields where possible, otherwise onto the action-feedback pattern (§12).

## 11. Screen states (mandatory vocabulary)

Every list surface implements: `idle` → `loading` → `forbidden` | `error` | `empty` | `ready` (+ **no-match** when filters are active); details add `notFound`. Standardized rendering:

| State | Rendering (binding) |
|---|---|
| idle | `NxEmptyState(Icons.workspaces_outline, 'Kein Arbeitsbereich aktiv')` |
| loading | **skeleton**, not spinner: shared `NxListSkeleton` (§18) for lists; `LinearProgressIndicator` in `NxCard` for details |
| forbidden | `NxEmptyState(Icons.lock_outline, 'Kein Zugriff auf …', '… benötigt die Berechtigung (<capability>).')` |
| error | `NxEmptyState(Icons.cloud_off_outlined, …)` with retry = `FilledButton.icon(Icons.refresh, 'Erneut versuchen')` — the single retry style |
| empty | invitation copy + create-CTA gated on the mutate capability |
| no-match | see §7 |
| ready | content; background refresh never blanks visible data |

Blank full-page spinners are forbidden where useful state can stay visible (Master-Plan rule).

## 12. Status, actions, feedback

- Status is always **`NxStatusBadge`** (`neutral/success/warning/error/info`, pill, never color-only — the label carries the meaning). Domain→kind mappings live beside the domain enum (`maintenance_capex_badges.dart` is the model).
- **Action feedback (binding, existing pattern):** `ref.listen` on the controller; `conflict` → conflict handling per §10; `succeeded/forbidden/failed/readOnly` → `ScaffoldMessenger` SnackBar with the controller’s message, then `clearAction()`. No custom toast/banner systems.
- KPI values use **`NxKpiTile`/`NxKpiRow` only** (value never colored, never auto-scaled; status is the dot). The private `_Kpi`/`_KpiTile` copies converge; legacy `KpiCard`/`KpiTile` are deprecated wrappers.
- Inline warnings use the shared **`NxNotice`** (§18; consolidates `_Notice`, `_TruncationNotice`, `DocumentNotice` styling: warning-tinted container, icon, wrapped text, optional action).

## 13. Live updates and degraded messaging

- Realtime is invalidation-only; REST stays canonical. Screens consume their invalidation source through the existing debounced-reload pattern (`_scheduleInvalidationReload`); a reconnect produces one reconcile, never a burst — specs must not weaken this.
- **Degraded state:** the reference-slice notice (`Key('reference-live-updates-degraded')`) is generalized as **`NxLiveUpdatesNotice`** (§18): passive container under the page header — `NxStatusBadge('Paused', warning)` + one sentence (“Live-Updates sind vorübergehend unterbrochen. Die Seite bleibt nutzbar und holt Änderungen automatisch nach.”), max 2 lines, non-blocking, self-clearing on the next reconcile. No dialogs, no provider/channel details, no sign-out. Wiring per domain follows each screen’s rebuild (controllers must surface their degraded flag the way `ReferenceSliceState.liveUpdatesDegraded` does — small per-domain follow-ups, not silent screen-PR changes).

## 14. Destructive confirmations

- Destructive = irreversible or hard to reverse (archive with data loss, delete, merge, end-role, unenroll). Always an `AlertDialog`: title names the action, body names the **object by name** and the consequence in one sentence, confirm button is `FilledButton` in error color with the verb (“Archivieren”, “Löschen”, “Zusammenführen”), cancel is `TextButton('Abbrechen')`. Never a SnackBar-undo as substitute, never double-modals. High-risk merges may require typing nothing extra — the named object in the copy is the guard (keep dialogs fast; the audit trail is server-side).

## 15. Responsive and platform rules

The AGENTS.md checklist stays binding, in short: no fixed widths/heights that break small screens; `Row`s with wide children wrapped in `Expanded/Flexible/Wrap`; explicit text overflow; targeted scroll regions (never whole-page `SingleChildScrollView` — `ListFilterTemplate.scrollable` exists for genuinely short pages); wide content scrolls inside its own container (the table shell does this). Desktop stays “professionell und breit” (content capped at 1440), mobile stacks vertically. Every screen spec declares behavior for the three golden viewports **390×844, 1024×768, 1440×900** plus the 320-width floor (no overflow), light and dark.

## 16. Accessibility baseline

- Contrast via tokens only (palette is AA-audited; e.g. `darkTextSecondary` was lifted for AA — do not reintroduce raw hex).
- Touch targets ≥ 44px on mobile (Material defaults; don’t shrink hit areas in dense tables below `dataRowMin`).
- Icon-only buttons carry `tooltip`; images/status carry text labels (badge text, not color, is the signal).
- Keyboard: dialogs trap focus, `Escape` cancels, `Enter` submits single-field forms; the palette’s Shortcuts/Actions pattern is the model. Focus lands on the first field when a dialog opens.
- Semantics: interactive rows expose their name (DataRow content is text-first); decorative glass layers stay out of the semantics tree.

## 17. Test keys and shared-component rules

- **Key convention (binding):** every interactive element and every state container gets a stable `Key('<screen>-<element>')` (kebab-case), like the reference slice. Widget tests bind to keys, never to German copy. Golden policy stays: six reference goldens, Linux-only, regenerated via the `goldens/**` workflow.
- **Ownership:** `Nx*` components, templates, tokens and this document belong to the foundation. Screens use them freely; small backwards-compatible extensions may ride a feature PR only if generic, tested, low-conflict; anything else is a `SHARED-UI-*` package (Master Plan §7). No screen introduces a second design language, a new color, radius, spacing, breakpoint or font outside the tokens.

### Component disposition (keep / change / remove)

| Component | Disposition |
|---|---|
| `NxCard`, `NxGlassPanel`, `NxPageHeader`, `NxSectionHeader`, `NxBreadcrumbs`, `NxActionToolbar`, `NxContentFrame`, `NxEmptyState`, `NxStatusBadge`, `NxKpiTile`/`NxKpiRow`, `NxDataTableShell`, `NxChartContainer`, `NxFormSectionCard`, `ListFilterTemplate`/`ListFilterBar`, `ResponsiveConstraints`, `SaveStatusIndicator`, `CommandPalette` (local mode) | **keep** (authoritative) |
| Wave skeleton copies, `_Kpi`/`_KpiTile` privates, `_Notice`/`_TruncationNotice`, `'__all__'` sentinels, per-file `_splitViewBreakpoint`, hand-rolled toolbars, stacked narrow detail | **change** — converge on §§4–13 as screens are rebuilt |
| `lib/ui/widgets/status_badge.dart` (color-matching wrapper), `kpi_card.dart`/`kpi_tile.dart` (after consumers migrate), `data_table_widget.dart`, unused `currency_field.dart`/`percent_field.dart`, dead `AppElevationTokens` | **remove** (deprecated now; deletion rides the wave that migrates their last consumer) |

## 18. Foundation implementation backlog (Wave-1 candidates; NOT part of this planning package)

1. `NxLiveUpdatesNotice` — extract from the reference slice; parameterized copy. |
2. `NxListSkeleton` — the one list skeleton (n rows × height, `surfaceAlt`). |
3. `AppLayout.splitViewMinWidth` + a small `NxSplitView` helper (3:2, narrow replace-with-back). |
4. `NxNotice` — shared inline warning/info container. |
5. Error/retry standardization sweep (icon + `FilledButton.icon` retry). |
6. Default landing → `GlobalPage.properties` (initial-route fallback). |
7. Key-convention retrofit rides each screen rebuild, not a big-bang sweep. |

Separate follow-up packages (own approval): `SHELL-ROUTING-01` (URL sync/back/forward), `SHELL-PALETTE-01` (cloud command palette with permission filtering), `PERMISSION-CATALOG-02` (finer capability mapping — backend), per-domain degraded-flag wiring, dashboard cloud migration (P2-D09).

## 19. Open decisions

- Product language of record is **German** for all user-facing copy (the reference slice’s English copy converges when that surface is rebuilt as the Properties screen); code, keys and docs stay English. — decided here, listed for visibility.
- Dashboard content (what the cloud dashboard shows) — Phase C planning, blocked on P2-D09.
- Whether `adminUsers`’ members surface stays a reference-slice screen or gets a rebuilt admin area — Phase B screen map decides.
- Tenants’ URL-only reachability (`/tenants` without sidebar entry) — Phase B decides sidebar placement.

## 20. Amendments

- **AMD-001 (2026-08-28, beschlossen mit `ADMIN-MEMBERS-V2`):** Sidebar-Destination `GlobalPage.adminUsers` wird von „Benutzer" auf **„Mitglieder"** umbenannt (Label + Titel in `appNavigationGroups`; `routeKey` `setup_administration.users`, Route `/members`, Permission-Mapping und Gruppenzuordnung unverändert). Implementierung reitet auf Paket A1 von `ADMIN-AREA-01` (`docs/product/screens/admin_members.md`).

---

*Screen specs cite sections of this document by number (e.g. “states per Foundation §11”). If a screen genuinely cannot follow a rule, the spec says so explicitly under Open decisions and the deviation is approved before implementation.*
