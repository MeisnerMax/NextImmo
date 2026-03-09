# UI Migration Checklist V2

## 1. Rollout Strategy
- Approach: incremental, low-risk, feature-flagged.
- Business logic: unchanged.
- Data layer: unchanged.
- Route/state contracts: unchanged.

## 2. Feature Flags
- `appShellV2`
- `dashboardV2`
- `propertiesV2`
- `propertyShellV2`

## 3. Completed Wave 1
- [x] Theme/token layer updated with light/dark and adaptive density support.
- [x] V2 shell introduced (new sidebar/topbar style).
- [x] Dashboard migrated to V2 template and components.
- [x] Properties list migrated to V2 template and components.
- [x] Property detail shell migrated to V2 structure.
- [x] Per-screen fallback path retained via feature flags.

## 4. Component Replacement Map
- Legacy page header area -> `NxPageHeader`
- Legacy card containers -> `NxCard`
- Legacy chart card wrappers -> `NxChartContainer`
- Ad-hoc empty cards -> `NxEmptyState`
- Type/status pills -> `NxStatusBadge`
- Main content frame -> `NxContentFrame`

## 5. Next Waves (Planned)

### 5.1 Operations
- [ ] Ledger
- [ ] Budgets
- [ ] Maintenance
- [ ] Tasks
- [ ] Imports
- [ ] Notifications

### 5.2 Governance
- [ ] ESG
- [ ] Documents
- [ ] Audit
- [ ] Criteria Sets
- [ ] Report Templates

### 5.3 System
- [ ] Users
- [ ] Settings
- [ ] Help

## 6. Migration Rules Per Screen
- Identify target template: Dashboard, List+Filter, Detail, Settings.
- Replace spacing/typography with tokens.
- Replace one-off surfaces with shared components.
- Ensure loading/empty/error states exist.
- Confirm keyboard navigation and focus visibility.
- Confirm no provider/repository contract changed.

