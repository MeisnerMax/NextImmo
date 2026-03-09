# NexImmo Design System V2

## 1. Scope and Intent
- Goal: modernize desktop UI/UX without changing business logic, routes, repositories, or engine behavior.
- Style direction: Graphite + Teal, high information density control, clean hierarchy.
- Theme support: light + dark.
- Accessibility baseline: WCAG AA.

## 2. Foundations

### 2.1 Color Tokens
| Token | Light | Dark | Usage |
|---|---|---|---|
| `background` | `#F6F8FA` | `#0F141A` | app background |
| `surface` | `#FFFFFF` | `#161D25` | cards, panels |
| `surfaceAlt` | `#EEF2F6` | `#1E2731` | inputs, selected rows |
| `border` | `#D4DCE5` | `#2D3946` | outlines/dividers |
| `textPrimary` | `#1C2733` | `#E8EEF5` | primary text |
| `textSecondary` | `#5A6B7C` | `#B2C0CF` | secondary text |
| `primary` | `#0F5C73` | `#41A8C4` | primary actions |
| `secondary` | `#3A7E91` | `#5BB7C8` | secondary accents |
| `accent` | `#16A3A6` | `#57D2CF` | highlights |
| `success` | `#1C8C5E` | `#41B883` | positive state |
| `warning` | `#C28A1A` | `#E0A13D` | warning state |
| `error` | `#C44949` | `#E47676` | error state |
| `info` | `#2B78B8` | `#6AB0E8` | informational state |

### 2.2 Contrast Targets
- Normal text: >= 4.5:1.
- Large text (18px regular or 14px bold+): >= 3:1.
- UI boundaries/focus indicators: >= 3:1 to adjacent colors.

### 2.3 Typography Tokens
- `H1`: 32/40, weight 700
- `H2`: 24/32, weight 700
- `H3`: 20/28, weight 700
- `Body`: 14/22, weight 400
- `Caption`: 12/18, weight 400
- `Button`: 14/20, weight 600
- Optional `Monospace`: 12/18 for IDs and numeric tables

### 2.4 Spacing Scale (8px Grid)
- Scale: `4, 8, 12, 16, 24, 32, 40, 48, 64`
- Semantic aliases:
- Page padding desktop/tablet/mobile: `24 / 16 / 12`
- Section gap: `24`
- Component gap: `12`
- Card internal padding: `16`

### 2.5 Radius Scale
- `4`, `8`, `12`, `16`

### 2.6 Elevation Scale
- `0`, `1`, `2`, `4`, `8`

### 2.7 Icon Size Rules
- Default: `20`
- Dense/table: `16`
- Prominent actions: `24`
- Minimum interactive target: `40x40`

## 3. Density and Responsiveness
- Modes: `comfort`, `compact`, `adaptive`.
- Adaptive rules:
- Mobile: comfort spacing
- Tablet: medium spacing
- Desktop: compact-leaning spacing for data-heavy surfaces
- Content grid:
- Desktop: 12 columns
- Tablet: 8 columns
- Mobile: 4 columns

## 4. Component Spec

### 4.1 AppShell
- Structure: `Sidebar + Topbar + MainContent`.
- States: default, collapsed sidebar, keyboard focus on nav.
- Rules: route/state providers remain source of truth.

### 4.2 PageHeader
- Slots: title, breadcrumbs, subtitle, primary action, secondary actions, optional trailing.
- Rules: one primary action max.

### 4.3 Buttons
- Variants: primary, secondary(outlined), ghost(text), destructive.
- States: default, hover, focus, active, disabled, loading.

### 4.4 Input / TextField / TextArea
- Slots: label, helper text, error text, prefix/suffix icon.
- States: default, hover, focus, disabled, error.

### 4.5 Select / Dropdown
- States: closed, open, selected, disabled, error.
- Rules: max menu height with scroll.

### 4.6 Tabs
- Used for detail contexts.
- States: active, inactive, hover, focus.

### 4.7 Card
- Variants: standard, interactive, KPI.
- States: default, hover(interactive), selected(if applicable).

### 4.8 Table
- Supports sorting, filtering, pagination.
- Rules: sticky headers optional, horizontal scroll fallback required.

### 4.9 EmptyState
- Required elements: icon, title, short description, optional action.

### 4.10 Modal / Dialog
- Includes title, content, primary + secondary actions.
- Must support escape key and focus trap.

### 4.11 Toast / Snackbar
- Variants: success, warning, error, info.
- Auto-dismiss with optional action.

### 4.12 Badge / Status Pill
- Variants: neutral, success, warning, error, info.
- Non-interactive by default.

### 4.13 Avatar / User Menu
- Sizes: 24/32.
- States: default, hover, menu open.

### 4.14 ChartContainer
- Provides title/subtitle and state shell.
- States: loading, empty, error, ready.
- Chart library remains interchangeable.

## 5. Implemented V2 Building Blocks
- `AppTheme` token expansion with adaptive density support.
- `UiScreenFlag` feature flag layer for low-risk rollout.
- New reusable UI components:
- `NxPageHeader`, `NxCard`, `NxEmptyState`, `NxChartContainer`, `NxStatusBadge`, `NxContentFrame`.

