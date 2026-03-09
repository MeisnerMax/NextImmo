# NexImmo Figma-like Structure V2

## 1. Global Frame Tree
```text
App
├─ Foundations
│  ├─ Colors (Light, Dark)
│  ├─ Typography
│  ├─ Spacing / Radius / Elevation / Icons
│  └─ Accessibility Rules
├─ Components
│  ├─ Shell
│  │  ├─ AppShell
│  │  ├─ Topbar
│  │  └─ Sidebar (collapsed/expanded)
│  ├─ Navigation
│  │  ├─ PageHeader
│  │  ├─ Breadcrumbs
│  │  └─ Tabs
│  ├─ Inputs
│  │  ├─ Button
│  │  ├─ TextField / TextArea
│  │  └─ Select / Dropdown
│  ├─ Data Display
│  │  ├─ Card (Standard, Interactive, KPI)
│  │  ├─ Table
│  │  ├─ Badge / Status Pill
│  │  └─ ChartContainer
│  └─ Feedback
│     ├─ EmptyState
│     ├─ Dialog
│     └─ Toast
├─ Templates
│  ├─ Dashboard Template
│  ├─ List + Filter Template
│  ├─ Detail Template
│  └─ Settings Template
└─ Screens
   ├─ Portfolio
   │  ├─ Dashboard
   │  ├─ Properties (List)
   │  └─ Property Detail
   ├─ Operations
   │  ├─ Ledger
   │  ├─ Budgets
   │  ├─ Maintenance
   │  ├─ Tasks
   │  ├─ Imports
   │  └─ Notifications
   ├─ Governance
   │  ├─ ESG
   │  ├─ Documents
   │  ├─ Audit
   │  ├─ Criteria
   │  └─ Templates
   └─ System
      ├─ Users
      ├─ Settings
      └─ Help
```

## 2. Content Grid Rules
- Desktop: 12 columns, page padding 24, max content width 1440.
- Tablet: 8 columns, page padding 16.
- Mobile: 4 columns, page padding 12.
- Gutter: 12.
- Tables: horizontal scroll below minimum readable width.
- Charts: stack vertically on narrow widths.

## 3. Template Layout Rules

### 3.1 Dashboard Template
- Row 1: KPI cards.
- Row 2: insights (charts).
- Row 3: activity/attention list.
- Priority order: operational frequency first, then analytical depth.

### 3.2 List + Filter Template
- Top: PageHeader with primary action.
- Filter bar: search + chips/dropdowns.
- Main: table/list.
- Bottom or inline: pagination.
- Empty state: guidance + next action.

### 3.3 Detail Template
- Summary header with key metadata.
- Scenario/context selector.
- Tabs for subsections.
- Main content cards/tables in sections.

### 3.4 Settings Template
- Left sub-navigation.
- Right pane grouped forms.
- Validation and save feedback always visible.

