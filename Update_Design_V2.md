You are a senior product designer and senior frontend engineer.

Goal
Implement a complete holistic UI/UX redesign for my existing software without changing core business logic. Keep the structure general and adaptable, because the current app structure and modules may differ. The result must feel like a modern SaaS product with strong usability, consistent visual hierarchy, and a reusable design system.

Hard constraints
1) Do not break existing functionality. Keep all routes, data flows, and business logic intact unless explicitly necessary for UI integration.
2) Refactor UI in a way that is incremental and safe: migrate screen by screen and component by component.
3) Create a design system first (tokens + components), then apply it to the app shell and key screens.
4) Keep the solution general: do not assume specific module names or domain objects. Use placeholders like "Module A", "Entity", "Dashboard Widget" where needed.
5) Output concrete artifacts: token definitions, component specs, layout rules, and a migration checklist.

Phase 1 Design System Foundation
Create a complete design system with:
A) Design Tokens
- Colors: primary, secondary, accent, background, surface, border, text (primary/secondary), success, warning, error, info
- Light and dark theme variants
- Accessible contrast rules and minimum contrast targets
- Typography: H1, H2, H3, body, caption, button, monospace (optional)
- Spacing scale based on an 8px grid (include the exact scale values)
- Radius scale (e.g., 4/8/12/16)
- Elevation/shadow scale (3 to 5 levels)
- Icon sizing rules

B) Component Library
Define reusable components with structure, props, states, and interaction rules:
- AppShell (Topbar, Sidebar, MainContent)
- PageHeader (title, breadcrumbs, primary actions, secondary actions)
- Button (primary/secondary/ghost/destructive, loading, disabled)
- Input / TextField / TextArea (validation, helper text)
- Select / Dropdown
- Tabs
- Card (normal, interactive, KPI card)
- Table (sortable, filterable, pagination)
- EmptyState component
- Modal / Dialog
- Toast / Snackbar
- Badge / Status pill
- Avatar / UserMenu
- ChartContainer (layout and loading/empty states only; no chart library assumptions)
Include component states: default, hover, active, focus, disabled, loading, error.

Output for Phase 1
- A structured “Design System Spec” document format (headings + bullet rules)
- Token tables for light/dark themes
- Component specification list with rules and example usage notes

Phase 2 Information Architecture and App Layout (Figma-like structure)
Produce a Figma-style hierarchy of frames and components. Keep it generic.

A) Global Frame Structure
App
├─ AppShell
│  ├─ Topbar
│  │  ├─ Brand/Logo area
│  │  ├─ Global Search (optional)
│  │  ├─ Notification entry point
│  │  └─ User Menu
│  ├─ Sidebar
│  │  ├─ Primary Navigation (modules)
│  │  ├─ Secondary Navigation (settings/help)
│  │  └─ Collapse behavior
│  └─ MainContent
│     ├─ PageHeader
│     └─ ContentGrid

B) ContentGrid Rules
- Desktop: 12-column grid
- Tablet: 8-column grid
- Mobile: 4-column grid
Define gutters, max content width, and how cards/tables/charts adapt responsively.

C) Screen Templates (generic)
Create reusable screen templates:
1) Dashboard Template
- KPI row (cards)
- Insight row (charts)
- Activity row (tasks, recent items, alerts)
Define prioritization: frequency of use and criticality determines placement.

2) List + Filter Template
- PageHeader with actions
- Filter bar (search, chips, dropdowns)
- Table/list with pagination
- Empty state rules

3) Detail Template
- Summary header with key metadata and quick actions
- Tabs: Overview, Data/Financials, Documents, Activity (generic naming)
- Content sections with cards and tables

4) Settings Template
- Left subnav
- Form sections with validation and save patterns

Output for Phase 2
- The “Figma-like file tree” for the full app structure
- Layout rules for each template and responsive behavior

Phase 3 Apply the Design System to Existing Screens
Implement the redesign by updating the UI incrementally:

A) AppShell Migration
- Replace current navigation layout with AppShell pattern (Topbar + Sidebar + MainContent)
- Ensure current routing still works
- Add breadcrumbs and consistent PageHeader usage

B) Screen-by-screen migration plan
For each existing screen in my app:
1) Identify the closest template (Dashboard, List, Detail, Settings, Form)
2) Map current UI elements to the new components
3) Replace inconsistent spacing/typography with tokens
4) Add clear empty/loading/error states
5) Improve accessibility: focus states, keyboard navigation, contrast

C) Dashboard modernization
- Convert overview into widget-based layout
- Define widget types: KPI, chart, list, activity, status
- Add “Customize layout” option only if trivial; otherwise provide a future-ready spec

Output for Phase 3
- A migration checklist per screen (generic format)
- A component replacement map (old UI element → new component)
- A short QA plan to verify no logic broke (navigation, forms, critical flows)

Phase 4 Deliverables
Provide the following final outputs:
1) A complete design system spec (tokens + components + states)
2) Figma-like hierarchy for AppShell and all screen templates
3) Implementation steps in the order of least risk first
4) A definition of “Done” for the redesign: consistency checks, accessibility checks, responsiveness checks

Style requirements
- Use clear, modern SaaS UI patterns
- Avoid clutter, improve hierarchy, and reduce cognitive load
- Prefer reusable components over custom one-off UI
- Keep language concise and implementation-oriented

Now produce:
A) The full Design System Spec
B) The Figma-like file tree
C) The migration plan and QA checklist