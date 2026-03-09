# NexImmo Technical System Documentation

## 1. System Overview

### 1.1 Purpose
NexImmo is an offline-first desktop application for real estate underwriting, portfolio operations, governance, and reporting. The system combines deterministic scenario analysis with operational modules such as ledger, budgets, leases, rent roll, maintenance, tasks, document compliance, audit, and security context management.

The application goal is to keep analysis, operations, and reporting in a single local workspace without cloud service dependencies.

### 1.2 Offline-first architecture
The runtime architecture is local by design:

- Flutter desktop client executes all UI and orchestration logic locally.
- SQLite (via `sqflite_common_ffi`) persists all data in a local single-file database.
- Generated artifacts (PDF, CSV, ZIP backups, reporting packs) are written to local file system paths.
- No external HTTP clients, API connectors, or web synchronization components are present in the core codebase.

### 1.3 Deterministic calculation philosophy
Core financial and operational engines are implemented in pure Dart modules under `lib/core`. Determinism is enforced by:

- Explicit function inputs and returned value objects.
- Canonical ordering where ordering affects hashing or diffs (for example scenario snapshots).
- Stable period key derivation (`YYYY-MM`) for aggregation logic.
- No random data in analysis engines.
- No hidden network latency or remote service calls in compute paths.

### 1.4 Desktop-first design
The primary UI shell is a desktop layout with:

- Persistent sidebar navigation.
- Topbar with contextual title and search.
- Content area switching by global and property-detail page states.

The app currently targets desktop workflow patterns and local file dialogs (`file_selector`) for import and export actions.

### 1.5 SQLite single-file architecture
Database initialization is centralized in `AppDatabase`:

- Default path: `<ApplicationSupportDirectory>/app_data.db`
- Foreign keys enabled via `PRAGMA foreign_keys = ON`.
- Versioned migration pipeline (`DbMigrations.currentVersion = 17`).
- Additive and idempotent migration pattern with `CREATE TABLE IF NOT EXISTS`, index creation, and guarded `ALTER TABLE ADD COLUMN`.

### 1.6 File system usage
Workspace path resolution creates these directories:

- `workspace/docs` for managed documents.
- `workspace/docs/exports` for mirrored export artifacts.
- `workspace/backups` for backup and pre-restore ZIP files.
- `workspace/tmp` for restore staging.

Backup ZIP archives include:

- `db/app_data.db`
- `docs/**`
- `meta/manifest.json`

Reporting pack ZIP archives include selected PDFs/CSVs and `meta/manifest.json`.

### 1.7 External dependency model
External runtime dependencies are local libraries only (Flutter framework, SQLite FFI, PDF/CSV/archive/crypto). There are no external web requests in business execution flows.

---

## 2. Architectural Principles

### 2.1 Layered architecture
NexImmo uses a layered architecture:

- `core`: pure Dart models, engines, scoring, criteria, offer solver, reports builders, security primitives, services.
- `data`: SQLite access and repository implementations.
- `ui`: state providers, screens, widgets, and shell.

This structure is enforced by import direction:

- `ui` depends on `data` and `core`.
- `data` depends on `core`.
- `core` has no Flutter UI dependency.

### 2.2 Separation of concerns
Responsibilities are intentionally partitioned:

- Engine math and deterministic transforms in `core`.
- Persistence and query composition in repositories.
- User interactions and navigation in UI layer.

State orchestration occurs through Riverpod providers that compose repositories and engines.

### 2.3 Deterministic engine isolation
Financial analysis components (`normalize`, `proforma`, `metrics`, `irr`, `analysis_engine`) are isolated in pure Dart. They accept explicit inputs and return deterministic outputs for the same inputs.

### 2.4 No hidden defaults
Global defaults are stored in `app_settings` and represented by `AppSettingsRecord`. Values are loaded, editable in settings UI, and passed explicitly into compute paths.

### 2.5 Versioning and immutability concepts
Scenario versioning stores immutable snapshot blobs:

- Version metadata in `scenario_versions`.
- Canonical JSON snapshots in `scenario_version_blobs`.
- Hash computed from canonical JSON (`sha256`) for baseline integrity.
- Rollback uses snapshot restore with a pre-rollback safety version.

### 2.6 Repository pattern
Each aggregate/domain uses dedicated repositories (for example `LedgerRepo`, `LeaseRepo`, `DocumentsRepo`). Repositories provide bounded CRUD and query operations and encapsulate SQL logic.

### 2.7 Service layer usage
Reusable domain services support repositories and workflows:

- `LedgerService` for signed amounts and period keys.
- `TaskGenerationService` for recurring task generation.
- `BackupService` and `ZipService` for archive operations.
- `AuditService` to create structured change diffs.

### 2.8 Architecture diagram

```text
UI Layer (Screens, Widgets, Shell)
  |
  v
State Layer (Riverpod Providers / Controllers)
  |
  v
Repositories (Data Access + Domain Persistence)
  |
  v
SQLite (Single local DB file + migrations)

Core Engine (pure Dart, deterministic)
  ^            ^
  |            |
  +------------+ used by state/repositories for calculation and policy logic
```

---

## 3. Folder and Module Breakdown

### 3.1 `lib/core`

#### Responsibility
Domain models, deterministic compute engines, policy logic, and export builders.

#### Must not depend on
Flutter UI framework (`flutter/material.dart`) and widget lifecycle.

#### Depended on by
`lib/data` repositories and `lib/ui` state/screen orchestration.

#### Main modules and examples
- `engine`: `AnalysisEngine`, `buildProforma`, `computeIrr`.
- `criteria`: `CriteriaEngine`.
- `offer`: `OfferSolver`.
- `reports`: `ReportBuilder`, `CsvExporter`, `PortfolioPackBuilder`.
- `finance`: `PortfolioIrrEngine`, `CovenantEngine`, `BudgetVsActual`.
- `operations`: `RentRollEngine`, `LeaseIndexationEngine`.
- `notifications`: `NotificationRules`.
- `quality`: `DataQualityService`, `DataQualityScoring`, V2 rules.
- `versioning`: `ScenarioSnapshot`, `ScenarioDiff`.
- `audit`: `AuditService`.
- `security`: `Rbac`, `PasswordHasher`.
- `services`: `BackupService`, `TaskGenerationService`, `LedgerService`, `ZipService`.
- `docs`: `DocComplianceEngine`.
- `models`: immutable record-like entities with `toMap/fromMap/copyWith`.

### 3.2 `lib/data`

#### Responsibility
Persistence infrastructure and repository implementations over SQLite.

#### Must not depend on
Flutter widgets or UI state constructs.

#### Depended on by
UI state providers/controllers and startup bootstrap.

#### Main modules
- `sqlite/db.dart`: open/close database, resolve DB path, configure FK pragma.
- `sqlite/migrations.dart`: schema creation and version upgrades to v17.
- `repositories/*`: domain persistence boundaries (properties, scenarios, inputs, ledger, rent roll, budgets, covenants, documents, tasks, quality, security, reporting, etc.).

### 3.3 `lib/ui`

#### Responsibility
Presentation layer and user interaction.

#### Must not do directly
Inline SQL logic or cross-cutting domain calculations that already exist in core/data.

#### Depends on
Riverpod providers in `ui/state`, repositories in `data`, and engines/services in `core`.

#### Main modules
- `shell`: `AppScaffold`, `Sidebar`, `TopBar`.
- `screens`: global modules and property detail modules.
- `state`: provider graph wiring DB, repositories, engines, and app navigation state.
- `widgets`: reusable UI components.
- `theme`: centralized theming and semantic color extension.
- `docs`: UI metric definitions for criteria guidance.

---

## 4. Database Architecture

### 4.1 Global design
- Single SQLite database file per local app data path.
- Schema version currently `17`.
- Additive migration strategy with idempotent creation and guarded column additions.
- Foreign key constraints enabled on connection configure.

### 4.2 Migration and versioning strategy
- `onCreate` executes migration steps V1 through V17 in order.
- `onUpgrade` executes only missing steps based on old version.
- Migrations are additive; existing data is preserved except explicit replacement flows such as restore operations.

### 4.3 Domain table map

#### Deal Analysis
- Tables: `properties`, `scenarios`, `scenario_inputs`, `income_lines`, `expense_lines`, `comps_sales`, `comps_rentals`, `criteria_sets`, `criteria_rules`, `property_criteria_overrides`, `scenario_valuation`.
- Key relationships:
  - `scenarios.property_id -> properties.id` (cascade delete).
  - `scenario_inputs.scenario_id -> scenarios.id` (1:1).
  - income/expense lines keyed by `scenario_id`.
  - property criteria override keyed by `property_id`.
- Indexing:
  - `idx_scenarios_property_id`
  - `idx_income_lines_scenario_id`
  - `idx_expense_lines_scenario_id`
- Constraints:
  - unique default set and template constraints (partial unique indexes).
  - case-insensitive unique names for criteria and templates.

#### Portfolio
- Tables: `portfolios`, `portfolio_properties`, `property_profiles`, `property_kpi_snapshots`, `notes`, `notifications`, `esg_profiles`, `import_jobs`, `import_mappings`, `capital_events`.
- Relationships:
  - many-to-many portfolio-property via composite PK in `portfolio_properties`.
  - ESG/profile rows keyed to property.
- Indexing:
  - `idx_portfolio_properties_property`
  - `idx_property_kpi_snapshots_property`
  - `idx_capital_events_asset_period`, `idx_capital_events_posted_at`
- Constraints:
  - unique portfolio name.

#### Ledger
- Tables: `ledger_accounts`, `ledger_entries`, `search_index`.
- Relationships:
  - `ledger_entries.account_id -> ledger_accounts.id` (`ON DELETE RESTRICT`).
- Indexing:
  - entity-period, account-period, posted_at indexes on `ledger_entries`.
  - search index by entity and updated time.
- Constraints:
  - unique ledger account name (case-insensitive).

#### Budgets
- Tables: `budgets`, `budget_lines`.
- Relationships:
  - `budget_lines.budget_id -> budgets.id` (cascade).
  - `budget_lines.account_id -> ledger_accounts.id` (restrict).
- Indexing:
  - `idx_budgets_entity`, `idx_budget_lines_budget`.
- Constraints:
  - unique `(entity_type, entity_id, fiscal_year, version_name)`.
  - unique `(budget_id, account_id, period_key)` line constraint.

#### Rent Roll and Leasing
- Tables: `units`, `tenants`, `leases`, `lease_rent_schedule`, `rent_roll_snapshots`, `rent_roll_lines`, `lease_indexation_rules`.
- Relationships:
  - units and leases anchored to property.
  - leases connect unit and optional tenant.
  - rent roll lines connect snapshot/unit/optional lease.
- Indexing:
  - asset-status indexes for units/leases.
  - snapshot period indexes.
  - lease indexation index.
- Constraints:
  - unique unit code per asset.
  - unique lease schedule by `(lease_id, period_key)`.
  - unique snapshot by `(asset_property_id, period_key)`.

#### Maintenance
- Table: `maintenance_tickets`.
- Relationships:
  - property required, unit optional.
- Indexing:
  - asset-status index.
  - priority-due index.

#### Covenants and Debt
- Tables: `loans`, `loan_periods`, `covenants`, `covenant_checks`.
- Relationships:
  - loans per asset.
  - periods and covenants by loan.
  - checks by covenant.
- Indexing:
  - asset and loan indexes.
- Constraints:
  - unique `(loan_id, period_key)` for loan periods.
  - unique `(covenant_id, period_key)` for covenant checks.

#### Documents and Compliance
- Tables: `document_types`, `documents`, `document_metadata`, `required_documents`.
- Relationships:
  - documents optionally typed by `document_types`.
  - metadata child rows per document.
  - required docs reference document type.
- Indexing:
  - entity and type indexes for document retrieval.
  - requirements by entity/property_type.
- Constraints:
  - unique document type name.
  - unique metadata key per document.
  - unique required doc triplet `(entity_type, property_type, type_id)`.

#### Audit and Versioning
- Tables: `audit_log`, `scenario_versions`, `scenario_version_blobs`.
- Relationships:
  - version rows map to scenario and optional parent version.
  - one blob per version (`version_id` unique).
- Indexing:
  - audit entity and timestamp indexes.
  - scenario version timeline index.

#### Tasks
- Tables: `tasks`, `task_checklist_items`, `task_templates`, `task_template_checklist_items`, `task_generated_instances`.
- Relationships:
  - checklist rows cascade by task/template.
- Indexing:
  - status/due index and entity index.
  - checklist ordering indexes.
- Constraints:
  - unique template name.
  - unique generated recurrence key.

#### Workspaces and Security Context
- Tables: `workspaces`, `local_users`, `user_sessions`.
- Relationships:
  - users and sessions scoped to workspace.
  - sessions reference both workspace and user.
- Indexing:
  - workspace-user-started index.
- Constraints:
  - unique workspace name.
  - unique display name per workspace (case-insensitive).

---

## 5. Core Engine Architecture

### 5.1 Scenario normalization
`normalizeInputs` merges scenario inputs with settings defaults and sanitizes percent values. Percent values over `1.0` are interpreted as percentages and divided by 100. Invalid negative/NaN values are replaced with explicit fallback settings values.

### 5.2 Pro forma generation
`buildProforma` computes:

- annual GSI, vacancy loss, EGI, opex, NOI
- debt service from amortization schedule
- annual cash flow before tax
- equity and loan balance trajectory
- exit cash flow in terminal year

It also returns buy closing costs, exit components, and warnings for invalid valuation inputs.

### 5.3 IRR and XIRR
- Scenario IRR: Newton-Raphson with binary-search fallback over periodic cash flows.
- Portfolio XIRR: date-based NPV derivative solver with binary fallback and signed-cashflow guard checks.

Both methods return `null` when insufficient sign variation exists.

### 5.4 Exit cap versus appreciation mode
Scenario valuation supports:

- `appreciation` mode: terminal value from appreciation growth.
- `exit_cap` mode: sale value from stabilized NOI divided by cap rate.

Stabilized NOI modes:
- year1 NOI
- manual NOI
- average over configured number of years

Invalid cap inputs trigger fallback warning and appreciation mode.

### 5.5 Deterministic cashflow aggregation
Ledger and portfolio analytics aggregate cash flows by derived period keys and sorted event ordering. Amount signs are normalized via direction and account logic before aggregation.

### 5.6 Portfolio IRR aggregation
Portfolio cashflow table combines:

- ledger entries for portfolio assets
- capital events within selected period range

The resulting dated stream is sorted and passed to `PortfolioIrrEngine`.

### 5.7 Covenant calculation
`CovenantEngine` computes DSCR and LTV where required data exists, then evaluates threshold operators (`gte`, `lte`). Missing data returns unknown (`null`) results at compute step and notes at repository level.

### 5.8 Data quality scoring engine
V2 quality evaluation maps asset facts to rule-based issues and severity deductions:

- error: -20
- warning: -10
- info: -5

Portfolio score is average asset score.

### 5.9 Why calculations are reproducible
Reproducibility is achieved because:

- Inputs are persisted and explicit.
- Engines are pure and deterministic.
- No external services or random seeds in compute paths.
- Snapshot hashing uses canonical sorted JSON serialization.

---

## 6. Operational Modules

### 6.1 Units and Leases
Data model: `units`, `tenants`, `leases`, `lease_indexation_rules`, `lease_rent_schedule`.

Core logic:
- lease CRUD and tenant assignment
- rent schedule rebuild from indexation rules and manual overrides

Persistence strategy:
- repository transactional writes for schedule rebuild
- unique constraints prevent duplicate periods

UI integration:
- property detail tabs: Units and Leases

Known limitations:
- no external CPI feed integration
- rule model is fixed to implemented fields (`annual_percent`, `fixed_step_amount`, caps/floors)

### 6.2 Rent Roll Snapshots
Data model: `rent_roll_snapshots`, `rent_roll_lines`.

Core logic:
- compute occupancy and rent metrics from units, leases, and schedule for a period
- replace snapshot for same asset/period atomically

Persistence strategy:
- transactional delete-and-reinsert for existing snapshot period

UI integration:
- property detail `Rent Roll` screen

Known limitations:
- snapshot is point-in-time by period key, no intraperiod history model

### 6.3 Lease Indexation
Data model: `lease_indexation_rules` + `lease_rent_schedule`.

Core logic:
- generate rent schedule for requested range
- preserve manual override rows when regenerating computed rows

Persistence strategy:
- generated rows replaced, manual overrides retained

UI integration:
- lease management screens and rent roll dependency

Known limitations:
- no rule conflict resolution engine beyond ordered application in current implementation

### 6.4 Ledger and Budget vs Actual
Data model: `ledger_accounts`, `ledger_entries`, `budgets`, `budget_lines`.

Core logic:
- signed amount normalization and period derivation
- budget variance calculation by account, period, and direction

Persistence strategy:
- repository-level CRUD with guard rails (for example account delete blocked when entries exist)

UI integration:
- global ledger and budgets screens
- property detail budget versus actual view

Known limitations:
- no multi-currency conversion engine; entries store currency code but no FX module

### 6.5 Maintenance Tickets
Data model: `maintenance_tickets` with optional `document_id` and `unit_id`.

Core logic:
- ticket lifecycle fields
- optional task creation at ticket creation
- due/overdue notification generation

Persistence strategy:
- ticket and optional task creation inside transaction

UI integration:
- global and property-level maintenance screens

Known limitations:
- no vendor SLA or work-order workflow states beyond current status fields

### 6.6 Task Templates and Recurring Tasks
Data model: task tables plus generated instance dedupe key.

Core logic:
- recurrence rules: daily, weekly, monthly, quarterly, yearly
- generated key prevents duplicate periodic generation
- optional due-soon and overdue notifications

Persistence strategy:
- generated instance logging and checklist cloning per created task

UI integration:
- Tasks and Task Templates screens
- startup and periodic generation triggers

Known limitations:
- recurrence scheduling based on application run cadence; no background OS scheduler service

### 6.7 Covenant Monitoring
Data model: loans, loan periods, covenants, covenant checks, notifications.

Core logic:
- DSCR/LTV checks across period ranges
- breach notification creation with dedupe check

Persistence strategy:
- check rows inserted or replaced per `(covenant_id, period_key)`

UI integration:
- property detail covenants screen

Known limitations:
- covenant kinds currently hardcoded to DSCR and LTV compute paths

### 6.8 Document Compliance
Data model: document types, required docs, documents, metadata.

Core logic:
- required-document presence checks
- expiry metadata checks with parse validation

Persistence strategy:
- document + metadata write in transaction
- unique metadata key per document

UI integration:
- documents screen and compliance dashboard

Known limitations:
- compliance depends on structured metadata values; no OCR/semantic extraction pipeline

---

## 7. Governance and Compliance

### 7.1 Scenario versioning
Scenario snapshots store canonical JSON with hash baseline. Diff generation compares flattened canonical maps and groups changes by section labels.

### 7.2 Audit log model
`audit_log` captures entity/action/user/time/source and optional structured diffs (`diff_json`). Many repositories write create/update/delete audit events.

### 7.3 Rollback safety
Rollback operation creates a safety version before restoring target snapshot content into scenario inputs/income/expense/valuation rows.

### 7.4 RBAC enforcement
Role model:
- `admin`: all actions
- `analyst`: create/update/import/export
- `viewer`: export only

Current enforcement is primarily UI-gated and permission-guard based where wired (for example settings and scenario operations).

### 7.5 Workspace isolation
Security context tracks active workspace and active user in `app_settings`, with local users and sessions scoped by workspace IDs.

### 7.6 Backup and restore
Backup:
- zips DB + docs + manifest
- stores DB SHA-256 in manifest

Restore:
- validates schema compatibility (backup schema must not be newer)
- creates automatic pre-restore backup
- imports common columns table-by-table from extracted DB
- restores docs folder

### 7.7 Data quality scoring
Portfolio quality evaluation uses repository snapshots and rules engine to generate module-severity issues and aggregate score.

### 7.8 Document requirement enforcement
Required document policies are entity/property-type aware and enforced through compliance checks over uploaded documents plus metadata expiry keys.

---

## 8. Reporting System

### 8.1 Template system
Report templates define section flags and metadata fields:

- include overview, inputs, cashflow, amortization, sensitivity, ESG, comps, criteria, offer
- title/disclaimer/investor fields
- default template selection with single-default enforcement

### 8.2 PDF generation flow
`ReportBuilder.savePdf` constructs a multi-page PDF from report DTO and template flags using the Dart `pdf` library, then writes to selected local output path.

### 8.3 CSV exports
CSV export functions include cashflow, amortization, portfolio cashflow tables, and multiple module-specific export paths in screens.

### 8.4 Portfolio reporting pack
Reporting pack generation composes files by section switches and bundles them into ZIP output via `ZipService`.

### 8.5 Manifest strategy
`PortfolioPackBuilder` produces `meta/manifest.json` including:

- app and schema version
- selected sections
- period range
- portfolio identity
- file list
- optional SHA-256 checksums per included artifact

### 8.6 Deterministic output guarantees
Generated file lists are sorted by relative path before manifest generation, reducing non-determinism in metadata ordering for equivalent inputs.

---

## 9. Security Model

### 9.1 Offline trust model
All data processing is local. Security boundaries are local workspace/user context and role checks.

### 9.2 Workspace separation
Workspaces and local users are first-class tables, with active context maintained in settings and switchable from UI topbar.

### 9.3 App lock
Optional app lock is implemented:

- PBKDF2-HMAC-SHA256 password hashing
- random salt generation
- constant-time hash compare
- lock screen gate before entering shell when enabled

### 9.4 Encryption status
Database-at-rest encryption is not implemented in current codebase.

### 9.5 Backup integrity checks
Backup manifest stores DB SHA-256 and metadata. Current restore flow validates schema version compatibility and structure, but does not enforce a mandatory hash verification gate before import.

---

## 10. Testing Strategy

### 10.1 Unit tests
Core engines and services are unit-tested, including:

- analysis/irr/sensitivity
- offer solver
- criteria engine
- operations engines
- covenant and portfolio IRR engines
- document compliance and quality scoring
- security hashing and RBAC

### 10.2 Repository tests
Data repositories are tested across domains:

- inputs, scenarios, portfolio, lease, rent roll, ledger, budget
- covenants, documents, imports, tasks, search, security
- scenario valuation/version repositories and audit

### 10.3 Widget tests
UI widgets and screens have targeted coverage, including ledger UI, theme behavior, portfolio analytics views, documents, tasks, security gate, and property detail screens.

### 10.4 Integration tests
Integration suite includes app-flow and backup/restore scenarios.

### 10.5 Deterministic numeric validation
IRR and financial engines are tested for expected outputs and convergence behaviors on deterministic input sets.

### 10.6 Migration safety testing
Migration tests validate schema creation and expected columns, including latest settings/UI/security additions.

---

## 11. Extension Guidelines

### 11.1 Add a new table
1. Add a new `DbMigrations._createV<N>` step with `CREATE TABLE IF NOT EXISTS`.
2. Add required indexes and unique constraints in same migration step.
3. Wire the migration into both `onCreate` and `onUpgrade`.
4. Use `ALTER TABLE ADD COLUMN` with `_addColumnIfMissing` for additive changes.
5. Add migration tests validating table and columns.

### 11.2 Add a new repository
1. Create repository under `lib/data/repositories`.
2. Keep SQL and persistence logic inside repository only.
3. Expose typed models, not raw maps, at repository boundary.
4. Register provider in `ui/state/app_state.dart`.
5. Add repository unit tests for CRUD and failure cases.

### 11.3 Extend core engine safely
1. Implement logic in `lib/core` pure Dart module.
2. Accept explicit inputs and avoid global mutable state.
3. Return structured immutable outputs.
4. Add deterministic unit tests (including edge inputs and invalid data handling).
5. Keep UI and repository concerns out of engine code.

### 11.4 Add new report sections
1. Extend report template model flags and migration columns if needed.
2. Map template flag to `ReportBuilder` rendering branch.
3. Update DTO composition path in report screen/repository flow.
4. Add tests for template serialization and rendering path activation.

### 11.5 Add new compliance rules
1. Add rule definition in `DataQualityRulesV2` or document requirement repositories.
2. Implement evaluation logic in quality/compliance engine.
3. Add related route/fix hint metadata for UI actionability.
4. Add tests for triggered and non-triggered conditions.

### 11.6 Avoid breaking determinism
1. Do not depend on unordered map iteration for hashes/diffs.
2. Sort collections before canonical serialization where order matters.
3. Avoid random or time-based values inside compute functions unless passed as explicit input.
4. Keep period key derivation standardized and centralized.

### 11.7 Maintain layering integrity
1. Do not import Flutter UI into `core` or `data`.
2. Do not place SQL in UI screens.
3. Keep side effects in repositories/services, not in pure engine functions.
4. Keep RBAC checks at orchestration boundaries and add repository-level guards where required for stricter enforcement.

---

## Appendix: Current Schema Version and Core Guarantees

- Current schema version: `17`.
- FK enforcement: enabled on database configure.
- Startup bootstraps default workspace/user context if absent.
- All major business functions run without external web connectivity.
